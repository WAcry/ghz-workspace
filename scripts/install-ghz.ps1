# 下载安装 ghz

$projectRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $projectRoot "reports"

if (-not (Test-Path $reportDir)) {
    Write-Host "创建reports目录..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

# 创建临时目录用于下载
$tempDir = Join-Path $env:TEMP "ghz-download"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# 定义版本和下载URL
$version = "v0.120.0"  # 最新版本
$downloadUrl = "https://github.com/bojand/ghz/releases/download/$version/ghz-windows-x86_64.zip"
$zipFile = Join-Path $tempDir "ghz.zip"

# 安装目录
$installDir = Join-Path $env:USERPROFILE "ghz"
$binDir = Join-Path $installDir "bin"

Write-Host "正在下载ghz $version..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile
}
catch {
    Write-Host "下载失败: $_" -ForegroundColor Red
    exit 1
}

Write-Host "正在解压文件..." -ForegroundColor Cyan
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $binDir)

# 添加到PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $currentPath.Contains($binDir)) {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binDir", "User")
    Write-Host "已将ghz添加到用户PATH中" -ForegroundColor Green
}

# 清理
Remove-Item -Path $tempDir -Recurse -Force

# 验证安装
try {
    $ghzVersion = & "$binDir\ghz" --version
    Write-Host "ghz安装成功!" -ForegroundColor Green
    Write-Host $ghzVersion -ForegroundColor Cyan
}
catch {
    Write-Host "ghz安装可能未成功，请尝试重启终端后运行 'ghz --version'" -ForegroundColor Yellow
}

Write-Host "`n使用说明:" -ForegroundColor Cyan
Write-Host "1. 重启PowerShell或命令提示符以使PATH更改生效"
Write-Host "2. 使用 'ghz --help' 查看所有可用选项"
Write-Host "3. 运行脚本开始测试: .\scripts\run-ghz-tests.ps1"

Write-Host "所有测试报告将保存在: $reportDir 目录" -ForegroundColor Green