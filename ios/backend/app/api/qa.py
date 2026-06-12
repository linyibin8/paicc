"""
PAI-CC 完整 AI 问答 API
支持语音问答、手势触发、WebSocket 多轮对话
"""
from fastapi import APIRouter, UploadFile, File, Form, WebSocket, WebSocketDisconnect, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
import uuid
import json
import asyncio
import base64
import os
from datetime import datetime

from app.models.database import get_db
from app.core.config import settings
from app.services.ollama_service import ollama_service
from app.services.tts_service import tts_service

router = APIRouter()


# ============ 数据模型 ============

class QARequest(BaseModel):
    """问答请求"""
    session_id: str
    query: str
    trigger_type: str = "voice"  # voice, gesture, auto
    conversation_history: List[dict] = []
    capture_meta: dict = {}


class QAResponse(BaseModel):
    """问答响应"""
    answer: str
    knowledge_points: List[str] = []
    suggested_followups: List[str] = []
    audio_url: Optional[str] = None
    processing_time: float = 0


class QAStreamMessage(BaseModel):
    """WebSocket 流式消息"""
    type: str  # thinking, partial, answer, interrupted, error
    content: Optional[str] = None
    status: Optional[str] = None
    history_length: Optional[int] = None


# ============ WebSocket 管理器 ============

class QAWebSocketManager:
    """管理所有活跃的 WebSocket 连接"""

    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}
        self.conversation_histories: dict[str, List[dict]] = {}

    async def connect(self, session_id: str, websocket: WebSocket):
        """连接 WebSocket"""
        await websocket.accept()
        self.active_connections[session_id] = websocket
        self.conversation_histories[session_id] = []

    def disconnect(self, session_id: str):
        """断开连接"""
        if session_id in self.active_connections:
            del self.active_connections[session_id]
        if session_id in self.conversation_histories:
            del self.conversation_histories[session_id]

    async def send_json(self, session_id: str, data: dict):
        """发送 JSON 消息"""
        if session_id in self.active_connections:
            await self.active_connections[session_id].send_json(data)

    def get_history(self, session_id: str) -> List[dict]:
        """获取对话历史"""
        return self.conversation_histories.get(session_id, [])

    def add_to_history(self, session_id: str, role: str, content: str):
        """添加到对话历史"""
        if session_id not in self.conversation_histories:
            self.conversation_histories[session_id] = []
        self.conversation_histories[session_id].append({
            "role": role,
            "content": content
        })
        # 保持最近 20 条
        if len(self.conversation_histories[session_id]) > 20:
            self.conversation_histories[session_id] = self.conversation_histories[session_id][-20:]


ws_manager = QAWebSocketManager()


# ============ 系统提示词 ============

SYSTEM_PROMPT = """你是一个专业的中文学习辅导助手，专注于帮助学生解答题目和理解知识点。

你的核心原则：
1. 随时待命 - 学生有问题时立即响应，不打扰时安静观察
2. 详细解答 - 提供完整的解题思路和步骤
3. 指出易错点 - 提醒学生常见的错误
4. 关联知识点 - 帮助学生建立知识网络

回答格式：
📝 **解答**：
   [详细步骤]

📚 **知识点**：
   - [知识点1]
   - [知识点2]

⚠️ **易错点**：
   [学生容易犯的错误]

💡 **建议**：
   [下一步学习建议]"""


# ============ REST API ============

@router.post("/ask", response_model=QAResponse)
async def ask_question(
    image: UploadFile = File(...),
    session_id: str = Form(...),
    query: str = Form(...),
    trigger_type: str = Form("voice"),
    conversation_history: Optional[str] = Form(None),
    capture_meta: Optional[str] = Form(None),
    db: Session = Depends(get_db)
):
    """
    发送问答请求（REST）

    流程：
    1. 接收截图 + 问题
    2. 构建 Prompt（包含上下文）
    3. 调用 Ollama AI
    4. 可选：生成 TTS 音频
    5. 返回答案
    """
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

    # 构建消息
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    for h in history[-5:]:
        messages.append(h)
    messages.append({"role": "user", "content": f"图片内容 + 问题：{query}"})

    # 调用 Ollama
    try:
        result = await ollama_service.chat(messages)
        answer = result["choices"][0]["message"]["content"]
    except Exception as e:
        answer = f"抱歉，AI 服务暂时不可用：{str(e)}"

    processing_time = time.time() - start_time

    # 生成 TTS
    audio_url = None
    try:
        filename = f"tts_{session_id}_{int(datetime.now().timestamp())}.wav"
        audio_path = await tts_service.synthesize(answer[:500], output_filename=filename)
        audio_url = f"/uploads/audio/{filename}"
    except:
        pass

    return QAResponse(
        answer=answer,
        knowledge_points=["题目分析", "解题思路"],
        suggested_followups=["下一题", "详细解释", "举一反三"],
        audio_url=audio_url,
        processing_time=processing_time
    )


# ============ WebSocket API ============

@router.websocket("/ws/{session_id}")
async def websocket_qa(websocket: WebSocket, session_id: str):
    """
    WebSocket 实时问答

    支持：
    - 实时流式响应
    - 打断机制
    - 多轮对话
    - 语音/手势触发
    """
    await ws_manager.connect(session_id, websocket)

    try:
        while True:
            # 接收消息
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "ask":
                # ========== 处理提问 ==========
                await ws_manager.send_json(session_id, {
                    "type": "thinking",
                    "status": "start",
                    "message": "正在思考..."
                })

                query = data.get("query", "")
                image_base64 = data.get("image")  # 可选的 base64 图片

                # 构建消息
                messages = [{"role": "system", "content": SYSTEM_PROMPT}]
                for h in ws_manager.get_history(session_id)[-10:]:
                    messages.append(h)

                if image_base64:
                    messages.append({
                        "role": "user",
                        "content": [
                            {"type": "text", "text": query},
                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}}
                        ]
                    })
                else:
                    messages.append({"role": "user", "content": query})

                # 流式调用 Ollama
                full_answer = ""
                try:
                    async for chunk in ollama_service.chat_stream(messages):
                        full_answer += chunk
                        await ws_manager.send_json(session_id, {
                            "type": "partial",
                            "content": chunk
                        })
                except Exception as e:
                    await ws_manager.send_json(session_id, {
                        "type": "error",
                        "content": str(e)
                    })
                    continue

                # 保存到历史
                ws_manager.add_to_history(session_id, "user", query)
                ws_manager.add_to_history(session_id, "assistant", full_answer)

                # 发送完成
                await ws_manager.send_json(session_id, {
                    "type": "answer",
                    "content": full_answer,
                    "history_length": len(ws_manager.get_history(session_id))
                })

                # 触发 TTS（可选）
                if data.get("speak", False):
                    try:
                        await ws_manager.send_json(session_id, {
                            "type": "tts_start",
                            "status": "playing"
                        })
                        filename = f"tts_{session_id}_{int(datetime.now().timestamp())}.wav"
                        audio_path = await tts_service.synthesize(full_answer[:500], output_filename=filename)
                        await ws_manager.send_json(session_id, {
                            "type": "tts_ready",
                            "audio_url": f"/uploads/audio/{filename}"
                        })
                    except Exception as e:
                        print(f"TTS error: {e}")

            elif msg_type == "interrupt":
                # ========== 打断信号 ==========
                await ws_manager.send_json(session_id, {
                    "type": "interrupted",
                    "status": "ready",
                    "message": "好的，请说..."
                })

            elif msg_type == "clear":
                # ========== 清空历史 ==========
                ws_manager.conversation_histories[session_id] = []
                await ws_manager.send_json(session_id, {
                    "type": "cleared",
                    "status": "ok"
                })

            elif msg_type == "speak":
                # ========== 语音播报 ==========
                text = data.get("text", "")
                if text:
                    try:
                        filename = f"tts_{session_id}_{int(datetime.now().timestamp())}.wav"
                        audio_path = await tts_service.synthesize(text[:500], output_filename=filename)
                        await ws_manager.send_json(session_id, {
                            "type": "tts_ready",
                            "audio_url": f"/uploads/audio/{filename}"
                        })
                    except Exception as e:
                        await ws_manager.send_json(session_id, {
                            "type": "error",
                            "content": f"TTS error: {str(e)}"
                        })

    except WebSocketDisconnect:
        ws_manager.disconnect(session_id)


# ============ 辅助端点 ============

@router.get("/history/{session_id}")
async def get_conversation_history(session_id: str):
    """获取对话历史"""
    return {
        "session_id": session_id,
        "history": ws_manager.get_history(session_id)
    }


@router.post("/trigger")
async def trigger_qa(
    session_id: str = Form(...),
    trigger_type: str = Form("gesture"),  # voice, gesture, auto
    image: UploadFile = File(None),
    db: Session = Depends(get_db)
):
    """
    触发问答模式

    当用户做出特定手势或说话时调用此接口
    返回提示音和确认信息
    """
    # 生成提示音
    prompt_text = "请说" if trigger_type == "voice" else "请说"
    audio_url = None

    try:
        filename = f"prompt_{session_id}_{int(datetime.now().timestamp())}.wav"
        audio_path = await tts_service.synthesize(prompt_text, voice="af_bella", output_filename=filename)
        audio_url = f"/uploads/audio/{filename}"
    except:
        pass

    return {
        "status": "ready",
        "trigger_type": trigger_type,
        "prompt_audio": audio_url,
        "message": "请说出您的问题"
    }