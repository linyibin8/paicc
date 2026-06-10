"""
PAI-CC 数据模型
"""
from sqlalchemy import Column, String, Integer, DateTime, Boolean, Text, JSON, ForeignKey, Float
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()


class Student(Base):
    """学生模型"""
    __tablename__ = "students"

    id = Column(Integer, primary_key=True, autoincrement=True)
    student_id = Column(String(64), unique=True, index=True)
    name = Column(String(128))
    grade = Column(String(32))
    subjects = Column(JSON, default=[])
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sessions = relationship("Session", back_populates="student")
    mistakes = relationship("Mistake", back_populates="student")
    review_events = relationship("ReviewEvent", back_populates="student")


class Session(Base):
    """学习会话/回合"""
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String(64), unique=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"))
    status = Column(String(32), default="created")
    student_goal = Column(Text)
    assistant_focus = Column(Text)
    report_style = Column(String(32), default="normal")

    camera_active_time = Column(Integer, default=0)
    student_active_time = Column(Integer, default=0)
    empty_capture_time = Column(Integer, default=0)
    capture_count = Column(Integer, default=0)
    mistake_count = Column(Integer, default=0)
    learning_item_count = Column(Integer, default=0)
    report = Column(JSON)
    timeline = Column(JSON)

    started_at = Column(DateTime)
    ended_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    student = relationship("Student", back_populates="sessions")
    captures = relationship("Capture", back_populates="session")


class Capture(Base):
    """单次画面采集"""
    __tablename__ = "captures"

    id = Column(Integer, primary_key=True, autoincrement=True)
    capture_id = Column(String(64), unique=True, index=True)
    session_id = Column(Integer, ForeignKey("sessions.id"))
    sequence = Column(Integer)
    timestamp = Column(DateTime)
    frame_fingerprint = Column(String(64))
    quality_score = Column(Float, default=0.0)
    student_present = Column(Boolean, default=False)
    content_type = Column(String(32))
    text_tokens = Column(Text)
    image_path = Column(String(256))
    analysis = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("Session", back_populates="captures")
    learning_items = relationship("LearningItem", back_populates="capture")
    mistakes = relationship("Mistake", back_populates="capture")


class LearningItem(Base):
    """学习条目"""
    __tablename__ = "learning_items"

    id = Column(Integer, primary_key=True, autoincrement=True)
    item_id = Column(String(64), unique=True, index=True)
    capture_id = Column(Integer, ForeignKey("captures.id"))
    session_id = Column(Integer, ForeignKey("sessions.id"))
    student_id = Column(Integer, ForeignKey("students.id"))
    item_type = Column(String(32))
    subject = Column(String(64))
    page_number = Column(String(32))
    question_number = Column(String(32))
    title = Column(Text)
    content = Column(Text)
    solution = Column(Text)
    knowledge_points = Column(JSON, default=[])
    evidence_image = Column(String(256))
    document_id = Column(String(64))
    created_at = Column(DateTime, default=datetime.utcnow)

    capture = relationship("Capture", back_populates="learning_items")


class Mistake(Base):
    """错题记录"""
    __tablename__ = "mistakes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    mistake_id = Column(String(64), unique=True, index=True)
    capture_id = Column(Integer, ForeignKey("captures.id"))
    session_id = Column(Integer, ForeignKey("sessions.id"))
    student_id = Column(Integer, ForeignKey("students.id"))

    status = Column(String(32), default="suspected")
    is_correct = Column(Boolean, nullable=True)

    subject = Column(String(64))
    page_number = Column(String(32))
    question_number = Column(String(32))
    student_answer = Column(Text)
    correct_answer = Column(Text)
    error_reason = Column(Text)
    knowledge_points = Column(JSON, default=[])
    correction_suggestion = Column(Text)
    next_action = Column(Text)
    evidence_image = Column(String(256))

    review_count = Column(Integer, default=0)
    review_status = Column(String(32), default="queued")
    next_review_at = Column(DateTime)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    capture = relationship("Capture", back_populates="mistakes")
    student = relationship("Student", back_populates="mistakes")
    review_events = relationship("ReviewEvent", back_populates="mistake")


class ReviewEvent(Base):
    """复习事件"""
    __tablename__ = "review_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    event_id = Column(String(64), unique=True, index=True)
    mistake_id = Column(Integer, ForeignKey("mistakes.id"))
    student_id = Column(Integer, ForeignKey("students.id"))
    result = Column(String(32))
    notes = Column(Text)
    time_spent = Column(Integer)
    score = Column(Float)
    created_at = Column(DateTime, default=datetime.utcnow)

    mistake = relationship("Mistake", back_populates="review_events")
    student = relationship("Student", back_populates="review_events")


class QASession(Base):
    """AI 问答会话"""
    __tablename__ = "qa_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    qa_session_id = Column(String(64), unique=True, index=True)
    session_id = Column(Integer, ForeignKey("sessions.id"))
    student_id = Column(Integer, ForeignKey("students.id"))
    trigger_type = Column(String(32))
    trigger_image = Column(String(256))
    conversation_history = Column(JSON, default=[])
    turn_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    ended_at = Column(DateTime)