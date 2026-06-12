"""
PAI-CC 图像采集 API
支持单张拍题和智能连拍
"""
from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
import uuid
import base64
import os
from datetime import datetime

from app.models.database import get_db
from app.core.config import settings
from app.services.ollama_service import ollama_service

router = APIRouter()


class CaptureMeta(BaseModel):
    """采集元数据"""
    sequence: int
    frame_fingerprint: str
    quality_score: float
    student_present: bool
    content_type: str = "new"  # new, page_turn, writing, erasing, blank


class CaptureResponse(BaseModel):
    """采集响应"""
    capture_id: str
    image_url: str
    analysis: Optional[dict] = None
    timestamp: datetime


@router.post("/", response_model=CaptureResponse)
async def upload_capture(
    image: UploadFile = File(...),
    session_id: str = Form(...),
    sequence: int = Form(...),
    frame_fingerprint: str = Form(...),
    quality_score: float = Form(0.0),
    student_present: bool = Form(False),
    content_type: str = Form("new"),
    db: Session = Depends(get_db)
):
    """
    上传单张图像

    流程：
    1. 验证会话
    2. 保存图片
    3. 生成元数据
    4. 入库
    5. 触发 LLM 分析（可选）
    """
    # 生成 ID
    capture_id = f"cap_{uuid.uuid4().hex[:12]}"

    # 保存图片
    timestamp = datetime.now()
    filename = f"{capture_id}_{timestamp.strftime('%Y%m%d%H%M%S')}.jpg"
    filepath = os.path.join(settings.upload_dir, "captures", session_id)
    os.makedirs(filepath, exist_ok=True)
    full_path = os.path.join(filepath, filename)

    with open(full_path, "wb") as f:
        content = await image.read()
        f.write(content)

    # 保存到数据库
    from app.models.models import Capture

    capture = Capture(
        capture_id=capture_id,
        session_id=None,  # 后续关联
        sequence=sequence,
        timestamp=timestamp,
        frame_fingerprint=frame_fingerprint,
        quality_score=quality_score,
        student_present=student_present,
        content_type=content_type,
        image_path=full_path
    )

    db.add(capture)
    db.commit()

    return CaptureResponse(
        capture_id=capture_id,
        image_url=f"/uploads/captures/{session_id}/{filename}",
        analysis=None,
        timestamp=timestamp
    )


@router.post("/batch")
async def upload_batch(
    images: List[UploadFile] = File(...),
    session_id: str = Form(...),
    db: Session = Depends(get_db)
):
    """
    批量上传图像

    用于智能连拍模式，一次性上传多个关键帧
    """
    results = []

    for idx, image in enumerate(images):
        capture_id = f"cap_{uuid.uuid4().hex[:12]}"
        timestamp = datetime.now()
        filename = f"{capture_id}_{timestamp.strftime('%Y%m%d%H%M%S')}.jpg"
        filepath = os.path.join(settings.upload_dir, "captures", session_id)
        os.makedirs(filepath, exist_ok=True)
        full_path = os.path.join(filepath, filename)

        with open(full_path, "wb") as f:
            content = await image.read()
            f.write(content)

        results.append({
            "capture_id": capture_id,
            "sequence": idx,
            "image_url": f"/uploads/captures/{session_id}/{filename}",
            "timestamp": timestamp.isoformat()
        })

    return {"captures": results, "count": len(results)}


@router.post("/analyze/{capture_id}")
async def analyze_capture(
    capture_id: str,
    db: Session = Depends(get_db)
):
    """
    分析单个采集图像

    调用 LLM 提取学习内容
    """
    from app.models.models import Capture

    capture = db.query(Capture).filter(Capture.capture_id == capture_id).first()
    if not capture:
        raise HTTPException(status_code=404, detail="Capture not found")

    if not capture.image_path or not os.path.exists(capture.image_path):
        raise HTTPException(status_code=404, detail="Image file not found")

    # 读取图片并转 base64
    with open(capture.image_path, "rb") as f:
        image_base64 = base64.b64encode(f.read()).decode()

    # 调用 LLM 分析
    result = await ollama_service.extract_learning_items(image_base64, capture_id)

    # 更新数据库
    capture.analysis = result
    db.commit()

    return {
        "capture_id": capture_id,
        "analysis": result
    }


@router.get("/{capture_id}")
async def get_capture(
    capture_id: str,
    db: Session = Depends(get_db)
):
    """获取单个采集"""
    from app.models.models import Capture

    capture = db.query(Capture).filter(Capture.capture_id == capture_id).first()
    if not capture:
        raise HTTPException(status_code=404, detail="Capture not found")

    return {
        "capture_id": capture.capture_id,
        "sequence": capture.sequence,
        "timestamp": capture.timestamp,
        "quality_score": capture.quality_score,
        "student_present": capture.student_present,
        "content_type": capture.content_type,
        "image_url": f"/uploads/{capture.image_path}" if capture.image_path else None,
        "analysis": capture.analysis
    }


@router.get("/session/{session_id}")
async def get_session_captures(
    session_id: str,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """获取会话的所有采集"""
    from app.models.models import Capture, Session

    session = db.query(Session).filter(Session.session_id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    captures = db.query(Capture).filter(
        Capture.session_id == session.id
    ).offset(skip).limit(limit).all()

    return {
        "session_id": session_id,
        "captures": [
            {
                "capture_id": c.capture_id,
                "sequence": c.sequence,
                "timestamp": c.timestamp,
                "image_url": f"/uploads/{c.image_path}" if c.image_path else None
            }
            for c in captures
        ],
        "total": len(captures)
    }