# 启动 gRPC 服务 Demo

$projectRoot = Split-Path -Parent $PSScriptRoot
$grpcServicePath = Join-Path $projectRoot "grpc-service"

Write-Host "正在启动gRPC服务..." -ForegroundColor Cyan
Write-Host "服务路径: $grpcServicePath"
Write-Host "端口: 50051"
Write-Host "按 Ctrl+C 停止服务"
Write-Host "========================================================="

# 切换到gRPC服务目录并启动
Push-Location $grpcServicePath
dotnet run
Pop-Location 