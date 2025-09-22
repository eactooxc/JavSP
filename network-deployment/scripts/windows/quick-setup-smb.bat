@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: JavSP Windows SMB 快速配置脚本

title JavSP SMB 服务器配置

echo ================================
echo   JavSP SMB 服务器快速配置
echo ================================
echo.

:: 检查管理员权限
net session >nul 2>&1
if errorlevel 1 (
    echo 错误: 此脚本需要管理员权限运行
    echo 请右键点击此脚本，选择"以管理员身份运行"
    pause
    exit /b 1
)

echo ✓ 管理员权限检查通过
echo.

:: 获取配置信息
set /p SHARE_BASE="请输入共享目录基础路径 (如 C:\JavSP): "
if "!SHARE_BASE!"=="" set SHARE_BASE=C:\JavSP

set /p USERNAME="请输入JavSP用户名 (默认: javsp): "
if "!USERNAME!"=="" set USERNAME=javsp

set /p PASSWORD="请输入JavSP用户密码: "
if "!PASSWORD!"=="" (
    echo 错误: 必须设置密码
    pause
    exit /b 1
)

echo.
echo 配置信息:
echo 共享基础路径: !SHARE_BASE!
echo 用户名: !USERNAME!
echo.

set /p CONFIRM="确认配置? (Y/N): "
if /i not "!CONFIRM!"=="Y" (
    echo 取消配置
    pause
    exit /b 0
)

echo.
echo 开始配置 JavSP SMB 服务器...
echo.

:: 创建目录
echo 创建共享目录...
mkdir "!SHARE_BASE!\input" 2>nul
mkdir "!SHARE_BASE!\output" 2>nul
echo ✓ 目录创建完成

:: 启用SMB服务
echo 启用SMB服务...
powershell -Command "Set-Service -Name 'LanmanServer' -StartupType Automatic; Start-Service -Name 'LanmanServer'" >nul 2>&1
echo ✓ SMB服务已启用

:: 配置防火墙
echo 配置防火墙规则...
netsh advfirewall firewall set rule group="文件和打印机共享" new enable=Yes >nul 2>&1
netsh advfirewall firewall add rule name="JavSP SMB" dir=in action=allow protocol=TCP localport=445 >nul 2>&1
echo ✓ 防火墙配置完成

:: 创建用户
echo 创建用户: !USERNAME!
net user !USERNAME! !PASSWORD! /add /comment:"JavSP服务用户" /passwordchg:no /expires:never >nul 2>&1
net localgroup users !USERNAME! /add >nul 2>&1
echo ✓ 用户创建完成

:: 设置目录权限
echo 设置目录权限...
icacls "!SHARE_BASE!\input" /grant !USERNAME!:(OI)(CI)F >nul 2>&1
icacls "!SHARE_BASE!\output" /grant !USERNAME!:(OI)(CI)RX >nul 2>&1
echo ✓ 权限设置完成

:: 删除现有共享
net share javsp-input /delete >nul 2>&1
net share javsp-output /delete >nul 2>&1

:: 创建SMB共享
echo 创建SMB共享...
net share javsp-input="!SHARE_BASE!\input" /grant:everyone,change >nul 2>&1
net share javsp-output="!SHARE_BASE!\output" /grant:everyone,read >nul 2>&1
echo ✓ SMB共享创建完成

:: 获取本机IP
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do (
    set IP=%%a
    set IP=!IP: =!
    goto :ip_found
)
:ip_found

echo.
echo ================================
echo   配置完成！
echo ================================
echo.
echo 服务器信息:
echo IP地址: !IP!
echo 输入共享: \\!IP!\javsp-input
echo 输出共享: \\!IP!\javsp-output
echo.
echo 客户端连接命令:
echo Windows: net use J: \\!IP!\javsp-input
echo Mac: mount -t smbfs //!IP!/javsp-input /Volumes/javsp-input
echo.
echo 使用说明:
echo 1. 将视频文件复制到输入共享目录
echo 2. 启动JavSP Docker容器
echo 3. 从输出共享目录获取整理结果
echo.

:: 生成配置文件
echo # JavSP SMB 服务器配置信息 > "!SHARE_BASE!\连接信息.txt"
echo # 生成时间: %date% %time% >> "!SHARE_BASE!\连接信息.txt"
echo. >> "!SHARE_BASE!\连接信息.txt"
echo 服务器IP: !IP! >> "!SHARE_BASE!\连接信息.txt"
echo 输入共享: \\!IP!\javsp-input >> "!SHARE_BASE!\连接信息.txt"
echo 输出共享: \\!IP!\javsp-output >> "!SHARE_BASE!\连接信息.txt"
echo. >> "!SHARE_BASE!\连接信息.txt"
echo Windows连接命令: >> "!SHARE_BASE!\连接信息.txt"
echo   net use J: \\!IP!\javsp-input >> "!SHARE_BASE!\连接信息.txt"
echo   net use K: \\!IP!\javsp-output >> "!SHARE_BASE!\连接信息.txt"
echo. >> "!SHARE_BASE!\连接信息.txt"
echo Mac连接命令: >> "!SHARE_BASE!\连接信息.txt"
echo   mount -t smbfs //!IP!/javsp-input /Volumes/javsp-input >> "!SHARE_BASE!\连接信息.txt"
echo   mount -t smbfs //!IP!/javsp-output /Volumes/javsp-output >> "!SHARE_BASE!\连接信息.txt"

echo 配置信息已保存到: !SHARE_BASE!\连接信息.txt
echo.
pause