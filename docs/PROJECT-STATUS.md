# PAI-CC 项目状态报告

**更新时间**: 2026-06-12

## 项目概述

**PAI-CC** 是一个面向学生学习陪伴的拍题/智能连拍辅助系统。iPhone 作为固定或手持摄像端，持续观察课本、试卷或屏幕学习场景，自动上传关键画面到后端。后端保存图片、日志、时间线和大模型分析结果，并生成学习回合报告、错题候选、知识点清单、复习队列和长期画像。

### 核心价值

- **单张拍题解析**: 拍一张题目或学习材料，后台用视觉大模型提取题干、学生作答、草稿、订正、清晰度和易错点
- **智能连拍学习回合**: iOS 端不重复上传无变化画面，只在学习材料出现、页面/文字/动作有变化时保存关键帧
- **AI 问答**: 支持语音指令和手势识别，实时响应学生的问题
- **TTS 语音合成**: AI 回答后自动语音播报
- **错题复习生命周期**: 错题可确认、忽略、订正、掌握，并记录复习事件
- **Web Dashboard**: 管理端提供会话管理、错题管理、复习队列、学生画像等功能

## 系统架构

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│   后端服务        │────▶│   Ollama LLM    │
│  (PAICC)        │     │  FastAPI         │     │  (100.64.0.5)   │
│                 │     │  (100.64.0.13)   │     │                 │
│  - 手势识别     │     │                  │     └─────────────────┘
│  - 语音识别     │     │  - REST API      │     ┌─────────────────┐
│  - TTS 播报     │     │  - WebSocket     │────▶│   Kokoro TTS    │
│  - AI 问答      │     │  - SQLite DB     │     │   (100.64.0.13) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │
         └───────────────────────┘
                  │
         ┌─────────────────┐
         │  Web Dashboard  │
         │  /web/          │
         └─────────────────┘
```

## 部署状态

### 后端服务 ✅
- **地址**: http://100.64.0.13:8030
- **域名**: http://paicc.evowit.com:8030
- **状态**: 健康运行
- **端口**: 8030
- **数据库**: SQLite (paicc.db)

### API 端点
| 端点 | 状态 | 说明 |
|------|------|------|
| `GET /health` | ✅ | 健康检查 |
| `POST /api/v1/sessions/` | ✅ | 创建会话 |
| `POST /api/v1/qa/ask` | ✅ | REST 问答 |
| `WebSocket /api/v1/qa/ws/{session_id}` | ✅ | WebSocket 问答 |
| `POST /api/v1/tts/synthesize` | ✅ | TTS 语音合成 |
| `GET /web/` | ✅ | Web Dashboard |

### Web Dashboard ✅
- **地址**: http://100.64.0.13:8030/web/
- **功能**: Dashboard 概览、会话管理、错题管理、复习队列、学生画像、提示词配置

### iOS 应用 ✅
- **Bundle ID**: com.evowit.paicc
- **部署目标**: iOS 16.0+
- **IPA 路径**: `/home/ydz/projects/pai-cc/ios/PAICC.ipa`
- **编译状态**: BUILD SUCCEEDED

## AI 问答流程

```
扫描中 → 用户伸出食指指向课本上的题目
    ↓
系统检测到指向手势（连续稳定 4 帧）
    ↓
截取当前帧
    ↓
TTS 说 "请说" → 麦克风打开
    ↓
用户说 "这道题怎么做？" → 3 秒沉默自动结束
    ↓
TTS 说 "好的" → 思考音开始播放
    ↓
图片 + 上下文页面 + 语音文本 → 后端 AI
    ↓
收到回答 → 停止思考音 → TTS 朗读答案
    ↓
15 秒后浮层自动消失
    ↓
用户可随时 👌 OK 打断并追问 → 或 ✌️ 结束本轮
```

## 手势识别

| 手势 | 描述 | 功能 |
|------|------|------|
| 食指指向 | 食指伸直，其他手指弯曲 | 截取当前帧，开始问答 |
| OK 手势 | 拇指和食指相触 | 打断当前问答 |
| ✌️ 手势 | 食指和中指伸直 | 结束本轮问答 |
| 举手 | 所有手指伸直 | 举手信号 |

## 已完成功能 ✅

### iOS 端
- [x] 手势识别服务 (GestureService)
- [x] 语音识别服务 (VoiceService)
- [x] TTS 语音合成
- [x] AI 问答服务 (QAService)
- [x] WebSocket 客户端
- [x] 问答浮层 UI
- [x] 相机采集服务
- [x] 会话管理

### 后端
- [x] QA API（REST + WebSocket）
- [x] 会话管理 API
- [x] 错题管理 API
- [x] 复习队列 API
- [x] TTS 语音合成 API
- [x] 学生画像 API
- [x] Dashboard API
- [x] 日志 API
- [x] 学习资产 API
- [x] Web Dashboard 前端

## 待完成/已知问题

### 1. iOS TestFlight 发布
- **问题**: 需要 Apple Developer 账号和 macOS 构建机
- **状态**: IPA 已编译，需要在 Mac 构建机 (100.64.0.6) 上传
- **解决方案**: 在 Mac 上使用 Xcode 组织者上传到 App Store Connect

### 2. 域名配置
- **问题**: paicc.evowit.com 指向可能未更新
- **状态**: 后端使用内网 IP 100.64.0.13 正常
- **解决方案**: 检查腾讯云 DNS 配置

### 3. iOS 端到端测试
- **问题**: 未在真实设备上测试完整流程
- **状态**: WebSocket 连接已修复，需要真机测试
- **解决方案**: 部署 TestFlight 后测试

## 运维命令

### 启动后端服务
```bash
cd /home/ydz/projects/pai-cc/backend
source venv/bin/activate
export PYTHONPATH=/home/ydz/projects/pai-cc/backend
nohup python -m uvicorn app.main:app --host 0.0.0.0 --port 8030 > app.log 2>&1 &
```

### 重启后端服务
```bash
ssh ydz@100.64.0.13 "pkill -f 'uvicorn.*8030'; sleep 2; cd /home/ydz/projects/pai-cc/backend && source venv/bin/activate && nohup python -m uvicorn app.main:app --host 0.0.0.0 --port 8030 > app.log 2>&1 &"
```

### 健康检查
```bash
curl http://100.64.0.13:8030/health
```

### 查看后端日志
```bash
ssh ydz@100.64.0.13 "tail -f /home/ydz/projects/pai-cc/backend/app.log"
```

### iOS 项目编译
```bash
cd ~/projects/PAICC
xcodegen generate
xcodebuild -project PAICC.xcodeproj -scheme PAICC \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  build
```

## 最近更新

### 2026-06-12
1. **修复 WebSocket connect 消息处理**
   - 后端 qa.py 添加了对 `connect` 类型消息的处理
   - 修复后 iOS 客户端可以正确接收连接成功响应

2. **验证后端服务健康**
   - 后端正确监听 8030 端口
   - 所有 API 端点正常工作

### 2026-06-10
1. **WebSocket 客户端和 TTS 下载管理器编译错误修复**
   - 修复 iOS 编译问题

2. **添加 no_think 参数**
   - Ollama 服务添加 no_think 参数
   - 处理 reasoning_content 返回

## 项目文件结构

```
pai-cc/
├── ios/                    # iOS App
│   └── PAICC/
│       └── Sources/
│           ├── API/       # API 客户端
│           ├── App/       # 应用入口
│           ├── Gesture/   # 手势识别
│           ├── Models/    # 数据模型
│           ├── QA/        # AI 问答
│           ├── Scanning/  # 摄像扫描
│           ├── Voice/     # 语音服务
│           └── Utils/     # 工具类
├── backend/              # FastAPI 后端
│   └── app/
│       ├── api/         # API 路由
│       ├── services/    # 业务服务
│       ├── models/      # 数据模型
│       └── main.py      # 入口
├── web/                  # Web Dashboard
├── docs/                 # 文档
├── deploy/              # 部署指南
└── uploads/             # 上传文件存储
```

## 技术栈

### iOS 端
- **语言**: Swift 5.0+
- **框架**: UIKit, Vision, AVFoundation, Speech
- **依赖管理**: CocoaPods (SnapKit, Alamofire)
- **构建工具**: XcodeGen

### 后端
- **语言**: Python 3.14
- **框架**: FastAPI + Uvicorn
- **数据库**: SQLite
- **AI 服务**: Ollama (视觉大模型)
- **TTS 服务**: Kokoro TTS

### 资源
- **后端服务器**: 100.64.0.13 (Ubuntu)
- **GPU 服务器**: 100.64.0.5 (Ollama evowit-agent27b)
- **Mac 构建机**: 100.64.0.6 (macstar)
- **VPS**: 159.75.178.237 (腾讯云广州)