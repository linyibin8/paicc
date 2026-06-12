"""
PAI-CC 错题管理 API
支持错题记录、标记、编辑、统计
"""
from fastapi import APIRouter, HTTPException, Query
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime
import uuid

router = APIRouter()


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
    status: Optional[str] = None  # new, reviewing, mastered


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
    status: str  # new, reviewing, mastered
    review_count: int = 0
    last_reviewed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


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


# 内存存储
_mistakes = {}


@router.post("", response_model=MistakeResponse)
async def create_mistake(data: MistakeCreate):
    """创建错题记录"""
    mistake_id = str(uuid.uuid4())
    now = datetime.now()

    mistake = {
        "mistake_id": mistake_id,
        "student_id": data.student_id,
        "session_id": data.session_id,
        "subject": data.subject,
        "topic": data.topic,
        "question_text": data.question_text,
        "student_answer": data.student_answer,
        "correct_answer": data.correct_answer,
        "error_type": data.error_type,
        "difficulty": data.difficulty,
        "capture_ids": data.capture_ids,
        "status": "new",
        "review_count": 0,
        "last_reviewed_at": None,
        "created_at": now,
        "updated_at": now,
        "review_events": []
    }

    _mistakes[mistake_id] = mistake
    return MistakeResponse(**{k: v for k, v in mistake.items() if k != "review_events"})


@router.get("/{mistake_id}", response_model=MistakeResponse)
async def get_mistake(mistake_id: str):
    """获取错题详情"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake = _mistakes[mistake_id]
    return MistakeResponse(**{k: v for k, v in mistake.items() if k != "review_events"})


@router.put("/{mistake_id}", response_model=MistakeResponse)
async def update_mistake(mistake_id: str, data: MistakeUpdate):
    """更新错题"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake = _mistakes[mistake_id]

    # 更新字段
    if data.correct_answer is not None:
        mistake["correct_answer"] = data.correct_answer
    if data.error_type is not None:
        mistake["error_type"] = data.error_type
    if data.difficulty is not None:
        mistake["difficulty"] = data.difficulty
    if data.notes is not None:
        mistake["notes"] = data.notes
    if data.status is not None:
        mistake["status"] = data.status

    mistake["updated_at"] = datetime.now()
    return MistakeResponse(**{k: v for k, v in mistake.items() if k != "review_events"})


@router.delete("/{mistake_id}")
async def delete_mistake(mistake_id: str):
    """删除错题"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    del _mistakes[mistake_id]
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
    offset: int = 0
):
    """列出错题列表"""
    results = list(_mistakes.values())

    # 过滤
    if student_id:
        results = [m for m in results if m["student_id"] == student_id]
    if session_id:
        results = [m for m in results if m.get("session_id") == session_id]
    if subject:
        results = [m for m in results if m.get("subject") == subject]
    if topic:
        results = [m for m in results if m.get("topic") == topic]
    if status:
        results = [m for m in results if m["status"] == status]
    if error_type:
        results = [m for m in results if m.get("error_type") == error_type]
    if knowledge_point:
        results = [m for m in results if knowledge_point in m.get("capture_ids", [])]
    if min_difficulty is not None:
        results = [m for m in results if m.get("difficulty", 0) >= min_difficulty]
    if max_difficulty is not None:
        results = [m for m in results if m.get("difficulty", 1) <= max_difficulty]

    # 排序（新的在前）
    results.sort(key=lambda x: x["created_at"], reverse=True)

    total = len(results)
    results = results[offset:offset + limit]

    return [MistakeResponse(**{k: v for k, v in m.items() if k != "review_events"}) for m in results]


@router.post("/{mistake_id}/review")
async def record_review(mistake_id: str):
    """记录一次复习"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake = _mistakes[mistake_id]
    mistake["review_count"] += 1
    mistake["last_reviewed_at"] = datetime.now()
    mistake["updated_at"] = datetime.now()

    return {
        "status": "ok",
        "mistake_id": mistake_id,
        "review_count": mistake["review_count"]
    }


@router.put("/{mistake_id}/master")
async def mark_mastered(mistake_id: str):
    """标记为已掌握"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    mistake = _mistakes[mistake_id]
    mistake["status"] = "mastered"
    mistake["updated_at"] = datetime.now()

    return {"status": "ok", "mistake_id": mistake_id}


@router.post("/{mistake_id}/review-events")
async def create_review_event(mistake_id: str, data: ReviewEventCreate):
    """创建复习事件"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    event_id = str(uuid.uuid4())
    event = {
        "event_id": event_id,
        "result": data.result,
        "notes": data.notes,
        "duration": data.duration,
        "score": data.score,
        "created_at": datetime.now().isoformat()
    }

    _mistakes[mistake_id]["review_events"].append(event)
    _mistakes[mistake_id]["review_count"] += 1
    _mistakes[mistake_id]["updated_at"] = datetime.now()

    # 更新状态
    if data.result == "mastered":
        _mistakes[mistake_id]["status"] = "mastered"

    return {"status": "ok", "event": event}


@router.get("/{mistake_id}/review-events")
async def list_review_events(mistake_id: str):
    """获取复习历史"""
    if mistake_id not in _mistakes:
        raise HTTPException(status_code=404, detail="Mistake not found")

    return {
        "events": _mistakes[mistake_id]["review_events"],
        "count": len(_mistakes[mistake_id]["review_events"])
    }


@router.get("/stats/summary", response_model=MistakeStats)
async def get_mistake_stats(student_id: Optional[str] = None):
    """获取错题统计"""
    results = list(_mistakes.values())

    if student_id:
        results = [m for m in results if m["student_id"] == student_id]

    if not results:
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
    total = len(results)
    by_status = {}
    by_subject = {}
    by_error_type = {}
    by_difficulty = {}

    total_review = 0
    mastered_count = 0

    for m in results:
        # by status
        status = m["status"]
        by_status[status] = by_status.get(status, 0) + 1

        # by subject
        subject = m.get("subject") or "unknown"
        by_subject[subject] = by_subject.get(subject, 0) + 1

        # by error type
        error_type = m.get("error_type") or "unknown"
        by_error_type[error_type] = by_error_type.get(error_type, 0) + 1

        # by difficulty
        difficulty = m.get("difficulty", 0.5)
        diff_bucket = f"{int(difficulty * 10) / 10:.1f}-{int(difficulty * 10) / 10 + 0.1:.1f}"
        by_difficulty[diff_bucket] = by_difficulty.get(diff_bucket, 0) + 1

        total_review += m.get("review_count", 0)
        if m["status"] == "mastered":
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
async def batch_create_mistakes(mistakes: List[MistakeCreate]):
    """批量创建错题"""
    results = []
    for data in mistakes:
        mistake_id = str(uuid.uuid4())
        now = datetime.now()

        mistake = {
            "mistake_id": mistake_id,
            "student_id": data.student_id,
            "session_id": data.session_id,
            "subject": data.subject,
            "topic": data.topic,
            "question_text": data.question_text,
            "student_answer": data.student_answer,
            "correct_answer": data.correct_answer,
            "error_type": data.error_type,
            "difficulty": data.difficulty,
            "capture_ids": data.capture_ids,
            "status": "new",
            "review_count": 0,
            "last_reviewed_at": None,
            "created_at": now,
            "updated_at": now,
            "review_events": []
        }

        _mistakes[mistake_id] = mistake
        results.append(mistake_id)

    return {"created": len(results), "mistake_ids": results}