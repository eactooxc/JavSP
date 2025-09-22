# JavSP 本地网络部署指南

## 📖 项目简介

JavSP本地网络部署方案将JavSP作为容器化服务运行在本地网络中，支持Windows和Mac客户端通过网络共享访问。

### ✨ 主要特性

- **🐳 容器化部署**: 基于Docker的可靠部署方案
- **🌐 网络共享**: 支持SMB/Samba网络文件共享
- **🔄 自动处理**: 智能文件监控和批处理
- **📊 实时监控**: 完整的系统监控和告警
- **🖥️ 跨平台**: Windows和Mac客户端支持
- **⚡ 高性能**: 资源优化和性能调优

## 🚀 快速开始

### 一键部署

1. **下载部署包**
   ```bash
   git clone https://github.com/Yuukiy/JavSP.git
   cd JavSP/network-deployment
   ```

2. **执行快速安装**
   
   **Windows (以管理员身份运行)**
   ```powershell
   .\scripts\windows\quick-setup-smb.bat
   ```
   
   **Mac/Linux (以root身份运行)**
   ```bash
   sudo ./scripts/linux/setup-samba-server.sh setup
   ```

3. **启动服务**
   ```bash
   docker-compose up -d
   ```

4. **连接客户端**
   ```powershell
   # Windows
   .\scripts\windows\connect-javsp.bat

   # Mac
   ./scripts/mac/connect-javsp.sh
   ```

### ⚡ 验证安装

访问共享目录，将测试视频文件放入输入目录，检查输出目录是否生成处理结果。

## 📋 系统要求

### 服务器要求

#### 推荐配置
- **CPU**: 4核心或更多
- **内存**: 8GB RAM或更多  
- **存储**: 200GB可用空间 (SSD推荐)
- **网络**: 1Gbps局域网

### 软件要求

#### 服务器端
- **操作系统**: Windows 10/11, macOS 10.15+, Linux (Ubuntu 20.04+)
- **Docker**: 20.10+
- **Docker Compose**: 1.29+

## 📁 目录结构

```
network-deployment/
├── docker-compose.yml          # Docker编排配置
├── config/
│   ├── config.yml              # JavSP主配置文件
│   └── monitor.json            # 监控配置文件
├── scripts/
│   ├── windows/                # Windows脚本
│   │   ├── connect-javsp.bat   # 客户端连接脚本
│   │   ├── quick-setup-smb.bat # 快速SMB配置
│   │   └── setup-smb-server.ps1# SMB服务器配置
│   ├── mac/                    # Mac脚本
│   │   ├── connect-javsp.sh    # 客户端连接脚本
│   │   └── setup-samba-server.sh# Samba服务器配置
│   ├── linux/                  # Linux脚本
│   │   └── setup-samba-server.sh# Samba服务器配置
│   └── monitoring/             # 监控脚本
│       ├── batch_process.sh    # 批处理脚本
│       ├── cron_manager.sh     # 定时任务管理
│       ├── troubleshoot.sh     # 故障排除脚本
│       └── health_check.py     # 健康检查脚本
├── input/                      # 输入目录
├── output/                     # 输出目录
├── data/                       # 数据目录
└── logs/                       # 日志目录
```

## 🔧 详细部署步骤

### 第一步：环境准备

#### 安装Docker

**Windows**
1. 下载并安装Docker Desktop
2. 启动Docker服务
3. 验证安装：`docker --version`

**Mac**
```bash
brew install --cask docker
```

**Linux (Ubuntu)**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

### 第二步：配置网络共享

#### Windows SMB配置

使用自动配置脚本：
```powershell
# 以管理员身份运行
.\scripts\windows\setup-smb-server.ps1 -Action setup -SharePath "C:\javsp-server"
```

#### Mac/Linux Samba配置

使用自动配置脚本：
```bash
# 以root身份运行
sudo ./scripts/linux/setup-samba-server.sh setup /opt/javsp-server
```

### 第三步：启动JavSP服务

```bash
# 启动所有服务
docker-compose up -d

# 检查容器状态
docker-compose ps

# 查看日志
docker-compose logs -f javsp
```

## 💻 客户端使用

### Windows客户端

```powershell
# 连接到服务器
.\scripts\windows\connect-javsp.bat <服务器IP>

# 断开连接
.\scripts\windows\disconnect-javsp.bat
```

### Mac客户端

```bash
# 连接到服务器
./scripts/mac/connect-javsp.sh <服务器IP>

# 断开连接
./scripts/mac/disconnect-javsp.sh
```

## 📊 监控与维护

### 健康检查

```bash
# 快速诊断
./scripts/monitoring/troubleshoot.sh quick

# 完整诊断
./scripts/monitoring/troubleshoot.sh full
```

### 性能优化

```bash
# 自动优化
./scripts/monitoring/performance_optimizer.sh auto

# 清理系统
./scripts/monitoring/performance_optimizer.sh cleanup
```

### 定时任务

```bash
# 设置每日自动处理
./scripts/monitoring/cron_manager.sh add daily

# 查看定时任务
./scripts/monitoring/cron_manager.sh list
```

## 🔍 故障排除

### 常见问题

1. **容器无法启动**
   - 检查Docker服务状态
   - 验证配置文件语法
   - 查看容器日志

2. **网络共享无法访问**
   - 检查SMB/Samba服务状态
   - 验证防火墙设置
   - 确认网络连通性

3. **处理速度慢**
   - 检查网络连接质量
   - 调整并发配置
   - 优化系统资源

### 紧急修复

```bash
# 执行紧急修复
./scripts/monitoring/troubleshoot.sh emergency
```

## 📚 更多文档

- [详细部署指南](docs/detailed-deployment.md)
- [监控与维护](docs/monitoring-maintenance.md)
- [故障排除指南](docs/troubleshooting.md)
- [性能优化指南](docs/performance-optimization.md)
- [常见问题解答](docs/faq.md)

## 🆘 技术支持

如遇问题请：

1. 运行诊断脚本收集信息
2. 查看详细错误日志
3. 参考故障排除文档
4. 联系技术支持

**收集诊断信息**:
```bash
./scripts/monitoring/troubleshoot.sh info
```

---

*JavSP 本地网络部署方案 - 让媒体文件整理更简单*