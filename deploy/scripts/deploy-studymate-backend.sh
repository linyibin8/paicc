#!/bin/bash
# StudyMate 后端部署脚本
# 使用方法: ./deploy-backend.sh

set -e

PROJECT_DIR="/home/ydz/projects/studymate-ios"
BACKEND_DIR="$PROJECT_DIR/backend"
BACKEND_PORT=8000
REMOTE_USER="ydz"
REMOTE_HOST="100.64.0.13"
VPS_HOST="ubuntu@100.64.0.8"

echo "=== StudyMate 后端部署脚本 ==="

# 1. 同步代码到后端服务器
echo "[1/6] 同步代码到后端服务器..."
rsync -avz --exclude 'venv' --exclude 'node_modules' --exclude '.git' --exclude '__pycache__' \
    $BACKEND_DIR/ $REMOTE_USER@$REMOTE_HOST:$BACKEND_DIR/

# 2. 创建 Python 虚拟环境
echo "[2/6] 创建 Python 虚拟环境..."
ssh $REMOTE_USER@$REMOTE_HOST "cd $BACKEND_DIR && \
    if [ ! -d venv ]; then python3 -m venv venv; fi && \
    source venv/bin/activate && \
    pip install -r requirements.txt -q"

# 3. 创建 systemd 服务文件
echo "[3/6] 配置 systemd 服务..."
ssh $REMOTE_USER@$REMOTE_HOST "sudo tee /etc/systemd/system/studymate-backend.service > /dev/null << 'SERVICE'
[Unit]
Description=StudyMate Backend API
After=network.target

[Service]
Type=simple
User=$REMOTE_USER
WorkingDirectory=$BACKEND_DIR
ExecStart=$BACKEND_DIR/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT --reload
Restart=always
RestartSec=5
Environment=PYTHONPATH=$BACKEND_DIR

[Install]
WantedBy=multi-user.target
SERVICE
sudo systemctl daemon-reload
sudo systemctl enable studymate-backend"

# 4. 重启后端服务
echo "[4/6] 重启后端服务..."
ssh $REMOTE_USER@$REMOTE_HOST "sudo systemctl restart studymate-backend"

# 5. 配置 Nginx (VPS)
echo "[5/6] 配置 Nginx..."
ssh $VPS_HOST "sudo tee /etc/nginx/sites-available/studymate-api.evowit.com > /dev/null << 'NGINX'
server {
    server_name api.studymate.ai studymate-api.evowit.com;
    client_max_body_size 50M;

    location / {
        proxy_pass http://$REMOTE_HOST:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ws {
        proxy_pass http://$REMOTE_HOST:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_read_timeout 86400;
    }

    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/letsencrypt/live/api.studymate.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.studymate.ai/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
server {
    if (\$host = api.studymate.ai) {
        return 301 https://\$host\$request_uri;
    }
    listen 80;
    listen [::]:80;
    server_name api.studymate.ai studymate-api.evowit.com;
    return 404;
}
NGINX
sudo ln -sf /etc/nginx/sites-available/studymate-api.evowit.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx"

# 6. 验证
echo "[6/6] 验证服务..."
sleep 5
ssh $REMOTE_USER@$REMOTE_HOST "curl -s http://localhost:$BACKEND_PORT/health || curl -s http://localhost:$BACKEND_PORT/"

echo ""
echo "=== 部署完成 ==="
echo "后端服务: http://$REMOTE_HOST:$BACKEND_PORT"
echo "API 文档: http://$REMOTE_HOST:$BACKEND_PORT/docs"
echo "公网访问: https://api.studymate.ai (需配置 DNS 和 SSL)"
echo ""
echo "请确保已创建 DNS 记录:"
echo "  api.studymate.ai -> 159.75.178.237"
echo ""
echo "获取 SSL 证书:"
echo "  ssh $VPS_HOST"
echo "  sudo certbot --nginx -d api.studymate.ai"