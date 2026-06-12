"""
PAI-CC TTS 语音合成 API
"""
from fastapi import APIRouter, APIRouter, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
import os
import uuid
from datetime import datetime

from app.models.database import get_db
from app.core.config import settings
from app.services.tts_service import tts_service

router = APIRouter()


# ============ 数据模型 ============

class TTSRequest(BaseModel):
    text: str
    voice: str = "af_heart"  # af_heart, af_bella, mf_man


class TTSResponse(BaseModel):
    audio_url: str
    duration: Optional[float] = None


# ============ API ============

@router.post("/synthesize", response_model=TTSResponse)
async def synthesize_speech(
    text: str = Form(...),
    voice: str = Form("af_heart")
):
    """
    合成语音

    Args:
        text: 要合成的文本
        voice: 声音选择
            - af_heart: 温暖女声
            - af_bella: 甜美女声
            - mf_man: 沉稳男声
    """
    if len(text) > 1000:
        raise HTTPException(status_code=400, detail="Text too long (max 1000 chars)")

    try:
        filename = f"tts_{datetime.now().timestamp()}.wav"
        audio_path = await tts_service.synthesize(text, voice=voice, output_filename=filename)

        return TTSResponse(
            audio_url=f"/uploads/audio/{filename}",
            duration=None  # TODO: 计算实际时长
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"TTS failed: {str(e)}")


@router.post("/synthesize-stream")
async def synthesize_speech_stream(
    text: str = Form(...),
    voice: str = Form("af_heart")
):
    """
    流式合成语音（直接返回音频数据）
    """
    if len(text) > 1000:
        raise HTTPException(status_code=400, detail="Text too long (max 1000 chars)")

    try:
        audio_data = await tts_service.synthesize_stream(text, voice=voice)

        return StreamingResponse(
            iter([audio_data]),
            media_type="audio/wav",
            headers={
                "Content-Disposition": f"attachment; filename=tts_{datetime.now().timestamp()}.wav"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"TTS failed: {str(e)}")


@router.get("/voices")
async def list_voices():
    """列出可用的声音"""
    return {
        "voices": [
            {"id": "af_heart", "name": "温暖女声", "gender": "female"},
            {"id": "af_bella", "name": "甜美女声", "gender": "female"},
            {"id": "mf_man", "name": "沉稳男声", "gender": "male"}
        ]
    }


@router.get("/audio/{filename}")
async def get_audio(filename: str):
    """获取生成的音频文件"""
    audio_path = os.path.join(settings.upload_dir, "audio", filename)

    if not os.path.exists(audio_path):
        raise HTTPException(status_code=404, detail="Audio not found")

    return FileResponse(audio_path, media_type="audio/wav")