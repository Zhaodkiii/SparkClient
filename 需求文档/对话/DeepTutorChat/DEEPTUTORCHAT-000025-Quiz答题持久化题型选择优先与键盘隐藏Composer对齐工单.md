# DEEPTUTORCHAT-000025 Quiz 答题持久化、题型选择优先与键盘隐藏 Composer 对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000025 |
| 工单类型 | P0 Quiz 体验与状态持久化修复 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | App 重新打开后 Quiz 问答数据/答题状态不可见；题型不是以选择题为主；Quiz 输入弹键盘时底部 Message DeepTutor 输入区仍占位 |
| 关联工单 | `DEEPTUTORCHAT-000013`、`DEEPTUTORCHAT-000021`、`DEEPTUTORCHAT-000023` |
| 核心约束 | 对齐 DeepTutor-main 的 QuizViewer、Notebook 持久化、题型配置和键盘交互；不使用临时缓存或 fixture 替代真实状态 |

## 1. 本工单目标

本工单解决三个问题：

```text
1. Quiz 问答数据和用户答题状态只像存在缓存里，重新打开 App 后看不到或恢复不完整。
2. 问答卡片当前偏向用户主动输入 / short answer，未按 DeepTutor-main 以选择题为主。
3. Quiz 卡片输入框弹出键盘时，底部 Message DeepTutor Composer 仍显示，挤占答题区域。
```

目标：

```text
1. Quiz 卡片、题目数据、用户选择/输入、提交状态、解释/判定状态都能跨 App 重启恢复。
2. 题型策略对齐 Web：默认优先选择题，支持 concept、fill_in_blank，但不能默认全部变成 short answer。
3. Quiz 内部输入聚焦时隐藏底部 DeepTutor Composer，只保留当前答题输入和键盘。
4. 所有行为都通过消息事件、result summary、answer store 或服务端 notebook 等稳定数据源驱动。
```

## 2. 当前 iOS 代码事实

### 2.1 Quiz 答案状态存储

iOS 文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizAnswerStore.swift
```

当前实现：

```text
1. 使用 actor `DeepTutorQuizAnswerStore`。
2. 写入 Application Support 下 `DeepTutorQuiz/quiz-answer-state.json`。
3. 内存中有 `cache = Storage()`。
4. session key 为 `conversationID|assistantMessageID|turnID`。
5. 如果 turnID 缺失，使用 `local-only`。
```

代码事实：

```text
func sessionKey(conversationID: UUID, assistantMessageID: UUID, turnID: String?) -> String {
    let turn = turnID 非空 ? turnID : "local-only"
    return "\(conversationID)|\(assistantMessageID)|\(turn)"
}
```

问题判断：

```text
1. 文件级持久化已经存在，不是完全没有本地持久化。
2. 但持久化 key 依赖 assistantMessageID 和 turnID。
3. 如果 App 重开后卡片 block 没有恢复，答案状态也无处加载。
4. 如果 turnID 为空或重建时变化，会落入 `local-only` 或新 key，旧答案不可见。
5. 如果 assistantMessageID 在消息重建/重新生成后变化，也会导致旧答案不可见。
```

结论：

```text
当前问题不是“只有内存缓存”这么简单，而是“持久化 key、卡片 block 恢复、turnID 稳定性、消息恢复链路”没有形成和 Web 一致的稳定闭环。
```

### 2.2 Quiz 卡片加载状态

iOS 文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizCardView.swift
```

当前实现：

```text
.task(id: sessionTaskID) {
    await loadSessionIfNeeded()
}

sessionTaskID = conversationID|messageID|turnID|questions.count
```

风险：

```text
1. `didLoadSession` 只在 View 生命周期内阻止重复加载。
2. 如果 `messageID` 或 `turnID` 变化，sessionTaskID 变化，但旧数据 key 不一定能命中。
3. 如果卡片完成态丢失，`DeepTutorQuizCardView` 根本不会被创建，answer store 无法加载。
```

### 2.3 题型渲染

iOS 文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizAnswerInputView.swift
```

当前支持：

```text
choice -> 选项按钮
concept -> 对/错按钮
fillInBlank -> 单行输入
shortAnswer / written / coding -> 多行自由输入
```

截图现象：

```text
卡片显示 SHORT ANSWER，并展示自由输入框。
```

问题判断：

```text
iOS 渲染层支持选择题，但上游生成/解析出来的 questionType 偏向 shortAnswer。
因此“没有选择题”不是卡片组件完全不支持，而是题型生成策略和 Web 配置未对齐。
```

### 2.4 Composer 键盘避让

iOS 文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerCardView.swift
```

当前结构：

```text
VStack {
    content
    DeepTutorComposerView(...)
}
```

截图问题：

```text
Quiz 卡片里的输入框聚焦后，系统键盘弹出；
底部 `Message DeepTutor` Composer 仍然显示在键盘上方；
答题卡片被压缩，当前 Quiz 输入和主消息 Composer 同时争抢键盘上下文。
```

结论：

```text
Quiz 卡片内输入聚焦时，页面需要进入“卡片答题输入模式”，临时隐藏主 Composer。
```

## 3. DeepTutor-main Web 对标事实

### 3.1 Web 答题状态持久化

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/notebook-api.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/session-api.ts
```

Web 关键行为：

```text
1. QuizViewer 通过 `lookupNotebookEntry(sessionId, questionId, turnId)` 恢复已保存答题记录。
2. 用户提交单题后，通过 `upsertNotebookEntry` 写入 question notebook。
3. 全部题完成后，通过 `recordQuizResults(sessionId, answers, turnId)` 写入 quiz-results。
4. `turnId` 是必需隔离维度；没有 turnId 时 Web 明确避免写入共享 legacy namespace。
5. Web 会恢复 `user_answer`、`bookmarked`、`ai_judgment`、`followup_session_id`、图片答案等状态。
```

Web 代码注释明确：

```text
No turn identity -> no notebook reads.
Reporting requires a turn identity.
```

对齐结论：

```text
iOS 不能只保存本地 UI 状态。
至少要做到本地数据库/文件可恢复；如果要完全对齐 Web，需要接入项目已有后端/Notebook 或等价本地 Repository，且 key 必须包含 turnID。
```

### 3.2 Web 题型配置

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizConfigPanel.tsx
```

Web 配置：

```text
question_types: []
```

语义：

```text
1. 空列表表示 auto，由 planner 选择题型。
2. 用户可选择 choice、concept、fill_in_blank 等题型。
3. `buildQuizWSConfig` 会把 question_types 和 per_type_counts 发送给后端。
```

本项目 iOS 目标：

```text
1. 健康知识小问答默认应以 choice 为主。
2. 可混入 concept / fill_in_blank，但不能默认产出全 short answer。
3. 如果没有明确配置，iOS prompt / config / parser 需要倾向生成 `choice`。
```

### 3.3 Web 输入体验

Web QuizViewer 的输入属于 Quiz 卡片内部：

```text
1. choice/concept 用按钮，不弹键盘。
2. fill_in_blank/free text 才出现输入框。
3. 主聊天 Composer 不应与卡片输入形成同一层级的输入竞争。
```

iOS 对齐目标：

```text
Quiz 卡片内部输入聚焦时，底部 Message DeepTutor Composer 应隐藏或折叠。
```

## 4. 根因分析

### 4.1 App 重开后问答数据看不到

可能根因：

```text
1. Quiz block 自身没有完成态持久化/恢复，导致卡片不出现。
2. 题目数据只存在流式内存态，没有写入 message events/result summary 或 blocks。
3. 答案状态虽然写入 `quiz-answer-state.json`，但 key 依赖不稳定的 messageID/turnID。
4. turnID 缺失时使用 `local-only`，跨轮或重开后容易无法正确匹配。
5. 当前没有和 Web notebook API 等价的后端持久化。
```

优先判断：

```text
先修卡片/题目数据恢复，再修答案状态恢复。
如果卡片都恢复不了，答案 store 无法加载。
```

### 4.2 为什么变成主动输入题

可能根因：

```text
1. AI 输出 `question_type` 为 short_answer / shortAnswer。
2. iOS prompt 没有强制“默认以 choice 为主”。
3. iOS 没有把 Web 的 `question_types` 配置发送给模型/工具链。
4. Parser 对未知题型归一化时落到 shortAnswer。
```

对齐方向：

```text
默认健康知识小问答：choice >= 2/3。
若 3 道题，建议 2 道 choice + 1 道 concept 或 fill_in_blank。
只有用户明确要求开放问答时，才生成 shortAnswer / written。
```

### 4.3 Quiz 输入弹键盘时 Composer 仍显示

可能根因：

```text
1. DeepTutorChatPage 固定在底部渲染 DeepTutorComposerView。
2. 页面只跟踪主 Composer 的 `isComposerFocused`，没有跟踪 Quiz 内部输入焦点。
3. QuizAnswerInputView 的 TextField 没有向页面上报“卡片输入正在编辑”。
4. 键盘避让逻辑没有区分主消息输入和卡片内部输入。
```

对齐方向：

```text
引入 `activeInlineInput` 或 `isQuizInputFocused` 状态。
当 Quiz 内部 TextField 聚焦时，主 Composer 隐藏、折叠或 opacity=0 且不占位。
```

## 5. 修复方案

### 5.1 P0：Quiz 卡片和题目数据持久化恢复

要求：

```text
1. 完成态 assistant message 必须持久化 `.quiz` block 或足够重建 `.quiz` block 的 events/result summary。
2. App 重启后打开同一 conversation，message.blocks 必须包含 `.quiz`。
3. `DeepTutorQuizPayload.turnID` 必须稳定。
4. Debug snapshot 必须显示 quizBlockCount、quizQuestionCount、turnID、quizExtractionSource。
5. 若无法恢复 quiz block，必须显示 parse/recovery error，不允许静默只显示 intro。
```

涉及文件：

```text
DeepTutorMessageReducer.swift
DeepTutorQuizExtractor.swift
DeepTutorQuizContentParser.swift
DeepTutorLocalChatStore.swift
DeepTutorMessageBlock.swift
DeepTutorChatDebugExporter.swift
```

### 5.2 P0：答题状态持久化恢复

要求：

```text
1. 答题状态 key 必须稳定，至少包含 conversationID + turnID + questionID。
2. 不建议继续把 assistantMessageID 作为唯一关键维度；如果保留，需要保证消息重建后 ID 不变。
3. 对 `turnID == nil` 的卡片禁止写入长期共享状态，只能 local-only 并明确日志提示。
4. 提交答案后立即持久化 selectedKey / typedText / submitted / isCorrect / reviewCollapsed / aiJudgment。
5. App 重启后恢复当前题号、已提交状态、答案、解释展开状态。
6. 需要补充 answer store 的 load/save/round-trip 日志和失败日志。
```

当前 iOS 最小可落地：

```text
继续使用本地 `DeepTutorQuizAnswerStore`，但修正 key 稳定性和恢复链路。
```

完全对齐 Web 的目标：

```text
接入等价 Notebook/QuizResult Repository：
lookupNotebookEntry
upsertNotebookEntry
recordQuizResults
updateNotebookEntry
```

### 5.3 P0：题型策略以选择题为主

要求：

```text
1. 默认 Quiz 健康知识问答以 `choice` 为主。
2. 3 题默认建议：2 choice + 1 concept/fill_in_blank。
3. 不允许默认全 short_answer。
4. Prompt / config / parser / UI label 必须使用同一套题型枚举。
5. 如果 AI 返回 short_answer，但 options 足够，应归一化为 choice。
6. 如果 AI 返回 choice 但 options 为空，应触发 parse error 或结构修复，不降级为输入题。
```

涉及文件：

```text
DeepTutorPromptBuilder.swift
DeepTutorQuizContentParser.swift
DeepTutorQuizExtractor.swift
DeepTutorQuizModels.swift
DeepTutorQuizAnswerInputView.swift
```

### 5.4 P0：Quiz 输入聚焦时隐藏主 Composer

要求：

```text
1. Quiz 卡片内部 TextField / TextEditor 聚焦时，隐藏底部 `Message DeepTutor` Composer。
2. 选择题和判断题不需要弹键盘，因此不触发隐藏。
3. 卡片输入失焦或键盘收起后，Composer 恢复。
4. 隐藏时不应留下大块空白占位。
5. 不影响主 Composer 自己发送消息时的键盘行为。
```

建议状态：

```text
DeepTutorChatPage:
@State private var activeInlineInput: DeepTutorInlineInputKind?

DeepTutorQuizCardView:
onInlineInputFocusChanged(Bool)

DeepTutorComposerView:
当 activeInlineInput != nil 时不渲染或折叠高度。
```

涉及文件：

```text
DeepTutorChatPage.swift
DeepTutorMessageListView.swift
DeepTutorMessageRowModel.swift
DeepTutorAssistantBubble.swift
DeepTutorQuizCardView.swift
DeepTutorQuizAnswerInputView.swift
DeepTutorComposerView.swift
```

## 6. UI 对齐要求

### 6.1 选择题主体验

选择题应呈现：

```text
1. A/B/C/D 圆形或胶囊标识。
2. 整行可点击。
3. 选中态蓝色边框/浅蓝底。
4. 提交后正确项绿色，错误选择红色。
5. 未提交前“检查答案”按钮在未选择时 disabled。
```

### 6.2 输入题键盘体验

当 fill_in_blank / shortAnswer 聚焦：

```text
1. 当前输入框保持在键盘上方可见。
2. 底部 Message DeepTutor 主输入区隐藏。
3. 卡片底部检查答案按钮不能被键盘遮住。
4. 滚动容器自动滚到当前 Quiz 输入区域。
```

## 7. 日志要求

新增或补齐日志：

```text
deeptutor.quiz.answer.load.start
deeptutor.quiz.answer.load.done
deeptutor.quiz.answer.load.miss
deeptutor.quiz.answer.persist.start
deeptutor.quiz.answer.persist.done
deeptutor.quiz.answer.persist.failed
deeptutor.quiz.answer.key.resolved
deeptutor.quiz.answer.turn_missing_local_only
deeptutor.quiz.question_type.resolved
deeptutor.quiz.question_type.fallback
deeptutor.quiz.inline_input.focus_changed
deeptutor.composer.hidden_for_inline_input
deeptutor.composer.restored_after_inline_input
```

关键字段：

```text
conversationID
assistantMessageID
turnID
questionID
questionType
sessionKey
submitted
isCorrect
source
```

## 8. 验收标准

### 8.1 App 重启恢复

Given：

```text
用户完成一轮健康知识小问答，选择/输入答案并点击检查答案。
```

When：

```text
杀掉 App，重新打开同一 DeepTutor 会话。
```

Then：

```text
1. Quiz 卡片仍然显示。
2. 题目仍然显示。
3. 已答题目保留已提交状态。
4. 用户选择或输入内容仍然存在。
5. 正误状态和解释仍然存在。
6. 当前题号恢复到上次位置或合理默认。
7. 日志显示 answer load 命中，不是重新空白初始化。
```

### 8.2 选择题优先

Given：

```text
用户输入：健康知识小问答
能力：Quiz
题目数：3
```

Then：

```text
1. 至少 2 道题为 choice。
2. choice 题必须有 A/B/C/D 或至少 A/B/C 选项。
3. 不允许默认生成 3 道 SHORT ANSWER。
4. 用户不需要弹键盘即可完成主要题目。
```

### 8.3 键盘隐藏 Composer

Given：

```text
用户点击 Quiz 卡片内的填空题/短答题输入框。
```

Then：

```text
1. 系统键盘弹出。
2. 底部 Message DeepTutor Composer 隐藏。
3. Quiz 输入框和检查答案按钮可见。
4. 输入框失焦后 Composer 恢复。
5. 主 Composer 的发送/停止逻辑不受影响。
```

## 9. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| turnID 缺失 | 答案无法跨轮安全恢复 | 深入对齐 Web，缺 turnID 时只允许 local-only 且明确提示/日志 |
| assistantMessageID 变化 | 本地答案 key 失效 | key 收敛到 conversationID + turnID + questionID |
| Quiz block 未持久化 | App 重启后卡片本身消失 | 先修 `.quiz` block / result summary 恢复 |
| AI 默认 short_answer | 用户体验偏离 Web | prompt/config/parser 联合约束 choice 优先 |
| 隐藏 Composer 影响主输入 | 消息发送体验异常 | 区分主 Composer focus 与 inline Quiz input focus |

待确认：

```text
1. DeepTutorChat 当前是否已有可复用 Notebook/QuizResult 后端接口。
2. App 重启后卡片消失时，message.blocks 是否还有 `.quiz`。
3. 当前 turnID 是否稳定写入 result 或 quizQuestionEmitted。
4. 是否需要把答题状态从 JSON 文件迁移到已有本地数据库。
5. iOS 是否要暴露 Web 一样的 QuizConfigPanel，用于选择题型比例。
```

## 10. 结论

本次问题的准确结论：

```text
Quiz 当前不是单个 UI 小问题，而是三条链路没有完全对齐 DeepTutor-main：
1. 卡片和答题状态恢复链路不完整。
2. 题型生成策略没有以选择题为主。
3. 卡片内部输入和主 Composer 的键盘上下文没有隔离。
```

优先修复顺序：

```text
1. 先保证 Quiz block 和题目数据 App 重启后可恢复。
2. 再保证用户答案状态按 turnID/questionID 稳定持久化。
3. 然后调整题型策略，让默认健康小问答以 choice 为主。
4. 最后补齐 Quiz 输入聚焦时隐藏主 Composer 的交互。
```
