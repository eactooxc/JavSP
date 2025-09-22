#!/bin/bash

# JavSP 文件监控和自动处理脚本
# 监控输入目录的文件变化，自动触发JavSP处理

# 配置变量
WATCH_DIR="/watch/input"
SCRIPT_NAME="JavSP 文件监控器"
VERSION="1.0.0"
LOCK_FILE="/tmp/javsp_processing.lock"
LAST_CHECK_FILE="/tmp/last_check"
LOG_FILE="/var/log/javsp_watcher.log"

# 日志函数
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_warn() {
    log_message "WARN" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

# 初始化
init_watcher() {
    log_info "启动 $SCRIPT_NAME v$VERSION"
    log_info "监控目录: $WATCH_DIR"
    
    # 创建必要的文件
    touch "$LAST_CHECK_FILE"
    
    # 安装inotify-tools（如果需要）
    if ! command -v inotifywait &> /dev/null; then
        log_info "安装 inotify-tools..."
        apk add --no-cache inotify-tools
    fi
    
    log_info "文件监控器初始化完成"
}

# 检查是否有新文件
check_new_files() {
    local new_files=$(find "$WATCH_DIR" -type f \( \
        -name "*.mp4" -o \
        -name "*.mkv" -o \
        -name "*.avi" -o \
        -name "*.mov" -o \
        -name "*.wmv" -o \
        -name "*.flv" -o \
        -name "*.m4v" -o \
        -name "*.m2ts" -o \
        -name "*.ts" -o \
        -name "*.vob" -o \
        -name "*.iso" -o \
        -name "*.rmvb" -o \
        -name "*.rm" -o \
        -name "*.3gp" -o \
        -name "*.f4v" -o \
        -name "*.webm" -o \
        -name "*.strm" -o \
        -name "*.mpg" -o \
        -name "*.mpeg" \
    \) -newer "$LAST_CHECK_FILE" 2>/dev/null)
    
    if [[ -n "$new_files" ]]; then
        log_info "发现新文件:"
        echo "$new_files" | while read -r file; do
            log_info "  - $(basename "$file")"
        done
        return 0
    else
        return 1
    fi
}

# 检查文件是否传输完成
is_file_complete() {
    local file=$1
    local size1=$(stat -c%s "$file" 2>/dev/null || echo 0)
    sleep 2
    local size2=$(stat -c%s "$file" 2>/dev/null || echo 0)
    
    [[ "$size1" == "$size2" ]] && [[ "$size1" -gt 0 ]]
}

# 等待所有文件传输完成
wait_for_transfers() {
    log_info "等待文件传输完成..."
    local max_wait=300  # 最大等待5分钟
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local incomplete_files=0
        
        find "$WATCH_DIR" -type f \( \
            -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o \
            -name "*.mov" -o -name "*.wmv" -o -name "*.flv" \
        \) -newer "$LAST_CHECK_FILE" 2>/dev/null | while read -r file; do
            if ! is_file_complete "$file"; then
                ((incomplete_files++))
                log_info "文件传输中: $(basename "$file")"
            fi
        done
        
        if [[ $incomplete_files -eq 0 ]]; then
            log_info "所有文件传输完成"
            return 0
        fi
        
        sleep 10
        ((wait_time += 10))
    done
    
    log_warn "等待文件传输超时，继续处理"
    return 0
}

# 触发JavSP处理
trigger_processing() {
    # 检查是否已有处理进程在运行
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "JavSP处理进程已在运行 (PID: $lock_pid)"
            return 1
        else
            log_info "删除过期的锁文件"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # 创建锁文件
    echo $$ > "$LOCK_FILE"
    
    log_info "开始JavSP处理..."
    
    # 等待文件传输完成
    wait_for_transfers
    
    # 执行JavSP处理
    local start_time=$(date +%s)
    
    # 使用docker exec调用JavSP容器
    if docker exec javsp-server /app/.venv/bin/javsp -i /app/input >> "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_info "JavSP处理完成，耗时: ${duration}秒"
        
        # 更新最后检查时间
        touch "$LAST_CHECK_FILE"
    else
        log_error "JavSP处理失败"
    fi
    
    # 清理锁文件
    rm -f "$LOCK_FILE"
}

# 使用inotify监控文件变化
monitor_with_inotify() {
    log_info "使用inotify监控文件变化..."
    
    inotifywait -m -r -e create,moved_to,close_write "$WATCH_DIR" --format '%w%f %e' 2>/dev/null | \
    while read file event; do
        # 只处理视频文件
        if [[ "$file" =~ \.(mp4|mkv|avi|mov|wmv|flv|m4v|m2ts|ts|vob|iso|rmvb|rm|3gp|f4v|webm|strm|mpg|mpeg)$ ]]; then
            log_info "检测到文件事件: $(basename "$file") [$event]"
            
            # 延迟处理，避免频繁触发
            sleep 30
            
            # 检查是否有新文件需要处理
            if check_new_files; then
                trigger_processing
            fi
        fi
    done
}

# 轮询监控（备用方案）
monitor_with_polling() {
    log_info "使用轮询方式监控文件变化..."
    
    while true; do
        if check_new_files; then
            trigger_processing
        fi
        
        sleep 60  # 每分钟检查一次
    done
}

# 清理函数
cleanup() {
    log_info "清理资源..."
    rm -f "$LOCK_FILE"
    exit 0
}

# 信号处理
trap cleanup SIGTERM SIGINT

# 主程序
main() {
    init_watcher
    
    # 检查inotify支持
    if command -v inotifywait &> /dev/null; then
        monitor_with_inotify
    else
        log_warn "inotify不可用，使用轮询方式"
        monitor_with_polling
    fi
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi