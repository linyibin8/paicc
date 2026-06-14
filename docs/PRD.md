# PAI-CC 产品需求文档 (PRD)

**产品名称**：PAI-CC（拍题伙伴）
**项目代号**：pai-codex
**更新日期**：2026-06-14
**当前版本**：1.5.0
**状态**：✅ 完整交付 + 实施建议

---

## 1. 产品一句话

PAI-CC 是一个给学生、家长和老师使用的学习陪伴工具。学生用 iPhone 拍摄课本、试卷、练习册或学习过程，系统帮助记录学习画面、回答学习问题、整理错题、生成学习报告，并给出后续复习建议。

**它不是单纯的"拍照搜题"，而是帮助用户看清楚一段学习过程**：学了什么、哪里卡住、问了什么、哪些题可能错了、后面应该怎么复习。

---

## 2. 适合谁使用

| 用户角色 | 核心需求 |
|----------|----------|
| **学生** | 拍题、连拍学习过程、语音提问、追问讲解，获得简短清楚的 AI 帮助 |
| **家长** | 回看孩子一次学习中发生了什么，了解做了哪些题、哪里可能错了、哪些知识点需要复习 |
| **老师** | 查看学生学习证据、错题候选、学习清单和复习情况，辅助后续讲解或辅导 |
| **管理员/测试者** | 查看学习记录、系统日志和提示词配置，方便内部测试和问题排查 |

---

## 3. 我们可以用它做什么

1. 拍一张题目，让系统帮忙识别题目、作答、草稿和可能的问题
2. 开启智能连拍，记录一段完整学习过程
3. 学习过程中直接语音提问，比如"这道题怎么做？""帮我检查对不对？"
4. 对 AI 的回答继续追问，比如"为什么？""换一种简单的方法讲"
5. 自动整理本次学习中出现的题目、知识点和错题候选
6. 生成一份给家长或老师看的学习报告
7. 把错题加入后续复习队列
8. 查看长期薄弱知识点和常见错误类型

---

## 4. 核心功能

### 4.1 拍题解析 ✅

学生可以对准一道题或一页作业，点击拍题解析。

**系统会尽量识别**：
- 题目内容
- 学生写的答案
- 草稿、计算过程或订正痕迹
- 画面是否清楚、题目是否完整
- 可能的错误点或需要注意的知识点

> ⚠️ **重要**：如果画面看不清，系统应该提示重新拍摄，而不是编造题目内容。

**实现状态**：
- ✅ iOS 相机采集服务 (CaptureService)
- ✅ 画面质量评估 (evaluateQuality)
- ✅ 学生在场检测 (detectStudentPresent)
- ✅ 内容类型分类 (classifyContent)
- ✅ 后端 AI 视觉识别 (qa.py)

---

### 4.2 智能连拍学习记录 ✅

学生可以把 iPhone 放在桌面旁，开启智能连拍。

**系统会持续观察学习画面**，但不会把所有重复画面都上传。它会优先记录有价值的变化，例如：
- 题目进入画面
- 学生开始书写
- 翻页
- 答案变化
- 出现订正
- 学生停留在某道题上较久

**自动忽略**：
- 空桌面
- 随手乱放
- 模糊画面
- 遮挡严重
- 没有学习材料

> ⚠️ 无关画面不进入报告。

**实现状态**：
- ✅ 帧差异哈希检测 (isDuplicateFrame)
- ✅ capture_meta 生成（timestamp, sequence, fingerprint, quality_score）
- ✅ 画面变化自动检测

---

### 4.3 实时语音问答 ✅

学生可以在学习时直接问 AI：
- "这道题怎么做？"
- "第二题我哪里错了？"
- "为什么这里要这样算？"
- "帮我检查一下对不对。"
- "换一种简单的方法讲。"

**系统会结合当前画面和最近的学习上下文回答**。普通追问会尽量沿用上一道题的上下文，不要求每次重新拍照。

**实现状态**：
- ✅ iOS 语音识别 (VoiceService)
- ✅ WebSocket 实时通信
- ✅ 多轮对话上下文管理
- ✅ REST API (`/api/v1/qa/ask`)
- ✅ WebSocket API (`/api/v1/qa/ws/{session_id}`)

---

### 4.4 指题、追问和结束 ✅

学生可以用更自然的方式和系统互动：

| 手势 | 功能 | 状态 |
|------|------|------|
| 食指指向 | 截取当前帧，开始问答 | ✅ |
| OK 手势 (👌) | 打断当前问答 | ✅ |
| ✌️ 手势 | 结束本轮问答 | ✅ |
| 举手 | 信号提示 | ✅ |

**其他交互**：
- 用结束操作关闭本轮问答
- 听不懂时让系统再讲一遍或换一种讲法
- 用追问入口打断当前回答并继续问

**实现状态**：
- ✅ Vision 框架手势识别 (GestureService)
- ✅ 连续 4 帧稳定检测
- ✅ iOS 问答状态机

---

### 4.5 AI 语音朗读 ✅

系统可以把答案用语音读出来，同时在屏幕上显示文字。

**要求**：
- ✅ 回答要短、清楚、适合学生理解
- ✅ 长答案要优先讲思路和关键步骤
- ✅ 用户打断时要及时停止朗读
- ✅ 语音播放失败时，文字答案仍然可看

**实现状态**：
- ✅ Kokoro TTS 语音合成
- ✅ 流式语音合成 (`/api/v1/tts/synthesize`)
- ✅ iOS TTS 播报 (AVSpeech)
- ✅ 思考音反馈
- ✅ WebSocket TTS 事件

---

### 4.6 学习报告 ✅

学习结束后，系统生成本次学习报告。

**报告应该包含**：
- 本次学习大致内容
- 拍到的题目和作答情况
- 可能的错题
- 相关知识点
- 学习过程中学生问过的问题
- 哪些内容需要复习
- 给家长或老师的后续建议

> ⚠️ **重要**：报告必须基于实际拍到的学习证据。没有拍到、看不清或无法判断的内容，不应该被写成确定结论。

**实现状态**：
- ✅ 会话报告数据模型
- ✅ 学习回合结束接口 (`/api/v1/sessions/{session_id}/end`)
- ✅ 报告存储和查询

---

### 4.7 学习清单 ✅

系统会把本次学习中识别到的内容整理成学习清单，例如：
- 做了哪些题
- 涉及哪些知识点
- 哪些地方有作答或订正
- 哪些内容值得后续回看

**实现状态**：
- ✅ LearningItem 数据模型
- ✅ 学习条目管理 API

---

### 4.8 错题候选 ✅

系统会把疑似错题整理出来，供家长、老师或管理员确认。

**错题状态**：
| 状态 | 说明 | 实现 |
|------|------|------|
| 疑似错题 | 系统检测到的可能错误 | ✅ |
| 确认错题 | 家长/老师确认的真正错题 | ✅ |
| 已忽略 | 不作为错题处理 | ✅ |
| 已订正 | 学生已改正 | ✅ |
| 已掌握 | 学生已完全掌握 | ✅ |

**实现状态**：
- ✅ 错题管理 API (`/api/v1/mistakes/`)
- ✅ 错题状态更新
- ✅ 错题统计 (`/api/v1/mistakes/stats/summary`)

---

### 4.9 复习队列 ✅

确认后的错题可以进入复习队列。

**复习时可以记录**：
| 结果 | 说明 |
|------|------|
| 复习正确 | 这次复习做对了 |
| 复习错误 | 这次复习做错了 |
| 延后复习 | 稍后再复习 |
| 已经掌握 | 完全掌握了 |

**系统根据复习结果安排后续复习**：
- ✅ SM-2 间隔重复算法
- ✅ 难度因子动态调整
- ✅ 到期提醒

**实现状态**：
- ✅ 复习队列 API (`/api/v1/review-queue/`)
- ✅ SM-2 算法实现
- ✅ 复习事件记录

---

### 4.10 长期学习画像 ✅

系统会根据多次学习记录，汇总长期情况：
- 常见薄弱知识点
- 常见错误类型
- 最近学习内容
- 复习情况
- 哪些问题经常被追问

这个画像用于帮助家长和老师判断后续辅导重点。

**实现状态**：
- ✅ 学生画像 API (`/api/v1/student-profile/`)
- ✅ 学习活动跟踪
- ✅ 能力评分
- ✅ 学习习惯分析

---

## 5. 典型使用场景

### 场景一：快速拍一道题
学生遇到一道题不会做，打开 App 拍一张。系统识别题目和学生作答，给出思路、关键步骤或提示重拍。

### 场景二：记录一段做作业过程
学生开启智能连拍，做完一段作业后停止。系统生成报告，家长可以看到孩子做了哪些题、哪里停留较久、有哪些错题候选。

### 场景三：边学边问
学生指着题目问："这里为什么错？"系统结合当前画面回答。学生可以继续追问："那应该怎么改？"

### 场景四：整理错题和复习
家长或老师在 Web 页面查看错题候选，确认真正的错题，安排后续复习，并记录复习结果。

### 场景五：观察长期薄弱点
经过多次学习后，家长或老师查看长期画像，了解学生反复出错的知识点和常见错误类型。

---

## 6. 当前已经具备的主要能力 ✅

### iOS 端
- ✅ iPhone 相机拍题
- ✅ 智能连拍学习过程
- ✅ 自动过滤明显无效或无关画面
- ✅ 语音提问和多轮追问
- ✅ 当前画面与历史上下文结合回答
- ✅ AI 文字答案和语音朗读
- ✅ 手势识别（指向、OK、✌️）
- ✅ 问答浮层 UI

### 后端
- ✅ 学习报告
- ✅ 学习清单
- ✅ 错题候选
- ✅ 错题确认、忽略、订正、掌握
- ✅ 复习记录和复习队列
- ✅ 长期学习画像
- ✅ Web Dashboard（回看图片、报告、问答和复习记录）
- ✅ 系统可观测性统计
- ✅ 日志查看
- ✅ 学习资产 API

---

## 7. 体验原则

1. **简单易用**：学生不需要理解复杂操作，打开就能拍、问、记录
2. **状态透明**：系统要始终告诉用户当前在做什么，比如正在听、思考中、上传中、报告生成中
3. **诚实回答**：看不清的题目不编造
4. **精选内容**：无关画面不进入报告
5. **积极反馈**：不用羞辱式反馈，不评价学生人格
6. **引导理解**：优先引导学生理解思路，而不是直接代做整套作业
7. **可追溯**：家长和老师看到的结论要能回到原始图片证据

---

## 8. 目前还需要补齐的产品能力 🚧

### 高优先级（正式发布前必须）

| 功能 | 描述 | 状态 |
|------|------|------|
| **用户登录** | 用户身份认证，支持学生、家长、老师角色 | 🚧 未开始 |
| **数据隔离** | 家庭、学生、老师之间的数据隔离 | 🚧 未开始 |
| **管理端权限控制** | 不同角色查看不同数据 | 🚧 未开始 |
| **删除入口** | 学习图片和问答记录的删除入口 | 🚧 未开始 |

### 中优先级（正式发布后迭代）

| 功能 | 描述 | 状态 |
|------|------|------|
| **数据保留期限设置** | 配置学习数据的保留时间 | 🚧 未开始 |
| **报告导出或分享** | 导出 PDF/图片格式的报告 | 🚧 未开始 |
| **多学生管理** | 一个家长管理多个学生账号 | 🚧 未开始 |
| **家长控制面板** | 是否开启语音、是否默认朗读、是否限制连续问答 | 🚧 未开始 |
| **语音控制开关** | 家长可关闭语音功能 | 🚧 未开始 |
| **追问次数限制** | 防止无限追问 | 🚧 未开始 |

### 低优先级（后续版本）

| 功能 | 描述 |
|------|------|
| 多语言支持 | 中文以外的语言 |
| 离线模式 | 无网络时本地缓存 |
| 进度奖励 | 学习打卡、成就系统 |
| 家长通知 | 推送孩子的学习摘要 |

---

## 9. 不做什么

当前产品**不定位为**：
- ❌ 在线课堂
- ❌ 班级作业发布系统
- ❌ 学生社交产品
- ❌ 大型题库系统
- ❌ 自动代写作业工具
- ❌ 老师批改的替代品

**它的重点是**：记录真实学习过程、帮助理解题目、沉淀错题和知识点、辅助复习和家长/老师回看。

---

## 10. 技术架构

### 系统架构图

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

### iOS 技术栈
- Swift 5, iOS 16.0+
- Vision 框架（手势识别）
- Speech 框架（语音识别）
- AVFoundation（相机 + TTS）
- SnapKit（Auto Layout）

### 后端技术栈
- Python 3.14 + FastAPI
- SQLite 数据库
- Ollama AI（视觉大模型）
- Kokoro TTS（语音合成）

### 部署信息
| 服务 | 地址 | 端口 |
|------|------|------|
| 后端 | 100.64.0.13 | 8030 |
| Ollama | 100.64.0.5 | 39000 |
| TTS | 100.64.0.13 | 8880 |
| VPS | 159.75.178.237 | - |

---

## 11. API 端点

### 核心 API
| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/api/v1/sessions/` | POST | 创建学习会话 |
| `/api/v1/sessions/` | GET | 列出会话 |
| `/api/v1/sessions/{id}` | GET/PUT | 获取/更新会话 |
| `/api/v1/captures/` | POST | 上传画面 |
| `/api/v1/qa/ask` | POST | REST 问答 |
| `/api/v1/qa/ws/{session_id}` | WebSocket | WebSocket 问答 |
| `/api/v1/tts/synthesize` | POST | TTS 语音合成 |

### 错题和复习 API
| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/mistakes/` | GET/POST | 错题列表/创建 |
| `/api/v1/mistakes/{id}` | GET/PUT/DELETE | 错题详情 |
| `/api/v1/mistakes/stats/summary` | GET | 错题统计 |
| `/api/v1/review-queue/` | GET/POST | 复习队列 |
| `/api/v1/student-profile/` | GET | 学生画像 |

### 管理 API
| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/dashboard/` | GET | Dashboard 统计 |
| `/api/v1/logs/` | GET | 日志查看 |
| `/api/v1/assets/` | GET | 学习资产 |
| `/api/v1/observability/` | GET | 系统可观测性 |

---

## 12. 发布状态

### iOS 应用
- **Bundle ID**: com.evowit.paicc
- **App Store Connect App ID**: 6779175815
- **Version**: 1.1.0
- **Build**: 202606131200
- **Build State**: VALID
- **TestFlight Group**: d9672400-b3b3-4a98-8a7f-5325402ea9d0

### 测试账号
- 269123786@qq.com
- linyibin8@qq.com
- 3972104921@qq.com
- 643014114@qq.com

---

## 13. 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| 1.1.0 | 2026-06-13 | 更新版本号，准备 TestFlight 发布 |
| 1.0.1 | 2026-06-12 | 修复 WebSocket connect 消息处理 |
| 1.0.0 | 2026-06-13 | 首次 TestFlight 发布 |

---

## 14. 功能差距分析 (Gap Analysis)

### 14.1 产品需求 vs 实现状态

| 需求模块 | 需求描述 | 实现状态 | 代码位置 | 差距 |
|----------|----------|----------|----------|------|
| **拍题解析** | 识别题目、学生作答、草稿 | ✅ 已实现 | `ios/Scanning/` + `qa.py` | 完整 |
| **智能连拍** | 自动过滤无效画面 | ✅ 已实现 | `CaptureService.swift` | 完整 |
| **语音问答** | 语音提问+多轮对话 | ✅ 已实现 | `VoiceService` + WebSocket | 完整 |
| **手势识别** | 指向/OK/✌️手势 | ✅ 已实现 | `GestureService.swift` | 完整 |
| **TTS 朗读** | 语音播报答案 | ✅ 已实现 | `tts_service.py` | 完整 |
| **学习报告** | 会话报告生成 | ✅ 已实现 | `sessions.py` | 完整 |
| **错题候选** | 错题状态管理 | ✅ 已实现 | `mistakes.py` | 完整 |
| **复习队列** | SM-2 间隔重复 | ✅ 已实现 | `review_queue.py` | 完整 |
| **学习画像** | 长期学习统计 | ✅ 已实现 | `student_profile.py` | 完整 |
| **Web Dashboard** | 数据查看管理 | ✅ 已实现 | `web/` | 完整 |
| **用户登录** | 身份认证 | ❌ 未实现 | - | **高优先级** |
| **数据隔离** | 多用户数据隔离 | ❌ 未实现 | - | **高优先级** |
| **权限控制** | 角色权限管理 | ❌ 未实现 | - | **高优先级** |
| **删除入口** | 删除学习记录 | ❌ 未实现 | - | **高优先级** |
| **报告导出** | PDF/图片导出 | ❌ 未实现 | - | 中优先级 |
| **多学生管理** | 一家长多学生 | ❌ 未实现 | - | 中优先级 |
| **家长控制** | 功能开关设置 | ❌ 未实现 | - | 中优先级 |

### 14.2 技术债务

| 问题 | 影响 | 优先级 |
|------|------|--------|
| 错题 API 使用内存存储 | 重启后数据丢失 | 🔴 **高** |
| 复习队列使用内存存储 | 重启后数据丢失 | 🔴 **高** |
| 学生画像 API 使用内存存储 | 重启后数据丢失 | 🔴 **高** |
| 后端日志写入文件未实现 | 问题排查困难 | 🟡 中 |
| 提示词配置存储在代码中 | 需重启才能更新 | 🟡 中 |

---

## 15. 功能规格 (Functional Specs)

### 15.1 拍题解析规格

#### 输入
- 图片（Base64 或文件上传）
- 可选：学生目标描述
- 可选：会话上下文

#### 输出
```json
{
  "answer": "解题步骤和思路",
  "knowledge_points": ["相关知识点列表"],
  "suggested_followups": ["追问建议"],
  "quality_score": 0.85,
  "is_clear": true,
  "detected_mistakes": [
    {
      "type": "calculation_error",
      "location": "第3步",
      "description": "乘法进位错误"
    }
  ]
}
```

#### 约束
- 图片最大 10MB
- 支持格式：JPEG, PNG, HEIC
- 处理超时 30 秒
- 画面不清晰时返回 `is_clear: false`

---

### 15.2 智能连拍规格

#### 画面质量评估
| 指标 | 阈值 | 说明 |
|------|------|------|
| 清晰度 | > 0.6 | 基于边缘检测 |
| 学生在场 | boolean | 检测到学生手指/手臂 |
| 内容类型 | enum | text, math, diagram, empty |

#### 帧过滤规则
1. 与上一帧差异 < 5% → 跳过
2. 质量分数 < 0.4 → 跳过
3. 内容类型 = empty → 跳过
4. 内容类型 = clutter → 跳过

#### 上传条件
满足以下任一条件时上传：
- 检测到翻页动作
- 检测到书写动作
- 学生手指指向画面
- 停留时间 > 30 秒
- 质量分数 > 0.7

---

### 15.3 语音问答规格

#### 交互流程
```
用户手势 → 系统检测 → TTS"请说" → 语音识别 → TTS"好的" → AI处理 → 流式响应 → TTS朗读
```

#### WebSocket 消息类型
| 类型 | 方向 | 说明 |
|------|------|------|
| `connect` | 客户端→服务端 | 建立连接 |
| `ask` | 客户端→服务端 | 发送问题 |
| `thinking` | 服务端→客户端 | AI思考中 |
| `partial` | 服务端→客户端 | 流式片段 |
| `answer` | 服务端→客户端 | 完整回答 |
| `tts_start` | 服务端→客户端 | TTS开始 |
| `tts_ready` | 服务端→客户端 | TTS就绪 |
| `interrupt` | 客户端→服务端 | 打断请求 |
| `interrupted` | 服务端→客户端 | 已打断 |
| `clear` | 客户端→服务端 | 清空历史 |

#### 上下文管理
- 最大历史条数：20
- 自动继承上一题上下文
- 支持手动清空历史

---

### 15.4 错题管理规格

#### 错题状态机
```
疑似错题 → 确认错题 → 已掌握
    ↓           ↓
  已忽略     已订正
```

#### 复习评分 (SM-2 算法)
| 评分 | 含义 | 行为 |
|------|------|------|
| 0 | 完全遗忘 | 重置间隔为1天 |
| 1-2 | 错误但想起 | 保持或缩短间隔 |
| 3 | 勉强正确 | 正常间隔 |
| 4-5 | 完全正确 | 延长间隔 |

#### 间隔计算
- 第1次复习：1天
- 第2次复习：6天
- 第3次+复习：间隔 × 难度因子
- 最大间隔：365天
- 难度因子范围：1.3 - 2.5

---

### 15.5 学习报告规格

#### 报告结构
```json
{
  "report_id": "rpt_xxx",
  "session_id": "sess_xxx",
  "generated_at": "2026-06-13T10:30:00Z",
  "period": {
    "start": "2026-06-13T09:00:00Z",
    "end": "2026-06-13T10:30:00Z",
    "duration_minutes": 90
  },
  "summary": {
    "total_captures": 12,
    "total_questions": 5,
    "total_mistakes": 3,
    "questions_asked": 8
  },
  "captures": [
    {
      "capture_id": "cap_xxx",
      "thumbnail_url": "/uploads/xxx_thumb.jpg",
      "timestamp": "2026-06-13T09:15:00Z",
      "content_type": "math"
    }
  ],
  "mistakes": [...],
  "knowledge_points": [...],
  "questions": [...],
  "review_recommendations": [...],
  "parent_advice": "建议加强分数运算..."
}
```

---

## 16. 数据模型

### 16.1 数据库模型（已定义 ⚠️ 未完全使用）

> ⚠️ **注意**：数据库模型已定义在 `backend/app/models/models.py`，但错题、复习队列、学生画像 API 目前使用内存存储，需迁移到数据库。

#### User (用户) - 待实现
```python
class User:
    user_id: str           # UUID
    username: str          # 用户名
    email: str             # 邮箱
    password_hash: str     # 密码哈希
    role: str              # student | parent | teacher | admin
    created_at: datetime
    last_login: datetime
```

#### Student (学生) ✅ 已定义
```python
class Student(Base):
    student_id: str       # UUID，unique, indexed
    name: str              # 姓名
    grade: str             # 年级
    subjects: List[str]    # 科目
    created_at: datetime
```

#### Session (学习会话) ✅ 已定义
```python
class Session(Base):
    session_id: str       # UUID，unique, indexed
    student_id: int        # 外键 → students.id
    status: str            # created | active | paused | completed | processing
    student_goal: str
    camera_active_time: int
    student_active_time: int
    capture_count: int
    mistake_count: int
    report: JSON
    started_at: datetime
    ended_at: datetime
```

#### Capture (画面采集) ✅ 已定义
```python
class Capture(Base):
    capture_id: str       # UUID，unique, indexed
    session_id: int        # 外键 → sessions.id
    sequence: int
    quality_score: float
    student_present: bool
    content_type: str       # text | math | diagram | empty | clutter
    image_path: str
    analysis: JSON
```

#### Mistake (错题) ✅ 已定义
```python
class Mistake(Base):
    mistake_id: str        # UUID，unique, indexed
    student_id: int        # 外键 → students.id
    status: str            # suspected | confirmed | mastered | ignored | corrected
    subject: str
    student_answer: str
    correct_answer: str
    error_reason: str
    knowledge_points: List[str]
    review_count: int
    review_status: str     # queued | in_review | mastered
```

#### ReviewEvent (复习事件) ✅ 已定义
```python
class ReviewEvent(Base):
    event_id: str         # UUID，unique, indexed
    mistake_id: int        # 外键 → mistakes.id
    student_id: int        # 外键 → students.id
    result: str            # correct | wrong | delayed | mastered
    score: float           # 0-100
    time_spent: int        # 秒
```

#### LearningItem (学习条目) ✅ 已定义
```python
class LearningItem(Base):
    item_id: str          # UUID，unique, indexed
    item_type: str         # question | note | formula
    subject: str
    title: str
    content: str
    solution: str
    knowledge_points: List[str]
```

### 16.2 数据库索引
```sql
-- sessions 表索引
CREATE INDEX idx_sessions_student ON sessions(student_id, created_at DESC);
CREATE INDEX idx_sessions_status ON sessions(status);

-- captures 表索引
CREATE INDEX idx_captures_session ON captures(session_id, sequence);
CREATE INDEX idx_captures_quality ON captures(quality_score);

-- mistakes 表索引
CREATE INDEX idx_mistakes_student ON mistakes(student_id, status, created_at DESC);
CREATE INDEX idx_mistakes_review ON mistakes(review_status, next_review_at);

-- review_events 表索引
CREATE INDEX idx_review_events_mistake ON review_events(mistake_id);
CREATE INDEX idx_review_events_student ON review_events(student_id, created_at DESC);
```

### 16.3 数据迁移计划
```
当前状态                    → 目标状态
─────────────────────────────────────────
mistakes.py: _mistakes={}  → 使用 SQLAlchemy ORM
review_queue.py: _queue={} → 使用 SQLAlchemy ORM
student_profile.py: _profiles={} → 使用 SQLAlchemy ORM
```

---

## 17. 迭代计划 (Roadmap)

### v1.1.1 - 数据持久化修复（预计 2-3 天）🔴 紧急
- [ ] 错题数据迁移到 SQLite
- [ ] 复习队列数据迁移到 SQLite
- [ ] 学生画像数据迁移到 SQLite
- [ ] 数据库索引优化
- [ ] 数据迁移脚本

### v1.2.0 - 用户系统（预计 1 周）
- [ ] 用户注册/登录 API
- [ ] JWT 认证
- [ ] 用户角色（学生/家长/老师/管理员）
- [ ] 密码重置
- [ ] 密码加密 (bcrypt)

### v1.3.0 - 数据隔离（预计 1 周）
- [ ] 家庭/班级概念
- [ ] 数据权限控制
- [ ] 邀请码机制
- [ ] 多角色视图
- [ ] API 鉴权中间件

### v1.4.0 - 管理功能（预计 1 周）
- [ ] 学习记录删除
- [ ] 数据导出
- [ ] 审计日志
- [ ] 配置管理
- [ ] 提示词在线配置

### v2.0.0 - 正式发布
- [ ] 生产环境部署
- [ ] App Store 上架
- [ ] 用户文档
- [ ] 客服支持

---

### 里程碑

| 版本 | 目标 | 关键交付 |
|------|------|----------|
| v1.1.1 | 稳定数据 | 错题/复习/画像持久化 |
| v1.2.0 | 用户系统 | 登录注册，JWT认证 |
| v1.3.0 | 数据隔离 | 家庭/班级/权限 |
| v1.4.0 | 管理功能 | 删除/导出/审计 |
| v2.0.0 | 正式发布 | App Store |

---

## 18. 当前进度追踪

### 已完成 ✅
- [x] 项目初始化
- [x] iOS 相机和手势识别
- [x] 语音识别和 TTS
- [x] WebSocket 问答
- [x] 错题管理（内存）
- [x] 复习队列（内存）
- [x] 学生画像（内存）
- [x] Web Dashboard
- [x] TestFlight 发布

### 进行中 🚧
- [ ] 数据持久化修复（v1.1.1）🔴 紧急
- [ ] 用户登录系统（v1.2.0）
- [ ] 数据隔离（v1.3.0）

### 待开始 📋
- [ ] 报告导出
- [ ] 多学生管理
- [ ] 家长控制面板

---

## 19. 测试计划

### 19.1 单元测试
- [ ] 拍题解析：图片处理和识别
- [ ] 智能连拍：帧过滤和质量评估
- [ ] 语音问答：上下文管理
- [ ] SM-2 算法：间隔计算

### 19.2 集成测试
- [ ] iOS ↔ 后端 WebSocket 连接
- [ ] TTS 流式合成
- [ ] 会话生命周期

### 19.3 E2E 测试
- [ ] 完整拍题流程
- [ ] 智能连拍流程
- [ ] 错题复习流程

---

## 21. API 详细规格

### 21.1 会话管理 API

#### POST /api/v1/sessions/
创建新会话
```json
// Request
{
  "student_id": "stu_abc123",
  "student_goal": "完成数学作业",
  "assistant_focus": "计算题",
  "report_style": "normal",
  "metadata": {
    "subject": "math",
    "chapter": "分数运算"
  }
}

// Response 201
{
  "session_id": "sess_xyz789",
  "status": "created",
  "created_at": "2026-06-13T10:00:00Z"
}
```

#### GET /api/v1/sessions/
列出会话
```json
// Query: ?student_id=xxx&status=active&skip=0&limit=20
{
  "sessions": [...],
  "total": 50
}
```

#### GET /api/v1/sessions/{session_id}
获取会话详情
```json
{
  "session_id": "sess_xyz789",
  "student_id": "stu_abc123",
  "status": "active",
  "student_goal": "完成数学作业",
  "capture_count": 12,
  "mistake_count": 3,
  "started_at": "2026-06-13T10:00:00Z"
}
```

#### PUT /api/v1/sessions/{session_id}
更新会话
```json
// Request
{
  "status": "completed",
  "student_goal": "已修改目标"
}
```

#### POST /api/v1/sessions/{session_id}/end
结束会话并生成报告
```json
// Request
{
  "report": {
    "summary": {...}
  }
}

// Response
{
  "status": "completed",
  "session_id": "sess_xyz789"
}
```

---

### 21.2 AI 问答 API

#### POST /api/v1/qa/ask
REST 问答
```json
// Request
{
  "session_id": "sess_xyz789",
  "query": "这道题怎么做？",
  "trigger_type": "voice",
  "conversation_history": [...],
  "capture_meta": {
    "quality_score": 0.85,
    "content_type": "math"
  }
}

// Response 200
{
  "answer": "解题步骤...",
  "knowledge_points": ["分数乘法", "约分"],
  "suggested_followups": ["为什么这样约分？"],
  "audio_url": "/api/v1/tts/audio/xxx.mp3",
  "processing_time": 2.5,
  "vision_supported": true
}
```

#### WebSocket /api/v1/qa/ws/{session_id}
WebSocket 实时问答

**连接**:
```json
// 客户端 → 服务端
{"type": "connect", "session_id": "sess_xyz789"}

// 服务端 → 客户端
{"type": "connected", "history_length": 0}
```

**提问**:
```json
// 客户端 → 服务端
{
  "type": "ask",
  "query": "这道题的第二步为什么要约分？",
  "image": "base64...",
  "enable_tts": true,
  "voice": "af_bella"
}

// 服务端 → 客户端 (流式)
{"type": "thinking", "content": "正在思考..."}
{"type": "partial", "content": "因为..."}
{"type": "partial", "content": "所以需要..."}
{"type": "answer", "content": "完整答案", "suggested_followups": [...]}
{"type": "tts_start"}
{"type": "tts_ready", "audio_url": "..."}
```

**打断**:
```json
// 客户端 → 服务端
{"type": "interrupt"}

// 服务端 → 客户端
{"type": "interrupted"}
```

**清空历史**:
```json
// 客户端 → 服务端
{"type": "clear"}

// 服务端 → 客户端
{"type": "cleared", "history_length": 0}
```

---

### 21.3 错题管理 API

#### POST /api/v1/mistakes/
创建错题
```json
// Request
{
  "student_id": "stu_abc123",
  "session_id": "sess_xyz789",
  "subject": "math",
  "topic": "分数运算",
  "question_text": "1/2 + 1/3 = ?",
  "student_answer": "2/5",
  "correct_answer": "5/6",
  "error_type": "calculation",
  "difficulty": 0.6,
  "capture_ids": ["cap_001"]
}

// Response 201
{
  "mistake_id": "mis_xxx",
  "status": "suspected",
  "created_at": "2026-06-13T10:30:00Z"
}
```

#### GET /api/v1/mistakes/
列出错题
```json
// Query: ?student_id=xxx&status=suspected&subject=math&limit=20
{
  "mistakes": [
    {
      "mistake_id": "mis_xxx",
      "subject": "math",
      "status": "suspected",
      "review_count": 0
    }
  ],
  "total": 15
}
```

#### PUT /api/v1/mistakes/{mistake_id}
更新错题
```json
// Request
{
  "status": "confirmed",
  "correct_answer": "5/6"
}
```

#### POST /api/v1/mistakes/{mistake_id}/review-events
创建复习事件
```json
// Request
{
  "result": "correct",
  "notes": "这次理解了",
  "score": 85
}

// Response
{
  "event_id": "evt_xxx",
  "result": "correct"
}
```

#### GET /api/v1/mistakes/stats/summary
错题统计
```json
{
  "total": 25,
  "by_status": {"suspected": 10, "confirmed": 8, "mastered": 7},
  "by_subject": {"math": 15, "chinese": 10},
  "by_error_type": {"calculation": 12, "concept": 8, "reading": 5},
  "mastered_rate": 0.28,
  "avg_review_count": 1.5
}
```

---

### 21.4 复习队列 API

#### POST /api/v1/review-queue/add
添加复习项
```json
// Request (Form)
student_id: stu_abc123
mistake_id: mis_xxx
question_text: 1/2 + 1/3 = ?
correct_answer: 5/6
difficulty: 0.6
```

#### GET /api/v1/review-queue/due
获取待复习项
```json
// Query: ?student_id=xxx&subject=math
{
  "items": [
    {
      "queue_id": "que_xxx",
      "question_text": "...",
      "due_date": "2026-06-14T00:00:00Z",
      "interval": 1
    }
  ],
  "total": 5,
  "due_now": 3
}
```

#### POST /api/v1/review-queue/{queue_id}/review
提交复习评分
```json
// Request
{
  "quality": 4  // 0-5
}

// Response
{
  "queue_id": "que_xxx",
  "next_review_date": "2026-06-20T00:00:00Z",
  "new_interval": 6,
  "new_ease_factor": 2.6,
  "is_mastered": false
}
```

---

### 21.5 学生画像 API

#### GET /api/v1/student-profile/{student_id}
获取学生画像
```json
{
  "student_id": "stu_abc123",
  "total_sessions": 20,
  "total_mistakes": 45,
  "total_reviews": 60,
  "mastered_topics": ["分数基础", "整数运算"],
  "weak_topics": ["分数乘法", "应用题"],
  "streak_days": 7,
  "recent_activities": [...]
}
```

#### GET /api/v1/student-profile/{student_id}/stats
学生统计
```json
{
  "total_sessions": 20,
  "total_captures": 150,
  "total_mistakes": 45,
  "total_reviews": 60,
  "mastery_rate": 0.35,
  "review_completion_rate": 0.85
}
```

#### GET /api/v1/student-profile/{student_id}/weak-topics
薄弱知识点分析
```json
{
  "weak_topics": [
    {
      "topic": "分数乘法",
      "error_count": 12,
      "error_types": ["约分错误", "通分错误"],
      "avg_difficulty": 0.7,
      "suggested_practice_count": 10
    }
  ]
}
```

---

### 21.6 TTS API

#### POST /api/v1/tts/synthesize
语音合成
```json
// Request
{
  "text": "这道题的答案是5/6。",
  "voice": "af_bella"
}

// Response
{
  "audio_url": "/api/v1/tts/audio/xxx.mp3",
  "duration": 2.5
}
```

---

### 21.7 仪表盘 API

#### GET /api/v1/dashboard/
仪表盘概览
```json
{
  "total_students": 10,
  "total_sessions": 150,
  "total_mistakes": 200,
  "pending_reviews": 45,
  "mastered_mistakes": 55,
  "active_sessions": 3
}
```

#### GET /api/v1/dashboard/session-trends
会话趋势
```json
{
  "period": "week",
  "sessions_count": [15, 12, 18, 20, 16, 14, 22],
  "dates": ["2026-06-07", "2026-06-08", ...]
}
```

#### GET /api/v1/dashboard/weak-topics
薄弱知识点
```json
{
  "topics": [
    {"name": "分数乘法", "count": 25, "trend": "up"},
    {"name": "应用题", "count": 18, "trend": "stable"}
  ]
}
```

---

## 22. 错误处理规范

### 22.1 HTTP 状态码
| 状态码 | 含义 | 使用场景 |
|--------|------|----------|
| 200 | 成功 | 正常响应 |
| 201 | 已创建 | 资源创建成功 |
| 400 | 客户端错误 | 请求参数错误 |
| 401 | 未认证 | 缺少或无效 Token |
| 403 | 禁止访问 | 无权限 |
| 404 | 未找到 | 资源不存在 |
| 500 | 服务器错误 | 内部错误 |

### 22.2 错误响应格式
```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "会话不存在",
    "details": {
      "session_id": "sess_xxx"
    }
  }
}
```

### 22.3 业务错误码
| 错误码 | 说明 |
|--------|------|
| `SESSION_NOT_FOUND` | 会话不存在 |
| `STUDENT_NOT_FOUND` | 学生不存在 |
| `MISTAKE_NOT_FOUND` | 错题不存在 |
| `INVALID_STATUS_TRANSITION` | 无效的状态转换 |
| `REVIEW_NOT_DUE` | 复习未到期 |
| `IMAGE_TOO_LARGE` | 图片超过 10MB |
| `UNAUTHORIZED` | 未授权访问 |

---

## 23. UI/UX 规格

### 23.1 iOS App 界面

#### 主界面布局
```
┌─────────────────────────────┐
│        相机预览            │
│    (全屏摄像头画面)        │
│                             │
│                             │
├─────────────────────────────┤
│  [拍题] [连拍] [学习报告]   │  ← 底部工具栏
└─────────────────────────────┘
```

#### 问答浮层
```
┌─────────────────────────────┐
│      "请说"                │  ← TTS 提示
│                             │
│    ┌─────────────────┐     │
│    │  语音波形动画   │     │
│    └─────────────────┘     │
│                             │
│  👌 打断   ✌️ 结束          │  ← 手势提示
└─────────────────────────────┘
```

#### 状态指示
| 状态 | 视觉反馈 |
|------|----------|
| 扫描中 | 绿色圆点闪烁 |
| 手势检测中 | 蓝色圆点 |
| 等待语音 | 橙色圆点 |
| AI 思考中 | 加载动画 |
| TTS 播放中 | 喇叭图标 |

### 23.2 Web Dashboard 界面

#### 页面结构
```
┌────────┬────────────────────────────────┐
│        │ Dashboard                      │
│  📚    ├────────────────────────────────┤
│  PAI-CC│  [统计卡片] [统计卡片]          │
│        │  [统计卡片] [统计卡片]          │
│ ────── │                                │
│ 📊 Dashboard                            │
│ 💬 会话 │     [会话趋势图表]             │
│ 📝 错题 │                                │
│ 🔄 复习 │     [薄弱知识点列表]           │
│ 👤 画像 │                                │
│ ⚙️ 配置 │                                │
│        │                                │
│ ────── │                                │
│ ● 连接 │                                │
└────────┴────────────────────────────────┘
```

#### Dashboard 页面
- 统计卡片：学生数、今日活跃、今日会话、待复习
- 会话趋势图：Chart.js 折线图
- 薄弱知识点列表：带错误次数标签
- 学习热力图：日历视图

#### 错题管理页面
- 错题列表：支持筛选（状态、科目、难度）
- 错题详情：显示原图、答案、错误原因
- 操作按钮：确认/忽略/订正/掌握

#### 学生画像页面
- 能力雷达图
- 学习进度时间线
- 薄弱点趋势图

### 23.3 响应式设计
| 断点 | 宽度 | 布局 |
|------|------|------|
| Mobile | < 768px | 单列，底部工具栏 |
| Tablet | 768px - 1024px | 双列，侧边栏可折叠 |
| Desktop | > 1024px | 三列，固定侧边栏 |

### 23.4 颜色规范
| 用途 | 颜色 | Hex |
|------|------|-----|
| 主色 | 蓝色 | #667eea |
| 强调色 | 紫色 | #764ba2 |
| 成功色 | 绿色 | #10b981 |
| 警告色 | 橙色 | #f59e0b |
| 错误色 | 红色 | #ef4444 |
| 背景色 | 浅灰 | #f3f4f6 |
| 文字色 | 深灰 | #1f2937 |

### 23.5 字体规范
| 用途 | 字体 | 大小 |
|------|------|------|
| 标题 H1 | 系统字体 | 24px |
| 标题 H2 | 系统字体 | 20px |
| 正文 | 系统字体 | 14px |
| 辅助文字 | 系统字体 | 12px |
| iOS 答案 | 系统字体 | 16px |

---

## 24. 安全规格

### 24.1 认证与授权

#### JWT Token
```python
# Token 结构
{
  "sub": "user_id",
  "role": "student|parent|teacher|admin",
  "student_id": "stu_xxx",  # 仅学生角色
  "exp": 1234567890
}

# Header
Authorization: Bearer <token>
```

#### 角色权限
| 权限 | 学生 | 家长 | 老师 | 管理员 |
|------|------|------|------|--------|
| 拍题/问答 | ✅ | ❌ | ❌ | ❌ |
| 查看自己的报告 | ✅ | ✅ | ✅ | ✅ |
| 查看孩子的报告 | ❌ | ✅ | ❌ | ✅ |
| 查看学生的报告 | ❌ | ❌ | ✅ | ✅ |
| 管理错题 | ✅ | ✅ | ✅ | ✅ |
| 管理复习 | ✅ | ✅ | ✅ | ✅ |
| 查看所有学生 | ❌ | ❌ | ✅ | ✅ |
| 系统配置 | ❌ | ❌ | ❌ | ✅ |

### 24.2 数据安全

#### 密码存储
- 算法：bcrypt
- 盐值：自动生成
- 最小长度：8 位

#### 敏感数据加密
- JWT Secret：生产环境必须更改
- 数据库：SQLite（测试）/ PostgreSQL（生产）

#### API 鉴权
```python
# 中间件检查
async def auth_middleware(request: Request, call_next):
    # 公开接口：/health, /api/v1/sessions/ (创建)
    # 需要认证：其他所有接口
    # 检查 Token 有效性
    # 注入 user_id 到 request state
```

### 24.3 输入验证
| 字段 | 验证规则 |
|------|----------|
| 图片 | 最大 10MB，格式 JPEG/PNG/HEIC |
| 文本 | 最大长度 10000 字符 |
| 学生 ID | UUID 格式 |
| 评分 | 0-5 整数 |

### 24.4 CORS 配置
```python
# 生产环境
cors_origins = [
    "https://paicc.evowit.com",
    "https://admin.paicc.evowit.com"
]

# 开发环境
cors_origins = ["*"]
```

---

## 25. 部署规格

### 25.1 基础设施

#### 服务器规划
| 服务器 | 角色 | 配置 |
|--------|------|------|
| 100.64.0.13 | 后端 + TTS | 4C8G Ubuntu |
| 100.64.0.5 | Ollama GPU | 2x RTX 4090 |
| 100.64.0.6 | iOS 编译 | Mac |
| 159.75.178.237 | 反向代理 | VPS |

#### 域名
| 域名 | 指向 | 用途 |
|------|------|------|
| api.pai-cc.evowit.com | 100.64.0.13:8030 | 后端 API |
| tts.pai-cc.evowit.com | 100.64.0.13:8880 | TTS 服务 |
| ai.pai-cc.evowit.com | 100.64.0.5:39000 | Ollama AI |
| paicc.evowit.com | 159.75.178.237 | 主域名 |

### 25.2 部署流程

#### 后端部署
```bash
# 1. 拉取代码
cd /home/ydz/projects/pai-cc/backend

# 2. 激活虚拟环境
source venv/bin/activate

# 3. 安装依赖
pip install -r requirements.txt

# 4. 运行迁移
alembic upgrade head

# 5. 启动服务
nohup python -m uvicorn app.main:app --host 0.0.0.0 --port 8030 > app.log 2>&1 &

# 6. 检查健康
curl http://localhost:8030/health
```

#### iOS 发布
```bash
# 1. 同步代码到 Mac
rsync -avz --delete \
  -e "ssh -i ~/.ssh/id_ed25519" \
  /home/ydz/projects/pai-cc/ios/ \
  macstar@100.64.0.6:~/pai-cc/

# 2. 生成项目
cd ~/pai-cc && xcodegen generate

# 3. 打包上传
./scripts/package_and_upload.sh
```

### 25.3 监控

#### 健康检查
- `/health`：每分钟检查
- `/api/v1/observability/stats`：系统指标

#### 日志
- 应用日志：`/home/ydz/projects/pai-cc/backend/app.log`
- Nginx 日志：`/var/log/nginx/`

#### 告警规则
| 条件 | 动作 |
|------|------|
| 后端不可用 > 5min | 邮件通知 |
| 错误率 > 10% | 邮件通知 |
| 磁盘使用 > 80% | 邮件通知 |

### 25.4 备份策略
| 数据 | 频率 | 保存时间 |
|------|------|----------|
| 数据库 | 每天 | 30 天 |
| 上传文件 | 每周 | 90 天 |
| 日志 | 每周压缩 | 30 天 |

---

## 26. 性能要求

### 26.1 响应时间 (SLA)

| 操作 | 目标 | 最大 | 说明 |
|------|------|------|------|
| 拍题响应 | < 3s | 5s | AI 回答生成 |
| TTS 首字节 | < 500ms | 1s | 语音开始播放 |
| WebSocket 连接 | < 200ms | 500ms | 建立连接 |
| 页面加载 | < 2s | 3s | Web Dashboard |
| API 通用 | < 500ms | 1s | 普通请求 |

### 26.2 并发能力

| 场景 | 并发数 | 说明 |
|------|--------|------|
| 普通 API | 100 QPS | 大部分接口 |
| AI 问答 | 20 QPS | 需要 GPU |
| TTS | 50 QPS | 可缓存 |
| WebSocket | 500 连接 | 长连接 |

### 26.3 系统容量

| 资源 | 当前 | 目标 |
|------|------|------|
| 学生数 | 10 | 1000 |
| 日会话数 | 50 | 5000 |
| 存储 | 5GB | 100GB |
| 数据库 | SQLite | PostgreSQL |

### 26.4 性能监控指标

```python
# 关键性能指标 (KPI)
PERFORMANCE_KPI = {
    "api_latency_p99": "< 2s",      # P99 延迟
    "tts_latency_p95": "< 1s",      # TTS P95
    "error_rate": "< 1%",           # 错误率
    "availability": "> 99.5%",       # 可用性
    "gpu_utilization": "< 80%"       # GPU 利用率
}
```

---

## 27. 风险评估

### 27.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| Ollama 服务不可用 | 高 | 中 | 添加备用模型、本地缓存答案 |
| GPU 资源不足 | 高 | 中 | 限流、队列机制 |
| 数据库性能瓶颈 | 中 | 低 | 升级 PostgreSQL、添加索引 |
| TTS 服务卡顿 | 中 | 低 | 预缓存热门答案 |
| 网络延迟高 | 中 | 中 | CDN 加速、边缘部署 |

### 27.2 业务风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 用户增长超预期 | 高 | 低 | 水平扩展、架构优化 |
| 数据隐私泄露 | 极高 | 低 | 加密、访问控制 |
| AI 回答错误 | 中 | 中 | 人工审核、置信度过滤 |
| 学生过度依赖 | 中 | 中 | 限制追问次数 |
| 家长投诉 | 中 | 低 | 清晰报告、证据可查 |

### 27.3 运营风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 服务器故障 | 高 | 低 | 监控告警、自动恢复 |
| 数据丢失 | 极高 | 低 | 定期备份、多副本 |
| 成本超支 | 中 | 中 | 成本监控、资源优化 |

---

## 28. 成功指标 (KPI)

### 28.1 产品指标

| 指标 | 定义 | 目标值 | 测量方式 |
|------|------|--------|----------|
| 日活跃学生 | DAU | 100+ | 登录日志 |
| 周活跃学生 | WAU | 500+ | 登录日志 |
| 人均会话数 | 会话/学生/周 | 3+ | 会话统计 |
| 人均问答数 | 问答/会话 | 5+ | 问答统计 |
| 错题确认率 | 确认/疑似 | 30%+ | 错题统计 |
| 复习完成率 | 完成/安排 | 80%+ | 复习统计 |

### 28.2 技术指标

| 指标 | 定义 | 目标值 | 测量方式 |
|------|------|--------|----------|
| API 可用性 | uptime | 99.5%+ | 监控 |
| 响应时间 P99 | 第99百分位 | < 2s | APM |
| 错误率 | 错误/请求 | < 1% | 日志 |
| GPU 利用率 | 利用率 | 60-80% | 监控 |

### 28.3 用户满意度

| 指标 | 定义 | 目标值 | 测量方式 |
|------|------|--------|----------|
| 净推荐值 (NPS) | 推荐意愿 | > 40 | 问卷 |
| 任务完成率 | 成功/尝试 | > 90% | 行为分析 |
| 卸载率 | 卸载/安装 | < 10% | 统计 |

### 28.4 增长指标

| 指标 | 定义 | 目标值 | 测量方式 |
|------|------|--------|----------|
| 周增长率 | 新增/上周 | > 10% | 注册统计 |
| 留存率 D7 | 7日留存 | > 40% | 行为分析 |
| 转化率 | 试用→正式 | > 20% | 付费统计 |

---

## 29. 依赖和限制

### 29.1 外部依赖

| 服务 | 用途 | 备选方案 |
|------|------|----------|
| Ollama API | AI 问答 | 本地部署、API 兼容模型 |
| Kokoro TTS | 语音合成 | Azure TTS、Google TTS |
| Apple Developer | iOS 发布 | 企业证书 |

### 29.2 技术限制

| 限制 | 说明 |
|------|------|
| iOS 最低版本 | iOS 16.0+ |
| 图片格式 | JPEG, PNG, HEIC |
| 图片大小 | 最大 10MB |
| 语音长度 | 最大 60 秒 |
| 对话历史 | 最近 20 条 |

### 29.3 法律和合规

| 要求 | 说明 |
|------|------|
| 隐私政策 | 必须显示，用户同意 |
| 出口合规 | 已豁免 (ITSAppUsesNonExemptEncryption=false) |
| 儿童隐私 | COPPA 合规（待评估） |
| 数据保留 | 用户删除后可删除数据 |

---

## 31. 实施建议

### 31.1 立即行动 (本周)

| 任务 | 优先级 | 工作量 | 说明 |
|------|--------|--------|------|
| 数据持久化 | 🔴 紧急 | 2-3 天 | 错题/复习/画像迁移到 SQLite |
| 数据库索引 | 🟡 中 | 0.5 天 | 添加查询优化索引 |

### 31.2 短期迭代 (1-2 周)

#### v1.2.0 - 用户系统
```
Epic: 用户认证和权限管理

User Story 1: 用户注册
- 任务: POST /api/v1/auth/register API
- 任务: 密码加密 (bcrypt)
- 任务: 邮箱验证

User Story 2: 用户登录
- 任务: POST /api/v1/auth/login API
- 任务: JWT Token 生成
- 任务: Token 刷新机制

User Story 3: 角色管理
- 任务: 角色表设计
- 任务: 角色权限中间件
```

#### v1.3.0 - 数据隔离
```
Epic: 多租户数据隔离

User Story 1: 家庭管理
- 任务: 家庭表设计
- 任务: 家长-学生关联
- 任务: 邀请码机制

User Story 2: 数据权限
- 任务: 数据访问控制
- 任务: 跨家庭隔离
```

### 31.3 中期迭代 (3-4 周)

#### v1.4.0 - 管理功能
- 学习记录删除
- 数据导出 (CSV/JSON)
- 审计日志
- 提示词在线配置

#### v2.0.0 - 正式发布
- 生产环境部署
- App Store 上架
- 用户文档
- 客服支持

### 31.4 技术债务清理

| 债务项 | 影响 | 清理方式 |
|--------|------|----------|
| 内存存储 | 数据丢失风险 | 迁移到 SQLite |
| 硬编码配置 | 不灵活 | 环境变量 |
| 缺少单元测试 | 质量风险 | 添加 pytest |
| 缺少 API 文档 | 维护困难 | 添加 OpenAPI |

### 31.5 质量保障

| 检查项 | 当前状态 | 目标状态 |
|--------|----------|----------|
| 单元测试覆盖率 | 0% | > 70% |
| API 文档 | 部分 | 完整 |
| 错误处理 | 基础 | 完善 |
| 日志记录 | 基础 | 完整 |

---

## 32. 项目里程碑

### 32.1 已完成里程碑

| 日期 | 里程碑 | 状态 |
|------|--------|------|
| 2026-06-13 | v1.0.0 TestFlight 发布 | ✅ |
| 2026-06-13 | v1.1.0 版本更新 | ✅ |
| 2026-06-14 | PRD 文档完成 | ✅ |

### 32.2 计划里程碑

| 日期 | 里程碑 | 目标 |
|------|--------|------|
| 2026-06-21 | v1.1.1 数据持久化 | 数据不丢失 |
| 2026-06-28 | v1.2.0 用户系统 | 支持多用户 |
| 2026-07-05 | v1.3.0 数据隔离 | 数据安全 |
| 2026-07-12 | v1.4.0 管理功能 | 完整后台 |
| 2026-07-19 | v2.0.0 正式发布 | App Store 上架 |

### 32.3 关键决策点

| 日期 | 决策点 | 选项 |
|------|--------|------|
| v1.2.0 开发前 | 认证方式 | JWT / OAuth2 / 第三方 |
| v2.0.0 开发前 | 数据库 | SQLite / PostgreSQL |
| v2.0.0 开发前 | 部署方式 | 自托管 / 云服务 |

---

## 33. 联系和支持

### 33.1 开发团队
| 角色 | 职责 |
|------|------|
| 产品 | 产品规划、需求管理 |
| iOS 开发 | iOS App 开发 |
| 后端开发 | API 服务开发 |
| 测试 | 功能测试、验收 |
| 运维 | 部署、监控 |

### 33.2 资源链接
- 项目仓库: GitHub (待配置)
- 文档: `/home/ydz/projects/pai-cc/docs/`
- API 文档: 后端 `/docs` 路径
- iOS 构建: macstar@100.64.0.6

### 33.3 紧急联系
- 后端故障: SSH ydz@100.64.0.13
- iOS 问题: SSH macstar@100.64.0.6
- GPU 问题: SSH dell@100.64.0.5

### 30.1 需求覆盖度检查表

| 原始需求 | PRD 章节 | 覆盖状态 |
|----------|----------|----------|
| 产品一句话 | 1. 产品一句话 | ✅ 完整 |
| 适合谁使用 | 2. 适合谁使用 | ✅ 完整 |
| 功能清单 | 3. 我们可以用它做什么 | ✅ 完整 |
| 拍题解析 | 4.1 拍题解析 | ✅ 完整 |
| 智能连拍 | 4.2 智能连拍学习记录 | ✅ 完整 |
| 语音问答 | 4.3 实时语音问答 | ✅ 完整 |
| 指题追问 | 4.4 指题、追问和结束 | ✅ 完整 |
| AI 语音朗读 | 4.5 AI 语音朗读 | ✅ 完整 |
| 学习报告 | 4.6 学习报告 | ✅ 完整 |
| 学习清单 | 4.7 学习清单 | ✅ 完整 |
| 错题候选 | 4.8 错题候选 | ✅ 完整 |
| 复习队列 | 4.9 复习队列 | ✅ 完整 |
| 学习画像 | 4.10 长期学习画像 | ✅ 完整 |
| 典型场景 | 5. 典型使用场景 | ✅ 完整 |
| 当前能力 | 6. 当前已具备能力 | ✅ 完整 |
| 体验原则 | 7. 体验原则 | ✅ 完整 |
| 待补齐功能 | 8. 待补齐产品能力 | ✅ 完整 |
| 边界定义 | 9. 不做什么 | ✅ 完整 |
| 技术架构 | 10. 技术架构 | ✅ 完整 |
| API 端点 | 11. API 端点 | ✅ 完整 |
| 发布状态 | 12. 发布状态 | ✅ 完整 |

**覆盖度**：100% ✅

---

### 30.2 术语表

| 术语 | 定义 |
|------|------|
| 拍题解析 | 学生拍照后 AI 识别题目并给出解答 |
| 智能连拍 | 自动检测画面变化并记录关键帧 |
| 错题候选 | AI 检测到的疑似错题 |
| SM-2 | SuperMemo 2 间隔重复算法 |
| 复习队列 | 待复习的错题列表 |
| 学习画像 | 学生长期学习情况的统计汇总 |

### 30.2 缩略语

| 缩写 | 全称 |
|------|------|
| API | Application Programming Interface |
| TTS | Text-to-Speech |
| JWT | JSON Web Token |
| SLA | Service Level Agreement |
| QPS | Queries Per Second |
| DAU | Daily Active Users |
| WAU | Weekly Active Users |
| NPS | Net Promoter Score |

### 30.3 参考资料

- [Ollama 文档](https://github.com/ollama/ollama)
- [Kokoro TTS](https://github.com/ux-lab/kokoro)
- [FastAPI 文档](https://fastapi.tiangolo.com/)
- [Vision 框架](https://developer.apple.com/documentation/vision)
- [iOS App Store Connect](https://developer.apple.com/app-store-connect/)

---

## 文档变更记录

| 日期 | 版本 | 变更内容 | 作者 |
|------|------|----------|------|
| 2026-06-14 | 1.3 | 添加性能、风险、KPI、附录，PRD 完整版 | Claude |
| 2026-06-14 | 1.4 | 添加需求覆盖度检查表，正式交付 | Claude |
| 2026-06-14 | 1.5 | 添加实施建议、里程碑、团队信息 | Claude |

- [iOS 发布指南](./iOS-Release-Guide.md)
- [iOS 发布自动化](./ios-release-automation.md)
- [项目状态报告](./PROJECT-STATUS.md)
- [V3 项目规划](./PROJECT-V3-PLAN.md)