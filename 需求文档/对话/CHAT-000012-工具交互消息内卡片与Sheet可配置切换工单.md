# CHAT-000012 工具交互消息内卡片与 Sheet 可配置切换工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000012 |
| 工单类型 | P1 工具交互架构 / 消息内阻塞卡片 / AI 设置配置 |
| 当前范围 | 需求与落地方案工单，指导后续 Swift 实现 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 目标设置模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 可参考实现 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 创建日期 | 2026-08-10 |
| 触发问题 | Chat 内成员选择、用户问答当前主要走全局 Sheet 队列；用户希望工具可配置为对话消息卡片形式完成阻塞式人机协作，同时保留原始 Sheet 流程并可在 AI 设置的工具区分别切换 |
| 核心目标 | 在 Chat 工具架构内新增“工具交互展示通道策略”，成员选择与用户问答分别支持 `Sheet 弹窗` / `会话卡片` 两种方式；会话卡片参考 DeepTutorChat 卡片视觉，但实现与类型完全属于 Chat |

## 1. 背景

当前 Chat 工具交互主要有两类：

```text
SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/
  ToolInteractionCoordinator.swift
  ToolInteractionSnapshot.swift
  ToolInteractionPresentationSheet.swift
  Sheets/MemberSelectionToolSheet.swift
  Sheets/ToolQuestionSheet.swift
```

这套是全局 Sheet 队列，优点是简单稳定、Continuation 清晰、不会污染消息流；缺点是用户在对话中看不到“AI 正在等我补充信息”的上下文卡片，回到历史消息时也无法看到当时的选择过程。

Chat 已经存在一张消息内成员选择卡：

```text
SparkClient/Projects/Features/Chat/Domain/ChatMessage/BlockPayloads/PendingMemberToolCard.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatPendingMemberToolCardView.swift
```

但现状只覆盖 `pendingMemberToolCards`，并且完成后只更新本地 block 与会话成员绑定，没有形成通用的“工具等待用户输入后恢复工具运行”的架构。

DeepTutorChat 内有更完整的消息内阻塞卡片体验：

```text
DeepTutorChat/Presentation/Cards/DeepTutorAskUserCardView.swift
DeepTutorChat/Presentation/Cards/DeepTutorMemberSelectionCardView.swift
DeepTutorChat/Application/DeepTutorMessageReducer.swift
DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift
```

本工单只参考体验，不复用 DeepTutorChat 类型、Reducer、Palette 或 UseCase。

## 2. 强边界

1. Chat 与 DeepTutorChat 完全独立，禁止复用 DeepTutorChat View / Domain / Reducer / Palette。
2. 不替换 Chat 现有工具运行时，不破坏 `ToolInteractionCoordinator` 的 Sheet 队列。
3. 新增能力必须作为 Chat 工具交互的一种展示通道，不新增第二套工具协议。
4. Sheet 原始流程必须保留，且默认值必须保持 Sheet，避免影响现有稳定链路。
5. 成员选择、用户问答必须分别可配置，不能只做一个总开关。

## 3. 产品目标

### 3.1 AI 设置入口

在 AI 设置中保持现有一级结构：

```text
AI 设置
├── 模型
├── 工具
│   ├── 成员选择工具
│   │   └── 提问方式：Sheet 弹窗 / 会话卡片
│   └── 用户问答工具
│       └── 提问方式：Sheet 弹窗 / 会话卡片
```

字段语义：

1. `成员选择工具` 控制 `ToolMemberSelectionPrompt` 的展示通道。
2. `用户问答工具` 控制 `ToolQuestionPrompt` 的展示通道。
3. 两个设置互不影响。
4. 默认都是 `Sheet 弹窗`。

### 3.2 用户体验目标

当配置为 `Sheet 弹窗`：

1. 行为保持当前 Chat。
2. 工具运行期间弹出原有 Sheet。
3. 用户提交后 continuation 返回工具结果。

当配置为 `会话卡片`：

1. 工具需要成员选择或用户问答时，在当前 assistant 消息内插入阻塞式交互卡片。
2. 卡片样式参考 DeepTutorChat：轻卡片、圆角、描边、选项行、已提交摘要。
3. 用户提交卡片后，卡片变成 resolved summary。
4. 工具 continuation 收到用户输入，继续原来的 Chat 工具运行链路。
5. 会话滚动应自动跟随到卡片位置，但用户已手动上滑时不强抢滚动。

## 4. 架构方案

### 4.1 核心设计

新增一层 Chat 专属展示通道策略：

```text
Tool runtime / use case
  -> ToolInteractionCoordinator
      -> 根据 AISettingsSnapshot.chatToolInteractionPreferences 选择通道
          -> SheetPresentationChannel
          -> InlineMessageCardChannel
```

注意：`ToolInteractionCoordinator` 仍是唯一的工具交互协调入口，负责串行、排队、Continuation 生命周期。

### 4.2 新增设置模型

建议新增：

```swift
nonisolated enum ChatToolInteractionPresentationMode: String, Codable, CaseIterable, Sendable {
    case sheet
    case inlineCard
}

nonisolated struct ChatToolInteractionPreferences: Codable, Equatable, Sendable {
    var memberSelectionPresentationMode: ChatToolInteractionPresentationMode
    var questionPresentationMode: ChatToolInteractionPresentationMode

    static let `default` = ChatToolInteractionPreferences(
        memberSelectionPresentationMode: .sheet,
        questionPresentationMode: .sheet
    )
}
```

落点：

```text
SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

### 4.3 新增 Chat 消息 block

建议新增两个 Chat 专属 block payload：

```swift
case toolQuestionCards([ChatToolQuestionCard])
case toolMemberSelectionCards([ChatToolMemberSelectionCard])
```

也可以先兼容复用现有 `pendingMemberToolCards`，但推荐新建 `ChatToolMemberSelectionCard`，理由：

1. 当前 `PendingMemberToolCard` 语义偏“成员资料工具待处理卡”，不是通用工具交互卡。
2. 新卡需要保存 prompt、answers、status、continuation id、resolved summary。
3. 后续可扩展为更多工具交互卡，不污染旧字段。

建议模型：

```swift
nonisolated struct ChatToolQuestionCard: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case submitted
        case cancelled
        case expired
    }

    let id: UUID
    let prompt: ToolQuestionPrompt
    var answers: [ToolQuestionResponse]
    var status: Status
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date
}

nonisolated struct ChatToolMemberSelectionCard: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case submitted
        case cancelled
        case expired
    }

    let id: UUID
    let prompt: ToolMemberSelectionPrompt
    var selectedMemberID: Int?
    var selectedMemberName: String?
    var status: Status
    var resultText: String?
    let createdAt: Date
    var updatedAt: Date
}
```

需要确认 `ToolQuestionPrompt`、`ToolMemberSelectionPrompt` 是否已 `Codable + Sendable`。如果没有，需要补齐或新增可持久化 DTO：

```swift
ChatToolQuestionCardPromptSnapshot
ChatToolMemberSelectionCardPromptSnapshot
```

## 5. 运行时流程

### 5.1 Sheet 模式

保持现状：

```text
ToolInteractionCoordinator.requestQuestionAnswer
  -> activePresentation = .question(prompt)
  -> ToolInteractionPresentationSheet
  -> ToolQuestionSheet
  -> completeQuestion
  -> continuation success
```

成员选择同理。

### 5.2 会话卡片模式

新增流程：

```text
ToolInteractionCoordinator.requestQuestionAnswer
  -> 读取 ChatToolInteractionPreferences.questionPresentationMode
  -> inlineCard
  -> 创建 ChatToolQuestionCard
  -> 追加到当前 assistant message 的 blocks
  -> continuation 挂起
  -> 用户在消息卡片内提交
  -> ChatDetailViewModel.completeInlineToolQuestionCard
  -> 更新 block 为 submitted
  -> ToolInteractionCoordinator.completeInlineQuestion
  -> continuation success
  -> 原 Chat 工具链继续执行
```

成员选择：

```text
ToolInteractionCoordinator.requestMemberSelection
  -> inlineCard
  -> 创建 ChatToolMemberSelectionCard
  -> 插入当前 assistant message
  -> 用户选择成员
  -> 更新会话成员绑定
  -> 更新 block 为 submitted
  -> continuation success(memberID)
```

关键点：会话卡片不是 DeepTutorChat 的“同 assistant resume stream”模型；Chat 首版应符合当前工具架构，让原工具 continuation 恢复执行，继续写工具结果 / 文本块。

## 6. Coordinator 改造

### 6.1 当前问题

`ToolInteractionCoordinator` 当前只知道 `activePresentation`，没有消息上下文写入能力。

### 6.2 建议新增协议

```swift
@MainActor
protocol ChatInlineToolInteractionCardSink: AnyObject {
    func presentInlineQuestionCard(
        threadID: UUID?,
        prompt: ToolQuestionPrompt,
        completionID: UUID
    ) async

    func presentInlineMemberSelectionCard(
        threadID: UUID?,
        prompt: ToolMemberSelectionPrompt,
        completionID: UUID
    ) async
}
```

`ChatDetailViewModel` 或专门的 `ChatInlineToolInteractionCardService` 实现该协议，负责：

1. 找到当前运行中的 assistant message。
2. 没有 assistant message 时创建一个 pending assistant message。
3. 插入 inline card block。
4. 持久化并刷新 `ChatStateStore`。

### 6.3 Coordinator 中保存挂起 continuation

新增 completion 类型：

```swift
case inlineQuestion(UUID, CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>)
case inlineMember(UUID, CheckedContinuation<InteractionResult<Int>, Never>)
```

其中 UUID 是 card / completion id。卡片提交时通过 id 找回 continuation。

## 7. UI 落点

新增目录：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ToolInteraction/
  ChatToolQuestionMessageCardView.swift
  ChatToolMemberSelectionMessageCardView.swift
  ChatToolInteractionCardChrome.swift
  ChatToolInteractionResolvedSummaryView.swift
```

视觉要求：

1. 参考 DeepTutorChat 的卡片层级：16pt padding、圆角、描边、柔和背景、选项行。
2. 不复用 `DeepTutorPalette`，新增 Chat 自己的 `ChatToolInteractionCardStyle` 或局部常量。
3. 问答卡支持单选、多选、其他输入。
4. 成员选择卡支持成员头像、姓名、关系、年龄、性别。
5. 提交后显示 resolved summary。
6. running / submitted 状态下禁用重复提交。

## 8. ChatMessageBlock 渲染接入

修改：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatRenderContext.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ChatConversationMessageRow.swift
```

新增 context 回调：

```swift
let onToolQuestionCardSubmit: (ChatToolQuestionCard, [ToolQuestionResponse]) -> Void
let onToolMemberSelectionCardSubmit: (ChatToolMemberSelectionCard, Int) -> Void
```

回调落到 `ChatDetailViewModel`：

```swift
func submitInlineToolQuestionCard(...)
func submitInlineToolMemberSelectionCard(...)
```

## 9. 与 SwiftUI 会话架构的关系

`CHAT-000011` 已增加 UIKit / SwiftUI 会话列表切换。本工单卡片必须同时支持两套列表：

1. UIKit 经典列表通过现有 `ChatConversationMessageRow` 渲染卡片。
2. SwiftUI 新架构当前也复用 `ChatConversationMessageRow`，因此首版只要接入 `ChatMessageBlock+Render` 即可两边生效。
3. 后续如果 SwiftUI 会话拆出独立 bubble，再迁移同一套卡片 View。

## 10. 状态与异常

### 10.1 卡片状态

```text
pending     等待用户输入
submitted   用户已提交，工具继续执行
cancelled   用户取消或工具取消
expired     会话恢复时 continuation 不存在，卡片不可再提交
```

### 10.2 恢复策略

应用重启或会话重载后：

1. `submitted` 卡片正常展示摘要。
2. `pending` 但 continuation 不存在时标记为 `expired`。
3. `expired` 卡片提示“本次工具等待已失效，请重新发送请求”。
4. 不允许点击一个历史 pending 卡片触发未知 continuation。

## 11. 设置页落地

建议在 AI 设置工具区新增：

```text
工具
  成员选择工具
    提问方式: Sheet 弹窗 / 会话卡片
  用户问答工具
    提问方式: Sheet 弹窗 / 会话卡片
```

实现方式：

1. 直接在 `AISettingsView` 的工具 Section 中增加两个 Picker。
2. 或新增 `AIToolInteractionSettingsView`，从工具 Section 进入二级页面。

首版推荐直接在工具 Section 增加两行 Picker，成本更低。

## 12. 验收标准

1. 默认设置下，成员选择与用户问答仍走原 Sheet。
2. 设置成员选择为会话卡片后，触发成员选择工具时不弹 Sheet，而是在消息内显示成员选择卡。
3. 设置用户问答为会话卡片后，触发用户问答工具时不弹 Sheet，而是在消息内显示问答卡。
4. 成员选择和用户问答可以分别切换，互不影响。
5. 会话卡片提交后，卡片显示已提交摘要，不能重复提交。
6. 提交后 Chat 原工具运行链路继续执行，不丢工具结果、不丢后续 AI 回复。
7. UIKit 会话列表和 SwiftUI 会话列表均可渲染卡片。
8. DeepTutorChat 不受任何影响。
9. 构建通过：

```bash
xcodebuild -project SparkClient.xcodeproj -scheme SparkClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## 13. 推荐分期

### 13.1 第一阶段：设置与策略层

1. 新增 `ChatToolInteractionPreferences`。
2. 持久化到 `AISettingsSnapshot.PreferencesPayload`。
3. 设置页工具区新增两个 Picker。
4. `ToolInteractionCoordinator` 支持读取展示通道策略。

### 13.2 第二阶段：消息内卡片基础能力

1. 新增 Chat inline question / member card 模型。
2. 新增 block payload 与 CoreData 编解码。
3. 新增消息卡片 View。
4. 接入 `ChatMessageBlock+Render`。

### 13.3 第三阶段：Continuation 与工具恢复

1. `ToolInteractionCoordinator` 对 inline card 建立 completion id。
2. `ChatDetailViewModel` 负责提交卡片并唤醒 continuation。
3. 补齐 expired / cancelled 状态。

### 13.4 第四阶段：体验打磨

1. 卡片视觉对齐 DeepTutorChat 的层级，但使用 Chat 自己的样式常量。
2. 流式过程中滚动到卡片。
3. SwiftUI 会话架构下验证刷新不闪屏。

## 14. 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| pending 卡片跨重启后 continuation 丢失 | 用户可能点击无效卡片 | 重载时标记 expired |
| 同一工具多次触发导致多张卡 | 重复等待 / 重复提交 | completion id + prompt id 去重 |
| Sheet 与 inline 两套状态分叉 | 工具结果不一致 | Coordinator 仍作为唯一等待入口 |
| 成员选择顺带更新会话绑定 | 影响后续工具上下文 | 与当前 Chat 行为保持一致，提交成员卡后同步更新 thread member binding |
| 与 DeepTutorChat 边界混乱 | 后续维护困难 | 只参考样式，不引用类型或代码 |

## 15. 最终实现原则

这不是“把 Sheet 改成卡片”，而是给 Chat 工具交互增加可配置展示通道：

```text
同一套工具等待语义
同一个 ToolInteractionCoordinator
同一个 continuation 生命周期
两种 UI 展示方式
设置内分别切换
```

Chat 的正确落地形态是：

```text
Sheet 模式：稳定保留
会话卡片模式：消息内阻塞式人机协作
DeepTutorChat：仅作体验参考，完全不复用
```

## 16. 代码落地记录

### 16.1 已实现代码位置

设置与持久化：

```text
SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

工具值模型隔离修正：

```text
SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift
```

Chat 消息内卡片模型：

```text
SparkClient/Projects/Features/Chat/Domain/ChatMessage/BlockPayloads/ChatToolInteractionCards.swift
SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift
```

Chat 消息内卡片渲染：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ToolInteraction/ChatToolInteractionMessageCards.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBubbleContentView.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatRenderContext.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ChatConversationMessageRow.swift
```

工具交互通道与提交闭环：

```text
SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionCoordinator.swift
SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
```

本地工具展示块保护：

```text
SparkClient/Projects/Features/Chat/Application/MessageRunActor.swift
SparkClient/Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift
```

### 16.2 已落地能力

1. AI 设置 > 工具区新增 `成员选择工具` 与 `用户问答工具` 两个 Picker。
2. 两个工具分别支持 `Sheet 弹窗` / `会话卡片`。
3. 默认保持 `Sheet 弹窗`，原流程保留。
4. `ToolInteractionCoordinator` 新增 inline card 通道，仍作为唯一 continuation 等待入口。
5. `ChatDetailViewModel` 实现 `ChatInlineToolInteractionCardSink`，负责插入消息内卡片、持久化 block、提交后唤醒 continuation。
6. 新增 `ChatToolQuestionCard` 和 `ChatToolMemberSelectionCard`，均为 Chat 专属模型。
7. 新增 `toolQuestionCards` 和 `toolMemberSelectionCards` 两类 Chat message block payload。
8. 新增 Chat 专属问答卡与成员选择卡 UI，样式参考 DeepTutorChat 但不复用其类型或 Palette。
9. UIKit 会话列表与 `CHAT-000011` SwiftUI 会话列表都通过 `ChatConversationMessageRow` 渲染，因此两套列表均可显示新卡片。
10. 会话卡片提交后会更新为 resolved summary，并继续原 Chat 工具链路。
11. 本地 inline 工具卡按 toolPresentation 富块保护，避免同步/刷新时被轻易冲掉。

### 16.3 编译验收

已执行：

```bash
xcodebuild -project SparkClient.xcodeproj -scheme SparkClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

结果：构建通过。当前输出仍包含工程既有 warning，本工单新增代码无阻断编译错误。
