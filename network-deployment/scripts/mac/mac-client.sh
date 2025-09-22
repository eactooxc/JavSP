#!/bin/bash

# JavSP Mac 客户端连接脚本
# 帮助Mac用户连接到JavSP网络服务器

# 配置变量
SCRIPT_NAME="JavSP Mac 客户端"
VERSION="1.0.0"
MOUNT_BASE="/Volumes"
INPUT_MOUNT="$MOUNT_BASE/javsp-input"
OUTPUT_MOUNT="$MOUNT_BASE/javsp-output"
SHARE_INPUT="javsp-input"
SHARE_OUTPUT="javsp-output"

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_error() {
    print_color $RED "错误: $1"
}

print_success() {
    print_color $GREEN "✓ $1"
}

print_warning() {
    print_color $YELLOW "⚠ $1"
}

print_info() {
    print_color $BLUE "$1"
}

print_header() {
    echo
    print_color $CYAN "================================"
    print_color $CYAN "  $SCRIPT_NAME v$VERSION"
    print_color $CYAN "================================"
    echo
}

# 显示使用方法
show_usage() {
    echo "使用方法:"
    echo "  $0 connect [服务器IP]     - 连接到JavSP服务器"
    echo "  $0 disconnect           - 断开所有连接"
    echo "  $0 status               - 显示连接状态"
    echo "  $0 find                 - 自动搜索服务器"
    echo "  $0 help                 - 显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 connect 192.168.1.100"
    echo "  $0 connect"
    echo "  $0 status"
}

# 检查依赖
check_dependencies() {
    print_info "检查系统依赖..."
    
    # 检查 osascript (AppleScript)
    if ! command -v osascript &> /dev/null; then
        print_error "osascript 未找到，需要macOS系统"
        return 1
    fi
    
    # 检查 ping
    if ! command -v ping &> /dev/null; then
        print_error "ping 命令未找到"
        return 1
    fi
    
    # 检查 mount
    if ! command -v mount &> /dev/null; then
        print_error "mount 命令未找到"
        return 1
    fi
    
    print_success "系统依赖检查通过"
    return 0
}

# 自动发现JavSP服务器
find_javsp_server() {
    print_info "正在搜索JavSP服务器..."
    
    # 获取本地网络信息
    local local_ip=$(route get default | grep interface | awk '{print $2}' | head -1 | xargs ifconfig | grep inet | grep -v inet6 | awk '{print $2}' | head -1)
    
    if [[ -z "$local_ip" ]]; then
        print_error "无法获取本地IP地址"
        return 1
    fi
    
    # 提取网段
    local subnet=$(echo $local_ip | cut -d'.' -f1-3)
    print_info "扫描网段: ${subnet}.*"
    
    # 扫描网段
    for i in {1..254}; do
        local test_ip="${subnet}.${i}"
        
        # 快速ping测试
        if ping -c 1 -W 1000 "$test_ip" &> /dev/null; then
            # 检查SMB服务
            if nc -z -w 2 "$test_ip" 445 2>/dev/null; then
                # 尝试列出共享
                if smbutil view "//$test_ip" 2>/dev/null | grep -q "$SHARE_INPUT"; then
                    print_success "找到JavSP服务器: $test_ip"
                    echo "$test_ip"
                    return 0
                fi
            fi
        fi
    done
    
    print_warning "未找到JavSP服务器"
    return 1
}

# 测试服务器连接
test_server_connection() {
    local server_ip=$1
    
    print_info "测试服务器连接: $server_ip"
    
    # 测试网络连通性
    if ! ping -c 2 "$server_ip" &> /dev/null; then
        print_error "无法ping通服务器: $server_ip"
        return 1
    fi
    
    print_success "网络连通性测试通过"
    
    # 测试SMB端口
    if ! nc -z -w 5 "$server_ip" 445 2>/dev/null; then
        print_error "SMB服务连接失败 (端口445)"
        print_info "请检查:"
        print_info "1. 服务器SMB服务是否已启动"
        print_info "2. 防火墙是否允许445端口"
        return 1
    fi
    
    print_success "SMB服务连接正常"
    return 0
}

# 创建挂载点
create_mount_points() {
    print_info "创建挂载点..."
    
    if [[ ! -d "$INPUT_MOUNT" ]]; then
        sudo mkdir -p "$INPUT_MOUNT"
        print_success "创建输入挂载点: $INPUT_MOUNT"
    fi
    
    if [[ ! -d "$OUTPUT_MOUNT" ]]; then
        sudo mkdir -p "$OUTPUT_MOUNT"
        print_success "创建输出挂载点: $OUTPUT_MOUNT"
    fi
}

# 挂载SMB共享
mount_smb_shares() {
    local server_ip=$1
    
    print_info "挂载SMB共享..."
    
    # 卸载现有挂载
    unmount_shares_silent
    
    # 挂载输入共享
    print_info "挂载输入共享..."
    if mount -t smbfs "//$server_ip/$SHARE_INPUT" "$INPUT_MOUNT" 2>/dev/null; then
        print_success "输入共享挂载成功: $INPUT_MOUNT"
    else
        # 尝试使用guest账户
        if mount -t smbfs "//guest@$server_ip/$SHARE_INPUT" "$INPUT_MOUNT" 2>/dev/null; then
            print_success "输入共享挂载成功 (guest): $INPUT_MOUNT"
        else
            print_error "输入共享挂载失败"
            return 1
        fi
    fi
    
    # 挂载输出共享
    print_info "挂载输出共享..."
    if mount -t smbfs "//$server_ip/$SHARE_OUTPUT" "$OUTPUT_MOUNT" 2>/dev/null; then
        print_success "输出共享挂载成功: $OUTPUT_MOUNT"
    else
        # 尝试使用guest账户
        if mount -t smbfs "//guest@$server_ip/$SHARE_OUTPUT" "$OUTPUT_MOUNT" 2>/dev/null; then
            print_success "输出共享挂载成功 (guest): $OUTPUT_MOUNT"
        else
            print_warning "输出共享挂载失败（可能是权限问题）"
        fi
    fi
    
    return 0
}

# 静默卸载共享
unmount_shares_silent() {
    umount "$INPUT_MOUNT" 2>/dev/null || true
    umount "$OUTPUT_MOUNT" 2>/dev/null || true
}

# 卸载共享
unmount_shares() {
    print_info "卸载SMB共享..."
    
    if mount | grep -q "$INPUT_MOUNT"; then
        if umount "$INPUT_MOUNT" 2>/dev/null; then
            print_success "已卸载输入共享: $INPUT_MOUNT"
        else
            print_error "卸载输入共享失败"
        fi
    else
        print_info "输入共享未挂载"
    fi
    
    if mount | grep -q "$OUTPUT_MOUNT"; then
        if umount "$OUTPUT_MOUNT" 2>/dev/null; then
            print_success "已卸载输出共享: $OUTPUT_MOUNT"
        else
            print_error "卸载输出共享失败"
        fi
    else
        print_info "输出共享未挂载"
    fi
    
    # 清理空目录
    [[ -d "$INPUT_MOUNT" ]] && rmdir "$INPUT_MOUNT" 2>/dev/null || true
    [[ -d "$OUTPUT_MOUNT" ]] && rmdir "$OUTPUT_MOUNT" 2>/dev/null || true
}

# 显示连接状态
show_connection_status() {
    print_color $CYAN "当前连接状态:"
    echo
    
    # 检查输入挂载
    if mount | grep -q "$INPUT_MOUNT"; then
        local input_server=$(mount | grep "$INPUT_MOUNT" | awk -F'on' '{print $1}' | tr -d ' ')
        print_success "输入目录: $INPUT_MOUNT -> $input_server"
        
        # 显示文件数量
        if [[ -d "$INPUT_MOUNT" ]]; then
            local file_count=$(find "$INPUT_MOUNT" -type f 2>/dev/null | wc -l | tr -d ' ')
            print_info "  文件数量: $file_count"
        fi
    else
        print_error "输入目录: $INPUT_MOUNT 未挂载"
    fi
    
    # 检查输出挂载
    if mount | grep -q "$OUTPUT_MOUNT"; then
        local output_server=$(mount | grep "$OUTPUT_MOUNT" | awk -F'on' '{print $1}' | tr -d ' ')
        print_success "输出目录: $OUTPUT_MOUNT -> $output_server"
        
        # 显示文件夹数量
        if [[ -d "$OUTPUT_MOUNT" ]]; then
            local folder_count=$(find "$OUTPUT_MOUNT" -type d -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
            print_info "  整理的影片: $folder_count 个文件夹"
        fi
    else
        print_error "输出目录: $OUTPUT_MOUNT 未挂载"
    fi
}

# 连接到服务器
connect_to_server() {
    local server_ip=$1
    
    # 如果没有提供IP，尝试自动发现
    if [[ -z "$server_ip" ]]; then
        server_ip=$(find_javsp_server)
        if [[ -z "$server_ip" ]]; then
            echo
            read -p "请输入JavSP服务器IP地址: " server_ip
        fi
    fi
    
    if [[ -z "$server_ip" ]]; then
        print_error "请提供有效的服务器IP地址"
        return 1
    fi
    
    # 测试连接
    if ! test_server_connection "$server_ip"; then
        return 1
    fi
    
    # 创建挂载点
    create_mount_points
    
    # 挂载共享
    if mount_smb_shares "$server_ip"; then
        echo
        print_success "连接成功！"
        print_info "输入目录: $INPUT_MOUNT"
        print_info "输出目录: $OUTPUT_MOUNT"
        echo
        print_color $YELLOW "现在可以将影片文件复制到 $INPUT_MOUNT 目录进行处理"
        
        # 在Finder中打开输入目录
        if [[ -d "$INPUT_MOUNT" ]]; then
            open "$INPUT_MOUNT"
            print_info "已在Finder中打开输入目录"
        fi
        
        return 0
    else
        print_error "连接失败"
        return 1
    fi
}

# 主程序
main() {
    local action=${1:-help}
    local server_ip=$2
    
    print_header
    
    # 检查依赖
    if ! check_dependencies; then
        exit 1
    fi
    
    case "$action" in
        "connect")
            connect_to_server "$server_ip"
            ;;
        "disconnect")
            unmount_shares
            ;;
        "status")
            show_connection_status
            ;;
        "find")
            find_javsp_server
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 检查是否以root权限运行某些操作
if [[ "$1" == "connect" ]] && [[ $EUID -ne 0 ]] && [[ ! -w "/Volumes" ]]; then
    print_warning "可能需要管理员权限来创建挂载点"
    print_info "如果遇到权限错误，请使用: sudo $0 $@"
fi

# 执行主程序
main "$@"