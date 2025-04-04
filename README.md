# gRPC 测试工作区

本项目提供了一个使用 `ghz` 工具进行 gRPC 服务性能和功能测试的工作环境。它包含一个示例 gRPC 服务、多个测试配置文件以及用于自动化安装、服务启动和测试执行的 PowerShell 脚本。

## ✨ 功能特性

*   **示例 gRPC 服务**: 包含一个简单的 C# gRPC 服务 (`grpc-service`)，用于演示和测试。
*   **多种测试场景**: 预置了多种 `ghz` 配置文件 (`config` 目录)，涵盖普通调用、流式调用、负载测试等场景。
*   **自动化脚本**:
    *   `.\scripts\install-ghz.ps1`: 自动下载并安装指定版本的 `ghz` 工具，并尝试添加到用户 PATH。
    *   `.\scripts\run-grpc-service.ps1`: 启动本地 gRPC 示例服务。
    *   `.\scripts\run-ghz-tests.ps1`: 提供交互式菜单，动态加载 `config` 目录下的所有测试配置，执行测试并自动处理文件路径和报告命名。
*   **动态测试发现**: `.\scripts\run-ghz-tests.ps1` 脚本自动发现 `config` 目录下的所有 `.json` 文件作为测试选项。
*   **自动报告生成**: 测试报告（HTML 格式）会自动生成在 `reports` 目录下，并带有时间戳。
*   **编码处理**: `.\scripts\run-ghz-tests.ps1` 脚本会自动检查并转换配置文件为 UTF-8 (无 BOM) 格式。

## 📁 目录结构

```
.
├── config/                   # ghz 测试配置文件 (.json)
│   ├── examples              # 参考配置文件
├── docs/                     # 文档
│   ├── troubleshooting.md    # 解决报错
├── grpc-service/             # 示例 C# gRPC 服务源代码
├── proto/                    # Protobuf 定义文件 (.proto)
├── reports/                  # 生成的测试报告 (HTML)
├── scripts/                  # 脚本 (, 运行服务, 测试)
│   ├── install-ghz.ps1       # 运行 ghz 下载安装脚本
│   ├── run-grpc-service.ps1  # 运行 demo grpc service
│   └── run-ghz-tests.ps1             # 运行测试脚本
└── README.md                 # 介绍
```

## 🚀 快速开始

### 1. 环境准备

*   **PowerShell**: 确保您的系统已安装 PowerShell (通常 Windows 自带)。
*   **.NET SDK（可选）**: 安装 .NET SDK (.NET 8 或更高版本) 以便能够运行 C# gRPC Demo 服务。您可以从 [Microsoft .NET 官网](https://dotnet.microsoft.com/download) 下载。

### 2. 安装 ghz

打开 PowerShell 终端，导航到项目根目录，然后运行安装脚本：

```shell
.\scripts\install-ghz.ps1
```

该脚本将下载 `ghz` 并尝试将其添加到用户环境变量 `PATH` 中。您可能需要**重启终端**才能使 `ghz` 命令生效。

### 3. 启动 gRPC 服务

在**单独的** PowerShell 终端中，导航到项目根目录，然后运行服务启动脚本：

```shell
.\scripts\run-grpc-service.ps1
```

服务将在 `localhost:50051` 上启动。保持此终端运行以进行测试。按 `Ctrl+C` 可以停止服务。

### 4. 运行测试

在**另一个** PowerShell 终端中，导航到项目根目录，然后运行测试脚本：

```shell
.\scripts\run-ghz-tests.ps1
```

脚本将显示一个菜单，列出 `config` 目录中找到的所有测试配置：

1.  输入对应的数字选择要运行的单个测试。
2.  输入 "执行所有测试" 对应的数字来运行所有可用的测试。
3.  输入 `0` 退出脚本。

脚本在执行测试前会自动处理配置文件（如转换编码、更新相对路径为绝对路径、为输出报告添加时间戳）。

## ⚙️ 配置

`config` 目录下的 `.json` 文件是 `ghz` 的配置文件。您可以根据需要修改它们或添加新的配置文件来定义不同的测试场景。`run-ghz-tests.ps1` 脚本会自动识别新的 `.json` 文件。

常用配置项说明：

*   `proto`: 指定 `.proto` 文件的路径 (脚本会自动处理相对路径)。
*   `call`: 指定要调用的 gRPC 方法。
*   `total`, `concurrency`, `rps`, `duration`: 控制测试负载和持续时间。
*   `data`: 定义请求的数据。可以使用 `{{randomString}}`, `{{randomInt}}` 等 `ghz` 支持的模板函数。
*   `metadata`: 添加请求元数据。
*   `output`: 指定报告输出路径 (脚本会自动处理相对路径并添加时间戳)。
*   `insecure`: 如果服务未使用 TLS，设置为 `true`。
*   `host`: 指定 gRPC 服务地址。

## 📊 报告

测试完成后，HTML 格式的报告将保存在 `reports` 目录下。报告文件名将包含原始配置文件名和执行时间戳，例如 `simple-test-result_20230101120000.html`。脚本会尝试自动打开生成的报告。

## ❓ 故障排除

如果在设置或运行过程中遇到问题，请参考 `docs/troubleshooting.md` 文件。
