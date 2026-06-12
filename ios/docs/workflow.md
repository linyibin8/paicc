# PAI-CC 工作流设计文档

> 面向学生学习陪伴的拍题/智能连拍辅助系统
> 版本: v1.0.0

---

## 目录

1. [系统架构概览](#1-系统架构概览)
2. [iOS端工作流](#2-ios端工作流)
3. [后端核心工作流](#3-后端核心工作流)
4. [学习回合生命周期](#4-学习回合生命周期)
5. [结构化资产抽取工作流](#5-结构化资产抽取工作流)
6. [错题复习生命周期](#6-错题复习生命周期)
7. [Dashboard管理功能](#7-dashboard管理功能)
8. [数据流与状态机](#8-数据流与状态机)
9. [API端点设计](#9-api端点设计)

---

## 1. 系统架构概览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           iOS 客户端                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  相机采集   │  │  画面分析   │  │  智能连拍   │  │  本地缓存   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ HTTPS/WebSocket
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           后端服务                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  接收网关   │  │  图像处理   │  │  LLM 解析   │  │  任务调度   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  存储服务   │  │  分析引擎   │  │  报告生成   │  │  复习队列   │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           数据存储层                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  图片存储   │  │  PostgreSQL │  │  Redis缓存  │  │  文件系统   │    │
│  │  (对象存储) │  │  (关系数据) │  │  (队列/会话)│  │  (日志/报告)│    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Web Dashboard                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  全局中心   │  │  回合详情   │  │  学习资产   │  │  提示词配置 │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. iOS端工作流

### 2.1 拍摄模式选择

```
┌──────────────────────────────────────────────────────────┐
│                    拍摄模式选择                           │
└──────────────────────────┬───────────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           ▼                               ▼
    ┌─────────────┐                  ┌─────────────┐
    │  单张拍题   │                  │  智能连拍   │
    └─────────────┘                  └─────────────┘
           │                               │
           ▼                               ▼
    即时上传分析                     持续监控画面
           │                               │
           │            ┌─────────────────┴─────────────────┐
           │            ▼                                   ▼
           │     ┌─────────────┐                     ┌─────────────┐
           │     │ 画面质量    │                     │ 变化检测    │
           │     │ 检测        │                     │             │
           │     └─────────────┘                     └─────────────┘
           │            │                                   │
           │     ┌───────┴───────┐                 ┌───────┴───────┐
           │     ▼               ▼                 ▼               ▼
           │  质量合格       质量不合格        检测到变化      无变化
           │     │               │                 │               │
           │     ▼               ▼                 ▼               ▼
           │  上传分析      提示调整角度     采集关键帧       继续监控
           │               /放弃拍摄           │               │
           │                               ┌────┴────┐          │
           │                               ▼         ▼          │
           │                          学生在场   无人/空拍      │
           │                             │         │            │
           │                             ▼         ▼            │
           │                       上传并标记   降权/标记        │
           │                       "学习材料"  "疑似空拍"       │
           └───────────────────────┬───────────────────────────┘
                                   │
                                   ▼
                          ┌─────────────┐
                          │  生成元数据  │
                          │ capture_meta│
                          └─────────────┘
```

### 2.2 capture_meta 元数据结构

```typescript
interface CaptureMeta {
  // 基础信息
  timestamp: number;           // 拍摄时间戳
  sequence: number;            // 本回合序号
  session_id: string;          // 学习回合ID

  // 画面分析
  image_hash: string;          // 画面指纹(用于去重)
  text_token: string;          // 文本特征token
  quality_score: number;       // 画质评分 0-1
  has_learning_material: boolean;  // 是否有学习材料
  has_hand_pen_person: boolean;   // 是否有手/笔/人

  // 检测信号
  student_present: boolean;    // 学生在场信号
  material_type: 'textbook' | 'exam' | 'screen' | 'unknown';
  change_type: 'new' | 'page_turn' | 'writing' | 'erasing' | 'none';

  // 批次信息
  batch_id?: string;           // 批次ID(连拍时)
  is_key_frame: boolean;       // 是否是关键帧

  // 可选元数据
  student_goal?: string;       // 学习目标(如有)
  device_info: {
    model: string;
    os_version: string;
    orientation: 'portrait' | 'landscape';
  };
}
```

### 2.3 智能连拍决策流程

```
                    ┌─────────────────┐
                    │   持续监控画面   │
                    └────────┬────────┘
                             │
                             ▼
                 ┌───────────────────────┐
                 │   计算画面指纹 hash    │
                 └───────────┬───────────┘
                             │
                             ▼
                 ┌───────────────────────┐
                 │ 与上一帧对比 hash      │
                 └───────────┬───────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
        ┌───────────┐                 ┌───────────┐
        │ hash相同   │                 │ hash变化   │
        │ (画面静止) │                 │ (有变化)   │
        └─────┬─────┘                 └─────┬─────┘
              │                             │
              ▼                             ▼
    ┌─────────────────┐           ┌─────────────────────┐
    │ 检查质量阈值    │           │ 分析变化类型         │
    │ quality < 0.7   │           │ new/page/writing...  │
    └────────┬────────┘           └──────────┬──────────┘
             │                               │
    ┌────────┴────────┐           ┌──────────┴──────────┐
    ▼                ▼           ▼                     ▼
┌───────────┐   ┌───────────┐ ┌───────────┐      ┌───────────┐
│ 放弃上传  │   │ 降权上传  │ │ 关键帧    │      │ 常规帧    │
│ 记录日志  │   │ 标记低质量│ │ 上传分析  │      │ 可选上传  │
└───────────┘   └───────────┘ └───────────┘      └───────────┘
```

---

## 3. 后端核心工作流

### 3.1 图像接收与预处理

```
┌─────────────────────────────────────────────────────────────────┐
│                        图像接收流程                              │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   iOS 上传   │────▶│  接收服务     │────▶│  存储服务    │
│  (单张/批量) │     │  验证签名    │     │  保存原图    │
└──────────────┘     └──────────────┘     └──────────────┘
                           │                     │
                           ▼                     ▼
                    ┌──────────────┐     ┌──────────────┐
                    │  生成记录    │     │  图片元数据  │
                    │  capture_id  │     │  url/尺寸    │
                    └──────────────┘     └──────────────┘
                           │
                           ▼
                    ┌──────────────┐     ┌──────────────┐
                    │  去重检查    │────▶│  跳过重复    │
                    │  image_hash  │     │  (记录日志)  │
                    └──────────────┘     └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  加入处理    │
                    │  队列        │
                    └──────────────┘
```

### 3.2 图像质量评估

```yaml
quality_assessment:
  input: 图片 + capture_meta
  output:
    quality_score: 0.0-1.0
    issues:
      - type: "blur" | "dark" | "occluded" | "angle" | "resolution"
        severity: "low" | "medium" | "high"
        suggestion: string
  thresholds:
    accept: 0.7
    warn: 0.5-0.7
    reject: < 0.5
  actions:
    > 0.7: 正常处理
    0.5-0.7: 标记低质量,继续处理
    < 0.5: 拒绝处理,返回重拍建议
```

### 3.3 LLM 视觉解析流程

```
┌─────────────────────────────────────────────────────────────────┐
│                      LLM 批次解析流程                            │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │  批次收集完成    │
                    │  (数量/时间触发) │
                    └────────┬────────┘
                             │
                             ▼
              ┌─────────────────────────────┐
              │   构建批次解析 Prompt        │
              │   - 注入系统提示词           │
              │   - 注入学习目标/策略        │
              │   - 附加所有图片URL          │
              └──────────────┬──────────────┘
                             │
                             ▼
              ┌─────────────────────────────┐
              │      调用视觉大模型          │
              │   (带重试/并发控制)          │
              └──────────────┬──────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   解析结果验证   │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
        ┌───────────┐               ┌───────────┐
        │  解析成功  │               │  解析失败  │
        └─────┬─────┘               └─────┬─────┘
              │                           │
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │  保存解析结果   │         │  加入重试队列   │
    │  更新capture   │         │  (最多3次)       │
    └─────────────────┘         └─────────────────┘
              │
              ▼
    ┌─────────────────┐
    │  触发资产抽取   │
    │  learning_items │
    │  mistake_items  │
    └─────────────────┘
```

### 3.4 提示词配置

```
提示词路径:
  - GET/POST   /api/prompts              # 列出所有提示词
  - GET/PUT    /api/prompts/{name}       # 获取/更新特定提示词

支持配置的提示词:
  ┌─────────────────────────────────────────────────────────────┐
  │ 提示词名称                    │ 用途                        │
  ├─────────────────────────────────────────────────────────────┤
  │ system_vision_analysis       │ 视觉分析系统提示            │
  │ batch_capture_prompt         │ 批次解析提示                │
  │ final_report_prompt          │ 最终报告生成提示            │
  │ learning_item_extraction     │ 学习条目抽取提示            │
  │ mistake_item_extraction      │ 错题条目抽取提示            │
  │ quality_assessment_prompt    │ 质量评估提示                │
  │ student_profile_prompt       │ 学生画像生成提示            │
  └─────────────────────────────────────────────────────────────┘

提示词变量注入:
  {{session_id}}
  {{student_goal}}
  {{assistant_focus}}
  {{report_style}}
  {{inferred_needs}}
  {{captures[]}}
  {{previous_context}}
```

---

## 4. 学习回合生命周期

### 4.1 回合状态机

```
┌─────────────────────────────────────────────────────────────────┐
│                    学习回合状态机                                │
└─────────────────────────────────────────────────────────────────┘

                         ┌─────────────────┐
                         │     created     │
                         │    (已创建)      │
                         └────────┬────────┘
                                  │ iOS开始拍摄
                                  ▼
                         ┌─────────────────┐
                         │    active       │◀────────┐
                         │    (进行中)      │         │
                         └────────┬────────┘         │ iOS继续拍摄
                                  │                   │
                                  │ 收到结束信号       │
                                  │ 或超时30min无活动   │
                                  ▼                   │
                         ┌─────────────────┐         │
                         │   processing    │─────────┘
                         │    (处理中)      │
                         └────────┬────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
          ┌─────────────────┐         ┌─────────────────┐
          │   completed     │         │    failed       │
          │    (已完成)      │         │    (失败)       │
          └─────────────────┘         └────────┬────────┘
                                               │ 重试
                                               ▼
                                     ┌─────────────────┐
                                     │   processing    │
                                     └─────────────────┘
```

### 4.2 回合时间线分析

```yaml
timeline_analysis:
  input:
    - captures: 所有采集记录(含时间戳)
    - student_present_signals: 学生在场信号
    - capture_analysis: 每帧分析结果

  output:
    timeline:
      total_duration: number           # 总时长(秒)
      observation_time: number        # 相机观察时长
      student_active_time: number     # 学生在场活动时长
      empty_capture_time: number      # 疑似空拍时长

    segments:
      - type: "learning" | "idle" | "empty" | "transition"
        start_time: number
        end_time: number
        capture_count: number
        key_events: string[]

    events:
      - timestamp: number
        type: "new_material" | "page_turn" | "writing" | "erasing" | "student_leave" | "student_return"
        capture_id: string
```

### 4.3 最终报告生成

```
┌─────────────────────────────────────────────────────────────────┐
│                      最终报告生成流程                            │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  时间线分析  │────▶│  证据提炼    │────▶│  Prompt压缩  │
│  完成        │     │  (大回合)    │     │  (大回合)    │
└──────────────┘     └──────────────┘     └──────────────┘
       │                                         │
       │                                         ▼
       │                               ┌──────────────┐
       │                               │  报告生成    │
       │                               │  LLM调用     │
       │                               └───────┬──────┘
       │                                       │
       │          ┌────────────────────────────┤
       │          │                            │
       │          ▼                            ▼
       │   ┌──────────────┐           ┌──────────────┐
       │   │  报告成功    │           │  报告失败    │
       │   └───────┬──────┘           └───────┬──────┘
       │           │                           │
       │           ▼                           ▼
       │   ┌──────────────┐           ┌──────────────┐
       └──▶│  保存报告    │           │  生成简版    │
           │  更新状态    │           │  标记需重试  │
           └──────────────┘           └──────────────┘
```

### 4.4 报告结构

```typescript
interface SessionReport {
  session_id: string;
  generated_at: number;

  // 时间线摘要
  timeline: {
    total_duration: number;
    observation_time: number;
    student_active_time: number;
    empty_capture_time: number;
  };

  // 内容摘要
  summary: {
    total_captures: number;
    key_frames: number;
    learning_materials: number;
    estimated_questions: number;
  };

  // 学习内容
  learning_content: {
    questions: Question[];
    answers: Answer[];
    student_work: StudentWork[];
    corrections: Correction[];
  };

  // 知识点
  knowledge_points: KnowledgePoint[];

  // 错题摘要
  mistake_summary: {
    candidates: MistakeCandidate[];
    confirmed: number;
    ignored: number;
  };

  // 建议
  recommendations: {
    review_needed: string[];
    practice_needed: string[];
    mastered: string[];
  };

  // 学生画像更新
  student_profile_delta?: StudentProfileDelta;
}
```

---

## 5. 结构化资产抽取工作流

### 5.1 学习条目(learning_items)抽取

```
┌─────────────────────────────────────────────────────────────────┐
│                    学习条目抽取流程                              │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ LLM解析结果  │────▶│  结构化提取  │────▶│  存储/索引   │
│              │     │              │     │              │
│ - 题目       │     │ learning_item│     │ 搜索/筛选    │
│ - 答案       │     │ - type       │     │ 支持         │
│ - 知识点     │     │ - content    │     │              │
│ - 解析       │     │ - evidence   │     │              │
└──────────────┘     │ - metadata   │     └──────────────┘
                    └──────────────┘

learning_item 结构:
  - id: string
  - session_id: string
  - type: "question" | "answer" | "explanation" | "note" | "formula"
  - content: string
  - subject: string
  - chapter?: string
  - page_number?: string
  - question_number?: string
  - confidence: number
  - evidence_capture_ids: string[]
  - created_at: number
```

### 5.2 错题条目(mistake_items)抽取

```
┌─────────────────────────────────────────────────────────────────┐
│                    错题条目抽取流程                              │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ LLM解析结果  │────▶│  错因识别    │────▶│  订正建议    │
│              │     │              │     │              │
│ - 学生作答   │     │ - 概念错误   │     │ - 知识点    │
│ - 正确答案   │     │ - 计算错误   │     │ - 练习题    │
│ - 错误类型   │     │ - 审题错误   │     │ - 下一步    │
└──────────────┘     │ - 粗心       │     └──────────────┘
                    └──────────────┘

mistake_item 结构:
  - id: string
  - session_id: string
  - capture_id: string          # 原始图片
  - status: "suspected" | "confirmed" | "ignored" | "corrected" | "mastered"

  # 错误分析
  - mistake_type: string
  - root_cause: string
  - knowledge_points: string[]

  # 证据
  - student_answer: string      # 学生作答
  - correct_answer: string      # 正确答案
  - evidence_text: string       # LLM分析文本

  # 订正
  - correction: string
  - next_steps: string[]

  # 元数据
  - subject: string
  - chapter?: string
  - difficulty?: number
  - created_at: number
  - updated_at: number

  # 复习
  - review_status: "queued" | "scheduled" | "reviewing" | "mastered"
  - review_count: number
  - last_review_at?: number
```

### 5.3 资产文档(asset_documents)

```
asset_documents 作用:
  - 作为 learning_items 和 mistake_items 的可搜索文档镜像
  - 支持全文搜索
  - 关联原始图片证据

索引字段:
  - full_text: 全文内容
  - subject, chapter, topic
  - keywords
  - capture_ids: 关联图片
```

---

## 6. 错题复习生命周期

### 6.1 错题状态机

```
┌─────────────────────────────────────────────────────────────────┐
│                      错题状态机                                  │
└─────────────────────────────────────────────────────────────────┘

                           ┌─────────────────┐
                           │    suspected     │
                           │   (疑似错题)     │
                           └────────┬────────┘
                                    │ 用户确认
                                    ▼
                           ┌─────────────────┐
                           │    confirmed    │◀────────┐
                           │    (已确认)     │         │ 用户取消确认
                           └────────┬────────┘         │
                                    │                  │
                    ┌───────────────┼───────────────┐  │
                    │               │               │  │
                    ▼               ▼               │  │
            ┌───────────┐   ┌───────────┐           │  │
            │  ignored  │   │ corrected │           │  │
            │  (忽略)   │   │(已订正)   │           │  │
            └───────────┘   └─────┬─────┘           │  │
                                 │                  │  │
                                 ▼                  │  │
                         ┌─────────────────┐       │  │
                         │    mastered     │───────┘  │
                         │    (已掌握)     │  用户标记未掌握
                         └─────────────────┘
```

### 6.2 复习状态机

```
┌─────────────────────────────────────────────────────────────────┐
│                      复习状态机                                  │
└─────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │      queued      │
                    │     (排队中)     │
                    └────────┬────────┘
                             │ 计划复习
                             ▼
                    ┌─────────────────┐
                    │    scheduled     │◀────────┐
                    │    (已计划)     │         │ 调整计划
                    └────────┬────────┘         │
                             │ 开始复习         │
                             ▼                  │
                    ┌─────────────────┐         │
                    │    reviewing    │         │
                    │    (复习中)     │         │
                    └────────┬────────┘         │
                             │                   │
              ┌──────────────┼──────────────┐   │
              │              │              │   │
              ▼              ▼              │   │
       ┌───────────┐ ┌───────────┐        │   │
       │  mastered │ │ incorrect │────────┘   │
       │  (掌握)   │ │  (错误)   │  再次错误  │
       └───────────┘ └───────────┘            │
```

### 6.3 复习事件记录

```yaml
review_event:
  - id: string
  - mistake_id: string
  - timestamp: number

  # 结果
  - result: "correct" | "incorrect" | "postponed" | "mastered"

  # 详情
  - notes?: string
  - time_spent?: number        # 秒
  - score?: number            # 0-100

  # 复习方式
  - review_type: "self" | "assisted" | "test"

  # 关联
  - session_id?: string
```

### 6.4 复习队列生成

```
复习优先级计算:

priority = base_priority
         × difficulty_factor
         × forgetting_curve
         × streak_penalty

因子说明:
  - base_priority: 基础优先级(确认错题 > 疑似错题)
  - difficulty_factor: 难度系数(难题权重更高)
  - forgetting_curve: 根据艾宾浩斯遗忘曲线调整
  - streak_penalty: 连续错误惩罚

队列API: GET /api/review-queue
  参数:
    - student_id: 学生ID
    - limit: 返回数量
    - subject: 科目筛选
    - status: 复习状态筛选

  返回:
    - queue: MistakeItem[]
    - stats:
        total: number
        due_today: number
        mastered_today: number
```

---

## 7. Dashboard管理功能

### 7.1 全局学习中心

```
功能:
  - 查看所有学习回合列表
  - 统计: 总回合数、总学习时长、错题数、掌握率
  - 筛选: 科目、日期范围、状态
  - 排序: 时间、时长、错题数

API:
  GET /api/sessions
    ?student_id=xxx
    &from=2024-01-01
    &to=2024-12-31
    &subject=math
    &status=completed

  返回:
    - sessions: Session[]
    - pagination: { total, page, limit }
    - stats: { total_sessions, total_time, total_mistakes, mastery_rate }
```

### 7.2 回合详情页

```
功能:
  - 时间线视图
  - 所有采集图片
  - LLM分析结果
  - 生成报告
  - 学习条目列表
  - 错题列表

API:
  GET /api/sessions/{id}
    - 返回完整回合信息
    - 包含 captures, analysis, report

  POST /api/sessions/{id}/regenerate-report
    - 重新生成报告
```

### 7.3 学习资产页

```
功能:
  - 分页浏览所有 learning_items 和 mistake_items
  - 筛选: 科目/页码/题号/错题状态
  - 搜索: 关键词搜索
  - 证据缩略图

API:
  GET /api/assets
    ?type=learning_item|mistake_item
    &subject=math
    &status=suspected|confirmed|mastered
    &q=keyword
    &page=1&limit=20

  返回:
    - items: (LearningItem | MistakeItem)[]
    - pagination: { total, page, limit }
    - filters: { subjects, statuses, chapters }
```

### 7.4 提示词配置页

```
功能:
  - 列出所有可配置提示词
  - 编辑提示词模板
  - 预览解析效果
  - 版本历史

API:
  GET /api/prompts
    - 返回所有提示词列表

  GET /api/prompts/{name}
    - 返回特定提示词详情

  PUT /api/prompts/{name}
    - 更新提示词

  POST /api/prompts/{name}/preview
    - 用示例数据预览效果
```

### 7.5 学生画像

```
API:
  GET /api/student-profile
    ?student_id=xxx

  返回:
    - weak_knowledge_points: string[]      # 薄弱知识点
    - common_mistakes: MistakePattern[]    # 常见错误
    - subject_distribution: {}              # 科目分布
    - review_overview:
        total_mistakes: number
        mastered: number
        in_progress: number
        mastered_rate: number
    - learning_trends: {}                   # 学习趋势
```

---

## 8. 数据流与状态机

### 8.1 完整数据流图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              iOS 端                                      │
│                                                                          │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│  │  拍摄   │───▶│ 画面分析 │───▶│ 智能决策 │───▶│ 上传     │              │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘              │
│                     │               │               │                  │
│                     ▼               ▼               ▼                  │
│               ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│               │元数据生成│    │变化检测 │    │本地缓存 │              │
│               └─────────┘    └─────────┘    └─────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
                               │
                               ▼ HTTPS/WebSocket
┌─────────────────────────────────────────────────────────────────────────┐
│                              后端                                         │
│                                                                          │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐  │
│  │  接收网关  │───▶│  质量评估  │───▶│  去重检查  │───▶│  存储服务  │  │
│  └────────────┘    └────────────┘    └────────────┘    └────────────┘  │
│        │               │               │               │              │
│        │               ▼               ▼               ▼              │
│        │         ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│        │         │  接受/拒绝 │  │  跳过/处理 │  │  记录元数据│        │
│        │         └────────────┘  └────────────┘  └────────────┘        │
│        │                                                        │      │
│        ▼                                                        ▼      │
│  ┌────────────┐                                          ┌────────────┐ │
│  │  批次收集  │                                          │  任务调度  │ │
│  └──────┬─────┘                                          └──────┬─────┘ │
│         │                                                    │       │
│         ▼                                                    ▼       │
│  ┌────────────┐                                        ┌────────────┐   │
│  │ LLM解析    │                                        │  任务队列  │   │
│  │ 视觉大模型 │                                        │  (重试/恢复)│  │
│  └──────┬─────┘                                        └────────────┘   │
│         │                                                          │   │
│         ├──────────────────────────────────────────────────────────┤   │
│         │                                                          │   │
│         ▼                                                          ▼   │
│  ┌────────────┐                          ┌────────────────────────────┐│
│  │ 资产抽取   │                          │ 报告生成                    ││
│  │ - learning │                          │ - 时间线分析                ││
│  │ - mistake  │                          │ - 证据提炼                  ││
│  │ - asset_doc│                          │ - 生成报告                  ││
│  └──────┬─────┘                          └────────────┬───────────────┘│
│         │                                            │                │
│         ▼                                            ▼                │
│  ┌────────────┐                          ┌────────────────────────────┐│
│  │ 索引/存储  │                          │ 学生画像更新                ││
│  └────────────┘                          └────────────┬───────────────┘│
│                                                     │                │
│                                                     ▼                │
│                                            ┌────────────────────────────┐│
│                                            │ 复习队列更新                ││
│                                            └────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.2 核心状态机

```
Capture 处理状态:
  received → validating → stored → queued → processing → analyzed → indexed
                    ↓
               rejected (质量不达标)

Session 状态:
  created → active → processing → completed
                        ↓
                   failed (可重试)

MistakeItem 状态:
  suspected → confirmed → corrected → mastered
         ↓         ↓
      ignored    incorrect → (回到 confirmed)

Review 状态:
  queued → scheduled → reviewing → mastered
                                  ↓
                             incorrect → (回到 queued)
```

---

## 9. API端点设计

### 9.1 捕获相关

```yaml
/api/captures:
  POST:
    - 上传单张图片
    - body: FormData { image, meta }
    - response: { capture_id, status, duplicate }

  POST /batch:
    - 批量上传
    - body: FormData { images[], meta[] }
    - response: { captures: [], batch_id }

/api/captures/{id}:
  GET: 获取详情
  DELETE: 删除

/api/captures/{id}/analysis:
  GET: 获取分析结果
  POST: 重新分析
```

### 9.2 会话相关

```yaml
/api/sessions:
  GET: 列表 (支持分页/筛选)
  POST: 创建新会话

/api/sessions/{id}:
  GET: 详情
  PUT: 更新 (结束会话等)
  DELETE: 删除

/api/sessions/{id}/captures:
  GET: 会话中的所有捕获

/api/sessions/{id}/report:
  GET: 获取最终报告
  POST: 重新生成

/api/sessions/{id}/timeline:
  GET: 获取时间线分析
```

### 9.3 资产相关

```yaml
/api/assets:
  GET: 列表 (learning_items + mistake_items)
  ?type=learning_item|mistake_item
  ?subject=math
  ?status=suspected|confirmed|mastered
  ?q=search_keyword

/api/learning-items:
  GET: 仅学习条目
  POST: 手动创建

/api/learning-items/{id}:
  GET/PUT/DELETE

/api/mistake-items:
  GET: 错题列表
  ?status=suspected|confirmed|ignored|corrected|mastered

/api/mistake-items/{id}:
  GET/PUT/DELETE

/api/mistake-items/{id}/status:
  PUT: 更新错题状态 (confirm/ignore/corrected/mastered)

/api/mistake-items/{id}/review-events:
  GET: 复习事件列表
  POST: 添加复习事件
```

### 9.4 复习相关

```yaml
/api/review-queue:
  GET: 获取复习队列
  ?student_id=xxx
  ?limit=20
  ?subject=math

/api/review-queue/generate:
  POST: 重新生成复习队列

POST /api/review-events:
  记录复习结果
  body: { mistake_id, result, notes?, time_spent?, score? }
```

### 9.5 学生画像

```yaml
/api/student-profile:
  GET: 获取学生画像
  ?student_id=xxx

  返回:
    - weak_points: []
    - common_mistakes: []
    - subject_distribution: {}
    - review_stats: {}
    - learning_trends: {}
```

### 9.6 管理相关

```yaml
/api/prompts:
  GET: 列出所有提示词
  POST: 创建新提示词

/api/prompts/{name}:
  GET: 获取提示词详情
  PUT: 更新提示词
  DELETE: 删除

/api/prompts/{name}/preview:
  POST: 预览提示词效果

/api/logs:
  GET: 日志列表
  ?level=info|warn|error
  ?from=timestamp
  ?to=timestamp

/api/logs/stream:
  GET: SSE流式日志

/api/observability:
  GET: 系统状态
  - storage: {}
  - counts: {}
  - llm_gate: {}
  - failed_tasks: []
```

### 9.7 WebSocket 实时

```yaml
WS /ws/sessions/{session_id}:
  - capture_uploaded: 新捕获上传
  - capture_processed: 捕获处理完成
  - analysis_progress: 分析进度
  - report_ready: 报告生成完成
  - error: 错误通知
```

---

## 附录: 错误处理策略

```yaml
llm_calls:
  max_retries: 3
  retry_delay: 2s, 5s, 15s (指数退避)
  fallback: 返回简化结果或标记需重试

task_queue:
  failed_tasks: 保存状态,支持手动重试
  auto_recovery: 服务重启后自动恢复

image_storage:
  failed_upload: 客户端保留本地,稍后重试
  partial_upload: 支持断点续传
```

---

*文档版本: v1.0.0*
*生成时间: 2024*
*维护者: PAI-CC Team*