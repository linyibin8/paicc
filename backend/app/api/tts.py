"""
PAI-CC TTS 语音合成 API
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import httpx
import os
import uuid

router = APIRouter()


class TTSRequest(BaseModel):
    """TTS 请求"""
    text: str
    voice: str = "af_heart"  # 音色选择
    speed: float = 1.0  # 语速 0.5-2.0
    language: str = "zh-CN"


class TTSResponse(BaseModel):
    """TTS 响应"""
    audio_url: str
    duration: float
    text_length: int


@router.post("/synthesize", response_model=TTSResponse)
async def synthesize_speech(request: TTSRequest):
    """
    文字转语音

    使用 Kokoro TTS 服务
    """
    from app.core.config import settings

    # 限制文本长度
    if len(request.text) > 1000:
        raise HTTPException(status_code=400, detail="Text too long (max 1000 chars)")

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{settings.tts_base_url}/v1/tts",
                json={
                    "text": request.text,
                    "model": "kokoro",
                    "voice": request.voice,
                    "speed": request.speed
                }
            )

            if response.status_code == 200:
                # 保存音频文件
                audio_id = str(uuid.uuid4())
                audio_dir = os.path.join(settings.upload_dir, "tts")
                os.makedirs(audio_dir, exist_ok=True)

                audio_path = os.path.join(audio_dir, f"{audio_id}.wav")
                with open(audio_path, "wb") as f:
                    f.write(response.content)

                # 估算时长（按中文约 5 字/秒）
                duration = len(request.text) / 5 / request.speed

                return TTSResponse(
                    audio_url=f"/api/v1/tts/audio/{audio_id}.wav",
                    duration=duration,
                    text_length=len(request.text)
                )
            else:
                raise HTTPException(status_code=500, detail="TTS service error")

    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="TTS service unavailable")


@router.get("/voices")
async def list_voices():
    """列出可用音色"""
    return {
        "voices": [
            {"id": "af_heart", "name": "女声-温柔", "language": "zh-CN"},
            {"id": "af_bella", "name": "女声-活泼", "language": "zh-CN"},
            {"id": "am_michael", "name": "男声-沉稳", "language": "zh-CN"},
            {"id": "am_patriot", "name": "男声-活力", "language": "zh-CN"},
        ]
    }


@router.get("/audio/{audio_id}")
async def get_audio(audio_id: str):
    """获取生成的音频"""
    from fastapi.responses import FileResponse
    from app.core.config import settings

    audio_path = os.path.join(settings.upload_dir, "tts", f"{audio_id}.wav")

    if not os.path.exists(audio_path):
        raise HTTPException(status_code=404, detail="Audio not found")

    return FileResponse(audio_path, media_type="audio/wav")