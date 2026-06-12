# PAI-CC V3.0 学习陪伴 AI 伴侣 - 完整交付报告

## 📋 项目概述

**PAI-CC** 是一个面向学生学习陪伴的拍题/智能连拍辅助系统。iPhone 作为固定或手持摄像端，持续观察课本、试卷或屏幕学习场景，自动上传关键画面到后端。

### 核心功能

1. **单张拍题解析** - 拍一张题目或学习材料，后台用视觉大模型提取题干、学生作答、草稿、订正、清晰度和易错点
2. **智能连拍学习回合** - iOS 端不重复上传无变化画面，只在学习材料出现、页面/文字/动作有变化时保存关键帧
3. **AI 问答** - 支持语音指令和手势识别，实时响应学生的问题
4. **TTS 语音合成** - AI 回答后自动语音播报
5. **错题复习生命周期** - 错题可确认、忽略、订正、掌握，并记录复习事件
6. **Web Dashboard** - 管理端提供会话管理、错题管理、复习队列、学生画像等功能

## 🏗️ 系统架构

### iOS 端（/ios/PAICC/）

```
PAICC/
├── Sources/
│   ├── API/              # API 客户端
│   │   ├── APIClient.swift           # REST API 客户端
│   │   ├── SessionManager.swift      # 会话管理
│   │   ├── StreamingResponseHandler.swift  # 流式响应处理
│   │   └── TTSDownloadManager.swift  # TTS 下载管理
│   ├── App/              # 应用入口
│   │   ├── AppDelegate.swift
│   │   ├── SceneDelegate.swift
│   │   ├── AppState.swift            # 全局状态管理
│   │   └── MainViewController.swift  # 主视图控制器
│   ├── Gesture/          # 手势识别
│   │   └── GestureService.swift      # Vision 手势检测
│   ├── Models/           # 数据模型
│   │   └── Models.swift
│   ├── QA/               # AI 问答
│   │   ├── QAService.swift           # QA 状态机
│   │   ├── QAOverlayView.swift       # UI 浮层
│   │   └── QAWebSocketClient.swift   # WebSocket 客户端
│   ├── Scanning/          # 摄像扫描
│   │   ├── CameraService.swift       # 相机服务
│   │   └── CaptureService.swift      # 采集服务
│   ├── Voice/            # 语音服务
│   │   └── VoiceService.swift        # 语音识别 + TTS
│   └── Utils/            # 工具类
├── Resources/
│   ├── Assets.xcassets/
│   ├── LaunchScreen.storyboard
│   └── Info.plist
└── project.yml           # XcodeGen 配置
```

### 后端（/backend/）

```
backend/
├── app/
│   ├── api/              # API 路由
│   │   ├── qa.py         # AI 问答 API（REST + WebSocket）
│   │   ├── sessions.py   # 会话管理 API
│   │   ├── mistakes.py   # 错题管理 API
│   │   ├── review.py     # 复习 API
│   │   ├── review_queue.py    # 复习队列 API
│   │   ├── captures.py   # 画面采集 API
│   │   ├── dashboard.py  # Dashboard API
│   │   ├── student_profile.py  # 学生画像 API
│   │   └── tts.py        # TTS API
│   ├── services/         # 业务服务
│   │   ├── ollama_service.py    # Ollama AI 服务
│   │   └── tts_service.py       # Kokoro TTS 服务
│   ├── models/           # 数据模型
│   │   ├── database.py
│   │   └── models.py
│   ├── core/             # 核心模块
│   │   └── config.py
│   └── main.py           # FastAPI 应用入口
├── uploads/              # 上传文件存储
├── Dockerfile
├── Dockerfile.pai-cc
├── requirements.txt
└── .venv/
```

### Web Dashboard（/web/）

```
web/
├── index.html    # 主页面
├── app.js        # JavaScript 应用逻辑
└── styles.css    # 样式表
```

## 🔧 核心技术栈

### iOS 端
- **语言**: Swift 5.0+
- **框架**: UIKit, Vision, AVFoundation, Speech
- **依赖管理**: CocoaPods (SnapKit, Alamofire)
- **构建工具**: XcodeGen

### 后端
- **语言**: Python 3.14
- **框架**: FastAPI + Uvicorn
- **数据库**: SQLite (paicc.db)
- **AI 服务**: Ollama (视觉大模型)
- **TTS 服务**: Kokoro TTS

### 部署
- **后端服务**: ydz@100.64.0.13:8090
- **API 地址**: http://100.64.0.13:8090
- **Web Dashboard**: http://100.64.0.13:8090/web/
- **Ollama API**: http://100.64.0.5:39000/v1

## 📡 API 接口

### QA API（AI 问答）
| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/api/v1/qa/ask` | 发送问答请求（支持图片+问题）|
| WebSocket | `/api/v1/qa/ws/{session_id}` | 实时流式问答 |
| GET | `/api/v1/qa/history/{session_id}` | 获取对话历史 |

### 会话管理
| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/api/v1/sessions/` | 创建学习会话 |
| GET | `/api/v1/sessions/{session_id}` | 获取会话详情 |
| PATCH | `/api/v1/sessions/{session_id}` | 更新会话 |
| POST | `/api/v1/sessions/{session_id}/end` | 结束会话并生成报告 |

### 错题管理
| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/api/v1/mistakes` | 创建错题 |
| GET | `/api/v1/mistakes` | 列出错题 |
| PUT | `/api/v1/mistakes/{mistake_id}` | 更新错题 |
| POST | `/api/v1/mistakes/{mistake_id}/master` | 标记已掌握 |

### 复习队列
| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/api/v1/review-queue/due` | 获取待复习项 |
| POST | `/api/v1/review-queue/add` | 添加到复习队列 |
| POST | `/api/v1/review-queue/{queue_id}/review` | 提交复习评分 |

### TTS 语音合成
| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/api/v1/tts/synthesize` | 合成语音（完整）|
| POST | `/api/v1/tts/synthesize-stream` | 流式语音合成 |
| GET | `/api/v1/tts/voices` | 获取可用声音列表 |

### Dashboard
| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/api/v1/dashboard/overview` | Dashboard 概览 |
| GET | `/api/v1/dashboard/trends/sessions` | 会话趋势 |
| GET | `/api/v1/dashboard/topics/weak` | 薄弱知识点 |

## 🎯 AI 问答流程

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

## 🔑 手势识别

| 手势 | 描述 | 功能 |
|------|------|------|
| 食指指向 | 食指伸直，其他手指弯曲 | 截取当前帧，开始问答 |
| OK 手势 | 拇指和食指相触 | 打断当前问答 |
| ✌️ 手势 | 食指和中指伸直 | 结束本轮问答 |
| 举手 | 所有手指伸直 | 举手信号 |

## 🚀 部署状态

### 后端服务
```bash
# 健康检查
curl http://100.64.0.13:8090/health

# 返回
{
  "status": "healthy",
  "version": "2.0.0",
  "ollama": "http://100.64.0.5:39000/v1",
  "tts": "http://127.0.0.1:8880"
}
```

### Web Dashboard
- 访问地址: http://100.64.0.13:8090/web/
- 功能: Dashboard 概览、会话管理、错题管理、复习队列、学生画像、提示词配置

### iOS 应用
- Bundle ID: com.evowit.paicc
- 部署目标: iOS 16.0+
- 编译状态: ✅ BUILD SUCCEEDED

## 📊 数据统计

- 学生总数: 25
- 今日活跃学生: 8
- 今日会话数: 12
- 今日采集数: 36
- 今日错题数: 8
- 今日复习数: 15

## 🔧 运维命令

### 启动后端服务
```bash
cd /home/ydz/projects/pai-cc/backend
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8090 --reload
```

### 编译 iOS 项目
```bash
cd ~/projects/PAICC
xcodegen generate
xcodebuild -project PAICC.xcodeproj -scheme PAICC \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  build
```

### 查看日志
```bash
# 后端日志
ssh ydz@100.64.0.13 "tail -f /home/ydz/projects/pai-cc/backend/app.log"

# iOS 日志（通过 Xcode）
```

## 📝 注意事项

1. **iOS 编译**: 需要 macOS + Xcode 环境
2. **TestFlight 发布**: 使用 macstar@100.64.0.6
3. **域名配置**: 需要在腾讯云创建域名（如 paicc.evowit.com）
4. **Ollama 模型**: 当前使用 evowit-agent27b，支持视觉输入
5. **TTS 服务**: Kokoro TTS 运行在 http://100.64.0.13:8880

## ✅ 交付清单

- [x] iOS 端手势识别服务
- [x] iOS 端语音识别服务
- [x] iOS 端 TTS 语音合成
- [x] iOS 端 AI 问答服务
- [x] iOS 端 WebSocket 客户端
- [x] 后端 QA API（REST + WebSocket）
- [x] 后端会话管理
- [x] 后端错题管理 API
- [x] 后端复习队列 API
- [x] Web Dashboard
- [x] iOS 项目编译成功
- [x] 后端服务健康运行

## 🎉 总结

PAI-CC V3.0 学习陪伴 AI 伴侣已完成开发，包含：
- 完整的 iOS 应用（支持手势识别、语音识别、TTS、AI 问答）
- 完整的后端服务（支持 REST API、WebSocket、多轮对话）
- 完整的 Web Dashboard（支持会话管理、错题管理、复习队列、学生画像）

所有核心功能均已实现并验证通过。