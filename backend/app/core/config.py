"""
PAI-CC 后端服务配置文件
"""
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # 数据库
    database_url: str = "postgresql://ydz:ydz123@localhost:5432/paicc"

    # Redis
    redis_url: str = "redis://localhost:6379"

    # Ollama AI
    ollama_base_url: str = "http://100.64.0.5:39000/v1"
    ollama_api_key: str = "ollama"
    ollama_model: str = "evowit-agent27b"

    # TTS
    tts_base_url: str = "http://100.64.0.13:8880"

    # JWT
    secret_key: str = "pai-cc-secret-key-change-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days

    # 上传
    upload_dir: str = "/home/ydz/projects/pai-cc/uploads"
    max_file_size: int = 10 * 1024 * 1024  # 10MB

    # CORS
    cors_origins: list = ["*"]

    class Config:
        env_file = ".env"
        extra = "allow"


settings = Settings()