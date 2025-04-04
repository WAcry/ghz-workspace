# ghz - gRPC性能测试工具

本工作空间包含在Windows上使用ghz工具对gRPC服务进行性能测试的相关文件和脚本。

## 目录结构

- `scripts/`: 包含所有PowerShell脚本
  - `install-ghz.ps1`: 安装脚本，用于下载和安装ghz工具
  - `run-ghz-tests.ps1`: 常用测试场景示例脚本
  - `advanced-examples.ps1`: 高级用法示例脚本
- `proto/`: 包含Proto定义文件
  - `example.proto`: 示例Proto文件，定义了用于测试的gRPC服务和消息
- `config/`: 包含配置文件
  - `ghz-config-example.json`: ghz配置文件示例
- `data/`: 包含测试数据文件
  - `request-unary.json`: 单次调用请求数据示例
  - `request-stream.json`: 流式调用请求数据示例
- `docs/`: 包含文档文件
  - `troubleshooting.md`: 故障排除指南
- `reports/`: 测试报告保存目录，运行测试后会自动创建

## 快速开始

1. 首先安装ghz工具：
   ```powershell
   .\scripts\install-ghz.ps1
   ```

2. 按照提示重启PowerShell终端使环境变量生效

3. 确保您有可用的gRPC服务运行在localhost:50051（或修改脚本中的targetHost变量）

4. 运行测试脚本：
   ```powershell
   .\scripts\run-ghz-tests.ps1
   ```

5. 在菜单中选择要执行的测试类型

## 测试类型说明

- **普通单次调用测试**：对标准单向RPC方法进行测试
- **流式调用测试**：包括服务端流、客户端流和双向流的测试
- **固定RPS负载测试**：以固定的每秒请求数进行测试
- **动态负载调度测试**：使用阶梯式增加并发数的测试方式
- **配置文件测试**：使用JSON配置文件执行测试

## 高级用法

要尝试更多高级功能，可以运行：
```powershell
.\scripts\advanced-examples.ps1
```

这将提供以下高级功能的示例：
- 使用模板函数动态生成数据
- 流式调用中使用动态消息
- 使用请求元数据
- 复杂负载测试方案
- 连接管理和超时设置
- 不同格式的输出

## 常见问题

如果您在使用过程中遇到问题，请参考 `docs/troubleshooting.md` 故障排除指南。

## 常用参数说明

- `-c, --concurrency`: 并发数（同时进行的请求数）
- `-n, --total`: 总请求数
- `-d, --data`: 请求数据（JSON格式）
- `-D, --data-file`: 从文件读取请求数据
- `-r, --rps`: 每秒请求数限制
- `-t, --timeout`: 请求超时时间
- `-z, --duration`: 测试持续时间
- `-O, --format`: 输出格式（如html、json、csv等）
- `-o, --output`: 输出文件路径

## 示例命令

```powershell
# 基本调用
ghz --insecure --proto ./proto/example.proto --call helloworld.Greeter.SayHello -d '{"name":"测试用户"}' -c 50 -n 1000 localhost:50051

# 使用配置文件
ghz --config ./config/ghz-config-example.json

# 流式调用
ghz --insecure --proto ./proto/example.proto --call helloworld.Greeter.SayHelloBidirectionalStream -D ./data/request-stream.json --stream-call-count 4 -c 5 -n 50 localhost:50051
```

## 报告文件

测试完成后，HTML报告将保存在`reports`目录下，可以用浏览器打开查看详细的测试结果。 