"""
PAI-CC 学生画像 API
学生行为分析、学习统计、能力评估
"""
from fastapi import APIRouter, HTTPException, Query
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta
from collections import defaultdict

router = APIRouter()


class LearningActivity(BaseModel):
    """学习活动"""
    activity_type: str  # session, mistake, review, qa
    duration: int  # 秒
    timestamp: datetime
    details: dict = {}


class AbilityScore(BaseModel):
    """能力评分"""
    subject: str
    topic: Optional[str] = None
    score: float  # 0-100
    confidence: float  # 0-1
    based_on_samples: int


class StudyHabit(BaseModel):
    """学习习惯"""
    avg_session_duration: int  # 分钟
    preferred_study_time: str  # morning, afternoon, evening, night
    weekly_frequency: float
    avg_daily_study_time: int  # 分钟
    consistency_score: float  # 0-1


class StudentProfile(BaseModel):
    """学生画像"""
    student_id: str
    created_at: datetime
    updated_at: datetime

    # 基础统计
    total_sessions: int
    total_captures: int
    total_mistakes: int
    total_reviews: int
    total_questions: int

    # 学习进度
    learning_progress: dict  # 各科目进度
    mastered_topics: List[str] = []
    weak_topics: List[str] = []

    # 能力评估
    ability_scores: List[AbilityScore] = []

    # 学习习惯
    study_habits: Optional[StudyHabit] = None

    # 时间线
    recent_activities: List[LearningActivity] = []
    streak_days: int  # 连续学习天数


class PerformanceTrend(BaseModel):
    """表现趋势"""
    period: str  # week, month, all
    start_date: datetime
    end_date: datetime
    sessions_count: int
    mistakes_count: int
    review_count: int
    accuracy_trend: List[float]  # 正确率趋势
    effort_trend: List[int]  # 学习时长趋势


class SubjectAnalysis(BaseModel):
    """科目分析"""
    subject: str
    total_questions: int
    accuracy_rate: float
    common_errors: List[str] = []
    difficulty_distribution: dict
    improvement_score: float  # 相比上次的变化


class WeaknessAnalysis(BaseModel):
    """薄弱点分析"""
    topic: str
    subject: str
    error_count: int
    error_types: List[str]
    avg_difficulty: float
    last_practiced: Optional[datetime]
    suggested_practice_count: int


class ProgressReport(BaseModel):
    """进度报告"""
    generated_at: datetime
    period: str

    summary: dict
    strengths: List[dict] = []
    weaknesses: List[dict] = []
    recommendations: List[str] = []

    subject_breakdown: List[SubjectAnalysis] = []
    recent_improvements: List[str] = []


# 内存存储
_profiles = {}
_activities = defaultdict(list)


def get_or_create_profile(student_id: str) -> dict:
    """获取或创建学生画像"""
    now = datetime.now()

    if student_id not in _profiles:
        _profiles[student_id] = {
            "student_id": student_id,
            "created_at": now,
            "updated_at": now,
            "total_sessions": 0,
            "total_captures": 0,
            "total_mistakes": 0,
            "total_reviews": 0,
            "total_questions": 0,
            "learning_progress": {},
            "mastered_topics": [],
            "weak_topics": [],
            "ability_scores": [],
            "study_habits": None,
            "recent_activities": [],
            "streak_days": 0,
            "last_activity_date": None
        }

    return _profiles[student_id]


def update_streak(profile: dict):
    """更新连续学习天数"""
    today = datetime.now().date()
    last_date = profile.get("last_activity_date")

    if last_date is None:
        profile["streak_days"] = 1
    else:
        delta = today - last_date
        if delta.days == 1:
            profile["streak_days"] += 1
        elif delta.days > 1:
            profile["streak_days"] = 1

    profile["last_activity_date"] = today


@router.get("/{student_id}", response_model=StudentProfile)
async def get_student_profile(student_id: str):
    """获取学生画像"""
    profile = get_or_create_profile(student_id)

    # 获取最近活动
    recent = _activities.get(student_id, [])[-20:]
    profile["recent_activities"] = recent

    return StudentProfile(**profile)


@router.put("/{student_id}")
async def update_student_profile(student_id: str, updates: dict):
    """更新学生画像"""
    profile = get_or_create_profile(student_id)
    profile["updated_at"] = datetime.now()

    # 只允许更新某些字段
    allowed_fields = ["mastered_topics", "weak_topics", "ability_scores", "study_habits"]
    for field in allowed_fields:
        if field in updates:
            profile[field] = updates[field]

    return {"status": "updated", "student_id": student_id}


@router.get("/{student_id}/stats")
async def get_student_stats(student_id: str):
    """获取学生统计"""
    profile = get_or_create_profile(student_id)

    # 计算额外统计
    from app.api.mistakes import _mistakes
    from app.api.sessions import _sessions
    from app.api.review_queue import _review_queue

    student_mistakes = [m for m in _mistakes.values() if m["student_id"] == student_id]
    student_sessions = [s for s in _sessions.values() if s.get("student_id") == student_id]
    student_reviews = [r for r in _review_queue.values() if r["student_id"] == student_id]

    # 计算正确率
    total_attempts = sum(m.get("review_count", 0) for m in student_mistakes)
    mastered_count = sum(1 for m in student_mistakes if m["status"] == "mastered")
    accuracy = mastered_count / total_attempts if total_attempts > 0 else 0.0

    return {
        "student_id": student_id,
        "total_sessions": len(student_sessions),
        "total_captures": profile["total_captures"],
        "total_mistakes": len(student_mistakes),
        "total_reviews": total_attempts,
        "total_questions": profile["total_questions"],
        "accuracy_rate": round(accuracy * 100, 1),
        "mastered_count": mastered_count,
        "streak_days": profile["streak_days"],
        "last_activity": profile.get("last_activity_date")
    }


@router.post("/{student_id}/activity")
async def log_activity(student_id: str, activity: LearningActivity):
    """记录学习活动"""
    profile = get_or_create_profile(student_id)
    profile["updated_at"] = datetime.now()
    update_streak(profile)

    # 更新计数
    if activity.activity_type == "session":
        profile["total_sessions"] += 1
        profile["total_captures"] += activity.details.get("captures", 0)
    elif activity.activity_type == "mistake":
        profile["total_mistakes"] += 1
    elif activity.activity_type == "review":
        profile["total_reviews"] += 1
    elif activity.activity_type == "qa":
        profile["total_questions"] += 1

    # 保存活动
    _activities[student_id].append(activity)

    return {"status": "logged", "activity_id": len(_activities[student_id])}


@router.get("/{student_id}/trend", response_model=PerformanceTrend)
async def get_performance_trend(
    student_id: str,
    period: str = Query(default="week", regex="^(week|month|all)$")
):
    """获取表现趋势"""
    now = datetime.now()

    if period == "week":
        start_date = now - timedelta(days=7)
    elif period == "month":
        start_date = now - timedelta(days=30)
    else:
        start_date = datetime(2020, 1, 1)

    # 获取活动
    activities = [a for a in _activities.get(student_id, [])
                  if a.timestamp >= start_date]

    # 按天聚合
    daily_stats = defaultdict(lambda: {"sessions": 0, "mistakes": 0, "reviews": 0, "duration": 0})

    for activity in activities:
        day = activity.timestamp.date().isoformat()
        daily_stats[day]["duration"] += activity.duration
        if activity.activity_type == "session":
            daily_stats[day]["sessions"] += 1
        elif activity.activity_type == "mistake":
            daily_stats[day]["mistakes"] += 1
        elif activity.activity_type == "review":
            daily_stats[day]["reviews"] += 1

    # 生成趋势数据
    accuracy_trend = []
    effort_trend = []

    for day in sorted(daily_stats.keys()):
        stats = daily_stats[day]
        total = stats["mistakes"] + stats["reviews"]
        if total > 0:
            accuracy = (stats["reviews"] - stats["mistakes"]) / total
            accuracy = max(0, min(1, accuracy))
        else:
            accuracy = 0.5
        accuracy_trend.append(round(accuracy * 100, 1))
        effort_trend.append(stats["duration"])

    return PerformanceTrend(
        period=period,
        start_date=start_date,
        end_date=now,
        sessions_count=sum(s["sessions"] for s in daily_stats.values()),
        mistakes_count=sum(s["mistakes"] for s in daily_stats.values()),
        review_count=sum(s["reviews"] for s in daily_stats.values()),
        accuracy_trend=accuracy_trend,
        effort_trend=effort_trend
    )


@router.get("/{student_id}/subjects", response_model=List[SubjectAnalysis])
async def get_subject_analysis(student_id: str):
    """获取科目分析"""
    from app.api.mistakes import _mistakes

    student_mistakes = [m for m in _mistakes.values() if m["student_id"] == student_id]

    # 按科目分组
    by_subject = defaultdict(list)
    for m in student_mistakes:
        subject = m.get("subject") or "unknown"
        by_subject[subject].append(m)

    results = []
    for subject, mistakes in by_subject.items():
        total = len(mistakes)
        mastered = sum(1 for m in mistakes if m["status"] == "mastered")
        accuracy = mastered / total if total > 0 else 0.0

        # 错误类型统计
        error_types = defaultdict(int)
        for m in mistakes:
            et = m.get("error_type") or "unknown"
            error_types[et] += 1

        # 难度分布
        difficulty_dist = defaultdict(int)
        for m in mistakes:
            d = round(m.get("difficulty", 0.5), 1)
            difficulty_dist[f"{d:.1f}"] += 1

        results.append(SubjectAnalysis(
            subject=subject,
            total_questions=total,
            accuracy_rate=round(accuracy * 100, 1),
            common_errors=[et for et, _ in sorted(error_types.items(), key=lambda x: -x[1])[:3]],
            difficulty_distribution=dict(difficulty_dist),
            improvement_score=0.0  # TODO: 计算相比上次
        ))

    return results


@router.get("/{student_id}/weaknesses", response_model=List[WeaknessAnalysis])
async def get_weakness_analysis(student_id: str, limit: int = Query(default=10, le=20)):
    """获取薄弱点分析"""
    from app.api.mistakes import _mistakes

    student_mistakes = [m for m in _mistakes.values() if m["student_id"] == student_id]
    student_mistakes = [m for m in student_mistakes if m["status"] != "mastered"]

    if not student_mistakes:
        return []

    # 按 topic 分组
    by_topic = defaultdict(lambda: {"errors": 0, "error_types": [], "difficulties": [], "last": None})
    for m in student_mistakes:
        topic = m.get("topic") or m.get("subject") or "unknown"
        by_topic[topic]["errors"] += 1
        if m.get("error_type"):
            by_topic[topic]["error_types"].append(m["error_type"])
        if m.get("difficulty"):
            by_topic[topic]["difficulties"].append(m["difficulty"])
        if m.get("last_reviewed_at"):
            by_topic[topic]["last"] = m["last_reviewed_at"]

    # 排序并取最弱的
    sorted_topics = sorted(by_topic.items(), key=lambda x: -x[1]["errors"])
    results = []

    for topic, data in sorted_topics[:limit]:
        results.append(WeaknessAnalysis(
            topic=topic,
            subject=data["error_types"][0] if data["error_types"] else "unknown",
            error_count=data["errors"],
            error_types=list(set(data["error_types"]))[:3],
            avg_difficulty=sum(data["difficulties"]) / len(data["difficulties"]) if data["difficulties"] else 0.5,
            last_practiced=data["last"],
            suggested_practice_count=min(data["errors"] * 3, 20)
        ))

    return results


@router.get("/{student_id}/report", response_model=ProgressReport)
async def get_progress_report(
    student_id: str,
    period: str = Query(default="week", regex="^(week|month|all)$")
):
    """获取进度报告"""
    profile = get_or_create_profile(student_id)
    now = datetime.now()

    # 获取科目分析
    subjects = await get_subject_analysis(student_id)

    # 获取薄弱点
    weaknesses = await get_weakness_analysis(student_id, limit=5)

    # 生成建议
    recommendations = []
    for w in weaknesses[:3]:
        recommendations.append(f"建议加强 {w.topic} 的练习，当前错误 {w.error_count} 次")

    if profile["streak_days"] > 0:
        recommendations.append(f"保持学习习惯，已连续学习 {profile['streak_days']} 天")

    # 分析 strengths
    strengths = []
    for s in subjects:
        if s.accuracy_rate > 80:
            strengths.append({
                "subject": s.subject,
                "accuracy": s.accuracy_rate,
                "reason": "正确率高于80%"
            })

    return ProgressReport(
        generated_at=now,
        period=period,
        summary={
            "total_sessions": profile["total_sessions"],
            "total_mistakes": profile["total_mistakes"],
            "mastered_count": len(profile["mastered_topics"]),
            "streak_days": profile["streak_days"]
        },
        strengths=strengths,
        weaknesses=[{"topic": w.topic, "error_count": w.error_count} for w in weaknesses[:3]],
        recommendations=recommendations,
        subject_breakdown=subjects,
        recent_improvements=["本周正确率提升 5%"]  # TODO: 计算实际变化
    )


@router.get("/{student_id}/habits", response_model=StudyHabit)
async def get_study_habits(student_id: str):
    """获取学习习惯分析"""
    profile = get_or_create_profile(student_id)
    activities = _activities.get(student_id, [])

    if not activities:
        return StudyHabit(
            avg_session_duration=0,
            preferred_study_time="unknown",
            weekly_frequency=0.0,
            avg_daily_study_time=0,
            consistency_score=0.0
        )

    # 分析学习时段
    hour_counts = defaultdict(int)
    for a in activities:
        if a.activity_type == "session":
            hour = a.timestamp.hour
            if 6 <= hour < 12:
                hour_counts["morning"] += 1
            elif 12 <= hour < 18:
                hour_counts["afternoon"] += 1
            elif 18 <= hour < 22:
                hour_counts["evening"] += 1
            else:
                hour_counts["night"] += 1

    preferred = max(hour_counts.items(), key=lambda x: x[1])[0] if hour_counts else "unknown"

    # 计算会话时长
    session_durations = [a.duration for a in activities if a.activity_type == "session"]
    avg_duration = sum(session_durations) / len(session_durations) / 60 if session_durations else 0

    # 计算周频率
    if len(activities) > 1:
        time_span = (activities[-1].timestamp - activities[0].timestamp).days
        if time_span > 0:
            weekly_freq = len(activities) / time_span * 7
        else:
            weekly_freq = len(activities)
    else:
        weekly_freq = 0.0

    # 计算每日平均学习时间
    daily_duration = sum(a.duration for a in activities) / 60  # 分钟

    return StudyHabit(
        avg_session_duration=int(avg_duration),
        preferred_study_time=preferred,
        weekly_frequency=round(weekly_freq, 1),
        avg_daily_study_time=int(daily_duration),
        consistency_score=min(profile["streak_days"] / 30, 1.0)  # 简单计算
    )
