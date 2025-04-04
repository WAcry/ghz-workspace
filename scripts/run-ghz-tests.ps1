# 运行基于配置的测试

$projectRoot = Split-Path -Parent $PSScriptRoot
$configDir = "$projectRoot/config"
$reportDir = "$projectRoot/reports"

# 确保报告目录存在
if (-not (Test-Path $reportDir))
{
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

Write-Host "欢迎使用gRPC测试脚本" -ForegroundColor Cyan
Write-Host "当前工作目录: $projectRoot" -ForegroundColor Gray
Write-Host "配置文件目录: $configDir" -ForegroundColor Gray
Write-Host "报告输出目录: $reportDir" -ForegroundColor Gray

# 处理配置文件路径，替换相对路径为绝对路径
function Process-ConfigFile
{
    param (
        [string]$ConfigFile,
        [string]$TestName
    )

    $tempConfigFile = "$env:TEMP/temp-grpc-config-$([guid]::NewGuid() ).json" # 使用唯一临时文件名以避免冲突

    try
    {
        # 检查配置文件是否存在
        if (-not (Test-Path $ConfigFile))
        {
            Write-Host "错误: 配置文件不存在: $ConfigFile" -ForegroundColor Red
            return $null
        }

        # === 文件编码与 BOM 处理 ===
        $configContent = $null
        $hasBom = $false

        try
        {
            # 1. 检查文件头部是否有 UTF-8 BOM (EF BB BF)
            $bytes = Get-Content $ConfigFile -Encoding Byte -TotalCount 3 -ErrorAction SilentlyContinue
            if ($bytes -ne $null -and $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            {
                $hasBom = $true
            }

            # 2. 读取完整文件内容 (无论是否有 BOM，先读取)
            #    使用 -Raw 获取单字符串，尝试用 UTF8 读取，如果失败或内容不对，可回退到 Default
            try
            {
                $configContent = Get-Content -Raw -Path $ConfigFile -Encoding UTF8 -ErrorAction Stop
            }
            catch
            {
                Write-Host "警告: 尝试以 UTF8 读取 '$ConfigFile' 失败: $_。将尝试以 Default 编码读取。" -ForegroundColor Yellow
                $configContent = Get-Content -Raw -Path $ConfigFile -Encoding Default
            }

            # 检查是否成功读取内容
            if ($configContent -eq $null)
            {
                Write-Host "错误: 读取配置文件内容失败: $ConfigFile" -ForegroundColor Red
                return $null
            }

        }
        catch
        {
            Write-Host "错误: 检查或读取配置文件 '$ConfigFile' 时出错: $_" -ForegroundColor Red
            return $null
        }

        # 3. 如果检测到 BOM，则使用 Out-File 转换 (覆盖原文件)
        if ($hasBom)
        {
            try
            {
                Write-Host "检测到 UTF-8 BOM，正在转换文件 '$ConfigFile' 为 UTF-8 无 BOM..." -ForegroundColor Yellow
                # 使用 Out-File 强制以 UTF8NoBOM 编码覆盖写入
                $configContent | Out-File -FilePath $ConfigFile -Encoding UTF8NoBOM -Force
                Write-Host "文件 $ConfigFile 已成功转换为 UTF-8 无 BOM。" -ForegroundColor Green

                # 注意: $configContent 仍然是转换前的内容，这通常没问题，因为BOM不影响JSON结构
                # 如果转换后的内容需要精确用于后续步骤，可以在此处重新读取:
                # $configContent = Get-Content -Raw -Path $ConfigFile -Encoding UTF8 
            }
            catch
            {
                Write-Host "错误: 转换文件 '$ConfigFile' 到 UTF-8 无 BOM 时出错: $_" -ForegroundColor Red
                return $null
            }
        }
        else
        {
            Write-Host "文件 $ConfigFile 未检测到 UTF-8 BOM，格式正确。" -ForegroundColor Gray
        }

        # 4. 解析 JSON (使用内存中的 $configContent)
        $config = $null
        try
        {
            # 移除可能存在于 $configContent 开头的 BOM 字符 (以防万一读取时未处理掉)
            if ($hasBom)
            {
                # UTF8 BOM is 3 bytes, find the first char after BOM
                # This assumes $configContent is string. Need conversion if it's byte array.
                if ($configContent -is [string])
                {
                    $configContent = $configContent.Substring(1) # Assuming BOM maps to one weird char at start
                }
                else
                {
                    # Handle byte array case if Get-Content returned that, though -Raw usually gives string
                }
            }
            $config = $configContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch
        {
            Write-Host "错误: 解析 JSON 配置文件 '$ConfigFile' 时出错: $_" -ForegroundColor Red
            # Write-Host "读取到的内容 (前500字符): $($configContent.Substring(0, [System.Math]::Min($configContent.Length, 500)))..." -ForegroundColor DarkGray 
            return $null
        }

        # --- 后续处理保持不变 --- 
        # 存储原始路径以供日志记录 (注意: reflection test 可能没有 proto)
        $originalProtoPath = if ($config.PSObject.Properties.Name -contains 'proto')
        {
            $config.proto
        }
        else
        {
            $null
        }
        $originalOutputPath = $config.output # output 应该总是存在或被生成

        # 显示配置文件内容摘要 (更全面)
        Write-Host "配置文件内容摘要:" -ForegroundColor Yellow
        Write-Host "  调用方法: $( $config.call )" -ForegroundColor Gray

        # 测试类型判断
        if (-not ($config.PSObject.Properties.Name -contains 'proto'))
        {
            Write-Host "  测试类型: 反射调用" -ForegroundColor Magenta
        }
        else
        {
            Write-Host "  测试类型: Proto 调用" -ForegroundColor Magenta
        }

        if (($config.PSObject.Properties.Name -contains 'data') -and (($config.data | ConvertTo-Json) -match '\{\{'))
        {
            Write-Host "  数据类型: 模板化数据 (包含 '{{')" -ForegroundColor Cyan
        }
        else
        {
            Write-Host "  数据类型: 静态数据" -ForegroundColor Gray
        }

        # 负载/请求参数
        if ($config.PSObject.Properties.Name -contains 'total')
        {
            Write-Host "  总请求数: $( $config.total )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'connections')
        {
            Write-Host "  连接数: $( $config.connections )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'concurrency')
        {
            Write-Host "  并发数: $( $config.concurrency )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'rps')
        {
            Write-Host "  每秒请求数 (RPS): $( $config.rps )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'duration')
        {
            Write-Host "  持续时间: $( $config.duration )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'timeout')
        {
            Write-Host "  请求超时: $( $config.timeout )" -ForegroundColor Gray
        }

        # 并发调度
        if ($config.PSObject.Properties.Name -contains 'concurrency-schedule')
        {
            Write-Host "  并发调度: $( $config.'concurrency-schedule' )" -ForegroundColor Gray
            if ($config.'concurrency-schedule' -eq 'step')
            {
                if ($config.PSObject.Properties.Name -contains 'concurrency-start')
                {
                    Write-Host "    开始: $( $config.'concurrency-start' )" -ForegroundColor Gray
                }
                if ($config.PSObject.Properties.Name -contains 'concurrency-step')
                {
                    Write-Host "    步长: $( $config.'concurrency-step' )" -ForegroundColor Gray
                }
                if ($config.PSObject.Properties.Name -contains 'concurrency-end')
                {
                    Write-Host "    结束: $( $config.'concurrency-end' )" -ForegroundColor Gray
                }
                if ($config.PSObject.Properties.Name -contains 'concurrency-step-duration')
                {
                    Write-Host "    步长持续: $( $config.'concurrency-step-duration' )" -ForegroundColor Gray
                }
            }
        }

        # 流式参数
        if ($config.PSObject.Properties.Name -contains 'stream-call-count')
        {
            Write-Host "  流调用数量: $( $config.'stream-call-count' )" -ForegroundColor Gray
        }
        if ($config.PSObject.Properties.Name -contains 'stream-interval')
        {
            Write-Host "  流间隔时间: $( $config.'stream-interval' )" -ForegroundColor Gray
        }

        # 目标主机
        Write-Host "  目标主机: $( $config.host )" -ForegroundColor Gray

        # 处理 proto 文件路径 (如果存在)
        if ($originalProtoPath -and $originalProtoPath.StartsWith("./"))
        {
            $protoAbsPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($projectRoot,$originalProtoPath.Substring(2)))
            $config.proto = $protoAbsPath.Replace('\', '/') # 更新对象中的路径
            Write-Host "更新 Proto 文件路径: $originalProtoPath -> $( $config.proto )" -ForegroundColor Gray
        }

        # 处理输出文件路径并添加测试名称和时间戳 （直接修改 $config 对象）
        if ($originalOutputPath -and $originalOutputPath.StartsWith("./"))
        {
            # 移除原始路径中的扩展名，以基础名称为起点
            $baseOutputPath = [System.IO.Path]::GetDirectoryName($originalOutputPath)
            $originalExtension = [System.IO.Path]::GetExtension($originalOutputPath) # 保留原始扩展名

            # 构造新的报告目录路径 (确保 reports 目录存在)
            $reportDirectoryPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($projectRoot, "reports"))
            if (-not (Test-Path $reportDirectoryPath))
            {
                New-Item -ItemType Directory -Path $reportDirectoryPath -Force | Out-Null
            }

            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $newFileName = "${TestName}_${timestamp}${originalExtension}"
            $newOutputAbsPath = [System.IO.Path]::Combine($reportDirectoryPath, $newFileName)

            $config.output = $newOutputAbsPath.Replace('\', '/') # 更新对象中的路径
            Write-Host "更新输出文件路径: $originalOutputPath -> $( $config.output )" -ForegroundColor Gray
        }
        elseif ($originalOutputPath)
        {
            # 如果提供了 output 路径但不是相对路径，只记录警告，不修改
            Write-Host "警告: 配置文件 '$ConfigFile' 中的 output 路径 '$originalOutputPath' 不是以 './' 开头的相对路径，将按原样使用。" -ForegroundColor Yellow
        }
        else
        {
            # 如果未提供 output 路径，生成一个默认路径
            Write-Host "警告: 配置文件 '$ConfigFile' 中未提供 output 路径。将生成默认报告路径。" -ForegroundColor Yellow
            $reportDirectoryPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($projectRoot, "reports"))
            if (-not (Test-Path $reportDirectoryPath))
            {
                New-Item -ItemType Directory -Path $reportDirectoryPath -Force | Out-Null
            }

            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $newFileName = "${TestName}_${timestamp}.html" # 默认使用 html 扩展名
            $newOutputAbsPath = [System.IO.Path]::Combine($reportDirectoryPath, $newFileName)
            $config.output = $newOutputAbsPath.Replace('\', '/')
            Write-Host "已生成默认输出文件路径: $( $config.output )" -ForegroundColor Gray
        }

        # 将 *修改后* 的 $config 对象转换为 JSON
        $tempConfig = $config | ConvertTo-Json -Depth 10

        # 使用UTF-8无BOM编码保存临时配置文件
        [System.IO.File]::WriteAllText($tempConfigFile, $tempConfig,[System.Text.UTF8Encoding]::new($false))
        Write-Host "已创建临时配置文件: $tempConfigFile" -ForegroundColor Gray

        return $tempConfigFile
    }
    catch
    {
        Write-Host "错误: 处理配置文件 '$( $ConfigFile )' 时发生顶层意外错误: $_" -ForegroundColor Red
        # 尝试删除可能已创建的临时文件
        if (Test-Path $tempConfigFile)
        {
            Remove-Item $tempConfigFile -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

# 执行测试函数
function Run-Test
{
    param (
        [string]$ConfigFile,
        [string]$TestName
    )

    Write-Host "`n执行 $TestName..." -ForegroundColor Green

    $fullConfigPath = "$configDir/$ConfigFile"
    $tempConfigFile = Process-ConfigFile -ConfigFile $fullConfigPath -TestName $TestName

    if (-not $tempConfigFile)
    {
        return
    }

    try
    {
        # 执行测试
        Write-Host "`n开始执行测试" -ForegroundColor Yellow
        Write-Host "执行命令: ghz --config `"$tempConfigFile`"" -ForegroundColor Gray

        & ghz --config "$tempConfigFile"

        # 从临时配置文件中读取最终的报告路径
        $finalConfig = Get-Content $tempConfigFile -Encoding UTF8 | ConvertFrom-Json
        $reportPath = $finalConfig.output

        if (Test-Path $reportPath)
        {
            Write-Host "测试报告已生成: $reportPath" -ForegroundColor Green
            # 尝试打开生成的报告
            try
            {
                Invoke-Item $reportPath
                Write-Host "已尝试自动打开报告: $reportPath" -ForegroundColor Cyan
            }
            catch
            {
                Write-Host "警告: 无法自动打开报告 '$reportPath'. 错误: $_" -ForegroundColor Yellow
            }
        }
        else
        {
            Write-Host "错误: 未找到预期的测试报告: $reportPath" -ForegroundColor Red
        }
    }
    catch
    {
        Write-Host "错误: 执行测试时出错: $_" -ForegroundColor Red
    }
    finally
    {
        # 测试完成后删除临时文件
        if (Test-Path $tempConfigFile)
        {
            Remove-Item $tempConfigFile -Force
            Write-Host "临时配置文件已删除" -ForegroundColor Gray
        }
    }

    Write-Host "`n测试完成" -ForegroundColor Green
}

# 动态菜单与执行
$continue = $true
while ($continue)
{
    # 获取 config 目录下的所有 JSON 文件, 并按名称排序
    try
    {
        $configFiles = Get-ChildItem -Path $configDir -Filter *.json -ErrorAction Stop | Sort-Object Name
    }
    catch
    {
        Write-Host "错误: 无法读取配置文件目录 '$configDir': $_" -ForegroundColor Red
        $continue = $false
        break
    }

    if ($configFiles.Count -eq 0)
    {
        Write-Host "`n警告: 在 '$configDir' 目录中未找到任何 .json 配置文件。" -ForegroundColor Yellow
        # 仍然提供退出选项
        Write-Host "`n0. 退出"
        $choice = Read-Host "请输入选项 (只有 0 可选)"
        if ($choice -eq "0")
        {
            $continue = $false
        }
        else
        {
            Write-Host "无效选项。" -ForegroundColor Red
        }
        continue # 继续循环以防用户输错
    }

    Write-Host "`n选择要执行的测试:" -ForegroundColor Yellow

    # 动态生成菜单项
    $menuItems = @{ } # 使用哈希表存储索引到文件名的映射
    for ($i = 0; $i -lt $configFiles.Count; $i++) {
        $menuIndex = $i + 1
        $fileName = $configFiles[$i].Name
        $displayName = $configFiles[$i].BaseName
        Write-Host (" {0,2}. {1}" -f $menuIndex, $displayName)
        $menuItems[$menuIndex.ToString()] = $fileName
    }

    $allTestsIndex = $configFiles.Count + 1
    $clearReportsIndex = $configFiles.Count + 2
    Write-Host (" {0,2}. 执行所有测试" -f $allTestsIndex)
    Write-Host (" {0,2}. 清除所有报告" -f $clearReportsIndex)
    Write-Host "  0. 退出"

    $choice = Read-Host "请输入选项"

    # 处理用户选择
    if ( $menuItems.ContainsKey($choice))
    {
        # 选择单个测试
        $selectedConfigFile = $menuItems[$choice]
        # 从处理过的显示名称或文件名获取测试名
        $selectedIndex = [int]$choice
        $configFileObject = $configFiles[$selectedIndex - 1]
        $testName = $configFileObject.BaseName # 使用 BaseName 作为测试名称传递
        Run-Test -ConfigFile $selectedConfigFile -TestName $testName
    }
    elseif ($choice -eq $allTestsIndex.ToString())
    {
        # 执行所有测试
        Write-Host "`n开始执行所有测试..." -ForegroundColor Magenta
        foreach ($configFileItem in $configFiles)
        {
            $testName = $configFileItem.BaseName # 使用 BaseName 作为测试名称传递
            Run-Test -ConfigFile $configFileItem.Name -TestName $testName
        }
        Write-Host "\n所有测试执行完毕。" -ForegroundColor Magenta
    }
    elseif ($choice -eq $clearReportsIndex.ToString())
    {
        Write-Host "\n警告：此操作将删除 '$reportDir' 目录下的所有报告文件和子目录，但会保留 '.gitkeep' 文件。" -ForegroundColor Yellow
        $confirm = Read-Host "确定要继续吗？(输入 'y' 确认)"
        if ($confirm -eq 'y')
        {
            if (Test-Path $reportDir)
            {
                Write-Host "正在清除报告目录..." -ForegroundColor Cyan
                try
                {
                    Get-ChildItem -Path $reportDir -Force | Where-Object { $_.Name -ne '.gitkeep' } | Remove-Item -Recurse -Force -ErrorAction Stop
                    Write-Host "报告目录已成功清除（保留 .gitkeep）。" -ForegroundColor Green
                }
                catch
                {
                    Write-Host "错误：清除报告目录时出错: $_" -ForegroundColor Red
                }
            }
            else
            {
                Write-Host "报告目录 '$reportDir' 不存在，无需清除。" -ForegroundColor Gray
            }
        }
        else
        {
            Write-Host "操作已取消。" -ForegroundColor Gray
        }
    }
    elseif ($choice -eq "0")
    {
        $continue = $false
        Write-Host "脚本已退出。" -ForegroundColor Cyan
    }
    else
    {
        Write-Host "无效选项，请重新选择。" -ForegroundColor Red
    }
}