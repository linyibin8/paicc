"""
PAI-CC 复习队列 API
基于间隔重复算法 (Spaced Repetition) 管理复习任务
"""
from fastapi import APIRouter, HTTPException, Query
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta
import uuid
import math

router = APIRouter()


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


# 内存存储
_review_queue = {}
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


# 初始化队列
_initialized_subjects = set()


def init_queue_for_mistakes(student_id: str, subject: str, difficulty: float):
    """为错题初始化复习队列"""
    if (student_id, subject) in _initialized_subjects:
        return []

    _initialized_subjects.add((student_id, subject))
    return []


@router.post("/add")
async def add_to_queue(
    student_id: str,
    mistake_id: str,
    question_text: str,
    correct_answer: Optional[str] = None,
    difficulty: float = 0.5,
    due_date: Optional[datetime] = None
):
    """添加复习项到队列"""
    queue_id = str(uuid.uuid4())
    now = datetime.now()

    item = {
        "queue_id": queue_id,
        "student_id": student_id,
        "mistake_id": mistake_id,
        "question_text": question_text,
        "correct_answer": correct_answer,
        "difficulty": difficulty,
        "ease_factor": 2.5,
        "interval": 1,
        "repetitions": 0,
        "due_date": due_date or now,
        "last_reviewed_at": None,
        "created_at": now
    }

    _review_queue[queue_id] = item
    return {"status": "added", "queue_id": queue_id}


@router.get("/due")
async def get_due_items(
    student_id: str,
    subject: Optional[str] = None,
    limit: int = Query(default=20, le=50)
):
    """获取待复习项"""
    now = datetime.now()
    results = []

    for item in _review_queue.values():
        if item["student_id"] != student_id:
            continue
        if item["due_date"] > now:
            continue
        if subject and item.get("subject") != subject:
            continue
        results.append(item)

    # 按到期时间排序
    results.sort(key=lambda x: x["due_date"])

    return {
        "items": results[:limit],
        "total": len(results),
        "due_now": len(results)
    }


@router.post("/{queue_id}/review", response_model=ReviewResponse)
async def submit_review(queue_id: str, data: ReviewRequest):
    """提交复习评分"""
    if queue_id not in _review_queue:
        raise HTTPException(status_code=404, detail="Review item not found")

    item = _review_queue[queue_id]

    # 验证评分
    if data.quality < 0 or data.quality > 5:
        raise HTTPException(status_code=400, detail="Quality must be 0-5")

    # SM-2 算法
    new_reps, new_ef, new_interval = calculate_sm2(
        data.quality,
        item["repetitions"],
        item["ease_factor"],
        item["interval"]
    )

    # 更新项
    now = datetime.now()
    item["repetitions"] = new_reps
    item["ease_factor"] = new_ef
    item["interval"] = new_interval
    item["due_date"] = now + timedelta(days=new_interval)
    item["last_reviewed_at"] = now

    # 是否已掌握（间隔超过30天且评分>=4）
    is_mastered = new_interval >= 30 and data.quality >= 4

    return ReviewResponse(
        queue_id=queue_id,
        next_review_date=item["due_date"],
        new_interval=new_interval,
        new_ease_factor=round(new_ef, 2),
        is_mastered=is_mastered
    )


@router.get("/{queue_id}")
async def get_queue_item(queue_id: str):
    """获取复习项详情"""
    if queue_id not in _review_queue:
        raise HTTPException(status_code=404, detail="Review item not found")
    return _review_queue[queue_id]


@router.delete("/{queue_id}")
async def remove_from_queue(queue_id: str):
    """从队列中移除"""
    if queue_id not in _review_queue:
        raise HTTPException(status_code=404, detail="Review item not found")

    del _review_queue[queue_id]
    return {"status": "removed", "queue_id": queue_id}


@router.get("/stats/{student_id}", response_model=QueueStats)
async def get_queue_stats(student_id: str):
    """获取队列统计"""
    items = [item for item in _review_queue.values() if item["student_id"] == student_id]

    now = datetime.now()
    week_later = now + timedelta(days=7)

    total = len(items)
    due_today = 0
    due_this_week = 0
    overdue = 0
    mastered = 0
    total_ef = 0.0
    by_subject = {}

    for item in items:
        due = item["due_date"]

        if due <= now:
            if (now - due).total_seconds() > 86400:  # 超过1天
                overdue += 1
            else:
                due_today += 1
        elif due <= week_later:
            due_this_week += 1

        if item["interval"] >= 30:
            mastered += 1

        total_ef += item.get("ease_factor", 2.5)

        subject = item.get("subject", "unknown")
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
    offset: int = 0
):
    """列出队列项"""
    now = datetime.now()
    week_later = now + timedelta(days=7)
    results = []

    for item in _review_queue.values():
        if item["student_id"] != student_id:
            continue
        if subject and item.get("subject") != subject:
            continue

        if status == "due":
            if item["due_date"] > now:
                continue
        elif status == "upcoming":
            if item["due_date"] <= now:
                continue
        elif status == "mastered":
            if item["interval"] < 30:
                continue

        results.append(item)

    # 排序
    results.sort(key=lambda x: x["due_date"])

    total = len(results)
    results = results[offset:offset + limit]

    return {
        "items": results,
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.post("/sync")
async def sync_from_mistakes(student_id: str, subject: Optional[str] = None):
    """从错题库同步复习队列"""
    from app.api.mistakes import _mistakes

    added = 0
    now = datetime.now()

    for mistake in _mistakes.values():
        if mistake["student_id"] != student_id:
            continue
        if subject and mistake.get("subject") != subject:
            continue
        if mistake["status"] == "mastered":
            continue

        # 检查是否已在队列
        exists = False
        for item in _review_queue.values():
            if item["mistake_id"] == mistake["mistake_id"]:
                exists = True
                break

        if not exists:
            queue_id = str(uuid.uuid4())
            item = {
                "queue_id": queue_id,
                "student_id": student_id,
                "mistake_id": mistake["mistake_id"],
                "question_text": mistake["question_text"],
                "correct_answer": mistake.get("correct_answer"),
                "difficulty": mistake.get("difficulty", 0.5),
                "ease_factor": 2.5,
                "interval": 1,
                "repetitions": 0,
                "due_date": now,
                "last_reviewed_at": None,
                "created_at": now,
                "subject": mistake.get("subject"),
                "error_type": mistake.get("error_type")
            }
            _review_queue[queue_id] = item
            added += 1

    return {
        "status": "synced",
        "added": added,
        "total_in_queue": len([i for i in _review_queue.values() if i["student_id"] == student_id])
    }
