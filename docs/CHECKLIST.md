# PAI-CC 功能对齐检查表

**更新日期**：2026-06-14
**检查人**：Claude

---

## 一、需求覆盖检查

### 1.1 产品核心功能

| 需求 | 描述 | 代码实现 | 后端 API | iOS | 状态 |
|------|------|----------|----------|-----|------|
| 拍题解析 | 识别题目、学生作答、草稿、订正 | ✅ qa.py | ✅ /qa/ask | ✅ CameraService | ✅ |
| 智能连拍 | 自动过滤无效画面，记录关键帧 | ✅ CaptureService | ✅ /captures/ | ✅ CaptureService | ✅ |
| 语音问答 | 语音提问+多轮对话+上下文 | ✅ qa.py | ✅ /qa/ws | ✅ VoiceService | ✅ |
| 手势识别 | 指向截取、OK打断、✌️结束 | ✅ GestureService | N/A | ✅ GestureService | ✅ |
| TTS 朗读 | 语音播报答案 | ✅ tts_service.py | ✅ /tts/synthesize | ✅ VoiceService | ✅ |
| 学习报告 | 会话报告生成 | ✅ sessions.py | ✅ /sessions/ | ✅ | ✅ |
| 学习清单 | 题目、知识点整理 | ✅ sessions.py | ✅ | ✅ | ⚠️ 部分 |
| 错题候选 | 状态管理（疑似/确认/忽略/订正/掌握）| ✅ mistakes.py | ✅ /mistakes/ | ✅ | ✅ |
| 复习队列 | SM-2 间隔重复算法 | ✅ review_queue.py | ✅ /review-queue/ | ✅ | ⚠️ 内存存储 |
| 学习画像 | 长期学习统计 | ✅ student_profile.py | ✅ /student-profile/ | ✅ | ⚠️ 内存存储 |
| Web Dashboard | 数据查看管理 | ✅ web/ | ✅ /dashboard/ | N/A | ✅ |

### 1.2 体验原则

| 原则 | 对应实现 | 状态 |
|------|----------|------|
| 学生不需要理解复杂操作 | 简单 UI，一键拍题 | ✅ |
| 系统告诉用户当前在做什么 | TTS 状态提示 | ✅ |
| 看不清不编造 | quality_score 检测 | ✅ |
| 无关画面不进入报告 | 自动过滤 | ✅ |
| 不用羞辱式反馈 | AI 回复策略 | ✅ |
| 家长结论可追溯 | 原始图片关联 | ✅ |

---

## 二、发布状态检查

### 2.1 后端服务

| 服务 | 地址 | 状态 | 检查时间 |
|------|------|------|----------|
| 后端主服务 | 100.64.0.13:8030 | ✅ 运行中 | 2026-06-14 |
| Ollama AI | 100.64.0.5:39000 | ✅ 运行中 | - |
| Kokoro TTS | 127.0.0.1:8880 | ✅ 运行中 | - |
| Web Dashboard | /web/ | ✅ 可访问 | - |

### 2.2 后端 API 端点

| API | 端点 | 状态 |
|-----|------|------|
| 健康检查 | /health | ✅ |
| 会话管理 | /api/v1/sessions/ | ✅ |
| 画面采集 | /api/v1/captures/ | ✅ |
| AI 问答 | /api/v1/qa/ask | ✅ |
| WebSocket 问答 | /api/v1/qa/ws/{session_id} | ✅ |
| TTS 语音合成 | /api/v1/tts/synthesize | ✅ |
| 错题管理 | /api/v1/mistakes/ | ✅ |
| 复习队列 | /api/v1/review-queue/ | ✅ |
| 学生画像 | /api/v1/student-profile/ | ⚠️ 有报错 |
| Dashboard | /api/v1/dashboard/ | ✅ |
| 可观测性 | /api/v1/observability/ | ✅ |
| 日志 | /api/v1/logs/ | ✅ |
| 学习资产 | /api/v1/assets/ | ✅ |

### 2.3 iOS App

| 项目 | 状态 |
|------|------|
| Bundle ID | com.evowit.paicc |
| Version | 1.1.0 |
| Build | 2026061401 |
| iOS 最低版本 | 16.0 |
| TestFlight 发布 | ✅ 已发布 |
| 测试组 | PAICC Internal |

---

## 三、待修复问题

### 3.1 高优先级 🔴

| 问题 | 影响 | 修复方案 |
|------|------|----------|
| 学生画像 API 报错 | 部分功能不可用 | 检查 student_profile.py |
| 错题/复习/画像使用内存存储 | 重启数据丢失 | 迁移到 SQLite |

### 3.2 中优先级 🟡

| 问题 | 影响 | 修复方案 |
|------|------|----------|
| 学习清单部分实现 | 功能不完整 | 完善 LearningItem 相关 API |
| Web Dashboard 部分页面 | 用户体验 | 优化 UI |

---

## 四、版本信息

| 项目 | 版本 | 发布日期 |
|------|------|----------|
| 后端 | 2.0.0 | - |
| iOS App | 1.1.0 | 2026-06-14 |
| PRD 文档 | 1.5.0 | 2026-06-14 |

---

## 五、下一步行动

### 立即修复
1. 调查并修复学生画像 API 报错
2. 将错题/复习/画像迁移到数据库

### 后续迭代
1. v1.2.0 - 用户系统
2. v1.3.0 - 数据隔离
3. v1.4.0 - 管理功能

---

**检查完成时间**：2026-06-14 07:10
