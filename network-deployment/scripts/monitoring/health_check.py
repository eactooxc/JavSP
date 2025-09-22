#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
JavSP 健康检查和维护脚本
定期检查系统健康状态并执行维护任务
"""

import os
import sys
import json
import time
import logging
import subprocess
import schedule
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict

@dataclass
class HealthStatus:
    """健康状态数据类"""
    component: str
    status: str  # healthy, warning, critical, unknown
    message: str
    timestamp: datetime
    details: Optional[Dict[str, Any]] = None

class HealthChecker:
    """健康检查器"""
    
    def __init__(self, config_path: str = "/app/config/health_check.json"):
        self.config_path = config_path
        self.config = self.load_config()
        self.setup_logging()
        
        # 健康状态缓存
        self.health_status = {}
        self.last_maintenance = None
        
        self.logger.info("健康检查器初始化完成")
    
    def load_config(self) -> Dict[str, Any]:
        """加载配置"""
        default_config = {
            "health_checks": {
                "enabled": True,
                "interval": 300,  # 5分钟
                "components": {
                    "docker": {"enabled": True, "timeout": 30},
                    "filesystem": {"enabled": True, "timeout": 10},
                    "network": {"enabled": True, "timeout": 15},
                    "application": {"enabled": True, "timeout": 20}
                }
            },
            "maintenance": {
                "enabled": True,
                "daily_time": "03:00",
                "weekly_day": "sunday",
                "tasks": {
                    "cleanup_logs": True,
                    "optimize_database": True,
                    "check_disk_space": True,
                    "update_stats": True
                }
            },
            "alerting": {
                "enabled": True,
                "critical_immediate": True,
                "warning_threshold": 3,
                "recovery_notification": True
            },
            "reporting": {
                "enabled": True,
                "daily_report": True,
                "weekly_summary": True
            }
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
                logging.FileHandler(log_dir / "health_check.log", encoding='utf-8'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger("HealthChecker")
    
    def check_docker_health(self) -> HealthStatus:
        """检查Docker健康状态"""
        try:
            # 检查Docker服务
            result = subprocess.run(['docker', 'info'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return HealthStatus(
                    component="docker",
                    status="critical",
                    message="Docker服务未运行",
                    timestamp=datetime.now()
                )
            
            # 检查JavSP容器
            result = subprocess.run(['docker', 'ps', '--filter', 'name=javsp-server', '--format', '{{.Status}}'],
                                  capture_output=True, text=True, timeout=10)
            
            if not result.stdout.strip():
                return HealthStatus(
                    component="docker",
                    status="critical",
                    message="JavSP容器未运行",
                    timestamp=datetime.now()
                )
            
            container_status = result.stdout.strip()
            if "Up" not in container_status:
                return HealthStatus(
                    component="docker",
                    status="warning",
                    message=f"JavSP容器状态异常: {container_status}",
                    timestamp=datetime.now()
                )
            
            # 检查容器资源使用
            result = subprocess.run(['docker', 'stats', '--no-stream', '--format', 
                                   '{{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}', 'javsp-server'],
                                  capture_output=True, text=True, timeout=10)
            
            if result.stdout.strip():
                parts = result.stdout.strip().split('\t')
                cpu_percent = float(parts[1].rstrip('%'))
                mem_percent = float(parts[2].rstrip('%'))
                
                details = {
                    "cpu_usage": cpu_percent,
                    "memory_usage": mem_percent,
                    "container_status": container_status
                }
                
                if cpu_percent > 90 or mem_percent > 90:
                    return HealthStatus(
                        component="docker",
                        status="warning",
                        message=f"容器资源使用过高 CPU:{cpu_percent}% MEM:{mem_percent}%",
                        timestamp=datetime.now(),
                        details=details
                    )
                
                return HealthStatus(
                    component="docker",
                    status="healthy",
                    message="Docker和容器运行正常",
                    timestamp=datetime.now(),
                    details=details
                )
            
            return HealthStatus(
                component="docker",
                status="healthy",
                message="Docker服务运行正常",
                timestamp=datetime.now()
            )
            
        except subprocess.TimeoutExpired:
            return HealthStatus(
                component="docker",
                status="warning",
                message="Docker检查超时",
                timestamp=datetime.now()
            )
        except Exception as e:
            return HealthStatus(
                component="docker",
                status="critical",
                message=f"Docker检查失败: {str(e)}",
                timestamp=datetime.now()
            )
    
    def check_filesystem_health(self) -> HealthStatus:
        """检查文件系统健康状态"""
        try:
            issues = []
            details = {}
            
            # 检查关键目录
            critical_dirs = ["/app/input", "/app/output", "/app/logs", "/app/config"]
            
            for dir_path in critical_dirs:
                if not os.path.exists(dir_path):
                    issues.append(f"目录不存在: {dir_path}")
                elif not os.access(dir_path, os.W_OK):
                    issues.append(f"目录权限不足: {dir_path}")
            
            # 检查磁盘空间
            import shutil
            for path in ["/app"]:
                if os.path.exists(path):
                    total, used, free = shutil.disk_usage(path)
                    usage_percent = (used / total) * 100
                    details[f"disk_usage_{path}"] = {
                        "total_gb": round(total / (1024**3), 2),
                        "used_gb": round(used / (1024**3), 2),
                        "free_gb": round(free / (1024**3), 2),
                        "usage_percent": round(usage_percent, 1)
                    }
                    
                    if usage_percent > 95:
                        issues.append(f"磁盘空间严重不足: {path} ({usage_percent:.1f}%)")
                    elif usage_percent > 85:
                        issues.append(f"磁盘空间紧张: {path} ({usage_percent:.1f}%)")
            
            # 检查文件数量
            for dir_path in ["/app/input", "/app/output"]:
                if os.path.exists(dir_path):
                    file_count = len([f for f in os.listdir(dir_path) if os.path.isfile(os.path.join(dir_path, f))])
                    details[f"file_count_{dir_path}"] = file_count
                    
                    if dir_path == "/app/input" and file_count > 1000:
                        issues.append(f"输入目录文件过多: {file_count}")
            
            if issues:
                status = "critical" if any("严重" in issue for issue in issues) else "warning"
                return HealthStatus(
                    component="filesystem",
                    status=status,
                    message="; ".join(issues),
                    timestamp=datetime.now(),
                    details=details
                )
            
            return HealthStatus(
                component="filesystem",
                status="healthy",
                message="文件系统状态正常",
                timestamp=datetime.now(),
                details=details
            )
            
        except Exception as e:
            return HealthStatus(
                component="filesystem",
                status="critical",
                message=f"文件系统检查失败: {str(e)}",
                timestamp=datetime.now()
            )
    
    def check_network_health(self) -> HealthStatus:
        """检查网络健康状态"""
        try:
            issues = []
            details = {}
            
            # 检查基本网络连通性
            result = subprocess.run(['ping', '-c', '3', '8.8.8.8'], 
                                  capture_output=True, text=True, timeout=15)
            
            if result.returncode != 0:
                issues.append("基本网络连接失败")
            else:
                # 解析ping结果获取延迟
                output_lines = result.stdout.split('\n')
                for line in output_lines:
                    if 'avg' in line or 'min/avg/max' in line:
                        # 提取平均延迟
                        parts = line.split('/')
                        if len(parts) >= 5:
                            avg_latency = float(parts[4])
                            details["ping_latency_ms"] = avg_latency
                            
                            if avg_latency > 1000:
                                issues.append(f"网络延迟过高: {avg_latency}ms")
            
            # 检查DNS解析
            result = subprocess.run(['nslookup', 'google.com'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                issues.append("DNS解析失败")
            else:
                details["dns_resolution"] = "working"
            
            # 检查数据源网站连通性
            test_sites = ["javbus.com", "javdb.com"]
            accessible_sites = 0
            
            for site in test_sites:
                try:
                    result = subprocess.run(['curl', '-Is', '--connect-timeout', '10', f'https://{site}'], 
                                          capture_output=True, text=True, timeout=15)
                    if result.returncode == 0:
                        accessible_sites += 1
                except:
                    pass
            
            details["accessible_data_sources"] = f"{accessible_sites}/{len(test_sites)}"
            
            if accessible_sites == 0:
                issues.append("所有数据源网站无法访问")
            elif accessible_sites < len(test_sites):
                issues.append(f"部分数据源网站无法访问 ({accessible_sites}/{len(test_sites)})")
            
            if issues:
                return HealthStatus(
                    component="network",
                    status="warning" if accessible_sites > 0 else "critical",
                    message="; ".join(issues),
                    timestamp=datetime.now(),
                    details=details
                )
            
            return HealthStatus(
                component="network",
                status="healthy",
                message="网络连接正常",
                timestamp=datetime.now(),
                details=details
            )
            
        except Exception as e:
            return HealthStatus(
                component="network",
                status="critical",
                message=f"网络检查失败: {str(e)}",
                timestamp=datetime.now()
            )
    
    def check_application_health(self) -> HealthStatus:
        """检查应用健康状态"""
        try:
            issues = []
            details = {}
            
            # 检查配置文件
            config_file = "/app/config.yml"
            if not os.path.exists(config_file):
                issues.append("配置文件不存在")
            else:
                details["config_file"] = "exists"
                
                # 简单的配置文件格式检查
                try:
                    with open(config_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if len(content) < 100:
                            issues.append("配置文件内容异常")
                except Exception as e:
                    issues.append(f"配置文件读取失败: {str(e)}")
            
            # 检查应用进程
            try:
                result = subprocess.run(['docker', 'exec', 'javsp-server', 'pgrep', '-f', 'python'],
                                      capture_output=True, text=True, timeout=10)
                
                if result.stdout.strip():
                    process_count = len(result.stdout.strip().split('\n'))
                    details["python_processes"] = process_count
                    
                    if process_count > 10:
                        issues.append(f"Python进程过多: {process_count}")
                else:
                    issues.append("未找到Python进程")
            except:
                issues.append("无法检查应用进程")
            
            # 检查处理队列状态
            state_file = "/app/logs/monitor_state.json"
            if os.path.exists(state_file):
                try:
                    with open(state_file, 'r', encoding='utf-8') as f:
                        state = json.load(f)
                    
                    queue_length = state.get('queue_length', 0)
                    details["processing_queue"] = queue_length
                    
                    if queue_length > 100:
                        issues.append(f"处理队列积压严重: {queue_length}")
                    elif queue_length > 50:
                        issues.append(f"处理队列积压: {queue_length}")
                    
                    # 检查最后活动时间
                    last_activity = state.get('last_activity')
                    if last_activity:
                        last_time = datetime.fromisoformat(last_activity.replace('Z', '+00:00'))
                        inactive_hours = (datetime.now() - last_time).total_seconds() / 3600
                        
                        if inactive_hours > 24:
                            issues.append(f"系统长时间无活动: {inactive_hours:.1f}小时")
                        
                        details["last_activity_hours_ago"] = round(inactive_hours, 1)
                
                except Exception as e:
                    issues.append(f"状态文件解析失败: {str(e)}")
            
            # 检查日志文件中的错误
            log_files = ["/app/logs/javsp.log", "/app/logs/batch_process.log"]
            recent_errors = 0
            
            for log_file in log_files:
                if os.path.exists(log_file):
                    try:
                        # 检查最近1小时的错误
                        result = subprocess.run(
                            ['tail', '-n', '1000', log_file],
                            capture_output=True, text=True, timeout=5
                        )
                        
                        if result.stdout:
                            lines = result.stdout.split('\n')
                            for line in lines:
                                if any(keyword in line.lower() for keyword in ['error', 'exception', 'failed', 'critical']):
                                    # 简单的时间检查（假设日志有时间戳）
                                    recent_errors += 1
                    except:
                        pass
            
            details["recent_errors"] = recent_errors
            
            if recent_errors > 20:
                issues.append(f"最近错误过多: {recent_errors}")
            elif recent_errors > 10:
                issues.append(f"最近有较多错误: {recent_errors}")
            
            if issues:
                return HealthStatus(
                    component="application",
                    status="warning",
                    message="; ".join(issues),
                    timestamp=datetime.now(),
                    details=details
                )
            
            return HealthStatus(
                component="application",
                status="healthy",
                message="应用运行正常",
                timestamp=datetime.now(),
                details=details
            )
            
        except Exception as e:
            return HealthStatus(
                component="application",
                status="critical",
                message=f"应用检查失败: {str(e)}",
                timestamp=datetime.now()
            )
    
    def perform_health_check(self) -> Dict[str, HealthStatus]:
        """执行健康检查"""
        self.logger.info("开始健康检查...")
        
        checks = {}
        components = self.config["health_checks"]["components"]
        
        if components["docker"]["enabled"]:
            checks["docker"] = self.check_docker_health()
        
        if components["filesystem"]["enabled"]:
            checks["filesystem"] = self.check_filesystem_health()
        
        if components["network"]["enabled"]:
            checks["network"] = self.check_network_health()
        
        if components["application"]["enabled"]:
            checks["application"] = self.check_application_health()
        
        # 更新健康状态缓存
        self.health_status.update(checks)
        
        # 保存健康检查结果
        self.save_health_status(checks)
        
        # 发送告警
        self.check_and_send_alerts(checks)
        
        self.logger.info("健康检查完成")
        return checks
    
    def save_health_status(self, status: Dict[str, HealthStatus]):
        """保存健康状态"""
        try:
            status_file = "/app/logs/health_status.json"
            
            status_data = {
                "timestamp": datetime.now().isoformat(),
                "overall_status": self.calculate_overall_status(status),
                "components": {}
            }
            
            for component, health in status.items():
                status_data["components"][component] = {
                    "status": health.status,
                    "message": health.message,
                    "timestamp": health.timestamp.isoformat(),
                    "details": health.details
                }
            
            with open(status_file, 'w', encoding='utf-8') as f:
                json.dump(status_data, f, indent=2, ensure_ascii=False)
                
        except Exception as e:
            self.logger.error(f"保存健康状态失败: {e}")
    
    def calculate_overall_status(self, status: Dict[str, HealthStatus]) -> str:
        """计算总体健康状态"""
        if any(h.status == "critical" for h in status.values()):
            return "critical"
        elif any(h.status == "warning" for h in status.values()):
            return "warning"
        else:
            return "healthy"
    
    def check_and_send_alerts(self, status: Dict[str, HealthStatus]):
        """检查并发送告警"""
        if not self.config["alerting"]["enabled"]:
            return
        
        for component, health in status.items():
            if health.status in ["critical", "warning"]:
                self.send_alert(health)
    
    def send_alert(self, health: HealthStatus):
        """发送告警"""
        try:
            alert_file = "/app/logs/health_alerts.log"
            
            alert_message = f"[{datetime.now().isoformat()}] [{health.status.upper()}] {health.component}: {health.message}"
            
            with open(alert_file, 'a', encoding='utf-8') as f:
                f.write(alert_message + '\n')
            
            self.logger.warning(f"健康告警: {alert_message}")
            
        except Exception as e:
            self.logger.error(f"发送告警失败: {e}")
    
    def perform_maintenance(self):
        """执行维护任务"""
        if not self.config["maintenance"]["enabled"]:
            return
        
        self.logger.info("开始执行维护任务...")
        
        tasks = self.config["maintenance"]["tasks"]
        
        if tasks.get("cleanup_logs", False):
            self.cleanup_logs()
        
        if tasks.get("optimize_database", False):
            self.optimize_database()
        
        if tasks.get("check_disk_space", False):
            self.check_disk_space()
        
        if tasks.get("update_stats", False):
            self.update_stats()
        
        self.last_maintenance = datetime.now()
        self.logger.info("维护任务完成")
    
    def cleanup_logs(self):
        """清理日志文件"""
        try:
            log_dir = Path("/app/logs")
            
            # 删除30天前的日志文件
            cutoff_date = datetime.now() - timedelta(days=30)
            
            for log_file in log_dir.glob("*.log"):
                if log_file.stat().st_mtime < cutoff_date.timestamp():
                    log_file.unlink()
                    self.logger.info(f"删除过期日志: {log_file}")
            
            # 压缩大日志文件
            for log_file in log_dir.glob("*.log"):
                if log_file.stat().st_size > 100 * 1024 * 1024:  # 100MB
                    subprocess.run(['gzip', str(log_file)], timeout=60)
                    self.logger.info(f"压缩大日志文件: {log_file}")
                    
        except Exception as e:
            self.logger.error(f"日志清理失败: {e}")
    
    def optimize_database(self):
        """优化数据库"""
        try:
            db_file = "/app/logs/monitoring.db"
            
            if os.path.exists(db_file):
                subprocess.run(['sqlite3', db_file, 'VACUUM;'], timeout=60)
                self.logger.info("数据库优化完成")
                
        except Exception as e:
            self.logger.error(f"数据库优化失败: {e}")
    
    def check_disk_space(self):
        """检查磁盘空间"""
        try:
            import shutil
            
            paths = ["/app", "/tmp"]
            
            for path in paths:
                if os.path.exists(path):
                    total, used, free = shutil.disk_usage(path)
                    usage_percent = (used / total) * 100
                    
                    self.logger.info(f"磁盘使用 {path}: {usage_percent:.1f}% ({free // (1024**3)}GB 可用)")
                    
                    if usage_percent > 90:
                        self.logger.warning(f"磁盘空间不足: {path} ({usage_percent:.1f}%)")
                        
        except Exception as e:
            self.logger.error(f"磁盘空间检查失败: {e}")
    
    def update_stats(self):
        """更新统计信息"""
        try:
            stats = {
                "timestamp": datetime.now().isoformat(),
                "uptime": self.get_uptime(),
                "health_checks_performed": getattr(self, 'checks_performed', 0),
                "last_maintenance": self.last_maintenance.isoformat() if self.last_maintenance else None,
                "overall_health": self.calculate_overall_status(self.health_status)
            }
            
            stats_file = "/app/logs/system_stats.json"
            with open(stats_file, 'w', encoding='utf-8') as f:
                json.dump(stats, f, indent=2, ensure_ascii=False)
                
        except Exception as e:
            self.logger.error(f"统计更新失败: {e}")
    
    def get_uptime(self) -> str:
        """获取系统运行时间"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.readline().split()[0])
                uptime_days = uptime_seconds // 86400
                uptime_hours = (uptime_seconds % 86400) // 3600
                return f"{int(uptime_days)}天{int(uptime_hours)}小时"
        except:
            return "未知"
    
    def generate_daily_report(self):
        """生成日常报告"""
        try:
            report = {
                "date": datetime.now().strftime("%Y-%m-%d"),
                "overall_status": self.calculate_overall_status(self.health_status),
                "health_summary": {},
                "maintenance_performed": self.last_maintenance is not None,
                "recommendations": []
            }
            
            for component, health in self.health_status.items():
                report["health_summary"][component] = {
                    "status": health.status,
                    "message": health.message
                }
            
            # 生成建议
            if any(h.status == "critical" for h in self.health_status.values()):
                report["recommendations"].append("存在严重问题，需要立即处理")
            
            if any(h.status == "warning" for h in self.health_status.values()):
                report["recommendations"].append("存在警告问题，建议关注")
            
            report_file = f"/app/logs/daily_report_{datetime.now().strftime('%Y%m%d')}.json"
            with open(report_file, 'w', encoding='utf-8') as f:
                json.dump(report, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"日常报告已生成: {report_file}")
            
        except Exception as e:
            self.logger.error(f"生成日常报告失败: {e}")
    
    def run(self):
        """运行健康检查服务"""
        self.logger.info("启动健康检查服务")
        
        # 设置定时任务
        interval = self.config["health_checks"]["interval"]
        schedule.every(interval).seconds.do(self.perform_health_check)
        
        # 设置每日维护任务
        maintenance_time = self.config["maintenance"]["daily_time"]
        schedule.every().day.at(maintenance_time).do(self.perform_maintenance)
        
        # 设置每日报告
        if self.config["reporting"]["daily_report"]:
            schedule.every().day.at("06:00").do(self.generate_daily_report)
        
        # 立即执行一次健康检查
        self.perform_health_check()
        
        # 主循环
        while True:
            try:
                schedule.run_pending()
                time.sleep(60)  # 每分钟检查一次定时任务
            except KeyboardInterrupt:
                self.logger.info("收到中断信号，停止健康检查服务")
                break
            except Exception as e:
                self.logger.error(f"健康检查服务异常: {e}")
                time.sleep(60)

def main():
    """主函数"""
    health_checker = HealthChecker()
    health_checker.run()

if __name__ == "__main__":
    main()