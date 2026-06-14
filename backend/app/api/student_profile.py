"""
PAI-CC 学生画像 API
学生行为分析、学习统计、能力评估
使用 SQLite 数据库持久化存储
"""
from fastapi import APIRouter, HTTPException, Query, Depends
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta
from collections import defaultdict
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.database import get_db, engine
from app.models.models import Base, Student as DBStudent, Mistake as DBMistake, Session as DBSession, Capture as DBCapture, ReviewEvent as DBReviewEvent

router = APIRouter()

# 初始化数据库表
Base.metadata.create_all(bind=engine)


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


@router.get("/{student_id}", response_model=StudentProfile)
async def get_student_profile(student_id: str, db: Session = Depends(get_db)):
    """获取学生画像"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        # 创建新学生
        student = _get_or_create_student(db, student_id)

    now = datetime.now()

    # 统计
    total_sessions = db.query(DBSession).filter(DBSession.student_id == student.id).count()
    total_captures = db.query(DBCapture).filter(DBCapture.session_id == DBSession.id).count()
    total_mistakes = db.query(DBMistake).filter(DBMistake.student_id == student.id).count()
    total_reviews = db.query(DBReviewEvent).filter(DBReviewEvent.student_id == student.id).count()

    # 获取已掌握的 topic
    mastered_mistakes = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBMistake.student_id == student.id,
        DBMistake.status == "mastered"
    ).all()
    mastered_topics = list(set([m.subject or "unknown" for m in mastered_mistakes]))

    # 获取薄弱 topic
    weak_mistakes = db.query(DBMistake).filter(
        DBMistake.student_id == student.id,
        DBMistake.status != "mastered"
    ).all()
    weak_topics = list(set([m.subject or "unknown" for m in weak_mistakes]))

    return StudentProfile(
        student_id=student_id,
        created_at=student.created_at,
        updated_at=student.updated_at,
        total_sessions=total_sessions,
        total_captures=total_captures,
        total_mistakes=total_mistakes,
        total_reviews=total_reviews,
        total_questions=0,
        learning_progress={},
        mastered_topics=mastered_topics,
        weak_topics=weak_topics,
        ability_scores=[],
        study_habits=None,
        recent_activities=[],
        streak_days=0
    )


@router.put("/{student_id}")
async def update_student_profile(student_id: str, updates: dict, db: Session = Depends(get_db)):
    """更新学生画像"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    student.updated_at = datetime.now()
    db.commit()

    return {"status": "updated", "student_id": student_id}


@router.get("/{student_id}/stats")
async def get_student_stats(student_id: str, db: Session = Depends(get_db)):
    """获取学生统计"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return {
            "student_id": student_id,
            "total_sessions": 0,
            "total_captures": 0,
            "total_mistakes": 0,
            "total_reviews": 0,
            "total_questions": 0,
            "accuracy_rate": 0.0,
            "mastered_count": 0,
            "streak_days": 0,
            "last_activity": None
        }

    # 获取会话数
    total_sessions = db.query(DBSession).filter(DBSession.student_id == student.id).count()

    # 获取错题数
    total_mistakes = db.query(DBMistake).filter(DBMistake.student_id == student.id).count()
    mastered_count = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBStudent.id == DBStudent.id,
        DBMistake.student_id == student.id,
        DBStudent.id == DBStudent.id,
        DBMistake.status == "mastered"
    ).count()
    mastered_count = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBMistake.student_id == student.id,
        DBMistake.status == "mastered"
    ).count()

    # 获取复习次数
    total_reviews = db.query(DBReviewEvent).filter(DBReviewEvent.student_id == student.id).count()

    # 计算正确率
    total_attempts = db.query(func.sum(DBMistake.review_count)).filter(DBMistake.student_id == student.id).scalar() or 0
    accuracy = mastered_count / total_attempts if total_attempts > 0 else 0.0

    return {
        "student_id": student_id,
        "total_sessions": total_sessions,
        "total_captures": 0,
        "total_mistakes": total_mistakes,
        "total_reviews": total_reviews,
        "total_questions": 0,
        "accuracy_rate": round(accuracy * 100, 1),
        "mastered_count": mastered_count,
        "streak_days": 0,
        "last_activity": None
    }


@router.post("/{student_id}/activity")
async def log_activity(student_id: str, activity: LearningActivity, db: Session = Depends(get_db)):
    """记录学习活动"""
    student = _get_or_create_student(db, student_id)
    student.updated_at = datetime.now()
    db.commit()

    return {"status": "logged", "student_id": student_id}


@router.get("/{student_id}/trend", response_model=PerformanceTrend)
async def get_performance_trend(
    student_id: str,
    period: str = Query(default="week", regex="^(week|month|all)$"),
    db: Session = Depends(get_db)
):
    """获取表现趋势"""
    now = datetime.now()

    if period == "week":
        start_date = now - timedelta(days=7)
    elif period == "month":
        start_date = now - timedelta(days=30)
    else:
        start_date = datetime(2020, 1, 1)

    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return PerformanceTrend(
            period=period,
            start_date=start_date,
            end_date=now,
            sessions_count=0,
            mistakes_count=0,
            review_count=0,
            accuracy_trend=[],
            effort_trend=[]
        )

    # 获取会话
    sessions = db.query(DBSession).filter(
        DBSession.student_id == student.id,
        DBSession.created_at >= start_date
    ).all()

    # 获取错题
    mistakes = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBStudent.id == DBStudent.id,
        DBMistake.student_id == student.id,
        DBMistake.created_at >= start_date
    ).all()
    mistakes = db.query(DBMistake).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBMistake.student_id == student.id,
        DBMistake.created_at >= start_date
    ).all()

    # 获取复习事件
    reviews = db.query(DBReviewEvent).filter(
        DBStudent.id == DBStudent.id,
        DBStudent.student_id == student_id,
        DBReviewEvent.student_id == student.id,
        DBReviewEvent.created_at >= start_date
    ).all()

    return PerformanceTrend(
        period=period,
        start_date=start_date,
        end_date=now,
        sessions_count=len(sessions),
        mistakes_count=len(mistakes),
        review_count=len(reviews),
        accuracy_trend=[],
        effort_trend=[]
    )


@router.get("/{student_id}/subjects", response_model=List[SubjectAnalysis])
async def get_subject_analysis(student_id: str, db: Session = Depends(get_db)):
    """获取科目分析"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return []

    # 获取该学生的错题
    mistakes = db.query(DBMistake).filter(
        DBMistake.student_id == student.id
    ).all()

    # 按科目分组
    by_subject = defaultdict(list)
    for m in mistakes:
        subject = m.subject or "unknown"
        by_subject[subject].append(m)

    results = []
    for subject, subject_mistakes in by_subject.items():
        total = len(subject_mistakes)
        mastered = sum(1 for m in subject_mistakes if m.status == "mastered")
        accuracy = mastered / total if total > 0 else 0.0

        # 错误类型统计
        error_types = defaultdict(int)
        for m in subject_mistakes:
            et = m.error_reason or "unknown"
            error_types[et] += 1

        # 难度分布
        difficulty_dist = defaultdict(int)
        for m in subject_mistakes:
            d = round(m.difficulty or 0.5, 1)
            difficulty_dist[f"{d:.1f}"] += 1

        results.append(SubjectAnalysis(
            subject=subject,
            total_questions=total,
            accuracy_rate=round(accuracy * 100, 1),
            common_errors=[et for et, _ in sorted(error_types.items(), key=lambda x: -x[1])[:3]],
            difficulty_distribution=dict(difficulty_dist),
            improvement_score=0.0
        ))

    return results


@router.get("/{student_id}/weaknesses", response_model=List[WeaknessAnalysis])
async def get_weakness_analysis(student_id: str, limit: int = Query(default=10, le=20), db: Session = Depends(get_db)):
    """获取薄弱点分析"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return []

    # 获取未掌握的错题
    mistakes = db.query(DBMistake).filter(
        DBMistake.student_id == student.id,
        DBMistake.status != "mastered"
    ).all()

    if not mistakes:
        return []

    # 按 topic(subject) 分组
    by_topic = defaultdict(lambda: {"errors": 0, "error_types": [], "difficulties": [], "last": None})
    for m in mistakes:
        topic = m.subject or "unknown"
        by_topic[topic]["errors"] += 1
        if m.error_reason:
            by_topic[topic]["error_types"].append(m.error_reason)
        if m.difficulty:
            by_topic[topic]["difficulties"].append(m.difficulty)
        if m.next_review_at:
            by_topic[topic]["last"] = m.next_review_at

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
    period: str = Query(default="week", regex="^(week|month|all)$"),
    db: Session = Depends(get_db)
):
    """获取进度报告"""
    now = datetime.now()

    # 获取科目分析
    subjects = await get_subject_analysis(student_id, db)

    # 获取薄弱点
    weaknesses = await get_weakness_analysis(student_id, limit=5, db=db)

    # 生成建议
    recommendations = []
    for w in weaknesses[:3]:
        recommendations.append(f"建议加强 {w.topic} 的练习，当前错误 {w.error_count} 次")

    # 获取统计
    stats = await get_student_stats(student_id, db)
    streak_days = stats.get("streak_days", 0)
    if streak_days > 0:
        recommendations.append(f"保持学习习惯，已连续学习 {streak_days} 天")

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
            "total_sessions": stats.get("total_sessions", 0),
            "total_mistakes": stats.get("total_mistakes", 0),
            "mastered_count": stats.get("mastered_count", 0),
            "streak_days": streak_days
        },
        strengths=strengths,
        weaknesses=[{"topic": w.topic, "error_count": w.error_count} for w in weaknesses[:3]],
        recommendations=recommendations,
        subject_breakdown=subjects,
        recent_improvements=[]
    )


@router.get("/{student_id}/habits", response_model=StudyHabit)
async def get_study_habits(student_id: str, db: Session = Depends(get_db)):
    """获取学习习惯分析"""
    student = db.query(DBStudent).filter(DBStudent.student_id == student_id).first()
    if not student:
        return StudyHabit(
            avg_session_duration=0,
            preferred_study_time="unknown",
            weekly_frequency=0.0,
            avg_daily_study_time=0,
            consistency_score=0.0
        )

    # 获取会话
    sessions = db.query(DBSession).filter(DBSession.student_id == student.id).all()

    if not sessions:
        return StudyHabit(
            avg_session_duration=0,
            preferred_study_time="unknown",
            weekly_frequency=0.0,
            avg_daily_study_time=0,
            consistency_score=0.0
        )

    # 分析学习时段
    hour_counts = defaultdict(int)
    for s in sessions:
        hour = s.created_at.hour
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
    total_duration = sum(s.camera_active_time or 0 for s in sessions)
    avg_duration = total_duration / len(sessions) / 60 if sessions else 0

    # 计算周频率
    if len(sessions) > 1:
        time_span = (sessions[-1].created_at - sessions[0].created_at).days
        if time_span > 0:
            weekly_freq = len(sessions) / time_span * 7
        else:
            weekly_freq = float(len(sessions))
    else:
        weekly_freq = 0.0

    return StudyHabit(
        avg_session_duration=int(avg_duration),
        preferred_study_time=preferred,
        weekly_frequency=round(weekly_freq, 1),
        avg_daily_study_time=int(total_duration / 60),
        consistency_score=0.0
    )