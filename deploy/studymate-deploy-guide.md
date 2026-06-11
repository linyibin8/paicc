# StudyMate API 部署指南

## 域名配置

### DNS 记录
```
类型: A
名称: api
值: 159.75.178.237 (腾讯云 VPS)

类型: A  
名称: studymate-api
值: 159.75.178.237
```

### 使用腾讯云 CLI 创建 DNS 记录
```bash
# 安装腾讯云 CLI
curl -sSL https://smartid-cli-release-1258344769.cos.ap-guangzhou.myqcloud.com/install.sh | sh

# 配置凭证
tencentcloudcli configure

# 创建 DNS 记录
tencentcloudcli domain dns-add \
  --domain studymate.ai \
  --record api \
  --type A \
  --value 159.75.178.237
```

## 后端部署

### 部署命令
```bash
cd /home/ydz/projects/pai-cc/deploy/scripts
chmod +x deploy-studymate-backend.sh
./deploy-studymate-backend.sh
```

### 手动部署
```bash
# 1. 同步代码
rsync -avz /home/ydz/projects/studymate-ios/backend/ ydz@100.64.0.13:/home/ydz/projects/studymate-ios/backend/

# 2. 安装依赖
ssh ydz@100.64.0.13 "cd /home/ydz/projects/studymate-ios/backend && \
    python3 -m venv venv && \
    source venv/bin/activate && \
    pip install -r requirements.txt"

# 3. 启动服务
ssh ydz@100.64.0.13 "cd /home/ydz/projects/studymate-ios/backend && \
    source venv/bin/activate && \
    nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/studymate.log 2>&1 &"
```

## SSL 证书配置

### 获取 Let's Encrypt 证书
```bash
ssh ubuntu@159.75.178.237
sudo certbot --nginx -d api.studymate.ai
```

### Nginx 配置
```nginx
server {
    listen 443 ssl;
    server_name api.studymate.ai;

    ssl_certificate /etc/letsencrypt/live/api.studymate.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.studymate.ai/privkey.pem;
    
    location / {
        proxy_pass http://100.64.0.13:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## 服务管理

### systemd 服务
```bash
# 查看状态
sudo systemctl status studymate-backend

# 重启服务
sudo systemctl restart studymate-backend

# 查看日志
sudo journalctl -u studymate-backend -f
```

## 健康检查
```bash
curl http://localhost:8000/health
curl https://api.studymate.ai/health
```

## API 端点
```
Base URL: https://api.studymate.ai

POST /api/v1/sessions/         创建会话
POST /api/v1/sessions/{id}/end 结束会话
POST /api/v1/captures/         上传采集
POST /api/v1/qa/ask            AI 问答
POST /api/v1/tts/synthesize    语音合成
GET  /health                   健康检查
```