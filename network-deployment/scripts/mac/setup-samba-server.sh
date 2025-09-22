#!/bin/bash

# JavSP Mac 快速Samba配置脚本
# 适用于macOS系统的简化配置

echo "================================"
echo "  JavSP Mac Samba 快速配置"
echo "================================"
echo

# 检查Homebrew
if ! command -v brew &> /dev/null; then
    echo "错误: 需要先安装Homebrew"
    echo "请访问: https://brew.sh/"
    exit 1
fi

# 检查管理员权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 此脚本需要管理员权限运行"
    echo "请使用: sudo $0"
    exit 1
fi

# 获取配置信息
read -p "请输入共享目录路径 (默认: /opt/javsp): " SHARE_PATH
SHARE_PATH=${SHARE_PATH:-/opt/javsp}

read -p "请输入用户名 (默认: javsp): " USERNAME
USERNAME=${USERNAME:-javsp}

read -s -p "请输入密码: " PASSWORD
echo

if [[ -z "$PASSWORD" ]]; then
    echo "错误: 必须设置密码"
    exit 1
fi

echo
echo "配置信息:"
echo "共享目录: $SHARE_PATH"
echo "用户名: $USERNAME"
echo

read -p "确认配置? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "取消配置"
    exit 0
fi

echo
echo "开始配置..."

# 安装Samba
echo "检查并安装Samba..."
if ! brew list samba &> /dev/null; then
    brew install samba
fi
echo "✓ Samba已安装"

# 创建目录
echo "创建共享目录..."
mkdir -p "$SHARE_PATH/input"
mkdir -p "$SHARE_PATH/output"
echo "✓ 目录创建完成"

# 创建用户
echo "配置用户..."
if ! id "$USERNAME" &>/dev/null; then
    dscl . -create /Users/$USERNAME
    dscl . -create /Users/$USERNAME UserShell /bin/bash
    dscl . -create /Users/$USERNAME RealName "JavSP Service User"
    dscl . -create /Users/$USERNAME UniqueID 1001
    dscl . -create /Users/$USERNAME PrimaryGroupID 1000
    dscl . -create /Users/$USERNAME NFSHomeDirectory /Users/$USERNAME
    dscl . -passwd /Users/$USERNAME $PASSWORD
fi

# 设置权限
chown -R $USERNAME:staff "$SHARE_PATH"
chmod 775 "$SHARE_PATH/input"
chmod 755 "$SHARE_PATH/output"
echo "✓ 权限设置完成"

# 配置Samba
SMB_CONF="/usr/local/etc/smb.conf"
mkdir -p "$(dirname "$SMB_CONF")"

cat > "$SMB_CONF" << EOF
[global]
    server string = JavSP Media Server
    workgroup = WORKGROUP
    security = user
    map to guest = never
    
[javsp-input]
    comment = JavSP Input Directory
    path = $SHARE_PATH/input
    valid users = $USERNAME
    writable = yes
    create mask = 0664
    directory mask = 0775

[javsp-output]
    comment = JavSP Output Directory
    path = $SHARE_PATH/output
    valid users = $USERNAME
    writable = no
    create mask = 0644
    directory mask = 0755
EOF

echo "✓ Samba配置完成"

# 添加Samba用户
echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -a $USERNAME
smbpasswd -e $USERNAME
echo "✓ Samba用户配置完成"

# 启动服务
echo "启动Samba服务..."
brew services start samba
sleep 2

if pgrep smbd > /dev/null; then
    echo "✓ Samba服务启动成功"
else
    echo "✗ Samba服务启动失败"
    exit 1
fi

# 获取IP地址
IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)

echo
echo "================================"
echo "   配置完成！"
echo "================================"
echo
echo "服务器信息:"
echo "IP地址: $IP"
echo "输入共享: //$IP/javsp-input"
echo "输出共享: //$IP/javsp-output"
echo
echo "客户端连接命令:"
echo "Windows: net use J: \\\\$IP\\javsp-input"
echo "Mac: mount -t smbfs //$IP/javsp-input /Volumes/javsp-input"
echo
echo "使用说明:"
echo "1. 将视频文件复制到输入共享目录"
echo "2. 启动JavSP Docker容器"
echo "3. 从输出共享目录获取整理结果"

# 生成配置文件
cat > "$SHARE_PATH/连接信息.txt" << EOF
# JavSP Mac Samba 服务器配置信息
# 生成时间: $(date)

服务器IP: $IP
输入共享: //$IP/javsp-input
输出共享: //$IP/javsp-output

Windows连接命令:
  net use J: \\\\$IP\\javsp-input
  net use K: \\\\$IP\\javsp-output

Mac连接命令:
  mount -t smbfs //$IP/javsp-input /Volumes/javsp-input
  mount -t smbfs //$IP/javsp-output /Volumes/javsp-output
EOF

echo
echo "配置信息已保存到: $SHARE_PATH/连接信息.txt"