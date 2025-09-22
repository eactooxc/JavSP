#!/bin/bash

# JavSP Mac 断开连接脚本

echo "================================"
echo "   JavSP 断开网络挂载"
echo "================================"
echo

MOUNT_BASE="/Volumes"
INPUT_MOUNT="$MOUNT_BASE/javsp-input"
OUTPUT_MOUNT="$MOUNT_BASE/javsp-output"

echo "正在断开网络挂载..."
echo

# 卸载输入挂载
if mount | grep -q "$INPUT_MOUNT"; then
    if umount "$INPUT_MOUNT" 2>/dev/null; then
        echo "✓ 已卸载输入目录: $INPUT_MOUNT"
    else
        echo "✗ 卸载输入目录失败，尝试强制卸载..."
        sudo umount -f "$INPUT_MOUNT" 2>/dev/null && echo "✓ 强制卸载成功" || echo "✗ 强制卸载失败"
    fi
else
    echo "- 输入目录未挂载或已断开"
fi

# 卸载输出挂载
if mount | grep -q "$OUTPUT_MOUNT"; then
    if umount "$OUTPUT_MOUNT" 2>/dev/null; then
        echo "✓ 已卸载输出目录: $OUTPUT_MOUNT"
    else
        echo "✗ 卸载输出目录失败，尝试强制卸载..."
        sudo umount -f "$OUTPUT_MOUNT" 2>/dev/null && echo "✓ 强制卸载成功" || echo "✗ 强制卸载失败"
    fi
else
    echo "- 输出目录未挂载或已断开"
fi

# 清理空挂载点
[[ -d "$INPUT_MOUNT" ]] && rmdir "$INPUT_MOUNT" 2>/dev/null
[[ -d "$OUTPUT_MOUNT" ]] && rmdir "$OUTPUT_MOUNT" 2>/dev/null

echo
echo "所有网络挂载已断开连接"
echo