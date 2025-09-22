#!/bin/bash

# JavSP Mac/Linux Samba 服务器配置脚本
# 此脚本用于在Mac/Linux系统上配置Samba共享

# 配置变量
SCRIPT_NAME="JavSP Samba 配置器"
VERSION="1.0.0"
SHARE_INPUT="javsp-input"
SHARE_OUTPUT="javsp-output"
DEFAULT_USER="javsp"
SMB_CONF="/usr/local/etc/smb.conf"
BACKUP_SUFFIX=".javsp.backup"

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        SMB_CONF="/usr/local/etc/smb.conf"
        SERVICE_CMD="brew services"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        SMB_CONF="/etc/samba/smb.conf"
        SERVICE_CMD="systemctl"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        SMB_CONF="/etc/samba/smb.conf"
        SERVICE_CMD="systemctl"
    else
        OS="unknown"
        echo "警告: 未识别的操作系统，使用默认配置"
    fi
}

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        echo "请使用: sudo $0 $@"
        exit 1
    fi
}

# 安装Samba
install_samba() {
    print_info "检查并安装Samba..."
    
    case $OS in
        "macos")
            if ! command -v brew &> /dev/null; then
                print_error "需要先安装Homebrew"
                print_info "请访问: https://brew.sh/"
                return 1
            fi
            
            if ! brew list samba &> /dev/null; then
                print_info "安装Samba..."
                brew install samba
            fi
            ;;
        "debian")
            if ! command -v smbd &> /dev/null; then
                print_info "安装Samba..."
                apt update
                apt install -y samba samba-common-bin
            fi
            ;;
        "rhel")
            if ! command -v smbd &> /dev/null; then
                print_info "安装Samba..."
                yum install -y samba samba-client
            fi
            ;;
        *)
            print_warning "请手动安装Samba"
            return 1
            ;;
    esac
    
    if command -v smbd &> /dev/null; then
        print_success "Samba已安装"
        return 0
    else
        print_error "Samba安装失败"
        return 1
    fi
}

# 创建JavSP用户
create_javsp_user() {
    local username=${1:-$DEFAULT_USER}
    local password=$2
    
    print_info "创建用户: $username"
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        print_warning "用户 $username 已存在"
    else
        # 创建系统用户
        case $OS in
            "macos")
                dscl . -create /Users/$username
                dscl . -create /Users/$username UserShell /bin/bash
                dscl . -create /Users/$username RealName "JavSP Service User"
                dscl . -create /Users/$username UniqueID 1001
                dscl . -create /Users/$username PrimaryGroupID 1000
                dscl . -create /Users/$username NFSHomeDirectory /Users/$username
                dscl . -passwd /Users/$username $password
                ;;
            *)
                useradd -r -s /bin/false -c "JavSP Service User" $username
                echo "$username:$password" | chpasswd
                ;;
        esac
        print_success "用户 $username 创建成功"
    fi
    
    # 添加到Samba用户数据库
    print_info "配置Samba用户..."
    echo -e "$password\n$password" | smbpasswd -a $username
    smbpasswd -e $username
    
    print_success "Samba用户配置完成"
}

# 创建共享目录
create_shared_directories() {
    local base_path=$1
    local username=${2:-$DEFAULT_USER}
    
    print_info "创建共享目录..."
    
    local input_path="$base_path/input"
    local output_path="$base_path/output"
    
    # 创建目录
    mkdir -p "$input_path"
    mkdir -p "$output_path"
    
    # 设置权限
    chown -R $username:$username "$base_path"
    chmod 755 "$base_path"
    chmod 775 "$input_path"   # 可读写
    chmod 755 "$output_path"  # 只读
    
    print_success "目录创建完成:"
    print_info "  输入目录: $input_path"
    print_info "  输出目录: $output_path"
    
    echo "$input_path:$output_path"
}

# 备份Samba配置
backup_smb_conf() {
    if [[ -f "$SMB_CONF" ]]; then
        cp "$SMB_CONF" "${SMB_CONF}${BACKUP_SUFFIX}"
        print_success "配置文件已备份: ${SMB_CONF}${BACKUP_SUFFIX}"
    fi
}

# 配置Samba
configure_samba() {
    local input_path=$1
    local output_path=$2
    local username=${3:-$DEFAULT_USER}
    
    print_info "配置Samba共享..."
    
    # 备份原配置
    backup_smb_conf
    
    # 创建基础配置目录
    mkdir -p "$(dirname "$SMB_CONF")"
    
    # 生成Samba配置
    cat > "$SMB_CONF" << EOF
# JavSP Samba 配置文件
# 生成时间: $(date)

[global]
    # 服务器设置
    server string = JavSP Media Server
    workgroup = WORKGROUP
    netbios name = JAVSP-SERVER
    
    # 安全设置
    security = user
    map to guest = never
    guest account = nobody
    
    # 网络设置
    bind interfaces only = no
    interfaces = lo 0.0.0.0/0
    
    # 协议设置
    server min protocol = SMB2
    client min protocol = SMB2
    
    # 日志设置
    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 1
    
    # 性能优化
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
    read raw = yes
    write raw = yes
    
    # 禁用打印机共享
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes

# JavSP 输入共享 (可读写)
[$SHARE_INPUT]
    comment = JavSP Input Directory
    path = $input_path
    valid users = $username
    public = no
    writable = yes
    printable = no
    create mask = 0664
    directory mask = 0775
    force user = $username
    force group = $username

# JavSP 输出共享 (只读)
[$SHARE_OUTPUT]
    comment = JavSP Output Directory
    path = $output_path
    valid users = $username
    public = no
    writable = no
    printable = no
    create mask = 0644
    directory mask = 0755
    force user = $username
    force group = $username
EOF
    
    print_success "Samba配置文件已生成: $SMB_CONF"
}

# 启动Samba服务
start_samba_service() {
    print_info "启动Samba服务..."
    
    case $OS in
        "macos")
            brew services start samba
            ;;
        "debian"|"rhel")
            systemctl enable smbd
            systemctl start smbd
            systemctl enable nmbd
            systemctl start nmbd
            ;;
    esac
    
    # 验证服务状态
    sleep 2
    if pgrep smbd > /dev/null; then
        print_success "Samba服务启动成功"
        return 0
    else
        print_error "Samba服务启动失败"
        return 1
    fi
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    case $OS in
        "macos")
            # macOS防火墙配置
            print_warning "请手动配置macOS防火墙允许Samba服务"
            ;;
        "debian")
            if command -v ufw &> /dev/null; then
                ufw allow samba
                print_success "UFW防火墙规则已添加"
            fi
            ;;
        "rhel")
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-service=samba
                firewall-cmd --reload
                print_success "Firewalld规则已添加"
            fi
            ;;
    esac
}

# 测试Samba配置
test_samba_config() {
    print_info "测试Samba配置..."
    
    # 测试配置文件语法
    if testparm -s "$SMB_CONF" &> /dev/null; then
        print_success "Samba配置文件语法正确"
    else
        print_error "Samba配置文件语法错误"
        print_info "运行以下命令查看详细错误:"
        print_info "testparm $SMB_CONF"
        return 1
    fi
    
    # 测试共享列表
    if smbclient -L localhost -U% &> /dev/null; then
        print_success "Samba服务响应正常"
    else
        print_warning "Samba服务可能未正常启动"
    fi
    
    return 0
}

# 显示连接信息
show_connection_info() {
    print_color $CYAN "连接信息:"
    echo
    
    # 获取IP地址
    local ip_addresses=$(hostname -I 2>/dev/null || ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d':' -f2)
    
    for ip in $ip_addresses; do
        [[ -n "$ip" ]] && print_success "服务器IP: $ip"
    done
    
    echo
    print_info "共享信息:"
    print_info "  输入共享: //$ip/$SHARE_INPUT"
    print_info "  输出共享: //$ip/$SHARE_OUTPUT"
    
    echo
    print_color $YELLOW "客户端连接命令:"
    print_info "Windows:"
    print_info "  net use J: \\\\$ip\\$SHARE_INPUT"
    print_info "  net use K: \\\\$ip\\$SHARE_OUTPUT"
    
    print_info "Mac:"
    print_info "  mount -t smbfs //$ip/$SHARE_INPUT /Volumes/javsp-input"
    print_info "  mount -t smbfs //$ip/$SHARE_OUTPUT /Volumes/javsp-output"
    
    print_info "Linux:"
    print_info "  mount -t cifs //$ip/$SHARE_INPUT /mnt/javsp-input -o username=$DEFAULT_USER"
    print_info "  mount -t cifs //$ip/$SHARE_OUTPUT /mnt/javsp-output -o username=$DEFAULT_USER"
}

# 生成配置信息文件
generate_config_file() {
    local base_path=$1
    local config_file="$base_path/samba-config.txt"
    
    local ip=$(hostname -I | awk '{print $1}')
    
    cat > "$config_file" << EOF
# JavSP Samba 服务器配置信息
# 生成时间: $(date)

[服务器信息]
IP地址: $ip
输入共享: //$ip/$SHARE_INPUT
输出共享: //$ip/$SHARE_OUTPUT

[客户端连接命令]
Windows:
  连接输入: net use J: \\\\$ip\\$SHARE_INPUT
  连接输出: net use K: \\\\$ip\\$SHARE_OUTPUT
  断开连接: net use J: /delete && net use K: /delete

Mac:
  挂载输入: mount -t smbfs //$ip/$SHARE_INPUT /Volumes/javsp-input
  挂载输出: mount -t smbfs //$ip/$SHARE_OUTPUT /Volumes/javsp-output
  卸载: umount /Volumes/javsp-input && umount /Volumes/javsp-output

Linux:
  挂载输入: mount -t cifs //$ip/$SHARE_INPUT /mnt/javsp-input -o username=$DEFAULT_USER
  挂载输出: mount -t cifs //$ip/$SHARE_OUTPUT /mnt/javsp-output -o username=$DEFAULT_USER

[使用说明]
1. 将视频文件复制到输入共享目录
2. 启动JavSP Docker容器进行处理
3. 从输出共享目录获取整理结果

[故障排除]
- 检查防火墙设置
- 确认Samba服务运行状态: systemctl status smbd
- 测试配置文件: testparm $SMB_CONF
- 查看日志: tail -f /var/log/samba/log.smbd
EOF
    
    print_success "配置信息已保存: $config_file"
}

# 移除Samba配置
remove_samba_config() {
    print_info "移除Samba配置..."
    
    # 停止服务
    case $OS in
        "macos")
            brew services stop samba
            ;;
        "debian"|"rhel")
            systemctl stop smbd
            systemctl stop nmbd
            systemctl disable smbd
            systemctl disable nmbd
            ;;
    esac
    
    # 恢复配置文件
    if [[ -f "${SMB_CONF}${BACKUP_SUFFIX}" ]]; then
        mv "${SMB_CONF}${BACKUP_SUFFIX}" "$SMB_CONF"
        print_success "配置文件已恢复"
    else
        rm -f "$SMB_CONF"
        print_success "配置文件已删除"
    fi
    
    # 询问是否删除用户
    read -p "是否删除JavSP用户 ($DEFAULT_USER)? (y/N): " delete_user
    if [[ "$delete_user" =~ ^[Yy]$ ]]; then
        smbpasswd -x $DEFAULT_USER 2>/dev/null || true
        userdel $DEFAULT_USER 2>/dev/null || true
        print_success "用户已删除"
    fi
    
    print_success "Samba配置移除完成"
}

# 显示使用帮助
show_usage() {
    echo "使用方法:"
    echo "  $0 setup [共享目录] [用户名] [密码]    - 设置Samba服务器"
    echo "  $0 remove                            - 移除Samba配置"
    echo "  $0 test                              - 测试Samba配置"
    echo "  $0 info                              - 显示连接信息"
    echo "  $0 help                              - 显示帮助信息"
    echo
    echo "示例:"
    echo "  $0 setup /opt/javsp javsp mypassword"
    echo "  $0 test"
}

# 主函数
main() {
    local action=${1:-help}
    local share_path=${2:-/opt/javsp}
    local username=${3:-$DEFAULT_USER}
    local password=$4
    
    print_header
    detect_os
    print_info "检测到操作系统: $OS"
    
    case "$action" in
        "setup")
            check_root
            
            if [[ -z "$password" ]]; then
                read -s -p "请输入JavSP用户密码: " password
                echo
            fi
            
            if [[ -z "$password" ]]; then
                print_error "必须设置密码"
                exit 1
            fi
            
            print_info "开始配置JavSP Samba服务器..."
            print_info "共享目录: $share_path"
            print_info "用户名: $username"
            echo
            
            if install_samba && \
               create_javsp_user "$username" "$password"; then
                
                local dirs=$(create_shared_directories "$share_path" "$username")
                local input_path=$(echo "$dirs" | cut -d':' -f1)
                local output_path=$(echo "$dirs" | cut -d':' -f2)
                
                if configure_samba "$input_path" "$output_path" "$username" && \
                   start_samba_service && \
                   test_samba_config; then
                    
                    configure_firewall
                    generate_config_file "$share_path"
                    
                    echo
                    print_success "🎉 JavSP Samba服务器配置完成！"
                    echo
                    show_connection_info
                else
                    print_error "配置失败"
                    exit 1
                fi
            else
                print_error "安装或用户创建失败"
                exit 1
            fi
            ;;
        "remove")
            check_root
            remove_samba_config
            ;;
        "test")
            test_samba_config
            ;;
        "info")
            show_connection_info
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 执行主函数
main "$@"