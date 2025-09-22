# JavSP 网络部署快速入门

## 🎯 5分钟快速部署

### 前提条件
- Docker已安装
- 管理员/root权限
- 稳定的网络连接

### Windows快速部署

1. **打开管理员PowerShell**

2. **下载部署文件**
   ```powershell
   git clone https://github.com/Yuukiy/JavSP.git
   cd JavSP\network-deployment
   ```

3. **一键配置SMB服务器**
   ```powershell
   .\scripts\windows\quick-setup-smb.bat
   ```
   
4. **启动JavSP服务**
   ```powershell
   docker-compose up -d
   ```

5. **连接客户端**
   ```powershell
   .\scripts\windows\connect-javsp.bat
   ```

### Mac快速部署

1. **打开终端**

2. **下载部署文件**
   ```bash
   git clone https://github.com/Yuukiy/JavSP.git
   cd JavSP/network-deployment
   ```

3. **一键配置Samba服务器**
   ```bash
   sudo ./scripts/mac/setup-samba-server.sh
   ```

4. **启动JavSP服务**
   ```bash
   docker-compose up -d
   ```

5. **连接客户端**
   ```bash
   ./scripts/mac/connect-javsp.sh
   ```

## 📁 使用方法

1. **上传文件**: 将视频文件复制到输入目录
2. **等待处理**: 系统自动检测并处理文件
3. **获取结果**: 从输出目录获取整理后的文件

## 🔧 验证部署

### 检查服务状态
```bash
docker ps | grep javsp
```

### 测试网络共享
- Windows: 访问 `\\<服务器IP>\javsp-input`
- Mac: 连接 `smb://<服务器IP>/javsp-input`

### 查看处理日志
```bash
docker logs javsp-server
```

## ⚡ 常用命令

### 管理服务
```bash
# 启动服务
docker-compose up -d

# 停止服务  
docker-compose down

# 重启服务
docker-compose restart

# 查看日志
docker-compose logs -f
```

### 客户端连接
```bash
# Windows
.\scripts\windows\connect-javsp.bat [IP地址]

# Mac  
./scripts/mac/connect-javsp.sh [IP地址]
```

### 监控和维护
```bash
# 快速健康检查
./scripts/monitoring/troubleshoot.sh quick

# 性能优化
./scripts/monitoring/performance_optimizer.sh auto

# 设置定时任务
./scripts/monitoring/cron_manager.sh add daily
```

## 🚨 遇到问题？

### 第一步：自动诊断
```bash
./scripts/monitoring/troubleshoot.sh quick
```

### 第二步：查看详细日志
```bash
docker logs javsp-server | tail -50
```

### 第三步：重启服务
```bash
docker-compose restart
```

### 第四步：紧急修复
```bash
./scripts/monitoring/troubleshoot.sh emergency
```

## 🔗 获取帮助

- 详细文档: [README.md](README.md)
- 故障排除: 运行 `troubleshoot.sh full`
- 配置示例: `config/` 目录

---

**🎉 部署完成！开始享受自动化的媒体文件整理吧！**