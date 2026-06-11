# PAI-CC V3.0 项目规划 - 学习伙伴 AI 伴侣

## 项目概述

**项目名称**：StudyMate AI（学习伙伴）
**产品定位**：面向学生的学习陪伴 AI 伴侣，实时观察课本/试卷，持续待命响应学生问题
**核心价值**：单摄持续观察 + 多模态交互（语音/手势/视觉）+ 实时 AI 问答 + 学习闭环

## 核心功能模块

### 1. 多模态感知系统
- **实时视觉采集**：iPhone 摄像头持续观察学习场景
- **手势识别**：食指指向截取题目、👌打断追问、✌️结束
- **语音识别**：中文语音输入，3秒沉默自动结束
- **画面质量检测**：自动判断学习材料入镜、学生在场

### 2. AI 问答引擎
- **多轮对话**：WebSocket 持续对话，支持打断和追问
- **视觉上下文**：当前画面 + 页面上下文 + 对话历史
- **TTS 语音播报**：流式合成，即时响应
- **思考音反馈**：AI 思考时播放提示音

### 3. 学习流程编排
```
扫描中 → 手势触发 → TTS"请说" → 语音输入 → 思考音 → AI分析 → TTS播报 → 自动消失
```

### 4. 后端服务
- **FastAPI REST API**：问答、图片上传、TTS 合成
- **WebSocket**：实时多轮对话
- **Ollama LLM**：视觉理解 + 自然语言生成
- **TTS 服务**：流式语音合成

## 技术架构

### iOS App（Xcode）
- **CameraService**：相机采集和画面帧处理
- **GestureService**：Vision 手势识别（连续4帧）
- **VoiceService**：Speech 语音识别 + AVSpeech TTS
- **QAService**：问答状态机和多轮对话管理
- **QAOverlayView**：问答浮层 UI

### 后端（Python/FastAPI）
- `/api/qa/ask`：REST 问答接口
- `/api/qa/ws/{session_id}`：WebSocket 实时问答
- `/api/tts/synthesize`：TTS 语音合成
- `/api/captures`：图片上传和批次管理

## 开发任务清单

### 阶段一：项目初始化
- [ ] 创建 GitHub 仓库
- [ ] 搭建 iOS 项目结构
- [ ] 搭建后端项目结构
- [ ] 配置域名和证书

### 阶段二：核心功能开发
- [ ] iOS 相机服务
- [ ] iOS 手势识别
- [ ] iOS 语音识别 + TTS
- [ ] iOS 问答服务
- [ ] 后端问答 API
- [ ] 后端 TTS 服务

### 阶段三：集成测试
- [ ] iOS 端到端测试
- [ ] 后端 API 测试
- [ ] WebSocket 多轮对话测试

### 阶段四：发布
- [ ] iOS TestFlight 发布
- [ ] 后端部署
- [ ] 域名配置

## 资源清单

### 计算资源
- **开发 PC**：100.64.0.2 / 100.64.0.3
- **GPU 服务器**：100.64.0.5（Ollama evowit-agent27b）
- **后端服务器**：100.64.0.13（Ubuntu）
- **VPS**：159.75.178.237（腾讯云广州）
- **Mac 构建机**：100.64.0.6（macstar）

### API 配置
- **Ollama Base URL**：http://100.64.0.5:39000/v1
- **Ollama API Key**：ollama
- **Ollama Model**：evowit-agent27b

## Agent 分工

| Agent | 职责 |
|-------|------|
| 分析员 | 扫描代码结构，识别模块依赖 |
| 架构师 | 设计服务边界和 API 接口 |
| iOS 开发 | iOS App 全部功能 |
| 后端开发 | FastAPI + Ollama + TTS |
| 测试验证 | 功能完整性检查 |

## 进度追踪

- 创建时间：2026-06-11
- 当前状态：规划中