@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: JavSP Windows 客户端快速连接脚本
:: 使用方法: connect-javsp.bat [服务器IP]

title JavSP Windows 客户端

echo ================================
echo   JavSP Windows 客户端 v1.0
echo ================================
echo.

:: 配置变量
set INPUT_DRIVE=J:
set OUTPUT_DRIVE=K:
set SHARE_INPUT=javsp-input
set SHARE_OUTPUT=javsp-output

:: 获取服务器IP
if "%1"=="" (
    set /p SERVER_IP="请输入JavSP服务器IP地址: "
) else (
    set SERVER_IP=%1
)

if "!SERVER_IP!"=="" (
    echo 错误: 请提供服务器IP地址
    pause
    exit /b 1
)

echo.
echo 正在连接到服务器: !SERVER_IP!
echo.

:: 测试网络连通性
ping -n 2 !SERVER_IP! >nul
if errorlevel 1 (
    echo 错误: 无法ping通服务器 !SERVER_IP!
    echo 请检查:
    echo 1. 服务器IP地址是否正确
    echo 2. 网络连接是否正常
    echo 3. 服务器是否已启动
    pause
    exit /b 1
)

echo ✓ 网络连通性测试通过

:: 断开现有连接
net use !INPUT_DRIVE! /delete >nul 2>&1
net use !OUTPUT_DRIVE! /delete >nul 2>&1

:: 连接输入共享
echo 正在连接输入目录...
net use !INPUT_DRIVE! \\!SERVER_IP!\!SHARE_INPUT!
if errorlevel 1 (
    echo 错误: 无法连接输入共享
    echo 请检查服务器SMB共享配置
    pause
    exit /b 1
)
echo ✓ 输入目录连接成功: !INPUT_DRIVE!

:: 连接输出共享
echo 正在连接输出目录...
net use !OUTPUT_DRIVE! \\!SERVER_IP!\!SHARE_OUTPUT!
if errorlevel 1 (
    echo 警告: 输出共享连接失败，但这可能是正常的
    echo 输出共享可能需要处理完成后才能访问
) else (
    echo ✓ 输出目录连接成功: !OUTPUT_DRIVE!
)

echo.
echo ================================
echo   连接完成！
echo ================================
echo.
echo 使用方法:
echo 1. 将影片文件复制到 !INPUT_DRIVE!\ 目录
echo 2. 等待服务器自动处理（通常需要几分钟）
echo 3. 处理完成后从 !OUTPUT_DRIVE!\ 目录获取结果
echo.
echo 当前连接状态:
if exist !INPUT_DRIVE!\ (
    echo ✓ 输入目录: !INPUT_DRIVE! 已连接
) else (
    echo ✗ 输入目录: !INPUT_DRIVE! 连接失败
)

if exist !OUTPUT_DRIVE!\ (
    echo ✓ 输出目录: !OUTPUT_DRIVE! 已连接
) else (
    echo ✗ 输出目录: !OUTPUT_DRIVE! 未连接或无访问权限
)

echo.
echo 要断开连接，请运行: disconnect-javsp.bat
echo.
pause