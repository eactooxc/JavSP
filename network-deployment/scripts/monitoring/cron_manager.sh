#!/bin/bash

# JavSP 定时任务管理脚本
# 用于设置和管理JavSP的定时处理任务

SCRIPT_NAME="JavSP 定时任务管理器"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_USER=${SUDO_USER:-$(whoami)}

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

# 预定义的定时任务模板
get_cron_templates() {
    cat << 'EOF'
# JavSP 定时任务模板

# 每小时检查一次
hourly|0 * * * *|每小时处理一次新文件

# 每2小时检查一次
2hourly|0 */2 * * *|每2小时处理一次新文件

# 每天凌晨2点执行
daily|0 2 * * *|每天凌晨2点批量处理

# 每天凌晨2点和下午2点执行
twice-daily|0 2,14 * * *|每天2次批量处理

# 每周日凌晨3点执行
weekly|0 3 * * 0|每周日凌晨3点批量处理

# 每30分钟检查一次（工作时间）
worktime|*/30 9-18 * * 1-5|工作时间每30分钟检查

# 自定义（需要手动填写cron表达式）
custom||自定义时间表达式
EOF
}

# 显示定时任务模板
show_templates() {
    print_info "可用的定时任务模板:"
    echo
    
    get_cron_templates | grep -v '^#' | grep -v '^$' | while IFS='|' read -r name schedule description; do
        if [[ -n "$name" ]]; then
            printf "  %-12s %-15s %s\n" "$name" "$schedule" "$description"
        fi
    done
    echo
}

# 获取cron表达式
get_cron_schedule() {
    local template=$1
    get_cron_templates | grep "^$template|" | cut -d'|' -f2
}

# 检查Docker容器状态
check_docker_container() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker未安装或不在PATH中"
        return 1
    fi
    
    if ! docker ps | grep -q javsp-server; then
        print_warning "JavSP容器未运行"
        print_info "请先启动Docker容器: docker-compose up -d"
        return 1
    fi
    
    print_success "Docker容器运行正常"
    return 0
}

# 生成cron任务
generate_cron_job() {
    local schedule=$1
    local script_path=$2
    local log_path=$3
    
    echo "$schedule cd $(dirname "$script_path") && $script_path >> $log_path 2>&1"
}

# 添加定时任务
add_cron_job() {
    local template=$1
    local custom_schedule=$2
    
    print_info "添加定时任务..."
    
    # 获取时间表达式
    local schedule
    if [[ "$template" == "custom" ]]; then
        if [[ -z "$custom_schedule" ]]; then
            read -p "请输入cron表达式 (如: 0 2 * * *): " custom_schedule
        fi
        schedule="$custom_schedule"
    else
        schedule=$(get_cron_schedule "$template")
    fi
    
    if [[ -z "$schedule" ]]; then
        print_error "无效的时间表达式"
        return 1
    fi
    
    # 生成脚本路径
    local batch_script="$SCRIPT_DIR/batch_process.sh"
    local log_file="/app/logs/cron_batch.log"
    
    # 检查批处理脚本是否存在
    if [[ ! -f "$batch_script" ]]; then
        print_error "批处理脚本不存在: $batch_script"
        return 1
    fi
    
    # 确保脚本可执行
    chmod +x "$batch_script"
    
    # 生成cron任务
    local cron_job=$(generate_cron_job "$schedule" "$batch_script" "$log_file")
    
    # 添加到crontab
    (crontab -u "$CRON_USER" -l 2>/dev/null; echo "# JavSP 自动处理任务"; echo "$cron_job") | crontab -u "$CRON_USER" -
    
    if [[ $? -eq 0 ]]; then
        print_success "定时任务添加成功"
        print_info "时间表达式: $schedule"
        print_info "执行脚本: $batch_script"
        print_info "日志文件: $log_file"
        return 0
    else
        print_error "定时任务添加失败"
        return 1
    fi
}

# 移除定时任务
remove_cron_job() {
    print_info "移除JavSP定时任务..."
    
    # 备份当前crontab
    crontab -u "$CRON_USER" -l > /tmp/crontab_backup_$$ 2>/dev/null
    
    # 移除JavSP相关任务
    crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "JavSP\|javsp\|batch_process.sh" | crontab -u "$CRON_USER" -
    
    if [[ $? -eq 0 ]]; then
        print_success "定时任务移除成功"
        print_info "备份文件: /tmp/crontab_backup_$$"
    else
        print_error "定时任务移除失败"
    fi
}

# 显示当前定时任务
show_current_jobs() {
    print_info "当前的JavSP定时任务:"
    echo
    
    local jobs=$(crontab -u "$CRON_USER" -l 2>/dev/null | grep -E "JavSP|javsp|batch_process")
    
    if [[ -n "$jobs" ]]; then
        echo "$jobs" | while read -r line; do
            if [[ "$line" =~ ^# ]]; then
                print_color $YELLOW "$line"
            else
                print_color $GREEN "$line"
            fi
        done
    else
        print_warning "没有找到JavSP定时任务"
    fi
    echo
}

# 测试定时任务
test_cron_job() {
    print_info "测试批处理脚本..."
    
    local batch_script="$SCRIPT_DIR/batch_process.sh"
    
    if [[ ! -f "$batch_script" ]]; then
        print_error "批处理脚本不存在: $batch_script"
        return 1
    fi
    
    # 检查脚本语法
    if bash -n "$batch_script"; then
        print_success "脚本语法检查通过"
    else
        print_error "脚本语法错误"
        return 1
    fi
    
    # 执行干运行
    print_info "执行测试运行..."
    if bash "$batch_script" --dry-run; then
        print_success "脚本测试运行成功"
    else
        print_error "脚本测试运行失败"
        return 1
    fi
}

# 查看日志
view_logs() {
    local log_type=${1:-batch}
    
    case "$log_type" in
        "batch")
            local log_file="/app/logs/batch_process.log"
            ;;
        "cron")
            local log_file="/app/logs/cron_batch.log"
            ;;
        "error")
            local log_file="/app/logs/batch_errors.log"
            ;;
        *)
            print_error "未知的日志类型: $log_type"
            print_info "可用类型: batch, cron, error"
            return 1
            ;;
    esac
    
    if [[ -f "$log_file" ]]; then
        print_info "显示日志: $log_file"
        echo "----------------------------------------"
        tail -n 50 "$log_file"
        echo "----------------------------------------"
    else
        print_warning "日志文件不存在: $log_file"
    fi
}

# 生成systemd服务（Linux）
generate_systemd_service() {
    if [[ ! -f /etc/systemd/system ]]; then
        print_warning "系统不支持systemd"
        return 1
    fi
    
    print_info "生成systemd服务..."
    
    local service_file="/etc/systemd/system/javsp-batch.service"
    local timer_file="/etc/systemd/system/javsp-batch.timer"
    
    # 生成服务文件
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=JavSP Batch Processing Service
After=docker.service

[Service]
Type=oneshot
User=$CRON_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/batch_process.sh
StandardOutput=append:/app/logs/systemd_batch.log
StandardError=append:/app/logs/systemd_batch.log

[Install]
WantedBy=multi-user.target
EOF

    # 生成定时器文件
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=JavSP Batch Processing Timer
Requires=javsp-batch.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 重载systemd并启用
    sudo systemctl daemon-reload
    sudo systemctl enable javsp-batch.timer
    sudo systemctl start javsp-batch.timer
    
    print_success "systemd服务已创建并启用"
    print_info "服务文件: $service_file"
    print_info "定时器文件: $timer_file"
    print_info "查看状态: sudo systemctl status javsp-batch.timer"
}

# 显示使用帮助
show_usage() {
    echo "使用方法:"
    echo "  $0 add [模板名]           - 添加定时任务"
    echo "  $0 remove                - 移除定时任务"
    echo "  $0 list                  - 显示当前任务"
    echo "  $0 test                  - 测试批处理脚本"
    echo "  $0 logs [类型]           - 查看日志"
    echo "  $0 systemd               - 生成systemd服务(Linux)"
    echo "  $0 templates             - 显示可用模板"
    echo "  $0 help                  - 显示帮助信息"
    echo
    echo "日志类型: batch(默认), cron, error"
    echo
    echo "示例:"
    echo "  $0 add daily             - 添加每日任务"
    echo "  $0 add custom '*/30 * * * *'  - 添加自定义任务"
    echo "  $0 logs error            - 查看错误日志"
}

# 主函数
main() {
    local action=${1:-help}
    local param1=$2
    local param2=$3
    
    print_header
    
    case "$action" in
        "add")
            if ! check_docker_container; then
                exit 1
            fi
            
            if [[ -z "$param1" ]]; then
                show_templates
                read -p "请选择模板 (或输入 custom): " param1
            fi
            
            add_cron_job "$param1" "$param2"
            ;;
        "remove")
            remove_cron_job
            ;;
        "list")
            show_current_jobs
            ;;
        "test")
            test_cron_job
            ;;
        "logs")
            view_logs "$param1"
            ;;
        "systemd")
            generate_systemd_service
            ;;
        "templates")
            show_templates
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 执行主函数
main "$@"