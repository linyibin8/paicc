"""
PAI-CC 会话/学习回合 API
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime, timedelta
import uuid

from app.models.database import get_db
from app.models.models import Session as SessionModel, Capture, LearningItem

router = APIRouter()


# ============ 数据模型 ============

class SessionCreate(BaseModel):
    student_id: str
    student_goal: Optional[str] = None
    assistant_focus: Optional[str] = None
    report_style: str = "normal"
    metadata: Optional[dict] = Field(default_factory=dict, description="会话元数据")


class SessionUpdate(BaseModel):
    status: Optional[str] = None
    student_goal: Optional[str] = None
    assistant_focus: Optional[str] = None
    report_style: Optional[str] = None
    metadata: Optional[dict] = None


class SessionMetadata(BaseModel):
    """会话元数据模型"""
    subject: Optional[str] = None
    chapter: Optional[str] = None
    difficulty: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    device_info: Optional[dict] = None
    location: Optional[str] = None
    notes: Optional[str] = None


class SessionHistoryEntry(BaseModel):
    """会话历史条目"""
    timestamp: datetime
    event_type: str  # capture_added, mistake_detected, goal_changed, status_changed
    description: str
    data: Optional[dict] = None


class SessionHistory(BaseModel):
    """会话历史"""
    session_id: str
    entries: List[SessionHistoryEntry]
    total_events: int


class SessionStats(BaseModel):
    """会话统计"""
    session_id: str
    duration_seconds: Optional[int]
    capture_count: int
    mistake_count: int
    learning_item_count: int
    camera_active_ratio: float
    student_attention_score: float
    completion_rate: float


class SessionResponse(BaseModel):
    session_id: str
    student_id: str
    status: str
    student_goal: Optional[str]
    assistant_focus: Optional[str]
    report_style: str
    metadata: Optional[dict]
    camera_active_time: int
    student_active_time: int
    empty_capture_time: int
    capture_count: int
    mistake_count: int
    learning_item_count: int
    report: Optional[dict]
    started_at: Optional[datetime]
    ended_at: Optional[datetime]
    created_at: datetime


def _session_to_response(session: SessionModel) -> SessionResponse:
    """将数据库模型转换为响应模型"""
    return SessionResponse(
        session_id=session.session_id,
        student_id=session.student_id,
        status=session.status,
        student_goal=session.student_goal,
        assistant_focus=session.assistant_focus,
        report_style=session.report_style,
        metadata=session.timeline if isinstance(session.timeline, dict) else None,
        camera_active_time=session.camera_active_time,
        student_active_time=session.student_active_time,
        empty_capture_time=session.empty_capture_time,
        capture_count=session.capture_count,
        mistake_count=session.mistake_count,
        learning_item_count=session.learning_item_count,
        report=session.report,
        started_at=session.started_at,
        ended_at=session.ended_at,
        created_at=session.created_at
    )


# ============ API ============

@router.post("/", response_model=SessionResponse)
async def create_session(data: SessionCreate, db: Session = Depends(get_db)):
    """创建新的学习会话"""
    session_id = f"sess_{uuid.uuid4().hex[:12]}"

    # 初始化会话历史
    initial_history = [
        {
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "session_created",
            "description": "会话已创建",
            "data": {"student_goal": data.student_goal, "report_style": data.report_style}
        }
    ]

    session = SessionModel(
        session_id=session_id,
        student_id=data.student_id,
        student_goal=data.student_goal,
        assistant_focus=data.assistant_focus,
        report_style=data.report_style,
        status="created",
        started_at=datetime.utcnow(),
        timeline=initial_history if not data.metadata else data.metadata
    )

    db.add(session)
    db.commit()
    db.refresh(session)

    return _session_to_response(session)


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str, db: Session = Depends(get_db)):
    """获取会话详情"""
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    return _session_to_response(session)


@router.put("/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: str,
    data: SessionUpdate,
    db: Session = Depends(get_db)
):
    """
    更新会话

    会自动记录历史变更
    """
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # 获取当前历史
    history = session.timeline if isinstance(session.timeline, list) else []

    if data.status:
        old_status = session.status
        session.status = data.status

        # 记录状态变更历史
        history.append({
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "status_changed",
            "description": f"状态从 {old_status} 变更为 {data.status}",
            "data": {"old_status": old_status, "new_status": data.status}
        })

        if data.status == "active":
            session.started_at = datetime.utcnow()
        elif data.status in ("completed", "failed"):
            session.ended_at = datetime.utcnow()

    if data.student_goal:
        history.append({
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "goal_changed",
            "description": f"学习目标已更新",
            "data": {"new_goal": data.student_goal}
        })
        session.student_goal = data.student_goal

    if data.assistant_focus:
        session.assistant_focus = data.assistant_focus

    if data.report_style:
        session.report_style = data.report_style

    if data.metadata:
        # 元数据更新时合并
        current_meta = session.timeline if isinstance(session.timeline, dict) else {}
        current_meta.update(data.metadata)
        session.timeline = current_meta

    # 保存历史
    session.timeline = history
    db.commit()
    db.refresh(session)

    return _session_to_response(session)


@router.post("/{session_id}/end")
async def end_session(
    session_id: str,
    report: dict = None,
    db: Session = Depends(get_db)
):
    """结束会话并生成报告"""
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    session.status = "processing"
    db.commit()

    # TODO: 触发报告生成任务
    if report:
        session.report = report

    session.status = "completed"
    session.ended_at = datetime.utcnow()
    db.commit()

    return {"status": "completed", "session_id": session_id}


@router.get("/")
async def list_sessions(
    student_id: Optional[str] = None,
    status: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    db: Session = Depends(get_db)
):
    """列出会话"""
    query = db.query(SessionModel)

    if student_id:
        query = query.filter(SessionModel.student_id == student_id)
    if status:
        query = query.filter(SessionModel.status == status)

    sessions = query.order_by(SessionModel.created_at.desc()).offset(skip).limit(limit).all()

    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "status": s.status,
                "capture_count": s.capture_count,
                "mistake_count": s.mistake_count,
                "created_at": s.created_at.isoformat() if s.created_at else None
            }
            for s in sessions
        ],
        "total": query.count()
    }


@router.delete("/{session_id}")
async def delete_session(session_id: str, db: Session = Depends(get_db)):
    """
    删除会话

    级联删除关联的 captures、learning_items、mistakes
    """
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # 获取关联数据用于清理
    captures = db.query(Capture).filter(Capture.session_id == session.id).all()

    # 清理文件（如果有本地存储）
    import os
    for capture in captures:
        if capture.image_path and os.path.exists(capture.image_path):
            try:
                os.remove(capture.image_path)
            except OSError:
                pass

    # 级联删除（依赖数据库外键级联或手动删除）
    for capture in captures:
        db.query(LearningItem).filter(LearningItem.capture_id == capture.id).delete()
        db.delete(capture)

    db.delete(session)
    db.commit()

    return {"message": "Session deleted", "session_id": session_id}


@router.get("/{session_id}/history", response_model=SessionHistory)
async def get_session_history(session_id: str, db: Session = Depends(get_db)):
    """
    获取会话历史

    返回会话的所有变更记录
    """
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    timeline = session.timeline if isinstance(session.timeline, list) else []

    entries = []
    for entry in timeline:
        entries.append(SessionHistoryEntry(
            timestamp=datetime.fromisoformat(entry["timestamp"]) if "timestamp" in entry else datetime.utcnow(),
            event_type=entry.get("event_type", "unknown"),
            description=entry.get("description", ""),
            data=entry.get("data")
        ))

    return SessionHistory(
        session_id=session_id,
        entries=entries,
        total_events=len(entries)
    )


@router.get("/{session_id}/stats", response_model=SessionStats)
async def get_session_stats(session_id: str, db: Session = Depends(get_db)):
    """
    获取会话统计信息

    计算会话的各种指标
    """
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # 计算时长
    duration_seconds = None
    if session.started_at:
        end_time = session.ended_at if session.ended_at else datetime.utcnow()
        duration_seconds = int((end_time - session.started_at).total_seconds())

    # 计算相机活跃占比
    total_time = session.camera_active_time + session.student_active_time + session.empty_capture_time
    camera_active_ratio = (session.camera_active_time / total_time * 100) if total_time > 0 else 0.0

    # 计算学生专注度分数 (基于检测到学生的次数)
    student_attention_score = min(100.0, (session.student_active_time / 60) * 10) if session.student_active_time > 0 else 0.0

    # 计算完成率
    expected_captures = session.learning_item_count + session.mistake_count
    completion_rate = (session.capture_count / expected_captures * 100) if expected_captures > 0 else 100.0

    return SessionStats(
        session_id=session_id,
        duration_seconds=duration_seconds,
        capture_count=session.capture_count,
        mistake_count=session.mistake_count,
        learning_item_count=session.learning_item_count,
        camera_active_ratio=round(camera_active_ratio, 2),
        student_attention_score=round(student_attention_score, 2),
        completion_rate=min(100.0, round(completion_rate, 2))
    )


@router.post("/{session_id}/history/entry")
async def add_history_entry(
    session_id: str,
    event_type: str = Query(..., description="事件类型"),
    description: str = Query(..., description="事件描述"),
    data: Optional[dict] = None,
    db: Session = Depends(get_db)
):
    """
    添加会话历史条目

    用于记录会话过程中的关键事件
    """
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    history = session.timeline if isinstance(session.timeline, list) else []

    history.append({
        "timestamp": datetime.utcnow().isoformat(),
        "event_type": event_type,
        "description": description,
        "data": data
    })

    session.timeline = history
    db.commit()

    return {"message": "History entry added", "total_entries": len(history)}