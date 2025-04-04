# 常用ghz测试命令示例脚本
# 在执行前确保已安装ghz并且有gRPC服务运行在localhost:50051

# 设置公共变量
$proto = "./proto/example.proto"
$targetHost = "localhost:50051"
$reportDir = "./reports"
$dataDir = "./data"
$configDir = "./config"

# 创建报告目录
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

Write-Host "欢迎使用ghz测试脚本" -ForegroundColor Cyan

function Run-UnaryTest {
    Write-Host "`n执行普通单次调用测试..." -ForegroundColor Green
    
    # 基本unary调用 - 使用命令行数据
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"测试用户","age":30}' `
        -c 50 -n 1000 `
        -O html -o "$reportDir/unary-test-1.html" `
        $targetHost
        
    # 从文件读取请求数据
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -D "$dataDir/request-unary.json" `
        -c 50 -n 1000 `
        -O html -o "$reportDir/unary-test-2.html" `
        $targetHost
}

function Run-StreamTest {
    Write-Host "`n执行流式调用测试..." -ForegroundColor Green
    
    # 服务端流测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHelloServerStream `
        -d '{"name":"测试用户","age":30}' `
        -c 10 -n 100 `
        -O html -o "$reportDir/server-stream-test.html" `
        $targetHost
        
    # 客户端流测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHelloClientStream `
        -D "$dataDir/request-stream.json" `
        -c 10 -n 100 `
        --stream-call-count 4 `
        -O html -o "$reportDir/client-stream-test.html" `
        $targetHost
        
    # 双向流测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHelloBidirectionalStream `
        -D "$dataDir/request-stream.json" `
        -c 5 -n 50 `
        --stream-call-count 4 `
        --stream-interval 100ms `
        -O html -o "$reportDir/bidirectional-stream-test.html" `
        $targetHost
}

function Run-LoadTestWithRPS {
    Write-Host "`n执行固定RPS负载测试..." -ForegroundColor Green
    
    # 固定RPS的测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -D "$dataDir/request-unary.json" `
        -c 50 --rps 200 -n 2000 `
        -O html -o "$reportDir/load-test-rps.html" `
        $targetHost
}

function Run-LoadTestWithSchedule {
    Write-Host "`n执行动态负载调度测试..." -ForegroundColor Green
    
    # 阶梯式增加并发的测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -D "$dataDir/request-unary.json" `
        -n 5000 `
        --concurrency-schedule=step `
        --concurrency-start=10 `
        --concurrency-step=10 `
        --concurrency-end=100 `
        --concurrency-step-duration=5s `
        -O html -o "$reportDir/load-test-concurrency-step.html" `
        $targetHost
}

function Run-ConfigFileTest {
    Write-Host "`n使用配置文件执行测试..." -ForegroundColor Green
    
    # 使用JSON配置文件执行测试
    ghz --config "$configDir/ghz-config-example.json"
}

# 菜单
$continue = $true
while ($continue) {
    Write-Host "`n选择要执行的测试:" -ForegroundColor Yellow
    Write-Host "1. 执行普通单次调用测试"
    Write-Host "2. 执行流式调用测试"
    Write-Host "3. 执行固定RPS负载测试"
    Write-Host "4. 执行动态负载调度测试"
    Write-Host "5. 使用配置文件执行测试"
    Write-Host "6. 执行所有测试"
    Write-Host "0. 退出"
    
    $choice = Read-Host "请输入选项"
    
    switch ($choice) {
        "1" { Run-UnaryTest }
        "2" { Run-StreamTest }
        "3" { Run-LoadTestWithRPS }
        "4" { Run-LoadTestWithSchedule }
        "5" { Run-ConfigFileTest }
        "6" { 
            Run-UnaryTest
            Run-StreamTest
            Run-LoadTestWithRPS
            Run-LoadTestWithSchedule
            Run-ConfigFileTest
        }
        "0" { $continue = $false }
        default { Write-Host "无效选项，请重新选择" -ForegroundColor Red }
    }
}

Write-Host "`n测试完成。报告文件保存在 $reportDir 目录下" -ForegroundColor Cyan 