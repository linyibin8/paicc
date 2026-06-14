"""
PAI-CC 复习队列 API
基于间隔重复算法 (Spaced Repetition) 管理复习任务
使用 SQLite 数据库持久化存储
"""
from fastapi import APIRouter, HTTPException, Query, Form, Depends
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
import uuid
import math

from app.models.database import get_db, engine
from app.models.models import Base, Mistake as DBMistake, Student as DBStudent

router = APIRouter()

# 初始化数据库表
Base.metadata.create_all(bind=engine)


class ReviewQueueItem(BaseModel):
    """复习队列项"""
    queue_id: str
    student_id: str
    mistake_id: str
    question_text: str
    correct_answer: Optional[str] = None
    difficulty: float
    ease_factor: float = 2.5  # 间隔重复参数
    interval: int = 1  # 当前间隔天数
    repetitions: int = 0  # 已复习次数
    due_date: datetime
    last_reviewed_at: Optional[datetime] = None
    created_at: datetime


class ReviewRequest(BaseModel):
    """复习请求"""
    quality: int  # 0-5 评分: 0=完全遗忘, 5=完美掌握


class ReviewResponse(BaseModel):
    """复习响应"""
    queue_id: str
    next_review_date: datetime
    new_interval: int
    new_ease_factor: float
    is_mastered: bool


class QueueStats(BaseModel):
    """队列统计"""
    total_items: int
    due_today: int
    due_this_week: int
    overdue: int
    mastered: int
    avg_ease_factor: float
    by_subject: dict


# SM-2 算法最小和最大间隔
MIN_INTERVAL = 1
MAX_INTERVAL = 365


def calculate_sm2(quality: int, repetitions: int, ease_factor: float, interval: int):
    """
    SM-2 间隔重复算法

    参数:
    - quality: 0-5 评分
    - repetitions: 已复习次数
    - ease_factor: 难度因子 (默认2.5)
    - interval: 当前间隔天数

    返回:
    - new_repetitions, new_ease_factor, new_interval
    """
    # 更新难度因子
    new_ef = ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    new_ef = max(1.3, new_ef)  # 最低1.3

    # 计算新间隔
    if quality < 3:
        # 复习失败，重置
        new_repetitions = 0
        new_interval = 1
    else:
        new_repetitions = repetitions + 1
        if new_repetitions == 1:
            new_interval = 1
        elif new_repetitions == 2:
            new_interval = 6
        else:
            new_interval = math.floor(interval * new_ef)

    # 限制最大间隔
    new_interval = min(new_interval, MAX_INTERVAL)
    new_interval = max(new_interval, MIN_INTERVAL)

    return new_repetitions, new_ef, new_interval


@router.post("/add")
async def add_to_queue(
    student_id: str = Form(...),
    mistake_id: str = Form(...),
    question_text: str = Form(...),
    correct_answer: Optional[str] = Form(None),
    difficulty: float = Form(0.5),
    due_date: Optional[datetime] = Form(None),
    db: Session = Depends(get_db)
):
    """添加复习项到队列（存储在错题的 next_review_at 字段）"""
    now = datetime.now()

    # 查找错题记录
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == mistake_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Mistake not found")

    # 更新错题的复习信息
    mistake.next_review_at = due_date or now
    mistake.review_status = "queued"
    db.commit()

    # 返回队列ID（使用错题ID作为队列ID）
    return {"status": "added", "queue_id": mistake_id, "due_date": mistake.next_review_at}


@router.get("/due")
async def get_due_items(
    student_id: str,
    subject: Optional[str] = None,
    limit: int = Query(default=20, le=50),
    db: Session = Depends(get_db)
):
    """获取待复习项"""
    now = datetime.now()

    # 查找学生
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return {"items": [], "total": 0, "due_now": 0}

    # 查询需要复习的错题
    query = db.query(DBMistake).filter(
        DBStudent.id == student.id,
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBStudent.id == DBStudent.id
    ).filter(
        DBStudent.id == DBStudent.id
    )

    # 获取学生的所有错题
    query = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id
    ).filter(
        DBMistake.student_id == student.id,
        DBMistake.review_status == "queued"
    )

    # 简单查询：获取该学生的待复习错题
    query = db.query(DBMistake).filter(
        DBMistake.student_id == student.id,
        DBMistake.review_status == "queued",
        DBMistake.status != "mastered"
    )

    if subject:
        query = query.filter(DBMistake.subject == subject)

    mistakes = query.all()
    results = []

    for m in mistakes:
        due = m.next_review_at or m.created_at
        if due <= now:
            results.append({
                "queue_id": m.mistake_id,
                "student_id": student_id,
                "mistake_id": m.mistake_id,
                "question_text": m.question_text,
                "correct_answer": m.correct_answer,
                "difficulty": m.difficulty or 0.5,
                "ease_factor": 2.5,
                "interval": 1,
                "repetitions": 0,
                "due_date": due,
                "last_reviewed_at": None,
                "created_at": m.created_at
            })

    # 按到期时间排序
    results.sort(key=lambda x: x["due_date"])

    return {
        "items": results[:limit],
        "total": len(results),
        "due_now": len(results)
    }


@router.post("/{queue_id}/review", response_model=ReviewResponse)
async def submit_review(queue_id: str, data: ReviewRequest, db: Session = Depends(get_db)):
    """提交复习评分"""
    # queue_id 就是 mistake_id
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == queue_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Review item not found")

    # 验证评分
    if data.quality < 0 or data.quality > 5:
        raise HTTPException(status_code=400, detail="Quality must be 0-5")

    # 获取当前复习参数
    repetitions = 0  # 从错题记录中获取
    ease_factor = 2.5
    interval = 1

    # SM-2 算法
    new_reps, new_ef, new_interval = calculate_sm2(
        data.quality,
        repetitions,
        ease_factor,
        interval
    )

    # 更新错题
    now = datetime.now()
    mistake.review_status = "in_review"
    mistake.review_count = (mistake.review_count or 0) + 1
    mistake.next_review_at = now + timedelta(days=new_interval)
    mistake.updated_at = now

    # 是否已掌握（间隔超过30天且评分>=4）
    is_mastered = new_interval >= 30 and data.quality >= 4
    if is_mastered:
        mistake.status = "mastered"
        mistake.review_status = "mastered"

    db.commit()

    return ReviewResponse(
        queue_id=queue_id,
        next_review_date=mistake.next_review_at,
        new_interval=new_interval,
        new_ease_factor=round(new_ef, 2),
        is_mastered=is_mastered
    )


@router.get("/{queue_id}")
async def get_queue_item(queue_id: str, db: Session = Depends(get_db)):
    """获取复习项详情"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == queue_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Review item not found")

    student = db.query(DBStudent).filter(DBStudent.id == mistake.student_id).first()
    student_id = student.student_id if student else ""

    return {
        "queue_id": mistake.mistake_id,
        "student_id": student_id,
        "mistake_id": mistake.mistake_id,
        "question_text": mistake.question_text,
        "correct_answer": mistake.correct_answer,
        "difficulty": mistake.difficulty or 0.5,
        "subject": mistake.subject,
        "status": mistake.review_status,
        "due_date": mistake.next_review_at,
        "created_at": mistake.created_at
    }


@router.delete("/{queue_id}")
async def remove_from_queue(queue_id: str, db: Session = Depends(get_db)):
    """从队列中移除"""
    mistake = db.query(DBMistake).filter(DBMistake.mistake_id == queue_id).first()
    if not mistake:
        raise HTTPException(status_code=404, detail="Review item not found")

    mistake.review_status = "removed"
    db.commit()

    return {"status": "removed", "queue_id": queue_id}


@router.get("/stats/{student_id}", response_model=QueueStats)
async def get_queue_stats(student_id: str, db: Session = Depends(get_db)):
    """获取队列统计"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return QueueStats(
            total_items=0,
            due_today=0,
            due_this_week=0,
            overdue=0,
            mastered=0,
            avg_ease_factor=2.5,
            by_subject={}
        )

    now = datetime.now()
    week_later = now + timedelta(days=7)

    # 获取该学生的错题
    mistakes = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBMistake.student_id == student.id
    ).all()

    total = len(mistakes)
    due_today = 0
    due_this_week = 0
    overdue = 0
    mastered = 0
    total_ef = 0.0
    by_subject = {}

    for m in mistakes:
        due = m.next_review_at or m.created_at

        if due <= now:
            if (now - due).total_seconds() > 86400:  # 超过1天
                overdue += 1
            else:
                due_today += 1
        elif due <= week_later:
            due_this_week += 1

        if m.status == "mastered":
            mastered += 1

        total_ef += 2.5  # 默认难度因子

        subject = m.subject or "unknown"
        by_subject[subject] = by_subject.get(subject, 0) + 1

    avg_ef = total_ef / total if total > 0 else 2.5

    return QueueStats(
        total_items=total,
        due_today=due_today,
        due_this_week=due_this_week,
        overdue=overdue,
        mastered=mastered,
        avg_ease_factor=round(avg_ef, 2),
        by_subject=by_subject
    )


@router.get("")
async def list_queue(
    student_id: str,
    status: Optional[str] = None,  # due, upcoming, mastered
    subject: Optional[str] = None,
    limit: int = Query(default=50, le=100),
    offset: int = 0,
    db: Session = Depends(get_db)
):
    """列出队列项"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return {"items": [], "total": 0, "limit": limit, "offset": offset}

    now = datetime.now()
    week_later = now + timedelta(days=7)

    query = db.query(DBMistake).filter(
        DBMistake.student_id == student.id
    )

    if subject:
        query = query.filter(DBMistake.subject == subject)

    if status == "due":
        query = query.filter(DBMistake.review_status == "queued")
        query = query.filter(DBMistake.next_review_at <= now)
    elif status == "upcoming":
        query = query.filter(DBMistake.review_status == "queued")
        query = query.filter(DBMistake.next_review_at > now)
    elif status == "mastered":
        query = query.filter(DBMistake.status == "mastered")

    # 排序
    query = query.order_by(DBMistake.next_review_at.asc())

    total = query.count()
    mistakes = query.offset(offset).limit(limit).all()

    results = []
    for m in mistakes:
        results.append({
            "queue_id": m.mistake_id,
            "student_id": student_id,
            "mistake_id": m.mistake_id,
            "question_text": m.question_text,
            "correct_answer": m.correct_answer,
            "difficulty": m.difficulty or 0.5,
            "due_date": m.next_review_at,
            "status": m.review_status,
            "created_at": m.created_at
        })

    return {
        "items": results,
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.post("/sync")
async def sync_from_mistakes(student_id: str, subject: Optional[str] = None, db: Session = Depends(get_db)):
    """从错题库同步复习队列"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return {"status": "synced", "added": 0, "total_in_queue": 0}

    query = db.query(DBMistake).filter(
        DBMistake.student_id == student.id,
        DBMistake.status != "mastered"
    )

    if subject:
        query = query.filter(DBMistake.subject == subject)

    mistakes = query.all()
    added = 0
    now = datetime.now()

    for m in mistakes:
        if m.review_status != "queued":
            m.review_status = "queued"
            if not m.next_review_at:
                m.next_review_at = now
            added += 1

    if added > 0:
        db.commit()

    total_in_queue = db.query(DBMistake).filter(
        DBMistake.student_id == student.id,
        DBMistake.review_status == "queued"
    ).count()

    return {
        "status": "synced",
        "added": added,
        "total_in_queue": total_in_queue
    }