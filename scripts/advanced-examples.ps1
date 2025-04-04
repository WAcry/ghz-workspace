# ghz高级用法示例脚本
# 展示模板功能、动态数据生成和其他高级特性

$proto = "./proto/example.proto"
$targetHost = "localhost:50051"
$reportDir = "./reports"
$dataDir = "./data"

# 创建报告目录
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

Write-Host "ghz高级用法示例" -ForegroundColor Cyan

# 使用模板函数生成动态数据
function Run-TemplateExample {
    Write-Host "`n1. 使用模板函数动态生成数据..." -ForegroundColor Green
    
    # 使用随机字符串和请求计数器
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"用户{{.RequestNumber}}","age":{{randomInt 18 65}},"tags":["{{randomString 8}}","{{randomString 8}}"]}' `
        -c 10 -n 100 `
        -O html -o "$reportDir/template-example.html" `
        $targetHost
    
    Write-Host "动态模板请求示例: " -ForegroundColor Yellow
    Write-Host '{"name":"用户{{.RequestNumber}}","age":{{randomInt 18 65}},"tags":["{{randomString 8}}","{{randomString 8}}"]}'
}

# 流式调用中使用动态消息
function Run-DynamicStreamExample {
    Write-Host "`n2. 流式调用中使用动态消息..." -ForegroundColor Green
    
    # 开启动态消息生成
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHelloClientStream `
        -d '[{"name":"动态{{.RequestNumber}}-{{randomInt 1 100}}","age":{{randomInt 18 65}}}]' `
        --stream-dynamic-messages `
        --stream-call-count 5 `
        -c 5 -n 20 `
        -O html -o "$reportDir/dynamic-stream-example.html" `
        $targetHost
        
    Write-Host "动态流消息示例: " -ForegroundColor Yellow
    Write-Host '[{"name":"动态{{.RequestNumber}}-{{randomInt 1 100}}","age":{{randomInt 18 65}}}]'
}

# 使用元数据
function Run-MetadataExample {
    Write-Host "`n3. 使用请求元数据..." -ForegroundColor Green
    
    # 添加请求元数据
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"测试用户"}' `
        -m '{"request-id":"{{.RequestNumber}}-{{randomString 8}}","user-agent":"ghz-client","authorization":"Bearer test-token"}' `
        -c 10 -n 100 `
        -O html -o "$reportDir/metadata-example.html" `
        $targetHost
        
    Write-Host "元数据示例: " -ForegroundColor Yellow
    Write-Host '{"request-id":"{{.RequestNumber}}-{{randomString 8}}","user-agent":"ghz-client","authorization":"Bearer test-token"}'
}

# 复杂的负载测试方案
function Run-ComplexLoadSchedule {
    Write-Host "`n4. 复杂负载测试方案..." -ForegroundColor Green
    
    # 线性增加负载速率
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"性能测试用户"}' `
        -c 20 `
        --load-schedule=line `
        --load-start=50 `
        --load-end=500 `
        --load-step=10 `
        -z 30s `
        -O html -o "$reportDir/complex-load-line.html" `
        $targetHost
        
    # 阶梯式增加并发和速率
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"性能测试用户"}' `
        --concurrency-schedule=step `
        --concurrency-start=10 `
        --concurrency-end=50 `
        --concurrency-step=10 `
        --concurrency-step-duration=5s `
        --load-schedule=step `
        --load-start=100 `
        --load-end=500 `
        --load-step=100 `
        --load-step-duration=10s `
        -z 1m `
        -O html -o "$reportDir/complex-load-step.html" `
        $targetHost
}

# 连接管理和超时设置
function Run-ConnectionExample {
    Write-Host "`n5. 连接管理和超时设置..." -ForegroundColor Green
    
    # 多连接测试
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"连接测试"}' `
        -c 50 -n 1000 `
        --connections=5 `
        --connect-timeout=500ms `
        --timeout=2s `
        --keepalive=5s `
        -O html -o "$reportDir/connection-example.html" `
        $targetHost
        
    Write-Host "多连接示例参数: " -ForegroundColor Yellow
    Write-Host "--connections=5 --connect-timeout=500ms --timeout=2s --keepalive=5s"
}

# 数据上传到监控系统的格式
function Show-MonitoringFormats {
    Write-Host "`n6. 数据上传到监控系统格式示例..." -ForegroundColor Green
    
    # InfluxDB行协议格式
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"监控测试"}' `
        -c 10 -n 50 `
        -O influx-summary -o "$reportDir/influx-format.txt" `
        $targetHost
        
    # Prometheus文本格式
    ghz --insecure `
        --proto $proto `
        --call helloworld.Greeter.SayHello `
        -d '{"name":"监控测试"}' `
        -c 10 -n 50 `
        -O prometheus -o "$reportDir/prometheus-format.txt" `
        $targetHost
        
    Write-Host "已生成监控系统格式文件(InfluxDB和Prometheus)到reports目录"
}

# 菜单
$continue = $true
while ($continue) {
    Write-Host "`n选择要执行的高级示例:" -ForegroundColor Yellow
    Write-Host "1. 使用模板函数动态生成数据"
    Write-Host "2. 流式调用中使用动态消息"
    Write-Host "3. 使用请求元数据"
    Write-Host "4. 复杂负载测试方案"
    Write-Host "5. 连接管理和超时设置"
    Write-Host "6. 数据上传到监控系统格式示例"
    Write-Host "7. 执行所有高级示例"
    Write-Host "0. 退出"
    
    $choice = Read-Host "请输入选项"
    
    switch ($choice) {
        "1" { Run-TemplateExample }
        "2" { Run-DynamicStreamExample }
        "3" { Run-MetadataExample }
        "4" { Run-ComplexLoadSchedule }
        "5" { Run-ConnectionExample }
        "6" { Show-MonitoringFormats }
        "7" { 
            Run-TemplateExample
            Run-DynamicStreamExample
            Run-MetadataExample
            Run-ComplexLoadSchedule
            Run-ConnectionExample
            Show-MonitoringFormats
        }
        "0" { $continue = $false }
        default { Write-Host "无效选项，请重新选择" -ForegroundColor Red }
    }
}

Write-Host "`n高级示例测试完成。报告文件保存在 $reportDir 目录下" -ForegroundColor Cyan 