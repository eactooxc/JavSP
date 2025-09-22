#!/bin/bash

# JavSP 性能优化脚本
# 自动优化系统和容器性能

SCRIPT_NAME="JavSP 性能优化器"
VERSION="1.0.0"
LOG_FILE="/app/logs/optimization.log"

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

# 检查系统资源
check_system_resources() {
    log "INFO" "检查系统资源使用情况..."
    
    # CPU使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log "INFO" "CPU使用率: ${cpu_usage}%"
    
    # 内存使用率
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc)
    log "INFO" "内存使用率: ${memory_usage}%"
    
    # 磁盘使用率
    local disk_usage=$(df /app | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    log "INFO" "磁盘使用率: ${disk_usage}%"
    
    # 检查是否需要优化
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        log "WARN" "CPU使用率过高，需要优化"
        return 1
    fi
    
    if (( $(echo "$memory_usage > 85" | bc -l) )); then
        log "WARN" "内存使用率过高，需要优化"
        return 1
    fi
    
    if [[ $disk_usage -gt 90 ]]; then
        log "WARN" "磁盘使用率过高，需要清理"
        return 1
    fi
    
    log "INFO" "系统资源使用正常"
    return 0
}

# 优化Docker容器
optimize_docker_containers() {
    log "INFO" "优化Docker容器配置..."
    
    # 检查容器资源限制
    local container_id=$(docker ps --filter "name=javsp-server" --format "{{.ID}}")
    
    if [[ -n "$container_id" ]]; then
        # 获取容器统计信息
        local stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $container_id)
        log "INFO" "容器资源使用: $stats"
        
        # 检查容器内存使用
        local memory_usage=$(docker stats --no-stream --format "{{.MemPerc}}" $container_id | cut -d'%' -f1)
        
        if (( $(echo "$memory_usage > 80" | bc -l) )); then
            log "WARN" "容器内存使用过高: ${memory_usage}%"
            
            # 可以考虑重启容器释放内存
            log "INFO" "考虑重启容器以释放内存"
        fi
    fi
}

# 清理临时文件
cleanup_temp_files() {
    log "INFO" "清理临时文件..."
    
    local cleaned_size=0
    
    # 清理系统临时文件
    if [[ -d "/tmp" ]]; then
        local temp_size=$(du -s /tmp | awk '{print $1}')
        find /tmp -type f -mtime +1 -user $(whoami) -delete 2>/dev/null || true
        local new_temp_size=$(du -s /tmp | awk '{print $1}')
        cleaned_size=$((cleaned_size + temp_size - new_temp_size))
    fi
    
    # 清理应用临时文件
    if [[ -d "/app/temp" ]]; then
        local app_temp_size=$(du -s /app/temp | awk '{print $1}')
        rm -rf /app/temp/* 2>/dev/null || true
        cleaned_size=$((cleaned_size + app_temp_size))
    fi
    
    # 清理Python缓存
    find /app -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find /app -name "*.pyc" -delete 2>/dev/null || true
    
    log "INFO" "临时文件清理完成，释放空间: ${cleaned_size}KB"
}

# 优化日志文件
optimize_log_files() {
    log "INFO" "优化日志文件..."
    
    local log_dir="/app/logs"
    
    if [[ -d "$log_dir" ]]; then
        # 压缩大于100MB的日志文件
        find "$log_dir" -name "*.log" -size +100M -exec gzip {} \; 2>/dev/null || true
        
        # 删除30天前的压缩日志
        find "$log_dir" -name "*.log.gz" -mtime +30 -delete 2>/dev/null || true
        
        # 截断过大的当前日志文件
        for log_file in "$log_dir"/*.log; do
            if [[ -f "$log_file" ]]; then
                local file_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
                local max_size=$((200 * 1024 * 1024))  # 200MB
                
                if [[ $file_size -gt $max_size ]]; then
                    log "INFO" "截断大日志文件: $(basename "$log_file")"
                    tail -n 10000 "$log_file" > "${log_file}.tmp"
                    mv "${log_file}.tmp" "$log_file"
                fi
            fi
        done
    fi
}

# 优化数据库
optimize_database() {
    log "INFO" "优化数据库..."
    
    local db_file="/app/logs/monitoring.db"
    
    if [[ -f "$db_file" ]]; then
        # 使用sqlite3优化数据库
        if command -v sqlite3 &> /dev/null; then
            sqlite3 "$db_file" "VACUUM;" 2>/dev/null || true
            sqlite3 "$db_file" "REINDEX;" 2>/dev/null || true
            log "INFO" "数据库优化完成"
        fi
    fi
}

# 内存优化
optimize_memory() {
    log "INFO" "内存优化..."
    
    # 清理系统缓存（如果有权限）
    if [[ -w /proc/sys/vm/drop_caches ]]; then
        sync
        echo 3 > /proc/sys/vm/drop_caches
        log "INFO" "系统缓存已清理"
    fi
    
    # 检查并优化Python进程
    local python_processes=$(pgrep -f python | wc -l)
    if [[ $python_processes -gt 5 ]]; then
        log "WARN" "Python进程过多: $python_processes"
        # 可以考虑重启相关服务
    fi
}

# 网络优化
optimize_network() {
    log "INFO" "网络连接优化..."
    
    # 检查网络连接数
    local connections=$(netstat -an | grep ESTABLISHED | wc -l)
    log "INFO" "当前网络连接数: $connections"
    
    # 清理已断开的连接
    netstat -an | grep TIME_WAIT | wc -l | while read count; do
        if [[ $count -gt 1000 ]]; then
            log "WARN" "TIME_WAIT连接过多: $count"
        fi
    done
}

# 存储优化
optimize_storage() {
    log "INFO" "存储空间优化..."
    
    local input_dir="/app/input"
    local output_dir="/app/output"
    
    # 检查输入目录中的重复文件
    if [[ -d "$input_dir" ]]; then
        local duplicate_files=$(find "$input_dir" -type f -exec md5sum {} + 2>/dev/null | sort | uniq -d -w32 | wc -l)
        if [[ $duplicate_files -gt 0 ]]; then
            log "WARN" "发现 $duplicate_files 个可能的重复文件"
        fi
    fi
    
    # 检查输出目录大小
    if [[ -d "$output_dir" ]]; then
        local output_size=$(du -sh "$output_dir" | cut -f1)
        log "INFO" "输出目录大小: $output_size"
    fi
}

# 性能调优建议
generate_recommendations() {
    log "INFO" "生成性能调优建议..."
    
    local recommendations_file="/app/logs/performance_recommendations.txt"
    
    cat > "$recommendations_file" << EOF
# JavSP 性能调优建议
# 生成时间: $(date)

## 系统级优化建议

1. 定期监控系统资源使用情况
   - CPU使用率保持在80%以下
   - 内存使用率保持在85%以下
   - 磁盘使用率保持在90%以下

2. 定期清理临时文件和日志
   - 设置日志轮转策略
   - 清理Python缓存文件
   - 删除过期的临时文件

3. 优化Docker容器配置
   - 合理设置内存和CPU限制
   - 使用多阶段构建减少镜像大小
   - 定期更新基础镜像

## 应用级优化建议

1. 处理队列管理
   - 控制并发处理数量
   - 实现优雅的失败重试机制
   - 监控队列积压情况

2. 网络请求优化
   - 设置合理的超时时间
   - 实现请求缓存机制
   - 使用连接池复用连接

3. 存储空间管理
   - 定期清理已处理文件
   - 实现文件去重机制
   - 监控磁盘空间使用

## 网络部署优化

1. 带宽管理
   - 限制上传下载速度
   - 实现传输断点续传
   - 优化文件传输协议

2. 负载均衡
   - 考虑多实例部署
   - 实现请求分发机制
   - 监控各节点负载

3. 缓存策略
   - 实现元数据缓存
   - 使用本地缓存减少网络请求
   - 定期清理过期缓存
EOF

    log "INFO" "性能建议已生成: $recommendations_file"
}

# 自动优化
auto_optimize() {
    log "INFO" "开始自动性能优化..."
    
    # 基础清理和优化
    cleanup_temp_files
    optimize_log_files
    optimize_database
    
    # 检查系统资源
    if ! check_system_resources; then
        log "WARN" "系统资源紧张，执行深度优化..."
        optimize_memory
        optimize_docker_containers
    fi
    
    # 网络和存储优化
    optimize_network
    optimize_storage
    
    log "INFO" "自动优化完成"
}

# 性能测试
performance_test() {
    log "INFO" "开始性能测试..."
    
    local test_start=$(date +%s)
    
    # 测试文件I/O性能
    local test_file="/tmp/javsp_io_test"
    dd if=/dev/zero of="$test_file" bs=1M count=100 2>/dev/null
    local write_time=$(date +%s)
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null
    local read_time=$(date +%s)
    rm -f "$test_file"
    
    local io_write_time=$((write_time - test_start))
    local io_read_time=$((read_time - write_time))
    
    log "INFO" "I/O性能测试 - 写入: ${io_write_time}s, 读取: ${io_read_time}s"
    
    # 测试网络连接
    local network_test_start=$(date +%s)
    if ping -c 5 google.com &>/dev/null; then
        local network_test_end=$(date +%s)
        local network_time=$((network_test_end - network_test_start))
        log "INFO" "网络连通性测试通过，耗时: ${network_time}s"
    else
        log "WARN" "网络连通性测试失败"
    fi
    
    log "INFO" "性能测试完成"
}

# 显示使用帮助
show_usage() {
    echo "使用方法:"
    echo "  $0 auto                  - 自动优化"
    echo "  $0 check                 - 检查系统资源"
    echo "  $0 cleanup               - 清理临时文件"
    echo "  $0 optimize-logs         - 优化日志文件"
    echo "  $0 optimize-db           - 优化数据库"
    echo "  $0 optimize-memory       - 内存优化"
    echo "  $0 optimize-network      - 网络优化"
    echo "  $0 optimize-storage      - 存储优化"
    echo "  $0 test                  - 性能测试"
    echo "  $0 recommendations       - 生成优化建议"
    echo "  $0 help                  - 显示帮助信息"
}

# 主函数
main() {
    local action=${1:-auto}
    
    print_header
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$action" in
        "auto")
            auto_optimize
            generate_recommendations
            ;;
        "check")
            check_system_resources
            ;;
        "cleanup")
            cleanup_temp_files
            ;;
        "optimize-logs")
            optimize_log_files
            ;;
        "optimize-db")
            optimize_database
            ;;
        "optimize-memory")
            optimize_memory
            ;;
        "optimize-network")
            optimize_network
            ;;
        "optimize-storage")
            optimize_storage
            ;;
        "test")
            performance_test
            ;;
        "recommendations")
            generate_recommendations
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 执行主函数
main "$@"