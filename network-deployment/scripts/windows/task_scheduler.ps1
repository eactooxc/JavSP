# JavSP Windows 定时任务配置脚本
# 使用Windows任务计划程序创建定时处理任务

param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "add",
    
    [Parameter(Mandatory=$false)]
    [string]$Schedule = "daily",
    
    [Parameter(Mandatory=$false)]
    [string]$Time = "02:00"
)

$SCRIPT_NAME = "JavSP Windows 定时任务管理器"
$VERSION = "1.0.0"
$TASK_NAME = "JavSP-AutoProcess"

# 颜色输出函数
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Header {
    Write-ColorOutput "================================" "Cyan"
    Write-ColorOutput "  $SCRIPT_NAME v$VERSION" "Cyan"
    Write-ColorOutput "================================" "Cyan"
    Write-Host ""
}

# 检查管理员权限
function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 检查Docker服务
function Test-DockerService {
    Write-ColorOutput "检查Docker服务..." "Yellow"
    
    try {
        $dockerStatus = docker ps | Select-String "javsp-server"
        if ($dockerStatus) {
            Write-ColorOutput "✓ JavSP容器运行正常" "Green"
            return $true
        } else {
            Write-ColorOutput "✗ JavSP容器未运行" "Red"
            Write-ColorOutput "请先启动Docker容器: docker-compose up -d" "Yellow"
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ Docker服务检查失败" "Red"
        return $false
    }
}

# 获取时间表达式
function Get-ScheduleTrigger {
    param([string]$Schedule, [string]$Time)
    
    $timeParts = $Time.Split(':')
    $hour = [int]$timeParts[0]
    $minute = [int]$timeParts[1]
    
    switch ($Schedule.ToLower()) {
        "hourly" {
            return New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
        }
        "daily" {
            return New-ScheduledTaskTrigger -Daily -At (Get-Date).Date.AddHours($hour).AddMinutes($minute)
        }
        "weekly" {
            return New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At (Get-Date).Date.AddHours($hour).AddMinutes($minute)
        }
        "workdays" {
            return New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At (Get-Date).Date.AddHours($hour).AddMinutes($minute)
        }
        default {
            Write-ColorOutput "未知的时间表类型: $Schedule" "Red"
            return $null
        }
    }
}

# 创建批处理脚本
function Create-BatchScript {
    $scriptPath = Join-Path $PSScriptRoot "javsp-batch.ps1"
    
    $batchContent = @"
# JavSP 自动批处理脚本
# 此脚本由定时任务调用

param(
    [switch]`$DryRun = `$false
)

`$LogFile = "C:\JavSP\logs\scheduled_task.log"
`$ErrorLog = "C:\JavSP\logs\scheduled_errors.log"

# 创建日志目录
New-Item -ItemType Directory -Path (Split-Path `$LogFile) -Force | Out-Null

function Write-Log {
    param([string]`$Message, [string]`$Level = "INFO")
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logEntry = "[`$timestamp] [`$Level] `$Message"
    
    Write-Output `$logEntry | Tee-Object -FilePath `$LogFile -Append
    
    if (`$Level -eq "ERROR") {
        Write-Output `$logEntry | Tee-Object -FilePath `$ErrorLog -Append
    }
}

try {
    Write-Log "开始JavSP定时处理任务"
    
    # 检查Docker容器状态
    `$containerStatus = docker ps --filter "name=javsp-server" --format "table {{.Status}}"
    if (-not `$containerStatus -or `$containerStatus -notmatch "Up") {
        Write-Log "JavSP容器未运行，尝试启动..." "WARN"
        
        # 尝试启动容器
        Set-Location "C:\JavSP\network-deployment"
        docker-compose up -d
        
        Start-Sleep -Seconds 30
        
        `$containerStatus = docker ps --filter "name=javsp-server" --format "table {{.Status}}"
        if (-not `$containerStatus -or `$containerStatus -notmatch "Up") {
            Write-Log "容器启动失败" "ERROR"
            exit 1
        }
    }
    
    Write-Log "Docker容器状态正常"
    
    if (`$DryRun) {
        Write-Log "干运行模式，跳过实际处理"
    } else {
        # 执行Docker容器内的批处理
        Write-Log "开始执行JavSP处理..."
        
        `$result = docker exec javsp-server /app/.venv/bin/python -m javsp -i /app/input 2>&1
        
        if (`$LASTEXITCODE -eq 0) {
            Write-Log "JavSP处理完成"
            Write-Log "处理结果: `$result"
        } else {
            Write-Log "JavSP处理失败: `$result" "ERROR"
        }
    }
    
    Write-Log "定时任务执行完成"
}
catch {
    Write-Log "定时任务执行异常: `$(`$_.Exception.Message)" "ERROR"
    exit 1
}
"@
    
    $batchContent | Out-File -FilePath $scriptPath -Encoding UTF8
    Write-ColorOutput "✓ 批处理脚本已创建: $scriptPath" "Green"
    
    return $scriptPath
}

# 创建定时任务
function Add-ScheduledTask {
    param([string]$Schedule, [string]$Time)
    
    Write-ColorOutput "创建定时任务..." "Yellow"
    
    try {
        # 检查任务是否已存在
        $existingTask = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-ColorOutput "任务已存在，先删除旧任务" "Yellow"
            Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
        }
        
        # 创建批处理脚本
        $scriptPath = Create-BatchScript
        
        # 创建触发器
        $trigger = Get-ScheduleTrigger -Schedule $Schedule -Time $Time
        if (-not $trigger) {
            return $false
        }
        
        # 创建动作
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
        
        # 创建设置
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        # 创建主体（以SYSTEM身份运行）
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # 注册任务
        Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "JavSP自动批处理任务"
        
        Write-ColorOutput "✓ 定时任务创建成功" "Green"
        Write-ColorOutput "任务名称: $TASK_NAME" "White"
        Write-ColorOutput "执行时间: $Schedule at $Time" "White"
        Write-ColorOutput "脚本路径: $scriptPath" "White"
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ 创建定时任务失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 移除定时任务
function Remove-ScheduledTask {
    Write-ColorOutput "移除定时任务..." "Yellow"
    
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
            Write-ColorOutput "✓ 定时任务已移除" "Green"
        } else {
            Write-ColorOutput "任务不存在: $TASK_NAME" "Yellow"
        }
    }
    catch {
        Write-ColorOutput "✗ 移除任务失败: $($_.Exception.Message)" "Red"
    }
}

# 显示当前任务
function Show-CurrentTask {
    Write-ColorOutput "当前JavSP定时任务:" "Cyan"
    Write-Host ""
    
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TASK_NAME
            
            Write-ColorOutput "任务名称: $($task.TaskName)" "Green"
            Write-ColorOutput "状态: $($task.State)" "White"
            Write-ColorOutput "上次运行: $($taskInfo.LastRunTime)" "White"
            Write-ColorOutput "下次运行: $($taskInfo.NextRunTime)" "White"
            Write-ColorOutput "上次结果: $($taskInfo.LastTaskResult)" "White"
            
            # 显示触发器信息
            foreach ($trigger in $task.Triggers) {
                Write-ColorOutput "触发器: $($trigger.CimClass.CimClassName)" "White"
            }
        } else {
            Write-ColorOutput "未找到JavSP定时任务" "Yellow"
        }
    }
    catch {
        Write-ColorOutput "查询任务失败: $($_.Exception.Message)" "Red"
    }
}

# 测试任务
function Test-ScheduledTask {
    Write-ColorOutput "测试定时任务..." "Yellow"
    
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-ColorOutput "任务不存在: $TASK_NAME" "Red"
            return
        }
        
        # 执行测试
        Write-ColorOutput "执行测试运行..." "Yellow"
        Start-ScheduledTask -TaskName $TASK_NAME
        
        Start-Sleep -Seconds 5
        
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TASK_NAME
        Write-ColorOutput "任务状态: $($taskInfo.LastTaskResult)" "White"
        
        # 检查日志
        $logFile = "C:\JavSP\logs\scheduled_task.log"
        if (Test-Path $logFile) {
            Write-ColorOutput "最近的日志:" "Cyan"
            Get-Content $logFile -Tail 10
        }
    }
    catch {
        Write-ColorOutput "测试失败: $($_.Exception.Message)" "Red"
    }
}

# 查看日志
function Show-Logs {
    param([string]$LogType = "task")
    
    $logFiles = @{
        "task" = "C:\JavSP\logs\scheduled_task.log"
        "error" = "C:\JavSP\logs\scheduled_errors.log"
    }
    
    $logFile = $logFiles[$LogType]
    if (-not $logFile) {
        Write-ColorOutput "未知的日志类型: $LogType" "Red"
        Write-ColorOutput "可用类型: task, error" "Yellow"
        return
    }
    
    if (Test-Path $logFile) {
        Write-ColorOutput "显示日志: $logFile" "Cyan"
        Write-Host "----------------------------------------"
        Get-Content $logFile -Tail 50
        Write-Host "----------------------------------------"
    } else {
        Write-ColorOutput "日志文件不存在: $logFile" "Yellow"
    }
}

# 显示可用模板
function Show-Templates {
    Write-ColorOutput "可用的时间表模板:" "Cyan"
    Write-Host ""
    Write-ColorOutput "  hourly      每小时执行一次" "White"
    Write-ColorOutput "  daily       每天执行一次" "White"
    Write-ColorOutput "  weekly      每周执行一次" "White"
    Write-ColorOutput "  workdays    工作日执行" "White"
    Write-Host ""
}

# 显示使用帮助
function Show-Usage {
    Write-ColorOutput "使用方法:" "Cyan"
    Write-Host ""
    Write-ColorOutput "添加定时任务:" "White"
    Write-ColorOutput "  .\task_scheduler.ps1 -Action add -Schedule daily -Time 02:00" "Gray"
    Write-Host ""
    Write-ColorOutput "移除定时任务:" "White"
    Write-ColorOutput "  .\task_scheduler.ps1 -Action remove" "Gray"
    Write-Host ""
    Write-ColorOutput "显示当前任务:" "White"
    Write-ColorOutput "  .\task_scheduler.ps1 -Action list" "Gray"
    Write-Host ""
    Write-ColorOutput "测试任务:" "White"
    Write-ColorOutput "  .\task_scheduler.ps1 -Action test" "Gray"
    Write-Host ""
    Write-ColorOutput "查看日志:" "White"
    Write-ColorOutput "  .\task_scheduler.ps1 -Action logs" "Gray"
    Write-Host ""
    Write-ColorOutput "参数说明:" "Cyan"
    Write-ColorOutput "  -Schedule: hourly|daily|weekly|workdays" "White"
    Write-ColorOutput "  -Time: HH:MM 格式 (如: 02:00)" "White"
}

# 主程序
function Main {
    Show-Header
    
    # 检查管理员权限
    if (-not (Test-AdminRights)) {
        Write-ColorOutput "错误: 此脚本需要管理员权限运行" "Red"
        Write-ColorOutput "请以管理员身份重新运行PowerShell" "Yellow"
        return
    }
    
    switch ($Action.ToLower()) {
        "add" {
            if (-not (Test-DockerService)) {
                Write-ColorOutput "请先确保Docker服务正常运行" "Red"
                return
            }
            
            Add-ScheduledTask -Schedule $Schedule -Time $Time
        }
        
        "remove" {
            Remove-ScheduledTask
        }
        
        "list" {
            Show-CurrentTask
        }
        
        "test" {
            Test-ScheduledTask
        }
        
        "logs" {
            Show-Logs
        }
        
        "templates" {
            Show-Templates
        }
        
        "help" {
            Show-Usage
        }
        
        default {
            Write-ColorOutput "未知操作: $Action" "Red"
            Show-Usage
        }
    }
}

# 执行主程序
Main