#!/bin/bash
# PAI-CC 部署脚本

set -e

# 配置
PROJECT_DIR="/home/ydz/projects/pai-cc"
BACKEND_PORT=8029
SERVICE_NAME="pai-cc"

echo "=== PAI-CC 部署脚本 ==="

# 1. 同步代码
echo "[1/4] 同步代码..."
rsync -avz --exclude 'venv' --exclude 'node_modules' --exclude '.git' \
    /home/ydz/projects/pai-cc/ ydz@100.64.0.13:$PROJECT_DIR/

# 2. 安装依赖
echo "[2/4] 安装 Python 依赖..."
ssh ydz@100.64.0.13 "cd $PROJECT_DIR/backend && \
    source venv/bin/activate && \
    pip install fastapi uvicorn httpx python-multipart aiofiles pydantic-settings -q"

# 3. 重启服务
echo "[3/4] 重启后端服务..."
ssh ydz@100.64.0.13 "pkill -f 'uvicorn app.main:app.*port $BACKEND_PORT' || true
cd $PROJECT_DIR/backend && \
    source venv/bin/activate && \
    nohup bash -c 'PYTHONPATH=. uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT' > /tmp/pai-cc.log 2>&1 &"

# 4. 验证
echo "[4/4] 验证服务..."
sleep 3
ssh ydz@100.64.0.13 "curl -s http://localhost:$BACKEND_PORT/health | jq . || curl -s http://localhost:$BACKEND_PORT/health"

echo "=== 部署完成 ==="
echo "后端服务: http://100.64.0.13:$BACKEND_PORT"
echo "API 文档: http://100.64.0.13:$BACKEND_PORT/docs"