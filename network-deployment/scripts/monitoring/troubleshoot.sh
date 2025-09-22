#!/bin/bash

# JavSP 故障排除和诊断脚本
# 自动诊断和修复常见问题

SCRIPT_NAME="JavSP 故障排除工具"
VERSION="1.0.0"
LOG_FILE="/app/logs/troubleshoot.log"

# 颜色输出
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

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

print_header() {
    echo
    print_color $CYAN "================================"
    print_color $CYAN "  $SCRIPT_NAME v$VERSION"
    print_color $CYAN "================================"
    echo
}

print_success() { print_color $GREEN "✓ $1"; }
print_error() { print_color $RED "✗ $1"; }
print_warning() { print_color $YELLOW "⚠ $1"; }
print_info() { print_color $BLUE "$1"; }

# 诊断结果收集
ISSUES_FOUND=()
FIXES_APPLIED=()

add_issue() {
    ISSUES_FOUND+=("$1")
}

add_fix() {
    FIXES_APPLIED+=("$1")
}

# 检查Docker服务
check_docker_service() {
    print_info "检查Docker服务状态..."
    
    if ! command -v docker &> /dev/null; then
        add_issue "Docker未安装或不在PATH中"
        print_error "Docker未安装"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        add_issue "Docker服务未运行"
        print_error "Docker服务未运行"
        
        # 尝试启动Docker服务
        print_info "尝试启动Docker服务..."
        if systemctl start docker 2>/dev/null || service docker start 2>/dev/null; then
            add_fix "已启动Docker服务"
            print_success "Docker服务已启动"
        else
            print_error "无法启动Docker服务，请手动检查"
            return 1
        fi
    else
        print_success "Docker服务运行正常"
    fi
    
    return 0
}

# 检查JavSP容器
check_javsp_container() {
    print_info "检查JavSP容器状态..."
    
    local container_id=$(docker ps -q --filter "name=javsp-server")
    
    if [[ -z "$container_id" ]]; then
        add_issue "JavSP容器未运行"
        print_error "JavSP容器未运行"
        
        # 检查是否存在但已停止
        local stopped_container=$(docker ps -aq --filter "name=javsp-server")
        
        if [[ -n "$stopped_container" ]]; then
            print_info "发现已停止的容器，尝试启动..."
            if docker start javsp-server; then
                add_fix "已启动JavSP容器"
                print_success "JavSP容器已启动"
            else
                print_error "容器启动失败"
                return 1
            fi
        else
            print_error "未找到JavSP容器，请检查docker-compose配置"
            return 1
        fi
    else
        print_success "JavSP容器运行正常"
        
        # 检查容器健康状态
        local health_status=$(docker inspect javsp-server --format='{{.State.Health.Status}}' 2>/dev/null)
        if [[ "$health_status" == "unhealthy" ]]; then
            add_issue "JavSP容器健康检查失败"
            print_warning "容器健康检查失败"
        fi
    fi
    
    return 0
}

# 检查网络连接
check_network_connectivity() {
    print_info "检查网络连接..."
    
    # 检查基本网络连通性
    if ! ping -c 3 8.8.8.8 &>/dev/null; then
        add_issue "网络连接异常"
        print_error "网络连接异常"
        return 1
    fi
    
    print_success "基本网络连接正常"
    
    # 检查DNS解析
    if ! nslookup google.com &>/dev/null; then
        add_issue "DNS解析失败"
        print_error "DNS解析失败"
    else
        print_success "DNS解析正常"
    fi
    
    # 检查常用网站连接
    local test_sites=("javbus.com" "javdb.com" "javlibrary.com")
    local failed_sites=0
    
    for site in "${test_sites[@]}"; do
        if ! curl -Is --connect-timeout 10 "https://$site" &>/dev/null; then
            ((failed_sites++))
            print_warning "无法连接到 $site"
        fi
    done
    
    if [[ $failed_sites -gt 0 ]]; then
        add_issue "部分数据源网站无法访问"
        print_warning "$failed_sites 个数据源网站无法访问"
    fi
    
    return 0
}

# 检查文件系统
check_filesystem() {
    print_info "检查文件系统..."
    
    local directories=("/app/input" "/app/output" "/app/logs" "/app/config")
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            add_issue "目录不存在: $dir"
            print_error "目录不存在: $dir"
            
            # 尝试创建目录
            if mkdir -p "$dir" 2>/dev/null; then
                add_fix "已创建目录: $dir"
                print_success "已创建目录: $dir"
            else
                print_error "无法创建目录: $dir"
            fi
        fi
        
        # 检查目录权限
        if [[ ! -w "$dir" ]]; then
            add_issue "目录权限不足: $dir"
            print_error "目录权限不足: $dir"
        fi
    done
    
    # 检查磁盘空间
    local disk_usage=$(df /app | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    if [[ $disk_usage -gt 90 ]]; then
        add_issue "磁盘空间不足: ${disk_usage}%"
        print_error "磁盘空间不足: ${disk_usage}%"
    elif [[ $disk_usage -gt 80 ]]; then
        add_issue "磁盘空间紧张: ${disk_usage}%"
        print_warning "磁盘空间紧张: ${disk_usage}%"
    else
        print_success "磁盘空间充足: ${disk_usage}%"
    fi
    
    return 0
}

# 检查配置文件
check_configuration() {
    print_info "检查配置文件..."
    
    local config_file="/app/config.yml"
    
    if [[ ! -f "$config_file" ]]; then
        add_issue "配置文件不存在: $config_file"
        print_error "配置文件不存在: $config_file"
        return 1
    fi
    
    # 检查配置文件语法
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            add_issue "配置文件格式错误"
            print_error "配置文件格式错误"
            return 1
        fi
    fi
    
    print_success "配置文件检查通过"
    return 0
}

# 检查进程状态
check_processes() {
    print_info "检查进程状态..."
    
    # 检查Python进程
    local python_processes=$(pgrep -f "python.*javsp" | wc -l)
    if [[ $python_processes -eq 0 ]]; then
        add_issue "未找到JavSP Python进程"
        print_warning "未找到JavSP Python进程"
    else
        print_success "找到 $python_processes 个JavSP进程"
    fi
    
    # 检查僵尸进程
    local zombie_processes=$(ps aux | awk '$8 ~ /^Z/ { print $2 }' | wc -l)
    if [[ $zombie_processes -gt 0 ]]; then
        add_issue "发现 $zombie_processes 个僵尸进程"
        print_warning "发现 $zombie_processes 个僵尸进程"
    fi
    
    return 0
}

# 检查日志文件
check_logs() {
    print_info "检查日志文件..."
    
    local log_files=(
        "/app/logs/javsp.log"
        "/app/logs/batch_process.log"
        "/app/logs/monitor.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            # 检查最近的错误
            local recent_errors=$(tail -n 100 "$log_file" | grep -i "error\|exception\|fail" | wc -l)
            if [[ $recent_errors -gt 10 ]]; then
                add_issue "日志中发现大量错误: $log_file"
                print_warning "日志 $log_file 中发现 $recent_errors 个错误"
            fi
            
            # 检查文件大小
            local file_size=$(stat -c%s "$log_file")
            local max_size=$((100 * 1024 * 1024))  # 100MB
            
            if [[ $file_size -gt $max_size ]]; then
                add_issue "日志文件过大: $log_file"
                print_warning "日志文件过大: $log_file ($(($file_size / 1024 / 1024))MB)"
            fi
        fi
    done
    
    return 0
}

# 检查SMB共享
check_smb_shares() {
    print_info "检查SMB共享..."
    
    # 检查SMB服务
    if command -v smbclient &> /dev/null; then
        if smbclient -L localhost -N &>/dev/null; then
            print_success "SMB服务运行正常"
        else
            add_issue "SMB服务异常"
            print_error "SMB服务异常"
        fi
    else
        print_warning "未安装SMB客户端工具"
    fi
    
    # 检查共享目录
    local share_dirs=("/app/input" "/app/output")
    for dir in "${share_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            add_issue "共享目录不存在: $dir"
            print_error "共享目录不存在: $dir"
        fi
    done
    
    return 0
}

# 自动修复常见问题
auto_fix_issues() {
    print_info "尝试自动修复问题..."
    
    # 清理临时文件
    if find /tmp -name "javsp_*" -mtime +1 2>/dev/null | grep -q .; then
        find /tmp -name "javsp_*" -mtime +1 -delete 2>/dev/null
        add_fix "已清理过期临时文件"
        print_success "已清理过期临时文件"
    fi
    
    # 重启卡住的容器
    local container_status=$(docker inspect javsp-server --format='{{.State.Status}}' 2>/dev/null)
    if [[ "$container_status" == "restarting" ]]; then
        print_info "容器处于重启状态，尝试强制重启..."
        docker kill javsp-server 2>/dev/null
        docker start javsp-server
        add_fix "已强制重启容器"
        print_success "已强制重启容器"
    fi
    
    # 修复权限问题
    local dirs_to_fix=("/app/input" "/app/output" "/app/logs")
    for dir in "${dirs_to_fix[@]}"; do
        if [[ -d "$dir" ]] && [[ ! -w "$dir" ]]; then
            if chmod 755 "$dir" 2>/dev/null; then
                add_fix "已修复目录权限: $dir"
                print_success "已修复目录权限: $dir"
            fi
        fi
    done
    
    return 0
}

# 收集系统信息
collect_system_info() {
    print_info "收集系统信息..."
    
    local info_file="/app/logs/system_info_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$info_file" << EOF
# JavSP 系统诊断信息
# 生成时间: $(date)

## 系统信息
操作系统: $(uname -a)
内核版本: $(uname -r)
主机名: $(hostname)
当前用户: $(whoami)
运行时间: $(uptime)

## 资源使用
CPU使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
内存使用: $(free -h | grep Mem)
磁盘使用: $(df -h)

## Docker信息
Docker版本: $(docker --version 2>/dev/null || echo "未安装")
Docker状态: $(docker info --format "{{.ServerVersion}}" 2>/dev/null || echo "服务未运行")
运行的容器: $(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "无法获取")

## 网络信息
网络接口: $(ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "无法获取")
路由表: $(ip route 2>/dev/null || route -n 2>/dev/null || echo "无法获取")
DNS配置: $(cat /etc/resolv.conf 2>/dev/null || echo "无法获取")

## 进程信息
JavSP进程: $(pgrep -fl javsp 2>/dev/null || echo "未找到")
Python进程: $(pgrep -fl python 2>/dev/null | head -5)
内存占用最高的进程: $(ps aux --sort=-%mem | head -5)

## 文件系统
挂载点: $(mount | grep -E "(app|javsp)" || echo "无相关挂载点")
目录结构: $(find /app -maxdepth 2 -type d 2>/dev/null || echo "无法访问/app目录")

## 错误日志摘要
EOF

    # 添加最近的错误日志
    for log_file in /app/logs/*.log; do
        if [[ -f "$log_file" ]]; then
            echo "### $(basename "$log_file") 最近错误:" >> "$info_file"
            tail -n 50 "$log_file" | grep -i "error\|exception\|fail" | tail -5 >> "$info_file" 2>/dev/null
            echo "" >> "$info_file"
        fi
    done
    
    print_success "系统信息已收集: $info_file"
    return 0
}

# 生成诊断报告
generate_report() {
    local report_file="/app/logs/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# JavSP 故障诊断报告
# 生成时间: $(date)

## 诊断摘要
检查项目: Docker服务、容器状态、网络连接、文件系统、配置文件、进程状态、日志文件、SMB共享

## 发现的问题
EOF

    if [[ ${#ISSUES_FOUND[@]} -eq 0 ]]; then
        echo "✓ 未发现严重问题" >> "$report_file"
    else
        for issue in "${ISSUES_FOUND[@]}"; do
            echo "✗ $issue" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## 已应用的修复
EOF

    if [[ ${#FIXES_APPLIED[@]} -eq 0 ]]; then
        echo "- 无需修复或无法自动修复" >> "$report_file"
    else
        for fix in "${FIXES_APPLIED[@]}"; do
            echo "✓ $fix" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## 建议的后续操作
EOF

    if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
        echo "1. 查看详细的错误日志以获取更多信息" >> "$report_file"
        echo "2. 检查网络连接和防火墙设置" >> "$report_file"
        echo "3. 验证Docker和JavSP配置" >> "$report_file"
        echo "4. 监控系统资源使用情况" >> "$report_file"
        echo "5. 如问题持续，请联系技术支持" >> "$report_file"
    else
        echo "系统运行正常，建议定期执行此诊断脚本进行预防性检查。" >> "$report_file"
    fi
    
    print_success "诊断报告已生成: $report_file"
}

# 快速诊断
quick_check() {
    print_info "执行快速诊断..."
    
    check_docker_service && \
    check_javsp_container && \
    check_network_connectivity
    
    if [[ ${#ISSUES_FOUND[@]} -eq 0 ]]; then
        print_success "快速诊断通过，系统运行正常"
        return 0
    else
        print_warning "快速诊断发现问题，建议执行完整诊断"
        return 1
    fi
}

# 完整诊断
full_check() {
    print_info "执行完整诊断..."
    
    check_docker_service
    check_javsp_container
    check_network_connectivity
    check_filesystem
    check_configuration
    check_processes
    check_logs
    check_smb_shares
    
    auto_fix_issues
    collect_system_info
    generate_report
    
    if [[ ${#ISSUES_FOUND[@]} -eq 0 ]]; then
        print_success "完整诊断完成，系统运行正常"
    else
        print_warning "完整诊断发现 ${#ISSUES_FOUND[@]} 个问题"
        print_info "请查看诊断报告获取详细信息"
    fi
}

# 紧急修复
emergency_fix() {
    print_info "执行紧急修复..."
    
    # 强制重启所有相关服务
    print_info "重启Docker容器..."
    docker-compose -f /app/docker-compose.yml restart 2>/dev/null || docker restart javsp-server 2>/dev/null
    
    # 清理所有临时文件
    print_info "清理临时文件..."
    find /tmp -name "*javsp*" -delete 2>/dev/null || true
    
    # 重置文件权限
    print_info "重置文件权限..."
    chmod -R 755 /app/input /app/output /app/logs 2>/dev/null || true
    
    # 清理日志文件
    print_info "清理大日志文件..."
    find /app/logs -name "*.log" -size +100M -exec truncate -s 50M {} \; 2>/dev/null || true
    
    add_fix "已执行紧急修复操作"
    print_success "紧急修复完成"
}

# 显示帮助信息
show_usage() {
    echo "使用方法:"
    echo "  $0 quick                 - 快速诊断"
    echo "  $0 full                  - 完整诊断"
    echo "  $0 fix                   - 自动修复"
    echo "  $0 emergency             - 紧急修复"
    echo "  $0 info                  - 收集系统信息"
    echo "  $0 docker                - 检查Docker服务"
    echo "  $0 container             - 检查容器状态"
    echo "  $0 network               - 检查网络连接"
    echo "  $0 filesystem            - 检查文件系统"
    echo "  $0 config                - 检查配置文件"
    echo "  $0 logs                  - 检查日志文件"
    echo "  $0 smb                   - 检查SMB共享"
    echo "  $0 help                  - 显示帮助信息"
}

# 主函数
main() {
    local action=${1:-quick}
    
    print_header
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "开始执行故障排除: $action"
    
    case "$action" in
        "quick")
            quick_check
            ;;
        "full")
            full_check
            ;;
        "fix")
            auto_fix_issues
            ;;
        "emergency")
            emergency_fix
            ;;
        "info")
            collect_system_info
            ;;
        "docker")
            check_docker_service
            ;;
        "container")
            check_javsp_container
            ;;
        "network")
            check_network_connectivity
            ;;
        "filesystem")
            check_filesystem
            ;;
        "config")
            check_configuration
            ;;
        "logs")
            check_logs
            ;;
        "smb")
            check_smb_shares
            ;;
        "help"|*)
            show_usage
            ;;
    esac
    
    log "INFO" "故障排除完成"
    
    # 显示摘要
    if [[ ${#ISSUES_FOUND[@]} -gt 0 ]] || [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
        echo
        print_color $CYAN "诊断摘要:"
        print_info "发现问题: ${#ISSUES_FOUND[@]} 个"
        print_info "已修复: ${#FIXES_APPLIED[@]} 个"
    fi
}

# 执行主函数
main "$@"