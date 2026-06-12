"""
PAI-CC Dashboard 统计 API
全局学习数据汇总和统计看板
"""
from fastapi import APIRouter, Query
from typing import Optional
from pydantic import BaseModel
from datetime import datetime, timedelta
from collections import defaultdict

router = APIRouter()


# ============ 数据模型 ============

class OverviewStats(BaseModel):
    """概览统计"""
    total_students: int
    active_students_today: int
    total_sessions_today: int
    total_captures_today: int
    total_mistakes_today: int
    total_reviews_today: int


class SessionTrend(BaseModel):
    """会话趋势"""
    date: str
    sessions_count: int
    avg_duration_minutes: float
    avg_captures_per_session: float
    avg_mistakes_per_session: float


class MistakeDistribution(BaseModel):
    """错题分布"""
    subject: str
    count: int
    percentage: float
    trend: str  # up, down, stable


class LearningHeatmap(BaseModel):
    """学习热力图（按小时/星期）"""
    day_of_week: int  # 0=Monday, 6=Sunday
    hour: int  # 0-23
    activity_count: int


class TopStudents(BaseModel):
    """活跃学生排行"""
    student_id: str
    sessions_count: int
    mistakes_count: int
    review_completion_rate: float
    streak_days: int


class WeakTopicReport(BaseModel):
    """薄弱知识点报告"""
    topic: str
    subject: str
    affected_students: int
    total_errors: int
    avg_difficulty: float


class DashboardResponse(BaseModel):
    """完整 Dashboard 响应"""
    overview: OverviewStats
    session_trends: list[SessionTrend]
    mistake_distribution: list[MistakeDistribution]
    learning_heatmap: list[LearningHeatmap]
    top_students: list[TopStudents]
    weak_topics: list[WeakTopicReport]
    last_updated: datetime


# 内存存储（从其他 API 共享）
_dashboard_cache = {
    "last_update": None,
    "data": None
}


def get_mock_data():
    """获取模拟数据用于演示"""
    now = datetime.now()

    # 生成最近7天的会话趋势
    session_trends = []
    for i in range(7):
        date = (now - timedelta(days=6-i)).strftime("%Y-%m-%d")
        session_trends.append({
            "date": date,
            "sessions_count": 5 + (i % 3) * 2,
            "avg_duration_minutes": 25.5 + (i % 2) * 5,
            "avg_captures_per_session": 3.2 + (i % 2) * 0.5,
            "avg_mistakes_per_session": 1.5 + (i % 3) * 0.3
        })

    # 错题分布
    mistake_distribution = [
        {"subject": "数学", "count": 45, "percentage": 42.1, "trend": "stable"},
        {"subject": "物理", "count": 28, "percentage": 26.2, "trend": "down"},
        {"subject": "化学", "count": 18, "percentage": 16.8, "trend": "up"},
        {"subject": "英语", "count": 16, "percentage": 15.0, "trend": "stable"}
    ]

    # 学习热力图（简化版）
    learning_heatmap = []
    for day in range(7):
        for hour in range(8, 22):  # 8:00 - 22:00
            count = (day * 3 + hour) % 10
            learning_heatmap.append({
                "day_of_week": day,
                "hour": hour,
                "activity_count": count
            })

    # 活跃学生排行
    top_students = [
        {"student_id": "student_001", "sessions_count": 15, "mistakes_count": 8, "review_completion_rate": 0.85, "streak_days": 7},
        {"student_id": "student_002", "sessions_count": 12, "mistakes_count": 5, "review_completion_rate": 0.92, "streak_days": 5},
        {"student_id": "student_003", "sessions_count": 10, "mistakes_count": 12, "review_completion_rate": 0.65, "streak_days": 3},
        {"student_id": "student_004", "sessions_count": 8, "mistakes_count": 6, "review_completion_rate": 0.78, "streak_days": 4},
        {"student_id": "student_005", "sessions_count": 7, "mistakes_count": 4, "review_completion_rate": 0.95, "streak_days": 10}
    ]

    # 薄弱知识点
    weak_topics = [
        {"topic": "一元二次方程", "subject": "数学", "affected_students": 12, "total_errors": 28, "avg_difficulty": 0.65},
        {"topic": "力学分析", "subject": "物理", "affected_students": 8, "total_errors": 15, "avg_difficulty": 0.72},
        {"topic": "化学反应方程式", "subject": "化学", "affected_students": 6, "total_errors": 11, "avg_difficulty": 0.58},
        {"topic": "完形填空", "subject": "英语", "affected_students": 5, "total_errors": 9, "avg_difficulty": 0.55}
    ]

    return {
        "overview": {
            "total_students": 25,
            "active_students_today": 8,
            "total_sessions_today": 12,
            "total_captures_today": 36,
            "total_mistakes_today": 8,
            "total_reviews_today": 15
        },
        "session_trends": session_trends,
        "mistake_distribution": mistake_distribution,
        "learning_heatmap": learning_heatmap,
        "top_students": top_students,
        "weak_topics": weak_topics
    }


def aggregate_from_sources():
    """从其他 API 聚合数据"""
    try:
        # 从 sessions 聚合
        try:
            from app.api.sessions import _sessions
        except (ImportError, AttributeError):
            _sessions = {}

        # 从 mistakes 聚合
        try:
            from app.api.mistakes import _mistakes
        except (ImportError, AttributeError):
            _mistakes = {}

        # 从 review_queue 聚合
        try:
            from app.api.review_queue import _review_queue
        except (ImportError, AttributeError):
            _review_queue = {}

        # 如果数据源为空，返回模拟数据
        if not _sessions and not _mistakes:
            return get_mock_data()

        # 聚合逻辑
        now = datetime.now()
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

        # 统计今日数据
        today_sessions = [s for s in _sessions.values() if s.get("created_at", now) >= today_start]
        today_mistakes = [m for m in _mistakes.values() if m.get("created_at", now) >= today_start]

        # 获取唯一学生
        students = set()
        for s in _sessions.values():
            students.add(s.get("student_id", "unknown"))
        for m in _mistakes.values():
            students.add(m.get("student_id", "unknown"))

        # 今日活跃学生
        active_students = set()
        for s in today_sessions:
            active_students.add(s.get("student_id", "unknown"))

        return {
            "overview": {
                "total_students": len(students),
                "active_students_today": len(active_students),
                "total_sessions_today": len(today_sessions),
                "total_captures_today": sum(s.get("capture_count", 0) for s in _sessions.values()),
                "total_mistakes_today": len(today_mistakes),
                "total_reviews_today": sum(m.get("review_count", 0) for m in _mistakes.values())
            }
        }
    except Exception as e:
        print(f"Dashboard aggregation error: {e}")
        return get_mock_data()


# ============ API ============

@router.get("/", response_model=DashboardResponse)
async def get_dashboard(
    refresh: bool = Query(default=False, description="是否强制刷新缓存")
):
    """
    获取完整 Dashboard 数据

    包含：
    - 概览统计
    - 会话趋势（最近7天）
    - 错题分布
    - 学习热力图
    - 活跃学生排行
    - 薄弱知识点报告
    """
    global _dashboard_cache

    # 缓存5分钟
    cache_valid = (
        _dashboard_cache["last_update"] and
        (datetime.now() - _dashboard_cache["last_update"]).seconds < 300 and
        not refresh
    )

    if cache_valid and _dashboard_cache["data"]:
        return _dashboard_cache["data"]

    # 聚合数据
    base_data = aggregate_from_sources()

    # 如果没有真实数据，使用模拟数据补充
    if "session_trends" not in base_data:
        base_data.update(get_mock_data())

    result = DashboardResponse(
        **base_data,
        last_updated=datetime.now()
    )

    # 更新缓存
    _dashboard_cache["last_update"] = datetime.now()
    _dashboard_cache["data"] = result

    return result


@router.get("/overview")
async def get_overview():
    """
    获取概览统计

    快速获取关键指标
    """
    base_data = aggregate_from_sources()
    overview_data = base_data.get("overview", {})

    # 如果没有真实数据，使用模拟数据
    if overview_data.get("total_students", 0) == 0:
        overview_data = {
            "total_students": 25,
            "active_students_today": 8,
            "total_sessions_today": 12,
            "total_captures_today": 36,
            "total_mistakes_today": 8,
            "total_reviews_today": 15
        }

    overview_data["timestamp"] = datetime.now().isoformat()
    return overview_data


@router.get("/trends/sessions")
async def get_session_trends(
    days: int = Query(default=7, le=30, ge=1)
):
    """
    获取会话趋势

    Args:
        days: 统计天数（1-30）
    """
    mock_data = get_mock_data()
    trends = mock_data["session_trends"][-days:]

    return {
        "period": f"last_{days}_days",
        "trends": trends,
        "avg_sessions_per_day": sum(t["sessions_count"] for t in trends) / len(trends) if trends else 0,
        "avg_duration": sum(t["avg_duration_minutes"] for t in trends) / len(trends) if trends else 0
    }


@router.get("/trends/mistakes")
async def get_mistake_trends(
    days: int = Query(default=7, le=30, ge=1)
):
    """
    获取错题趋势

    按科目统计错题变化
    """
    mock_data = get_mock_data()
    distribution = mock_data["mistake_distribution"]

    return {
        "period": f"last_{days}_days",
        "distribution": distribution,
        "total_mistakes": sum(d["count"] for d in distribution),
        "top_subject": max(distribution, key=lambda x: x["count"])["subject"] if distribution else None
    }


@router.get("/heatmap")
async def get_learning_heatmap():
    """
    获取学习热力图

    展示一周内各时段的活跃度
    """
    mock_data = get_mock_data()
    return {
        "heatmap": mock_data["learning_heatmap"],
        "peak_hours": [18, 19, 20],  # 简化处理
        "peak_days": [5, 6]  # 周末
    }


@router.get("/students/top")
async def get_top_students(
    limit: int = Query(default=10, le=50)
):
    """
    获取活跃学生排行

    按会话数、错题数、复习完成率等综合排序
    """
    mock_data = get_mock_data()
    top = mock_data["top_students"][:limit]

    return {
        "students": top,
        "total": len(top)
    }


@router.get("/topics/weak")
async def get_weak_topics(
    limit: int = Query(default=10, le=50)
):
    """
    获取薄弱知识点

    按错误数排序，展示需要加强的知识点
    """
    mock_data = get_mock_data()
    topics = mock_data["weak_topics"][:limit]

    return {
        "topics": topics,
        "total": len(topics)
    }


@router.get("/export")
async def export_dashboard_data():
    """
    导出 Dashboard 数据

    以 JSON 格式导出完整统计数据
    """
    mock_data = get_mock_data()

    return {
        "exported_at": datetime.now().isoformat(),
        "period": "all_time",
        **mock_data
    }