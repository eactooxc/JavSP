#!/bin/bash

# JavSP 批处理脚本
# 用于批量处理视频文件的定时任务脚本

# 配置变量
SCRIPT_NAME="JavSP 批处理器"
VERSION="1.0.0"
INPUT_DIR="/app/input"
OUTPUT_DIR="/app/output"
LOG_DIR="/app/logs"
CONFIG_FILE="/app/config.yml"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志文件
LOG_FILE="$LOG_DIR/batch_process.log"
ERROR_LOG="$LOG_DIR/batch_errors.log"
STATS_FILE="$LOG_DIR/batch_stats.json"

# 锁文件防止重复执行
LOCK_FILE="/tmp/javsp_batch.lock"
PID_FILE="/tmp/javsp_batch.pid"

# 配置参数
MAX_RUNTIME=7200        # 最大运行时间（秒）
MIN_FREE_SPACE_GB=5     # 最小剩余空间（GB）
MAX_LOG_SIZE_MB=100     # 最大日志文件大小（MB）
RETRY_COUNT=3           # 失败重试次数
BATCH_SIZE=10           # 每批处理文件数量

# 统计信息
STATS_PROCESSED=0
STATS_FAILED=0
STATS_SKIPPED=0
STATS_START_TIME=$(date +%s)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] $message" >> "$ERROR_LOG"
    fi
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# 检查运行环境
check_environment() {
    log_info "检查运行环境..."
    
    # 检查输入目录
    if [[ ! -d "$INPUT_DIR" ]]; then
        log_error "输入目录不存在: $INPUT_DIR"
        return 1
    fi
    
    # 检查输出目录
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        log_info "创建输出目录: $OUTPUT_DIR"
    fi
    
    # 检查配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "配置文件不存在: $CONFIG_FILE"
    fi
    
    # 检查磁盘空间
    local free_space=$(df "$OUTPUT_DIR" | tail -1 | awk '{print $4}')
    local free_space_gb=$((free_space / 1024 / 1024))
    
    if [[ $free_space_gb -lt $MIN_FREE_SPACE_GB ]]; then
        log_error "磁盘空间不足: ${free_space_gb}GB < ${MIN_FREE_SPACE_GB}GB"
        return 1
    fi
    
    log_info "环境检查通过，可用空间: ${free_space_gb}GB"
    return 0
}

# 创建锁文件
create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "批处理进程已在运行 (PID: $lock_pid)"
            return 1
        else
            log_info "清理过期锁文件"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    echo $$ > "$PID_FILE"
    return 0
}

# 清理锁文件
cleanup_lock() {
    rm -f "$LOCK_FILE" "$PID_FILE"
}

# 查找待处理文件
find_pending_files() {
    find "$INPUT_DIR" -type f \( \
        -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o \
        -name "*.mov" -o -name "*.wmv" -o -name "*.flv" -o \
        -name "*.m4v" -o -name "*.m2ts" -o -name "*.ts" -o \
        -name "*.vob" -o -name "*.iso" -o -name "*.rmvb" -o \
        -name "*.rm" -o -name "*.3gp" -o -name "*.f4v" -o \
        -name "*.webm" -o -name "*.strm" -o -name "*.mpg" -o \
        -name "*.mpeg" \
    \) -size +200M 2>/dev/null | head -$BATCH_SIZE
}

# 检查文件是否已处理
is_file_processed() {
    local file_path=$1
    local basename=$(basename "$file_path" | sed 's/\.[^.]*$//')
    
    # 检查输出目录中是否存在对应的NFO文件
    find "$OUTPUT_DIR" -name "${basename}*.nfo" -o -name "*${basename}*.nfo" | grep -q .
}

# 处理单个文件
process_single_file() {
    local file_path=$1
    local basename=$(basename "$file_path")
    
    log_info "开始处理: $basename"
    
    # 检查文件是否已处理
    if is_file_processed "$file_path"; then
        log_info "文件已处理，跳过: $basename"
        ((STATS_SKIPPED++))
        return 0
    fi
    
    # 检查文件稳定性
    local size1=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    sleep 5
    local size2=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    
    if [[ "$size1" != "$size2" ]]; then
        log_warn "文件可能仍在传输，跳过: $basename"
        ((STATS_SKIPPED++))
        return 0
    fi
    
    # 执行JavSP处理
    local start_time=$(date +%s)
    local temp_input="/tmp/javsp_single_$$"
    
    # 创建临时目录并链接文件
    mkdir -p "$temp_input"
    ln -s "$file_path" "$temp_input/"
    
    # 运行JavSP
    if timeout $MAX_RUNTIME python -m javsp -i "$temp_input" >> "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_info "处理完成: $basename (耗时: ${duration}秒)"
        ((STATS_PROCESSED++))
        
        # 清理临时目录
        rm -rf "$temp_input"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "处理失败: $basename (耗时: ${duration}秒)"
        ((STATS_FAILED++))
        
        # 清理临时目录
        rm -rf "$temp_input"
        return 1
    fi
}

# 批量处理文件
batch_process() {
    log_info "开始批量处理..."
    
    local files=($(find_pending_files))
    local total_files=${#files[@]}
    
    if [[ $total_files -eq 0 ]]; then
        log_info "没有找到待处理文件"
        return 0
    fi
    
    log_info "找到 $total_files 个待处理文件"
    
    local retry_count=0
    for file_path in "${files[@]}"; do
        if [[ ! -f "$file_path" ]]; then
            log_warn "文件不存在: $file_path"
            continue
        fi
        
        # 重试机制
        retry_count=0
        while [[ $retry_count -lt $RETRY_COUNT ]]; do
            if process_single_file "$file_path"; then
                break
            else
                ((retry_count++))
                if [[ $retry_count -lt $RETRY_COUNT ]]; then
                    log_warn "重试处理文件 ($retry_count/$RETRY_COUNT): $(basename "$file_path")"
                    sleep 30
                else
                    log_error "文件处理最终失败: $(basename "$file_path")"
                fi
            fi
        done
        
        # 检查是否超时
        local current_time=$(date +%s)
        local elapsed=$((current_time - STATS_START_TIME))
        if [[ $elapsed -gt $MAX_RUNTIME ]]; then
            log_warn "达到最大运行时间，停止处理"
            break
        fi
    done
}

# 清理旧日志
cleanup_logs() {
    log_info "清理旧日志文件..."
    
    # 按大小截断日志文件
    local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    local max_size=$((MAX_LOG_SIZE_MB * 1024 * 1024))
    
    if [[ $log_size -gt $max_size ]]; then
        tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log_info "日志文件已截断"
    fi
    
    # 删除7天前的错误日志
    find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # 删除临时文件
    find /tmp -name "javsp_*" -user $(whoami) -mtime +1 -delete 2>/dev/null || true
}

# 生成统计报告
generate_stats() {
    local end_time=$(date +%s)
    local total_time=$((end_time - STATS_START_TIME))
    
    # 生成JSON统计
    cat > "$STATS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "execution_time": $total_time,
    "files_processed": $STATS_PROCESSED,
    "files_failed": $STATS_FAILED,
    "files_skipped": $STATS_SKIPPED,
    "success_rate": $(echo "scale=2; $STATS_PROCESSED * 100 / ($STATS_PROCESSED + $STATS_FAILED + 1)" | bc 2>/dev/null || echo "0"),
    "avg_time_per_file": $(echo "scale=2; $total_time / ($STATS_PROCESSED + 1)" | bc 2>/dev/null || echo "0")
}
EOF
    
    log_info "统计信息:"
    log_info "  处理成功: $STATS_PROCESSED 个文件"
    log_info "  处理失败: $STATS_FAILED 个文件"
    log_info "  跳过文件: $STATS_SKIPPED 个文件"
    log_info "  总耗时: $total_time 秒"
    
    # 发送通知（如果配置了）
    send_notification
}

# 发送通知
send_notification() {
    # 这里可以添加邮件、Webhook等通知方式
    local success_rate=$(echo "scale=0; $STATS_PROCESSED * 100 / ($STATS_PROCESSED + $STATS_FAILED + 1)" | bc 2>/dev/null || echo "0")
    
    if [[ $STATS_FAILED -gt 0 ]] && [[ $success_rate -lt 80 ]]; then
        log_warn "成功率较低 ($success_rate%)，建议检查错误日志"
    fi
}

# 信号处理
handle_signal() {
    log_info "收到退出信号，正在清理..."
    cleanup_lock
    generate_stats
    exit 0
}

# 主函数
main() {
    # 设置信号处理
    trap handle_signal SIGTERM SIGINT
    
    log_info "启动 $SCRIPT_NAME v$VERSION"
    
    # 检查环境
    if ! check_environment; then
        log_error "环境检查失败"
        exit 1
    fi
    
    # 创建锁文件
    if ! create_lock; then
        log_error "无法获取处理锁"
        exit 1
    fi
    
    # 执行批处理
    batch_process
    
    # 清理日志
    cleanup_logs
    
    # 生成统计
    generate_stats
    
    # 清理锁文件
    cleanup_lock
    
    log_info "批处理完成"
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi