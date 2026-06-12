"""
PAI-CC 后端服务入口
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from app.core.config import settings
from app.api import captures, sessions, qa, tts, mistakes, review_queue, student_profile, dashboard

app = FastAPI(
    title="PAI-CC API",
    description="学生学习陪伴辅助系统 API",
    version="2.0.0"
)

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 静态文件
os.makedirs(settings.upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")

# 注册路由
app.include_router(captures.router, prefix="/api/v1/captures", tags=["采集"])
app.include_router(sessions.router, prefix="/api/v1/sessions", tags=["会话"])
app.include_router(qa.router, prefix="/api/v1/qa", tags=["问答"])
app.include_router(tts.router, prefix="/api/v1/tts", tags=["语音合成"])
app.include_router(mistakes.router, prefix="/api/v1/mistakes", tags=["错题管理"])
app.include_router(review_queue.router, prefix="/api/v1/review-queue", tags=["复习队列"])
app.include_router(student_profile.router, prefix="/api/v1/student-profile", tags=["学生画像"])
app.include_router(dashboard.router, prefix="/api/v1/dashboard", tags=["Dashboard统计"])


@app.get("/")
async def root():
    return {"message": "PAI-CC API", "version": "2.0.0"}


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