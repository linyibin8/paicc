"""
PAI-CC Ollama AI 服务
"""
import httpx
import json
from typing import List, Dict, Optional, AsyncIterator, Union, Any
import base64
from app.core.config import settings


# 消息内容类型：可以是字符串或包含 image_url 的列表
MessageContent = Union[str, List[Dict[str, Any]]]
Message = Dict[str, Any]


class OllamaService:
    """Ollama AI 服务封装"""

    def __init__(self):
        self.base_url = settings.ollama_base_url
        self.api_key = settings.ollama_api_key
        self.model = settings.ollama_model

    async def chat(
        self,
        messages: List[Message],
        stream: bool = False,
        temperature: float = 0.7,
        max_tokens: int = 1024
    ) -> Dict:
        """
        发送聊天请求

        Args:
            messages: 消息列表，支持多种格式：
                - 简单文本: [{"role": "user", "content": "..."}]
                - 带图片: [{"role": "user", "content": [
                    {"type": "text", "text": "..."},
                    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
                ]}]
            stream: 是否流式返回
            temperature: 温度参数
            max_tokens: 最大 token 数

        Returns:
            AI 回复内容
        """
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": stream,
                    "options": {
                        "temperature": temperature,
                        "num_predict": max_tokens
                    }
                },
                headers={"Authorization": f"Bearer {self.api_key}"}
            )

            if response.status_code == 200:
                return response.json()
            else:
                raise Exception(f"Ollama API error: {response.status_code}")

    async def chat_stream(
        self,
        messages: List[Message],
    ) -> AsyncIterator[str]:
        """
        流式聊天

        Args:
            messages: 消息列表，支持多种格式（同 chat 方法）

        Yields:
            每次返回一个文本片段
        """
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/chat/completions",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": True
                },
                headers={"Authorization": f"Bearer {self.api_key}"}
            ) as response:
                async for line in response.aiter_lines():
                    if line.startswith("data: "):
                        data_str = line[6:]
                        if data_str == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data_str)
                            content = chunk["choices"][0]["delta"].get("content", "")
                            if content:
                                yield content
                        except:
                            continue

    async def analyze_image(
        self,
        image_base64: str,
        prompt: str,
        system_prompt: Optional[str] = None
    ) -> str:
        """
        分析图片

        Args:
            image_base64: base64 编码的图片
            prompt: 分析提示词
            system_prompt: 系统提示词

        Returns:
            分析结果
        """
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})

        messages.append({
            "role": "user",
            "content": prompt,
            "images": [image_base64]
        })

        result = await self.chat(messages)
        return result["choices"][0]["message"]["content"]

    async def extract_learning_items(self, image_base64: str, capture_id: str) -> Dict:
        """
        从图片中抽取学习条目

        Args:
            image_base64: 图片
            capture_id: 采集 ID

        Returns:
            学习条目数据
        """
        system_prompt = """你是一个专业的学习内容分析助手。从学生拍摄的图片中提取学习内容。

请分析图片并返回以下 JSON 格式的数据：
{
    "items": [
        {
            "type": "question",  // question, answer, knowledge_point, note
            "subject": "数学",
            "page_number": "12",
            "question_number": "3",
            "title": "题目描述",
            "content": "题目完整内容",
            "solution": "解题步骤",
            "knowledge_points": ["知识点1", "知识点2"]
        }
    ],
    "mistakes": [
        {
            "subject": "数学",
            "page_number": "12",
            "question_number": "3",
            "student_answer": "学生的错误答案",
            "correct_answer": "正确答案",
            "error_reason": "错误原因",
            "knowledge_points": ["相关知识点"],
            "correction_suggestion": "订正建议"
        }
    ],
    "quality_score": 0.85,  // 画面质量分数 0-1
    "student_present": true  // 是否有学生在场
}

只返回 JSON，不要有其他内容。"""

        user_prompt = f"请分析这张图片，提取学习内容。capture_id: {capture_id}"

        result = await self.analyze_image(image_base64, user_prompt, system_prompt)

        try:
            # 尝试解析 JSON
            data = json.loads(result)
            return data
        except:
            return {"items": [], "mistakes": [], "error": result}

    async def generate_session_report(self, session_data: Dict) -> Dict:
        """
        生成学习回合报告

        Args:
            session_data: 会话数据

        Returns:
            报告内容
        """
        system_prompt = """你是一个专业的学习分析师。根据学生的学习记录生成回合报告。

分析以下数据并生成报告：

1. 时间线分析
2. 学习内容统计
3. 错题分析
4. 知识点掌握情况
5. 学习建议

请返回详细的报告内容。"""

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"请分析以下学习数据并生成报告：\n{json.dumps(session_data, ensure_ascii=False, indent=2)}"}
        ]

        result = await self.chat(messages, temperature=0.5, max_tokens=2048)
        return {"report": result["choices"][0]["message"]["content"]}

    async def check_vision_capability(self) -> bool:
        """
        检测模型是否支持视觉/图片输入

        通过发送一个包含简单图片的请求来检测

        Returns:
            True 如果支持 vision，False 如果不支持
        """
        # 创建一个最小的白色 1x1 PNG 图片作为测试
        # PNG 文件头 + IHDR + IDAT + IEND (最小有效 PNG)
        minimal_png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

        test_messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Hi"},
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{minimal_png_base64}"}}
                ]
            }
        ]

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    json={
                        "model": self.model,
                        "messages": test_messages,
                        "max_tokens": 5
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"}
                )

                # 422 通常表示模型不支持该参数（vision）
                if response.status_code == 422:
                    return False

                # 其他 2xx 状态码表示支持
                if response.status_code < 300:
                    return True

                return False

        except Exception as e:
            print(f"Vision capability check failed: {e}")
            return False


# 全局单例
ollama_service = OllamaService()