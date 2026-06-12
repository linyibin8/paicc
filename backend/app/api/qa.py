"""
PAI-CC 完整 AI 问答 API
支持语音问答、手势触发、WebSocket 多轮对话、流式响应
"""
from fastapi import APIRouter, UploadFile, File, Form, WebSocket, WebSocketDisconnect, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
import uuid
import json
import asyncio
import base64
import os
import time
import re
from enum import Enum

from app.models.database import get_db
from app.core.config import settings
from app.services.ollama_service import ollama_service
from app.services.tts_service import tts_service, TTSServiceError

router = APIRouter()


# ============ 枚举定义 ============

class TriggerType(str, Enum):
    VOICE = "voice"
    GESTURE = "gesture"
    AUTO = "auto"


class StreamMessageType(str, Enum):
    THINKING = "thinking"
    PARTIAL = "partial"
    ANSWER = "answer"
    ERROR = "error"
    INTERRUPTED = "interrupted"
    TTS_START = "tts_start"
    TTS_READY = "tts_ready"
    TTS_ERROR = "tts_error"
    HISTORY_UPDATE = "history_update"
    CLEARED = "cleared"
    MISTAKE_CREATED = "mistake_created"


# ============ 数据模型 ============

class QARequest(BaseModel):
    """问答请求"""
    session_id: str
    query: str
    trigger_type: TriggerType = TriggerType.VOICE
    conversation_history: List[dict] = []
    capture_meta: dict = {}


class QAResponse(BaseModel):
    """问答响应"""
    answer: str
    knowledge_points: List[str] = []
    suggested_followups: List[str] = []
    audio_url: Optional[str] = None
    processing_time: float = 0
    vision_supported: bool = True
    fallback_used: bool = False


class QAStreamMessage(BaseModel):
    """WebSocket 流式消息"""
    type: StreamMessageType
    content: Optional[str] = None
    status: Optional[str] = None
    history_length: Optional[int] = None
    metadata: Optional[Dict[str, Any]] = None


class HistoryMessage(BaseModel):
    """对话历史消息"""
    role: str  # user, assistant, system
    content: str
    timestamp: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class HistoryResponse(BaseModel):
    """历史记录响应"""
    session_id: str
    history: List[HistoryMessage]
    total_count: int
    message_count: int


class TTSRequest(BaseModel):
    """TTS 请求"""
    text: str
    voice: str = "af_bella"
    session_id: Optional[str] = None


class SystemPromptConfig(BaseModel):
    """系统提示词配置"""
    name: str
    content: str
    description: Optional[str] = None
    is_active: bool = False


class SystemPromptResponse(BaseModel):
    """提示词响应"""
    active_prompt: str
    available_prompts: List[SystemPromptConfig]


# ============ WebSocket 管理器 ============

class QAWebSocketManager:
    """管理所有活跃的 WebSocket 连接"""

    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.conversation_histories: Dict[str, List[dict]] = {}
        self.interrupted_sessions: set = set()
        self.model_capabilities: Dict[str, bool] = {}  # 缓存模型能力
        self.max_history: int = 20  # 最大历史条数
        self.tts_enabled: bool = True  # TTS 开关

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
        self.interrupted_sessions.discard(session_id)

    async def send_json(self, session_id: str, data: dict):
        """发送 JSON 消息"""
        if session_id in self.active_connections:
            try:
                await self.active_connections[session_id].send_json(data)
            except Exception as e:
                print(f"WebSocket send error: {e}")
                self.disconnect(session_id)

    def is_interrupted(self, session_id: str) -> bool:
        """检查是否被打断"""
        return session_id in self.interrupted_sessions

    def set_interrupted(self, session_id: str, value: bool = True):
        """设置打断状态"""
        if value:
            self.interrupted_sessions.add(session_id)
        else:
            self.interrupted_sessions.discard(session_id)

    def get_history(self, session_id: str) -> List[dict]:
        """获取对话历史"""
        return self.conversation_histories.get(session_id, [])

    def add_to_history(self, session_id: str, role: str, content: str, metadata: dict = None):
        """添加到对话历史"""
        if session_id not in self.conversation_histories:
            self.conversation_histories[session_id] = []

        message = {
            "role": role,
            "content": content,
            "timestamp": datetime.now().isoformat()
        }
        if metadata:
            message["metadata"] = metadata

        self.conversation_histories[session_id].append(message)

        # 保持最近 max_history 条
        if len(self.conversation_histories[session_id]) > self.max_history:
            self.conversation_histories[session_id] = self.conversation_histories[session_id][-self.max_history:]

    def clear_history(self, session_id: str):
        """清空对话历史"""
        self.conversation_histories[session_id] = []

    def get_history_count(self, session_id: str) -> int:
        """获取历史条数"""
        return len(self.conversation_histories.get(session_id, []))

    def set_model_capability(self, session_id: str, vision_supported: bool):
        """设置模型视觉能力"""
        self.model_capabilities[session_id] = vision_supported

    def get_model_capability(self, session_id: str) -> Optional[bool]:
        """获取模型视觉能力"""
        return self.model_capabilities.get(session_id)

    def remove_session(self, session_id: str):
        """移除会话"""
        self.disconnect(session_id)
        self.model_capabilities.pop(session_id, None)


ws_manager = QAWebSocketManager()


# ============ 系统提示词配置 ============

# 默认学习辅导助手提示词
DEFAULT_SYSTEM_PROMPT = """你是一个专业的中文学习辅导助手，专注于帮助学生解答题目和理解知识点。

你的核心原则：
1. 随时待命 - 学生有问题时立即响应，不打扰时安静观察
2. 详细解答 - 提供完整的解题思路和步骤
3. 指出易错点 - 提醒学生常见的错误
4. 关联知识点 - 帮助学生建立知识网络
5. 耐心引导 - 用温和的方式引导学生思考

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

# 预设提示词库
SYSTEM_PROMPTS = {
    "default": SystemPromptConfig(
        name="default",
        content=DEFAULT_SYSTEM_PROMPT,
        description="默认学习辅导助手",
        is_active=True
    ),
    "strict": SystemPromptConfig(
        name="strict",
        content="""你是一个严格的数学老师，对学生的解题过程要求严格。

要求：
1. 严格检查每一步计算
2. 指出所有不规范的地方
3. 对错误绝不姑息
4. 要求学生按标准格式书写

回复风格：严肃、严格、直接指出问题。""",
        description="严格模式",
        is_active=False
    ),
    "encourage": SystemPromptConfig(
        name="encourage",
        content="""你是一个温暖鼓励的学习伙伴。

特点：
1. 总是先肯定学生的努力
2. 用温和的方式指出问题
3. 强调"你一定能行"
4. 多用鼓励性语言

回复风格：温暖、鼓励、充满正能量。""",
        description="鼓励模式",
        is_active=False
    ),
    "exam_prep": SystemPromptConfig(
        name="exam_prep",
        content="""你是一个专注于考试备考的学习教练。

职责：
1. 帮助学生复习考试重点
2. 提供模拟练习题
3. 讲解解题技巧和应试策略
4. 帮助学生建立考试信心

回复格式：
📋 **考点分析**：
🎯 **解题技巧**：
📝 **练习题**：
💪 **备考建议**：""",
        description="考试备考模式",
        is_active=False
    ),
    "mistake_review": SystemPromptConfig(
        name="mistake_review",
        content="""你是一个错题分析专家。

任务：
1. 分析学生错题的原因
2. 找出知识漏洞
3. 提供针对性的练习
4. 帮助学生巩固相关知识点

回复格式：
🔍 **错误分析**：
📖 **知识点讲解**：
✏️ **相关练习**：
🔄 **复习建议**：""",
        description="错题复习模式",
        is_active=False
    )
}

# 当前激活的提示词
active_prompt_name = "default"


def get_active_system_prompt() -> str:
    """获取当前激活的系统提示词"""
    return SYSTEM_PROMPTS.get(active_prompt_name, SYSTEM_PROMPTS["default"]).content


def set_active_prompt(prompt_name: str) -> bool:
    """设置激活的提示词"""
    global active_prompt_name
    if prompt_name in SYSTEM_PROMPTS:
        # 重置所有提示词的激活状态
        for name in SYSTEM_PROMPTS:
            SYSTEM_PROMPTS[name].is_active = (name == prompt_name)
        active_prompt_name = prompt_name
        return True
    return False


# ============ 辅助函数 ============

def extract_knowledge_points(text: str) -> List[str]:
    """从回答中提取知识点"""
    points = []
    patterns = [
        r'[📚知识点](.*?)(?=\n|$)',
        r'[-*]\s*(.*?知识点.*?)(?=\n|$)',
        r'涉及.*?：\s*(.*?)(?=\n|$)',
    ]
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        points.extend(matches)
    return list(set(points))[:5]


def extract_suggested_followups(text: str) -> List[str]:
    """从回答中提取建议的后续问题"""
    suggestions = []
    suggestion_keywords = ["下一题", "详细解释", "举一反三", "换个题目", "继续", "下一道"]
    for keyword in suggestion_keywords:
        if keyword in text:
            suggestions.append(keyword)
    return suggestions if suggestions else ["详细解释", "举一反三", "换一道题"]


def clean_text_for_tts(text: str, max_length: int = 500) -> str:
    """清理文本以适配 TTS"""
    # 移除 emoji
    text = re.sub(r'[\U00010000-\U0010ffff]', '', text)
    # 移除 markdown 格式
    text = re.sub(r'[*_#>`\[\]]', '', text)
    # 移除多余空白
    text = re.sub(r'\s+', ' ', text)
    # 截断
    return text[:max_length].strip()


def parse_mistake_info(text: str) -> Optional[Dict]:
    """从回答中解析错题信息"""
    # 简单实现，可以根据实际返回格式调整
    try:
        if "错题" in text or "错误" in text:
            return {
                "has_mistake": True,
                "needs_review": True
            }
    except:
        pass
    return None


async def trigger_tts(session_id: str, text: str, voice: str = "af_bella"):
    """触发 TTS 语音合成"""
    try:
        # 通知 TTS 开始
        await ws_manager.send_json(session_id, {
            "type": StreamMessageType.TTS_START.value,
            "status": "processing",
            "message": "正在生成语音..."
        })

        # 清理文本
        clean_text = clean_text_for_tts(text)
        if not clean_text:
            raise TTSServiceError("Text is empty after cleaning")

        # 生成音频
        filename = f"tts_{session_id}_{int(time.time())}.wav"
        audio_path = await tts_service.synthesize(clean_text, voice=voice, output_filename=filename)

        # 通知 TTS 完成
        await ws_manager.send_json(session_id, {
            "type": StreamMessageType.TTS_READY.value,
            "status": "ready",
            "audio_url": f"/uploads/audio/{filename}",
            "message": "语音已生成"
        })
        return True

    except TTSServiceError as e:
        await ws_manager.send_json(session_id, {
            "type": StreamMessageType.TTS_ERROR.value,
            "status": "error",
            "error": str(e),
            "message": "语音生成失败"
        })
        return False
    except Exception as e:
        await ws_manager.send_json(session_id, {
            "type": StreamMessageType.TTS_ERROR.value,
            "status": "error",
            "error": f"TTS unexpected error: {str(e)}",
            "message": "语音生成失败"
        })
        return False


async def process_vision_request(
    session_id: str,
    messages: List[dict],
    image_base64: str,
    query: str
) -> tuple[str, bool]:
    """
    处理带图片的请求

    Returns:
        (answer, vision_supported) - 回答内容和是否使用了 vision
    """
    # 检查缓存的模型能力
    cached_capability = ws_manager.get_model_capability(session_id)

    # 构建带图片的消息
    vision_messages = messages.copy()
    vision_messages.append({
        "role": "user",
        "content": [
            {"type": "text", "text": query},
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}}
        ]
    })

    # 如果已知不支持 vision，直接回退
    if cached_capability is False:
        return await _process_text_fallback(session_id, messages, query), False

    # 尝试使用 vision
    try:
        full_answer = ""
        first_chunk = True

        async for chunk in ollama_service.chat_stream(vision_messages):
            # 检查打断
            if ws_manager.is_interrupted(session_id):
                return "[回答已被打断]", True
            full_answer += chunk
            first_chunk = False

        ws_manager.set_model_capability(session_id, True)
        return full_answer, True

    except Exception as e:
        error_str = str(e).lower()

        # 检测是否是不支持 vision 的错误
        vision_unsupported_keywords = [
            "vision", "image", "unsupported", "does not support",
            "invalid parameter", "model does not support", "422"
        ]

        if any(keyword in error_str for keyword in vision_unsupported_keywords):
            ws_manager.set_model_capability(session_id, False)
            return await _process_text_fallback(session_id, messages, query), False

        # 其他错误，抛出
        raise


async def _process_text_fallback(
    session_id: str,
    messages: List[dict],
    query: str
) -> str:
    """纯文本回退处理"""
    # 添加用户消息（不含图片）
    fallback_messages = messages.copy()
    fallback_messages.append({
        "role": "user",
        "content": f"{query}\n\n（注意：图片无法显示，请根据描述或上下文回答）"
    })

    full_answer = ""
    async for chunk in ollama_service.chat_stream(fallback_messages):
        if ws_manager.is_interrupted(session_id):
            return "[回答已被打断]"
        full_answer += chunk

    return full_answer


# ============ REST API ============

@router.post("/ask", response_model=QAResponse)
async def ask_question(
    image: UploadFile = File(...),
    session_id: str = Form(...),
    query: str = Form(...),
    trigger_type: str = Form("voice"),
    conversation_history: Optional[str] = Form(None),
    capture_meta: Optional[str] = Form(None),
    enable_tts: bool = Form(True),
    voice: str = Form("af_bella"),
    db: Session = Depends(get_db)
):
    """
    发送问答请求（REST）

    流程：
    1. 接收截图 + 问题
    2. 检测模型视觉能力
    3. 调用 Ollama AI（支持 vision 回退）
    4. 可选：生成 TTS 音频
    5. 返回答案
    """
    start_time = time.time()
    fallback_used = False

    # 解析历史对话
    history = []
    if conversation_history:
        try:
            history = json.loads(conversation_history)
        except:
            pass

    # 读取图片
    image_bytes = await image.read()
    image_base64 = base64.b64encode(image_bytes).decode()

    # 构建消息
    messages = [{"role": "system", "content": get_active_system_prompt()}]
    for h in history[-5:]:
        messages.append(h)

    # 调用 Ollama（带 vision 支持检测）
    try:
        answer, vision_supported = await process_vision_request(
            session_id, messages, image_base64, query
        )
        fallback_used = not vision_supported
    except Exception as e:
        answer = f"抱歉，AI 服务暂时不可用：{str(e)}"

    processing_time = time.time() - start_time

    # 生成 TTS
    audio_url = None
    if enable_tts and answer and not answer.startswith("抱歉"):
        try:
            clean_text = clean_text_for_tts(answer)
            if clean_text:
                filename = f"tts_{session_id}_{int(datetime.now().timestamp())}.wav"
                audio_path = await tts_service.synthesize(
                    clean_text,
                    voice=voice,
                    output_filename=filename
                )
                audio_url = f"/uploads/audio/{filename}"
        except Exception as e:
            print(f"TTS error in REST API: {e}")

    return QAResponse(
        answer=answer,
        knowledge_points=extract_knowledge_points(answer),
        suggested_followups=extract_suggested_followups(answer),
        audio_url=audio_url,
        processing_time=processing_time,
        vision_supported=not fallback_used,
        fallback_used=fallback_used
    )


@router.post("/ask/text-only")
async def ask_text_only(
    query: str = Form(...),
    session_id: str = Form(...),
    conversation_history: Optional[str] = Form(None),
    enable_tts: bool = Form(True),
    voice: str = Form("af_bella"),
    db: Session = Depends(get_db)
):
    """
    纯文本问答（不包含图片）

    用于：
    - 直接文字提问
    - 图片处理失败后的回退
    """
    start_time = time.time()

    # 解析历史对话
    history = []
    if conversation_history:
        try:
            history = json.loads(conversation_history)
        except:
            pass

    # 构建消息
    messages = [{"role": "system", "content": get_active_system_prompt()}]
    for h in history[-10:]:
        messages.append(h)
    messages.append({"role": "user", "content": query})

    # 调用 Ollama
    try:
        full_answer = ""
        async for chunk in ollama_service.chat_stream(messages):
            full_answer += chunk
        answer = full_answer
    except Exception as e:
        answer = f"抱歉，AI 服务暂时不可用：{str(e)}"

    processing_time = time.time() - start_time

    # 生成 TTS
    audio_url = None
    if enable_tts and answer and not answer.startswith("抱歉"):
        try:
            clean_text = clean_text_for_tts(answer)
            if clean_text:
                filename = f"tts_{session_id}_{int(datetime.now().timestamp())}.wav"
                audio_path = await tts_service.synthesize(
                    clean_text,
                    voice=voice,
                    output_filename=filename
                )
                audio_url = f"/uploads/audio/{filename}"
        except Exception as e:
            print(f"TTS error: {e}")

    return QAResponse(
        answer=answer,
        knowledge_points=extract_knowledge_points(answer),
        suggested_followups=extract_suggested_followups(answer),
        audio_url=audio_url,
        processing_time=processing_time,
        vision_supported=False,
        fallback_used=False
    )


@router.post("/ask/json")
async def ask_question_json(request: QARequest):
    """
    JSON 格式的问答请求

    方便客户端发送 JSON 数据
    """
    start_time = time.time()

    # 构建消息
    messages = [{"role": "system", "content": get_active_system_prompt()}]
    for h in request.conversation_history[-10:]:
        messages.append(h)
    messages.append({"role": "user", "content": request.query})

    # 调用 Ollama
    try:
        full_answer = ""
        async for chunk in ollama_service.chat_stream(messages):
            full_answer += chunk
        answer = full_answer
    except Exception as e:
        answer = f"抱歉，AI 服务暂时不可用：{str(e)}"

    processing_time = time.time() - start_time

    return QAResponse(
        answer=answer,
        knowledge_points=extract_knowledge_points(answer),
        suggested_followups=extract_suggested_followups(answer),
        audio_url=None,
        processing_time=processing_time,
        vision_supported=False,
        fallback_used=False
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
    - 视觉图片处理
    - 自动 TTS 语音合成
    """
    await ws_manager.connect(session_id, websocket)
    print(f"WebSocket connected: {session_id}")

    try:
        while True:
            # 接收消息
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "connect":
                # ========== 客户端连接 ==========
                client = data.get("client", "unknown")
                version = data.get("version", "1.0")
                print(f"Client connected: {client} v{version}")
                await ws_manager.send_json(session_id, {
                    "type": "connected",
                    "status": "ok",
                    "client": client,
                    "version": version,
                    "message": "连接成功"
                })

            elif msg_type == "ask":
                # ========== 处理提问 ==========
                await ws_manager.send_json(session_id, {
                    "type": StreamMessageType.THINKING.value,
                    "status": "start",
                    "message": "正在思考..."
                })

                query = data.get("query", "")
                image_base64 = data.get("image")  # 可选的 base64 图片
                enable_tts = data.get("enable_tts", True)
                voice = data.get("voice", "af_bella")

                if not query:
                    await ws_manager.send_json(session_id, {
                        "type": StreamMessageType.ERROR.value,
                        "content": "Query is empty"
                    })
                    continue

                # 构建消息
                messages = [{"role": "system", "content": get_active_system_prompt()}]
                for h in ws_manager.get_history(session_id)[-10:]:
                    messages.append(h)

                full_answer = ""
                vision_used = False

                try:
                    # 判断使用哪种方式处理
                    if image_base64:
                        # 带图片处理（带回退）
                        full_answer, vision_used = await process_vision_request(
                            session_id, messages, image_base64, query
                        )
                    else:
                        # 纯文本处理
                        text_messages = messages.copy()
                        text_messages.append({"role": "user", "content": query})

                        async for chunk in ollama_service.chat_stream(text_messages):
                            # 检查打断
                            if ws_manager.is_interrupted(session_id):
                                await ws_manager.send_json(session_id, {
                                    "type": StreamMessageType.INTERRUPTED.value,
                                    "status": "ready",
                                    "message": "好的，请说..."
                                })
                                break
                            full_answer += chunk
                            await ws_manager.send_json(session_id, {
                                "type": StreamMessageType.PARTIAL.value,
                                "content": chunk
                            })

                except Exception as e:
                    await ws_manager.send_json(session_id, {
                        "type": StreamMessageType.ERROR.value,
                        "content": f"AI 服务错误: {str(e)}"
                    })
                    continue

                # 如果被正常打断，不保存到历史
                if ws_manager.is_interrupted(session_id):
                    ws_manager.set_interrupted(session_id, False)
                    continue

                # 保存到历史
                ws_manager.add_to_history(session_id, "user", query, {"vision_used": bool(image_base64)})
                ws_manager.add_to_history(session_id, "assistant", full_answer)

                # 发送完成消息
                await ws_manager.send_json(session_id, {
                    "type": StreamMessageType.ANSWER.value,
                    "content": full_answer,
                    "history_length": ws_manager.get_history_count(session_id),
                    "vision_used": vision_used,
                    "knowledge_points": extract_knowledge_points(full_answer),
                    "suggested_followups": extract_suggested_followups(full_answer)
                })

                # 触发 TTS（异步，不阻塞）
                if enable_tts and full_answer and not full_answer.startswith("抱歉"):
                    asyncio.create_task(trigger_tts(session_id, full_answer, voice))

            elif msg_type == "interrupt":
                # ========== 打断信号 ==========
                ws_manager.set_interrupted(session_id, True)
                await ws_manager.send_json(session_id, {
                    "type": StreamMessageType.INTERRUPTED.value,
                    "status": "acknowledged",
                    "message": "好的，请说..."
                })

            elif msg_type == "clear":
                # ========== 清空历史 ==========
                ws_manager.clear_history(session_id)
                await ws_manager.send_json(session_id, {
                    "type": StreamMessageType.CLEARED.value,
                    "status": "ok",
                    "message": "历史已清空"
                })

            elif msg_type == "speak":
                # ========== 语音播报 ==========
                text = data.get("text", "")
                voice = data.get("voice", "af_bella")
                if text:
                    asyncio.create_task(trigger_tts(session_id, text, voice))
                else:
                    await ws_manager.send_json(session_id, {
                        "type": StreamMessageType.ERROR.value,
                        "content": "Text is empty"
                    })

            elif msg_type == "stop_tts":
                # ========== 停止 TTS ==========
                await ws_manager.send_json(session_id, {
                    "type": "tts_stopped",
                    "status": "ok",
                    "message": "TTS 已停止"
                })

            elif msg_type == "get_history":
                # ========== 获取历史 ==========
                history = ws_manager.get_history(session_id)
                await ws_manager.send_json(session_id, {
                    "type": StreamMessageType.HISTORY_UPDATE.value,
                    "history": history,
                    "total_count": len(history)
                })

            elif msg_type == "set_prompt":
                # ========== 设置提示词 ==========
                prompt_name = data.get("prompt_name", "default")
                if set_active_prompt(prompt_name):
                    await ws_manager.send_json(session_id, {
                        "type": "prompt_changed",
                        "status": "ok",
                        "prompt_name": prompt_name,
                        "message": f"提示词已切换为 {SYSTEM_PROMPTS[prompt_name].description}"
                    })
                else:
                    await ws_manager.send_json(session_id, {
                        "type": StreamMessageType.ERROR.value,
                        "content": f"未知的提示词: {prompt_name}"
                    })

            elif msg_type == "ping":
                # ========== 心跳检测 ==========
                await ws_manager.send_json(session_id, {
                    "type": "pong",
                    "timestamp": datetime.now().isoformat()
                })

    except WebSocketDisconnect:
        print(f"WebSocket disconnected: {session_id}")
        ws_manager.disconnect(session_id)
    except Exception as e:
        print(f"WebSocket error: {e}")
        ws_manager.disconnect(session_id)


# ============ 提示词配置 API ============

@router.get("/prompts", response_model=SystemPromptResponse)
async def list_prompts():
    """
    获取所有提示词配置

    返回可用提示词列表和当前激活的提示词
    """
    return SystemPromptResponse(
        active_prompt=get_active_system_prompt(),
        available_prompts=list(SYSTEM_PROMPTS.values())
    )


@router.get("/prompts/{prompt_name}")
async def get_prompt(prompt_name: str):
    """
    获取指定提示词内容
    """
    if prompt_name not in SYSTEM_PROMPTS:
        raise HTTPException(status_code=404, detail="Prompt not found")
    return SYSTEM_PROMPTS[prompt_name]


@router.post("/prompts/{prompt_name}/activate")
async def activate_prompt(prompt_name: str):
    """
    激活指定提示词

    切换学习辅导的模式
    """
    if not set_active_prompt(prompt_name):
        raise HTTPException(status_code=404, detail="Prompt not found")

    prompt = SYSTEM_PROMPTS[prompt_name]
    return {
        "status": "ok",
        "prompt_name": prompt_name,
        "description": prompt.description,
        "message": f"提示词已切换为 {prompt.description}"
    }


@router.put("/prompts/{prompt_name}")
async def update_prompt(prompt_name: str, config: SystemPromptConfig):
    """
    更新提示词配置

    可以修改提示词内容或描述
    """
    if prompt_name not in SYSTEM_PROMPTS:
        raise HTTPException(status_code=404, detail="Prompt not found")

    SYSTEM_PROMPTS[prompt_name].content = config.content
    if config.description is not None:
        SYSTEM_PROMPTS[prompt_name].description = config.description

    return {
        "status": "ok",
        "prompt_name": prompt_name,
        "message": "提示词已更新"
    }


@router.post("/prompts")
async def create_prompt(config: SystemPromptConfig):
    """
    创建新提示词

    可以添加自定义的学习辅导模式
    """
    if config.name in SYSTEM_PROMPTS:
        raise HTTPException(status_code=400, detail="Prompt name already exists")

    SYSTEM_PROMPTS[config.name] = config
    return {
        "status": "created",
        "prompt_name": config.name,
        "message": f"提示词 '{config.name}' 已创建"
    }


# ============ 辅助端点 ============

@router.get("/history/{session_id}", response_model=HistoryResponse)
async def get_conversation_history(session_id: str):
    """
    获取对话历史

    返回指定 session 的完整对话历史
    """
    history = ws_manager.get_history(session_id)
    return HistoryResponse(
        session_id=session_id,
        history=[HistoryMessage(**msg) for msg in history],
        total_count=len(history),
        message_count=len(history)
    )


@router.delete("/history/{session_id}")
async def clear_conversation_history(session_id: str):
    """
    清空对话历史

    删除指定 session 的所有对话历史
    """
    ws_manager.clear_history(session_id)
    return {
        "status": "ok",
        "message": f"Session {session_id} history cleared"
    }


@router.post("/history/{session_id}/export")
async def export_conversation_history(session_id: str):
    """
    导出对话历史

    以 JSON 格式导出完整对话历史
    """
    history = ws_manager.get_history(session_id)
    return {
        "session_id": session_id,
        "exported_at": datetime.now().isoformat(),
        "history": history,
        "total_count": len(history)
    }


@router.post("/trigger")
async def trigger_qa(
    session_id: str = Form(...),
    trigger_type: str = Form("gesture"),
    image: UploadFile = File(None),
    db: Session = Depends(get_db)
):
    """
    触发问答模式

    当用户做出特定手势或说话时调用此接口
    返回提示音和确认信息
    """
    prompt_text = "请说" if trigger_type == "voice" else "请说"
    audio_url = None

    try:
        filename = f"prompt_{session_id}_{int(datetime.now().timestamp())}.wav"
        audio_path = await tts_service.synthesize(
            prompt_text,
            voice="af_bella",
            output_filename=filename
        )
        audio_url = f"/uploads/audio/{filename}"
    except Exception as e:
        print(f"TTS trigger error: {e}")

    return {
        "status": "ready",
        "trigger_type": trigger_type,
        "prompt_audio": audio_url,
        "message": "请说出您的问题"
    }


@router.post("/tts", response_model=dict)
async def synthesize_speech(
    text: str = Form(...),
    voice: str = Form("af_bella"),
    session_id: str = Form(None)
):
    """
    语音合成

    将文本转换为语音
    """
    try:
        filename = f"tts_{session_id or 'standalone'}_{int(datetime.now().timestamp())}.wav"
        audio_path = await tts_service.synthesize(
            clean_text_for_tts(text),
            voice=voice,
            output_filename=filename
        )
        return {
            "status": "success",
            "audio_url": f"/uploads/audio/{filename}"
        }
    except TTSServiceError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/tts/voices")
async def get_available_voices():
    """
    获取可用声音列表
    """
    return {
        "voices": tts_service.get_available_voices(),
        "default": "af_bella"
    }


@router.get("/capabilities/{session_id}")
async def get_session_capabilities(session_id: str):
    """
    获取会话的模型能力信息

    包括视觉支持状态等
    """
    return {
        "session_id": session_id,
        "vision_supported": ws_manager.get_model_capability(session_id),
        "history_count": ws_manager.get_history_count(session_id),
        "is_connected": session_id in ws_manager.active_connections
    }


@router.get("/health")
async def health_check():
    """
    健康检查
    """
    tts_health = await tts_service.health_check()

    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "services": {
            "tts": tts_health,
            "ollama": {
                "status": "configured",
                "base_url": settings.ollama_base_url,
                "model": settings.ollama_model
            }
        },
        "active_sessions": len(ws_manager.active_connections)
    }


# ============ 错题关联 API ============

@router.post("/analyze-mistake")
async def analyze_and_create_mistake(
    session_id: str = Form(...),
    student_id: str = Form(...),
    question_text: str = Form(...),
    student_answer: str = Form(...),
    correct_answer: str = Form(...),
    subject: str = Form(None),
    db: Session = Depends(get_db)
):
    """
    分析并创建错题记录

    从问答内容中提取错题信息并创建记录
    """
    from app.api.mistakes import MistakeCreate, create_mistake

    mistake_data = MistakeCreate(
        student_id=student_id,
        session_id=session_id,
        subject=subject,
        question_text=question_text,
        student_answer=student_answer,
        correct_answer=correct_answer,
        error_type="analysis_required",
        difficulty=0.5
    )

    try:
        result = await create_mistake(mistake_data)
        return {
            "status": "created",
            "mistake_id": result.mistake_id,
            "message": "错题已创建"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/explain-concept")
async def explain_concept(
    concept: str = Form(...),
    level: str = Form("middle_school"),
    include_examples: bool = Form(True)
):
    """
    知识点讲解

    专门用于讲解某个知识点
    """
    system_prompt = f"""你是一个专业的{level}知识讲解老师。

要求：
1. 用通俗易懂的语言解释概念
2. 从基础开始，逐步深入
3. 提供具体的例子
4. 关联相关知识点
5. 给出学习建议

回复格式：
📖 **概念定义**：
📝 **核心要点**：
💡 **理解技巧**：
📋 **相关例子**：
🔗 **关联知识**："""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"请讲解以下知识点：{concept}"}
    ]

    try:
        full_answer = ""
        async for chunk in ollama_service.chat_stream(messages):
            full_answer += chunk
        answer = full_answer
    except Exception as e:
        answer = f"抱歉，AI 服务暂时不可用：{str(e)}"

    return {
        "concept": concept,
        "level": level,
        "explanation": answer,
        "knowledge_points": extract_knowledge_points(answer)
    }