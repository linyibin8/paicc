"""
PAI-CC 复习队列 API
"""
from fastapi import APIRouter, HTTPException
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta
import uuid

router = APIRouter()


class ReviewQueueItem(BaseModel):
    """复习队列项"""
    queue_id: str
    mistake_id: str
    session_id: str
    status: str  # queued, scheduled, reviewing, mastered
    scheduled_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    priority: int = 0
    knowledge_points: List[str] = []


class StudentProfile(BaseModel):
    """学生画像"""
    student_id: str
    weak_points: List[dict] = []
    common_errors: List[dict] = []
    subject_distribution: dict = {}
    review_overview: dict = {}
    recent_sessions: List[dict] = []
    mastery_trend: List[dict] = []


# 内存存储
_review_queue = {}
_profiles = {}


@router.get("/queue")
async def get_review_queue(
    student_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 20
):
    """获取复习队列"""
    results = list(_review_queue.values())

    if student_id:
        results = [r for r in results if r.get("student_id") == student_id]
    if status:
        results = [r for r in results if r.get("status") == status]

    results.sort(key=lambda x: (x.get("priority", 0), x.get("scheduled_at", datetime.now())))

    return {
        "queue": results[:limit],
        "total": len(results)
    }


@router.post("/queue/{mistake_id}")
async def add_to_review_queue(
    mistake_id: str,
    student_id: str,
    priority: int = 0,
    scheduled_at: Optional[datetime] = None
):
    """添加错题到复习队列"""
    queue_id = str(uuid.uuid4())

    item = {
        "queue_id": queue_id,
        "mistake_id": mistake_id,
        "session_id": "",
        "student_id": student_id,
        "status": "queued" if not scheduled_at else "scheduled",
        "scheduled_at": scheduled_at.isoformat() if scheduled_at else None,
        "completed_at": None,
        "priority": priority,
        "knowledge_points": []
    }

    _review_queue[queue_id] = item

    return {"status": "ok", "queue_id": queue_id, "item": item}


@router.put("/queue/{queue_id}")
async def update_review_item(queue_id: str, status: str):
    """更新复习项状态"""
    if queue_id not in _review_queue:
        raise HTTPException(status_code=404, detail="Queue item not found")

    valid_statuses = ["queued", "scheduled", "reviewing", "mastered"]
    if status not in valid_statuses:
        raise HTTPException(status_code=400, detail="Invalid status")

    _review_queue[queue_id]["status"] = status
    if status == "mastered":
        _review_queue[queue_id]["completed_at"] = datetime.now().isoformat()

    return {"status": "ok"}


@router.delete("/queue/{queue_id}")
async def remove_from_queue(queue_id: str):
    """从队列中移除"""
    if queue_id in _review_queue:
        del _review_queue[queue_id]
        return {"status": "deleted"}

    raise HTTPException(status_code=404, detail="Queue item not found")


@router.get("/student/{student_id}/profile", response_model=StudentProfile)
async def get_student_profile(student_id: str):
    """获取学生画像"""
    if student_id not in _profiles:
        _profiles[student_id] = {
            "student_id": student_id,
            "weak_points": [
                {"point": "一元二次方程", "count": 5, "trend": "stable"},
                {"point": "函数图像", "count": 3, "trend": "improving"}
            ],
            "common_errors": [
                {"error": "符号错误", "count": 8},
                {"error": "计算粗心", "count": 6}
            ],
            "subject_distribution": {
                "数学": 60,
                "物理": 25,
                "化学": 15
            },
            "review_overview": {
                "total_mistakes": 25,
                "mastered": 10,
                "in_progress": 8,
                "new": 7
            },
            "recent_sessions": [],
            "mastery_trend": [
                {"date": "2026-06-01", "mastery": 0.3},
                {"date": "2026-06-05", "mastery": 0.45},
                {"date": "2026-06-10", "mastery": 0.55}
            ]
        }

    return StudentProfile(**_profiles[student_id])


@router.get("/student/{student_id}/stats")
async def get_student_stats(student_id: str):
    """获取学生统计"""
    return {
        "student_id": student_id,
        "total_sessions": 15,
        "total_captures": 156,
        "total_mistakes": 25,
        "mastered_mistakes": 10,
        "review_queue_length": 8,
        "weekly_study_time": 3600,
        "success_rate": 0.75
    }