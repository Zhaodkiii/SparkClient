# DEEPTUTORCHAT-000042 DeepTutorChat 健康体检计划流程意外停止与暂停边界修复工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000042 |
| 工单类型 | P0 流程中断修复 / 工具暂停边界 / 健康体检计划卡片闭环 |
| 当前范围 | 创建优化工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 关联工单 | `DEEPTUTORCHAT-000039`、`DEEPTUTORCHAT-000040`、`DEEPTUTORCHAT-000041` |
| 创建日期 | 2026-08-08 |
| 触发日志 | `deeptutor.trace.user_toggle message=F47A1FBB expanded=true`、`deeptutor.debug.snapshot conversation=047D76FF ... activeCapability=health_exam_plan` |
| 核心问题 | 健康体检计划流程已经进入 `health_exam_plan`，但在成员选择处意外停止；同一条消息又记录了成员选择之后的健康资料工具调用，最终只展示成员选择卡和 trace，没有生成成员档案、风险摘要、体检计划卡片 |

## 1. 日志现象

本次日志关键信息：

```text
conversation=047D76FF
activeCapability=health_exam_plan
turnPlan: capability=health_exam_plan, stage=selecting_member
phase=ready
isStreaming=false
blockKinds=envelope=2,memberSelection=1,text=1,trace=1
memberProfileBlockCount=0
healthRiskBlockCount=0
healthExamPlanBlockCount=0
quizGateDecision=skipped_not_quiz_turn
eventTypes=memberSelectionRequested=1,reasoningDelta=1,result=2,toolCallStarted=4,toolResult=4
finishReason=awaiting_user_input
```

消息事件顺序：

```text
reasoningDelta
toolCallStarted get_current_member
toolResult get_current_member
toolCallStarted request_member_selection
memberSelectionRequested
toolResult request_member_selection
result finishReason=awaiting_user_input
toolCallStarted query_member_profile
toolResult query_member_profile
toolCallStarted list_member_health_sources
toolResult list_member_health_sources
result finishReason=awaiting_user_input
```

最终卡片：

```text
envelope
trace
memberSelection(pending)
```

缺失卡片：

```text
memberProfileSummary
healthRiskSummary
healthExamPlan
healthExamPlanMissingInfo
healthResourceCandidateSelection
healthResourceReference
```

## 2. 为什么说流程“意外停止”

正常的 `health_exam_plan` 应该是：

```text
选择成员
  -> 等用户选择
  -> resume 同一 assistant message
  -> query_member_profile
  -> list_member_health_sources
  -> 必要时 ask_user_question
  -> 生成 health_exam_plan JSON
  -> DeepTutorHealthExamPlanCardView
```

但当前实际是：

```text
选择成员卡 pending
  -> message status ready
  -> trace 标题已完成
  -> 工具行仍显示 running
  -> 后续 query_member_profile/list_member_health_sources 已经出现在事件里
  -> 没有任何健康计划领域卡片
```

这代表用户感知上流程停止在“请选择成员”，但内部事件又像已经继续跑过部分健康工具，状态出现分裂。

## 3. 根因分析

### 3.1 `awaiting_user_input` 没有成为硬暂停边界

`ChatOrchestrator` 中工具需要用户输入时会返回：

```swift
if toolResult.isAwaitingUserInput {
    return ChatOrchestratorOutput(
        finishReason: "awaiting_user_input",
        ...
    )
}
```

理论上，`request_member_selection` 后本轮应立即停止，等待用户选择。

但日志里，在第一个：

```text
result finishReason=awaiting_user_input
```

之后，又出现了：

```text
query_member_profile
list_member_health_sources
result finishReason=awaiting_user_input
```

这说明 DeepTutorChat 侧至少存在一种问题：

1. partial/event 合并时没有按 `awaiting_user_input` 截断后续事件。
2. resume 事件或过期事件被合并回了同一条 pending 消息。
3. 工具 trace 构建器把 already-started 的工具行保留为 running，但没有收到完成状态修正。
4. health exam plan workflow 没有把 pause boundary 写入 turn state，导致调试快照看起来“已完成但又等待输入”。

### 3.2 成员选择 pending 后不应继续跑健康资料工具

当前提示词要求：

```text
1. Ensure member context via member selection or bound member.
2. Call query_member_profile...
3. Call list_member_health_sources...
```

模型在 reasoning 中也在犹豫：

```text
先 get_current_member？
如果没有当前成员，是不是 request_member_selection？
```

正确执行规则应该是：

```text
如果 get_current_member 没有明确 memberID
  -> request_member_selection
  -> hard pause
  -> 等用户选择后 resume
  -> 再 query_member_profile/list_member_health_sources
```

当前日志说明规则没有被严格执行，后续工具事件已经进入同一条消息。

### 3.3 Trace 状态与消息状态不一致

日志里 trace：

```text
trace_title = 已完成
trace_is_streaming = false
trace rows:
  get_current_member status=running
  request_member_selection status=running
  query_member_profile status=running
  list_member_health_sources status=running
```

这说明 trace reducer 对于 `toolResult` 没有把对应 `toolCallStarted` 行更新为 completed，或者 tool start/result 的 callID 不一致：

```text
toolCallStarted call_id = legacy-tool-start-488848E6
toolResult call_id = legacy-tool-result-BEB5C7F6
```

因为 start/result ID 不稳定，trace 无法配对，只能留下 running 行。

### 3.4 健康计划领域事件没有生成

代码中已有：

```text
DeepTutorHealthExamPlanEventMapper
DeepTutorMessageBlock.healthExamPlan
DeepTutorMessageBlock.healthExamPlanMissingInfo
DeepTutorAssistantBubble healthExamPlan 渲染分支
```

但日志显示：

```text
memberProfileBlockCount=0
healthRiskBlockCount=0
healthExamPlanBlockCount=0
```

原因可能是：

1. `DeepTutorHealthExamPlanEventMapper.events(from:)` 依赖 `toolResult.summary`，但当前 summary 只是“正在使用工具：查询成员资料”，没有真实结构化结果。
2. `query_member_profile` 和 `list_member_health_sources` 实际工具没有在当前 turn 中返回可解析业务数据。
3. `DeepTutorAIRuntimeEventMapper` 没有在 toolResult 时注入 health exam domain events。
4. `draftEvent(from:)` 依赖 assistant `content` 中出现 fenced `health_exam_plan` JSON，但本次 assistant `content` 为空。

### 3.5 提示词要求输出 JSON，但流程暂停时没有最终内容

`DeepTutorPromptBuilder` 已要求：

```text
Prefer appending one fenced code block tagged `health_exam_plan` with JSON
```

但本次：

```text
content_length=0
content_text_from_events=""
resultHasSummaryJSON=false
```

因为 turn 停在成员选择 pending，没有进入最终回答阶段，所以不会生成 `health_exam_plan` JSON，自然也不会生成计划卡。

### 3.6 工具白名单和工具策略存在收窄风险

调试摘要里：

```text
turnFinalAllowedTools:
ask_user_question,get_current_member,get_health_resource_reference,
list_member_health_sources,read_web_page,request_member_selection,save_memory,update_memory

latestAllowedTools:
ask_user_question,read_web_page,save_memory,update_memory
```

两个字段不一致。

这说明：

1. turn plan 阶段允许了健康计划工具。
2. latest tool policy 或 snapshot 阶段又被收窄。
3. 需要确认 debug exporter 显示的是哪一次 policy，是初始 live send，还是 awaiting/resume 后的 policy。

## 4. 正确目标流程

### 4.1 Live send

```text
用户发送体检计划请求
  -> capabilityResolver = health_exam_plan
  -> turnStage = selecting_member
  -> get_current_member
  -> if no member
      emit memberSelectionRequested
      emit result(finishReason=awaiting_user_input, pauseBoundary=true)
      mark assistant.status = awaitingUserInput / readyWithPendingInput
      stop accepting later tool events for this live turn
```

### 4.2 Member selection resume

```text
用户在 DeepTutorMemberSelectionCardView 选择成员
  -> submitMemberSelection
  -> memberSelectionResolved event
  -> turnStage = collecting_profile
  -> query_member_profile(memberID)
  -> memberProfileSummaryCreated
  -> turnStage = collecting_reports
  -> list_member_health_sources(memberID)
  -> healthResourceCandidateSelectionRequested 或 healthRiskSummaryCreated
  -> ask_user_question 缺失信息
  -> healthExamPlanDraftCreated
  -> DeepTutorHealthExamPlanCardView
```

### 4.3 Final state

```text
message.status = ready
trace rows = completed / awaiting_input / failed 三态明确
memberSelection card = resolved
memberProfileSummary card >= 1
healthRiskSummary card >= 1 或 missingInfo card >= 1
healthExamPlan card >= 1
```

## 5. 优化方案

### 5.1 增加 Pause Boundary

新增事件或 metadata：

```swift
case turnPaused(reason: String, pendingToolCallID: String, interactionType: String)
```

或者扩展 result：

```swift
.result(metadata: [
    "finishReason": "awaiting_user_input",
    "pauseBoundary": "true",
    "pendingToolCallID": toolCallID,
    "interactionType": "member_selection"
])
```

规则：

```text
同一次 live send 中，出现 pauseBoundary 后：
1. 后续 toolCallStarted/toolResult 不应合并进当前消息
2. 后续事件如果来自 resume，必须带 resumeMode / resumeTurnID
3. reducer 必须以 pauseBoundary 作为一轮事件截断点
```

### 5.2 `DeepTutorAIRuntimeEventMapper` 按 pause 截断

建议增加：

```swift
private var hasPausedForUserInput = false
```

核心示例：

```swift
mutating func events(from partial: ChatAssistantPartialDelta) -> [DeepTutorStreamEvent] {
    guard hasPausedForUserInput == false else {
        DeepTutorChatLog.eventDroppedAfterPause(...)
        return []
    }

    var events = mapPartial(partial)

    if events.containsAwaitingUserInputResult || events.containsPendingInteraction {
        hasPausedForUserInput = true
    }

    return events
}
```

### 5.3 `ChatOrchestrator` 输出 pending tool call 元数据

当前 output 只有：

```swift
finishReason: "awaiting_user_input"
toolName: toolTrace?.name
```

建议补：

```swift
pendingToolCallID
pendingInteractionType
pendingInteraction
```

让 DeepTutorChat 不需要从 legacy callID 里猜。

### 5.4 稳定 toolCallID

当前 start/result ID：

```text
legacy-tool-start-...
legacy-tool-result-...
legacy-member-selection-...
```

导致 trace 无法配对。

目标：

```text
toolCallStarted.callID == toolResult.callID == pendingInteraction.toolCallID
```

建议：

```swift
let stableID = DeepTutorStableToolCallID.resolve(
    rawToolCallID: partial.toolCallID,
    toolName: toolName,
    arguments: partial.toolArguments
)
```

并让所有事件使用同一个 stableID。

### 5.5 Trace reducer 修正状态

Trace 行状态规则：

```text
toolCallStarted -> running
toolResult same callID -> completed
pendingInteraction same callID -> awaiting_input
result finishReason=awaiting_user_input -> trace title = 等待用户操作
result finishReason=stop/completed -> trace title = 已完成
```

本次不应该出现：

```text
trace title 已完成
但工具行仍 running
```

### 5.6 健康计划 workflow 分阶段

`DeepTutorHealthExamPlanWorkflow` 当前只是 marker：

```swift
struct DeepTutorHealthExamPlanWorkflow: DeepTutorCapabilityWorkflow {
    let capability: DeepTutorCapability = .healthExamPlan
}
```

需要升级成状态机：

```swift
enum DeepTutorHealthExamPlanStage: String, Codable, Sendable {
    case selectingMember
    case collectingProfile
    case collectingReports
    case askingMissingInfo
    case planning
    case completed
}
```

每阶段允许工具：

```text
selectingMember:
  get_current_member, request_member_selection

collectingProfile:
  query_member_profile

collectingReports:
  list_member_health_sources, get_health_resource_reference

askingMissingInfo:
  ask_user_question

planning:
  no more member selection; produce health_exam_plan JSON/card
```

### 5.7 工具策略按阶段收窄

在 `DeepTutorToolPolicyResolver` 中按 health exam plan stage 过滤：

```swift
if context.capability == .healthExamPlan {
    allowed = DeepTutorHealthExamPlanWorkflow.allowedTools(
        stage: context.capabilityStage,
        baseAllowed: allowed
    )
}
```

这样可以避免“成员还没选，模型就调用 query_member_profile/list_member_health_sources”。

### 5.8 体检计划卡片生成不只依赖最终文本

当前 `draftEvent(from:)` 依赖：

```swift
message.content 中存在 ```health_exam_plan JSON
```

但实际中工具链可能先产生 profile/risk，再由模型最终生成计划。

建议三层来源：

```text
1. 工具结构化 sideEffect / tool output
2. result.summaryJSON
3. legacy fenced health_exam_plan JSON
```

核心示例：

```swift
enum DeepTutorHealthExamPlanCardAssembler {
    static func assemble(from events: [DeepTutorStreamEvent]) -> DeepTutorHealthExamPlanPayload? {
        let profile = events.latestMemberProfileSummary
        let risk = events.latestHealthRiskSummary
        let draft = events.latestHealthExamPlanDraft

        if let draft { return draft }
        guard let profile else { return nil }

        return DeepTutorHealthExamPlanPayload(
            memberID: profile.memberID,
            title: "个性化体检计划",
            riskLevel: risk?.riskLevel ?? "待评估",
            basis: profile.highlights + (risk?.riskPoints ?? []),
            baseItems: DeepTutorHealthExamPlanDefaults.baseItems(),
            additionalItems: DeepTutorHealthExamPlanDefaults.additionalItems(from: risk),
            preparation: DeepTutorHealthExamPlanDefaults.preparation(),
            followUp: DeepTutorHealthExamPlanDefaults.followUp()
        )
    }
}
```

## 6. 相关文件改造清单

### 6.1 `Core/AIRuntime/ChatOrchestrator.swift`

改造点：

1. `awaiting_user_input` output 增加 pending metadata。
2. 确保工具 `isAwaitingUserInput` 后不再继续执行本轮 tool loop。
3. 输出 `pendingInteraction` 给 partial / completion 层。

### 6.2 `Core/AIRuntime/ToolHub/Models/ToolingModels.swift`

改造点：

1. `ToolExecutionResult` 增加稳定 `pendingToolCallID` 或确保 anchorToolCallID 可用于 pending。
2. `ToolPendingInteraction` 增加统一 interaction type。

### 6.3 `Application/DeepTutorAIRuntimeEventMapper.swift`

改造点：

1. 增加 pause boundary state。
2. 后续事件如果没有 resume marker，直接 drop。
3. pendingInteraction 事件必须使用稳定 toolCallID。
4. tool result 触发 health exam domain mapper。

### 6.4 `Application/DeepTutorMessageReducer.swift`

改造点：

1. 处理 `turnPaused` 或 result pauseBoundary。
2. pending member selection 后，message status 不应简单变 ready，应表达 awaiting user input。
3. 根据 health exam events 生成 profile/risk/plan block。

### 6.5 `Application/DeepTutorTraceFormatter.swift`

改造点：

1. start/result 使用同一 stableID 配对。
2. pending interaction 显示 `awaiting_input`。
3. trace title 在 pending 时显示“等待用户操作”，不是“已完成”。

### 6.6 `Application/DeepTutorHealthExamPlanEventMapper.swift`

改造点：

1. 不只解析 summary 文本。
2. 支持真实 tool output / sideEffect / summaryJSON。
3. 当工具只返回“正在使用工具”这类占位 summary 时，不生成假卡片，并记录原因。

### 6.7 `Application/DeepTutorCapabilityWorkflow.swift`

改造点：

1. `DeepTutorHealthExamPlanWorkflow` 从 marker 升级为阶段状态机。
2. 提供 `allowedTools(stage:)`。
3. 提供 `nextStage(after:)`。

### 6.8 `Application/DeepTutorToolPolicyResolver.swift`

改造点：

1. mount context 增加 `capabilityStage`。
2. `health_exam_plan` 按阶段过滤工具。
3. member selection resume 后强制进入 `collectingProfile`。

### 6.9 `Application/SendDeepTutorAIMessageUseCase.swift`

改造点：

1. `submitMemberSelection` resume 时写入 capability stage。
2. `shouldForcePersist` 增加 health plan pending cards。
3. finalize 时调用 `DeepTutorHealthExamPlanCardAssembler`。

### 6.10 `Application/DeepTutorChatDebugExporter.swift`

改造点：

1. 增加 `pauseBoundaryCount`。
2. 增加 `pendingInteractionType`。
3. 增加 `postPauseEventCount`。
4. 增加 `traceRunningRowsAfterReadyCount`。
5. 增加 `healthExamPlanAssemblerFailureReason`。

## 7. 核心代码示例

### 7.1 Pause boundary event

```swift
extension DeepTutorStreamEvent {
    static func turnPaused(
        reason: String,
        pendingToolCallID: String,
        interactionType: String
    ) -> DeepTutorStreamEvent {
        .result(metadata: [
            "finishReason": "awaiting_user_input",
            "pauseBoundary": "true",
            "pendingToolCallID": pendingToolCallID,
            "interactionType": interactionType
        ])
    }
}
```

### 7.2 Event mapper 截断后续事件

```swift
struct DeepTutorAIRuntimeEventMapper: Sendable {
    private var pausedToolCallID: String?

    mutating func events(from partial: ChatAssistantPartialDelta) -> [DeepTutorStreamEvent] {
        if let pausedToolCallID, partial.resumeMarker == nil {
            DeepTutorChatLog.eventDroppedAfterPause(
                pausedToolCallID: pausedToolCallID,
                toolName: partial.toolName
            )
            return []
        }

        var events = mapPartialWithoutPauseFiltering(partial)
        if let pause = events.pauseBoundary {
            pausedToolCallID = pause.pendingToolCallID
        }
        return events
    }
}
```

### 7.3 Health plan stage tool filter

```swift
enum DeepTutorHealthExamPlanWorkflowRules {
    static func allowedTools(
        stage: DeepTutorHealthExamPlanStage,
        baseAllowed: Set<String>
    ) -> Set<String> {
        let stageAllowed: Set<String>
        switch stage {
        case .selectingMember:
            stageAllowed = [
                SparkToolName.getCurrentMember.rawValue,
                SparkToolName.requestMemberSelection.rawValue
            ]
        case .collectingProfile:
            stageAllowed = [SparkToolName.queryMemberProfile.rawValue]
        case .collectingReports:
            stageAllowed = [
                SparkToolName.listMemberHealthSources.rawValue,
                SparkToolName.getHealthResourceReference.rawValue
            ]
        case .askingMissingInfo:
            stageAllowed = [SparkToolName.askUserQuestion.rawValue]
        case .planning, .completed:
            stageAllowed = []
        }
        return baseAllowed.intersection(stageAllowed)
    }
}
```

### 7.4 Trace 状态配对

```swift
struct DeepTutorTraceToolState {
    var rowsByCallID: [String: DeepTutorTraceRow] = [:]

    mutating func apply(_ event: DeepTutorStreamEvent) {
        switch event {
        case let .toolCallStarted(callID, toolName, _):
            rowsByCallID[callID] = DeepTutorTraceRow.running(callID: callID, toolName: toolName)
        case let .toolResult(callID, payload):
            rowsByCallID[callID]?.status = .completed
            rowsByCallID[callID]?.resultDetail = payload.summary
        case let .memberSelectionRequested(_, _, toolCallID):
            rowsByCallID[toolCallID]?.status = .awaitingInput
        default:
            break
        }
    }
}
```

### 7.5 Health plan card assembler

```swift
enum DeepTutorHealthExamPlanCardAssembler {
    static func event(from message: DeepTutorMessage) -> DeepTutorStreamEvent? {
        guard message.capability == .healthExamPlan else { return nil }
        guard message.events.contains(where: hasPlanEvent) == false else { return nil }
        guard message.events.containsPendingUserInput == false else { return nil }

        if let jsonPayload = DeepTutorHealthExamPlanEventMapper.draftEvent(from: message) {
            return jsonPayload
        }

        guard let profile = message.events.latestProfileSummary else {
            return nil
        }

        let payload = DeepTutorHealthExamPlanPayload.from(profile: profile, risk: message.events.latestRiskSummary)
        return .healthExamPlanDraftCreated(payload: payload)
    }
}
```

## 8. 分阶段落地

### Phase A：暂停边界止血

目标：

1. `awaiting_user_input` 后不再合并后续非 resume 事件。
2. trace pending 时标题显示“等待用户操作”。
3. ready 消息里不再出现 running 工具行。

### Phase B：稳定 toolCallID

目标：

1. tool start/result/pending 使用同一个 callID。
2. memberSelection 卡片 toolCallID 和 trace 行一致。
3. debug exporter 能输出 unmatched tool rows。

### Phase C：健康计划阶段状态机

目标：

1. `health_exam_plan` 按阶段允许工具。
2. 未选成员时只允许成员相关工具。
3. 选成员后 resume 再进入 profile/report 阶段。

### Phase D：健康计划卡片生成

目标：

1. profile/risk/plan 卡片按事件生成。
2. 如果资料不足，生成 missing info 卡片。
3. 不再只依赖最终文本中的 fenced JSON。

### Phase E：回放和调试完善

目标：

1. Debug snapshot 标出 pause boundary。
2. 标出 post-pause dropped events。
3. 标出卡片 assembler 失败原因。

## 9. 验收标准

### 9.1 复现本次输入

输入：

```text
我想为当前家庭成员制定下一次体检计划。请先根据已有健康档案询问必要信息。
```

未选成员时预期：

1. `activeCapability=health_exam_plan`。
2. 只出现 `get_current_member` 和 `request_member_selection`。
3. 出现 `memberSelection` pending 卡片。
4. 不出现 `query_member_profile` / `list_member_health_sources`。
5. trace 标题为“等待用户操作”。
6. 工具行没有 running 残留。

选择成员后预期：

1. memberSelection 卡片变 resolved。
2. resume 后才出现 `query_member_profile`。
3. 出现 `memberProfileSummary` 卡片。
4. 出现 `healthRiskSummary` 或 `healthResourceCandidateSelection`。
5. 最终出现 `healthExamPlan` 或 `healthExamPlanMissingInfo`。

### 9.2 日志验收

必须新增或确认：

```text
pauseBoundaryCount >= 1
postPauseEventCount = 0
traceRunningRowsAfterReadyCount = 0
healthExamPlanBlockCount >= 1 或 healthExamPlanMissingInfoBlockCount >= 1
```

### 9.3 状态验收

1. `finishReason=awaiting_user_input` 不等价于“已完成”。
2. pending 卡片存在时，消息状态不能误导为完整 ready。
3. trace、blocks、events 三者状态一致。

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 事件截断误删合法 resume 事件 | resume 后没有继续生成 | 所有 resume 事件必须带 `resumeMode` / `resumeTurnID` |
| 阶段工具过滤过严 | 模型无法灵活调用工具 | 每阶段保留 ask_user fallback，并在 debug 输出 suppressed reason |
| toolCallID 改造影响旧消息 | 历史 trace 无法配对 | legacy ID 保持兼容，新消息使用 stable ID |
| 计划卡片 assembler 过早兜底 | 卡片内容泛化 | 优先真实工具数据，兜底卡必须标记 `basis=default` |
| 消息状态新增 awaiting 影响 UI | 旧 UI 不认识状态 | 第一阶段可用 ready + pending block，但文案和 trace 必须表达等待 |

## 11. 结论

本次流程意外停止不是 capability 没命中，恰好相反：

```text
health_exam_plan 已经命中
Quiz gate 已经跳过
成员选择卡已经生成
```

真正的问题是：

```text
awaiting_user_input 没有成为硬暂停边界
暂停后的工具事件混入同一条消息
trace start/result callID 不稳定导致 running 残留
健康计划领域事件和卡片没有从工具结果中生成
```

修复方向是：

1. 建立 pause boundary。
2. 稳定 toolCallID。
3. 让 health_exam_plan 按阶段限制工具。
4. 让工具结果进入 profile/risk/plan 卡片，而不是只进入 trace。

完成后，DeepTutorChat 的健康体检计划流程应该能从“选择成员”自然推进到“整理档案、追问缺失信息、生成体检计划卡片”，不会再出现用户看到流程停住、内部事件却继续跑的状态分裂。
