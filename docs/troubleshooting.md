# ghz 故障排除指南

在使用 ghz 进行 gRPC 性能测试时，可能会遇到各种问题。以下是一些常见问题及其解决方案。

## 连接问题

### 无法连接到服务器

**症状**：出现类似 `rpc error: code = Unavailable desc = connection error` 的错误。

**可能的原因与解决方案**：

1. **服务器未运行**：确认目标 gRPC 服务正在运行且端口正确。
   ```powershell
   # 检查端口是否在监听
   netstat -an | findstr "50051"
   ```

2. **防火墙阻止**：检查防火墙设置，确保允许该端口的访问。
   ```powershell
   # 临时关闭 Windows 防火墙进行测试
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   ```

3. **使用了TLS但未指定**：如果服务需要 TLS 连接但您使用了 `--insecure`，则连接会失败。移除 `--insecure` 参数。

4. **使用了自签名证书**：如果服务使用自签名证书，需要指定 `--skipTLS` 或提供正确的证书。
   ```powershell
   ghz --skipTLS --proto ... localhost:50051
   # 或
   ghz --cacert ./server-ca.crt --proto ... localhost:50051
   ```

### TLS握手失败

**症状**：出现 `rpc error: code = Unavailable desc = transport: authentication handshake failed` 错误。

**解决方案**：
- 确认是否需要使用 TLS。如服务使用明文 (非TLS) 连接，需添加 `--insecure` 参数。
- 如果服务需要 TLS，检查证书是否正确，或使用 `--skipTLS` 跳过证书验证。

## Proto 文件相关问题

### 无法找到 Proto 文件

**症状**：出现 `open helloworld.proto: The system cannot find the file specified.` 错误。

**解决方案**：
- 确保 proto 文件路径正确。使用相对路径时，注意当前工作目录。
- 考虑使用绝对路径指定 proto 文件：`--proto C:\path\to\proto\file.proto`

### Proto 导入错误

**症状**：出现 `example.proto:5:3: a.proto: File not found.` 类似错误。

**解决方案**：
- 使用 `--import-paths` 参数指定导入路径：
  ```powershell
  ghz --proto example.proto --import-paths "C:\protos,C:\another\path" ...
  ```
- 或者使用 protoset 文件代替多个相互依赖的 proto 文件：
  ```powershell
  # 先生成 protoset
  protoc --include_imports -I . --descriptor_set_out=bundle.protoset *.proto
  
  # 然后使用 protoset
  ghz --protoset bundle.protoset ...
  ```

### 找不到服务或方法

**症状**：出现 `service "helloworld.Greeter" not found in proto descriptor` 错误。

**解决方案**：
- 确认 proto 文件中服务名和方法名的拼写与使用的 `--call` 参数中完全一致（包括大小写）。
- 确认包名是否正确：`package helloworld;` 对应于 `--call helloworld.Greeter.SayHello`。
- 使用 `--call` 参数的正确格式：`包名.服务名.方法名`

## 数据和请求格式问题

### JSON 解析错误

**症状**：出现 `failed to marshal request: invalid character...` 错误。

**解决方案**：
- 检查 JSON 格式是否有效。特别注意引号嵌套问题。
- 在 Windows PowerShell 中，可能需要对引号进行转义：
  ```powershell
  ghz -d '{\"name\":\"测试\"}' ...
  # 或使用单引号包裹 JSON
  ghz -d '{"name":"测试"}' ...
  ```
- 考虑使用 `-D` 参数从文件读取 JSON，避免命令行转义问题：
  ```powershell
  ghz -D request.json ...
  ```

### 流式请求格式错误

**症状**：流式调用时出现错误，或请求无响应。

**解决方案**：
- 确保流式方法使用正确的数据格式：对于客户端流或双向流，应使用 JSON 数组：
  ```powershell
  ghz -d '[{"name":"消息1"},{"name":"消息2"}]' ...
  ```
- 检查 `--stream-call-count` 设置是否与数组长度匹配。
- 对于服务端流，确保只发送一个请求消息，而不是数组。

## 性能和结果问题

### 吞吐量 (QPS) 不如预期

**症状**：测试结果中的 Requests/sec 值远低于预期。

**解决方案**：
- 增加 `-c` (并发数) 参数，尝试不同的并发值找到最佳设置。
- 检查客户端机器资源是否成为瓶颈（CPU、内存、网络）：
  ```powershell
  # 在测试过程中监控 CPU 使用率
  Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 60
  ```
- 使用 `--connections` 参数增加连接数，减少单一 TCP 连接的限制。
- 检查是否有大量错误响应，影响了有效吞吐量。

### 延迟异常高

**症状**：测试结果中延迟值异常高。

**解决方案**：
- 使用 `--skipFirst N` 跳过前 N 个请求的统计，避免预热阶段影响。
- 检查网络延迟，尤其是测试远程服务时：
  ```powershell
  ping -n 100 target.server.com
  ```
- 检查是否有异常值极大地影响了平均延迟，关注 p50（中位数）和 p99 等分位数值。
- 尝试降低并发数和 RPS，查看是否为服务端过载导致。

## 系统和环境问题

### 权限不足

**症状**：在某些操作中出现权限相关错误。

**解决方案**：
- 以管理员身份运行 PowerShell：右键点击 PowerShell 图标，选择"以管理员身份运行"。
- 检查是否需要访问受限制的系统资源，如特定目录或端口。

### 环境变量和路径问题

**症状**：`ghz: command not found` 或类似错误。

**解决方案**：
- 确认是否正确设置 PATH 环境变量。执行以下命令检查：
  ```powershell
  $env:Path -split ";" | Where-Object { $_ -like "*ghz*" }
  ```
- 考虑使用绝对路径运行命令：
  ```powershell
  C:\Users\username\ghz\bin\ghz.exe ...
  ```
- 重新启动终端或系统，使环境变量更改生效。

## 其他常见错误

### DEADLINE_EXCEEDED 错误

**症状**：大量请求返回 `[DEADLINE_EXCEEDED]` 状态码。

**解决方案**：
- 增加请求超时时间：
  ```powershell
  ghz -t 10s ... # 设置10秒超时
  ```
- 检查服务处理时间是否过长，可能需要优化服务性能。

### 资源耗尽

**症状**：测试进行一段时间后崩溃或性能急剧下降。

**解决方案**：
- 降低并发数或 RPS。
- 检查系统资源使用情况，尤其是内存和文件描述符：
  ```powershell
  # 查看内存使用
  Get-Process | Where-Object { $_.ProcessName -eq "ghz" }
  ```
- 分批进行测试，而不是一次执行大规模测试。

## 获取更多帮助

如果以上方法无法解决您的问题，可以：

1. 查看 ghz 完整文档：https://ghz.sh/docs/intro
2. 访问 ghz GitHub 仓库：https://github.com/bojand/ghz
3. 提交 issue 报告问题：https://github.com/bojand/ghz/issues 