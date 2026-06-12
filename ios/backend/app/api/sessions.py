"""
PAI-CC 会话/学习回合 API
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid

from app.models.database import get_db
from app.models.models import Session as SessionModel

router = APIRouter()


# ============ 数据模型 ============

class SessionCreate(BaseModel):
    student_id: str
    student_goal: Optional[str] = None
    assistant_focus: Optional[str] = None
    report_style: str = "normal"


class SessionUpdate(BaseModel):
    status: Optional[str] = None
    student_goal: Optional[str] = None
    assistant_focus: Optional[str] = None
    report_style: Optional[str] = None


class SessionResponse(BaseModel):
    session_id: str
    student_id: str
    status: str
    student_goal: Optional[str]
    assistant_focus: Optional[str]
    report_style: str
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


# ============ API ============

@router.post("/", response_model=SessionResponse)
async def create_session(data: SessionCreate, db: Session = Depends(get_db)):
    """创建新的学习会话"""
    session_id = f"sess_{uuid.uuid4().hex[:12]}"

    session = SessionModel(
        session_id=session_id,
        student_id=data.student_id,
        student_goal=data.student_goal,
        assistant_focus=data.assistant_focus,
        report_style=data.report_style,
        status="created",
        started_at=datetime.utcnow()
    )

    db.add(session)
    db.commit()
    db.refresh(session)

    return SessionResponse(**{
        "session_id": session.session_id,
        "student_id": session.student_id,
        "status": session.status,
        "student_goal": session.student_goal,
        "assistant_focus": session.assistant_focus,
        "report_style": session.report_style,
        "camera_active_time": session.camera_active_time,
        "student_active_time": session.student_active_time,
        "empty_capture_time": session.empty_capture_time,
        "capture_count": session.capture_count,
        "mistake_count": session.mistake_count,
        "learning_item_count": session.learning_item_count,
        "report": session.report,
        "started_at": session.started_at,
        "ended_at": session.ended_at,
        "created_at": session.created_at
    })


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str, db: Session = Depends(get_db)):
    """获取会话详情"""
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    return SessionResponse(**{
        "session_id": session.session_id,
        "student_id": session.student_id,
        "status": session.status,
        "student_goal": session.student_goal,
        "assistant_focus": session.assistant_focus,
        "report_style": session.report_style,
        "camera_active_time": session.camera_active_time,
        "student_active_time": session.student_active_time,
        "empty_capture_time": session.empty_capture_time,
        "capture_count": session.capture_count,
        "mistake_count": session.mistake_count,
        "learning_item_count": session.learning_item_count,
        "report": session.report,
        "started_at": session.started_at,
        "ended_at": session.ended_at,
        "created_at": session.created_at
    })


@router.patch("/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: str,
    data: SessionUpdate,
    db: Session = Depends(get_db)
):
    """更新会话"""
    session = db.query(SessionModel).filter(
        SessionModel.session_id == session_id
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if data.status:
        session.status = data.status
        if data.status == "active":
            session.started_at = datetime.utcnow()
        elif data.status in ("completed", "failed"):
            session.ended_at = datetime.utcnow()

    if data.student_goal:
        session.student_goal = data.student_goal
    if data.assistant_focus:
        session.assistant_focus = data.assistant_focus
    if data.report_style:
        session.report_style = data.report_style

    db.commit()
    db.refresh(session)

    return SessionResponse(**{
        "session_id": session.session_id,
        "student_id": session.student_id,
        "status": session.status,
        "student_goal": session.student_goal,
        "assistant_focus": session.assistant_focus,
        "report_style": session.report_style,
        "camera_active_time": session.camera_active_time,
        "student_active_time": session.student_active_time,
        "empty_capture_time": session.empty_capture_time,
        "capture_count": session.capture_count,
        "mistake_count": session.mistake_count,
        "learning_item_count": session.learning_item_count,
        "report": session.report,
        "started_at": session.started_at,
        "ended_at": session.ended_at,
        "created_at": session.created_at
    })


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