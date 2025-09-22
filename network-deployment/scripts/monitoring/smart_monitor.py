#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
JavSP 智能处理监控器
基于Python的高级文件监控和处理系统
"""

import os
import sys
import time
import json
import logging
import signal
import subprocess
import threading
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Set, Optional
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor
import hashlib

# 尝试导入watchdog，如果不可用则使用轮询
try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
    WATCHDOG_AVAILABLE = True
except ImportError:
    WATCHDOG_AVAILABLE = False

@dataclass
class ProcessingJob:
    """处理任务数据类"""
    file_path: str
    size: int
    detected_time: datetime
    last_modified: datetime
    hash_md5: Optional[str] = None
    status: str = "pending"  # pending, processing, completed, failed
    
    def to_dict(self) -> Dict:
        data = asdict(self)
        data['detected_time'] = self.detected_time.isoformat()
        data['last_modified'] = self.last_modified.isoformat()
        return data

class JavSPMonitor:
    """JavSP智能监控器"""
    
    def __init__(self, config_path: str = "/app/config/monitor.json"):
        self.config_path = config_path
        self.load_config()
        self.setup_logging()
        
        # 状态管理
        self.processing_queue: List[ProcessingJob] = []
        self.completed_files: Set[str] = set()
        self.is_running = True
        self.current_job: Optional[ProcessingJob] = None
        
        # 线程控制
        self.executor = ThreadPoolExecutor(max_workers=2)
        self.lock = threading.Lock()
        
        # 统计信息
        self.stats = {
            'files_processed': 0,
            'files_failed': 0,
            'total_processing_time': 0,
            'last_activity': None
        }
        
        self.logger.info("JavSP监控器初始化完成")
    
    def load_config(self):
        """加载配置"""
        default_config = {
            "input_directory": "/app/input",
            "output_directory": "/app/output",
            "log_file": "/app/logs/monitor.log",
            "state_file": "/app/logs/monitor_state.json",
            "video_extensions": [
                ".mp4", ".mkv", ".avi", ".mov", ".wmv", 
                ".flv", ".m4v", ".m2ts", ".ts", ".vob",
                ".iso", ".rmvb", ".rm", ".3gp", ".f4v",
                ".webm", ".strm", ".mpg", ".mpeg"
            ],
            "min_file_size_mb": 200,
            "stability_check_interval": 10,
            "stability_check_count": 3,
            "max_processing_time": 3600,
            "check_interval": 60,
            "enable_hash_check": True,
            "cleanup_days": 7
        }
        
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    user_config = json.load(f)
                default_config.update(user_config)
            except Exception as e:
                print(f"配置文件加载失败，使用默认配置: {e}")
        
        self.config = default_config
        
        # 创建必要的目录
        os.makedirs(os.path.dirname(self.config['log_file']), exist_ok=True)
        os.makedirs(self.config['input_directory'], exist_ok=True)
        os.makedirs(self.config['output_directory'], exist_ok=True)
    
    def setup_logging(self):
        """设置日志"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s [%(levelname)s] %(message)s',
            handlers=[
                logging.FileHandler(self.config['log_file'], encoding='utf-8'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def calculate_file_hash(self, file_path: str) -> Optional[str]:
        """计算文件MD5哈希"""
        if not self.config['enable_hash_check']:
            return None
        
        try:
            hash_md5 = hashlib.md5()
            with open(file_path, "rb") as f:
                # 只读取文件的前1MB和最后1MB来快速计算哈希
                chunk_size = 8192
                total_read = 0
                max_read = 1024 * 1024  # 1MB
                
                while total_read < max_read:
                    chunk = f.read(min(chunk_size, max_read - total_read))
                    if not chunk:
                        break
                    hash_md5.update(chunk)
                    total_read += len(chunk)
                
                # 读取文件末尾
                f.seek(-min(max_read, os.path.getsize(file_path)), 2)
                while True:
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    hash_md5.update(chunk)
            
            return hash_md5.hexdigest()
        except Exception as e:
            self.logger.warning(f"计算文件哈希失败 {file_path}: {e}")
            return None
    
    def is_video_file(self, file_path: str) -> bool:
        """检查是否为视频文件"""
        ext = Path(file_path).suffix.lower()
        return ext in self.config['video_extensions']
    
    def is_file_stable(self, file_path: str) -> bool:
        """检查文件是否稳定（传输完成）"""
        try:
            stat1 = os.stat(file_path)
            time.sleep(self.config['stability_check_interval'])
            stat2 = os.stat(file_path)
            
            # 检查大小和修改时间是否相同
            return (stat1.st_size == stat2.st_size and 
                    stat1.st_mtime == stat2.st_mtime and
                    stat1.st_size >= self.config['min_file_size_mb'] * 1024 * 1024)
        except (OSError, FileNotFoundError):
            return False
    
    def scan_for_new_files(self) -> List[str]:
        """扫描新文件"""
        new_files = []
        input_dir = Path(self.config['input_directory'])
        
        if not input_dir.exists():
            return new_files
        
        for file_path in input_dir.rglob('*'):
            if (file_path.is_file() and 
                self.is_video_file(str(file_path)) and
                str(file_path) not in self.completed_files):
                
                # 检查文件是否在处理队列中
                in_queue = any(job.file_path == str(file_path) for job in self.processing_queue)
                if not in_queue:
                    new_files.append(str(file_path))
        
        return new_files
    
    def add_to_queue(self, file_path: str):
        """添加文件到处理队列"""
        try:
            stat = os.stat(file_path)
            job = ProcessingJob(
                file_path=file_path,
                size=stat.st_size,
                detected_time=datetime.now(),
                last_modified=datetime.fromtimestamp(stat.st_mtime)
            )
            
            with self.lock:
                self.processing_queue.append(job)
            
            self.logger.info(f"添加到处理队列: {os.path.basename(file_path)} ({stat.st_size / 1024 / 1024:.1f} MB)")
        except Exception as e:
            self.logger.error(f"添加文件到队列失败 {file_path}: {e}")
    
    def process_file(self, job: ProcessingJob) -> bool:
        """处理单个文件"""
        file_path = job.file_path
        self.logger.info(f"开始处理: {os.path.basename(file_path)}")
        
        try:
            # 更新状态
            job.status = "processing"
            self.current_job = job
            
            # 等待文件稳定
            stability_checks = 0
            while stability_checks < self.config['stability_check_count']:
                if self.is_file_stable(file_path):
                    stability_checks += 1
                    self.logger.info(f"文件稳定性检查 {stability_checks}/{self.config['stability_check_count']}")
                else:
                    stability_checks = 0
                    self.logger.info(f"文件仍在传输: {os.path.basename(file_path)}")
                
                if not self.is_running:
                    return False
            
            # 计算文件哈希
            if self.config['enable_hash_check']:
                job.hash_md5 = self.calculate_file_hash(file_path)
            
            # 执行JavSP处理
            start_time = time.time()
            cmd = ["/app/.venv/bin/javsp", "-i", self.config['input_directory']]
            
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                cwd="/app"
            )
            
            # 监控处理进程
            output_lines = []
            while True:
                output = process.stdout.readline()
                if output == '' and process.poll() is not None:
                    break
                if output:
                    output_lines.append(output.strip())
                    self.logger.info(f"JavSP: {output.strip()}")
            
            process_time = time.time() - start_time
            
            if process.returncode == 0:
                job.status = "completed"
                self.stats['files_processed'] += 1
                self.stats['total_processing_time'] += process_time
                self.completed_files.add(file_path)
                
                self.logger.info(f"处理完成: {os.path.basename(file_path)} (耗时: {process_time:.1f}秒)")
                return True
            else:
                job.status = "failed"
                self.stats['files_failed'] += 1
                self.logger.error(f"处理失败: {os.path.basename(file_path)} (返回码: {process.returncode})")
                return False
                
        except Exception as e:
            job.status = "failed"
            self.stats['files_failed'] += 1
            self.logger.error(f"处理异常: {os.path.basename(file_path)} - {e}")
            return False
        finally:
            self.current_job = None
    
    def process_queue(self):
        """处理队列中的文件"""
        while self.is_running:
            with self.lock:
                pending_jobs = [job for job in self.processing_queue if job.status == "pending"]
            
            if pending_jobs:
                job = pending_jobs[0]
                self.process_file(job)
                
                # 清理已完成的任务
                with self.lock:
                    self.processing_queue = [j for j in self.processing_queue if j.status == "pending"]
            else:
                time.sleep(5)
    
    def save_state(self):
        """保存状态"""
        try:
            state = {
                'stats': self.stats,
                'completed_files': list(self.completed_files),
                'queue_length': len(self.processing_queue),
                'current_job': self.current_job.to_dict() if self.current_job else None,
                'timestamp': datetime.now().isoformat()
            }
            
            with open(self.config['state_file'], 'w', encoding='utf-8') as f:
                json.dump(state, f, indent=2, ensure_ascii=False)
        except Exception as e:
            self.logger.error(f"保存状态失败: {e}")
    
    def load_state(self):
        """加载状态"""
        try:
            if os.path.exists(self.config['state_file']):
                with open(self.config['state_file'], 'r', encoding='utf-8') as f:
                    state = json.load(f)
                
                self.stats.update(state.get('stats', {}))
                self.completed_files.update(state.get('completed_files', []))
                self.logger.info("状态加载完成")
        except Exception as e:
            self.logger.error(f"加载状态失败: {e}")
    
    def cleanup_old_logs(self):
        """清理旧日志"""
        try:
            log_dir = Path(self.config['log_file']).parent
            cutoff_date = datetime.now() - timedelta(days=self.config['cleanup_days'])
            
            for log_file in log_dir.glob('*.log*'):
                if log_file.stat().st_mtime < cutoff_date.timestamp():
                    log_file.unlink()
                    self.logger.info(f"删除旧日志: {log_file}")
        except Exception as e:
            self.logger.error(f"清理日志失败: {e}")
    
    def signal_handler(self, signum, frame):
        """信号处理"""
        self.logger.info(f"收到信号 {signum}，准备退出...")
        self.is_running = False
    
    def run(self):
        """主运行循环"""
        self.logger.info("启动JavSP智能监控器")
        
        # 注册信号处理
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
        # 加载状态
        self.load_state()
        
        # 启动处理线程
        processing_thread = threading.Thread(target=self.process_queue, daemon=True)
        processing_thread.start()
        
        # 主监控循环
        last_cleanup = datetime.now()
        
        while self.is_running:
            try:
                # 扫描新文件
                new_files = self.scan_for_new_files()
                for file_path in new_files:
                    self.add_to_queue(file_path)
                
                # 更新活动时间
                if new_files or self.processing_queue:
                    self.stats['last_activity'] = datetime.now().isoformat()
                
                # 定期保存状态
                self.save_state()
                
                # 定期清理日志
                if datetime.now() - last_cleanup > timedelta(hours=24):
                    self.cleanup_old_logs()
                    last_cleanup = datetime.now()
                
                # 等待下次检查
                time.sleep(self.config['check_interval'])
                
            except Exception as e:
                self.logger.error(f"监控循环异常: {e}")
                time.sleep(30)
        
        self.logger.info("JavSP监控器已停止")

def main():
    """主函数"""
    monitor = JavSPMonitor()
    monitor.run()

if __name__ == "__main__":
    main()