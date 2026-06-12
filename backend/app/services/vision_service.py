"""
PAI-CC Vision Service
LLM 降噪和画面处理服务
"""
import hashlib
import json
from typing import List, Dict, Optional, Tuple
from datetime import datetime


class VisionService:
    """视觉服务 - 处理画面相似度检测和 prompt 压缩"""

    def __init__(self):
        # session_id -> list of (timestamp, frame_hash)
        self.recent_frames: Dict[str, List[Tuple[datetime, str]]] = {}
        self.max_history_per_session = 50

    # ============ 画面指纹 ============

    def compute_frame_hash(self, image_bytes: bytes) -> str:
        """
        计算画面指纹（简化版感知哈希）

        Args:
            image_bytes: 图像字节数据

        Returns:
            指纹字符串
        """
        # 使用 MD5 作为简化版指纹
        # 实际应用中可以使用更复杂的感知哈希算法
        return hashlib.md5(image_bytes).hexdigest()

    def compute_image_hash(self, image_data) -> str:
        """
        计算图像哈希

        Args:
            image_data: 可以是 bytes, str(path), 或 PIL.Image

        Returns:
            哈希字符串
        """
        if isinstance(image_data, bytes):
            return self.compute_frame_hash(image_data)
        elif isinstance(image_data, str):
            with open(image_data, 'rb') as f:
                return self.compute_frame_hash(f.read())
        else:
            # 假设是 PIL Image
            import io
            buf = io.BytesIO()
            image_data.save(buf, format='PNG')
            return self.compute_frame_hash(buf.getvalue())

    # ============ 重复画面检测 ============

    def is_duplicate(
        self,
        session_id: str,
        frame_hash: str,
        threshold: float = 0.85
    ) -> bool:
        """
        检测是否是重复画面

        Args:
            session_id: 会话 ID
            frame_hash: 当前帧的指纹
            threshold: 相似度阈值（0-1）

        Returns:
            True 如果是重复画面
        """
        if session_id not in self.recent_frames:
            return False

        history = self.recent_frames[session_id]

        # 检查最近 N 帧
        for _, old_hash in history[-10:]:
            similarity = self._calculate_similarity(frame_hash, old_hash)
            if similarity >= threshold:
                return True

        return False

    def _calculate_similarity(self, hash1: str, hash2: str) -> float:
        """
        计算两个哈希的相似度

        使用汉明距离计算相似度

        Args:
            hash1: 第一个哈希
            hash2: 第二个哈希

        Returns:
            相似度（0-1）
        """
        if len(hash1) != len(hash2):
            return 0.0

        # 转换为二进制比较
        diff = sum(c1 != c2 for c1, c2 in zip(hash1, hash2))
        similarity = 1.0 - (diff / len(hash1))

        return similarity

    def record_frame(self, session_id: str, frame_hash: str):
        """
        记录已处理的帧

        Args:
            session_id: 会话 ID
            frame_hash: 帧指纹
        """
        if session_id not in self.recent_frames:
            self.recent_frames[session_id] = []

        self.recent_frames[session_id].append((datetime.now(), frame_hash))

        # 限制历史长度
        if len(self.recent_frames[session_id]) > self.max_history_per_session:
            self.recent_frames[session_id] = self.recent_frames[session_id][-self.max_history_per_session:]

    def clear_session(self, session_id: str):
        """
        清空会话的帧历史

        Args:
            session_id: 会话 ID
        """
        if session_id in self.recent_frames:
            del self.recent_frames[session_id]

    def get_similar_frames(
        self,
        session_id: str,
        frame_hash: str,
        limit: int = 5
    ) -> List[Dict]:
        """
        获取相似的帧列表

        Args:
            session_id: 会话 ID
            frame_hash: 当前帧的指纹
            limit: 返回数量限制

        Returns:
            相似帧列表
        """
        if session_id not in self.recent_frames:
            return []

        similar = []
        for timestamp, old_hash in self.recent_frames[session_id]:
            similarity = self._calculate_similarity(frame_hash, old_hash)
            if similarity >= 0.7:
                similar.append({
                    'timestamp': timestamp.isoformat(),
                    'hash': old_hash,
                    'similarity': similarity
                })

        # 按相似度排序
        similar.sort(key=lambda x: x['similarity'], reverse=True)
        return similar[:limit]

    # ============ Prompt 压缩 ============

    def compress_prompt(
        self,
        evidence: List[str],
        max_tokens: int = 2000
    ) -> str:
        """
        压缩 prompt，控制 token 数量

        Args:
            evidence: 证据列表（可以是题目、答案、分析结果等）
            max_tokens: 最大 token 数（约等于字符数 / 4）

        Args:
            evidence: 证据列表
            max_tokens: 最大 token 数

        Returns:
            压缩后的 prompt
        """
        if not evidence:
            return ""

        # 估算当前 token 数
        current_tokens = sum(len(e) // 4 for e in evidence)

        if current_tokens <= max_tokens:
            return "\n".join(evidence)

        # 需要压缩
        compressed = []
        current_tokens = 0

        for item in evidence:
            item_tokens = len(item) // 4

            if current_tokens + item_tokens <= max_tokens:
                compressed.append(item)
                current_tokens += item_tokens
            else:
                # 截断当前项
                remaining = max_tokens - current_tokens
                truncated = item[:remaining * 4]
                compressed.append(truncated + "...")
                break

        return "\n".join(compressed)

    def summarize_evidence(
        self,
        evidence: List[Dict],
        max_items: int = 10
    ) -> List[Dict]:
        """
        总结证据，提取关键信息

        Args:
            evidence: 证据列表
            max_items: 最大保留项数

        Returns:
            总结后的证据列表
        """
        if len(evidence) <= max_items:
            return evidence

        # 简单策略：保留最新的 N 项
        return evidence[-max_items:]

    # ============ 智能过滤 ============

    def should_process_frame(
        self,
        session_id: str,
        frame_hash: str,
        quality_score: float = 0.5,
        min_quality: float = 0.3
    ) -> Tuple[bool, str]:
        """
        判断是否应该处理当前帧

        Args:
            session_id: 会话 ID
            frame_hash: 帧指纹
            quality_score: 画面质量分数（0-1）
            min_quality: 最低质量要求

        Returns:
            (是否处理, 原因)
        """
        # 检查质量
        if quality_score < min_quality:
            return False, f"quality_too_low ({quality_score:.2f})"

        # 检查重复
        if self.is_duplicate(session_id, frame_hash):
            return False, f"duplicate_frame"

        return True, "ok"

    def filter_captures(
        self,
        session_id: str,
        captures: List[Dict]
    ) -> List[Dict]:
        """
        过滤采集列表，只保留需要处理的帧

        Args:
            session_id: 会话 ID
            captures: 采集列表，每个元素包含 fingerprint, quality_score 等

        Returns:
            过滤后的采集列表
        """
        filtered = []
        processed_hashes = set()

        for capture in captures:
            fingerprint = capture.get('fingerprint', '')
            quality = capture.get('quality_score', 0.5)

            should_process, reason = self.should_process_frame(
                session_id,
                fingerprint,
                quality
            )

            if should_process and fingerprint not in processed_hashes:
                filtered.append(capture)
                processed_hashes.add(fingerprint)
                self.record_frame(session_id, fingerprint)

        return filtered

    # ============ 批量处理优化 ============

    def optimize_batch_processing(
        self,
        captures: List[Dict],
        batch_size: int = 5
    ) -> List[List[Dict]]:
        """
        优化批量处理，将相似的帧分组

        Args:
            captures: 采集列表
            batch_size: 每组最大数量

        Returns:
            分组后的采集列表
        """
        if not captures:
            return []

        groups = []
        current_group = []
        last_hash = None

        for capture in captures:
            fingerprint = capture.get('fingerprint', '')

            if last_hash is None:
                # 第一帧，总是处理
                current_group.append(capture)
                last_hash = fingerprint
            else:
                # 检查是否与上一帧相似
                similarity = self._calculate_similarity(fingerprint, last_hash)

                if similarity >= 0.9:
                    # 非常相似，可能只需要处理一帧
                    # 保留最后一帧，覆盖前面的
                    if len(current_group) <= batch_size // 2:
                        current_group.append(capture)
                    else:
                        # 组已满，开启新组
                        groups.append(current_group)
                        current_group = [capture]
                else:
                    # 不相似，开启新组
                    groups.append(current_group)
                    current_group = [capture]

                last_hash = fingerprint

        # 处理最后一组
        if current_group:
            groups.append(current_group)

        return groups

    # ============ 统计信息 ============

    def get_stats(self, session_id: str) -> Dict:
        """获取会话统计信息"""
        if session_id not in self.recent_frames:
            return {
                "total_frames": 0,
                "unique_frames": 0,
                "duplicate_frames": 0
            }

        history = self.recent_frames[session_id]
        total = len(history)
        unique = len(set(h for _, h in history))

        return {
            "total_frames": total,
            "unique_frames": unique,
            "duplicate_frames": total - unique
        }


# 全局单例
vision_service = VisionService()