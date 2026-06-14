"""
PAI-CC 错题管理 API
支持错题记录、标记、编辑、统计
使用 SQLite 数据库持久化存储
"""
from fastapi import APIRouter, HTTPException, Query, Depends
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime
from sqlalchemy.orm import Session
import uuid
import math

from app.models.database import get_db, engine
from app.models.models import Base, Mistake as DBMistake, ReviewEvent as DBReviewEvent, Student as DBStudent

router = APIRouter()

# 初始化数据库表
Base.metadata.create_all(bind=engine)


class MistakeCreate(BaseModel):
    """创建错题记录"""
    student_id: str
    session_id: Optional[str] = None
    subject: Optional[str] = None
    topic: Optional[str] = None
    question_text: str
    student_answer: Optional[str] = None
    correct_answer: Optional[str] = None
    error_type: Optional[str] = None  # 计算错误、概念混淆、审题不清等
    difficulty: float = 0.5  # 0.0-1.0
    capture_ids: List[str] = []  # 关联的截图
    notes: Optional[str] = None


class MistakeUpdate(BaseModel):
    """更新错题"""
    correct_answer: Optional[str] = None
    error_type: Optional[str] = None
    difficulty: Optional[float] = None
    notes: Optional[str] = None
    status: Optional[str] = None  # suspected, confirmed, ignored, corrected, mastered


class MistakeResponse(BaseModel):
    """错题响应"""
    mistake_id: str
    student_id: str
    session_id: Optional[str]
    subject: Optional[str]
    topic: Optional[str]
    question_text: str
    student_answer: Optional[str]
    correct_answer: Optional[str]
    error_type: Optional[str]
    difficulty: float
    capture_ids: List[str]
    status: str  # suspected, confirmed, ignored, corrected, mastered
    review_count: int = 0
    last_reviewed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ReviewEventCreate(BaseModel):
    """创建复习事件"""
    result: str  # correct, wrong, delayed, mastered
    notes: Optional[str] = None
    duration: int = 0
    score: Optional[int] = None


class MistakeStats(BaseModel):
    """错题统计"""
    total: int
    by_status: dict
    by_subject: dict
    by_error_type: dict
    by_difficulty: dict
    mastered_rate: float
    avg_review_count: float


def _get_or_create_student(db: Session, student_id: str) -> DBStudent:
    """获取或创建学生记录"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        student = DBStudent(
            student_id=student_id,
            name=f"Student_{student_id[:8]}",
            grade="",
            subjects=[]
        )
        db.add(student)
        db.commit()
        db.refresh(student)
    return student


@router.post("", response_model=MistakeResponse)
async def create_mistake(data: MistakeCreate, db: Session = Depends(get_db)):
    """创建错题记录"""
    mistake_id = str(uuid.uuid4())
    now = datetime.now()

    # 获取或创建学生
    student = _get_or_create_student(db, data.student_id)

    mistake = DBMistake(
        mistake_id=mistake_id,
        student_id=student.id,
        status="suspected",
        subject=data.subject,
        question_text=data.question_text,
        student_answer=data.student_answer,
        correct_answer=data.correct_answer,
        error_reason=data.error_type,
        difficulty=data.difficulty,
        review_count=0,
        created_at=now,
        updated_at=now
    )

    db.add(mistake)
    db.commit()
    db.refresh(mistake)

    return MistakeResponse(
        mistake_id=mistake.mistake_id,
        student_id=data.student_id,
        session_id=data.session_id,
        subject=mistake.subject,
        topic=data.topic,
        question_text=mistake.question_text,
        student_answer=mistake.student_answer,
        correct_answer=mistake.correct_answer,
        error_type=mistake.error_reason,
        difficulty=mistake.difficulty,
        capture_ids=data.capture_ids,
        status=mistake.status,
        review_count=mistake.review_count,
        last_reviewed_at=mistake.next_review_at,
        created_at=mistake.created_at,
        updated_at=mistake.updated_at
    )


@router.get("/{mistake_id}", response_model=MistakeResponse)
async def get_mistake(mistake_id: str, db: Session = Depends(get_db)):
    """获取错题详情"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    student = db.query(DBStudent).filter(DBStudent.id == mistake.student_id).first()
    student_id = student.student_id if student else ""

    return MistakeResponse(
        mistake_id=mistake.mistake_id,
        student_id=student_id,
        session_id=None,
        subject=mistake.subject,
        topic=None,
        question_text=mistake.question_text,
        student_answer=mistake.student_answer,
        correct_answer=mistake.correct_answer,
        error_type=mistake.error_reason,
        difficulty=mistake.difficulty,
        capture_ids=[],
        status=mistake.status,
        review_count=mistake.review_count,
        last_reviewed_at=mistake.next_review_at,
        created_at=mistake.created_at,
        updated_at=mistake.updated_at
    )


@router.put("/{mistake_id}", response_model=MistakeResponse)
async def update_mistake(mistake_id: str, data: MistakeUpdate, db: Session = Depends(get_db)):
    """更新错题"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    # 更新字段
    if data.correct_answer is not None:
        mistake.correct_answer = data.correct_answer
    if data.error_type is not None:
        mistake.error_reason = data.error_type
    if data.difficulty is not None:
        mistake.difficulty = data.difficulty
    if data.status is not None:
        mistake.status = data.status

    mistake.updated_at = datetime.now()
    db.commit()
    db.refresh(mistake)

    student = db.query(DBStudent).filter(DBStudent.id == mistake.student_id).first()
    student_id = student.student_id if student else ""

    return MistakeResponse(
        mistake_id=mistake.mistake_id,
        student_id=student_id,
        session_id=None,
        subject=mistake.subject,
        topic=None,
        question_text=mistake.question_text,
        student_answer=mistake.student_answer,
        correct_answer=mistake.correct_answer,
        error_type=mistake.error_reason,
        difficulty=mistake.difficulty,
        capture_ids=[],
        status=mistake.status,
        review_count=mistake.review_count,
        last_reviewed_at=mistake.next_review_at,
        created_at=mistake.created_at,
        updated_at=mistake.updated_at
    )


@router.delete("/{mistake_id}")
async def delete_mistake(mistake_id: str, db: Session = Depends(get_db)):
    """删除错题"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    db.delete(mistake)
    db.commit()
    return {"status": "deleted", "mistake_id": mistake_id}


@router.get("", response_model=List[MistakeResponse])
async def list_mistakes(
    student_id: Optional[str] = None,
    session_id: Optional[str] = None,
    subject: Optional[str] = None,
    topic: Optional[str] = None,
    status: Optional[str] = None,
    error_type: Optional[str] = None,
    knowledge_point: Optional[str] = None,
    min_difficulty: Optional[float] = None,
    max_difficulty: Optional[float] = None,
    limit: int = Query(default=50, le=100),
    offset: int = 0,
    db: Session = Depends(get_db)
):
    """列出错题列表"""
    query = db.query(DBMistake)

    # 过滤
    if student_id:
        student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
        if student:
            query = query.filter(DBMistake.student_id == student.id)
        else:
            return []

    if subject:
        query = query.filter(DBMistake.subject == subject)
    if status:
        query = query.filter(DBMistake.status == status)
    if error_type:
        query = query.filter(DBMistake.error_reason == error_type)
    if min_difficulty is not None:
        query = query.filter(DBMistake.difficulty >= min_difficulty)
    if max_difficulty is not None:
        query = query.filter(DBMistake.difficulty <= max_difficulty)

    # 排序（新的在前）
    query = query.order_by(DBMistake.created_at.desc())

    # 分页
    total = query.count()
    mistakes = query.offset(offset).limit(limit).all()

    results = []
    for m in mistakes:
        student = db.query(DBStudent).filter(DBStudent.id == m.student_id).first()
        stu_id = student.student_id if student else ""
        results.append(MistakeResponse(
            mistake_id=m.mistake_id,
            student_id=stu_id,
            session_id=None,
            subject=m.subject,
            topic=None,
            question_text=m.question_text,
            student_answer=m.student_answer,
            correct_answer=m.correct_answer,
            error_type=m.error_reason,
            difficulty=m.difficulty,
            capture_ids=[],
            status=m.status,
            review_count=m.review_count,
            last_reviewed_at=m.next_review_at,
            created_at=m.created_at,
            updated_at=m.updated_at
        ))

    return results


@router.post("/{mistake_id}/review")
async def record_review(mistake_id: str, db: Session = Depends(get_db)):
    """记录一次复习"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake.review_count += 1
    mistake.next_review_at = datetime.now()
    mistake.updated_at = datetime.now()
    db.commit()

    return {
        "status": "ok",
        "mistake_id": mistake_id,
        "review_count": mistake.review_count
    }


@router.put("/{mistake_id}/master")
async def mark_mastered(mistake_id: str, db: Session = Depends(get_db)):
    """标记为已掌握"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake.status = "mastered"
    mistake.updated_at = datetime.now()
    db.commit()

    return {"status": "ok", "mistake_id": mistake_id}


@router.post("/{mistake_id}/review-events")
async def create_review_event(mistake_id: str, data: ReviewEventCreate, db: Session = Depends(get_db)):
    """创建复习事件"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    event_id = str(uuid.uuid4())
    event = DBReviewEvent(
        event_id=event_id,
        mistake_id=mistake.id,
        student_id=mistake.student_id,
        result=data.result,
        notes=data.notes,
        time_spent=data.duration,
        score=data.score,
        created_at=datetime.now()
    )

    db.add(event)
    mistake.review_count += 1
    mistake.updated_at = datetime.now()

    # 更新状态
    if data.result == "mastered":
        mistake.status = "mastered"

    db.commit()
    db.refresh(event)

    return {
        "status": "ok",
        "event": {
            "event_id": event.event_id,
            "result": event.result,
            "created_at": event.created_at.isoformat()
        }
    }


@router.get("/{mistake_id}/review-events")
async def list_review_events(mistake_id: str, db: Session = Depends(get_db)):
    """获取复习历史"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    events = db.query(DBReviewEvent).filter(DBReviewEvent.mistake_id == mistake.id).all()

    return {
        "events": [
            {
                "event_id": e.event_id,
                "result": e.result,
                "notes": e.notes,
                "time_spent": e.time_spent,
                "score": e.score,
                "created_at": e.created_at.isoformat()
            }
            for e in events
        ],
        "count": len(events)
    }


@router.get("/stats/summary", response_model=MistakeStats)
async def get_mistake_stats(student_id: Optional[str] = None, db: Session = Depends(get_db)):
    """获取错题统计"""
    query = db.query(DBMistake)

    if student_id:
        student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
        if student:
            query = query.filter(DBMistake.student_id == student.id)
        else:
            return MistakeStats(
                total=0,
                by_status={},
                by_subject={},
                by_error_type={},
                by_difficulty={},
                mastered_rate=0.0,
                avg_review_count=0.0
            )

    mistakes = query.all()
    total = len(mistakes)

    if not mistakes:
        return MistakeStats(
            total=0,
            by_status={},
            by_subject={},
            by_error_type={},
            by_difficulty={},
            mastered_rate=0.0,
            avg_review_count=0.0
        )

    # 统计
    by_status = {}
    by_subject = {}
    by_error_type = {}
    by_difficulty = {}
    total_review = 0
    mastered_count = 0

    for m in mistakes:
        # by status
        status = m.status
        by_status[status] = by_status.get(status, 0) + 1

        # by subject
        subject = m.subject or "unknown"
        by_subject[subject] = by_subject.get(subject, 0) + 1

        # by error type
        error_type = m.error_reason or "unknown"
        by_error_type[error_type] = by_error_type.get(error_type, 0) + 1

        # by difficulty
        difficulty = m.difficulty or 0.5
        diff_bucket = f"{int(difficulty * 10) / 10:.1f}-{int(difficulty * 10) / 10 + 0.1:.1f}"
        by_difficulty[diff_bucket] = by_difficulty.get(diff_bucket, 0) + 1

        total_review += m.review_count or 0
        if m.status == "mastered":
            mastered_count += 1

    mastered_rate = mastered_count / total if total > 0 else 0.0
    avg_review = total_review / total if total > 0 else 0.0

    return MistakeStats(
        total=total,
        by_status=by_status,
        by_subject=by_subject,
        by_error_type=by_error_type,
        by_difficulty=by_difficulty,
        mastered_rate=round(mastered_rate, 2),
        avg_review_count=round(avg_review, 1)
    )


@router.post("/batch")
async def batch_create_mistakes(mistakes: List[MistakeCreate], db: Session = Depends(get_db)):
    """批量创建错题"""
    results = []

    for data in mistakes:
        mistake_id = str(uuid.uuid4())
        now = datetime.now()

        # 获取或创建学生
        student = _get_or_create_student(db, data.student_id)

        mistake = DBMistake(
            mistake_id=mistake_id,
            student_id=student.id,
            status="suspected",
            subject=data.subject,
            question_text=data.question_text,
            student_answer=data.student_answer,
            correct_answer=data.correct_answer,
            error_reason=data.error_type,
            difficulty=data.difficulty,
            review_count=0,
            created_at=now,
            updated_at=now
        )

        db.add(mistake)
        results.append(mistake_id)

    db.commit()

    return {"created": len(results), "mistake_ids": results}
