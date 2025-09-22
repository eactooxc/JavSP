# JavSP Windows 客户端连接脚本
# 此脚本帮助Windows用户连接到JavSP网络服务器

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP,
    
    [Parameter(Mandatory=$false)]
    [string]$Action = "connect"
)

# 配置变量
$SCRIPT_NAME = "JavSP Windows 客户端"
$VERSION = "1.0.0"
$INPUT_DRIVE = "J:"
$OUTPUT_DRIVE = "K:"
$SHARE_INPUT = "javsp-input"
$SHARE_OUTPUT = "javsp-output"

# 颜色输出函数
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# 显示标题
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

# 自动发现服务器IP
function Find-JavSPServer {
    Write-ColorOutput "正在搜索JavSP服务器..." "Yellow"
    
    # 获取本地网段
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -match "^192\.168\." -or $_.IPAddress -match "^10\." -or $_.IPAddress -match "^172\."}).IPAddress | Select-Object -First 1
    if (-not $localIP) {
        Write-ColorOutput "无法获取本地IP地址" "Red"
        return $null
    }
    
    $subnet = $localIP.Substring(0, $localIP.LastIndexOf('.')) + "."
    Write-ColorOutput "扫描网段: $subnet*" "Yellow"
    
    # 扫描常见IP范围
    $found = $false
    foreach ($i in 1..254) {
        $testIP = "$subnet$i"
        try {
            $ping = Test-Connection -ComputerName $testIP -Count 1 -Quiet -TimeoutSeconds 1
            if ($ping) {
                # 检查是否有SMB共享
                try {
                    $shares = Get-WmiObject -Class Win32_Share -ComputerName $testIP -ErrorAction SilentlyContinue
                    if ($shares | Where-Object {$_.Name -eq $SHARE_INPUT}) {
                        Write-ColorOutput "找到JavSP服务器: $testIP" "Green"
                        return $testIP
                    }
                }
                catch {
                    # 忽略错误继续
                }
            }
        }
        catch {
            # 忽略ping错误
        }
    }
    
    Write-ColorOutput "未找到JavSP服务器，请手动指定IP地址" "Red"
    return $null
}

# 测试服务器连接
function Test-ServerConnection {
    param([string]$IP)
    
    Write-ColorOutput "测试服务器连接: $IP" "Yellow"
    
    # 测试网络连通性
    if (-not (Test-Connection -ComputerName $IP -Count 2 -Quiet)) {
        Write-ColorOutput "无法ping通服务器: $IP" "Red"
        return $false
    }
    
    # 测试SMB端口
    try {
        $socket = New-Object System.Net.Sockets.TcpClient
        $socket.Connect($IP, 445)
        $socket.Close()
        Write-ColorOutput "SMB服务连接正常" "Green"
    }
    catch {
        Write-ColorOutput "SMB服务连接失败 (端口445)" "Red"
        return $false
    }
    
    return $true
}

# 连接网络驱动器
function Connect-NetworkDrives {
    param([string]$ServerIP)
    
    Write-ColorOutput "连接网络驱动器..." "Yellow"
    
    try {
        # 断开现有连接
        if (Get-PSDrive -Name $INPUT_DRIVE.TrimEnd(':') -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $INPUT_DRIVE.TrimEnd(':') -Force
            Write-ColorOutput "断开现有输入驱动器连接" "Yellow"
        }
        
        if (Get-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':') -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':') -Force
            Write-ColorOutput "断开现有输出驱动器连接" "Yellow"
        }
        
        # 连接输入共享（可读写）
        $inputPath = "\\$ServerIP\$SHARE_INPUT"
        New-PSDrive -Name $INPUT_DRIVE.TrimEnd(':') -PSProvider FileSystem -Root $inputPath -Persist
        Write-ColorOutput "已连接输入目录: $INPUT_DRIVE -> $inputPath" "Green"
        
        # 连接输出共享（只读）
        $outputPath = "\\$ServerIP\$SHARE_OUTPUT"
        New-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':') -PSProvider FileSystem -Root $outputPath -Persist
        Write-ColorOutput "已连接输出目录: $OUTPUT_DRIVE -> $outputPath" "Green"
        
        # 验证连接
        if (Test-Path $INPUT_DRIVE) {
            Write-ColorOutput "输入目录连接验证成功" "Green"
        } else {
            throw "输入目录连接验证失败"
        }
        
        if (Test-Path $OUTPUT_DRIVE) {
            Write-ColorOutput "输出目录连接验证成功" "Green"
        } else {
            Write-ColorOutput "输出目录连接验证失败（可能是权限问题）" "Yellow"
        }
        
        return $true
    }
    catch {
        Write-ColorOutput "连接失败: $($_.Exception.Message)" "Red"
        Write-ColorOutput "请检查:" "Yellow"
        Write-ColorOutput "1. 服务器IP地址是否正确" "Yellow"
        Write-ColorOutput "2. 网络连接是否正常" "Yellow"
        Write-ColorOutput "3. 服务器SMB共享是否已启用" "Yellow"
        Write-ColorOutput "4. Windows防火墙设置" "Yellow"
        return $false
    }
}

# 断开网络驱动器
function Disconnect-NetworkDrives {
    Write-ColorOutput "断开网络驱动器连接..." "Yellow"
    
    try {
        if (Get-PSDrive -Name $INPUT_DRIVE.TrimEnd(':') -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $INPUT_DRIVE.TrimEnd(':') -Force
            Write-ColorOutput "已断开输入驱动器: $INPUT_DRIVE" "Green"
        }
        
        if (Get-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':') -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':') -Force
            Write-ColorOutput "已断开输出驱动器: $OUTPUT_DRIVE" "Green"
        }
        
        Write-ColorOutput "网络驱动器断开完成" "Green"
    }
    catch {
        Write-ColorOutput "断开连接时出错: $($_.Exception.Message)" "Red"
    }
}

# 显示连接状态
function Show-ConnectionStatus {
    Write-ColorOutput "当前连接状态:" "Cyan"
    Write-Host ""
    
    # 检查输入驱动器
    if (Test-Path $INPUT_DRIVE) {
        $inputTarget = (Get-PSDrive -Name $INPUT_DRIVE.TrimEnd(':')).DisplayRoot
        Write-ColorOutput "✓ 输入目录: $INPUT_DRIVE -> $inputTarget" "Green"
        
        # 显示输入目录内容
        $inputFiles = Get-ChildItem $INPUT_DRIVE -File | Measure-Object
        Write-ColorOutput "  文件数量: $($inputFiles.Count)" "White"
    } else {
        Write-ColorOutput "✗ 输入目录: $INPUT_DRIVE 未连接" "Red"
    }
    
    # 检查输出驱动器
    if (Test-Path $OUTPUT_DRIVE) {
        $outputTarget = (Get-PSDrive -Name $OUTPUT_DRIVE.TrimEnd(':')).DisplayRoot
        Write-ColorOutput "✓ 输出目录: $OUTPUT_DRIVE -> $outputTarget" "Green"
        
        # 显示输出目录内容
        $outputFolders = Get-ChildItem $OUTPUT_DRIVE -Directory | Measure-Object
        Write-ColorOutput "  整理的影片: $($outputFolders.Count) 个文件夹" "White"
    } else {
        Write-ColorOutput "✗ 输出目录: $OUTPUT_DRIVE 未连接" "Red"
    }
}

# 显示使用说明
function Show-Usage {
    Write-ColorOutput "使用方法:" "Cyan"
    Write-Host ""
    Write-ColorOutput "1. 连接到服务器:" "White"
    Write-ColorOutput "   .\windows-client.ps1 -ServerIP 192.168.1.100 -Action connect" "Gray"
    Write-Host ""
    Write-ColorOutput "2. 自动发现并连接:" "White"
    Write-ColorOutput "   .\windows-client.ps1 -Action connect" "Gray"
    Write-Host ""
    Write-ColorOutput "3. 断开连接:" "White"
    Write-ColorOutput "   .\windows-client.ps1 -Action disconnect" "Gray"
    Write-Host ""
    Write-ColorOutput "4. 查看状态:" "White"
    Write-ColorOutput "   .\windows-client.ps1 -Action status" "Gray"
    Write-Host ""
    Write-ColorOutput "使用步骤:" "Cyan"
    Write-ColorOutput "1. 连接到JavSP服务器" "White"
    Write-ColorOutput "2. 将影片文件复制到 $INPUT_DRIVE 目录" "White"
    Write-ColorOutput "3. 等待服务器自动处理" "White"
    Write-ColorOutput "4. 从 $OUTPUT_DRIVE 目录获取整理结果" "White"
}

# 检查网络共享支持
function Test-SMBSupport {
    Write-ColorOutput "检查SMB支持..." "Yellow"
    
    try {
        $smbFeature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol"
        if ($smbFeature.State -eq "Disabled") {
            Write-ColorOutput "检测到SMB1协议已禁用（这是好的安全做法）" "Green"
        }
        
        # 检查SMB客户端
        $smbClient = Get-SmbClientConfiguration
        if ($smbClient) {
            Write-ColorOutput "SMB客户端配置正常" "Green"
            return $true
        }
    }
    catch {
        Write-ColorOutput "SMB检查失败: $($_.Exception.Message)" "Red"
        Write-ColorOutput "请确保已启用'SMB 1.0/CIFS文件共享支持'功能" "Yellow"
        return $false
    }
}

# 主程序
function Main {
    Show-Header
    
    # 检查SMB支持
    if (-not (Test-SMBSupport)) {
        Write-ColorOutput "SMB支持检查失败，请检查系统配置" "Red"
        return
    }
    
    switch ($Action.ToLower()) {
        "connect" {
            if (-not $ServerIP) {
                $ServerIP = Find-JavSPServer
                if (-not $ServerIP) {
                    $ServerIP = Read-Host "请输入JavSP服务器IP地址"
                }
            }
            
            if (Test-ServerConnection -IP $ServerIP) {
                if (Connect-NetworkDrives -ServerIP $ServerIP) {
                    Write-Host ""
                    Write-ColorOutput "连接成功！" "Green"
                    Write-ColorOutput "输入目录: $INPUT_DRIVE" "White"
                    Write-ColorOutput "输出目录: $OUTPUT_DRIVE" "White"
                    Write-Host ""
                    Write-ColorOutput "现在可以将影片文件复制到 $INPUT_DRIVE 目录进行处理" "Yellow"
                }
            }
        }
        
        "disconnect" {
            Disconnect-NetworkDrives
        }
        
        "status" {
            Show-ConnectionStatus
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