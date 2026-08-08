# DEEPTUTORCHAT-000041 DeepTutorChat 工具调用与 Quiz 卡片流程对齐 DeepTutor-main 优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000041 |
| 工单类型 | P0 流程修复 / DeepTutor-main 对齐 / 工具调用与卡片闭环优化 |
| 当前范围 | 创建优化工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 对标项目 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-08 |
| 触发日志 | `deeptutor.quiz.extract.failed ... reason=no_quiz_data` |
| 核心目标 | 分析当前 DeepTutorChat 工具调用、成员选择、健康资料、Quiz 提取和卡片展示没有完成闭环的原因，并对齐 DeepTutor-main 的 capability pipeline、StreamBus 事件和卡片渲染方式 |

## 1. 现象与日志结论

本次日志关键片段：

```text
deeptutor.quiz.extract.failed
conversation=A9B50F9B
assistant=1B67D26A
turnID=msg-1B67D26A...
reason=no_quiz_data

activeCapability: chat
turnPlan: capability=chat, stage=exploring
blockKinds: envelope=2,memberSelection=1,text=1,trace=1
quizBlockCount: 0
quizQuestionCount: 0
streamingQuizQuestionEventCount: 0
eventTypes: memberSelectionRequested=1,reasoningDelta=1,result=2,toolCallStarted=2,toolResult=2
finishReason=awaiting_user_input
```

可以直接判断：

1. 当前用户诉求是“制定体检计划”，不是 Quiz。
2. 当前运行 capability 是 `chat`，不是 `deep_question`。
3. 工具链正确触发了成员选择，但 turn 暂停在 `awaiting_user_input`。
4. 消息中没有 `quizQuestionEmitted`，也没有 result summary JSON。
5. 但 `DeepTutorQuizExtractor` 仍在 ready 阶段执行，并记录 `no_quiz_data`。

所以这不是“题目 JSON 解析失败”的主问题，而是：

```text
非 Quiz turn 被 Quiz 提取器扫描
健康计划 turn 被当成普通 chat + 工具 trace 处理
工具交互后没有形成领域卡片 / 计划卡片闭环
```

## 2. 为什么整个流程没有完成

### 2.1 capability 没有切到正确业务模式

日志显示：

```text
activeCapability: chat
turnPlan: capability=chat
```

但用户的目标是：

```text
为当前家庭成员制定下一次体检计划
先根据已有健康档案询问必要信息
```

这类请求应该进入健康计划类 capability 或至少进入 DeepTutorChat 的 domain workflow，而不是只停留在普通 `chat`。

当前结果是：

1. 模型先调用 `request_member_selection`。
2. 选成员卡片出现。
3. turn 暂停。
4. 没有继续进入“查询成员档案 -> 整理健康资料 -> 追问缺失信息 -> 生成体检计划卡片”的流水线。

### 2.2 工具调用和卡片产物没有一一对应

日志中已有工具事件：

```text
toolCallStarted=request_member_selection
memberSelectionRequested
toolResult=request_member_selection
toolCallStarted=list_member_health_sources
```

但最终卡片只有：

```text
memberSelection
trace
text
envelope
```

缺少：

```text
healthResourceCandidateSelection
healthResourceReference
memberProfileSummary
healthExamPlanDraft
missingInformationQuestions
```

也就是说，工具调用存在，但卡片层没有完整承接工具结果。

### 2.3 Quiz 提取器运行条件过宽

当前 `SendDeepTutorAIMessageUseCase.finalizeAssistantMessage` 会执行：

```swift
let parsed = DeepTutorQuizContentParser.apply(to: assistant)
return DeepTutorMessageReducer.applyBlocks(to: parsed)
```

同时 debug exporter 会调用：

```swift
DeepTutorQuizExtractor.extract(from: message)
```

而 `DeepTutorQuizExtractor.extract(from:)` 在没有 quiz 数据时会记录：

```swift
reportExtractionFailure(reason: "no_quiz_data")
```

问题是它没有先判断：

```text
当前 capability 是否 deepQuestion / quiz
当前事件里是否出现 quizQuestionEmitted
当前 result 是否声明 source=deep_question
当前内容是否包含 quiz schema
```

所以普通 chat / health plan / member selection turn 也会产生 quiz failure 噪音。

### 2.4 DeepTutor-main 的 quiz 是 capability 产物，不是事后扫文本

DeepTutor-main 中 `DeepQuestionCapability` 的 manifest 明确：

```python
CapabilityManifest(
    name="deep_question",
    stages=["ideation", "generation"],
    tools_used=["rag", "web_search", "code_execution"],
)
```

`QuestionPipeline` 的结构是：

```text
Phase 1 Explore
Phase 2 Plan
Phase 3 Quiz
```

其中 Phase 3 每生成一题，就解析严格 JSON 并发：

```text
quiz_question_emitted
```

前端直接按事件渲染 Quiz card。

Spark 侧虽然已有 `DeepTutorStreamEvent.quizQuestionEmitted` 和 `DeepTutorQuizCardView`，但当前来源更偏“流式内容/完成内容里尝试提取”，没有做到 capability pipeline 自己产出结构化卡片事件。

### 2.5 健康计划缺少专属 card schema

当前 DeepTutorChat 已有：

```text
memberSelection
askUser
healthResourceCandidateSelection
healthResourceReference
quiz
trace
```

但体检计划智能体需要的是：

```text
memberProfileSummaryCard
healthRiskSummaryCard
healthExamPlanCard
missingInformationQuestionCard
healthExamPreparationCard
followUpChecklistCard
```

工具返回后如果只进入 trace，而没有进入这些领域卡片，用户会感知为“工具跑了，但任务没完成”。

## 3. DeepTutor-main 对齐基准

### 3.1 Capability 接管整个 turn

DeepTutor-main 的 `runtime/orchestrator.py`：

```python
cap_name = context.active_capability or "chat"
capability = self._cap_registry.get(cap_name)
await capability.run(context, bus)
```

也就是说：

```text
orchestrator 只负责路由
capability 负责本轮业务流水线
StreamBus 负责事件输出
```

DeepTutorChat 需要对齐为：

```text
DeepTutorTurnCoordinator
  -> capability resolver
  -> capability workflow
  -> tool policy
  -> stream events
  -> message blocks
```

### 3.2 Quiz 不是通用提取器，而是 deep_question 的结构化输出

DeepTutor-main 的 `QuestionPipeline` 写得很明确：

```text
Explore: 使用工具调研
Plan: 输出 JSON plan
Quiz: 每题一个循环，FINISH 是严格 JSON
emit quiz_question_emitted
```

Spark 侧对齐目标：

```text
只有 deepQuestion capability 才触发 quiz parser / quiz extractor
deepQuestion 过程必须发 quizQuestionEmitted
QuizCard 只消费 quizQuestionEmitted 或 deep_question result
```

### 3.3 工具事件必须转成可渲染事件

DeepTutor-main 的 `StreamBus` 支持：

```text
stage_start / stage_end
content
thinking
tool_call
tool_result
progress
sources
result
done
```

Spark 侧已有：

```text
DeepTutorStreamEvent
DeepTutorAIRuntimeEventMapper
DeepTutorMessageReducer
DeepTutorMessageBlock
```

需要补齐的是：

```text
工具调用结果 -> 结构化 domain event -> DeepTutorMessageBlock -> 卡片
```

而不是只在 trace 里展示工具 JSON。

## 4. 优化目标

### 4.1 短期目标

1. `DeepTutorQuizExtractor` 只在 quiz turn 中运行。
2. 非 quiz turn 不再输出 `deeptutor.quiz.extract.failed reason=no_quiz_data`。
3. 成员选择恢复后，健康计划 turn 能继续进入工具查询链路。
4. 健康资料工具结果能生成 DeepTutor 专属资料卡片。
5. 体检计划智能体能生成计划卡片，而不是只输出纯文本。

### 4.2 中期目标

1. 对齐 DeepTutor-main 的 capability pipeline：每类能力由 workflow 接管 turn。
2. 建立 `DeepTutorCapabilityWorkflow` 协议。
3. 建立 health exam plan 专属 domain event 和 card schema。
4. 建立 per-capability event-to-card mapper。
5. Debug exporter 能按 capability 展示阶段、工具、卡片、失败原因。

## 5. 目标流程

### 5.1 体检计划智能体完整流程

```text
用户：制定体检计划
  -> capabilityResolver 识别 healthExamPlan
  -> DeepTutorHealthExamPlanWorkflow.start
  -> 如果没有 memberID
      -> request_member_selection
      -> DeepTutorMemberSelectionCardView
      -> submitMemberSelection
      -> resume same assistant message
  -> query_member_profile
  -> list_member_health_sources
  -> get_health_resource_reference
  -> 整理基础档案、病史、症状、生活习惯、过往体检、风险评估
  -> 如果缺关键资料
      -> ask_user
      -> DeepTutorAskUserCardView
      -> resume same assistant message
  -> 生成 healthExamPlanDraft event
  -> DeepTutorHealthExamPlanCardView
  -> 输出最终体检计划 + 复查闭环
```

### 5.2 DeepQuestion / Quiz 完整流程

```text
用户切换 Deep Question / Quiz capability
  -> DeepTutorDeepQuestionWorkflow
  -> exploring stage
  -> planning stage
  -> per-question generation stage
  -> 每题 emit quizQuestionEmitted
  -> DeepTutorMessageReducer upsert quiz block
  -> DeepTutorQuizCardView 即时展示
  -> 完成后 result 带 summaryJSON
```

### 5.3 非 Quiz turn 的 finalize 流程

```text
assistant ready
  -> if capability == deepQuestion or hasQuizEvents
      -> run quiz parser/extractor
  -> else
      -> skip quiz parser/extractor
  -> apply message blocks
  -> persist
```

## 6. 技术方案

### 6.1 增加 capability-aware finalize

当前：

```swift
nonisolated private func finalizeAssistantMessage(_ assistant: DeepTutorMessage) -> DeepTutorMessage {
    let parsed = DeepTutorQuizContentParser.apply(to: assistant)
    return DeepTutorMessageReducer.applyBlocks(to: parsed)
}
```

建议：

```swift
nonisolated private func finalizeAssistantMessage(_ assistant: DeepTutorMessage) -> DeepTutorMessage {
    let shouldParseQuiz = DeepTutorQuizGate.shouldParseQuiz(message: assistant)
    let prepared = shouldParseQuiz
        ? DeepTutorQuizContentParser.apply(to: assistant)
        : assistant
    return DeepTutorMessageReducer.applyBlocks(to: prepared)
}
```

新增：

```swift
enum DeepTutorQuizGate {
    static func shouldParseQuiz(message: DeepTutorMessage) -> Bool {
        if message.capability == .deepQuestion { return true }
        if message.events.contains(where: isQuizEvent) { return true }
        if message.content.contains("\"question_type\"") { return true }
        return false
    }

    private static func isQuizEvent(_ event: DeepTutorStreamEvent) -> Bool {
        if case .quizQuestionEmitted = event { return true }
        if case let .result(metadata, summaryJSON) = event {
            return metadata["source"] == "deep_question"
                || summaryJSON?.contains("\"question_type\"") == true
        }
        return false
    }
}
```

### 6.2 Debug exporter 也必须带 gate

当前 debug exporter 会直接：

```swift
DeepTutorQuizExtractor.extract(from: message)
```

建议：

```swift
let quizExtraction = DeepTutorQuizGate.shouldParseQuiz(message: latestAssistant)
    ? DeepTutorQuizExtractor.extract(from: latestAssistant)
    : DeepTutorQuizExtractor.ExtractResult(
        payload: nil,
        source: .streaming,
        questionCount: 0,
        failureReason: nil
    )
```

这样非 quiz turn 不再产生误导日志。

### 6.3 Quiz extractor 不应该把 no data 都当 failed

建议把失败分为：

```text
skipped_not_quiz_turn
no_quiz_data_in_quiz_turn
invalid_quiz_json
schema_mismatch
```

核心代码：

```swift
enum DeepTutorQuizExtractionReason: String {
    case skippedNotQuizTurn = "skipped_not_quiz_turn"
    case noQuizDataInQuizTurn = "no_quiz_data_in_quiz_turn"
    case invalidQuizJSON = "invalid_quiz_json"
    case schemaMismatch = "schema_mismatch"
}
```

### 6.4 建立 capability workflow 协议

对齐 DeepTutor-main 的 `BaseCapability.run(context, stream)`，Swift 侧建议增加：

```swift
protocol DeepTutorCapabilityWorkflow: Sendable {
    var capability: DeepTutorCapability { get }

    func prepare(
        context: DeepTutorTurnContext
    ) async throws -> DeepTutorWorkflowPlan

    func handle(
        event: DeepTutorStreamEvent,
        context: DeepTutorTurnContext
    ) async -> [DeepTutorMessageBlock]
}
```

首批实现：

```text
DeepTutorChatWorkflow
DeepTutorDeepQuestionWorkflow
DeepTutorHealthExamPlanWorkflow
```

### 6.5 体检计划 domain event

新增事件：

```swift
extension DeepTutorStreamEvent {
    case memberProfileSummaryCreated(payload: DeepTutorMemberProfileSummaryPayload)
    case healthRiskSummaryCreated(payload: DeepTutorHealthRiskSummaryPayload)
    case healthExamPlanDraftCreated(payload: DeepTutorHealthExamPlanPayload)
    case healthExamPlanMissingInfoRequested(payload: DeepTutorHealthExamPlanMissingInfoPayload)
}
```

新增 block：

```swift
enum DeepTutorMessageBlockKind: String, Codable, Sendable {
    case memberProfileSummary
    case healthRiskSummary
    case healthExamPlan
    case healthExamPlanMissingInfo
}
```

### 6.6 体检计划卡片数据

```swift
struct DeepTutorHealthExamPlanPayload: Codable, Equatable, Sendable {
    var memberID: Int
    var title: String
    var riskLevel: String
    var basis: [String]
    var baseItems: [DeepTutorExamPlanItem]
    var additionalItems: [DeepTutorExamPlanItem]
    var preparation: [String]
    var followUp: [String]
    var missingInformation: [String]
    var generatedAt: Date
}

struct DeepTutorExamPlanItem: Codable, Equatable, Sendable {
    var name: String
    var category: String
    var reason: String
    var priority: String
    var suggestedFrequency: String?
}
```

### 6.7 工具结果转领域卡片

```swift
enum DeepTutorHealthExamPlanEventMapper {
    static func events(
        from toolResult: DeepTutorToolResultPayload,
        context: DeepTutorTurnContext
    ) -> [DeepTutorStreamEvent] {
        switch toolResult.kind {
        case SparkToolName.queryMemberProfile.rawValue:
            return [.memberProfileSummaryCreated(payload: makeProfilePayload(toolResult))]
        case SparkToolName.getHealthResourceReference.rawValue:
            return [.healthRiskSummaryCreated(payload: makeRiskPayload(toolResult))]
        default:
            return []
        }
    }
}
```

### 6.8 MessageReducer 按事件生成卡片

```swift
extension DeepTutorMessageReducer {
    static func applyDomainEvent(
        _ event: DeepTutorStreamEvent,
        to blocks: inout [DeepTutorMessageBlock]
    ) {
        switch event {
        case let .healthExamPlanDraftCreated(payload):
            blocks.upsert(
                kind: .healthExamPlan,
                toolCallID: payload.memberID.description,
                payload: .healthExamPlan(payload)
            )
        case let .memberProfileSummaryCreated(payload):
            blocks.upsert(
                kind: .memberProfileSummary,
                toolCallID: payload.memberID.description,
                payload: .memberProfileSummary(payload)
            )
        default:
            break
        }
    }
}
```

## 7. 相关带动文件说明

### 7.1 DeepTutorChat Application

#### `Application/SendDeepTutorAIMessageUseCase.swift`

改造点：

1. `finalizeAssistantMessage` 增加 `DeepTutorQuizGate`。
2. resume 成员选择后继续 health exam plan workflow。
3. `shouldForcePersist` 增加 health resource candidate / consent / plan missing info pending 卡片。

#### `Application/DeepTutorAIRuntimeAdapter.swift`

改造点：

1. completionEvents 里补 `turn_id`、`capability`、`stage`。
2. onPartial 映射工具结果时调用 domain mapper。
3. 不在所有 capability 中执行 quiz during streaming parser。

#### `Application/DeepTutorAIRuntimeEventMapper.swift`

改造点：

1. 保留 ask_user、memberSelection、healthResourceCandidates 映射。
2. 增加 health exam plan domain event 映射。
3. quizQuestionEmitted 只由 deepQuestion workflow 或明确 quiz payload 触发。

#### `Application/DeepTutorQuizExtractor.swift`

改造点：

1. 接入 `DeepTutorQuizGate`。
2. 将非 quiz turn 标记为 skip，不记 failed。
3. 只有 deepQuestion turn 没有 quiz 数据时才记录 failure。

#### `Application/DeepTutorQuizContentParser.swift`

改造点：

1. 增加 capability 参数。
2. 对 `.chat`、health plan 等 capability 默认不解析。
3. 对 `.deepQuestion` 支持 result JSON、streaming event、legacy content 三种来源。

#### `Application/DeepTutorChatDebugExporter.swift`

改造点：

1. debug 输出增加 `quizGateDecision`。
2. 非 quiz turn 显示 `quizExtractionSource: skipped_not_quiz_turn`。
3. 增加 health workflow section：member profile、health sources、plan card、missing info。

### 7.2 DeepTutorChat Domain

#### `Domain/DeepTutorCapability.swift`

改造点：

1. 新增或预留 `healthExamPlan` capability。
2. 增加 capability stage 定义：
   - `chat`: exploring / responding
   - `deepQuestion`: exploring / planning / quizzing
   - `healthExamPlan`: selectingMember / collectingProfile / collectingReports / askingMissingInfo / planning

#### `Domain/DeepTutorStreamEvent.swift`

改造点：

1. 增加 health exam plan domain events。
2. result metadata 标准化：
   - `turn_id`
   - `capability`
   - `stage`
   - `source`
   - `parse_failed`

#### `Domain/DeepTutorMessageBlock.swift`

改造点：

1. 新增 health plan block kind 和 payload。
2. 确保 Codable 兼容旧消息。
3. 每个卡片都带 `toolCallID` 或 domain key，便于 upsert。

#### `Domain/DeepTutorQuizModels.swift`

改造点：

1. 对齐 DeepTutor-main 的 question taxonomy：
   - `choice`
   - `concept`
   - `fill_in_blank`
   - `short_answer`
   - `written`
   - `coding`
2. 保证 `turnID` 是 quiz answer store 的强隔离键。

### 7.3 DeepTutorChat Presentation

#### `Presentation/Cards/DeepTutorQuizCardView.swift`

改造点：

1. 仅渲染 deepQuestion 产物。
2. 显示 stage / turnID。
3. 对齐 DeepTutor-main QuizViewer：答题、判题、收藏、追问。

#### 新增 `Presentation/Cards/DeepTutorHealthExamPlanCardView.swift`

职责：

1. 展示基础项目。
2. 展示专项加项。
3. 展示每项原因。
4. 展示体检前准备。
5. 展示报告解读和复查闭环。

#### 新增 `Presentation/Cards/DeepTutorMemberProfileSummaryCardView.swift`

职责：

1. 展示年龄、性别、身高体重。
2. 展示慢病、过敏、用药、家族史、生活方式摘要。
3. 标出缺失字段。

#### 新增 `Presentation/Cards/DeepTutorHealthRiskSummaryCardView.swift`

职责：

1. 展示风险点。
2. 展示依据来源。
3. 展示建议追问。

#### `Presentation/Bubbles/DeepTutorAssistantBubble.swift`

改造点：

1. 新增 health plan 卡片渲染分支。
2. quiz 卡片仅对 quiz block 渲染，不从普通 text 中猜。

### 7.4 Infrastructure

#### `Infrastructure/DeepTutorMessageCodec.swift`

改造点：

1. 注册新 block kind 常量。
2. 兼容历史 block。

#### `Infrastructure/DeepTutorLocalChatStore.swift`

改造点：

1. 持久化新增 block kind。
2. pending 卡片恢复时保持状态。

## 8. 核心代码示例

### 8.1 Quiz gate

```swift
enum DeepTutorQuizGate {
    static func decision(for message: DeepTutorMessage) -> DeepTutorQuizGateDecision {
        if message.capability == .deepQuestion {
            return .parse(reason: "capability_deep_question")
        }
        if message.events.contains(where: hasQuizEvent) {
            return .parse(reason: "quiz_event_present")
        }
        if DeepTutorQuizContentParser.hasQuizJsonInContent(message.content) {
            return .parse(reason: "legacy_quiz_json")
        }
        return .skip(reason: "skipped_not_quiz_turn")
    }

    private static func hasQuizEvent(_ event: DeepTutorStreamEvent) -> Bool {
        switch event {
        case .quizQuestionEmitted:
            return true
        case let .result(metadata, summaryJSON):
            return metadata["source"] == "deep_question"
                || summaryJSON?.contains("\"question_type\"") == true
        default:
            return false
        }
    }
}

enum DeepTutorQuizGateDecision: Equatable, Sendable {
    case parse(reason: String)
    case skip(reason: String)
}
```

### 8.2 Capability-aware finalize

```swift
nonisolated private func finalizeAssistantMessage(_ assistant: DeepTutorMessage) -> DeepTutorMessage {
    let decision = DeepTutorQuizGate.decision(for: assistant)
    let prepared: DeepTutorMessage
    switch decision {
    case .parse:
        prepared = DeepTutorQuizContentParser.apply(to: assistant)
    case .skip:
        prepared = assistant
    }
    return DeepTutorMessageReducer.applyBlocks(to: prepared)
}
```

### 8.3 DeepQuestion workflow 事件输出

```swift
struct DeepTutorDeepQuestionWorkflow: DeepTutorCapabilityWorkflow {
    let capability: DeepTutorCapability = .deepQuestion

    func handleQuestionPayload(
        _ question: DeepTutorQuizQuestion,
        index: Int,
        turnID: String
    ) -> DeepTutorStreamEvent {
        .quizQuestionEmitted(
            question: question,
            questionIndex: index,
            turnID: turnID
        )
    }
}
```

### 8.4 Health plan payload

```swift
struct DeepTutorHealthExamPlanPayload: Codable, Equatable, Sendable {
    let memberID: Int
    let riskSummary: [String]
    let baseItems: [DeepTutorExamPlanItem]
    let additionalItems: [DeepTutorExamPlanItem]
    let preparation: [String]
    let followUp: [String]
}
```

### 8.5 Health plan card reducer

```swift
extension DeepTutorMessageReducer {
    static func applyHealthPlanEvent(
        _ event: DeepTutorStreamEvent,
        blocks: inout [DeepTutorMessageBlock]
    ) {
        guard case let .healthExamPlanDraftCreated(payload) = event else { return }
        blocks.upsert(
            kind: .healthExamPlan,
            toolCallID: "health-exam-plan-\(payload.memberID)",
            payload: .healthExamPlan(payload)
        )
    }
}
```

## 9. 落地阶段

### Phase A：止血修复

目标：

1. 增加 `DeepTutorQuizGate`。
2. 非 quiz turn 不再报 `no_quiz_data`。
3. Debug exporter 显示 skipped，而不是 failed。

涉及文件：

```text
DeepTutorQuizExtractor.swift
DeepTutorQuizContentParser.swift
SendDeepTutorAIMessageUseCase.swift
DeepTutorChatDebugExporter.swift
```

### Phase B：工具事件到卡片闭环

目标：

1. member selection、health source、health reference 都有对应卡片。
2. 工具 result 不只进 trace。
3. 卡片带 toolCallID，可 pending / resolved / failed。

涉及文件：

```text
DeepTutorAIRuntimeEventMapper.swift
DeepTutorMessageReducer.swift
DeepTutorMessageBlock.swift
DeepTutorAssistantBubble.swift
```

### Phase C：体检计划 workflow

目标：

1. 新增 healthExamPlan capability 或 workflow。
2. 串起成员选择、档案查询、资料引用、缺失信息追问、计划生成。
3. 生成健康计划专属卡片。

涉及文件：

```text
DeepTutorCapability.swift
DeepTutorToolPolicyResolver.swift
DeepTutorPromptBuilder.swift
DeepTutorPromptMerger.swift
DeepTutorHealthExamPlanWorkflow.swift
DeepTutorHealthExamPlanCardView.swift
```

### Phase D：对齐 DeepTutor-main deep_question

目标：

1. deepQuestion 采用 exploring / planning / quizzing 阶段。
2. 每题直接 emit `quizQuestionEmitted`。
3. QuizCard 不依赖普通文本扫 JSON。

涉及文件：

```text
DeepTutorDeepQuestionWorkflow.swift
DeepTutorAIRuntimeEventMapper.swift
DeepTutorQuizModels.swift
DeepTutorQuizCardView.swift
DeepTutorQuizAnswerStore.swift
```

### Phase E：测试与回放

目标：

1. 建立 fixture 测试：chat turn、health plan turn、deepQuestion turn。
2. 验证每类 turn 的 block kinds。
3. 验证非 quiz turn 不产出 quiz failure 日志。

## 10. 验收标准

### 10.1 本次日志对应验收

复现同样输入：

```text
我想为当前家庭成员制定下一次体检计划。请先根据已有健康档案询问必要信息。
```

预期：

1. 不出现 `deeptutor.quiz.extract.failed reason=no_quiz_data`。
2. 如果未选成员，出现 DeepTutor 成员选择卡片。
3. 选成员后继续同一 assistant message resume。
4. 工具查询成员基础档案和健康资料。
5. 消息中出现成员档案摘要卡、风险摘要卡或体检计划草稿卡。
6. 如果资料不足，出现 DeepTutor ask_user 缺失信息追问卡。

### 10.2 DeepQuestion 验收

1. `activeCapability=deep_question` 时才进入 Quiz 流程。
2. 每道题通过 `quizQuestionEmitted` 生成卡片。
3. `DeepTutorQuizExtractor` 能从 streaming event 或 result 中提取。
4. `turnID` 隔离每次 quiz 的答题状态。

### 10.3 工具调用验收

1. 每个 toolCallID 都能在 trace 和卡片中对应。
2. pending 卡片刷新后可恢复。
3. 工具副作用能转成 DeepTutorMessageBlock。
4. 不同 capability 只渲染自己的卡片。

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| Quiz gate 过严 | 旧版 quiz 文本无法显示卡片 | 保留 legacy JSON 检测作为 fallback |
| healthExamPlan capability 新增范围大 | 排期变长 | Phase A 先止血，Phase C 再做完整 workflow |
| 工具事件映射重复 | reducer 复杂 | 引入 per-capability event mapper |
| 体检计划卡片字段过早定死 | 后续扩展困难 | payload 保留 `basis`、`missingInformation`、`metadata` |
| DeepTutor-main 与 Spark 工具名不完全一致 | 对齐困难 | 对齐事件语义，不强行复制 Python 文件结构 |

## 12. 结论

这次问题的核心不是 Quiz 解析器本身坏了，而是：

```text
capability 边界不清
非 quiz turn 也跑 quiz extractor
健康计划工具链没有领域卡片承接
工具调用结果更多停留在 trace，没有形成 DeepTutor-main 式 stream event -> card 闭环
```

优化方向是：

1. 先用 `DeepTutorQuizGate` 止血。
2. 再把工具结果稳定映射为 DeepTutor 卡片。
3. 最后按 DeepTutor-main 的 capability pipeline 思路，把 `deepQuestion` 和 `healthExamPlan` 都做成明确 workflow。

完成后，DeepTutorChat 会更接近 DeepTutor-main 的模式：

```text
Capability 接管 turn
Tools 服务 capability
StreamEvent 是唯一中间产物
MessageBlock / Card 是前端投影
Extractor 只做兼容兜底，不再主导流程
```
