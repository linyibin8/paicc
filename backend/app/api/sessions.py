"""
PAI-CC 会话管理 API
"""
from fastapi import APIRouter, HTTPException
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime
import uuid

router = APIRouter()


class SessionCreate(BaseModel):
    """创建会话"""
    student_id: Optional[str] = None
    student_goal: Optional[str] = None
    assistant_focus: Optional[str] = None
    report_style: str = "detailed"


class SessionResponse(BaseModel):
    """会话响应"""
    session_id: str
    status: str
    created_at: datetime
    student_id: Optional[str] = None
    total_captures: int = 0


class SessionReport(BaseModel):
    """会话报告"""
    session_id: str
    generated_at: datetime
    timeline: dict
    summary: dict
    learning_content: dict
    knowledge_points: List[str] = []
    mistake_summary: dict
    recommendations: dict


# 内存存储（实际生产环境应使用数据库）
_sessions = {}


@router.post("", response_model=SessionResponse)
async def create_session(data: SessionCreate):
    """创建学习回合"""
    session_id = str(uuid.uuid4())

    session = {
        "session_id": session_id,
        "status": "created",
        "created_at": datetime.now(),
        "student_id": data.student_id,
        "student_goal": data.student_goal,
        "assistant_focus": data.assistant_focus,
        "report_style": data.report_style,
        "total_captures": 0
    }

    _sessions[session_id] = session

    return SessionResponse(
        session_id=session_id,
        status="created",
        created_at=session["created_at"],
        student_id=data.student_id,
        total_captures=0
    )


@router.get("/{session_id}")
async def get_session(session_id: str):
    """获取会话详情"""
    if session_id not in _sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    return _sessions[session_id]


@router.put("/{session_id}/status")
async def update_session_status(session_id: str, status: str):
    """更新会话状态"""
    if session_id not in _sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    valid_statuses = ["created", "active", "processing", "completed", "failed"]
    if status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of {valid_statuses}")

    _sessions[session_id]["status"] = status
    return {"status": "ok", "session_id": session_id, "new_status": status}


@router.get("/{session_id}/report", response_model=SessionReport)
async def get_session_report(session_id: str):
    """获取会话报告"""
    if session_id not in _sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    # 生成报告（实际应调用 AI 服务）
    return SessionReport(
        session_id=session_id,
        generated_at=datetime.now(),
        timeline={
            "total_duration": 1800,
            "observation_time": 1700,
            "student_active_time": 1500,
            "empty_capture_time": 200
        },
        summary={
            "total_captures": 25,
            "key_frames": 15,
            "learning_materials": 10,
            "estimated_questions": 5
        },
        learning_content={
            "questions": [],
            "answers": [],
            "student_work": [],
            "corrections": []
        },
        knowledge_points=["一元二次方程", "函数图像"],
        mistake_summary={
            "candidates": [],
            "confirmed": 0,
            "ignored": 0
        },
        recommendations={
            "review_needed": [],
            "practice_needed": [],
            "mastered": []
        }
    )


@router.get("")
async def list_sessions(
    student_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0
):
    """列出所有会话"""
    results = list(_sessions.values())

    if student_id:
        results = [s for s in results if s.get("student_id") == student_id]

    if status:
        results = [s for s in results if s.get("status") == status]

    total = len(results)
    results = results[offset:offset + limit]

    return {
        "sessions": results,
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.delete("/{session_id}")
async def delete_session(session_id: str):
    """删除会话"""
    if session_id in _sessions:
        del _sessions[session_id]
        return {"status": "deleted", "session_id": session_id}

    raise HTTPException(status_code=404, detail="Session not found")