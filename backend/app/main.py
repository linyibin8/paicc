"""
PAI-CC 后端主程序
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from app.api import qa, captures, sessions, tts
from app.core.config import settings

app = FastAPI(
    title="PAI-CC API",
    description="面向学生学习陪伴的智能辅助系统 API",
    version="2.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 静态文件（上传的图片和音频）
os.makedirs(settings.upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")

# 注册路由
app.include_router(qa.router, prefix="/api/v1/qa", tags=["AI 问答"])
app.include_router(captures.router, prefix="/api/v1/captures", tags=["拍摄采集"])
app.include_router(sessions.router, prefix="/api/v1/sessions", tags=["学习会话"])
app.include_router(tts.router, prefix="/api/v1/tts", tags=["语音合成"])


@app.get("/")
async def root():
    return {
        "name": "PAI-CC",
        "version": "2.0.0",
        "status": "running"
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "version": "2.0.0",
        "ollama": settings.ollama_base_url,
        "tts": settings.tts_base_url
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8027)