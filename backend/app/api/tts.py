"""
PAI-CC TTS 语音合成 API
"""
from fastapi import APIRouter, Form, HTTPException, Header
from fastapi.responses import FileResponse, StreamingResponse, Response
from pydantic import BaseModel, Field
from typing import Optional
import os
from datetime import datetime

from app.core.config import settings
from app.services.tts_service import tts_service, TTSServiceError

router = APIRouter()

# ============ 数据模型 ============

class TTSRequest(BaseModel):
    """标准 TTS 请求"""
    text: str = Field(..., min_length=1, max_length=1000, description="要合成的文本")
    voice: str = Field(default="af_heart", description="声音选择")


class TTSResponse(BaseModel):
    """标准 TTS 响应"""
    audio_url: str
    duration: Optional[float] = None


class VoiceInfo(BaseModel):
    """声音信息"""
    id: str
    name: str
    gender: str
    style: Optional[str] = None


class VoicesListResponse(BaseModel):
    """声音列表响应"""
    voices: list[VoiceInfo]


# ============ OpenAI 兼容 API (/v1/audio/speech) ============

@router.post(
    "/v1/audio/speech",
    summary="OpenAI 兼容 TTS 端点",
    response_class=StreamingResponse,
    responses={
        200: {"content": {"audio/wav": {}}},
        400: {"description": "无效请求"},
        500: {"description": "服务器错误"},
    }
)
async def create_speech(
    # OpenAI 兼容参数
    model: str = Form(default="kokoro", description="模型名称（仅支持 kokoro）"),
    input: str = Form(..., description="要合成的文本"),
    voice: str = Form(default="af_heart", description="声音选择"),
    response_format: str = Form(default="wav", description="输出格式（仅支持 wav）"),
    speed: Optional[float] = Form(default=None, description="语速（暂不支持）"),
):
    """
    OpenAI 兼容的语音合成端点

    遵循 OpenAI Audio API 规范，支持以下参数：
    - model: 模型名称（固定为 kokoro）
    - input: 要合成的文本
    - voice: 声音选择
    - response_format: 音频格式（支持 wav, mp3, opus）

    返回:
        音频数据流（Content-Type: audio/wav）
    """
    # 验证输入
    if not input or not input.strip():
        raise HTTPException(status_code=400, detail="Input text cannot be empty")

    if len(input) > 1000:
        raise HTTPException(status_code=400, detail="Input text too long (max 1000 chars)")

    # 验证响应格式
    supported_formats = ["wav", "mp3", "opus"]
    if response_format not in supported_formats:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {response_format}. Supported: {supported_formats}"
        )

    # 验证模型
    if model != "kokoro":
        raise HTTPException(status_code=400, detail=f"Unsupported model: {model}. Only 'kokoro' is supported")

    try:
        # 流式生成音频
        audio_generator = tts_service.synthesize_stream(text=input, voice=voice)

        # 生成文件名
        filename = f"speech_{datetime.now().timestamp()}.{response_format}"

        return StreamingResponse(
            audio_generator,
            media_type=f"audio/{response_format}",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "X-Audio-Voice": voice,
                "X-Generated-At": datetime.now().isoformat(),
            }
        )
    except TTSServiceError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Speech synthesis failed: {str(e)}")


# ============ 标准 API ============

@router.post(
    "/synthesize",
    response_model=TTSResponse,
    summary="合成语音（保存文件）"
)
async def synthesize_speech(
    text: str = Form(..., min_length=1, max_length=1000, description="要合成的文本"),
    voice: str = Form(default="af_heart", description="声音选择")
):
    """
    合成语音并保存到文件

    Args:
        text: 要合成的文本（最大 1000 字符）
        voice: 声音选择（默认 af_heart）

    Returns:
        音频文件 URL
    """
    try:
        filename = f"tts_{datetime.now().timestamp()}.wav"
        audio_path = await tts_service.synthesize(
            text=text,
            voice=voice,
            output_filename=filename
        )

        return TTSResponse(
            audio_url=f"/uploads/audio/{filename}",
            duration=None
        )
    except TTSServiceError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"TTS synthesis failed: {str(e)}")


@router.post(
    "/synthesize-stream",
    response_class=StreamingResponse,
    summary="流式合成语音",
    responses={
        200: {"content": {"audio/wav": {}}},
        400: {"description": "无效请求"},
        500: {"description": "服务器错误"},
    }
)
async def synthesize_speech_stream(
    text: str = Form(..., min_length=1, max_length=1000, description="要合成的文本"),
    voice: str = Form(default="af_heart", description="声音选择")
):
    """
    流式合成语音（直接返回音频数据）

    适用于实时播放场景，返回音频数据流。
    """
    try:
        audio_generator = tts_service.synthesize_stream(text=text, voice=voice)
        filename = f"tts_{datetime.now().timestamp()}.wav"

        return StreamingResponse(
            audio_generator,
            media_type="audio/wav",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "X-Audio-Voice": voice,
                "X-Generated-At": datetime.now().isoformat(),
            }
        )
    except TTSServiceError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"TTS streaming failed: {str(e)}")


# ============ 声音管理 API ============

@router.get(
    "/voices",
    response_model=VoicesListResponse,
    summary="获取可用声音列表"
)
async def list_voices():
    """
    获取所有可用的声音

    Returns:
        声音列表，包含每个声音的 ID、名称、性别和风格
    """
    voices = tts_service.get_available_voices()
    return VoicesListResponse(
        voices=[VoiceInfo(**v) for v in voices]
    )


@router.get(
    "/voices/{voice_id}",
    response_model=VoiceInfo,
    summary="获取声音详情"
)
async def get_voice(voice_id: str):
    """
    获取指定声音的详细信息
    """
    voices = tts_service.get_available_voices()
    for voice in voices:
        if voice["id"] == voice_id:
            return VoiceInfo(**voice)
    raise HTTPException(status_code=404, detail=f"Voice '{voice_id}' not found")


# ============ 音频文件 API ============

@router.get(
    "/audio/{filename}",
    summary="获取音频文件",
    responses={404: {"description": "音频文件不存在"}}
)
async def get_audio(filename: str):
    """
    获取已生成的音频文件
    """
    # 安全检查：防止路径遍历
    if ".." in filename or "/" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")

    audio_path = os.path.join(settings.upload_dir, "audio", filename)

    if not os.path.exists(audio_path):
        raise HTTPException(status_code=404, detail="Audio file not found")

    return FileResponse(audio_path, media_type="audio/wav")


# ============ 健康检查 ============

@router.get("/health", summary="TTS 服务健康检查")
async def health_check():
    """
    检查 TTS 服务健康状态
    """
    health = await tts_service.health_check()
    return health