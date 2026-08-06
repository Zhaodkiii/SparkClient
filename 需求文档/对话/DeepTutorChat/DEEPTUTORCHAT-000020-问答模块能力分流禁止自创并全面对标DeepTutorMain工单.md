# DEEPTUTORCHAT-000020 问答模块能力分流禁止自创并全面对标 DeepTutor-main 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000020 |
| 工单类型 | P0 问答模块能力分流治理 + DeepTutor-main 全链路对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 触发文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorCapabilityResolver.swift` |
| 创建日期 | 2026-08-06 |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000013`、`DEEPTUTORCHAT-000019` |
| 核心约束 | 不要自创能力识别规则；问答模块必须逐模块对标 DeepTutor-main 真实链路 |

## 1. 本工单目标

用户明确要求：

```text
不要自己创作。
创建新的工单，需要完全对标问答模块，每一个模块，每一个方案。
```

本工单目标：

```text
1. 将 `DeepTutorCapabilityResolver.swift` 中自创的健康问答关键词分流列为 P0 偏差。
2. 明确 Web DeepTutor-main 没有同名/同职责的自然语言关键词 resolver。
3. iOS 问答模块必须以 Web 的显式 capability 选择、Quiz 配置、发送请求、事件解析、消息渲染、答题状态为事实基线。
4. 后续修复不能再通过新增关键词、猜测用户意图、硬编码健康知识场景来“补效果”。
5. 逐模块建立 Web -> iOS 对齐清单，每个模块写明当前偏差、对标文件、目标方案和验收标准。
```

本工单只写需求与技术方案，不修改 Swift 代码。

## 2. 当前 iOS 偏差事实

### 2.1 当前触发文件

当前 iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorCapabilityResolver.swift
```

当前逻辑：

```swift
if selected == .deepQuestion {
    return .deepQuestion
}
if matchesHealthQuizIntent(userInput) {
    return .deepQuestion
}
return selected
```

关键词包含：

```text
健康知识
健康科普
健康测验
健康小测
健康问答
来一些题
来几道
出几道题
出点题
小测验
快问快答
考考我
quiz me
quick check
health quiz
health knowledge quiz
给我来一些
```

### 2.2 该逻辑的问题

该文件的问题不是语法问题，而是产品/架构偏差：

```text
1. Web DeepTutor-main 没有发现同等自然语言关键词 resolver。
2. iOS 会在用户选择 Chat 时，因为文本命中“健康知识/给我来一些”而自动改成 Quiz。
3. 这会改变用户显式选择的 capability。
4. 这会导致工具策略、Prompt、消息卡片、数据解析全部走问答链路。
5. 一旦 parser 或卡片未接管，就出现 JSON 泄漏、消息卡片异常、调试信息混乱。
6. 该方案属于 iOS 自创，不是对标 Web。
```

### 2.3 当前接入点

当前 `DeepTutorChatViewModel.swift` 发送时调用：

```text
let resolvedCapability = DeepTutorCapabilityResolver.resolvedCapability(
    userInput: text,
    selected: state.activeCapability
)
if resolvedCapability != state.activeCapability {
    state.activeCapability = resolvedCapability
}
```

偏差：

```text
1. Web 的 activeCapability 是 session 状态，由用户选择/历史恢复决定。
2. Web 发送时使用 effectiveCapability，不在发送时按文本关键词重写。
3. iOS 这里会修改 state.activeCapability，影响后续 UI chip、工具策略和消息 request snapshot。
```

### 2.4 工具策略层继续依赖自创判断

当前 `DeepTutorToolPolicyResolver.swift` 中也引用：

```text
if DeepTutorCapabilityResolver.matchesHealthQuizIntent(context.userInput) {
    ...
    policyReason = "capability_deep_question_health_quiz"
}
```

偏差：

```text
1. 工具策略不应依赖 iOS 自创关键词。
2. Web 的 deep_question 工具配置来自 capability 定义和用户配置，而非“健康知识”关键词。
3. 问答工具策略应按 Web capability 的 allowedTools/defaultTools/config 对齐。
```

## 3. DeepTutor-main 对标事实

### 3.1 Web 没有同名 CapabilityResolver

在 DeepTutor-main Web 端，对应能力选择不是一个自然语言 resolver 文件，而是以下模块组合：

```text
1. 页面定义能力列表 CAPABILITIES。
2. 用户在 Composer 选择 active capability。
3. UnifiedChatContext 保存 session.activeCapability。
4. 发送消息时读取 effectiveCapability。
5. 后端/运行时根据 capability 和 config 执行。
6. 消息渲染层根据 assistant message capability 分流到 QuizViewer。
```

结论：

```text
Web 没有“用户输入包含健康知识 -> 自动 deep_question”的前端规则。
```

### 3.2 Web 能力定义位置

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

`deep_question` 定义：

```text
value: "deep_question"
label: "Quiz"
description: "Auto-validated question generation"
allowedTools: ["web_search", "code_execution"]
defaultTools: ["web_search", "code_execution"]
```

对齐要求：

```text
iOS 的 Quiz 能力入口应来自用户显式选择 Quiz capability，不是文本关键词自动升级。
```

### 3.3 Web activeCapability 状态

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx
```

核心状态：

```text
activeCapability: string | null
SET_CAPABILITY
setCapability(cap)
```

发送时：

```text
const effectiveCapability =
  replaySnapshot?.capability ?? session.activeCapability;
```

然后发送：

```text
sendThroughRunner(key, {
  type: "start_turn",
  content,
  tools: effectiveTools,
  capability: effectiveCapability,
  ...
})
```

对齐要求：

```text
iOS 应同样使用“当前选中的 activeCapability / requestSnapshot capability”，不应在 send 时基于 userInput 重写 capability。
```

### 3.4 Web Quiz 配置位置

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizConfigPanel.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/CapabilityConfigCard.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

Web 默认配置：

```text
DEFAULT_QUIZ_CONFIG:
  mode
  num_questions
  difficulty
  question_types
  per_type_counts
```

页面逻辑：

```text
isQuizMode = activeCap.value === "deep_question"
capabilityNeedsConfig = isQuizMode || isVisualizeMode || isResearchMode
QuizConfigPanel hosted inside CapabilityConfigCard
capabilityConfigConfirmed gate
```

对齐要求：

```text
iOS 问答模块需要对齐 Quiz 配置，而不是用关键词决定“这是问答”。
```

### 3.5 Web Quiz 渲染位置

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx
```

渲染条件：

```text
if msg.capability !== "deep_question" return null
if resultEvent exists -> extractQuizQuestions(resultEvent.metadata)
else -> extractStreamingQuizQuestions(msg.events)
quizQuestions exists -> render QuizViewer
```

对齐要求：

```text
iOS 应在消息渲染层按 message.capability 和 quiz events/result 渲染卡片，不应靠输入关键词强制走 Quiz。
```

## 4. 逐模块对齐清单

### 4.1 能力入口模块

| 项 | Web | iOS 当前 | 目标 |
| --- | --- | --- | --- |
| 能力来源 | `CAPABILITIES` + Composer 显式选择 | Composer 选择 + `DeepTutorCapabilityResolver` 二次改写 | 去除文本改写，只保留显式选择/历史恢复 |
| Quiz 标识 | `deep_question` | `.deepQuestion` | 一一映射 |
| 默认 Chat | activeCapability 为空或 chat | `.chat` | 一致 |
| 健康知识自动问答 | 未发现 Web 前端规则 | iOS 自创关键词 | 禁止作为默认逻辑 |

目标方案：

```text
1. iOS 保留 `state.activeCapability` 作为唯一前端能力来源。
2. 用户选择 Quiz 后发送才是 `.deepQuestion`。
3. 若后续需要“意图推荐”，只能做非侵入式建议 UI，例如提示“是否切换到 Quiz”，不能静默改写。
4. 该建议 UI 也必须先在 Web 有对应实现或产品明确新增，不允许 iOS 单端自创。
```

### 4.2 Composer 模块

Web 对标：

```text
ChatComposer receives:
  activeCap
  capabilities
  capabilityNeedsConfig
  capabilityConfigConfirmed
  onRequestConfigConfirm
```

iOS 目标：

```text
1. Composer 显示 Chat / Quiz / Model 等能力状态。
2. 用户手动切换 capability。
3. 发送时不再自动改变 capability。
4. 如果 Quiz 需要配置，必须显式展示配置确认状态。
```

需要对标的 iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerToolbarView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerCardView.swift
```

### 4.3 Capability 配置模块

Web 对标：

```text
CapabilityConfigCard
QuizConfigPanel
DEFAULT_QUIZ_CONFIG
buildDeepQuestionConfig
```

iOS 当前缺口：

```text
1. Quiz 配置是否完整对齐需要复核。
2. 如果没有 QuizConfigPanel 等价物，当前 iOS 只靠 Prompt 生成 1-3 题，不能算完全对齐。
3. 不得用健康关键词替代配置面板。
```

iOS 目标：

```text
1. 支持 num_questions。
2. 支持 difficulty。
3. 支持 question_types。
4. 支持 per_type_counts。
5. 支持配置确认 gate。
6. 发送 requestSnapshot 时携带 config。
```

### 4.4 发送请求模块

Web 对标：

```text
UnifiedChatContext.sendMessage
  -> effectiveCapability = replaySnapshot?.capability ?? session.activeCapability
  -> requestSnapshot.capability = effectiveCapability
  -> start_turn.capability = effectiveCapability
  -> start_turn.tools = effectiveTools
  -> start_turn.config = effectiveConfig
```

iOS 当前偏差：

```text
DeepTutorChatViewModel.sendCurrentDraft
  -> DeepTutorCapabilityResolver.resolvedCapability(userInput:selected:)
  -> 可能静默改写 activeCapability
```

iOS 目标：

```text
1. send 使用 selected activeCapability。
2. request snapshot 保存 selected capability。
3. regenerate/edit 使用原 message requestSnapshot capability。
4. 不按 userInput 改写 capability。
5. 日志记录 selectedCapability/effectiveCapability，但不出现 keyword_auto_promoted。
```

### 4.5 工具策略模块

Web 对标：

```text
deep_question:
  allowedTools: ["web_search", "code_execution"]
  defaultTools: ["web_search", "code_execution"]
```

iOS 当前偏差：

```text
DeepTutorToolPolicyResolver 对 deepQuestion 额外调用 matchesHealthQuizIntent。
命中健康关键词时改变 policyReason 和 knowledge bag 行为。
```

iOS 目标：

```text
1. 工具策略按 capability/config/context 解析，不按健康关键词。
2. deepQuestion 默认工具对齐 Web allowedTools/defaultTools。
3. 是否使用 knowledge bag 由用户选择的知识库/上下文决定。
4. 工具策略日志使用 Web 对齐字段：allowedTools、defaultTools、enabledTools、actualTools。
```

### 4.6 Prompt 模块

Web 对标：

```text
Quiz 由 deep_question capability + config 驱动。
题型、数量、难度来自 config。
```

iOS 当前风险：

```text
如果 iOS Prompt 自行把健康知识写成固定 quiz_json 生成规则，会继续与 Web 后端 QuestionPipeline 偏移。
```

iOS 目标：

```text
1. Prompt 只表达 deep_question 通用能力要求。
2. 题目数量/难度/题型来自 Quiz config。
3. 结构化输出协议优先对齐 Web events/result metadata。
4. 文本 quiz_json 只能作为 fallback，不作为主协议。
```

### 4.7 事件与数据解析模块

Web 对标：

```text
extractStreamingQuizQuestions(events)
extractQuizQuestions(resultEvent.metadata)
extractQuizTurnId(events)
normalizeQuizQuestionType
```

iOS 目标：

```text
1. DeepTutorStreamEvent 支持 quizQuestionEmitted。
2. DeepTutorQuizExtractor 与 Web 字段一一对应。
3. DeepTutorQuizContentParser 只是兜底。
4. 解析失败不展示原始 JSON。
5. turnID 必须用于答题状态隔离。
```

### 4.8 Reducer 模块

Web 对标：

```text
AssistantMessage 根据 capability 和 result/events 分支：
  quizQuestions -> AssistantResponse(preface) + QuizViewer
```

iOS 目标：

```text
1. DeepTutorMessageReducer 只从真实 events/result 生成 quiz block。
2. 不硬编码健康知识卡片。
3. 不硬编码 Fixture。
4. `.quiz` block 存在时，text block 只保留前置说明。
```

### 4.9 UI 消息卡片模块

Web 对标：

```text
QuizViewer:
  header navigation
  progress
  chips
  choice/concept/fill_in_blank
  check answer
  retry
  reference answer
  AI judgment
  follow-up
```

iOS 目标：

```text
1. UI 细节按 DEEPTUTORCHAT-000013。
2. 不通过能力 resolver 强行制造卡片。
3. 卡片显示必须来自 `.quiz` block。
4. 原始 JSON 不进入可见正文。
```

### 4.10 本地状态与刷新模块

Web 对标：

```text
QuizViewer local state + notebook state
sessionId + turnId + questionId 隔离
```

iOS 目标：

```text
1. DeepTutorQuizAnswerStore 用 conversationID + assistantMessageID + turnID + questionID。
2. reload 不丢答题状态。
3. final result merge 不清空答案。
4. 对齐 DEEPTUTORCHAT-000012 的流式/reload 解耦。
```

### 4.11 日志与调试模块

iOS 目标日志：

```text
deeptutor.capability.selected
deeptutor.capability.effective
deeptutor.capability.snapshot
deeptutor.capability.unexpected_mutation
deeptutor.quiz.config.snapshot
deeptutor.quiz.extract.source_selected
deeptutor.quiz.render.block_created
deeptutor.quiz.render.raw_json_suppressed
```

禁止继续使用或新增：

```text
health_quiz_keyword_promoted
capability_auto_promoted_by_text
```

除非 Web 同步实现同等产品能力并有统一需求。

## 5. 必须删除/收敛的自创点

### 5.1 `DeepTutorCapabilityResolver`

目标：

```text
1. 不允许在发送时把 `.chat` 静默改成 `.deepQuestion`。
2. `matchesHealthQuizIntent` 不应作为主流程能力决策。
3. 如果保留文件，只能作为调试/建议层，并默认不改变 capability。
4. 更推荐移除 resolver，使 iOS 与 Web 一致：activeCapability 是唯一来源。
```

### 5.2 工具策略中的健康问答特殊分支

目标：

```text
1. 移除 `matchesHealthQuizIntent(context.userInput)` 对工具策略的影响。
2. deepQuestion 工具策略按 Web capability 定义和用户 config/contexts。
3. 健康知识只是用户内容，不是 iOS 特殊 capability。
```

### 5.3 Prompt 中健康场景硬编码

目标：

```text
1. 不为“健康知识”写特殊 Prompt。
2. 问答题材由用户输入和上下文自然决定。
3. 题型/数量/难度由 QuizConfig 决定。
```

## 6. 分阶段实施方案

### P0-1：冻结 Web 对标事实

产出：

```text
1. Web capability 定义表。
2. Web sendMessage effectiveCapability 链路。
3. Web QuizConfig 字段表。
4. Web QuizViewer 渲染状态机。
5. Web events/result 解析协议。
```

验收：

```text
文档中每个结论都有 Web 文件路径证据。
```

### P0-2：治理 iOS 自创 capability resolver

目标：

```text
1. 发送消息不再调用关键词自动升级。
2. activeCapability 不再被 userInput 静默改写。
3. 健康知识输入在 Chat 模式下保持 Chat。
4. 用户手动选 Quiz 时才走 Quiz。
```

验收：

```text
1. Chat 模式输入“健康知识给我来一些”，日志 capability=chat。
2. Quiz 模式输入同一句，日志 capability=deep_question。
3. 不出现 state.activeCapability 被自动改成 deepQuestion。
```

### P0-3：工具策略对齐

目标：

```text
1. deepQuestion allowedTools/defaultTools 对齐 Web。
2. 移除健康关键词影响。
3. Knowledge bag 使用只由用户选中知识库或上下文决定。
```

验收：

```text
同一 capability/config 下，iOS allowed tools 与 Web 目标一致。
```

### P0-4：Quiz 配置对齐

目标：

```text
1. iOS 提供或承接 QuizConfig。
2. request snapshot 中有 config。
3. regenerate/edit 使用原 config。
```

验收：

```text
发送请求日志能看到 num_questions、difficulty、question_types。
```

### P0-5：消息卡片对齐

目标：

```text
1. Quiz 卡片只由真实 quiz block 渲染。
2. 原始 JSON 不进入正文。
3. UI 和交互按 DEEPTUTORCHAT-000013。
```

验收：

```text
Web 与 iOS 在同一 Quiz 输出下卡片结构一致。
```

### P1：非侵入式意图建议

只有在产品确认需要时才做：

```text
1. 用户在 Chat 模式输入“出几道题”。
2. iOS 可提示：“是否切换到 Quiz 模式？”
3. 用户确认后才切换。
4. Web 也需要同步同等能力，否则不做。
```

## 7. 验收用例

### 7.1 Chat 模式不自动切 Quiz

步骤：

```text
1. iOS 选择 Chat。
2. 输入：健康知识给我来一些。
3. 发送。
```

期望：

```text
1. effectiveCapability=chat。
2. activeCapability 仍为 chat。
3. 不调用 deepQuestion Prompt。
4. 不出现 Quiz 卡片，除非后端/模型在 Chat 中明确返回可渲染卡片协议并 Web 同样支持。
```

### 7.2 Quiz 模式明确生成问答

步骤：

```text
1. iOS 选择 Quiz。
2. 输入：健康知识给我来一些。
3. 发送。
```

期望：

```text
1. effectiveCapability=deep_question。
2. 使用 QuizConfig。
3. 使用 deepQuestion 工具策略。
4. 生成 Quick Check 卡片。
5. 不展示原始 JSON。
```

### 7.3 Regenerate 使用原 capability

步骤：

```text
1. 对一条 Quiz 回答点击重试/重新生成。
```

期望：

```text
1. 使用原 requestSnapshot.capability。
2. 不重新跑关键词 resolver。
3. 原 config/tools/knowledgeBases 保持。
```

### 7.4 Edit 分支使用原链路

步骤：

```text
1. 编辑一条用户消息。
2. 内容包含或不包含“健康知识”。
```

期望：

```text
1. 如果用户当前显式选择 Chat，则仍 Chat。
2. 如果 requestSnapshot 来自 Quiz，则保持 Quiz。
3. 不因关键词变化导致历史分支能力漂移。
```

### 7.5 工具策略不受健康关键词影响

步骤：

```text
1. Chat 输入：健康知识给我来一些。
2. Quiz 输入：健康知识给我来一些。
```

期望：

```text
1. Chat 工具策略按 chat。
2. Quiz 工具策略按 deep_question。
3. 日志中不出现 capability_deep_question_health_quiz 这类 iOS 自创 reason。
```

## 8. 风险与注意事项

### 8.1 不要通过关键词修 UI 问题

Quick Check 卡片不显示的根因在事件解析、Reducer、正文清洗和 UI 分流，不应该通过“命中健康知识就切 Quiz”修复。

### 8.2 不要让 iOS 单端能力漂移

如果 iOS 自己支持 Chat 输入自动变 Quiz，而 Web 不支持，会导致多端同一输入得到不同交付语义。

### 8.3 不要隐藏用户显式选择

用户选 Chat 就应按 Chat 发送。除非用户确认切换，否则系统不应静默修改。

### 8.4 不要把内容主题当 capability

“健康知识”是 topic，不是 capability。capability 是用户选择的工作模式：Chat、Quiz、Research、Visualize 等。

## 9. 最终验收标准

实现完成后必须满足：

```text
1. `DeepTutorCapabilityResolver` 不再作为发送主流程能力改写入口。
2. iOS 不再基于健康知识等关键词静默切换 `.deepQuestion`。
3. iOS capability 来源对齐 Web：用户选择、session.activeCapability、requestSnapshot。
4. iOS 问答模块的能力入口、配置、发送、工具策略、Prompt、事件解析、Reducer、UI、持久化全部有 Web 对标路径。
5. Chat 模式输入“健康知识给我来一些”不会自动显示 Quiz 卡片。
6. Quiz 模式输入“健康知识给我来一些”会按 Web Quiz 链路生成问答卡片。
7. regenerate/edit 不因文本关键词重新判定 capability。
8. 工具策略不再出现健康关键词专用分支。
9. 后续任何“意图推荐”必须作为跨端产品能力另立需求，且用户确认后才切换。
10. 调试日志能明确展示 selectedCapability、effectiveCapability、requestSnapshotCapability、messageCapability，且无静默改写。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
