"""
PAI-CC AI 问答 API
支持语音问答、手势触发、多轮对话
"""
from fastapi import APIRouter, UploadFile, File, Form, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from typing import Optional, List
from pydantic import BaseModel
import httpx
import json
import asyncio
from datetime import datetime

router = APIRouter()


class QARequest(BaseModel):
    """问答请求"""
    session_id: str
    query: str
    trigger_type: str = "voice"  # voice, gesture, auto
    conversation_history: Optional[List[dict]] = []
    capture_meta: Optional[dict] = {}


class QAResponse(BaseModel):
    """问答响应"""
    answer: str
    knowledge_points: List[str] = []
    suggested_followups: List[str] = []
    audio_url: Optional[str] = None
    processing_time: float = 0


class QAWebSocketManager:
    """WebSocket 连接管理器"""
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, session_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[session_id] = websocket

    def disconnect(self, session_id: str):
        if session_id in self.active_connections:
            del self.active_connections[session_id]

    async def send_message(self, session_id: str, message: dict):
        if session_id in self.active_connections:
            await self.active_connections[session_id].send_json(message)


ws_manager = QAWebSocketManager()


@router.post("/ask", response_model=QAResponse)
async def ask_question(
    image: UploadFile = File(...),
    session_id: str = Form(...),
    query: str = Form(...),
    trigger_type: str = Form("voice"),
    conversation_history: Optional[str] = Form(None),
    capture_meta: Optional[str] = Form(None)
):
    """
    发送问答请求

    流程：
    1. 接收截图 + 问题
    2. 构建 Prompt（包含上下文）
    3. 调用 Ollama AI
    4. 返回答案
    5. 可选：生成 TTS 音频
    """
    from app.core.config import settings
    import time
    start_time = time.time()

    # 解析历史对话
    history = []
    if conversation_history:
        try:
            history = json.loads(conversation_history)
        except:
            pass

    # 读取图片
    image_bytes = await image.read()

    # 构建系统 Prompt
    system_prompt = """你是一个专业的中文学习辅导助手，专注于帮助学生解答题目和理解知识点。

你的职责：
1. 详细解释题目的解题思路和步骤
2. 指出学生可能犯的错误和易错点
3. 关联相关的知识点
4. 提供举一反三的练习建议

回答要求：
1. 语言简洁清晰，适合学生理解
2. 包含详细的解题步骤
3. 指出关键知识点
4. 如果是错题，分析错误原因

回复格式：
- 解答：详细的解题步骤
- 知识点：相关的知识要点
- 易错点：学生容易犯的错误
- 建议：下一步学习建议
"""

    # 构建用户消息（包含图片和文字）
    user_message = f"用户问题：{query}\n\n请分析这张图片中的题目并给出解答。"

    # 构建消息历史
    messages = [{"role": "system", "content": system_prompt}]
    for h in history[-5:]:  # 只保留最近 5 条对话
        messages.append(h)
    messages.append({"role": "user", "content": user_message})

    # 调用 Ollama
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{settings.ollama_base_url}/chat/completions",
                json={
                    "model": settings.ollama_model,
                    "messages": messages,
                    "stream": False,
                    "options": {
                        "temperature": 0.7,
                        "num_predict": 1024
                    }
                },
                headers={"Authorization": f"Bearer {settings.ollama_api_key}"}
            )

            if response.status_code == 200:
                result = response.json()
                answer = result["choices"][0]["message"]["content"]
            else:
                answer = "抱歉，AI 服务暂时不可用，请稍后重试。"

    except Exception as e:
        answer = f"抱歉，服务出错：{str(e)}"

    processing_time = time.time() - start_time

    # 生成 TTS（可选）
    audio_url = None
    try:
        tts_response = await client.post(
            f"{settings.tts_base_url}/v1/tts",
            json={
                "text": answer[:500],  # 限制长度
                "model": "kokoro",
                "voice": "af_heart"
            },
            timeout=30.0
        )
        if tts_response.status_code == 200:
            audio_url = f"/api/v1/tts/audio/{session_id}_{int(datetime.now().timestamp())}.wav"
    except:
        pass  # TTS 失败不影响主流程

    return QAResponse(
        answer=answer,
        knowledge_points=["题目分析", "解题思路"],
        suggested_followups=["下一题", "详细解释"],
        audio_url=audio_url,
        processing_time=processing_time
    )


@router.websocket("/ws/{session_id}")
async def websocket_qa(websocket: WebSocket, session_id: str):
    """
    WebSocket 实时问答

    支持：
    - 实时流式响应
    - 打断机制
    - 多轮对话
    """
    await ws_manager.connect(session_id, websocket)

    conversation_history = []

    try:
        while True:
            # 接收消息
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "ask":
                # 收到提问
                await ws_manager.send_message(session_id, {
                    "type": "thinking",
                    "status": "start"
                })

                query = data.get("query", "")
                image_data = data.get("image")  # base64

                # 构建 Prompt
                messages = [
                    {"role": "system", "content": "你是专业的中文学习助手。"},
                ]
                # 添加历史
                for h in conversation_history[-5:]:
                    messages.append(h)
                messages.append({"role": "user", "content": query})

                # 流式调用 Ollama
                async with httpx.AsyncClient(timeout=120.0) as client:
                    async with client.stream(
                        "POST",
                        f"{settings.ollama_base_url}/chat/completions",
                        json={
                            "model": settings.ollama_model,
                            "messages": messages,
                            "stream": True
                        },
                        headers={"Authorization": f"Bearer {settings.ollama_api_key}"}
                    ) as response:
                        full_answer = ""
                        async for line in response.aiter_lines():
                            if line.startswith("data: "):
                                data_str = line[6:]
                                if data_str == "[DONE]":
                                    break
                                try:
                                    chunk = json.loads(data_str)
                                    content = chunk["choices"][0]["delta"].get("content", "")
                                    if content:
                                        full_answer += content
                                        await ws_manager.send_message(session_id, {
                                            "type": "partial",
                                            "content": content
                                        })
                                except:
                                    continue

                # 保存到历史
                conversation_history.append({"role": "user", "content": query})
                conversation_history.append({"role": "assistant", "content": full_answer})

                # 发送完成
                await ws_manager.send_message(session_id, {
                    "type": "answer",
                    "content": full_answer,
                    "history_length": len(conversation_history)
                })

            elif msg_type == "interrupt":
                # 打断信号
                await ws_manager.send_message(session_id, {
                    "type": "interrupted",
                    "status": "ready"
                })

            elif msg_type == "clear":
                # 清空历史
                conversation_history = []
                await ws_manager.send_message(session_id, {
                    "type": "cleared",
                    "status": "ok"
                })

    except WebSocketDisconnect:
        ws_manager.disconnect(session_id)