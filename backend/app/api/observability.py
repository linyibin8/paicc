"""
PAI-CC Observability API
系统可观测性端点
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Dict, Optional
from datetime import datetime, timedelta
import os
import shutil

from app.core.config import settings

router = APIRouter()


# ============ 数据模型 ============

class StorageStats(BaseModel):
    """存储统计"""
    total_size_bytes: int
    total_size_formatted: str
    file_count: int
    audio_count: int
    captures_count: int
    uploads_free_bytes: Optional[int] = None


class APIStats(BaseModel):
    """API 调用统计"""
    total_requests: int
    qa_requests: int
    capture_requests: int
    tts_requests: int
    session_count: int


class LLMStats(BaseModel):
    """LLM 统计"""
    status: str  # healthy, degraded, down
    total_calls: int
    failed_calls: int
    avg_response_time_ms: float
    last_call_time: Optional[str] = None


class TaskStats(BaseModel):
    """后台任务统计"""
    pending: int
    running: int
    failed: int
    completed_today: int


class ObservabilityResponse(BaseModel):
    """可观测性响应"""
    timestamp: str
    storage: StorageStats
    api: APIStats
    llm: LLMStats
    tasks: TaskStats


# ============ 全局计数器 ============

class StatsCollector:
    """统计收集器"""

    def __init__(self):
        self.qa_requests = 0
        self.capture_requests = 0
        self.tts_requests = 0
        self.session_count = 0
        self.llm_calls = 0
        self.llm_failed_calls = 0
        self.task_runs = {"pending": 0, "running": 0, "failed": 0, "completed_today": 0}
        self.last_llm_call = None

    def record_qa(self):
        self.qa_requests += 1

    def record_capture(self):
        self.capture_requests += 1

    def record_tts(self):
        self.tts_requests += 1

    def record_session(self):
        self.session_count += 1

    def record_llm_call(self, success: bool = True):
        self.llm_calls += 1
        self.last_llm_call = datetime.now().isoformat()
        if not success:
            self.llm_failed_calls += 1

    def record_task(self, status: str):
        if status in self.task_runs:
            self.task_runs[status] += 1


stats = StatsCollector()


# ============ API 端点 ============

@router.get("/stats", response_model=ObservabilityResponse)
async def get_observability_stats():
    """
    获取系统可观测性统计

    返回：
    - 存储统计
    - API 调用统计
    - LLM 状态
    - 后台任务状态
    """
    # 获取存储统计
    upload_dir = settings.upload_dir
    total_size = 0
    file_count = 0
    audio_count = 0
    captures_count = 0

    if os.path.exists(upload_dir):
        for root, dirs, files in os.walk(upload_dir):
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    total_size += os.path.getsize(file_path)
                    file_count += 1

                    # 分类统计
                    if "audio" in root:
                        audio_count += 1
                    elif "captures" in root:
                        captures_count += 1
                except:
                    pass

    # 获取磁盘空间
    try:
        stat = shutil.disk_usage(upload_dir)
        free_bytes = stat.free
    except:
        free_bytes = None

    # 格式化大小
    def format_size(size):
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size < 1024:
                return f"{size:.2f} {unit}"
            size /= 1024
        return f"{size:.2f} PB"

    storage = StorageStats(
        total_size_bytes=total_size,
        total_size_formatted=format_size(total_size),
        file_count=file_count,
        audio_count=audio_count,
        captures_count=captures_count,
        uploads_free_bytes=free_bytes
    )

    # API 统计
    api = APIStats(
        total_requests=stats.qa_requests + stats.capture_requests + stats.tts_requests,
        qa_requests=stats.qa_requests,
        capture_requests=stats.capture_requests,
        tts_requests=stats.tts_requests,
        session_count=stats.session_count
    )

    # LLM 统计
    llm_status = "healthy"
    if stats.llm_calls > 0:
        failure_rate = stats.llm_failed_calls / stats.llm_calls
        if failure_rate > 0.1:
            llm_status = "degraded"
        if failure_rate > 0.5:
            llm_status = "down"

    avg_response_time = 0  # 简化，实际应该记录每个调用的响应时间

    llm = LLMStats(
        status=llm_status,
        total_calls=stats.llm_calls,
        failed_calls=stats.llm_failed_calls,
        avg_response_time_ms=avg_response_time,
        last_call_time=stats.last_llm_call
    )

    # 任务统计
    tasks = TaskStats(
        pending=stats.task_runs["pending"],
        running=stats.task_runs["running"],
        failed=stats.task_runs["failed"],
        completed_today=stats.task_runs["completed_today"]
    )

    return ObservabilityResponse(
        timestamp=datetime.now().isoformat(),
        storage=storage,
        api=api,
        llm=llm,
        tasks=tasks
    )


@router.get("/health")
async def health_check():
    """
    健康检查

    返回系统各组件的健康状态
    """
    health = {
        "status": "healthy",
        "components": {
            "api": "healthy",
            "llm": "unknown",
            "tts": "unknown",
            "storage": "unknown"
        },
        "timestamp": datetime.now().isoformat()
    }

    # 检查存储
    try:
        if os.path.exists(settings.upload_dir):
            health["components"]["storage"] = "healthy"
        else:
            health["components"]["storage"] = "warning"
            health["status"] = "degraded"
    except:
        health["components"]["storage"] = "error"
        health["status"] = "unhealthy"

    return health


@router.get("/metrics")
async def get_metrics():
    """
    获取 Prometheus 格式的指标

    用于监控系统集成
    """
    metrics = f"""# HELP pai_cc_total_requests Total API requests
# TYPE pai_cc_total_requests counter
pai_cc_total_requests {stats.qa_requests + stats.capture_requests + stats.tts_requests}

# HELP pai_cc_qa_requests QA API requests
# TYPE pai_cc_qa_requests counter
pai_cc_qa_requests {stats.qa_requests}

# HELP pai_cc_capture_requests Capture API requests
# TYPE pai_cc_capture_requests counter
pai_cc_capture_requests {stats.capture_requests}

# HELP pai_cc_llm_calls Total LLM calls
# TYPE pai_cc_llm_calls counter
pai_cc_llm_calls {stats.llm_calls}

# HELP pai_cc_llm_failed_calls Failed LLM calls
# TYPE pai_cc_llm_failed_calls counter
pai_cc_llm_failed_calls {stats.llm_failed_calls}

# HELP pai_cc_sessions Total sessions
# TYPE pai_cc_sessions gauge
pai_cc_sessions {stats.session_count}
"""

    return Response(content=metrics, media_type="text/plain")