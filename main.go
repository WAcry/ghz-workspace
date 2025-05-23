// main.go
//
// Interactive ghz wrapper with explicit security mode (plain / tls),
// endpoint history, 4 descriptor modes, YAML→JSON test data,
// zap + lumberjack logging, HTML report.
//
// Go 1.22

package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"google.golang.org/grpc/credentials/insecure"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/bojand/ghz/printer"
	"github.com/bojand/ghz/runner"
	"github.com/jhump/protoreflect/desc"
	"github.com/jhump/protoreflect/desc/protoparse"
	"github.com/jhump/protoreflect/dynamic"
	"github.com/jhump/protoreflect/grpcreflect"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"
	reflectionpb "google.golang.org/grpc/reflection/grpc_reflection_v1alpha"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/descriptorpb"
	"gopkg.in/natefinch/lumberjack.v2"
	"gopkg.in/yaml.v3"
)

/* ──────────────────────────────── Constants & Basic Types ──────────────────────────────── */

const (
	historyRelPath = "history.json"

	logDir    = "logs"
	reportDir = "reports"

	// Default values for interaction
	defDuration = "30s"
	defDataDir  = "./example"
	defQPS      = "0"

	// Connection security modes
	SecPlain   = "plain"    // h2c plaintext
	SecTLSSkip = "tls-skip" // TLS but skip certificate verification

	// Descriptor source modes
	ModeProto       = "proto"
	ModeProtoset    = "protoset"
	ModeReflect     = "reflect"
	ModeReflectMeta = "reflect_meta"
)

// Endpoint stores a reusable target configuration
type Endpoint struct {
	Name            string            `json:"name"`
	Host            string            `json:"host"`
	Mode            string            `json:"mode"`     // proto | protoset | reflect | reflect_meta
	Security        string            `json:"security"` // plain | tls-skip
	Proto           string            `json:"proto,omitempty"`
	ProtoPaths      []string          `json:"proto_paths,omitempty"`
	Protoset        string            `json:"protoset,omitempty"`
	ReflectionMeta  map[string]string `json:"reflection_meta,omitempty"`
	LastUsedRFC3339 string            `json:"last_used"`
}

// History implements a simple endpoint LRU
type History []Endpoint

/* ──────────────────────────────── Persistence ──────────────────────────────── */
func loadHistory() History {
	b, err := os.ReadFile(historyRelPath)
	if err != nil {
		return nil
	}
	var h History
	_ = json.Unmarshal(b, &h)
	return h
}
func (h History) save() {
	_ = os.MkdirAll(filepath.Dir(historyRelPath), 0700)
	_ = os.WriteFile(historyRelPath, mustJSONIndent(h), 0o644)
}
func (h History) mostRecent() History {
	sort.Slice(h, func(i, j int) bool { return h[i].LastUsedRFC3339 > h[j].LastUsedRFC3339 })
	return h
}
func (h *History) upsert(ep Endpoint) {
	for i := range *h {
		if (*h)[i].Name == ep.Name {
			(*h)[i] = ep
			return
		}
	}
	*h = append(*h, ep)
}

/* ──────────────────────────────── Interactive Tools ──────────────────────────────── */

var (
	rdr   = bufio.NewReader(os.Stdin)
	sepLn = strings.Repeat("-", 60)
)

func prompt(label, def string, req bool) string {
	for {
		if def != "" {
			fmt.Printf("%s [%s]: ", label, def)
		} else {
			fmt.Printf("%s: ", label)
		}
		t, _ := rdr.ReadString('\n')
		t = strings.TrimSpace(t)
		if t == "" {
			t = def
		}
		if req && t == "" {
			fmt.Println("Required, please enter again")
			continue
		}
		return t
	}
}

func choose(label string, items []string, def int) int {
	for i, it := range items {
		fmt.Printf("  %d. %s\n", i, it)
	}
	for {
		idxStr := prompt(label, strconv.Itoa(def), true)
		idx, _ := strconv.Atoi(idxStr)
		if idx >= 0 && idx < len(items) {
			return idx
		}
		fmt.Println("Invalid selection, please enter again")
	}
}

/* ──────────────────────────────── Logging ──────────────────────────────── */

func newLogger() (*zap.SugaredLogger, func()) {
	_ = os.MkdirAll(logDir, 0o755)
	f := &lumberjack.Logger{
		Filename:   filepath.Join(logDir, time.Now().Format("20060102-150405")+".log"),
		MaxSize:    50, // MB
		MaxBackups: 20,
		Compress:   true,
	}
	core := zapcore.NewCore(
		zapcore.NewJSONEncoder(zap.NewProductionEncoderConfig()),
		zapcore.AddSync(f),
		zap.DebugLevel,
	)
	lg := zap.New(core).Sugar()
	return lg, func() { _ = lg.Sync(); _ = f.Close() }
}

/* ──────────────────────────────── Descriptor Discovery ──────────────────────────────── */

func methodsFromProto(file string, paths []string) ([]string, error) {
	pp := protoparse.Parser{ImportPaths: append(paths, filepath.Dir(file))}
	fds, err := pp.ParseFiles(filepath.Base(file))
	if err != nil {
		return nil, err
	}
	return listMethods(fds), nil
}

func methodsFromProtoset(pset string) ([]string, error) {
	raw := mustRead(pset)
	var fset descriptorpb.FileDescriptorSet
	if json.Unmarshal(raw, &fset) != nil { // Try parsing binary format
		if err := proto.Unmarshal(raw, &fset); err != nil {
			return nil, fmt.Errorf("decode protoset: %w", err)
		}
	}
	fdMap, err := desc.CreateFileDescriptorsFromSet(&fset)
	if err != nil {
		return nil, err
	}
	var fds []*desc.FileDescriptor
	for _, v := range fdMap {
		fds = append(fds, v)
	}
	return listMethods(fds), nil
}

func methodsViaReflection(host, sec string, md metadata.MD) ([]string, error) {
	conn, err := smartDial(host, sec)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	if len(md) > 0 {
		ctx = metadata.NewOutgoingContext(ctx, md)
	}
	rc := grpcreflect.NewClientV1Alpha(ctx, reflectionpb.NewServerReflectionClient(conn))
	defer rc.Reset()

	svcs, err := rc.ListServices()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, svc := range svcs {
		if svc == "grpc.reflection.v1alpha.ServerReflection" {
			continue
		}
		fd, _ := rc.FileContainingSymbol(svc)
		if fd == nil {
			continue
		}
		sd := fd.FindService(svc)
		if sd == nil {
			continue
		}
		for _, m := range sd.GetMethods() {
			out = append(out, fmt.Sprintf("%s/%s", svc, m.GetName()))
		}
	}
	sort.Strings(out)
	return out, nil
}

func listMethods(fds []*desc.FileDescriptor) []string {
	var res []string
	for _, fd := range fds {
		for _, svc := range fd.GetServices() {
			for _, m := range svc.GetMethods() {
				res = append(res, fmt.Sprintf("%s/%s", svc.GetFullyQualifiedName(), m.GetName()))
			}
		}
	}
	sort.Strings(res)
	return res
}

/* ──────────────────────────────── gRPC Connection ──────────────────────────────── */

func smartDial(target, sec string, extra ...grpc.DialOption) (*grpc.ClientConn, error) {
	target = strings.TrimPrefix(target, "http://")
	target = strings.TrimPrefix(target, "https://")
	target = strings.TrimPrefix(target, "grpc://")

	base := []grpc.DialOption{
		grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(64 << 20)),
	}
	base = append(base, extra...)

	switch sec {
	case SecPlain:
		base = append(base, grpc.WithTransportCredentials(insecure.NewCredentials()))
	case SecTLSSkip:
		base = append(base, grpc.WithTransportCredentials(
			credentials.NewTLS(&tls.Config{InsecureSkipVerify: true}),
		))
	default:
		return nil, fmt.Errorf("unknown security mode %s", sec)
	}

	return grpc.NewClient(target, base...) // ← New API
}

/* ──────────────────────────────── YAML → JSON ──────────────────────────────── */

func parseRequestDir(dir string) ([][]byte, []metadata.MD, error) {
	dataDir := filepath.Join(dir, "data")
	metaDir := filepath.Join(dir, "metadata")

	dataFiles, _ := filepath.Glob(filepath.Join(dataDir, "*.y*ml"))
	if len(dataFiles) == 0 {
		return nil, nil, fmt.Errorf("no yaml in %s", dataDir)
	}
	sort.Strings(dataFiles)

	metaFiles, _ := filepath.Glob(filepath.Join(metaDir, "*.y*ml"))
	sort.Strings(metaFiles)

	var (
		blobs [][]byte
		mds   []metadata.MD
	)
	for i, df := range dataFiles {
		var v interface{}
		mustErr(yaml.Unmarshal(mustRead(df), &v))
		blobs = append(blobs, mustJSON(v))

		var md metadata.MD
		if i < len(metaFiles) {
			var mv map[string]interface{}
			mustErr(yaml.Unmarshal(mustRead(metaFiles[i]), &mv))
			tmp := make(map[string]string)
			for k, vv := range mv {
				tmp[k] = fmt.Sprint(vv)
			}
			md = metadata.New(tmp)
		}
		mds = append(mds, md)
	}
	return blobs, mds, nil
}

/* ──────────────────────────────── ghz Adapter Layer ──────────────────────────────── */

// JSON → wire-format
func binFunc(blobs [][]byte) runner.BinaryDataFunc {
	if len(blobs) == 0 {
		return nil
	}
	return func(mtd *desc.MethodDescriptor, cd *runner.CallData) []byte {
		idx := int(cd.RequestNumber) % len(blobs)
		if len(blobs[idx]) == 0 {
			return nil
		}
		// ① JSON → Dynamic Message
		msg := dynamic.NewMessage(mtd.GetInputType())
		if err := msg.UnmarshalJSON(blobs[idx]); err != nil {
			fmt.Fprintf(os.Stderr, "unmarshal JSON: %v\n", err)
			return nil
		}
		// ② Message → wire-format
		bin, err := msg.Marshal()
		if err != nil {
			fmt.Fprintf(os.Stderr, "marshal proto: %v\n", err)
			return nil
		}
		return bin
	}
}

// Metadata corresponds to request numbers, also used cyclically
func mdFunc(mds []metadata.MD) runner.MetadataProviderFunc {
	if len(mds) == 0 {
		return nil
	}
	return func(cd *runner.CallData) (*metadata.MD, error) {
		md := mds[int(cd.RequestNumber)%len(mds)]
		if len(md) == 0 {
			return nil, nil
		}
		return &md, nil
	}
}

func buildRunnerOpts(ep Endpoint, blobs [][]byte, mds []metadata.MD, lg *zap.SugaredLogger) ([]runner.Option, error) {
	opts := []runner.Option{
		runner.WithLogger(lg),
		runner.WithConcurrency(uint(runtime.NumCPU())),
		runner.WithBinaryDataFunc(binFunc(blobs)),
		runner.WithMetadataProvider(mdFunc(mds)),
	}
	// Connection security
	switch ep.Security {
	case SecPlain:
		opts = append(opts, runner.WithInsecure(true))
	case SecTLSSkip:
		opts = append(opts, runner.WithSkipTLSVerify(true))
	default:
		return nil, fmt.Errorf("unknown security mode %s", ep.Security)
	}
	// Descriptor source
	switch ep.Mode {
	case ModeProto:
		opts = append(opts, runner.WithProtoFile(ep.Proto, ep.ProtoPaths))
	case ModeProtoset:
		opts = append(opts, runner.WithProtoset(ep.Protoset))
	case ModeReflect:
		// nothing
	case ModeReflectMeta:
		opts = append(opts, runner.WithReflectionMetadata(ep.ReflectionMeta))
	default:
		return nil, fmt.Errorf("unknown mode %s", ep.Mode)
	}
	return opts, nil
}

/* ──────────────────────────────── Main Flow ──────────────────────────────── */

func main() {
	// Logging
	lg, flush := newLogger()
	defer flush()

	// Endpoint history
	his := loadHistory().mostRecent()

	/* --- Select / Create Endpoint --- */
	items := append([]string{"<New Endpoint>"}, func() (xs []string) {
		for _, ep := range his {
			xs = append(xs, fmt.Sprintf("%s (%s, %s)", ep.Name, ep.Host, ep.Security))
		}
		return
	}()...)
	idx := choose("Select endpoint", items, 0)

	var ep Endpoint
	if idx == 0 {
		ep = createEndpointInteractive()
	} else {
		ep = his[idx-1]
		fmt.Printf("✔  Using history endpoint %s (%s, %s)\n", ep.Name, ep.Host, ep.Security)
	}
	ep.LastUsedRFC3339 = time.Now().Format(time.RFC3339)
	his.upsert(ep)
	his.save()

	/* --- Discover Available Methods --- */
	var (
		methods []string
		err     error
	)
	switch ep.Mode {
	case ModeProto:
		methods, err = methodsFromProto(ep.Proto, ep.ProtoPaths)
	case ModeProtoset:
		methods, err = methodsFromProtoset(ep.Protoset)
	case ModeReflect:
		methods, err = methodsViaReflection(ep.Host, ep.Security, nil)
	case ModeReflectMeta:
		methods, err = methodsViaReflection(ep.Host, ep.Security, metadata.New(ep.ReflectionMeta))
	}
	mustErr(err)
	if len(methods) == 0 {
		exit("no methods discovered")
	}
	call := methods[choose("Select method", methods, 0)]

	/* --- Benchmark Parameters --- */
	dur := mustParseDuration(prompt("Duration (e.g. 45s, 2m)", defDuration, true))
	qps := uint(mustAtoi(prompt("QPS (0 = unlimited)", defQPS, false)))
	dataRoot := prompt("Request data root directory", defDataDir, true)

	blobs, mds, err := parseRequestDir(dataRoot)
	mustErr(err)

	opts, err := buildRunnerOpts(ep, blobs, mds, lg)
	mustErr(err)
	opts = append(opts,
		runner.WithRunDuration(dur),
		runner.WithDurationStopAction("wait"),
		runner.WithRPS(qps),
	)

	/* --- Run! --- */
	fmt.Println(sepLn)
	fmt.Printf("Start benchmarking: %s  @ %s, duration=%s, qps=%d\n", call, ep.Host, dur, qps)
	fmt.Println(sepLn)

	report, err := runner.Run(call, ep.Host, opts...)
	mustErr(err)

	_ = os.MkdirAll(reportDir, 0o755)
	repPath := filepath.Join(reportDir, time.Now().Format("20060102-150405")+".html")
	f, err := os.Create(repPath)
	mustErr(err)
	defer f.Close()

	mustErr((&printer.ReportPrinter{Report: report, Out: f}).Print("html"))
	fmt.Printf("✅ Benchmark completed, report saved to %s\n", repPath)
}

/* ──────────────────────────────── Endpoint Interaction ──────────────────────────────── */

func createEndpointInteractive() Endpoint {
	ep := Endpoint{}
	ep.Name = prompt("Endpoint name", time.Now().Format("srv-150405"), true)
	ep.Host = strings.TrimPrefix(prompt("gRPC server (host:port)", "", true), "http://")
	ep.Host = strings.TrimPrefix(ep.Host, "https://")
	ep.Host = strings.TrimPrefix(ep.Host, "grpc://")

	// Connection security
	secIdx := choose("Select connection security mode", []string{
		"plain        (h2c plaintext, no TLS)",
		"tls-skip     (TLS, but skip certificate verification)",
	}, 0)
	ep.Security = map[int]string{0: SecPlain, 1: SecTLSSkip}[secIdx]

	// Descriptor source
	modeIdx := choose("Select descriptor source", []string{
		"proto            (main proto + import paths)",
		"protoset         (descriptor set file)",
		"reflect          (Server Reflection)",
		"reflect + meta   (Reflection with metadata)",
	}, 2)

	switch modeIdx {
	case 0:
		ep.Mode = ModeProto
		ep.Proto = prompt("Main proto file path", "", true)
		if p := prompt("Extra import paths (comma separated, optional)", "", false); p != "" {
			ep.ProtoPaths = splitTrim(p, ",")
		}
	case 1:
		ep.Mode = ModeProtoset
		ep.Protoset = prompt("protoset file path", "", true)
	case 2:
		ep.Mode = ModeReflect
	case 3:
		ep.Mode = ModeReflectMeta
		ep.ReflectionMeta = mustKV(prompt("metadata (key:value[,k2:v2])", "", true))
	}
	return ep
}

/* ──────────────────────────────── Utility Functions ──────────────────────────────── */

func mustErr(err error) {
	if err != nil {
		exit(err.Error())
	}
}
func mustRead(p string) []byte    { b, err := os.ReadFile(p); mustErr(err); return b }
func mustJSONIndent(v any) []byte { b, _ := json.MarshalIndent(v, "", "  "); return b }
func mustJSON(v any) []byte       { b, _ := json.Marshal(v); return b }
func mustAtoi(s string) int       { i, _ := strconv.Atoi(s); return i }
func mustParseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	mustErr(err)
	return d
}
func exit(msg string) { fmt.Fprintln(os.Stderr, "❌", msg); os.Exit(1) }
func splitTrim(s, sep string) []string {
	var out []string
	for _, p := range strings.Split(s, sep) {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
func mustKV(s string) map[string]string {
	m := map[string]string{}
	for _, kv := range splitTrim(s, ",") {
		p := strings.SplitN(kv, ":", 2)
		if len(p) != 2 {
			exit("invalid kv: " + kv)
		}
		m[strings.TrimSpace(p[0])] = strings.TrimSpace(p[1])
	}
	return m
}
