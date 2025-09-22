@echo off
chcp 65001 >nul

:: JavSP Windows 客户端断开连接脚本

title JavSP 断开连接

echo ================================
echo   JavSP 断开网络驱动器
echo ================================
echo.

set INPUT_DRIVE=J:
set OUTPUT_DRIVE=K:

echo 正在断开网络驱动器连接...
echo.

:: 断开输入驱动器
net use !INPUT_DRIVE! /delete >nul 2>&1
if errorlevel 1 (
    echo - 输入驱动器 !INPUT_DRIVE! 未连接或已断开
) else (
    echo ✓ 已断开输入驱动器: !INPUT_DRIVE!
)

:: 断开输出驱动器
net use !OUTPUT_DRIVE! /delete >nul 2>&1
if errorlevel 1 (
    echo - 输出驱动器 !OUTPUT_DRIVE! 未连接或已断开
) else (
    echo ✓ 已断开输出驱动器: !OUTPUT_DRIVE!
)

echo.
echo 所有网络驱动器已断开连接
echo.
pause