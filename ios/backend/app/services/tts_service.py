"""
PAI-CC TTS 服务
"""
import httpx
import base64
import os
from datetime import datetime
from app.core.config import settings


class TTSService:
    """TTS 语音合成服务"""

    def __init__(self):
        self.base_url = settings.tts_base_url

    async def synthesize(
        self,
        text: str,
        voice: str = "af_heart",
        output_filename: str = None
    ) -> str:
        """
        合成语音

        Args:
            text: 要合成的文本
            voice: 声音选择
            output_filename: 输出文件名

        Returns:
            音频文件路径
        """
        if not output_filename:
            output_filename = f"tts_{datetime.now().timestamp()}.wav"

        output_path = os.path.join(settings.upload_dir, "audio", output_filename)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        async with httpx.AsyncClient(timeout=60.0) as client:
            try:
                response = await client.post(
                    f"{self.base_url}/v1/tts",
                    json={
                        "text": text[:1000],  # 限制长度
                        "model": "kokoro",
                        "voice": voice
                    }
                )

                if response.status_code == 200:
                    with open(output_path, "wb") as f:
                        f.write(response.content)
                    return output_path
                else:
                    raise Exception(f"TTS API error: {response.status_code}")

            except Exception as e:
                raise Exception(f"TTS synthesis failed: {str(e)}")

    async def synthesize_stream(self, text: str, voice: str = "af_heart") -> bytes:
        """
        流式合成语音（返回字节）

        Args:
            text: 要合成的文本
            voice: 声音选择

        Returns:
            音频数据（bytes）
        """
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                f"{self.base_url}/v1/tts",
                json={
                    "text": text[:1000],
                    "model": "kokoro",
                    "voice": voice
                }
            )

            if response.status_code == 200:
                return response.content
            else:
                raise Exception(f"TTS API error: {response.status_code}")


# 全局单例
tts_service = TTSService()