# DEEPTUTORCHAT-000046 DeepTutorChat 独立工具交互协调器与 Sheet 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000046 |
| 工单类型 | P0 工具交互架构 / Sheet 协调器 / DeepTutorChat 独立工具系统 |
| 当前范围 | 创建需求工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `SparkClient/Projects/Features/DeepTutorChat` |
| 参考模块 | `SparkClient/Projects/Features/Chat/Presentation/ToolInteraction` |
| 参考文件 | `ToolInteractionCoordinator.swift`、`ToolInteractionPresentationSheet.swift`、`ToolInteractionSnapshot.swift` |
| 创建日期 | 2026-08-08 |
| 核心目标 | 在 DeepTutorChat 中实现一套与 Chat 工具交互协调器行为完全一致、但类型和状态完全独立的工具交互 Coordinator + Sheet，并接入 DeepTutorChat 原生工具系统 |

## 1. 背景

Chat 模块已经有成熟的工具交互协调器：

```text
ToolInteractionCoordinator
  -> FIFO queue
  -> activePresentation
  -> CheckedContinuation 等待用户操作
  -> complete / cancel / dismiss
  -> 串行展示 Sheet

ToolInteractionPresentationSheet
  -> switch active.snapshot
  -> 展示 Consent / Question / Member / ToolPreview / Health Candidates / AskReport / APIKeys
```

DeepTutorChat 当前已有原生工具系统目录：

```text
Projects/Features/DeepTutorChat/Application/Tools/
Projects/Features/DeepTutorChat/Domain/Tools/
```

并已有第一阶段工具：

```text
DeepTutorAskUserTool
DeepTutorMemberSelectionTool
DeepTutorGetCurrentMemberBindingTool
DeepTutorReadMemoryTool
DeepTutorWriteMemoryTool
```

但 DeepTutorChat 目前没有独立的工具交互 Sheet 协调器：

```text
DeepTutorChatPage.swift
  -> 没有挂载 DeepTutorToolInteractionPresentationSheet

DeepTutorPauseResumeCoordinator.swift
  -> 目前只是占位说明

DeepTutorChatDebugExporter.swift
  -> activePresentationSnapshot 当前仍是 none 风格
```

这会导致两个问题：

1. DeepTutorChat 如果未来需要弹窗式工具交互，缺少自己的统一入口。
2. 如果继续借用 Chat 的 `ToolInteractionCoordinator`，会破坏 `DEEPTUTORCHAT-000043` 要求的 DeepTutorChat 独立工具架构。

因此需要为 DeepTutorChat 建立一套独立但同构的工具交互协调器和 Sheet。

## 2. 核心原则

### 2.1 行为完全对齐 Chat

DeepTutorChat 协调器必须学习 Chat 的优秀结构：

```text
1. 一个 activePresentation 驱动一个 Sheet。
2. 所有交互请求进入 FIFO 队列。
3. 同一时间只展示一个工具交互。
4. 阻塞型交互通过 CheckedContinuation 等待结果。
5. 展示型交互不阻塞工具执行，只等待用户关闭。
6. 用户手势关闭时按 snapshot 类型给默认取消/关闭结果。
7. 每个交互完成后延迟 350ms，再展示下一个 Sheet。
```

### 2.2 类型完全独立

不能复用：

```text
ToolInteractionCoordinator
ToolInteractionPresentationSheet
ToolInteractionSnapshot
ChatStateStore
ChatRenderContext
ChatMessageBlock
ChatAskReportSheet
ChatHealthSourceCandidateSheet
ToolPreviewSheet 中的 Chat state 依赖
```

必须新增 DeepTutorChat 专属类型：

```text
DeepTutorToolInteractionCoordinator
DeepTutorToolInteractionPresentationSheet
DeepTutorToolInteractionSnapshot
DeepTutorToolInteractionResult
DeepTutorToolQuestionPrompt
DeepTutorToolMemberSelectionPrompt
DeepTutorToolConsentPrompt
DeepTutorToolPreviewPrompt
```

### 2.3 状态完全隔离

Chat 和 DeepTutorChat 必须互不影响：

```text
Chat activePresentation != DeepTutor activePresentation
Chat queue != DeepTutor queue
Chat member sheet != DeepTutor member sheet
Chat ask report picker != DeepTutor ask report picker
Chat tool preview context != DeepTutor tool preview context
```

任何 DeepTutorChat 工具交互不得进入：

```text
Projects/Features/Chat/Presentation/ToolInteraction
```

任何 Chat 工具交互不得进入：

```text
Projects/Features/DeepTutorChat/Presentation/ToolInteraction
```

## 3. Chat 参考实现拆解

### 3.1 `ToolInteractionCoordinator`

Chat Coordinator 的关键结构：

```swift
@MainActor
final class ToolInteractionCoordinator: ObservableObject {
    struct ActivePresentation: Identifiable, Equatable {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
    }

    @Published private(set) var activePresentation: ActivePresentation?

    private struct QueuedWork {
        let id: UUID
        let snapshot: ToolInteractionSnapshot
        let completion: QueuedCompletion?
    }
}
```

关键能力：

```text
requestConsentDecision(...)
requestQuestionAnswer(...)
requestMemberSelection(...)
requestHealthResourceCandidateSelection(...)
presentToolPreview(...)
presentSystemMessageSettings(...)
presentAPIKeysSettings(...)
presentAskReportPicker(...)
completeConsent(...)
completeQuestion(...)
completeMemberSelection(...)
completeHealthResourceCandidates(...)
dismissActivePresentationByUser()
runDrainLoop()
defaultOutcome(for:)
resumeCompletion(...)
```

DeepTutorChat 要做到行为一致，但根据 DeepTutorChat 第一阶段工具范围裁剪类型。

### 3.2 `ToolInteractionPresentationSheet`

Chat Sheet 的职责非常清晰：

```swift
switch active.snapshot {
case .consent:
case .question:
case .member:
case .toolPreview:
case .systemMessageSettings:
case .healthResourceCandidates:
case .askReportPicker:
case .apiKeysSettings:
}
```

它只做 UI 路由，不管理队列。

DeepTutorChat 也必须保持这个分工：

```text
Coordinator 管队列和 continuation。
PresentationSheet 只按 snapshot 切换 UI。
具体 Sheet/Card 只收集用户输入并调用 coordinator.complete。
```

## 4. DeepTutorChat 目标架构

### 4.1 新目录结构

新增目录：

```text
Projects/Features/DeepTutorChat/Presentation/ToolInteraction/
├── DeepTutorToolInteractionCoordinator.swift
├── DeepTutorToolInteractionPresentationSheet.swift
├── DeepTutorToolInteractionSnapshot.swift
├── DeepTutorToolInteractionModels.swift
├── DeepTutorToolInteraction说明.md
├── Sheets/
│   ├── DeepTutorToolQuestionSheet.swift
│   ├── DeepTutorMemberSelectionToolSheet.swift
│   ├── DeepTutorToolPreviewSheet.swift
│   ├── DeepTutorToolConsentSheet.swift
│   └── DeepTutorAPIKeysSettingsSheet.swift
└── Shared/
    ├── DeepTutorToolSheetSection.swift
    ├── DeepTutorToolLargeTextPreview.swift
    └── DeepTutorToolSheetDisplayLimits.swift
```

第一阶段最小可落地：

```text
DeepTutorToolInteractionCoordinator.swift
DeepTutorToolInteractionPresentationSheet.swift
DeepTutorToolInteractionSnapshot.swift
DeepTutorToolInteractionModels.swift
Sheets/DeepTutorToolQuestionSheet.swift
Sheets/DeepTutorMemberSelectionToolSheet.swift
Sheets/DeepTutorToolPreviewSheet.swift
```

后续接入敏感数据工具时再补：

```text
DeepTutorToolConsentSheet
DeepTutorHealthResourceCandidateSheet
DeepTutorAskReportPickerSheet
```

### 4.2 Coordinator 架构

新增：

```swift
@MainActor
final class DeepTutorToolInteractionCoordinator: ObservableObject {
    struct ActivePresentation: Identifiable, Equatable {
        let id: UUID
        let snapshot: DeepTutorToolInteractionSnapshot
    }

    @Published private(set) var activePresentation: ActivePresentation?
}
```

内部队列：

```swift
private struct QueuedWork {
    let id: UUID
    let snapshot: DeepTutorToolInteractionSnapshot
    let completion: QueuedCompletion?
}
```

Continuation 类型：

```swift
private enum QueuedCompletion {
    // 首批不启用，先预留。
    case question(CheckedContinuation<DeepTutorToolInteractionResult<DeepTutorToolQuestionAnswer>, Never>)
    case member(CheckedContinuation<DeepTutorToolInteractionResult<Int>, Never>)
    case consent(CheckedContinuation<DeepTutorToolInteractionResult<DeepTutorToolConsentDecision>, Never>)
}
```

首批必须实现：

```swift
func presentToolPreview(prompt: DeepTutorToolPreviewPrompt)
func dismissToolPreview(id: UUID)
func dismissActivePresentationByUser()
```

后续阶段补：

```swift
func requestQuestionAnswer(...)
func requestMemberSelection(...)
func requestConsentDecision(...)
func presentAPIKeysSettings()
func requestHealthResourceCandidateSelection(...)
func presentAskReportPicker(...)
```

### 4.3 Snapshot 设计

新增：

```swift
enum DeepTutorToolInteractionSnapshot: Codable, Equatable, Sendable {
    case question(DeepTutorToolQuestionPrompt)
    case member(DeepTutorToolMemberSelectionPrompt)
    case toolPreview(DeepTutorToolPreviewPrompt)
    case consent(DeepTutorToolConsentPrompt)
    case apiKeysSettings
}
```

第一阶段可先只实现：

```swift
case question
case member
case toolPreview
```

保留 `requiresForcedSheetDismiss`：

```swift
var requiresForcedSheetDismiss: Bool {
    switch self {
    case .question, .member, .consent:
        return true
    case .toolPreview, .apiKeysSettings:
        return false
    }
}
```

### 4.4 Result 模型

不要直接复用 Chat 的 `InteractionResult`，新增：

```swift
enum DeepTutorToolInteractionResult<Value>: Sendable {
    case success(Value)
    case cancelled
}
```

原因：

```text
1. DeepTutorChat 工具系统要独立。
2. 后续可以扩展 timeout / unavailable / staleTurn 等 DeepTutor 专属结果。
3. 避免把 Chat Presentation 类型泄露到 DeepTutorChat Application 层。
```

## 5. Presentation Sheet 设计

新增：

```swift
struct DeepTutorToolInteractionPresentationSheet: View {
    let active: DeepTutorToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: DeepTutorToolInteractionCoordinator
    @ObservedObject var memberContextStore: MemberContextStore
    let toolPreviewRenderContext: DeepTutorToolPreviewRenderContext?
    let onClearToolPreviewRenderContext: () -> Void

    var body: some View {
        switch active.snapshot {
        case .toolPreview(let prompt):
            DeepTutorToolPreviewSheet(...)
        case .question(let prompt):
            DeepTutorToolQuestionSheet(...)
        case .member(let prompt):
            DeepTutorMemberSelectionToolSheet(...)
        case .consent(let prompt):
            DeepTutorToolConsentSheet(...)
        case .apiKeysSettings:
            DeepTutorAPIKeysSettingsSheet(...)
        }
    }
}
```

第一阶段 Sheet 对应关系：

| Snapshot | DeepTutor Sheet | 数据来源 |
| --- | --- | --- |
| `.toolPreview` | `DeepTutorToolPreviewSheet` | DeepTutor trace/tool result |
| `.question` | `DeepTutorToolQuestionSheet` | `DeepTutorToolQuestionPrompt` |
| `.member` | `DeepTutorMemberSelectionToolSheet` | `MemberContextStore` + prompt |

首批只实现 `.toolPreview`；`.question` / `.member` 是同构预留，不进入本次首批开发。

注意：

```text
DeepTutorChat 已有消息内 DeepTutorAskUserCardView / DeepTutorMemberSelectionCardView。
本工单新增的是 Sheet 协调器，不要求替代消息内卡片。
```

分工规则：

```text
消息内卡片：用于 agent loop pause_for_user，需要持久化到消息流，可 reload 后恢复。
Sheet：用于全局/临时工具交互，不写入消息流，例如工具详情预览、设置、非持久化确认。
```

如果 `ask_user` 和 `request_member_selection` 是 agent loop pause，则默认仍走消息内卡片；只有明确是 “Sheet 模式工具交互” 时才进入 `DeepTutorToolInteractionCoordinator`。

## 6. DeepTutorChatPage 挂载方式

在 `DeepTutorChatPage` 中新增 Sheet：

```swift
.sheet(
    item: Binding(
        get: { viewModel.toolInteractionCoordinator.activePresentation },
        set: { newValue in
            if newValue == nil {
                viewModel.toolInteractionCoordinator.dismissActivePresentationByUser()
            }
        }
    )
) { active in
    DeepTutorToolInteractionPresentationSheet(
        active: active,
        coordinator: viewModel.toolInteractionCoordinator,
        memberContextStore: viewModel.memberContextStoreForToolInteraction,
        toolPreviewRenderContext: viewModel.deepTutorToolPreviewRenderContext,
        onClearToolPreviewRenderContext: {
            viewModel.clearDeepTutorToolPreviewRenderContext()
        }
    )
    .interactiveDismissDisabled(active.snapshot.requiresForcedSheetDismiss)
}
```

要求：

```text
1. Sheet 只挂在 DeepTutorChatPage。
2. 不挂在 ChatView。
3. 不读取 ChatStateStore。
4. 不调用 ToolInteractionPresentationSheet。
5. dismiss 行为必须走 DeepTutorToolInteractionCoordinator.dismissActivePresentationByUser。
```

## 7. ViewModel 注入

`DeepTutorChatViewModel` 新增：

```swift
let toolInteractionCoordinator: DeepTutorToolInteractionCoordinator
```

初始化：

```swift
self.toolInteractionCoordinator = DeepTutorToolInteractionCoordinator()
```

或从 AppContainer 注入：

```text
DeepTutorChat 专属 singleton / per feature coordinator
```

推荐：

```text
DeepTutorChatViewModel 持有一套 coordinator。
ChatDetailViewModel 持有 Chat 的 coordinator。
两者永远不是同一个实例。
```

对外暴露：

```swift
var deepTutorToolInteractionCoordinator: DeepTutorToolInteractionCoordinator {
    toolInteractionCoordinator
}
```

不要再暴露：

```swift
ToolInteractionCoordinator
```

## 8. 与 DeepTutor 工具系统的接入

### 8.1 接入点

DeepTutor 原生工具 runtime 中，当工具需要 Sheet 交互时，不应调用 Chat Coordinator，而应通过 context 调用 DeepTutor Coordinator。

建议扩展 `DeepTutorToolContext`：

```swift
@MainActor
let interactionCoordinator: DeepTutorToolInteractionCoordinator?
```

或通过 application service：

```swift
protocol DeepTutorToolInteractionHandling: Sendable {
    func requestQuestionAnswer(...) async -> DeepTutorToolInteractionResult<DeepTutorToolQuestionAnswer>
    func requestMemberSelection(...) async -> DeepTutorToolInteractionResult<Int>
    func presentToolPreview(...)
}
```

更推荐协议方式，避免工具层直接依赖 SwiftUI ObservableObject。

### 8.2 ask_user 的接入规则

当前 `DeepTutorAskUserTool` 返回：

```swift
pauseForUser: .askUser(payload)
```

这是 agent loop pause，应进入消息内卡片：

```text
DeepTutorAskUserCardView
```

不是本工单 Sheet 的默认目标。

只有未来出现非持久化追问工具时，才使用：

```text
DeepTutorToolInteractionCoordinator.requestQuestionAnswer
```

### 8.3 request_member_selection 的接入规则

当前 `DeepTutorMemberSelectionTool` 返回：

```swift
pauseForUser: .memberSelection(...)
```

这是 agent loop pause，应进入消息内卡片：

```text
DeepTutorMemberSelectionCardView
```

但以下场景可以走 Sheet：

```text
1. 输入框成员 chip 主动选择成员。
2. 工具需要临时选择但不需要写入消息流。
3. 系统设置/资料选择前置选择成员。
```

### 8.4 tool preview 的接入规则

DeepTutor trace / tool result 点击详情时，进入：

```text
DeepTutorToolInteractionCoordinator.presentToolPreview
```

并展示：

```text
DeepTutorToolPreviewSheet
```

不要复用 Chat 的：

```text
ToolPreviewSheet
ChatRenderContext
ChatStateStore
```

## 9. 第一阶段实现范围

### 9.1 首批接入范围

首批只接入一个 Sheet：

```text
工具使用详情 Sheet
```

入口：

```text
DeepTutorChat 思考过程 / trace panel 内的工具名称
```

交互：

```text
用户点击思考过程里的工具名称
  -> DeepTutorTracePanelView 构造 DeepTutorToolPreviewPrompt
  -> DeepTutorToolInteractionCoordinator.presentToolPreview(prompt:)
  -> DeepTutorChatPage 弹出 DeepTutorToolInteractionPresentationSheet
  -> DeepTutorToolPreviewSheet 展示工具详情
```

首批不接入：

```text
ask_user Sheet
member selection Sheet
consent Sheet
health resource candidates Sheet
ask report picker Sheet
API keys Sheet
```

原因：

```text
ask_user / request_member_selection 当前属于 agent loop pause，需要落在消息内卡片，支持持久化和 reload 恢复。
本次截图需求是“点击思考过程内的工具名称，弹出工具使用详情 Sheet”，属于只读预览，不应改变工具执行流程。
```

### 9.2 首批必须落地

```text
1. DeepTutorToolInteractionCoordinator
2. DeepTutorToolInteractionSnapshot
3. DeepTutorToolInteractionResult
4. DeepTutorToolInteractionPresentationSheet
5. DeepTutorToolPreviewSheet
6. DeepTutorToolPreviewPrompt
7. DeepTutorToolPreviewRelatedContent
8. DeepTutorChatPage sheet 挂载
9. DeepTutorTracePanelView 工具名称点击入口
10. DeepTutorChatDebugExporter 输出 activePresentationSnapshot
```

### 9.3 第一阶段预留但不实现

```text
DeepTutorToolQuestionSheet
DeepTutorMemberSelectionToolSheet
DeepTutorToolConsentSheet
DeepTutorHealthResourceCandidateSheet
DeepTutorAskReportPickerSheet
DeepTutorAPIKeysSettingsSheet
```

但 Snapshot 架构要预留对应 case，或者在注释中明确后续扩展位置。

### 9.4 工具详情 Sheet 视觉目标

参考截图，DeepTutorToolPreviewSheet 目标形态：

```text
半屏 / 大圆角 Sheet
顶部有拖拽指示条
右上角“完成”
大标题：工具详情
下面按卡片分区展示：
  1. 工具名称 / tool_call_id
  2. 参数
  3. 输出
  4. 关联内容
```

每个区块：

```text
白色卡片
8-14pt 圆角
标题加粗
正文支持 monospaced 文本
长文本可滚动或折行
```

截图中的示例结构：

```text
工具详情

展示消息卡片
tool_call_id: call_xxx

参数
card_type: report_photo

输出
已展示上传 / 拍照卡片入口（report_photo），请继续引导用户上传材料。

关联内容
AI 智能解读报告卡片
```

### 9.5 与 ToolSideEffectBlockMapper 的对齐点

Chat 的 `ToolSideEffectBlockMapper` 在 65-75 行附近处理：

```swift
case .captureCard(let payload):
    guard isEncodable(payload) else { return nil }
    return [
        ChatMessageBlock(
            anchor: normalizedAnchor.map(ChatBlockAnchor.toolCall),
            kind: .captureCard,
            toolCallID: normalizedAnchor,
            parentToolCallID: normalizedAnchor,
            captureMessageCard: payload
        )
    ]
```

DeepTutorChat 需要学习这个映射思想：

```text
工具调用产生的 UI 产物，必须和 toolCallID 建立父子关系。
用户点击工具名称时，Sheet 不只展示参数/输出，还能展示该工具产生的关联内容。
```

DeepTutorChat 不直接复用 `ChatMessageBlock.captureCard`，而是新增 DeepTutor 专属预览模型：

```text
DeepTutorToolPreviewRelatedContent
```

用于承载：

```text
messageCard
askUserCard
memberSelectionCard
generatedFileCard
researchOutlineCard
quizCard
healthExamPlanCard（未来）
reportUploadCard（未来）
```

## 10. 文件级任务清单

### 10.1 新增文件

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/DeepTutorToolInteractionCoordinator.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/DeepTutorToolInteractionPresentationSheet.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/DeepTutorToolInteractionSnapshot.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/DeepTutorToolInteractionModels.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/Sheets/DeepTutorToolPreviewSheet.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/Sheets/DeepTutorToolPreviewRelatedContentView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/Shared/DeepTutorToolLargeTextPreview.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/Shared/DeepTutorToolSheetSection.swift
```

### 10.2 修改文件

```text
DeepTutorChatPage.swift
  -> 挂载 .sheet(item:)

DeepTutorChatViewModel.swift
  -> 持有 DeepTutorToolInteractionCoordinator
  -> 暴露 active presentation debug 信息
  -> 提供 clear preview render context

DeepTutorChatDebugExporter.swift
  -> activePresentationSnapshot 不再写死 none

DeepTutorAssistantBubble.swift
  -> trace block 渲染时向 DeepTutorTracePanelView 传入 onToolPreview 回调

DeepTutorMessageRowView.swift / DeepTutorMessageListView.swift
  -> 将 onToolPreview 回调向上传递到 viewModel

DeepTutorTracePanelView.swift
  -> 工具行内的工具名称从“只展开内联详情”升级为“可打开 Sheet”
  -> 内联展开可保留为轻量预览，但点击工具名称必须 presentToolPreview

DeepTutorToolDetailView.swift
  -> 继续作为内联轻量详情
  -> 不承担全屏 / 半屏 Sheet 展示

DeepTutorToolContext / DeepTutorAgenticRuntime
  -> 预留 interaction handler 接入点
```

### 10.3 点击链路落地细节

`DeepTutorAssistantBubble.swift` 当前 trace 渲染：

```swift
case .trace(let payload):
    DeepTutorTracePanelView(messageID: message.id, payload: payload)
```

需要改为：

```swift
case .trace(let payload):
    DeepTutorTracePanelView(
        message: message,
        payload: payload,
        onToolPreview: onToolPreview
    )
```

`DeepTutorAssistantBubble` 新增入参：

```swift
let onToolPreview: (DeepTutorToolPreviewPrompt) -> Void
```

初始化参数默认值：

```swift
onToolPreview: @escaping (DeepTutorToolPreviewPrompt) -> Void = { _ in }
```

继续向上传：

```text
DeepTutorAssistantBubble
  -> DeepTutorMessageRowView
  -> DeepTutorMessageListView
  -> DeepTutorChatViewModel.presentToolPreview(prompt:)
```

ViewModel 方法：

```swift
@MainActor
func presentToolPreview(_ prompt: DeepTutorToolPreviewPrompt) {
    toolInteractionCoordinator.presentToolPreview(prompt: prompt)
}
```

`DeepTutorTracePanelView` 改造：

```swift
struct DeepTutorTracePanelView: View {
    let message: DeepTutorMessage
    let payload: DeepTutorTraceBlockPayload
    let onToolPreview: (DeepTutorToolPreviewPrompt) -> Void
}
```

工具行中，工具名称部分单独成为按钮：

```swift
Button {
    onToolPreview(makeToolPreviewPrompt(row))
} label: {
    Text(row.toolName ?? row.verb)
}
```

点击区域要求：

```text
1. 点击工具名称：打开 Sheet。
2. 点击 chevron：保留当前内联展开/收起。
3. 如果没有 argsDetail/resultDetail/relatedContent，也可以打开 Sheet，但显示“暂无参数/暂无输出”。
4. 正在 running 的工具也可打开 Sheet，输出区显示“工具仍在运行”。
```

### 10.4 关联内容映射器

新增：

```text
DeepTutorToolPreviewRelatedContentMapper.swift
```

路径建议：

```text
Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolPreviewRelatedContentMapper.swift
```

职责：

```text
从 message.blocks 中查找和 row.toolCallID 相同的 block。
将这些 block 映射为 DeepTutorToolPreviewRelatedContent。
```

伪代码：

```swift
enum DeepTutorToolPreviewRelatedContentMapper {
    static func relatedContent(
        row: DeepTutorTraceRowModel,
        message: DeepTutorMessage
    ) -> [DeepTutorToolPreviewRelatedContent] {
        let callID = row.toolCallID ?? row.id
        return message.blocks.compactMap { block in
            guard block.toolCallID == callID else { return nil }
            switch block.payload {
            case .askUser(let payload): return .askUser(payload)
            case .memberSelection(let payload): return .memberSelection(payload)
            case .generatedFile(let payload): return .generatedFile(payload)
            case .researchOutline(let payload): return .researchOutline(payload)
            case .quiz(let payload): return .quiz(payload)
            default: return nil
            }
        }
    }
}
```

对于类似截图中的“展示消息卡片 / report_photo”：

```text
如果 DeepTutor 还没有对应 block 类型，应先映射为 messageCard。
不要为了首批需求强行引入 Chat 的 captureCard。
```

### 10.5 禁止修改方向

```text
不要把 Chat ToolInteractionCoordinator 改成支持 host=deepTutorChat。
不要在 Chat ToolInteractionSnapshot 增加 DeepTutor 专属 case。
不要让 DeepTutorToolInteractionPresentationSheet 接收 ChatStateStore。
不要让 ChatView 挂 DeepTutor Sheet。
不要把 DeepTutor Sheet 的完成回调写进 ChatDetailViewModel。
```

## 11. 数据模型设计

### 11.1 首批必须实现的工具详情模型

首批只实现工具详情 Sheet，因此必须先落以下模型。

```swift
struct DeepTutorToolPreviewPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let conversationID: UUID?
    let messageID: UUID?
    let toolCallID: String?
    let toolName: String
    let displayTitle: String
    let arguments: String?
    let output: String?
    let outputIsMarkdown: Bool
    let metadata: [String: String]
    let relatedContent: [DeepTutorToolPreviewRelatedContent]
}
```

关联内容：

```swift
enum DeepTutorToolPreviewRelatedContent: Codable, Equatable, Sendable, Identifiable {
    case messageCard(DeepTutorToolPreviewMessageCard)
    case askUser(DeepTutorAskUserBlockPayload)
    case memberSelection(DeepTutorMemberSelectionBlockPayload)
    case generatedFile(DeepTutorGeneratedFilePayload)
    case researchOutline(DeepTutorResearchOutlinePayload)
    case quiz(DeepTutorQuizPayload)

    var id: String { ... }
}
```

首批最少实现：

```swift
struct DeepTutorToolPreviewMessageCard: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let body: String?
    let iconName: String?
    let actions: [DeepTutorToolPreviewAction]
}

struct DeepTutorToolPreviewAction: Codable, Equatable, Sendable {
    let title: String
    let systemImage: String?
}
```

映射示例：

```text
toolName = show_custom_message_card / show_report_upload_card
toolCallID = row.id 或 row.toolCallID
arguments = row.argsDetail
output = row.resultDetail
relatedContent = [.messageCard(...)]
```

### 11.2 从 Trace Row 构造 Prompt

`DeepTutorTraceRowModel` 当前已有字段：

```swift
var id: String
var verb: String
var chip: String?
var status: DeepTutorTraceRowStatus
var toolName: String?
var argsDetail: String?
var resultDetail: String?
var resultIsMarkdown: Bool
```

首批构造规则：

```swift
DeepTutorToolPreviewPrompt(
    id: UUID(),
    conversationID: message.conversationID,
    messageID: message.id,
    toolCallID: row.id,
    toolName: row.toolName ?? row.verb,
    displayTitle: row.verb,
    arguments: row.argsDetail,
    output: row.resultDetail,
    outputIsMarkdown: row.resultIsMarkdown,
    metadata: [
        "status": row.status.rawValue,
        "chip": row.chip ?? ""
    ],
    relatedContent: DeepTutorToolPreviewRelatedContentMapper.relatedContent(
        row: row,
        message: message
    )
)
```

注意：

```text
row.id 当前承担 trace row id，必须确认它是否稳定等于 tool_call_id。
如果不是，需要在 DeepTutorTraceRowModel 增加 toolCallID 字段，不能把展示 id 当真实 call id。
```

建议扩展：

```swift
var toolCallID: String?
```

兼容策略：

```text
toolCallID ?? id
```

### 11.3 预留 Prompt 模型

以下模型第一阶段只预留，不进入首批开发。

```swift
struct DeepTutorToolQuestionPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let conversationID: UUID?
    let title: String
    let message: String
    let questions: [DeepTutorToolQuestionItem]
}

struct DeepTutorToolQuestionItem: Codable, Equatable, Sendable {
    let id: String
    let prompt: String
    let options: [DeepTutorToolQuestionOption]
    let allowsFreeText: Bool
    let multiSelect: Bool
}

struct DeepTutorToolQuestionAnswer: Codable, Equatable, Sendable {
    let responses: [String: [String]]
    let freeText: [String: String]
}
```

成员 prompt：

```swift
struct DeepTutorToolMemberSelectionPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let conversationID: UUID?
    let title: String
    let reason: String
    let selectedMemberID: Int?
    let allowsNone: Bool
}
```

## 12. UI 设计要求

### 12.1 首批：DeepTutorToolPreviewSheet

要求：

```text
1. 半屏 Sheet，顶部有拖拽条。
2. 右上角显示“完成”按钮。
3. 大标题“工具详情”。
4. 第一张卡显示工具名称和 tool_call_id。
5. 第二张卡显示“参数”。
6. 第三张卡显示“输出”。
7. 如果 relatedContent 非空，第四张卡显示“关联内容”。
8. 参数和 tool_call_id 使用 monospaced 字体。
9. 输出支持 Markdown / 普通文本两种。
10. 长文本可滚动，不撑爆 Sheet。
11. 不使用 Chat 的 ToolPreviewSheet / ChatRenderContext。
```

Sheet 结构伪代码：

```swift
NavigationStack {
    ScrollView {
        VStack(spacing: 14) {
            DeepTutorToolSheetSection(title: prompt.displayTitle) {
                tool_call_id...
            }
            DeepTutorToolSheetSection(title: "参数") {
                DeepTutorToolLargeTextPreview(prompt.arguments)
            }
            DeepTutorToolSheetSection(title: "输出") {
                output view
            }
            if prompt.relatedContent.isEmpty == false {
                DeepTutorToolSheetSection(title: "关联内容") {
                    DeepTutorToolPreviewRelatedContentView(...)
                }
            }
        }
    }
    .navigationTitle("工具详情")
    .toolbar {
        ToolbarItem(placement: .confirmationAction) {
            Button("完成") { coordinator.dismissToolPreview(id: active.id) }
        }
    }
}
```

### 12.2 关联内容卡片

首批至少实现 `messageCard`：

要求：

```text
1. 标题大字加粗。
2. 副标题/说明用 secondary。
3. 如果有 actions，以浅蓝胶囊按钮样式展示。
4. 如果没有关联内容，不显示该区块。
5. 后续可扩展渲染 askUser/memberSelection/generatedFile/researchOutline。
```

对应截图：

```text
关联内容
  AI 智能解读报告
  请将清晰完整的检查检验报告或 20M 以内的体检报告发送给我...
  [拍照] [上传照片] [选择文件]
```

### 12.3 预留：DeepTutorToolQuestionSheet

要求：

```text
1. 支持单题和多题。
2. 支持选项、自由输入、多选。
3. 底部有取消和提交。
4. 提交为空时根据 allowsFreeText/options 判断是否禁用。
5. 风格与 DeepTutorChat 卡片一致，不使用 Chat 的 Hanlin 样式。
```

### 12.4 预留：DeepTutorMemberSelectionToolSheet

要求：

```text
1. 使用 MemberContextStore 的成员列表。
2. 当前已选成员显示 checkmark。
3. allowsNone=true 时显示“无成员/不绑定”。
4. 成员为空时显示空状态。
5. 提交后调用 coordinator.completeMemberSelection。
6. 取消调用 coordinator.completeMemberCancelled。
```

## 13. 队列与取消规则

必须与 Chat 保持一致：

```text
1. enqueue 后触发 runDrainLoop。
2. 如果 isDraining=true，不重复启动 loop。
3. activePresentation 设置后等待 userWaitGate。
4. 用户完成/取消后写 pendingOutcome。
5. resumeUserGate 后清理 activePresentation。
6. completion 按 outcome resume。
7. 每个 presentation 结束后 sleep 350ms。
```

默认结果：

```text
question -> cancelled
member -> cancelled
consent -> cancelled
toolPreview -> dismissed
apiKeysSettings -> dismissed
```

手势关闭：

```text
question/member/consent 禁止交互式关闭。
toolPreview/apiKeysSettings 允许关闭。
```

## 14. 与消息内卡片的边界

DeepTutorChat 有两类工具交互：

### 14.1 持久化到消息流的交互

```text
ask_user pause_for_user
request_member_selection pause_for_user
quiz inline answer
```

特点：

```text
1. 写入 DeepTutorMessageBlock。
2. reload 后仍可恢复。
3. 属于 agent loop 的 pause/resume。
4. 不走 Sheet coordinator。
```

### 14.2 不写入消息流的 Sheet 交互

```text
tool preview
临时成员选择
工具参数确认
API keys 设置
未来授权确认
未来健康资料候选选择
```

特点：

```text
1. 不持久化为消息 block。
2. 由 DeepTutorToolInteractionCoordinator 串行。
3. 关闭后不影响历史消息结构。
4. 可作为工具执行前置等待。
```

## 15. 调试与日志

新增日志：

```text
deeptutor.tool_interaction.enqueued
  conversation
  presentationID
  snapshot

deeptutor.tool_interaction.presented
  presentationID
  snapshot

deeptutor.tool_interaction.completed
  presentationID
  outcome

deeptutor.tool_interaction.cancelled
  presentationID
  snapshot

deeptutor.tool_interaction.queue_drained
  remaining
```

Debug exporter 输出：

```text
activePresentationID
activePresentationSnapshot
toolInteractionQueueCount
toolInteractionIsDraining
```

注意：

```text
Debug 信息只读，不暴露 continuation。
```

## 16. 测试计划

### 16.1 Coordinator 单元测试

```text
dismissToolPreview 关闭 activePresentation
dismissToolPreview 不触发阻塞 completion
多个 work 按 FIFO 顺序展示
dismissActivePresentationByUser 对 toolPreview 生效
presentToolPreview 连续调用时，第二个 Sheet 在第一个关闭后展示
```

### 16.2 Sheet UI 测试

```text
toolPreview snapshot 展示 DeepTutorToolPreviewSheet
点击完成调用 dismissToolPreview
下滑关闭调用 dismissActivePresentationByUser
参数区展示 row.argsDetail
输出区展示 row.resultDetail
关联内容区展示 DeepTutorToolPreviewRelatedContent
```

### 16.3 隔离测试

```text
DeepTutorChat 打开 tool preview，不改变 Chat detailViewModel.toolInteractionCoordinator.activePresentation。
Chat 打开 tool preview，不改变 DeepTutorToolInteractionCoordinator.activePresentation。
DeepTutorToolInteractionPresentationSheet 不 import ChatStateStore。
DeepTutorToolInteractionCoordinator 不引用 ToolInteractionCoordinator。
```

### 16.4 回归测试

```text
DeepTutorAskUserCardView 仍可消息内提交。
DeepTutorMemberSelectionCardView 仍可消息内提交。
Chat ToolInteractionPresentationSheet 行为不变。
Chat 成员选择 Sheet 行为不变。
```

## 17. 验收标准

本工单完成后必须满足：

```text
1. DeepTutorChat 有独立 ToolInteraction 目录。
2. DeepTutorChat 有独立 Coordinator / Snapshot / PresentationSheet。
3. DeepTutorChatPage 挂载 DeepTutorToolInteractionPresentationSheet。
4. DeepTutor 工具交互不再进入 Chat ToolInteractionCoordinator。
5. DeepTutor Sheet 与 Chat Sheet 状态互不影响。
6. DeepTutor tool preview 能通过 Sheet 展示。
7. 点击思考过程内的工具名称可以弹出工具使用详情 Sheet。
8. 工具使用详情 Sheet 至少展示工具名/tool_call_id、参数、输出。
9. 如果工具产生了关联消息卡片，Sheet 中显示关联内容。
10. 消息内 pause 卡片和 Sheet 交互边界清晰。
11. Debug exporter 能显示 activePresentationSnapshot。
12. Chat 现有工具交互不回归。
```

## 18. Done Definition

```text
DeepTutorChat 拥有一套与 Chat 行为同构、但类型和状态完全独立的工具交互协调器：

DeepTutorToolInteractionCoordinator
DeepTutorToolInteractionSnapshot
DeepTutorToolInteractionPresentationSheet
DeepTutor 专属 Tool Preview Sheet
DeepTutorChatPage 独立挂载
点击思考过程工具名称弹出工具使用详情
工具详情展示工具名/tool_call_id、参数、输出、关联内容
Question / Member / Consent Sheet 只作为后续同构扩展预留

Chat 与 DeepTutorChat 的工具交互队列、Sheet、状态、回调互不共享。
```
