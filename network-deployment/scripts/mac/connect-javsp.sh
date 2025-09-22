#!/bin/bash

# JavSP Mac 简化连接脚本
# 使用方法: ./connect-javsp.sh [服务器IP]

MOUNT_BASE="/Volumes"
INPUT_MOUNT="$MOUNT_BASE/javsp-input"
OUTPUT_MOUNT="$MOUNT_BASE/javsp-output"

echo "================================"
echo "  JavSP Mac 客户端 v1.0"
echo "================================"
echo

# 获取服务器IP
if [[ -z "$1" ]]; then
    read -p "请输入JavSP服务器IP地址: " SERVER_IP
else
    SERVER_IP=$1
fi

if [[ -z "$SERVER_IP" ]]; then
    echo "错误: 请提供服务器IP地址"
    exit 1
fi

echo "正在连接到服务器: $SERVER_IP"
echo

# 测试网络连通性
if ! ping -c 2 "$SERVER_IP" &> /dev/null; then
    echo "错误: 无法ping通服务器 $SERVER_IP"
    echo "请检查:"
    echo "1. 服务器IP地址是否正确"
    echo "2. 网络连接是否正常"
    echo "3. 服务器是否已启动"
    exit 1
fi

echo "✓ 网络连通性测试通过"

# 创建挂载点
echo "创建挂载点..."
sudo mkdir -p "$INPUT_MOUNT"
sudo mkdir -p "$OUTPUT_MOUNT"

# 卸载现有挂载
umount "$INPUT_MOUNT" 2>/dev/null || true
umount "$OUTPUT_MOUNT" 2>/dev/null || true

# 挂载输入共享
echo "正在挂载输入目录..."
if mount -t smbfs "//$SERVER_IP/javsp-input" "$INPUT_MOUNT" 2>/dev/null || \
   mount -t smbfs "//guest@$SERVER_IP/javsp-input" "$INPUT_MOUNT" 2>/dev/null; then
    echo "✓ 输入目录挂载成功: $INPUT_MOUNT"
else
    echo "错误: 无法挂载输入共享"
    echo "请检查服务器SMB共享配置"
    exit 1
fi

# 挂载输出共享
echo "正在挂载输出目录..."
if mount -t smbfs "//$SERVER_IP/javsp-output" "$OUTPUT_MOUNT" 2>/dev/null || \
   mount -t smbfs "//guest@$SERVER_IP/javsp-output" "$OUTPUT_MOUNT" 2>/dev/null; then
    echo "✓ 输出目录挂载成功: $OUTPUT_MOUNT"
else
    echo "警告: 输出共享挂载失败，但这可能是正常的"
    echo "输出共享可能需要处理完成后才能访问"
fi

echo
echo "================================"
echo "   连接完成！"
echo "================================"
echo
echo "使用方法:"
echo "1. 将影片文件复制到 $INPUT_MOUNT 目录"
echo "2. 等待服务器自动处理（通常需要几分钟）"
echo "3. 处理完成后从 $OUTPUT_MOUNT 目录获取结果"
echo

echo "当前连接状态:"
if mount | grep -q "$INPUT_MOUNT"; then
    echo "✓ 输入目录: $INPUT_MOUNT 已挂载"
else
    echo "✗ 输入目录: $INPUT_MOUNT 挂载失败"
fi

if mount | grep -q "$OUTPUT_MOUNT"; then
    echo "✓ 输出目录: $OUTPUT_MOUNT 已挂载"
else
    echo "✗ 输出目录: $OUTPUT_MOUNT 未挂载或无访问权限"
fi

echo
echo "要断开连接，请运行: ./disconnect-javsp.sh"
echo

# 在Finder中打开输入目录
if [[ -d "$INPUT_MOUNT" ]]; then
    open "$INPUT_MOUNT"
    echo "已在Finder中打开输入目录"
fi