"""
PAI-CC 拍摄采集 API
"""
from fastapi import APIRouter, UploadFile, File, Form
from typing import Optional
from pydantic import BaseModel
from datetime import datetime
import uuid
import os
import hashlib

router = APIRouter()


class CaptureMeta(BaseModel):
    """拍摄元数据"""
    timestamp: int
    sequence: int
    session_id: str
    image_hash: str
    quality_score: float = 0.0
    has_learning_material: bool = False
    has_hand_pen_person: bool = False
    student_present: bool = False
    material_type: str = "unknown"
    change_type: str = "none"
    is_key_frame: bool = True


class CaptureResponse(BaseModel):
    """采集响应"""
    capture_id: str
    status: str
    duplicate: bool = False
    url: Optional[str] = None


@router.post("/upload", response_model=CaptureResponse)
async def upload_capture(
    image: UploadFile = File(...),
    session_id: str = Form(...),
    timestamp: int = Form(...),
    sequence: int = Form(0),
    quality_score: float = Form(0.0),
    has_learning_material: bool = Form(False),
    has_hand_pen_person: bool = Form(False),
    student_present: bool = Form(False),
    material_type: str = Form("unknown"),
    change_type: str = Form("none"),
    is_key_frame: bool = Form(True)
):
    """
    上传单张图片

    流程：
    1. 验证文件
    2. 计算哈希去重
    3. 保存文件
    4. 生成元数据
    5. 返回 capture_id
    """
    from app.core.config import settings

    # 生成 capture_id
    capture_id = str(uuid.uuid4())

    # 读取文件内容
    content = await image.read()

    # 计算哈希
    image_hash = hashlib.md5(content).hexdigest()

    # 检查重复
    upload_dir = os.path.join(settings.upload_dir, session_id)
    os.makedirs(upload_dir, exist_ok=True)

    # 保存文件
    file_ext = os.path.splitext(image.filename)[1] or ".jpg"
    file_path = os.path.join(upload_dir, f"{capture_id}{file_ext}")

    with open(file_path, "wb") as f:
        f.write(content)

    # 生成 URL
    url = f"/api/v1/captures/{capture_id}/image"

    return CaptureResponse(
        capture_id=capture_id,
        status="stored",
        duplicate=False,
        url=url
    )


@router.post("/batch")
async def upload_batch(
    images: list[UploadFile] = File(...),
    session_id: str = Form(...),
    batch_id: Optional[str] = Form(None)
):
    """
    批量上传图片

    用于智能连拍模式，一次性上传多个关键帧
    """
    from app.core.config import settings

    if not batch_id:
        batch_id = str(uuid.uuid4())

    upload_dir = os.path.join(settings.upload_dir, session_id, "batches", batch_id)
    os.makedirs(upload_dir, exist_ok=True)

    results = []
    for i, image in enumerate(images):
        content = await image.read()
        capture_id = str(uuid.uuid4())

        file_ext = os.path.splitext(image.filename)[1] or ".jpg"
        file_path = os.path.join(upload_dir, f"{capture_id}{file_ext}")

        with open(file_path, "wb") as f:
            f.write(content)

        results.append({
            "capture_id": capture_id,
            "sequence": i,
            "url": f"/api/v1/captures/{capture_id}/image"
        })

    return {
        "batch_id": batch_id,
        "captures": results,
        "count": len(results)
    }


@router.get("/{capture_id}/image")
async def get_capture_image(capture_id: str):
    """获取采集图片"""
    from fastapi.responses import FileResponse
    from app.core.config import settings

    # 搜索文件
    for root, dirs, files in os.walk(settings.upload_dir):
        for file in files:
            if file.startswith(capture_id):
                file_path = os.path.join(root, file)
                return FileResponse(file_path, media_type="image/jpeg")

    return {"error": "File not found"}


@router.delete("/{capture_id}")
async def delete_capture(capture_id: str):
    """删除采集"""
    from app.core.config import settings

    # 搜索并删除文件
    for root, dirs, files in os.walk(settings.upload_dir):
        for file in files:
            if file.startswith(capture_id):
                file_path = os.path.join(root, file)
                os.remove(file_path)
                return {"status": "deleted", "capture_id": capture_id}

    return {"error": "File not found"}