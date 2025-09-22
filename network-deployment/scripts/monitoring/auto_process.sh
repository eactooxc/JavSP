#!/bin/bash

# JavSP 自动处理脚本
# 定期检查输入目录并处理新文件

# 配置变量
INPUT_DIR="/app/input"
OUTPUT_DIR="/app/output"
LOG_FILE="/app/logs/auto_process.log"
LOCK_FILE="/tmp/javsp_auto.lock"
LAST_RUN_FILE="/tmp/javsp_last_run"

# 配置参数
MIN_FILE_SIZE="200M"  # 最小文件大小
WAIT_TIME=60          # 检查间隔（秒）
PROCESS_DELAY=30      # 文件稳定等待时间（秒）

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 检查锁文件
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log "WARN" "处理进程已在运行 (PID: $lock_pid)"
            return 1
        else
            log "INFO" "清理过期锁文件"
            rm -f "$LOCK_FILE"
        fi
    fi
    return 0
}

# 创建锁文件
create_lock() {
    echo $$ > "$LOCK_FILE"
}

# 清理锁文件
remove_lock() {
    rm -f "$LOCK_FILE"
}

# 检查文件是否稳定（传输完成）
is_file_stable() {
    local file=$1
    local size1=$(stat -c%s "$file" 2>/dev/null || echo 0)
    sleep 2
    local size2=$(stat -c%s "$file" 2>/dev/null || echo 0)
    
    [[ "$size1" == "$size2" ]] && [[ "$size1" -gt 0 ]]
}

# 查找新的视频文件
find_new_files() {
    local reference_time="$LAST_RUN_FILE"
    [[ ! -f "$reference_time" ]] && touch "$reference_time"
    
    find "$INPUT_DIR" -type f \( \
        -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o \
        -name "*.mov" -o -name "*.wmv" -o -name "*.flv" -o \
        -name "*.m4v" -o -name "*.m2ts" -o -name "*.ts" -o \
        -name "*.vob" -o -name "*.iso" -o -name "*.rmvb" -o \
        -name "*.rm" -o -name "*.3gp" -o -name "*.f4v" -o \
        -name "*.webm" -o -name "*.strm" -o -name "*.mpg" -o \
        -name "*.mpeg" \
    \) -newer "$reference_time" -size +${MIN_FILE_SIZE} 2>/dev/null
}

# 等待文件稳定
wait_for_stability() {
    local files=("$@")
    log "INFO" "等待 ${#files[@]} 个文件传输稳定..."
    
    local max_wait=300  # 最大等待5分钟
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local unstable_count=0
        
        for file in "${files[@]}"; do
            if [[ -f "$file" ]] && ! is_file_stable "$file"; then
                ((unstable_count++))
                log "INFO" "文件传输中: $(basename "$file")"
            fi
        done
        
        if [[ $unstable_count -eq 0 ]]; then
            log "INFO" "所有文件传输完成"
            return 0
        fi
        
        sleep $PROCESS_DELAY
        ((wait_time += PROCESS_DELAY))
    done
    
    log "WARN" "文件稳定等待超时，继续处理"
    return 0
}

# 处理视频文件
process_files() {
    local start_time=$(date +%s)
    log "INFO" "开始JavSP处理..."
    
    # 执行JavSP
    if python -m javsp -i "$INPUT_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "INFO" "JavSP处理完成，耗时: ${duration}秒"
        
        # 更新最后运行时间
        touch "$LAST_RUN_FILE"
        return 0
    else
        log "ERROR" "JavSP处理失败"
        return 1
    fi
}

# 清理旧日志
cleanup_logs() {
    # 保留最近7天的日志
    find "$(dirname "$LOG_FILE")" -name "*.log" -mtime +7 -delete 2>/dev/null || true
}

# 主处理循环
main_loop() {
    log "INFO" "启动JavSP自动处理服务"
    log "INFO" "监控目录: $INPUT_DIR"
    log "INFO" "输出目录: $OUTPUT_DIR"
    log "INFO" "检查间隔: ${WAIT_TIME}秒"
    
    while true; do
        # 检查是否有新文件
        local new_files=()
        while IFS= read -r -d '' file; do
            new_files+=("$file")
        done < <(find_new_files -print0)
        
        if [[ ${#new_files[@]} -gt 0 ]]; then
            log "INFO" "发现 ${#new_files[@]} 个新文件"
            
            # 显示文件列表
            for file in "${new_files[@]}"; do
                log "INFO" "  - $(basename "$file")"
            done
            
            # 检查锁文件
            if check_lock; then
                create_lock
                
                # 等待文件传输稳定
                wait_for_stability "${new_files[@]}"
                
                # 处理文件
                process_files
                
                remove_lock
            fi
        fi
        
        # 定期清理日志
        cleanup_logs
        
        # 等待下次检查
        sleep $WAIT_TIME
    done
}

# 信号处理
cleanup_and_exit() {
    log "INFO" "收到退出信号，清理资源..."
    remove_lock
    exit 0
}

trap cleanup_and_exit SIGTERM SIGINT

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 启动主循环
main_loop