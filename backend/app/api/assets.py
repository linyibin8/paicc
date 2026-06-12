"""
PAI-CC Assets API
学习资产管理端点
"""
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from enum import Enum
import uuid

router = APIRouter()


# ============ 数据模型 ============

class MistakeStatus(str, Enum):
    SUSPECTED = "suspected"
    CONFIRMED = "confirmed"
    IGNORED = "ignored"
    CORRECTED = "corrected"
    MASTERED = "mastered"


class ContentType(str, Enum):
    TEXTBOOK = "textbook"
    EXAM = "exam"
    BLANK = "blank"
    OTHER = "other"


class LearningItem(BaseModel):
    """学习条目"""
    item_id: str
    type: str  # question, answer, knowledge_point, note
    subject: Optional[str] = None
    page_number: Optional[str] = None
    question_number: Optional[str] = None
    title: Optional[str] = None
    content: str
    solution: Optional[str] = None
    knowledge_points: List[str] = []
    capture_id: Optional[str] = None
    created_at: str


class MistakeItem(BaseModel):
    """错题条目"""
    mistake_id: str
    subject: Optional[str] = None
    page_number: Optional[str] = None
    question_number: Optional[str] = None
    student_answer: Optional[str] = None
    correct_answer: Optional[str] = None
    error_reason: Optional[str] = None
    knowledge_points: List[str] = []
    correction_suggestion: Optional[str] = None
    status: MistakeStatus = MistakeStatus.SUSPECTED
    capture_id: Optional[str] = None
    created_at: str


class AssetDocument(BaseModel):
    """学习文档"""
    doc_id: str
    title: str
    content: str
    item_ids: List[str] = []
    mistake_ids: List[str] = []
    created_at: str
    updated_at: str


class AssetResponse(BaseModel):
    """资产响应"""
    learning_items: List[LearningItem]
    mistake_items: List[MistakeItem]
    documents: List[AssetDocument]
    total_items: int
    total_mistakes: int
    total_documents: int


class AssetQuery(BaseModel):
    """资产查询参数"""
    subject: Optional[str] = None
    page_number: Optional[str] = None
    question_number: Optional[str] = None
    mistake_status: Optional[MistakeStatus] = None
    content_type: Optional[ContentType] = None
    search: Optional[str] = None
    page: int = 1
    page_size: int = 20


# ============ 内存存储 ============

class AssetStore:
    """资产存储"""

    def __init__(self):
        self.learning_items: List[LearningItem] = []
        self.mistake_items: List[MistakeItem] = []
        self.documents: List[AssetDocument] = []

    def add_learning_item(self, item: LearningItem):
        self.learning_items.append(item)

    def add_mistake_item(self, item: MistakeItem):
        self.mistake_items.append(item)

    def add_document(self, doc: AssetDocument):
        self.documents.append(doc)

    def query(
        self,
        subject: Optional[str] = None,
        page_number: Optional[str] = None,
        question_number: Optional[str] = None,
        mistake_status: Optional[str] = None,
        content_type: Optional[str] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20
    ) -> AssetResponse:
        # 过滤学习条目
        items = list(self.learning_items)
        if subject:
            items = [i for i in items if i.subject == subject]
        if page_number:
            items = [i for i in items if i.page_number == page_number]
        if question_number:
            items = [i for i in items if i.question_number == question_number]
        if search:
            search_lower = search.lower()
            items = [i for i in items
                    if search_lower in i.content.lower() or
                       (i.title and search_lower in i.title.lower())]

        # 过滤错题
        mistakes = list(self.mistake_items)
        if subject:
            mistakes = [m for m in mistakes if m.subject == subject]
        if page_number:
            mistakes = [m for m in mistakes if m.page_number == page_number]
        if question_number:
            mistakes = [m for m in mistakes if m.question_number == question_number]
        if mistake_status:
            mistakes = [m for m in mistakes if m.status.value == mistake_status]
        if search:
            search_lower = search.lower()
            mistakes = [m for m in mistakes
                       if (m.student_answer and search_lower in m.student_answer.lower()) or
                          (m.correct_answer and search_lower in m.correct_answer.lower())]

        # 分页
        start = (page - 1) * page_size
        end = start + page_size
        items_page = items[start:end]
        mistakes_page = mistakes[start:end]

        return AssetResponse(
            learning_items=items_page,
            mistake_items=mistakes_page,
            documents=self.documents,
            total_items=len(items),
            total_mistakes=len(mistakes),
            total_documents=len(self.documents)
        )


# 全局存储
asset_store = AssetStore()


# ============ API 端点 ============

@router.get("", response_model=AssetResponse)
async def get_assets(
    subject: Optional[str] = Query(None, description="科目"),
    page_number: Optional[str] = Query(None, description="页码"),
    question_number: Optional[str] = Query(None, description="题号"),
    mistake_status: Optional[str] = Query(None, description="错题状态"),
    content_type: Optional[str] = Query(None, description="内容类型"),
    search: Optional[str] = Query(None, description="搜索内容"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=100, description="每页数量")
):
    """
    获取学习资产列表

    支持：
    - 按科目筛选
    - 按页码筛选
    - 按题号筛选
    - 按错题状态筛选
    - 按内容类型筛选
    - 全文搜索
    - 分页
    """
    return asset_store.query(
        subject=subject,
        page_number=page_number,
        question_number=question_number,
        mistake_status=mistake_status,
        content_type=content_type,
        search=search,
        page=page,
        page_size=page_size
    )


@router.get("/learning-items")
async def get_learning_items(
    subject: Optional[str] = None,
    page: int = 1,
    page_size: int = 20
):
    """
    获取学习条目列表

    支持分页和按科目筛选
    """
    items = list(asset_store.learning_items)

    if subject:
        items = [i for i in items if i.subject == subject]

    start = (page - 1) * page_size
    end = start + page_size

    return {
        "items": items[start:end],
        "total": len(items),
        "page": page,
        "page_size": page_size
    }


@router.get("/mistakes")
async def get_mistake_items(
    subject: Optional[str] = None,
    status: Optional[str] = None,
    page: int = 1,
    page_size: int = 20
):
    """
    获取错题列表

    支持分页和按状态筛选
    """
    mistakes = list(asset_store.mistake_items)

    if subject:
        mistakes = [m for m in mistakes if m.subject == subject]
    if status:
        mistakes = [m for m in mistakes if m.status.value == status]

    start = (page - 1) * page_size
    end = start + page_size

    return {
        "mistakes": mistakes[start:end],
        "total": len(mistakes),
        "page": page,
        "page_size": page_size
    }


@router.get("/learning-items/{item_id}")
async def get_learning_item(item_id: str):
    """获取单个学习条目"""
    for item in asset_store.learning_items:
        if item.item_id == item_id:
            return item
    raise HTTPException(status_code=404, detail="Learning item not found")


@router.get("/mistakes/{mistake_id}")
async def get_mistake_item(mistake_id: str):
    """获取单个错题"""
    for mistake in asset_store.mistake_items:
        if mistake.mistake_id == mistake_id:
            return mistake
    raise HTTPException(status_code=404, detail="Mistake item not found")


@router.post("/learning-items")
async def create_learning_item(
    type: str = Query(..., description="类型"),
    content: str = Query(..., description="内容"),
    subject: Optional[str] = Query(None, description="科目"),
    page_number: Optional[str] = Query(None, description="页码"),
    question_number: Optional[str] = Query(None, description="题号"),
    title: Optional[str] = Query(None, description="标题"),
    solution: Optional[str] = Query(None, description="解答"),
    knowledge_points: Optional[str] = Query(None, description="知识点（逗号分隔）"),
    capture_id: Optional[str] = Query(None, description="采集 ID")
):
    """
    创建学习条目

    从拍题结果中提取学习条目
    """
    item = LearningItem(
        item_id=f"item_{uuid.uuid4().hex[:12]}",
        type=type,
        subject=subject,
        page_number=page_number,
        question_number=question_number,
        title=title,
        content=content,
        solution=solution,
        knowledge_points=knowledge_points.split(",") if knowledge_points else [],
        capture_id=capture_id,
        created_at=datetime.now().isoformat()
    )

    asset_store.add_learning_item(item)
    return item


@router.post("/mistakes")
async def create_mistake_item(
    subject: Optional[str] = Query(None, description="科目"),
    page_number: Optional[str] = Query(None, description="页码"),
    question_number: Optional[str] = Query(None, description="题号"),
    student_answer: Optional[str] = Query(None, description="学生答案"),
    correct_answer: Optional[str] = Query(None, description="正确答案"),
    error_reason: Optional[str] = Query(None, description="错误原因"),
    knowledge_points: Optional[str] = Query(None, description="知识点（逗号分隔）"),
    correction_suggestion: Optional[str] = Query(None, description="订正建议"),
    capture_id: Optional[str] = Query(None, description="采集 ID")
):
    """
    创建错题条目

    从拍题结果中提取错题
    """
    item = MistakeItem(
        mistake_id=f"mist_{uuid.uuid4().hex[:12]}",
        subject=subject,
        page_number=page_number,
        question_number=question_number,
        student_answer=student_answer,
        correct_answer=correct_answer,
        error_reason=error_reason,
        knowledge_points=knowledge_points.split(",") if knowledge_points else [],
        correction_suggestion=correction_suggestion,
        status=MistakeStatus.SUSPECTED,
        capture_id=capture_id,
        created_at=datetime.now().isoformat()
    )

    asset_store.add_mistake_item(item)
    return item


@router.put("/mistakes/{mistake_id}/status")
async def update_mistake_status(
    mistake_id: str,
    status: str = Query(..., description="状态")
):
    """更新错题状态"""
    for mistake in asset_store.mistake_items:
        if mistake.mistake_id == mistake_id:
            mistake.status = MistakeStatus(status)
            return mistake

    raise HTTPException(status_code=404, detail="Mistake not found")


@router.get("/stats")
async def get_asset_stats():
    """获取资产统计"""
    subjects = set()
    knowledge_points_all = []
    mistake_subjects = set()
    mistake_by_status = {
        "suspected": 0,
        "confirmed": 0,
        "ignored": 0,
        "corrected": 0,
        "mastered": 0
    }

    for item in asset_store.learning_items:
        if item.subject:
            subjects.add(item.subject)
        knowledge_points_all.extend(item.knowledge_points)

    for mistake in asset_store.mistake_items:
        if mistake.subject:
            mistake_subjects.add(mistake.subject)
        if mistake.status.value in mistake_by_status:
            mistake_by_status[mistake.status.value] += 1

    return {
        "total_learning_items": len(asset_store.learning_items),
        "total_mistakes": len(asset_store.mistake_items),
        "total_documents": len(asset_store.documents),
        "subjects": list(subjects),
        "mistake_subjects": list(mistake_subjects),
        "mistake_by_status": mistake_by_status,
        "top_knowledge_points": knowledge_points_all[:20]
    }