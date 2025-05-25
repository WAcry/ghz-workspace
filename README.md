# ghz Interactive for gRPC load testing

An interactive CLI wrapper around [ghz](https://github.com/bojand/ghz)

that makes it easy to define endpoints, manage history, choose descriptor modes,
feed YAML-based test data, and generate HTML reports.

Built with Go 1.22, Zap logging + Lumberjack rotation, and supports plain or TLS (skip‐verify) connections.

---

## Features

- **Interactive prompts** for creating or selecting endpoints
- **LRU history** of previously used endpoints (`history.json`)
- **Four descriptor modes**:
    - `proto` — supply a `.proto` file + import paths
    - `protoset` — supply a compiled descriptor set (`.protoset`)
    - `reflect` — use gRPC Server Reflection
    - `reflect_meta` — reflection with custom metadata
- **Security modes**:
    - `plain` — h2c (insecure, no TLS)
    - `tls-skip` — TLS but skip certificate validation
- **Test data**:
    - Read request payloads from `data/*.yaml` → convert to JSON
    - Read per-request metadata from `metadata/*.yaml`
    - Loop through data files automatically
- **High-performance runner** using [`github.com/bojand/ghz/runner`](https://github.com/bojand/ghz)
- **Concurrency**: defaults to #CPU cores
- **Zap + Lumberjack** for structured JSON logging and log rotation (in `logs/`)
- **HTML report** generation (in `reports/`)
- Portable: single `main.go` with no external scripts

---

## Prerequisites

- Go 1.22 or later
- `ghz` Runner dependencies are vendored via Go modules:

```bash
go mod tidy
```

## Usage

Run the `main.go` file to start the interactive CLI:

1. **Select or create an endpoint**

    * Choose `<new endpoint>` to define a new target, or pick one from history.
2. **Endpoint configuration**

    * **Name**: a friendly label (e.g. `my-service-tls`)
    * **Host**: gRPC target (e.g. `hostname:443`)
    * **Security**: `plain` (h2c) or `tls-skip` (TLS, skip verification)
    * **Descriptor mode**: one of `proto`, `protoset`, `reflect`, `reflect_meta`

        * If `proto`, provide path to your `.proto` file and any import paths.
        * If `protoset`, provide path to your compiled `.protoset` file.
        * If using reflection, metadata key-values can be supplied (and sometimes required).
3. **Method discovery**

    * Automatically lists available RPC methods (from proto, protoset, or reflection).
4. **Benchmark parameters**

    * **Duration** (e.g. `30s`, `2m`)
    * **QPS** (0 = unlimited)
    * **Test data root** (defaults to `./example`, contains `data/` + `metadata/`)
5. **Run & Report**

    * Runs the benchmark
    * Logs to `logs/YYYYMMDD-HHMMSS.log` (rotated)
    * Saves an HTML report to `reports/YYYYMMDD-HHMMSS.html`

## Test Data Format

Place your test data under a root directory (e.g. `example/`):

```
example/
├── data/
│   ├── req1.yaml     # YAML representing the JSON request payload
│   └── req2.yaml
└── metadata/
    ├── md1.yaml      # Optional metadata (key: value)
    └── md2.yaml
```

* Data files are converted from YAML → JSON and cycled per request.
* Metadata files are parsed into gRPC metadata and cycled in parallel.
* Usually the files in `data` should match the amount of metadata files in `metadata`.

---

## Logs & Reports

* **Logs**: `logs/YYYYMMDD-HHMMSS.log` (JSON, rotated by Lumberjack and compressed if large)
* **Reports**: `reports/YYYYMMDD-HHMMSS.html` (detailed HTML with latency, throughput, errors)

---

## Example

Using the included `Protos/greet.proto`:

```proto
syntax = "proto3";
package hello;

service HelloService {
  rpc SayHello(HelloRequest) returns (HelloResponse);
}

message HelloRequest {
  string greeting = 1;
}
message HelloResponse {
  string reply = 1;
}
```

And a sample history entry (`history.json`):

```json
[
  {
    "name": "grpcb.in (tls)",
    "host": "grpcb.in:443",
    "mode": "proto",
    "security": "tls-skip",
    "proto": "Protos/greet.proto",
    "last_used": "2025-05-25T06:07:06-07:00"
  }
]
```

You can select this endpoint, pick `hello.HelloService/SayHello`, and run a quick 30-second test against `grpcb.in:443`.

---

## History Persistence

* Endpoints are saved in `history.json` with a timestamp (`last_used`).
* On startup, history is sorted by most recent use (LRU).
* New or updated endpoints are upserted automatically.

---

## License

This project is open-source under the MIT License. Feel free to use and adapt!
