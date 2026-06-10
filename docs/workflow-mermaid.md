# PAI-CC Mermaid 流程图

## 1. iOS端智能连拍流程

```mermaid
flowchart TD
    A([开始监控]) --> B[持续采集画面]
    B --> C{计算画面指纹}
    C --> D{与上一帧对比}
    D -->|相同| E[检查质量阈值]
    D -->|变化| F[分析变化类型]
    E --> G{quality >= 0.7?}
    G -->|是| H[标记关键帧]
    G -->|否| I[降权上传或放弃]
    F --> J{变化类型}
    J -->|new| K[采集新画面]
    J -->|page_turn| L[采集翻页]
    J -->|writing| M[采集书写]
    J -->|erasing| N[采集擦除]
    K --> O[生成capture_meta]
    L --> O
    M --> O
    N --> O
    H --> O
    O --> P[分批上传后端]
    I --> P
    P --> Q{上传成功?}
    Q -->|是| B
    Q -->|否| R[本地缓存重试]
    R --> B
```

## 2. 后端处理流程

```mermaid
flowchart LR
    subgraph iOS端
        A[拍摄画面] --> B[生成capture_meta]
        B --> C[上传后端]
    end

    subgraph 后端接收
        C --> D[接收服务]
        D --> E{验证签名}
        E -->|失败| F[返回错误]
        E -->|成功| G[保存原图]
        G --> H{去重检查}
        H -->|重复| I[记录日志跳过]
        H -->|新图| J[加入处理队列]
    end

    subgraph 处理流程
        J --> K[质量评估]
        K --> L{质量分数}
        L -->|< 0.5| M[拒绝返回重拍]
        L -->|0.5-0.7| N[降权处理]
        L -->|> 0.7| O[正常处理]
        N --> P[批次收集]
        O --> P
        P --> Q[触发LLM解析]
        Q --> R{解析成功?}
        R -->|否| S[重试队列]
        R -->|是| T[保存结果]
    end

    subgraph 资产抽取
        T --> U[抽取learning_items]
        T --> V[抽取mistake_items]
        U --> W[索引存储]
        V --> W
    end
```

## 3. 学习回合状态机

```mermaid
stateDiagram-v2
    [*] --> created: 创建会话
    created --> active: iOS开始拍摄
    active --> active: 继续拍摄
    active --> processing: 结束信号/超时
    processing --> completed: 处理完成
    processing --> failed: 处理失败
    failed --> processing: 重试
    completed --> [*]
    failed --> [*]
```

## 4. 错题生命周期

```mermaid
flowchart TD
    A[疑似错题] --> B{用户确认?}
    B -->|是| C[已确认错题]
    B -->|否| D[忽略]
    C --> E{订正完成?}
    E -->|是| F[已订正]
    E -->|否| G[复习中]
    G --> H{复习结果}
    H -->|正确| I[已掌握]
    H -->|错误| C
    I --> J{再次错误?}
    J -->|是| C
    J -->|否| I
```

## 5. 复习状态机

```mermaid
stateDiagram-v2
    [*] --> queued: 加入队列
    queued --> scheduled: 计划复习
    scheduled --> reviewing: 开始复习
    reviewing --> mastered: 掌握
    reviewing --> incorrect: 错误
    incorrect --> queued: 重新排队
    mastered --> [*]
```

## 6. LLM批次解析流程

```mermaid
flowchart TD
    A[批次收集完成] --> B[构建解析Prompt]
    B --> C[注入系统提示词]
    C --> D[注入学习目标/策略]
    D --> E[附加图片URLs]
    E --> F[调用视觉大模型]
    F --> G{成功?}
    G -->|是| H[验证解析结果]
    G -->|否| I{重试次数<3?}
    I -->|是| J[等待后重试]
    I -->|否| K[标记失败]
    J --> F
    H --> L[保存解析结果]
    L --> M[触发资产抽取]
    M --> N[更新capture状态]
```

## 7. 最终报告生成

```mermaid
flowchart TD
    A[会话处理完成] --> B[时间线分析]
    B --> C[提取关键事件]
    C --> D{是否为大规模会话?}
    D -->|是 大回合| E[证据提炼]
    D -->|否| F[直接生成报告]
    E --> G[Prompt压缩]
    G --> F
    F --> H[调用LLM生成报告]
    H --> I{成功?}
    I -->|是| J[保存完整报告]
    I -->|否| K[生成简化报告]
    K --> L[标记需重试]
    J --> M[更新学生画像]
    M --> N[更新复习队列]
    L --> O[后台重试]
    O --> H
```

## 8. 完整数据流

```mermaid
flowchart TB
    subgraph iOS
        A1[拍摄] --> A2[画面分析]
        A2 --> A3[智能决策]
        A3 --> A4[上传]
    end

    subgraph 后端网关
        A4 --> B1[接收]
        B1 --> B2[质量评估]
        B2 --> B3[去重检查]
        B3 --> B4[存储]
    end

    subgraph 处理引擎
        B4 --> C1[批次收集]
        C1 --> C2[LLM解析]
        C2 --> C3[资产抽取]
        C3 --> C4[报告生成]
    end

    subgraph 存储层
        B4 --> D1[图片存储]
        C2 --> D2[分析结果]
        C3 --> D3[学习资产]
        C4 --> D4[报告]
    end

    subgraph 学习闭环
        C3 --> E1[错题队列]
        C4 --> E2[学生画像]
        E1 --> E3[复习队列]
        E2 --> E3
    end

    subgraph Dashboard
        D2 --> F1[回合详情]
        D3 --> F2[资产浏览]
        D4 --> F3[报告查看]
        E3 --> F4[复习管理]
    end
```

## 9. 时序图 - 单张拍题

```mermaid
sequenceDiagram
    participant iOS
    participant Backend
    participant LLM
    participant Storage
    participant Dashboard

    iOS->>iOS: 拍摄画面
    iOS->>iOS: 生成capture_meta
    iOS->>Backend: POST /api/captures
    Backend->>Backend: 质量评估
    Backend->>Storage: 保存原图
    Backend->>Backend: 去重检查
    Backend->>LLM: 视觉解析
    LLM-->>Backend: 解析结果
    Backend->>Storage: 保存分析
    Backend->>LLM: 抽取资产
    LLM-->>Backend: learning/mistake items
    Backend->>Storage: 保存资产
    Backend-->>iOS: 返回结果
    Dashboard->>Storage: 查询资产
    Storage-->>Dashboard: 返回列表
```

## 10. 时序图 - 智能连拍回合

```mermaid
sequenceDiagram
    participant iOS
    participant Backend
    participant Queue
    participant LLM
    participant Storage

    iOS->>Backend: POST /api/sessions
    Backend-->>iOS: session_id

    loop 持续拍摄
        iOS->>iOS: 监控画面
        iOS->>iOS: 检测变化
        iOS->>iOS: 生成capture_meta
        iOS->>Backend: POST /api/captures/batch
        Backend-->>iOS: batch_id
    end

    iOS->>Backend: POST /api/sessions/{id}/end
    Backend->>Queue: 触发处理

    loop 批次处理
        Queue->>LLM: 批次解析
        LLM-->>Queue: 解析结果
        Queue->>LLM: 资产抽取
        LLM-->>Queue: 资产列表
    end

    Queue->>Storage: 保存结果
    Queue->>LLM: 生成最终报告
    LLM-->>Queue: 报告
    Queue->>Storage: 保存报告
    Queue-->>Backend: 处理完成
    Backend->>Storage: 更新学生画像
    Backend-->>iOS: 报告就绪通知
```

## 11. 复习队列优先级

```mermaid
flowchart TD
    A[所有错题] --> B[计算优先级]
    B --> C{基础优先级}
    C -->|confirmed| D[高优先级]
    C -->|suspected| E[中优先级]
    C -->|ignored| F[跳过]

    D --> G{难度系数}
    E --> G
    G --> H[× 难度因子]
    H --> I{遗忘曲线}
    I --> J[× 遗忘调整]
    J --> K{错误次数}
    K --> L[× 错误惩罚]
    L --> M[最终优先级]

    M --> N[排序队列]
    N --> O[返回复习列表]
```

## 12. Dashboard API关系

```mermaid
flowchart LR
    subgraph 管理端
        A1[全局学习中心] --> A2[回合列表]
        A2 --> A3[统计信息]

        B1[回合详情页] --> B2[时间线]
        B2 --> B3[采集图片]
        B3 --> B4[分析结果]
        B4 --> B5[最终报告]
        B5 --> B6[学习条目]
        B6 --> B7[错题列表]

        C1[学习资产页] --> C2[筛选]
        C2 --> C3[搜索]
        C3 --> C4[证据缩略图]

        D1[提示词配置] --> D2[编辑模板]
        D2 --> D3[预览效果]
        D3 --> D4[版本历史]
    end

    subgraph 数据源
        E1[会话数据]
        E2[资产数据]
        E3[报告数据]
        E4[提示词配置]
    end

    A2 --> E1
    B2 --> E1
    B3 --> E2
    B5 --> E3
    C2 --> E2
    D2 --> E4
```