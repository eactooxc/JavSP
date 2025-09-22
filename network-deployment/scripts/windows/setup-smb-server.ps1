# JavSP Windows SMB 服务器配置脚本
# 此脚本用于在Windows系统上配置SMB共享，使其他设备能够访问JavSP服务

param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "setup",
    
    [Parameter(Mandatory=$false)]
    [string]$SharePath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "javsp",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = ""
)

# 配置变量
$SCRIPT_NAME = "JavSP Windows SMB 配置器"
$VERSION = "1.0.0"
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

# 启用SMB功能
function Enable-SMBFeatures {
    Write-ColorOutput "启用SMB功能..." "Yellow"
    
    try {
        # 启用SMB服务器
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
        
        # 启动并设置SMB服务自动启动
        Set-Service -Name "LanmanServer" -StartupType Automatic
        Start-Service -Name "LanmanServer"
        
        Write-ColorOutput "✓ SMB功能已启用" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "✗ 启用SMB功能失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 配置防火墙规则
function Configure-Firewall {
    Write-ColorOutput "配置防火墙规则..." "Yellow"
    
    try {
        # 启用文件和打印机共享规则
        Enable-NetFirewallRule -DisplayGroup "文件和打印机共享"
        Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
        
        # 添加特定端口规则
        New-NetFirewallRule -DisplayName "JavSP SMB" -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "JavSP NetBIOS" -Direction Inbound -Protocol TCP -LocalPort 139 -Action Allow -ErrorAction SilentlyContinue
        
        Write-ColorOutput "✓ 防火墙规则已配置" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "✗ 配置防火墙失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 创建JavSP用户
function Create-JavSPUser {
    param([string]$Username, [string]$Password)
    
    Write-ColorOutput "创建JavSP用户: $Username" "Yellow"
    
    try {
        # 检查用户是否已存在
        $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-ColorOutput "用户 $Username 已存在，跳过创建" "Yellow"
            return $true
        }
        
        # 创建密码安全字符串
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        
        # 创建用户
        New-LocalUser -Name $Username -Password $securePassword -Description "JavSP服务用户" -PasswordNeverExpires
        
        # 添加到用户组
        Add-LocalGroupMember -Group "Users" -Member $Username
        
        Write-ColorOutput "✓ 用户 $Username 创建成功" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "✗ 创建用户失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 创建共享目录
function Create-SharedDirectories {
    param([string]$BasePath)
    
    Write-ColorOutput "创建共享目录..." "Yellow"
    
    try {
        $inputPath = Join-Path $BasePath "input"
        $outputPath = Join-Path $BasePath "output"
        
        # 创建目录
        New-Item -ItemType Directory -Path $inputPath -Force | Out-Null
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
        
        Write-ColorOutput "✓ 目录创建完成:" "Green"
        Write-ColorOutput "  输入目录: $inputPath" "White"
        Write-ColorOutput "  输出目录: $outputPath" "White"
        
        return @{
            InputPath = $inputPath
            OutputPath = $outputPath
        }
    }
    catch {
        Write-ColorOutput "✗ 创建目录失败: $($_.Exception.Message)" "Red"
        return $null
    }
}

# 设置目录权限
function Set-DirectoryPermissions {
    param(
        [string]$Path,
        [string]$Username,
        [string]$Permission = "FullControl"
    )
    
    try {
        $acl = Get-Acl $Path
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, $Permission, "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($accessRule)
        Set-Acl $Path $acl
        
        Write-ColorOutput "✓ 权限设置完成: $Path" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "✗ 设置权限失败: $Path - $($_.Exception.Message)" "Red"
        return $false
    }
}

# 创建SMB共享
function Create-SMBShares {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [string]$Username
    )
    
    Write-ColorOutput "创建SMB共享..." "Yellow"
    
    try {
        # 删除现有共享（如果存在）
        Remove-SmbShare -Name $SHARE_INPUT -Force -ErrorAction SilentlyContinue
        Remove-SmbShare -Name $SHARE_OUTPUT -Force -ErrorAction SilentlyContinue
        
        # 创建输入共享（可读写）
        New-SmbShare -Name $SHARE_INPUT -Path $InputPath -Description "JavSP输入目录" -FullAccess $Username, "Everyone"
        Write-ColorOutput "✓ 创建输入共享: \\$env:COMPUTERNAME\$SHARE_INPUT" "Green"
        
        # 创建输出共享（只读）
        New-SmbShare -Name $SHARE_OUTPUT -Path $OutputPath -Description "JavSP输出目录" -ReadAccess $Username, "Everyone"
        Write-ColorOutput "✓ 创建输出共享: \\$env:COMPUTERNAME\$SHARE_OUTPUT" "Green"
        
        return $true
    }
    catch {
        Write-ColorOutput "✗ 创建SMB共享失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 测试SMB共享
function Test-SMBShares {
    Write-ColorOutput "测试SMB共享..." "Yellow"
    
    try {
        $shares = Get-SmbShare -Name $SHARE_INPUT, $SHARE_OUTPUT -ErrorAction SilentlyContinue
        
        if ($shares.Count -eq 2) {
            Write-ColorOutput "✓ SMB共享测试通过" "Green"
            
            # 显示共享信息
            foreach ($share in $shares) {
                Write-ColorOutput "  共享名: $($share.Name)" "White"
                Write-ColorOutput "  路径: $($share.Path)" "White"
                Write-ColorOutput "  描述: $($share.Description)" "White"
                Write-Host ""
            }
            
            return $true
        }
        else {
            Write-ColorOutput "✗ SMB共享不完整" "Red"
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ SMB共享测试失败: $($_.Exception.Message)" "Red"
        return $false
    }
}

# 显示连接信息
function Show-ConnectionInfo {
    Write-ColorOutput "连接信息:" "Cyan"
    Write-Host ""
    
    # 获取本机IP地址
    $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -eq "Dhcp"}
    
    foreach ($ip in $ipAddresses) {
        Write-ColorOutput "服务器IP: $($ip.IPAddress)" "Green"
        Write-ColorOutput "输入共享: \\$($ip.IPAddress)\$SHARE_INPUT" "White"
        Write-ColorOutput "输出共享: \\$($ip.IPAddress)\$SHARE_OUTPUT" "White"
        Write-Host ""
    }
    
    Write-ColorOutput "客户端连接命令:" "Yellow"
    Write-ColorOutput "Windows: net use J: \\<服务器IP>\$SHARE_INPUT" "Gray"
    Write-ColorOutput "Mac: mount -t smbfs //<服务器IP>/$SHARE_INPUT /Volumes/javsp-input" "Gray"
}

# 生成配置文件
function Generate-ConfigFile {
    param([string]$BasePath)
    
    $configContent = @"
# JavSP Windows SMB 服务器配置
# 生成时间: $(Get-Date)

[SMB设置]
输入共享名: $SHARE_INPUT
输出共享名: $SHARE_OUTPUT
基础路径: $BasePath

[网络信息]
"@
    
    # 添加IP地址信息
    $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -eq "Dhcp"}
    foreach ($ip in $ipAddresses) {
        $configContent += "`n服务器IP: $($ip.IPAddress)"
    }
    
    $configContent += @"

[客户端连接命令]
Windows命令行:
  连接输入: net use J: \\<服务器IP>\$SHARE_INPUT
  连接输出: net use K: \\<服务器IP>\$SHARE_OUTPUT
  断开连接: net use J: /delete && net use K: /delete

Mac命令行:
  挂载输入: mount -t smbfs //<服务器IP>/$SHARE_INPUT /Volumes/javsp-input
  挂载输出: mount -t smbfs //<服务器IP>/$SHARE_OUTPUT /Volumes/javsp-output
  卸载: umount /Volumes/javsp-input && umount /Volumes/javsp-output

[使用说明]
1. 将视频文件复制到输入共享目录
2. 启动JavSP Docker容器进行处理
3. 从输出共享目录获取整理结果
"@
    
    $configFile = Join-Path $BasePath "javsp-smb-config.txt"
    $configContent | Out-File -FilePath $configFile -Encoding UTF8
    
    Write-ColorOutput "✓ 配置文件已生成: $configFile" "Green"
}

# 移除SMB配置
function Remove-SMBConfiguration {
    Write-ColorOutput "移除SMB配置..." "Yellow"
    
    try {
        # 删除SMB共享
        Remove-SmbShare -Name $SHARE_INPUT -Force -ErrorAction SilentlyContinue
        Remove-SmbShare -Name $SHARE_OUTPUT -Force -ErrorAction SilentlyContinue
        
        Write-ColorOutput "✓ SMB共享已删除" "Green"
        
        # 可选：删除用户（询问用户）
        $deleteUser = Read-Host "是否删除JavSP用户 ($Username)? (y/N)"
        if ($deleteUser -eq "y" -or $deleteUser -eq "Y") {
            Remove-LocalUser -Name $Username -ErrorAction SilentlyContinue
            Write-ColorOutput "✓ 用户已删除" "Green"
        }
        
        Write-ColorOutput "SMB配置移除完成" "Green"
    }
    catch {
        Write-ColorOutput "✗ 移除配置失败: $($_.Exception.Message)" "Red"
    }
}

# 显示帮助信息
function Show-Help {
    Write-ColorOutput "使用方法:" "Cyan"
    Write-Host ""
    Write-ColorOutput "设置SMB服务器:" "White"
    Write-ColorOutput "  .\setup-smb-server.ps1 -Action setup -SharePath C:\JavSP" "Gray"
    Write-Host ""
    Write-ColorOutput "移除SMB配置:" "White"
    Write-ColorOutput "  .\setup-smb-server.ps1 -Action remove" "Gray"
    Write-Host ""
    Write-ColorOutput "测试SMB配置:" "White"
    Write-ColorOutput "  .\setup-smb-server.ps1 -Action test" "Gray"
    Write-Host ""
    Write-ColorOutput "参数说明:" "Cyan"
    Write-ColorOutput "  -Action: setup(设置) | remove(移除) | test(测试)" "White"
    Write-ColorOutput "  -SharePath: 共享目录基础路径" "White"
    Write-ColorOutput "  -Username: JavSP用户名(默认: javsp)" "White"
    Write-ColorOutput "  -Password: JavSP用户密码" "White"
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
        "setup" {
            if (-not $SharePath) {
                $SharePath = Read-Host "请输入共享目录基础路径 (如: C:\JavSP)"
            }
            
            if (-not $Password) {
                $Password = Read-Host "请输入JavSP用户密码" -AsSecureString
                $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
            }
            
            Write-Host ""
            Write-ColorOutput "开始配置JavSP SMB服务器..." "Green"
            Write-Host ""
            
            # 执行配置步骤
            if ((Enable-SMBFeatures) -and
                (Configure-Firewall) -and
                (Create-JavSPUser -Username $Username -Password $Password)) {
                
                $directories = Create-SharedDirectories -BasePath $SharePath
                if ($directories) {
                    if ((Set-DirectoryPermissions -Path $directories.InputPath -Username $Username -Permission "FullControl") -and
                        (Set-DirectoryPermissions -Path $directories.OutputPath -Username $Username -Permission "ReadAndExecute") -and
                        (Create-SMBShares -InputPath $directories.InputPath -OutputPath $directories.OutputPath -Username $Username)) {
                        
                        Write-Host ""
                        Write-ColorOutput "🎉 JavSP SMB服务器配置完成！" "Green"
                        Write-Host ""
                        
                        Generate-ConfigFile -BasePath $SharePath
                        Show-ConnectionInfo
                    }
                }
            }
        }
        
        "remove" {
            Remove-SMBConfiguration
        }
        
        "test" {
            Test-SMBShares
            Show-ConnectionInfo
        }
        
        "help" {
            Show-Help
        }
        
        default {
            Write-ColorOutput "未知操作: $Action" "Red"
            Show-Help
        }
    }
}

# 执行主程序
Main