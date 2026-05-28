# ChatMessage 数据模型重构方案（统一 Block 内容体系）

## 1\. 文档概述

### 1\.1 重构背景

当前项目中 **ChatMessage** 存在严重的模型职责混乱问题，同时维护 `content`、`attachments`、`blocks` 三套内容存储体系，新旧逻辑混杂、兼容hack代码冗余、数据一致性无法保障，长期增加迭代成本、BUG风险及维护难度。

### 1\.2 核心问题

Message 与 Block 职责边界模糊，**三套内容系统并存**，无统一数据出口，衍生大量兼容逻辑与异常问题。

### 1\.3 重构目标

统一消息内容底层模型，**废弃老旧的 content、attachments 内容体系**，全网唯一保留 `blocks` 作为消息内容唯一数据源，彻底解决多体系兼容hack、数据不一致、逻辑冗余问题，实现消息内容结构化、统一化、可扩展。

## 2\. 现状问题详细分析

### 2\.1 三套内容体系并存现状

|字段/体系|来源属性|核心用途|状态|
|---|---|---|---|
|content|老旧字段|存储纯文本消息内容|待废弃|
|attachments|老旧结构字段|存储图片、文件等附件资源|待废弃|
|blocks|新结构化系统|统一承载文本、工具调用、卡片、附件、地图、事件等所有结构化消息内容|唯一保留|

### 2\.2 衍生核心问题

- **逻辑兼容成本极高**：toolMeta 逻辑需要多层 fallback 兼容新旧数据，分支逻辑臃肿混乱

- **存在临时hack代码**：为适配新旧体系差异，存在 `attachmentsOnlyMessage` 临时hack逻辑，代码不优雅且难以维护

- **数据一致性缺失**：Message 顶层字段与 Block 内部数据无法实时同步，存在内容不一致、渲染异常风险

- **扩展能力受限**：新旧体系并行，新增消息类型需要同时适配三套逻辑，迭代效率低

## 3\. 核心重构方案

### 3\.1 核心设计原则

1. **单一数据源原则**：所有消息内容、附件、结构化卡片、工具调用数据，全部收敛至 `blocks` 体系

2. **完全废弃旧字段**：彻底删除 Message 层 `content`、`attachments` 相关所有字段及逻辑

3. **职责清晰拆分**：ChatMessage 仅负责消息基础属性（ID、会话、角色、状态、时间等），ChatMessageBlock 全权负责消息内容承载

4. **平滑兼容迁移**：存量数据做兼容转换，增量数据统一走新 Block 体系，无业务中断

### 3\.2 重构后最终模型结构

重构后 **ChatMessage 不再承载任何业务内容数据**，仅保留基础元信息，所有内容由 `\[ChatMessageBlock\]` 统一承载。

**核心改造**：ChatMessage 顶层模型彻底剥离所有业务内容存储能力，仅保留消息基础元数据，完全废弃 content、attachments、kind 三大老旧内容字段，唯一保留 blocks 作为消息内容数据源。

## 4\. 全端模型改造细则

### 4\.1 数据库实体模型（ChatMessageEntity）改造

删除老旧内容相关字段，保留消息基础元数据，彻底剥离顶层内容存储能力。

**数据库实体改造要点**：清理数据库层老旧内容存储字段，删除 **attachmentsData、content、kind** 顶层内容字段，仅保留消息标识、会话关联、投递状态、时间、AI推理配置等元数据字段，所有消息结构化内容统一交由 Block 体系存储。

**改造说明**：移除`attachmentsData`、`content`、`kind` 老旧顶层字段，AI推理相关字段下沉至 Block 层，所有内容类型、业务内容全部由 Block 体系承载。

### 4\.2 客户端 Swift 模型改造

精简 ChatMessage 结构体，删除废弃的顶层内容字段，唯一保留 blocks 作为内容数据源，ChatMessageBlock 结构保持不变（已具备全类型内容承载能力）。

**客户端Swift模型改造要点**：精简 ChatMessage 结构体，彻底删除三类老旧字段：文本 content、附件 attachments、消息类型 kind。模型仅负责维护消息ID、会话ID、角色、发送状态、时间等基础元数据，所有文本、附件、结构化卡片、推理内容、工具数据均由 blocks 数组承载，实现职责完全拆分。

**改造说明**：

- 删除 `content: String` 顶层文本字段

- 删除 `attachments: \[ChatAttachment\]` 顶层附件字段

- 删除 `kind` 顶层消息类型字段，消息类型完全由 Block\.payload\.kind 判定

- 所有文本内容、附件资源、类型判定、结构化卡片、工具调用数据，全部通过 `blocks` 数组解析获取

- ChatMessageBlock 现有载荷能力 \+ 推理属性完整覆盖旧体系所有能力

### 4\.3 后端 Django 模型改造

清理后端老旧内容存储字段，剥离 Message 层内容存储职责，统一通过 Block 关联存储所有消息内容。

**后端Django模型改造要点**：清理后端老旧内容存储逻辑，删除顶层 content 文本字段、kind 消息类型字段，废弃后端多字段兼容判断逻辑。后端消息模型仅维护消息基础业务属性，所有消息内容解析、类型判定、数据读取统一对接前端标准化 Block 数据。

**改造说明**：删除后端 `content` 文本字段、`kind` 消息类型字段，后端所有消息内容、类型判断逻辑统一对接 Block 数据。

## 5\. 旧体系能力迁移方案

原 content、attachments 所有能力，全部迁移至 ChatMessageBlock 对应载荷类型，实现能力全覆盖无丢失：

1. **纯文本内容**：原 content 文本 → 迁移至 `payload\.text` 对应文本载荷（text/reasoning/translatedText 等）

2. **图片/文件附件**：原 attachments 附件数组 → 迁移至 `imageGallery`、`fileAttachments` 载荷

3. **工具调用数据**：统一由 `tool` 载荷承载，废弃原有 toolMeta fallback 兼容逻辑

4. **各类结构化卡片**：知识卡片、任务卡片、健康卡片、地图路线、事件等，沿用现有 Block 载荷能力

## 6\. SendChatMessageUseCase 模块专项重构（核心重点）

### 6\.1 模块重构背景与现存核心问题

当前 **SendChatMessageUseCase**作为消息发送核心业务模块，仍残留大量旧体系兼容逻辑，未完全适配 Block 单一数据源架构，存在严重的多字段拼接冗余问题，是本次重构的重点整改模块。

现存核心问题：

- 未遵循单一数据源规范，业务逻辑仍在拼接 **content \+ attachments \+ blocks** 三套数据，新旧体系混杂

- 消息构建依赖老旧顶层字段 `content`、`attachments`、`kind`，未完全基于 Block 结构化构建消息

- AI 返回结果处理依赖 `toolEventInterpreter\.interpret` 做二次兼容解析，存在冗余降级逻辑

- 用户消息、助手消息落库仍写入废弃旧字段，无法彻底下线老旧兼容代码

### 6\.2 重构核心规范（强制收口标准）

本次模块重构核心目标：**彻底废弃 content、attachments、kind 三大老旧字段，所有消息统一通过 BlockTree \+ ChatMessageBlock 构建，实现唯一数据源收口**。

强制禁止：业务代码中任何场景手动赋值、拼接、读取 `content`、`attachments`、`kind` 字段

统一标准：所有用户消息、AI 助手消息、结构化卡片消息、工具消息，全部通过构建 `\[ChatMessageBlock\]` 数组，组装 `ChatBlockTree` 完成消息初始化与落库

### 6\.3 核心业务逻辑重构方案

#### 6\.3\.1 用户消息构建逻辑重构

废弃旧逻辑中通过 `persistedContent`、`persistedAttachments`、`persistedKind` 组装消息的方式，统一基于业务数据构建多类型 Block 数组，再封装为 BlockTree 生成完整消息。

标准构建逻辑：

1. 基于用户输入文本、上传附件、小任务卡片，分别生成对应类型 `ChatMessageBlock`

2. 聚合所有内容块为统一 blocks 数组，自动过滤空数据

3. 通过 blocks 数组构建 `ChatBlockTree`，作为消息唯一内容数据源

4. ChatMessage 仅传入基础元数据 \+ blockTree，不携带任何老旧内容字段

重构后标准代码范式：

**用户消息构建逻辑改造点**：摒弃旧体系多字段拼接方式，不再手动组装 content、attachments 数据。根据用户输入文本、上传图片/文件附件、小任务卡片等业务数据，自动生成对应类型 ChatMessageBlock，聚合为统一 blocks 数组后封装为 BlockTree，作为消息唯一数据源完成消息构建与落库。

#### 6\.3\.2 AI 助手消息返回逻辑重构（关键升级）

彻底废弃 `toolEventInterpreter\.interpret` 冗余解析逻辑，改为由 **ChatOrchestrator** 直接返回标准化 blocks 数据，消除二次兼容转换，简化链路、减少异常风险。

核心优化点：

- AI 编排层直接输出结构化 blocks，无需前端二次解析工具事件、附件、文本数据

- AI 推理内容（reasoningText）主动组装为独立 reasoning 类型 Block，适配精细化渲染能力

- 所有 AI 返回内容、工具调用、推理数据、结构化卡片，全部收敛至 blocks 数组

- 完全删除助手消息落库时对 content、attachments、kind 字段的赋值逻辑

重构后标准代码范式：

**AI助手消息构建逻辑改造点**：废弃 toolEventInterpreter\.interpret 二次兼容解析逻辑，由 ChatOrchestrator 直接输出标准化 Blocks 数据。单独拆分 AI 推理内容为独立 reasoning 内容块，与正文块聚合组装，全程不读写任何老旧字段，实现助手消息全链路结构化构建。

### 6\.4 模块完整优化代码（适配全新架构）

重构后完整 `SendChatMessageUseCase` 代码，彻底清理旧体系字段与兼容逻辑，全链路基于 BlockTree 结构化构建消息，适配单一数据源规范：

重构后 **SendChatMessageUseCase 核心逻辑完全适配纯Block架构**，彻底肃清所有老旧字段兼容逻辑，全链路基于 BlockTree \+ ChatMessageBlock 构建消息。下文精简展示核心改造逻辑、关键代码范式，剔除冗余完整源码，聚焦重构核心要点：

#### 核心改造要点

- **数据源统一收口**：彻底废弃 content、attachments、kind 三大老旧字段，用户消息、AI助手消息、重生成消息全部通过组装 ChatMessageBlock 数组构建唯一内容数据源

- **解析链路精简**：删除 `toolEventInterpreter\.interpret` 二次兼容解析逻辑，由 ChatOrchestrator 直接输出标准化结构化 Blocks，消除中间转换冗余与异常

- **推理内容独立承载**：AI 深度思考/推理内容单独封装为 reasoning 类型 Block，支持精细化渲染、独立展开/隐藏控制

- **全流程规范统一**：消息发送、重生成、落库、流式更新全流程遵循同一套 Block 构建规范，无多分支兼容逻辑

- **附件能力完全迁移**：图片、文件附件分别收敛至 imageGallery、fileAttachments 专属 Block，废弃顶层附件字段读写逻辑

#### 精简核心代码范式

**1\. 用户消息核心构建逻辑**

```Plain Text
// 聚合文本、附件、小任务卡片为统一Block数组
let userBlocks: [ChatMessageBlock] = {
    var blocks: [ChatMessageBlock] = []
    if !sanitizedInput.isEmpty { blocks.append(.text(sanitizedInput)) }
    // 分类组装图片/文件附件Block
    let imageAtts = chatAttachments.filter { $0.kind == .image }
    let fileAtts = chatAttachments.filter { $0.kind != .image }
    if !imageAtts.isEmpty { blocks.append(.imageGallery(imageAtts)) }
    if !fileAtts.isEmpty { blocks.append(.fileAttachments(fileAtts)) }
    // 组装小任务卡片Block
    if let smallTask, let taskPayload = ChatSmallTaskMessageCardPayload(task: smallTask) {
        blocks.append(.smallTaskCard(taskPayload))
    }
    return blocks
}()
// 唯一数据源落库，仅传入元数据+BlockTree
let userBlockTree = ChatBlockTree(rootBlocks: userBlocks)
_ = try await repository.appendMessage(threadID: thread.id, role: .user, blockTree: userBlockTree, ...)
```

**2\. AI助手消息核心组装逻辑**

```Plain Text
// 编排器直接返回标准化Blocks，无二次解析
let output = try await orchestrator.generateReply(...)
// 拼接独立推理内容Block
let reasoningTrimmed = output.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
var assistantBlocks = output.blocks
if let reasoningText = reasoningTrimmed, !reasoningText.isEmpty {
    assistantBlocks.append(.reasoning(reasoningText))
}
// 纯Block结构化落库
_ = try await repository.appendMessage(threadID: thread.id, role: .assistant, blockTree: ChatBlockTree(rootBlocks: assistantBlocks), ...)
```

#### 关键方法改造说明

**execute（消息发送）**：完成附件预处理、多模态能力判断、Block聚合组装，全链路摒弃老旧字段，实现纯结构化消息构建与落库，同时保留流式回调、消息同步、会话快照返回核心能力。

**executeRegenerateReply（消息重生成）**：适配纯Block重构规范，复用统一的AI Blocks解析、推理内容组装、消息落库逻辑，删除旧体系附件、文本兼容分支，保证重生成链路与消息发送链路架构统一。

**私有工具方法**：保留线程解析、完成原因文案适配、小任务输入格式化、日志短ID工具等通用能力，无老旧逻辑残留，完全适配新架构。

### 6\.5 重构核心优化收益

1. **彻底肃清多数据源冗余**：完全废弃 content、attachments、kind 三大老旧字段，SendChatMessageUseCase 全链路唯一依赖 BlockTree 结构化数据源，彻底解决数据不一致问题

2. **精简链路、减少异常**：删除 toolEventInterpreter 二次解析逻辑，由 AI 编排层直接输出标准化 Blocks，减少中间转换异常、兼容hack代码

3. **适配精细化渲染能力**：AI 推理内容独立封装为推理块，支持单消息多内容块差异化渲染、独立展开/隐藏控制

4. **降低迭代维护成本**：新增消息类型、卡片类型仅需扩展 Block 载荷，无需修改消息发送核心逻辑，扩展性大幅提升

5. **统一全链路规范**：用户消息、AI消息、重生成消息全流程遵循同一套 Block 构建规范，代码一致性、可维护性拉满

### 6\.6 改造验收标准

- 代码层面：SendChatMessageUseCase 代码中无任何 `content`、`attachments`、`kind` 字段读写逻辑

- 链路层面：彻底移除 `toolEventInterpreter\.interpret` 工具解析兼容逻辑，AI 数据全量由 orchestrator 直接输出 Blocks

- 能力层面：文本、附件、小任务卡片、AI推理、工具调用所有场景功能正常，无数据丢失、渲染异常

- 架构层面：所有消息均通过 BlockTree 构建，严格遵循单一数据源架构规范

## 7\. 代码逻辑改造范围

原 content、attachments 所有能力，全部迁移至 ChatMessageBlock 对应载荷类型，实现能力全覆盖无丢失：

1. **纯文本内容**：原 content 文本 → 迁移至 `payload\.text` 对应文本载荷（text/reasoning/translatedText 等）

2. **图片/文件附件**：原 attachments 附件数组 → 迁移至 `imageGallery`、`fileAttachments` 载荷

3. **工具调用数据**：统一由 `tool` 载荷承载，废弃原有 toolMeta fallback 兼容逻辑

4. **各类结构化卡片**：知识卡片、任务卡片、健康卡片、地图路线等，沿用现有 Block 载荷能力

## 6\. 代码逻辑改造范围

重构完成后，彻底清理以下老旧兼容逻辑：

- 移除所有 **toolMeta 多层 fallback** 兼容分支代码

- 删除**attachmentsOnlyMessage**临时hack逻辑

- 删除所有判断 content/attachments/blocks 多体系兼容的分支判断

- 统一所有消息渲染、数据解析、工具调用、附件加载逻辑，全部基于 blocks 数据源

## 8\. 数据平滑迁移策略

### 7\.1 存量数据兼容

针对历史存量消息数据，新增数据适配转换逻辑：读取老旧 content、attachments 数据，自动转换为对应 ChatMessageBlock 载荷数据，保证历史消息正常展示、无数据丢失。

### 7\.2 增量数据规范

重构上线后，所有新增消息不再写入 content、attachments 字段，所有内容统一写入 blocks 数组，严格遵循单一数据源规范。

### 7\.3 字段下线节奏

1. 兼容期（1个迭代）：保留数据库旧字段，代码层完成新逻辑适配、旧逻辑兼容

2. 改造期（1个迭代）：全量替换业务逻辑，下线所有旧体系兼容代码

3. 清理期（1个迭代）：数据库下线废弃字段，完成模型彻底重构

## 9\. 风险与兜底方案

## 8\. 风险与兜底方案

- **数据丢失风险**：上线前新增存量数据批量转换脚本，全量校验文本、附件、卡片数据完整性

- **渲染异常风险**：兼容期双逻辑并行，新逻辑异常自动 fallback 旧逻辑，保证业务可用

- **接口兼容风险**：前后端同步改造，统一数据交互协议，避免接口数据解析失败

## 10\. 验收标准

## 9\. 验收标准

1. 模型层面：全端彻底删除 content、attachments、顶层kind 字段，仅保留 blocks 作为内容、类型唯一数据源

2. 逻辑层面：无任何多体系兼容hack代码、无 toolMeta 无效 fallback 逻辑

3. 功能层面：文本消息、附件消息、工具调用、各类结构化卡片展示、交互完全正常

4. 数据层面：存量数据迁移完整、增量数据写入规范，无数据不一致、无数据丢失

5. 一致性层面：Message 元数据与 Block 内容数据完全统一，无内容冲突、类型判定异常问题

## 11\. ChatMessageBlock 完整模型设计

## 10\. ChatMessageBlock 完整模型设计

### 10\.1 模型设计理念

在本次重构体系中，**ChatMessageBlock 是唯一的消息内容承载单元**。废弃 ChatMessage 顶层的 content、attachments 两套旧体系，同时将 AI 思考推理相关属性全部下沉至 Block 层；所有消息内容形态（文本、AI思考、工具调用、附件、各类业务卡片、富文本、错误信息等）全部收敛至 `ChatMessageBlock` 与 `ChatMessageBlockPayload`。

核心设计特点：

- **枚举多态承载**：通过枚举 case 区分所有消息内容类型，天然区分场景、类型安全

- **单一载荷出口**：一个 Block 对应一类内容载荷，杜绝多字段冗余并存

- **可无限扩展**：新增消息形态仅需新增枚举 case，无需改动顶层 Message 模型

### 10\.2 核心模型下沉说明

本次核心调整：**将全局统一的 AI 推理属性从 ChatMessage 下沉至 ChatMessageBlock**，实现「内容粒度级别的推理控制」。适配单消息多 Block、混合内容块场景，支持不同内容块独立携带推理信息、独立展开状态、独立可见性，彻底解决顶层统一字段无法适配精细化内容渲染的问题。

下沉属性清单：reasoningContent / reasoningDurationMs / reasoningExpanded / reasoningVisibility

**ChatMessageBlock核心改造要点**：将原本挂载在 ChatMessage 顶层的 AI 推理相关属性（推理内容、耗时、展开状态、可见性）**下沉至 Block 层**，实现单内容块粒度的精细化渲染控制。完善多类型载荷枚举，全覆盖文本、推理、附件、工具、各类业务卡片场景，完全替代旧体系多字段能力，同时新增便捷解析属性，简化各类结构化数据读取逻辑。

```swift
/// 消息结构化内容块单元
/// 重构核心：所有消息内容、AI推理内容、结构化业务数据的唯一承载单元
/// 顶层 ChatMessage 仅存元数据，所有业务内容全部下沉至 Block 层
struct ChatMessageBlock: Identifiable, Codable, Equatable, Sendable {
    // MARK: - 块唯一标识与关联信息
    /// 当前内容块唯一ID
    let id: UUID
    /// 内容锚点信息（用于消息编辑、内容定位、段落关联）
    let anchor: ChatBlockAnchor?
    /// 关联工具调用ID（工具类内容专属关联标识）
    let toolCallID: String?
    
    // MARK: - 核心内容载荷
    /// 多态内容载荷：承载文本、推理、工具、附件、各类业务卡片
    let payload: ChatMessageBlockPayload
    
    // MARK: - 时间属性
    /// 内容块创建时间
    let createdAt: Date
    /// 内容块最后更新时间
    let updatedAt: Date
 
    // MARK: - 便捷计算属性（内容解析兼容）
    /// 块内容类型枚举
    var kind: ChatMessageBlockKind { payload.kind }
    
    /// 通用文本提取：适配所有文本类载荷
    var text: String? {
        switch payload {
        case .text(let text),
                .reasoning(let text),
                .translatedText(let text),
                .html(let text),
                .error(let text):
            return text
        case .tool(let tool):
            return tool.content
        default:
            return nil
        }
    }
    
    /// 工具名称提取（工具载荷专属）
    var toolName: String? {
        guard case .tool(let tool) = payload else { return nil }
        return tool.name
    }
    
    /// 附件资源提取（图片/文件载荷专属）
    var attachments: [ChatAttachment] {
        switch payload {
        case .imageGallery(let attachments), .fileAttachments(let attachments):
            return attachments
        default:
            return []
        }
    }
    
    /// 知识库卡片提取
    var knowledgeCards: [ChatKnowledgeCard] {
        guard case .knowledgeCards(let cards) = payload else { return [] }
    }
    
    /// 任务卡片提取
    var taskCards: [TaskCard] {
        guard case .taskCards(let cards) = payload else { return [] }
    }
    
    /// 成员待确认工具卡片提取
    var pendingMemberToolCards: [PendingMemberToolCard] {
        guard case .pendingMemberToolCards(let cards) = payload else { return [] }
    }
    
    /// 地图点位提取
    var locations: [ChatMapLocationPayload] {
        guard case .mapRoute(let route) = payload else { return [] }
    }
    
    /// 地图路线提取
    var routes: [ChatRoutePayload] {
        guard case .mapRoute(let route) = payload else { return [] }
    }
    
    /// 日程事件提取
    var events: [ChatEventPayload] {
        guard case .events(let events) = payload else { return [] }
    }
    
    /// 普通健康卡片提取
    var healthCards: [ChatHealthCardPayload] {
        guard case .healthCards(let cards) = payload else { return [] }
    }
    
    /// 结构化健康数据提取
    var structuredHealthCards: StructuredHealthCardsBlob? {
        guard case .structuredHealthCards(let blob) = payload else { return nil }
    }
    
    /// 睡眠可视化健康数据提取
    var sleepVisualization: ChatHealthSleepModel? {
        guard case .sleepVisualization(let model) = payload else { return nil }
    }
    
    /// 采集消息卡片提取
    var captureMessageCard: ChatCaptureMessageCardPayload? {
        guard case .captureCard(let card) = payload else { return nil }
    }
    
    /// 小型任务卡片提取
    var smallTaskCard: ChatSmallTaskMessageCardPayload? {
        guard case .smallTaskCard(let card) = payload else { return nil }
    }
}

/// 消息内容载荷枚举
/// 统一承载所有消息内容类型，是重构后【唯一】的消息内容数据源
/// 替代旧体系：Message.content + Message.attachments
enum ChatMessageBlockPayload: Equatable, Sendable {
    // MARK: - 基础文本类内容
    /// 普通用户/助手正文文本
    case text(String)
    /// AI 模型思考/推理过程文本
    case reasoning(String)
    /// 翻译后的文本内容
    case translatedText(String)
    /// HTML 富文本内容
    case html(String)
    /// 错误提示文本（模型报错、接口异常、执行失败等）
    case error(String)
    
    // MARK: - 工具 & 附件类内容
    /// 工具调用执行内容
    case tool(ChatToolBlockPayload)
    /// 图片画廊附件组（多张图片）
    case imageGallery([ChatAttachment])
    /// 文件附件组（文档、压缩包、普通文件等）
    case fileAttachments([ChatAttachment])
    
    // MARK: - 通用业务卡片
    /// 知识库引用卡片组
    case knowledgeCards([ChatKnowledgeCard])
    /// 任务清单卡片组
    case taskCards([TaskCard])
    /// 小型独立任务卡片
    case smallTaskCard(ChatSmallTaskMessageCardPayload)
    /// 成员待确认工具操作卡片
    case pendingMemberToolCards([PendingMemberToolCard])
    /// 截图/采集消息卡片
    case captureCard(ChatCaptureMessageCardPayload)
    
    // MARK: - 场景化专项内容
    /// 地图路线、点位规划内容
    case mapRoute(ChatMapRouteBlockPayload)
    /// 日程/事件类消息卡片
    case events([ChatEventPayload])
    
    // MARK: - 健康专项内容
    /// 普通健康数据卡片组
    case healthCards([ChatHealthCardPayload])
    /// 结构化健康数据二进制/聚合数据
    case structuredHealthCards(StructuredHealthCardsBlob)
    /// 睡眠可视化健康模型数据
    case sleepVisualization(ChatHealthSleepModel)

    /// 载荷类型枚举映射
    /// 用于类型判断、埋点、渲染分发、数据解析
    var kind: ChatMessageBlockKind {
        switch self {
        case .text: return .text
        case .reasoning: return .reasoning
        case .tool: return .tool
        case .imageGallery: return .imageGallery
        case .fileAttachments: return .fileAttachments
        case .knowledgeCards: return .knowledgeCards
        case .translatedText: return .translatedText
        case .mapRoute: return .mapRoute
        case .events: return .events
        case .healthCards: return .healthCards
        case .pendingMemberToolCards: return .pendingMemberToolCards
        case .structuredHealthCards: return .structuredHealthCards
        case .sleepVisualization: return .sleepVisualization
        case .captureCard: return .captureCard
        case .html: return .html
        case .smallTaskCard: return .smallTaskCard
        case .taskCards: return .taskCards
        case .error: return .error
        }
    }
}

```

### 10\.3 配套说明（Kind 枚举语义对应）

`ChatMessageBlockKind` 为与 payload 一一对应的类型枚举，用于视图渲染分发、数据解析、日志埋点、新旧逻辑区分，**每一个 payload case 严格对应唯一 kind**，保证类型映射无遗漏、无错乱。

### 10\.4 新旧能力对应关系（最终收敛）

|旧体系字段|新体系 BlockPayload 承载方式|收敛说明|
|---|---|---|
|Message\.content|\.text / \.reasoning / \.translatedText / \.html / \.error|所有文本语义完全拆分，不再用单一字符串兜底|
|Message\.attachments|\.imageGallery / \.fileAttachments|图片、文件附件分类承载，语义更清晰|
|toolMeta 冗余字段|\.tool\(ChatToolBlockPayload\)|彻底废除 fallback 兼容逻辑，工具数据结构化唯一承载|

### 10\.5 重构后核心优势

1. **彻底解决职责混乱**：Message 只管纯元数据，Block 全权承载内容\+内容类型，边界绝对清晰

2. **消灭多数据源、多类型判定问题**：页面渲染、数据解析、消息类型判断统一读取 blocks 内载荷类型，无分支兼容

3. **精细化粒度控制**：推理内容、展开状态、可见性与具体内容块绑定，支持单消息多内容块差异化渲染

4. **删除所有历史 hack**：无需区分 attachmentsOnlyMessage、无需多层 toolMeta 降级、无需顶层类型兜底判断

## 12\. 工具与结构化卡片渲染流程优化

## 11\. 工具与结构化卡片渲染流程优化

### 11\.1 优化背景与现存问题

旧体系下工具调用、结构化业务卡片渲染存在严重双路径逻辑冗余：同时依赖附件体系与内容块体系，存在附件路径、卡片路径双逻辑区分、流式更新与持久化落库逻辑不一致、锚点定位错乱、增量合并覆盖异常等问题。本次基于最新模型架构深度优化，**彻底废弃 attachments 附件承载方式**，所有工具生成卡片、结构化内容统一由 `blocks: \[ChatMessageBlock\]` 唯一承载，消除双分支兼容逻辑，统一全量卡片渲染、流式更新、持久化落库流程。

为完全适配新模型架构，统一所有工具与结构化卡片的渲染、流式更新、持久化落库流程，收口所有内容更新逻辑，消除多路径兼容问题，针对性优化结构化内容合并协调逻辑。

### 11\.2 核心优化设计（适配 Block 重构架构）

5. **纯Block单一收口（核心改造）**：废弃“附件路径/卡片路径”双分支逻辑、彻底移除所有 attachments 依赖，所有工具、卡片内容更新、渲染、落库统一收口为 Block 结构化补丁，全程仅操作 `blocks` 数组

6. **完全适配最新模型规范**：严格遵循 Block 唯一数据源架构，所有结构化卡片、工具卡片、AI深度思考卡片数据全部落地至 `blocks`，无任何老旧字段兼容逻辑

7. **流式\+持久化双阶段更新**：先实时合并补丁到流式消息缓存，实现前端实时渲染；待助手消息正式落库后，再完成持久化补丁更新与服务端同步标记，解决流式渲染与落库时序错乱问题

8. **锚点精准定位**：支持 toolCallID 锚点绑定，工具卡片可精准挂载到对应工具调用块下方，解决多内容块顺序错乱、插入位置异常问题

9. **纯Block增量合并**：仅针对blocks数组做增量更新、同类型覆盖，无附件数据参与，杜绝双数据源数据丢失、不一致问题

10. **超时兜底机制**：内置最大等待时长，避免消息未落地导致的补丁永久等待、逻辑阻塞

### 11\.3 能力覆盖范围

本次优化全覆盖所有工具生成卡片、结构化卡片场景，**无任何附件参与**，全部统一由 Block 体系承载：

- 结构化健康数据卡片（药品、处方、检查报告、病历增量合并）

- 睡眠可视化健康卡片（锚点绑定工具调用块精准插入）

- 任务清单卡片批量插入与更新

- 知识库预览卡片流式渲染

- 截图采集消息卡片持久化落库

- AI深度思考结构化卡片渲染与增量更新

- 所有工具自动生成的业务结构化卡片

### 11\.4 标准化执行流程

所有工具结构化卡片统一遵循 **流式缓存预合并 \-\&gt; 消息落库监听 \-\&gt; 锚点校验 \-\&gt; 增量补丁提交 \-\&gt; 本地\+缓存双更新 \-\&gt; 标记待同步** 标准流程：

1. **实时流式合并**：将结构化内容补丁实时合并到流式消息缓存，前端无需等待落库即可实时展示卡片内容

2. **消息就绪监听**：循环监听助手消息落库状态，超时自动终止，避免阻塞

3. **锚点有效性校验**：存在工具锚点时，强制校验目标工具块已落库，防止卡片插入顺序错乱

4. **增量补丁生成**：基于原消息内容增量合并数据，生成最新结构化内容补丁

5. **统一提交更新**：合并新旧 blocks、attachments 数据，保证数据不丢失、不重复

6. **双端同步更新**：同时更新本地持久化存储与内存缓存，保证渲染与落库数据一致

7. **标记待同步状态**：标记内容需要同步至服务端，保证多端数据一致性

### 11\.5 关键优化点对比（新旧逻辑）

|优化维度|旧体系问题|新体系优化效果|
|---|---|---|
|逻辑收口|附件、卡片双逻辑分支，依赖attachments承载结构化数据，代码分散、兼容hack多、数据双写不一致|纯Block单一路径收口，彻底废弃attachments，单套逻辑维护所有结构化卡片、工具卡片|
|数据承载|依赖顶层 attachments 字段存储卡片数据，与新模型单一数据源规范严重冲突，双数据源易引发数据不一致|所有工具、卡片、深度思考数据100%落地blocks数组，完全适配最新重构架构，无冗余数据源|
|内容排序|无锚点校验，工具卡片易插入顶部、顺序错乱|锚点前置校验，严格跟随对应工具块位置，顺序精准可控|
|数据更新|全量覆盖更新，易丢失增量结构化数据|增量合并\+同类型覆盖，保证数据完整性与时效性|
|渲染体验|需等待消息落库后渲染，流式卡顿、延迟高|先缓存流式渲染、后持久化，页面实时响应无延迟|

### 11\.6 完整可编译优化代码（全注释）

**结构化卡片/工具渲染逻辑改造点**：彻底废弃 attachments 附件承载结构化卡片的双分支冗余逻辑，所有工具调用、健康卡片、任务卡片、知识库卡片、AI深度思考卡片统一通过 Block 体系承载。重构增量合并、流式渲染、持久化落库逻辑，新增锚点精准定位、超时兜底、增量覆盖能力，统一全场景更新流程，彻底解决数据不一致、渲染错乱问题。

> （注：文档部分内容可能由 AI 生成）
