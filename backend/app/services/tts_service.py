"""
PAI-CC TTS 语音合成服务
"""
import httpx
import base64
import os
import io
import asyncio
from datetime import datetime
from typing import AsyncGenerator, Optional
from app.core.config import settings


class TTSServiceError(Exception):
    """TTS 服务异常"""
    pass


class TTSService:
    """TTS 语音合成服务"""

    # 可用声音配置
    VOICES = {
        # 女声
        "af_alloy": {"name": "活泼女声", "gender": "female"},
        "af_bella": {"name": "甜美女声", "gender": "female"},
        "af_heart": {"name": "温暖女声", "gender": "female"},
        "af_sarah": {"name": "知性女声", "gender": "female"},
        "af_nicole": {"name": "清新女声", "gender": "female"},
        "af_sky": {"name": "柔和女声", "gender": "female"},
        # 男声
        "mf_boston": {"name": "活力男声", "gender": "male"},
        "mf_man": {"name": "沉稳男声", "gender": "male"},
        "mf_james": {"name": "磁性男声", "gender": "male"},
        "mf_charles": {"name": "阳光男声", "gender": "male"},
    }

    def __init__(self):
        self.base_url = settings.tts_base_url
        self.timeout = 60.0
        self.max_text_length = 1000

    def _validate_voice(self, voice: str) -> bool:
        """验证声音是否可用"""
        return voice in self.VOICES

    def _validate_text(self, text: str) -> str:
        """验证并清理文本"""
        if not text or not text.strip():
            raise TTSServiceError("Text cannot be empty")
        # 限制长度
        return text[:self.max_text_length].strip()

    async def synthesize(
        self,
        text: str,
        voice: str = "af_heart",
        output_filename: str = None
    ) -> str:
        """
        合成语音（保存到文件）

        Args:
            text: 要合成的文本
            voice: 声音选择
            output_filename: 输出文件名

        Returns:
            音频文件路径

        Raises:
            TTSServiceError: 服务异常
        """
        # 验证输入
        text = self._validate_text(text)
        if not self._validate_voice(voice):
            raise TTSServiceError(f"Invalid voice: {voice}. Available: {list(self.VOICES.keys())}")

        if not output_filename:
            output_filename = f"tts_{datetime.now().timestamp()}.wav"

        output_path = os.path.join(settings.upload_dir, "audio", output_filename)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/v1/tts",
                    json={
                        "text": text,
                        "model": "kokoro",
                        "voice": voice
                    }
                )

                if response.status_code == 200:
                    with open(output_path, "wb") as f:
                        f.write(response.content)
                    return output_path
                elif response.status_code == 400:
                    raise TTSServiceError("Invalid request parameters")
                elif response.status_code == 422:
                    raise TTSServiceError("Text contains invalid characters")
                else:
                    raise TTSServiceError(f"TTS API error: HTTP {response.status_code}")

            except httpx.TimeoutException:
                raise TTSServiceError("TTS request timeout")
            except httpx.ConnectError:
                raise TTSServiceError(f"Cannot connect to TTS service at {self.base_url}")
            except TTSServiceError:
                raise
            except Exception as e:
                raise TTSServiceError(f"TTS synthesis failed: {str(e)}")

    async def synthesize_bytes(
        self,
        text: str,
        voice: str = "af_heart"
    ) -> bytes:
        """
        合成语音（返回字节数据）

        Args:
            text: 要合成的文本
            voice: 声音选择

        Returns:
            音频数据（bytes）

        Raises:
            TTSServiceError: 服务异常
        """
        # 验证输入
        text = self._validate_text(text)
        if not self._validate_voice(voice):
            raise TTSServiceError(f"Invalid voice: {voice}. Available: {list(self.VOICES.keys())}")

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/v1/tts",
                    json={
                        "text": text,
                        "model": "kokoro",
                        "voice": voice
                    }
                )

                if response.status_code == 200:
                    return response.content
                elif response.status_code == 400:
                    raise TTSServiceError("Invalid request parameters")
                elif response.status_code == 422:
                    raise TTSServiceError("Text contains invalid characters")
                else:
                    raise TTSServiceError(f"TTS API error: HTTP {response.status_code}")

            except httpx.TimeoutException:
                raise TTSServiceError("TTS request timeout")
            except httpx.ConnectError:
                raise TTSServiceError(f"Cannot connect to TTS service at {self.base_url}")
            except TTSServiceError:
                raise
            except Exception as e:
                raise TTSServiceError(f"TTS synthesis failed: {str(e)}")

    async def synthesize_stream(
        self,
        text: str,
        voice: str = "af_heart"
    ) -> AsyncGenerator[bytes, None]:
        """
        流式合成语音（用于 SSE/流式响应）

        Args:
            text: 要合成的文本
            voice: 声音选择

        Yields:
            音频数据块

        Raises:
            TTSServiceError: 服务异常
        """
        # 验证输入
        text = self._validate_text(text)
        if not self._validate_voice(voice):
            raise TTSServiceError(f"Invalid voice: {voice}. Available: {list(self.VOICES.keys())}")

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                async with client.stream(
                    "POST",
                    f"{self.base_url}/v1/tts",
                    json={
                        "text": text,
                        "model": "kokoro",
                        "voice": voice
                    }
                ) as response:
                    if response.status_code == 200:
                        async for chunk in response.aiter_bytes(chunk_size=8192):
                            if chunk:
                                yield chunk
                    elif response.status_code == 400:
                        raise TTSServiceError("Invalid request parameters")
                    elif response.status_code == 422:
                        raise TTSServiceError("Text contains invalid characters")
                    else:
                        raise TTSServiceError(f"TTS API error: HTTP {response.status_code}")

            except httpx.TimeoutException:
                raise TTSServiceError("TTS request timeout")
            except httpx.ConnectError:
                raise TTSServiceError(f"Cannot connect to TTS service at {self.base_url}")
            except TTSServiceError:
                raise
            except Exception as e:
                raise TTSServiceError(f"TTS streaming failed: {str(e)}")

    def get_available_voices(self) -> list:
        """获取所有可用声音"""
        return [
            {"id": voice_id, **voice_info}
            for voice_id, voice_info in self.VOICES.items()
        ]

    async def health_check(self) -> dict:
        """健康检查"""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{self.base_url}/health")
                if response.status_code == 200:
                    return {"status": "healthy", "service": self.base_url}
                else:
                    return {"status": "unhealthy", "service": self.base_url, "error": f"HTTP {response.status_code}"}
        except Exception as e:
            return {"status": "unhealthy", "service": self.base_url, "error": str(e)}


# 全局单例
tts_service = TTSService()