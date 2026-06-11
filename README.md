# PAI-CC - 学习陪伴智能助手

面向学生学习陪伴的拍题/智能连拍辅助系统。

## 功能特性

- 📷 **智能连拍** - 自动识别学习材料变化
- 🎤 **语音问答** - 说出问题，AI 即时解答
- 👌 **手势控制** - 指向题目开始问答，OK 打断，✌️ 结束
- 🔊 **TTS 回复** - 语音朗读答案
- 📊 **学习报告** - 自动生成学习回合报告

## 技术栈

- **iOS**: Swift, Vision, AVFoundation, Speech
- **Backend**: FastAPI, Ollama, Kokoro TTS
- **AI**: evowit-agent27b

## 项目结构

```
pai-cc/
├── ios/              # iOS App
├── backend/         # FastAPI 后端
├── frontend/        # Web Dashboard
└── docs/            # 文档
```

## 快速开始

### 后端
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8090
```

### iOS
```bash
cd ios
xcodegen generate
xcodebuild -project PAICC.xcodeproj
```
