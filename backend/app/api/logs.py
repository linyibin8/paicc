"""
PAI-CC Logs API
日志查看端点
"""
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, timedelta
from enum import Enum
import asyncio
import json
from collections import deque

router = APIRouter()


# ============ 日志级别 ============

class LogLevel(str, Enum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


# ============ 日志模型 ============

class LogEntry(BaseModel):
    """日志条目"""
    timestamp: str
    level: str
    message: str
    source: Optional[str] = None
    session_id: Optional[str] = None
    extra: Optional[dict] = None


class LogQuery(BaseModel):
    """日志查询"""
    level: Optional[LogLevel] = None
    source: Optional[str] = None
    session_id: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    search: Optional[str] = None


class LogResponse(BaseModel):
    """日志响应"""
    logs: List[LogEntry]
    total: int
    page: int
    page_size: int
    has_more: bool


# ============ 内存日志存储 ============

class InMemoryLogStore:
    """内存日志存储"""

    def __init__(self, max_entries: int = 10000):
        self.max_entries = max_entries
        self.logs = deque(maxlen=max_entries)

    def add(self, entry: LogEntry):
        self.logs.append(entry)

    def query(
        self,
        level: Optional[str] = None,
        source: Optional[str] = None,
        session_id: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 50
    ) -> LogResponse:
        filtered = list(self.logs)

        # 按级别筛选
        if level:
            filtered = [log for log in filtered if log.level == level]

        # 按来源筛选
        if source:
            filtered = [log for log in filtered if log.source == source]

        # 按会话筛选
        if session_id:
            filtered = [log for log in filtered if log.session_id == session_id]

        # 按时间范围筛选
        if start_time:
            filtered = [log for log in filtered
                       if datetime.fromisoformat(log.timestamp) >= start_time]
        if end_time:
            filtered = [log for log in filtered
                       if datetime.fromisoformat(log.timestamp) <= end_time]

        # 按搜索词筛选
        if search:
            search_lower = search.lower()
            filtered = [log for log in filtered
                       if search_lower in log.message.lower()]

        # 排序（最新的在前）
        filtered.sort(key=lambda x: x.timestamp, reverse=True)

        total = len(filtered)

        # 分页
        start = (page - 1) * page_size
        end = start + page_size
        page_logs = filtered[start:end]

        return LogResponse(
            logs=page_logs,
            total=total,
            page=page,
            page_size=page_size,
            has_more=end < total
        )


# 全局日志存储
log_store = InMemoryLogStore()


# ============ 日志工具函数 ============

def log_info(message: str, source: str = "app", session_id: str = None, **extra):
    """记录 INFO 日志"""
    entry = LogEntry(
        timestamp=datetime.now().isoformat(),
        level="INFO",
        message=message,
        source=source,
        session_id=session_id,
        extra=extra if extra else None
    )
    log_store.add(entry)


def log_warning(message: str, source: str = "app", session_id: str = None, **extra):
    """记录 WARNING 日志"""
    entry = LogEntry(
        timestamp=datetime.now().isoformat(),
        level="WARNING",
        message=message,
        source=source,
        session_id=session_id,
        extra=extra if extra else None
    )
    log_store.add(entry)


def log_error(message: str, source: str = "app", session_id: str = None, **extra):
    """记录 ERROR 日志"""
    entry = LogEntry(
        timestamp=datetime.now().isoformat(),
        level="ERROR",
        message=message,
        source=source,
        session_id=session_id,
        extra=extra if extra else None
    )
    log_store.add(entry)


def log_debug(message: str, source: str = "app", session_id: str = None, **extra):
    """记录 DEBUG 日志"""
    entry = LogEntry(
        timestamp=datetime.now().isoformat(),
        level="DEBUG",
        message=message,
        source=source,
        session_id=session_id,
        extra=extra if extra else None
    )
    log_store.add(entry)


# ============ API 端点 ============

@router.get("", response_model=LogResponse)
async def get_logs(
    level: Optional[str] = Query(None, description="日志级别"),
    source: Optional[str] = Query(None, description="日志来源"),
    session_id: Optional[str] = Query(None, description="会话 ID"),
    start_time: Optional[datetime] = Query(None, description="开始时间"),
    end_time: Optional[datetime] = Query(None, description="结束时间"),
    search: Optional[str] = Query(None, description="搜索日志内容"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(50, ge=1, le=200, description="每页数量")
):
    """
    获取日志列表

    支持：
    - 按级别筛选（DEBUG, INFO, WARNING, ERROR）
    - 按来源筛选
    - 按会话筛选
    - 按时间范围筛选
    - 全文搜索
    - 分页
    """
    return log_store.query(
        level=level,
        source=source,
        session_id=session_id,
        start_time=start_time,
        end_time=end_time,
        search=search,
        page=page,
        page_size=page_size
    )


@router.get("/stream")
async def stream_logs(
    level: Optional[str] = Query(None, description="日志级别"),
    session_id: Optional[str] = Query(None, description="会话 ID")
):
    """
    SSE 流式日志

    实时推送新日志条目
    """
    async def event_generator():
        last_index = len(log_store.logs)

        while True:
            try:
                # 检查新日志
                while last_index < len(log_store.logs):
                    entry = log_store.logs[last_index]

                    # 过滤
                    if level and entry.level != level:
                        last_index += 1
                        continue
                    if session_id and entry.session_id != session_id:
                        last_index += 1
                        continue

                    # 发送
                    yield f"data: {json.dumps(entry.model_dump(), ensure_ascii=False)}\n\n"
                    last_index += 1

                await asyncio.sleep(1)  # 1秒检查一次

            except asyncio.CancelledError:
                break

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@router.get("/sources")
async def get_log_sources():
    """
    获取所有日志来源

    返回系统中所有日志来源的列表
    """
    sources = set()
    for log in log_store.logs:
        if log.source:
            sources.add(log.source)

    return {"sources": sorted(list(sources))}


@router.get("/stats")
async def get_log_stats():
    """
    获取日志统计

    返回各级别的日志数量
    """
    stats = {
        "DEBUG": 0,
        "INFO": 0,
        "WARNING": 0,
        "ERROR": 0
    }

    for log in log_store.logs:
        if log.level in stats:
            stats[log.level] += 1

    return {
        "total": len(log_store.logs),
        "by_level": stats
    }


@router.post("/clear")
async def clear_logs():
    """
    清空所有日志

    警告：此操作不可恢复
    """
    log_store.logs.clear()
    return {"status": "ok", "message": "所有日志已清空"}