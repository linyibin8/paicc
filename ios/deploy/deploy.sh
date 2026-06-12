#!/bin/bash
# PAI-CC 部署脚本
# 使用方法: ./deploy.sh

set -e

PROJECT_DIR="/home/ydz/projects/pai-cc"
BACKEND_PORT=8029
REMOTE_USER="ydz"
REMOTE_HOST="100.64.0.13"
VPS_HOST="ubuntu@100.64.0.8"

echo "=== PAI-CC 部署脚本 ==="

# 1. 同步代码到后端服务器
echo "[1/5] 同步代码到后端服务器..."
rsync -avz --exclude 'venv' --exclude 'node_modules' --exclude '.git' --exclude '__pycache__' \
    $PROJECT_DIR/ $REMOTE_USER@$REMOTE_HOST:$PROJECT_DIR/

# 2. 安装依赖
echo "[2/5] 安装 Python 依赖..."
ssh $REMOTE_USER@$REMOTE_HOST "cd $PROJECT_DIR/backend && \
    source venv/bin/activate && \
    pip install fastapi uvicorn httpx python-multipart aiofiles pydantic-settings -q 2>/dev/null || \
    (python3 -m venv venv && source venv/bin/activate && pip install fastapi uvicorn httpx python-multipart aiofiles pydantic-settings -q)"

# 3. 重启后端服务
echo "[3/5] 重启后端服务..."
ssh $REMOTE_USER@$REMOTE_HOST "pkill -f 'uvicorn app.main:app.*port $BACKEND_PORT' 2>/dev/null || true
cd $PROJECT_DIR/backend && \
    source venv/bin/activate && \
    nohup bash -c 'PYTHONPATH=. uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT' > /tmp/pai-cc.log 2>&1 &"

# 4. 配置 Nginx (VPS)
echo "[4/5] 配置 Nginx..."
ssh $VPS_HOST "sudo tee /etc/nginx/sites-available/pai-cc.evowit.com > /dev/null << 'NGINX'
server {
    server_name api.pai-cc.evowit.com;
    client_max_body_size 50M;

    location / {
        proxy_pass http://100.64.0.13:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ws {
        proxy_pass http://100.64.0.13:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_read_timeout 86400;
    }

    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/letsencrypt/live/api.pai-cc.evowit.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.pai-cc.evowit.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
server {
    if (\$host = api.pai-cc.evowit.com) {
        return 301 https://\$host\$request_uri;
    }
    listen 80;
    listen [::]:80;
    server_name api.pai-cc.evowit.com;
    return 404;
}
NGINX
sudo ln -sf /etc/nginx/sites-available/pai-cc.evowit.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx"

# 5. 验证
echo "[5/5] 验证服务..."
sleep 3
ssh $REMOTE_USER@$REMOTE_HOST "curl -s http://localhost:$BACKEND_PORT/health | jq . || curl -s http://localhost:$BACKEND_PORT/health"

echo ""
echo "=== 部署完成 ==="
echo "后端服务: http://100.64.0.13:$BACKEND_PORT"
echo "API 文档: http://100.64.0.13:$BACKEND_PORT/docs"
echo "公网访问: https://api.pai-cc.evowit.com (需配置 DNS 和 SSL)"
echo ""
echo "请确保已创建 DNS 记录:"
echo "  api.pai-cc.evowit.com -> 159.75.178.237"
echo ""
echo "获取 SSL 证书:"
echo "  ssh $VPS_HOST"
echo "  sudo certbot --nginx -d api.pai-cc.evowit.com"