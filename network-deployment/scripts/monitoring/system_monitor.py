#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
JavSP 系统监控器
实时监控JavSP网络部署的性能和健康状态
"""

import os
import sys
import json
import time
import psutil
import logging
import subprocess
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from pathlib import Path
import sqlite3

try:
    import docker
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False

@dataclass
class MetricData:
    """监控指标数据类"""
    name: str
    value: float
    unit: str
    timestamp: datetime
    status: str  # normal, warning, critical
    threshold_warning: Optional[float] = None
    threshold_critical: Optional[float] = None

@dataclass
class Alert:
    """告警数据类"""
    id: str
    level: str  # warning, critical
    message: str
    timestamp: datetime
    source: str
    resolved: bool = False
    resolved_time: Optional[datetime] = None

class SystemMonitor:
    """系统监控器"""
    
    def __init__(self, config_path: str = "/app/config/monitor.json"):
        self.config_path = config_path
        self.config = self.load_config()
        self.setup_logging()
        
        # 数据库连接
        self.db_path = "/app/logs/monitoring.db"
        self.init_database()
        
        # Docker客户端
        self.docker_client = None
        if DOCKER_AVAILABLE:
            try:
                self.docker_client = docker.from_env()
            except Exception as e:
                self.logger.warning(f"Docker客户端初始化失败: {e}")
        
        # 监控状态
        self.is_running = True
        self.metrics_cache = {}
        self.active_alerts = {}
        
        self.logger.info("系统监控器初始化完成")
    
    def load_config(self) -> Dict[str, Any]:
        """加载配置文件"""
        default_config = {
            "system_monitoring": {"enabled": True, "check_interval": 60},
            "container_monitoring": {"enabled": True, "check_interval": 60},
            "application_monitoring": {"enabled": True, "check_interval": 120},
            "network_monitoring": {"enabled": True, "check_interval": 300},
            "log_monitoring": {"enabled": True, "check_interval": 180},
            "alerting": {"enabled": True, "channels": {"file": {"enabled": True, "path": "/app/logs/alerts.log"}}},
            "performance_optimization": {"resource_limits": {"container_memory": "2GB", "container_cpu": "2"}},
            "health_checks": {"enabled": True, "failure_threshold": 3},
            "reporting": {"enabled": True}
        }
        
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    user_config = json.load(f)
                    self._merge_config(default_config, user_config)
            except Exception as e:
                print(f"配置文件加载失败，使用默认配置: {e}")
        
        return default_config
    
    def _merge_config(self, default: Dict, user: Dict) -> None:
        """递归合并配置"""
        for key, value in user.items():
            if key in default and isinstance(default[key], dict) and isinstance(value, dict):
                self._merge_config(default[key], value)
            else:
                default[key] = value
    
    def setup_logging(self):
        """设置日志"""
        log_dir = Path("/app/logs")
        log_dir.mkdir(exist_ok=True)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
            handlers=[
                logging.FileHandler(log_dir / "monitor.log", encoding='utf-8'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger("SystemMonitor")
    
    def init_database(self):
        """初始化数据库"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 创建指标表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                value REAL NOT NULL,
                unit TEXT NOT NULL,
                status TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
                threshold_warning REAL,
                threshold_critical REAL
            )
        ''')
        
        # 创建告警表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
                id TEXT PRIMARY KEY,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                source TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
                resolved BOOLEAN DEFAULT 0,
                resolved_time DATETIME
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def store_metric(self, metric: MetricData):
        """存储监控指标"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO metrics (name, value, unit, status, timestamp, threshold_warning, threshold_critical)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            metric.name, metric.value, metric.unit, metric.status,
            metric.timestamp.isoformat(), metric.threshold_warning, metric.threshold_critical
        ))
        
        conn.commit()
        conn.close()
        
        # 缓存最新值
        self.metrics_cache[metric.name] = metric
    
    def store_alert(self, alert: Alert):
        """存储告警"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO alerts (id, level, message, source, timestamp, resolved, resolved_time)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            alert.id, alert.level, alert.message, alert.source,
            alert.timestamp.isoformat(), alert.resolved,
            alert.resolved_time.isoformat() if alert.resolved_time else None
        ))
        
        conn.commit()
        conn.close()
    
    def check_system_metrics(self):
        """检查系统指标"""
        if not self.config["system_monitoring"]["enabled"]:
            return
        
        # CPU使用率
        cpu_config = self.config["system_monitoring"]["metrics"]["cpu_usage"]
        if cpu_config["enabled"]:
            cpu_percent = psutil.cpu_percent(interval=1)
            status = "normal"
            if cpu_percent >= cpu_config["threshold_critical"]:
                status = "critical"
            elif cpu_percent >= cpu_config["threshold_warning"]:
                status = "warning"
            
            metric = MetricData(
                name="cpu_usage",
                value=cpu_percent,
                unit="percent",
                timestamp=datetime.now(),
                status=status,
                threshold_warning=cpu_config["threshold_warning"],
                threshold_critical=cpu_config["threshold_critical"]
            )
            self.store_metric(metric)
            
            if status != "normal":
                self.create_alert(f"CPU使用率过高: {cpu_percent:.1f}%", status, "system")
        
        # 内存使用率
        memory_config = self.config["system_monitoring"]["metrics"]["memory_usage"]
        if memory_config["enabled"]:
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            status = "normal"
            if memory_percent >= memory_config["threshold_critical"]:
                status = "critical"
            elif memory_percent >= memory_config["threshold_warning"]:
                status = "warning"
            
            metric = MetricData(
                name="memory_usage",
                value=memory_percent,
                unit="percent",
                timestamp=datetime.now(),
                status=status,
                threshold_warning=memory_config["threshold_warning"],
                threshold_critical=memory_config["threshold_critical"]
            )
            self.store_metric(metric)
            
            if status != "normal":
                self.create_alert(f"内存使用率过高: {memory_percent:.1f}%", status, "system")
        
        # 磁盘使用率
        disk_config = self.config["system_monitoring"]["metrics"]["disk_usage"]
        if disk_config["enabled"]:
            for path in disk_config["monitored_paths"]:
                if os.path.exists(path):
                    disk = psutil.disk_usage(path)
                    disk_percent = (disk.used / disk.total) * 100
                    status = "normal"
                    if disk_percent >= disk_config["threshold_critical"]:
                        status = "critical"
                    elif disk_percent >= disk_config["threshold_warning"]:
                        status = "warning"
                    
                    metric = MetricData(
                        name=f"disk_usage_{path.replace('/', '_')}",
                        value=disk_percent,
                        unit="percent",
                        timestamp=datetime.now(),
                        status=status,
                        threshold_warning=disk_config["threshold_warning"],
                        threshold_critical=disk_config["threshold_critical"]
                    )
                    self.store_metric(metric)
                    
                    if status != "normal":
                        self.create_alert(f"磁盘空间不足 {path}: {disk_percent:.1f}%", status, "system")
    
    def check_container_metrics(self):
        """检查容器指标"""
        if not self.config["container_monitoring"]["enabled"] or not self.docker_client:
            return
        
        container_config = self.config["container_monitoring"]
        
        for container_name in container_config["containers"]:
            try:
                container = self.docker_client.containers.get(container_name)
                
                # 容器状态
                status_config = container_config["metrics"]["container_status"]
                if status_config["enabled"]:
                    container_status = container.status
                    expected_status = status_config["expected_status"]
                    
                    if container_status != expected_status:
                        self.create_alert(
                            f"容器状态异常 {container_name}: {container_status} (期望: {expected_status})",
                            "critical", "container"
                        )
                
                # 容器资源使用
                stats = container.stats(stream=False)
                
                # 内存使用
                memory_config = container_config["metrics"]["container_memory"]
                if memory_config["enabled"] and "memory" in stats:
                    memory_usage = stats["memory"]["usage"]
                    memory_limit = stats["memory"]["limit"]
                    memory_percent = (memory_usage / memory_limit) * 100
                    
                    metric = MetricData(
                        name=f"container_memory_{container_name}",
                        value=memory_percent,
                        unit="percent",
                        timestamp=datetime.now(),
                        status="normal"
                    )
                    self.store_metric(metric)
                
                # CPU使用
                cpu_config = container_config["metrics"]["container_cpu"]
                if cpu_config["enabled"] and "cpu" in stats:
                    # 计算CPU使用率
                    cpu_delta = stats["cpu"]["cpu_usage"]["total_usage"] - stats["precpu"]["cpu_usage"]["total_usage"]
                    system_delta = stats["cpu"]["system_cpu_usage"] - stats["precpu"]["system_cpu_usage"]
                    cpu_count = len(stats["cpu"]["cpu_usage"]["percpu_usage"])
                    
                    if system_delta > 0:
                        cpu_percent = (cpu_delta / system_delta) * cpu_count * 100
                        
                        metric = MetricData(
                            name=f"container_cpu_{container_name}",
                            value=cpu_percent,
                            unit="percent",
                            timestamp=datetime.now(),
                            status="normal"
                        )
                        self.store_metric(metric)
                
            except Exception as e:
                self.logger.error(f"检查容器 {container_name} 失败: {e}")
                self.create_alert(f"容器监控失败 {container_name}: {str(e)}", "warning", "container")
    
    def check_application_metrics(self):
        """检查应用指标"""
        if not self.config["application_monitoring"]["enabled"]:
            return
        
        # 检查处理队列
        queue_config = self.config["application_monitoring"]["metrics"]["processing_queue"]
        if queue_config["enabled"]:
            try:
                # 这里需要根据实际的JavSP状态文件来检查
                state_file = "/app/logs/monitor_state.json"
                if os.path.exists(state_file):
                    with open(state_file, 'r', encoding='utf-8') as f:
                        state = json.load(f)
                    
                    queue_length = state.get('queue_length', 0)
                    
                    status = "normal"
                    if queue_length >= queue_config["threshold_critical"]:
                        status = "critical"
                    elif queue_length >= queue_config["threshold_warning"]:
                        status = "warning"
                    
                    metric = MetricData(
                        name="processing_queue_length",
                        value=queue_length,
                        unit="count",
                        timestamp=datetime.now(),
                        status=status,
                        threshold_warning=queue_config["threshold_warning"],
                        threshold_critical=queue_config["threshold_critical"]
                    )
                    self.store_metric(metric)
                    
                    if status != "normal":
                        self.create_alert(f"处理队列积压: {queue_length} 个任务", status, "application")
            
            except Exception as e:
                self.logger.error(f"检查应用指标失败: {e}")
    
    def create_alert(self, message: str, level: str, source: str):
        """创建告警"""
        alert_id = f"{source}_{level}_{hash(message) % 10000}"
        
        # 检查是否已存在相同告警
        if alert_id in self.active_alerts:
            return
        
        alert = Alert(
            id=alert_id,
            level=level,
            message=message,
            timestamp=datetime.now(),
            source=source
        )
        
        self.active_alerts[alert_id] = alert
        self.store_alert(alert)
        self.send_notification(alert)
        
        self.logger.warning(f"告警生成 [{level.upper()}] {source}: {message}")
    
    def send_notification(self, alert: Alert):
        """发送告警通知"""
        if not self.config["alerting"]["enabled"]:
            return
        
        channels = self.config["alerting"]["channels"]
        
        # 文件通知
        if channels["file"]["enabled"]:
            try:
                alert_log = channels["file"]["path"]
                os.makedirs(os.path.dirname(alert_log), exist_ok=True)
                
                with open(alert_log, 'a', encoding='utf-8') as f:
                    f.write(f"[{alert.timestamp.isoformat()}] [{alert.level.upper()}] {alert.source}: {alert.message}\n")
            except Exception as e:
                self.logger.error(f"文件告警发送失败: {e}")
        
        # 可以添加其他通知方式（邮件、Webhook等）
    
    def generate_report(self):
        """生成监控报告"""
        if not self.config["reporting"]["enabled"]:
            return
        
        try:
            report_data = {
                "timestamp": datetime.now().isoformat(),
                "system_status": "healthy",
                "metrics_summary": {},
                "active_alerts": len(self.active_alerts),
                "recommendations": []
            }
            
            # 获取最近的指标数据
            for metric_name, metric in self.metrics_cache.items():
                report_data["metrics_summary"][metric_name] = {
                    "value": metric.value,
                    "unit": metric.unit,
                    "status": metric.status,
                    "timestamp": metric.timestamp.isoformat()
                }
            
            # 生成建议
            if any(m.status == "critical" for m in self.metrics_cache.values()):
                report_data["system_status"] = "critical"
                report_data["recommendations"].append("存在严重问题，需要立即处理")
            elif any(m.status == "warning" for m in self.metrics_cache.values()):
                report_data["system_status"] = "warning"
                report_data["recommendations"].append("存在潜在问题，建议关注")
            
            # 保存报告
            report_file = f"/app/logs/report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(report_file, 'w', encoding='utf-8') as f:
                json.dump(report_data, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"监控报告已生成: {report_file}")
            
        except Exception as e:
            self.logger.error(f"生成报告失败: {e}")
    
    def cleanup_old_data(self):
        """清理过期数据"""
        try:
            # 清理30天前的指标数据
            cutoff_date = datetime.now() - timedelta(days=30)
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('DELETE FROM metrics WHERE timestamp < ?', (cutoff_date.isoformat(),))
            cursor.execute('DELETE FROM alerts WHERE timestamp < ? AND resolved = 1', (cutoff_date.isoformat(),))
            
            conn.commit()
            conn.close()
            
            self.logger.info("过期数据清理完成")
            
        except Exception as e:
            self.logger.error(f"数据清理失败: {e}")
    
    def run(self):
        """主运行循环"""
        self.logger.info("启动系统监控器")
        
        last_cleanup = datetime.now()
        
        while self.is_running:
            try:
                # 系统监控
                if self.config["system_monitoring"]["enabled"]:
                    self.check_system_metrics()
                
                # 容器监控
                if self.config["container_monitoring"]["enabled"]:
                    self.check_container_metrics()
                
                # 应用监控
                if self.config["application_monitoring"]["enabled"]:
                    self.check_application_metrics()
                
                # 每小时生成一次报告
                if datetime.now().minute == 0:
                    self.generate_report()
                
                # 每天清理一次过期数据
                if datetime.now() - last_cleanup > timedelta(hours=24):
                    self.cleanup_old_data()
                    last_cleanup = datetime.now()
                
                # 等待下次检查
                time.sleep(self.config["system_monitoring"]["check_interval"])
                
            except Exception as e:
                self.logger.error(f"监控循环异常: {e}")
                time.sleep(60)
        
        self.logger.info("系统监控器已停止")

def main():
    """主函数"""
    monitor = SystemMonitor()
    
    try:
        monitor.run()
    except KeyboardInterrupt:
        monitor.logger.info("收到中断信号，停止监控")
        monitor.is_running = False

if __name__ == "__main__":
    main()