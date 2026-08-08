# DEEPTUTORCHAT-000040 DeepTutorChat 与 Chat 工具交互模式隔离优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000040 |
| 工单类型 | P0 交互隔离 / 工具使用模式统一 / DeepTutorChat 工具卡片补齐 |
| 当前范围 | 创建优化工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 关联模块 | `Chat`、`DeepTutorChat`、`ToolHub`、`ToolInteractionCoordinator`、`ChatOrchestrator` |
| 创建日期 | 2026-08-08 |
| 触发问题 | DeepTutorChat 和 Chat 共用同一套工具运行时，但工具交互 UI、资料选择、授权弹窗、资料卡片没有完全隔离；DeepTutorChat 内触发工具交互时可能打开 Chat 的 Sheet，这是错误体验 |
| 核心目标 | 底层工具运行时继续共享，上层对话系统的工具交互、消息卡片、资料选择与授权呈现必须按 Chat / DeepTutorChat 两套 UI 隔离 |

## 1. 问题背景

当前 `Chat` 和 `DeepTutorChat` 共用：

```text
ChatOrchestrator
ToolHub
ToolInteractionCoordinator
AI Runtime Tool Definitions
Health resource tools
Consent tools
Member selection tools
Ask user tools
```

这个共享底层是合理的，因为工具执行、权限判断、模型 tool call、工具结果回灌不应该重复实现。

真正的问题在 Presentation 层：

```text
Chat 使用全局 Sheet
DeepTutorChat 应使用消息内卡片或 DeepTutor 专属 Sheet
```

但当前 DeepTutorChat 只完整实现了：

```text
ask_user -> DeepTutorAskUserCardView
request_member_selection -> DeepTutorMemberSelectionCardView
```

对于数据授权、健康资料候选、多资料选择、问报告资料选择、工具结果资料卡片等场景，DeepTutorChat 还没有完整隔离，导致底层 `ToolInteractionCoordinator` 触发交互时，可能走到 Chat 的 `ToolInteractionPresentationSheet` / `ChatAskReportSheet` / `ChatHealthSourceCandidateSheet`。

这会造成几个明显问题：

1. DeepTutorChat 页面出现 Chat 风格的授权或资料选择弹窗。
2. DeepTutorChat 的消息流中没有对应资料卡片，用户选择完资料后难以理解上下文。
3. 工具结果只出现在 trace 或 JSON 里，没有成为 DeepTutorChat 原生消息结构。
4. 两个对话系统共用 coordinator，但缺少“交互宿主归属”的隔离边界。

## 2. 产品目标

### 2.1 目标

1. Chat 和 DeepTutorChat 继续共用底层工具运行时。
2. Chat 的工具交互继续走现有全局 Sheet。
3. DeepTutorChat 的工具交互优先走消息内卡片。
4. 必须弹窗的场景，DeepTutorChat 使用 DeepTutor 专属 Sheet，不复用 Chat Sheet。
5. 健康资料、授权、成员选择、工具追问、资料候选选择都要能在 DeepTutorChat 内被理解、操作、恢复和回放。
6. 工具副作用数据要能映射为 DeepTutorMessageBlock，而不是只服务 ChatMessageBlock。

### 2.2 非目标

1. 不重写 `ToolHub`。
2. 不拆掉共享 `ChatOrchestrator`。
3. 不要求 Chat 改成消息内卡片。
4. 不把 DeepTutorChat 强行接入 Chat 的完整 UI。
5. 不在本工单内重做健康资料业务模型。

## 3. 核心原则

### 3.1 底层共享

以下层继续共用：

```text
Core/AIRuntime/ChatOrchestrator.swift
Core/AIRuntime/ToolHub
ChatOrchestratorInferenceOptions
AIRuntimeToolDefinition
ToolExecutionResult
ToolSideEffect
```

### 3.2 交互隔离

以下层必须隔离：

```text
Chat Presentation Sheet
DeepTutorChat Presentation Card / Sheet
ChatMessageBlock
DeepTutorMessageBlock
Chat ask report picker
DeepTutor ask report card / picker
Chat health resource reference card
DeepTutor health resource reference card
```

### 3.3 按宿主路由

工具交互必须知道当前由哪个对话系统发起：

```text
host = chat
host = deepTutorChat
```

同一个 `ToolInteractionCoordinator` 可以共享，但 active presentation 需要带 host，或者在 DeepTutorChat 内使用独立的 interaction adapter。

## 4. 当前链路分析

### 4.1 Chat 链路

Chat 当前完整链路：

```text
ChatView
  -> ToolInteractionPresentationSheet
  -> ExternalToolDataConsentSheet
  -> ToolQuestionSheet
  -> MemberSelectionToolSheet
  -> ChatHealthSourceCandidateSheet
  -> ChatAskReportSheet

SendChatMessageUseCase
  -> ChatOrchestrator
  -> ToolHub
  -> MessageRunActor
  -> ToolSideEffectBlockMapper
  -> ChatMessageBlock.healthResourceReference
```

Chat 的交互特点：

1. 工具交互通过全局 Sheet 呈现。
2. 工具副作用通过 `MessageRunActor` 写入 `ChatMessageBlock`。
3. 问报告由 Composer 手动入口打开 `ChatAskReportSheet`。
4. 健康资料候选通过 `ChatHealthSourceCandidateSheet` 多选。

### 4.2 DeepTutorChat 链路

DeepTutorChat 当前链路：

```text
DeepTutorChatPage
  -> DeepTutorChatViewModel
  -> SendDeepTutorAIMessageUseCase
  -> DeepTutorAIRuntimeAdapter
  -> ChatOrchestrator
  -> ToolHub
```

DeepTutorChat 已有内联能力：

```text
preferInlineAskUser = true
preferInlineMemberSelection = true

ask_user -> DeepTutorAskUserCardView
request_member_selection -> DeepTutorMemberSelectionCardView
```

DeepTutorChat 当前缺口：

1. 没有 DeepTutor 专属授权卡片或授权 Sheet。
2. 没有 DeepTutor 专属健康资料候选选择卡片。
3. 没有 DeepTutor 专属问报告资料选择入口。
4. 没有 DeepTutor 健康资料引用消息卡片。
5. 没有 DeepTutor 版 `ToolSideEffect -> DeepTutorMessageBlock` mapper。
6. 没有 host 级别的工具交互隔离。

## 5. 目标架构

### 5.1 总体结构

```text
                 Shared Runtime
┌────────────────────────────────────────────┐
│ ChatOrchestrator                            │
│ ToolHub                                     │
│ ToolInteractionCoordinator Protocol          │
│ ToolExecutionResult / ToolSideEffect         │
└────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
 Chat Interaction Host     DeepTutor Interaction Host
        │                         │
        ▼                         ▼
 Chat Sheet UI             DeepTutor Inline Cards / Sheets
        │                         │
        ▼                         ▼
 ChatMessageBlock          DeepTutorMessageBlock
```

### 5.2 DeepTutorChat 优先策略

DeepTutorChat 工具交互优先级：

```text
1. 能内联卡片解决的，一律消息内卡片
2. 必须打断的敏感授权，使用 DeepTutor 专属 Sheet 或内联授权卡片
3. 不能复用 Chat Sheet
4. 如果 DeepTutor 专属 UI 尚未实现，fail closed：提示当前工具交互暂不可用，不跳到 Chat UI
```

### 5.3 两套对话系统的隔离边界

| 能力 | Chat | DeepTutorChat |
| --- | --- | --- |
| 工具执行 | 共享 ToolHub | 共享 ToolHub |
| 模型工具循环 | 共享 ChatOrchestrator | 共享 ChatOrchestrator |
| 追问 | `ToolQuestionSheet` | `DeepTutorAskUserCardView` |
| 成员选择 | `MemberSelectionToolSheet` | `DeepTutorMemberSelectionCardView` |
| 数据授权 | `ExternalToolDataConsentSheet` | `DeepTutorToolConsentCardView` 或 `DeepTutorToolConsentSheet` |
| 健康资料候选 | `ChatHealthSourceCandidateSheet` | `DeepTutorHealthResourceCandidateCardView` |
| 问报告资料选择 | `ChatAskReportSheet` | `DeepTutorAskReportPickerCardView` 或 DeepTutor 专属 Sheet |
| 资料引用卡 | `ChatMessageBlock.healthResourceReference` | `DeepTutorMessageBlock.healthResourceReference` |
| 工具副作用落库 | `MessageRunActor` | `DeepTutorToolSideEffectMapper` + DeepTutor message upsert |

## 6. 核心流程

### 6.1 DeepTutorChat 工具交互总流程

```text
用户发送 DeepTutorChat 消息
  -> DeepTutorAIRuntimeAdapter.stream
  -> ChatOrchestrator.generateReply
  -> ToolHub 执行工具
  -> 工具需要人机交互
  -> 根据 host=deepTutorChat 路由
  -> 生成 DeepTutorStreamEvent
  -> DeepTutorMessageReducer 转成 DeepTutorMessageBlock
  -> DeepTutor 专属卡片展示
  -> 用户在卡片内选择 / 授权 / 回答
  -> submit resume
  -> ChatOrchestrator 继续同一 turn
  -> 工具结果和副作用映射为 DeepTutor 卡片
```

### 6.2 授权流程

目标：

DeepTutorChat 触发敏感工具时，不打开 Chat 的 `ExternalToolDataConsentSheet`。

建议流程：

```text
ToolHub.applyModelEgressConsentIfNeeded
  -> requestConsentDecision(host: .deepTutorChat)
  -> DeepTutorToolConsentRequested event
  -> DeepTutorToolConsentCardView
  -> 用户选择 拒绝 / 允许一次 / 始终允许
  -> submitToolConsent
  -> ToolHub 收到 decision
  -> 继续工具执行
```

如果授权必须用 Sheet：

```text
DeepTutorChatPage
  -> .sheet(item: deepTutorToolInteractionCoordinator.activePresentation)
  -> DeepTutorToolInteractionPresentationSheet
  -> DeepTutorToolConsentSheet
```

但首选仍是消息内卡片，因为 DeepTutorChat 的 agent-native 体验更强调“对话内可恢复”。

### 6.3 成员选择流程

当前 DeepTutorChat 已有：

```text
request_member_selection
  -> isAwaitingUserInput
  -> memberSelectionRequested event
  -> DeepTutorMemberSelectionCardView
  -> submitMemberSelection
  -> resumeMemberSelectionStream
```

本工单要求：

1. 保留现有内联卡片。
2. 移除或限制 Chat Sheet fallback。
3. 隐式成员选择也必须走 DeepTutor 卡片，例如 `query_member_profile` 缺少 member_id 时。

### 6.4 ask_user 流程

当前 DeepTutorChat 已有：

```text
ask_user
  -> askUser event
  -> DeepTutorAskUserCardView
  -> submitAskUser
  -> resumeStream
```

本工单要求：

1. 保持 DeepTutor 内联追问。
2. Chat 继续使用 `ToolQuestionSheet`。
3. 两边不要共享 Presentation View。

### 6.5 健康资料候选选择流程

当前 Chat：

```text
list_member_health_sources
  -> candidates >= 2
  -> ChatHealthSourceCandidateSheet
  -> selected resources
  -> healthResourceReference block
```

DeepTutorChat 目标：

```text
list_member_health_sources
  -> candidates >= 2
  -> DeepTutorHealthResourceCandidateRequested event
  -> DeepTutorHealthResourceCandidateCardView
  -> 用户在消息卡片内多选
  -> submitHealthResourceCandidates
  -> resume same assistant message
  -> DeepTutorMessageBlock.healthResourceReference
```

### 6.6 问报告资料选择流程

Chat 当前有 Composer 问报告按钮：

```text
presentAskReportPicker
  -> ChatAskReportSheet
  -> appendAskReportRefs
  -> 用户消息插入 healthResourceReference block
```

DeepTutorChat 目标：

```text
DeepTutorComposer 问报告入口
  -> DeepTutorAskReportPickerCard / Sheet
  -> 用户选择资料
  -> 写入 draft references
  -> 发送消息时生成 DeepTutorMessageBlock.healthResourceReference
  -> DeepTutor prompt / tool context 接收 health resource context
```

## 7. 数据结构设计

### 7.1 Tool Interaction Host

新增宿主枚举：

```swift
enum ToolInteractionHost: String, Codable, Sendable {
    case chat
    case deepTutorChat
}
```

建议放置：

```text
Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionHost.swift
```

如果不希望放在 Chat 目录，也可下沉到：

```text
Projects/Core/AIRuntime/ToolHub/Models/ToolInteractionHost.swift
```

### 7.2 Active Presentation 增加 host

```swift
extension ToolInteractionCoordinator {
    struct ActivePresentation: Identifiable, Sendable {
        let id: UUID
        let host: ToolInteractionHost
        let snapshot: ToolInteractionSnapshot
    }
}
```

约束：

1. `ChatView` 只消费 `host == .chat`。
2. `DeepTutorChatPage` 只消费 `host == .deepTutorChat`。
3. 没有 host 的旧调用默认 `.chat`，保证 Chat 不破。

### 7.3 DeepTutor 工具卡片 Block

在 `DeepTutorMessageBlockKind` 增加：

```swift
case toolConsent
case healthResourceCandidateSelection
case healthResourceReference
case askReportPicker
```

新增 payload：

```swift
struct DeepTutorToolConsentPayload: Codable, Equatable, Sendable {
    let toolName: String
    let title: String
    let summary: String
    let dataTypes: [String]
    let rememberAllowedSupported: Bool
}

struct DeepTutorHealthResourceCandidatePayload: Codable, Equatable, Sendable {
    let toolCallID: String
    let memberID: Int
    let candidates: [DeepTutorHealthResourceCandidate]
    let minSelectionCount: Int
    let maxSelectionCount: Int?
}

struct DeepTutorHealthResourceReferencePayload: Codable, Equatable, Sendable {
    let resourceType: String
    let resourceID: Int
    let memberID: Int
    let title: String
    let subtitle: String?
    let sourceDateText: String?
}

struct DeepTutorAskReportPickerPayload: Codable, Equatable, Sendable {
    let memberID: Int?
    let selectedReferences: [DeepTutorHealthResourceReferencePayload]
    let allowsMultipleSelection: Bool
}
```

### 7.4 DeepTutor Stream Event 扩展

在 `DeepTutorStreamEvent` 增加：

```swift
case toolConsentRequested(payload: DeepTutorToolConsentPayload, toolCallID: String)
case toolConsentResolved(toolCallID: String, decision: DeepTutorToolConsentDecision)
case healthResourceCandidateSelectionRequested(payload: DeepTutorHealthResourceCandidatePayload)
case healthResourceCandidateSelectionResolved(toolCallID: String, selectedResourceIDs: [Int])
case healthResourceReferenceCreated(payload: DeepTutorHealthResourceReferencePayload)
```

### 7.5 Tool Side Effect 映射

Chat 现有：

```text
ToolSideEffectBlockMapper
  -> ChatMessageBlock
```

DeepTutorChat 新增：

```text
DeepTutorToolSideEffectMapper
  -> DeepTutorMessageBlock
```

示例：

```swift
enum DeepTutorToolSideEffectMapper {
    static func blocks(from sideEffects: [ToolSideEffect]) -> [DeepTutorMessageBlock] {
        sideEffects.compactMap { sideEffect in
            switch sideEffect {
            case let .healthResourceReference(resourceType, resourceID, memberID):
                return DeepTutorMessageBlock(
                    kind: .healthResourceReference,
                    payload: .healthResourceReference(
                        DeepTutorHealthResourceReferencePayload(
                            resourceType: resourceType,
                            resourceID: resourceID,
                            memberID: memberID,
                            title: "\(resourceType) #\(resourceID)",
                            subtitle: nil,
                            sourceDateText: nil
                        )
                    )
                )
            default:
                return nil
            }
        }
    }
}
```

## 8. 按文件拆分的落地清单

### 8.1 共享层文件

#### `Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionCoordinator.swift`

改造点：

1. 给 active presentation 增加 `host`。
2. 给请求方法增加 host 参数：
   - `requestConsentDecision(..., host:)`
   - `requestMemberSelection(..., host:)`
   - `requestQuestionAnswer(..., host:)`
   - `requestHealthResourceCandidateSelection(..., host:)`
   - `presentAskReportPicker(..., host:)`
3. 旧方法保留默认 host `.chat`，减少 Chat 改动。

核心示例：

```swift
func requestConsentDecision(
    _ prompt: ToolConsentPrompt,
    host: ToolInteractionHost = .chat
) async -> Result<ToolConsentDecision, ToolInteractionError> {
    await enqueue(.consent(prompt), host: host)
}
```

#### `Projects/Core/AIRuntime/ToolHub/ToolHub+Consent.swift`

改造点：

1. 从 tool execution context 读取 host。
2. 调用 `requestConsentDecision(..., host: context.interactionHost)`。
3. DeepTutorChat 触发时，不再落到 Chat 默认 Sheet。

#### `Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift`

改造点：

1. 如果当前 tool context 没有 host 字段，新增 `interactionHost`。
2. 默认 `.chat`，DeepTutorChat adapter 显式传 `.deepTutorChat`。

### 8.2 Chat 层文件

#### `Projects/Features/Chat/Presentation/ChatView.swift`

改造点：

1. Sheet binding 只接收 `active.host == .chat`。
2. 防止 DeepTutorChat 的 active presentation 被 ChatView 消费。

核心示例：

```swift
.sheet(
    item: Binding(
        get: {
            guard detailViewModel.toolInteractionCoordinator.activePresentation?.host == .chat else {
                return nil
            }
            return detailViewModel.toolInteractionCoordinator.activePresentation
        },
        set: { _ in }
    )
) { active in
    ToolInteractionPresentationSheet(active: active, ...)
}
```

#### `Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionPresentationSheet.swift`

改造点：

1. 保持 Chat 专属 Sheet router。
2. 如果收到 `host != .chat`，直接不渲染或 assertion 日志。
3. 文档里明确它不是全 App 工具交互入口，而是 Chat 工具交互入口。

### 8.3 DeepTutorChat 层文件

#### `Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift`

改造点：

1. 调用 `ChatOrchestrator.generateReply` 时传入 DeepTutor host。
2. 保留 `preferInlineAskUser: true` 和 `preferInlineMemberSelection: true`。
3. 将 tool partial / sideEffect 映射为 DeepTutorStreamEvent。
4. 不直接触发 Chat Sheet fallback。

建议新增字段：

```swift
let interactionHost: ToolInteractionHost = .deepTutorChat
```

#### `Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeEventMapper.swift`

改造点：

1. 新增 consent、health resource candidates、health resource reference 的事件映射。
2. 所有 DeepTutor 工具交互都先变成 `DeepTutorStreamEvent`。

#### `Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift`

改造点：

1. 将新增 event 转换为 DeepTutorMessageBlock。
2. 支持 pending / resolved / failed 状态。
3. 确保同一个 toolCallID 的卡片可以原地更新。

#### `Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift`

改造点：

1. 新增 block kind。
2. 新增 payload。
3. 兼容旧消息解码。
4. 给 unknown / legacy payload 留容错。

#### `Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift`

改造点：

1. 增加新增 block 的渲染分支。
2. 卡片回调统一进入 `DeepTutorChatViewModel`。

#### 新增 `Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorToolConsentCardView.swift`

职责：

1. 展示工具授权说明。
2. 提供拒绝、允许一次、始终允许。
3. 提交后调用 `viewModel.submitToolConsent(...)`。

#### 新增 `Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorHealthResourceCandidateCardView.swift`

职责：

1. 展示健康资料候选列表。
2. 支持多选。
3. 提交后调用 `viewModel.submitHealthResourceCandidates(...)`。

#### 新增 `Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorHealthResourceReferenceCardView.swift`

职责：

1. 展示已选资料引用。
2. 支持点击查看详情或展开摘要。
3. 卡片视觉风格对齐 DeepTutorChat，不复用 Chat bubble 内卡片。

#### 新增 `Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorAskReportPickerCardView.swift`

职责：

1. 作为 DeepTutorChat 的“问报告”资料选择入口。
2. 可以先做消息内卡片，也可以做 DeepTutor 专属 Sheet。
3. 选择结果写入 DeepTutor draft references。

#### `Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift`

改造点：

1. 新增：
   - `submitToolConsent`
   - `submitHealthResourceCandidates`
   - `presentDeepTutorAskReportPicker`
   - `appendDeepTutorReportReferences`
2. 所有提交都走 DeepTutorChat 自己的 resume 逻辑。
3. 不调用 Chat 的 `presentAskReportPicker`。

## 9. 核心代码示例

### 9.1 host 隔离

```swift
enum ToolInteractionHost: String, Codable, Sendable {
    case chat
    case deepTutorChat
}

struct ToolInteractionActivePresentation: Identifiable, Sendable {
    let id: UUID
    let host: ToolInteractionHost
    let snapshot: ToolInteractionSnapshot
}
```

### 9.2 Chat 只消费 Chat 的 Sheet

```swift
private var chatToolPresentation: ToolInteractionActivePresentation? {
    guard toolInteractionCoordinator.activePresentation?.host == .chat else {
        return nil
    }
    return toolInteractionCoordinator.activePresentation
}
```

### 9.3 DeepTutorChat 只消费 DeepTutor 的交互

```swift
private var deepTutorToolPresentation: ToolInteractionActivePresentation? {
    guard toolInteractionCoordinator.activePresentation?.host == .deepTutorChat else {
        return nil
    }
    return toolInteractionCoordinator.activePresentation
}
```

### 9.4 DeepTutor 专属交互路由

```swift
struct DeepTutorToolInteractionPresentationView: View {
    let active: ToolInteractionActivePresentation
    let onConsent: (ToolConsentDecision) -> Void
    let onHealthResourcesSelected: ([Int]) -> Void

    var body: some View {
        switch active.snapshot {
        case .consent(let prompt):
            DeepTutorToolConsentCardView(prompt: prompt, onSubmit: onConsent)
        case .healthResourceCandidates(let prompt):
            DeepTutorHealthResourceCandidateCardView(
                prompt: prompt,
                onSubmit: onHealthResourcesSelected
            )
        default:
            DeepTutorUnsupportedToolInteractionCardView(snapshot: active.snapshot)
        }
    }
}
```

### 9.5 DeepTutor 消息 block 增加资料卡

```swift
enum DeepTutorMessageBlockKind: String, Codable, Sendable {
    case text
    case askUser
    case memberSelection
    case toolTrace
    case toolConsent
    case healthResourceCandidateSelection
    case healthResourceReference
    case askReportPicker
}
```

### 9.6 DeepTutor reducer 处理工具事件

```swift
extension DeepTutorMessageReducer {
    static func apply(event: DeepTutorStreamEvent, to message: DeepTutorMessage) -> DeepTutorMessage {
        var blocks = message.blocks

        switch event {
        case let .healthResourceReferenceCreated(payload):
            blocks.append(
                DeepTutorMessageBlock(
                    kind: .healthResourceReference,
                    payload: .healthResourceReference(payload)
                )
            )
        case let .healthResourceCandidateSelectionRequested(payload):
            blocks.upsertToolCard(
                toolCallID: payload.toolCallID,
                kind: .healthResourceCandidateSelection,
                payload: .healthResourceCandidateSelection(payload)
            )
        default:
            break
        }

        return message.replacing(blocks: blocks)
    }
}
```

### 9.7 DeepTutor 资料选择提交

```swift
@MainActor
func submitHealthResourceCandidates(
    toolCallID: String,
    selectedResourceIDs: [Int]
) async {
    guard let conversationID = activeConversationID else { return }
    do {
        try await sendMessageUseCase.submitHealthResourceCandidates(
            conversationID: conversationID,
            toolCallID: toolCallID,
            selectedResourceIDs: selectedResourceIDs,
            visibleHistory: state.messages,
            session: generationSession
        )
    } catch {
        logger.error(
            "DeepTutor health resource candidate submit failed: \(error.localizedDescription)",
            module: DeepTutorChatLog.module
        )
    }
}
```

## 10. 资料卡片生成方案

### 10.1 用户手动选择资料

DeepTutorChat Composer 新增“资料/报告”入口。

生成路径：

```text
用户选择资料
  -> draft.references
  -> 发送消息
  -> user message blocks append healthResourceReference
  -> requestSnapshot.references 写入同一批资料
  -> prompt/context 注入 healthResourceContext
```

### 10.2 AI 工具选择资料

生成路径：

```text
AI 调用 list_member_health_sources
  -> 候选多条
  -> DeepTutorHealthResourceCandidateCardView
  -> 用户确认
  -> ToolHub 继续
  -> ToolSideEffect.healthResourceReference
  -> DeepTutorToolSideEffectMapper
  -> assistant message block healthResourceReference
```

### 10.3 卡片显示要求

DeepTutor 资料卡片至少显示：

1. 资料标题。
2. 资料类型。
3. 所属成员。
4. 时间。
5. 工具来源。
6. 是否已被本轮 AI 使用。

卡片交互：

1. 点击展开摘要。
2. 点击查看原始资料详情。
3. 支持多资料合并展示。
4. 支持在 trace 中查看工具调用来源。

## 11. 测试与验收

### 11.1 必测场景

1. Chat 中触发数据授权，仍打开 `ExternalToolDataConsentSheet`。
2. DeepTutorChat 中触发数据授权，不打开 Chat Sheet。
3. Chat 中触发成员选择，仍打开 `MemberSelectionToolSheet`。
4. DeepTutorChat 中触发成员选择，出现 `DeepTutorMemberSelectionCardView`。
5. Chat 中问报告，仍使用 `ChatAskReportSheet`。
6. DeepTutorChat 中问报告，使用 DeepTutor 专属资料选择卡片或 Sheet。
7. DeepTutorChat 调用健康资料候选选择时，出现 DeepTutor 专属候选卡片。
8. DeepTutorChat 工具返回健康资料引用时，助手消息出现 DeepTutor 资料引用卡片。

### 11.2 回归标准

1. Chat 原有工具交互不退化。
2. DeepTutorChat 不再打开 Chat 的授权、成员、资料选择 Sheet。
3. DeepTutorChat 的所有人工介入点都能在同一 assistant message 内恢复。
4. 工具执行结果、资料卡片、trace 三者 toolCallID 能对齐。
5. 重启 App 后，pending 卡片仍能恢复状态或给出明确失败提示。

### 11.3 日志验收

每次工具交互必须能看到：

```text
conversationID
assistantMessageID
toolCallID
host
toolName
interactionType
status
selectedResourceIDs / selectedMemberID / consentDecision
```

## 12. 推荐实施阶段

### Phase A：host 隔离

目标：

1. `ToolInteractionCoordinator` active presentation 带 host。
2. `ChatView` 只消费 `.chat`。
3. `DeepTutorChat` 不再被 Chat Sheet 抢走交互。

### Phase B：DeepTutor 专属授权与资料候选卡片

目标：

1. 新增 `DeepTutorToolConsentCardView`。
2. 新增 `DeepTutorHealthResourceCandidateCardView`。
3. 新增对应 `DeepTutorStreamEvent` 和 reducer 分支。

### Phase C：DeepTutor 资料引用卡片

目标：

1. 新增 `DeepTutorHealthResourceReferenceCardView`。
2. 新增 `DeepTutorToolSideEffectMapper`。
3. 工具 sideEffect 能落入 DeepTutor message block。

### Phase D：DeepTutor 问报告入口

目标：

1. DeepTutor Composer 增加资料选择入口。
2. 选择结果写入 draft references。
3. 发送后用户消息展示资料卡片。

### Phase E：调试与回放

目标：

1. Debug export 输出 host、toolCallID、card block、sideEffect。
2. pending / resolved / failed 状态可回放。
3. Chat 和 DeepTutorChat 的工具交互链路能独立验收。

## 13. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| host 改造影响 Chat | Chat 工具 Sheet 可能回归 | 默认 host 设为 `.chat`，Chat 路径先不改行为 |
| DeepTutor 内联授权阻塞 ToolHub | 工具 await 无法恢复 | 复用 ask_user / member_selection 的 resume 思路，所有 pending 卡片带 toolCallID |
| 健康资料候选流程复杂 | 多选后工具回灌失败 | 第一阶段只支持 selected IDs，后续再扩展完整摘要 |
| sideEffect 双系统映射重复 | 维护成本上升 | 共享 sideEffect domain model，分别映射到 ChatMessageBlock / DeepTutorMessageBlock |
| DeepTutor 专属 Sheet 与卡片边界不清 | 交互体验不一致 | 默认卡片，只有系统级授权或复杂资料浏览才用 DeepTutor Sheet |

## 14. 结论

这次优化的关键判断是：

```text
ToolHub / ChatOrchestrator 可以共享
工具交互 UI / 消息卡片 / 资料选择入口必须隔离
```

Chat 是“全局 Sheet + ChatMessageBlock”模式。

DeepTutorChat 应该是“消息内工具卡片 + DeepTutorMessageBlock + 同 assistant message resume”模式。

落地后，DeepTutorChat 中触发授权、成员选择、健康资料候选、问报告资料选择，都不会再打开 Chat 的 Sheet；用户会在 DeepTutorChat 自己的消息流里完成选择、授权和恢复，工具结果也会以 DeepTutor 原生卡片沉淀下来。
