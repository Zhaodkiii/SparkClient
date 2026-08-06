# DEEPTUTORCHAT-000019 健康知识问答自定义消息卡片未接管与 Web 全面对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000019 |
| 工单类型 | P0 问答自定义消息卡片未接管 + Web 全面对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 用户截图 | `/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-98ecf74a-5fcf-4861-9aa1-be3dceeb9100.png`、`/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-8d5033d5-06e7-475a-8c74-b4637967847c.png` |
| 创建日期 | 2026-08-06 |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000012`、`DEEPTUTORCHAT-000013`、`DEEPTUTORCHAT-000018` |
| 场景约束 | 模型消费继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` 场景 |

## 1. 本工单目标

用户输入：

```text
健康知识给我来一些
```

当前现象：

```text
1. Web 能把健康知识问答渲染成自定义 Quick Check 卡片。
2. iOS 截图中没有稳定显示同等自定义消息卡片。
3. iOS 把结构化题目内容直接展示成正文/代码块，例如 `"question"`、`"question_type"`、`"options"`、`"correct_answer"`、`"explanation"` 等字段。
4. iOS 即使已有 Quiz 组件，也没有稳定完成“模型输出 -> 结构化事件 -> Quiz block -> 自定义卡片 -> 清洗正文”的闭环。
```

本工单目标：

```text
1. 解释为什么 Web 有自定义消息卡片，而 iOS 当前没有稳定展示。
2. 对比 Web 和 iOS 在工具使用、模型输出、事件处理、数据解析、Reducer、消息卡片 UI、刷新和持久化上的差距。
3. 为 iOS 问答能力制定全面对齐 DeepTutor-main 的落地方案。
4. 明确当前代码事实：iOS 已有部分 Quiz 组件和解析器，但链路仍未稳定接管真实 AI 输出。
5. 给出可验收的修复拆分，避免继续把 JSON 当正文展示。
```

本工单只写需求和技术方案，不修改 Swift 代码。

## 2. 截图问题结论

### 2.1 Web 截图表现

Web 展示为 DeepTutor-main 的自定义 Quick Check 卡片：

```text
正文说明
  -> Quick Check 卡片
    -> 顶部题目导航 3/3
    -> 题号 chips：1 红、2 绿、3 当前 primary
    -> 进度条
    -> Q3 / MEDIUM / fill_in_blank chips
    -> 收藏 / 分类 / 追问对话
    -> Markdown 题干
    -> 填空输入/答案状态
```

这说明 Web 已经把结构化问答内容从普通正文中分离出来，并交给 `QuizViewer` 渲染。

### 2.2 iOS 截图表现

iOS 展示为普通正文/代码块：

```text
以下是几个关于睡眠健康的小测验...

"question": "根据健康指南，大多数成年人每晚推荐睡眠时..."
"question_type": "choice",
"options": {
  "A": "5-6小时",
  "B": "7-9小时",
  ...
},
"correct_answer": "B",
"explanation": "..."
```

这说明 iOS 没有把模型输出识别为 Quick Check 结构化数据，或者识别发生得太晚/失败，导致 UI 先渲染了原始 JSON。

### 2.3 直接结论

```text
Web 有自定义消息卡片，是因为 Web 的消息渲染层会基于 capability + events/result metadata 分流到 QuizViewer。
iOS 当前没有稳定显示，是因为模型输出协议、事件映射、内容 parser、Reducer block 生成、正文清洗、流式刷新之间没有完全对齐。
```

注意：

```text
iOS 当前并非完全没有 Quiz UI 代码。当前代码中已经存在 `DeepTutorQuizCardView`、`DeepTutorQuizExtractor`、`DeepTutorQuizContentParser` 等文件。
实际问题是这些组件未稳定接管真实 AI 输出，仍让结构化 quiz JSON 进入了普通 Markdown 正文。
```

## 3. Web 为什么能显示自定义消息卡片

### 3.1 Web 消息分流链路

Web 关键文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-question-type.ts
```

Web 流程：

```text
AssistantMessage
  -> msg.capability === "deep_question"
  -> resultEvent 存在时 extractQuizQuestions(resultEvent.metadata)
  -> resultEvent 不存在时 extractStreamingQuizQuestions(msg.events)
  -> quizQuestions 有数据
  -> 渲染 AssistantResponse 作为前置说明正文
  -> 渲染 QuizViewer 自定义卡片
  -> 不再把每道题 JSON 当正文渲染
```

### 3.2 Web 流式题目事件

Web 支持一题一题地出现：

```text
event.type === "content"
event.metadata.call_kind === "quiz_question_emitted"
event.metadata.qa_pair
event.metadata.question_index
```

`extractStreamingQuizQuestions` 做了：

```text
1. 扫描 events。
2. 找到 `quiz_question_emitted`。
3. 读取 `qa_pair`。
4. normalize question_type。
5. 按 question_id / question_index 去重。
6. 按 question_index 排序。
7. 直接交给 QuizViewer 渲染。
```

### 3.3 Web final result 事件

完成后 Web 以 final result 为权威数据：

```text
result.metadata.summary.results[].qa_pair
```

`extractQuizQuestions` 做了：

```text
1. 从 result metadata 取 summary。
2. 从 summary.results 提取 qa_pair。
3. 解析 question_id、question、question_type、options、correct_answer、explanation、difficulty、concentration。
4. 返回 QuizQuestion[]。
```

### 3.4 Web Turn 隔离

Web 使用 `extractQuizTurnId(msg.events)`：

```text
1. 优先取 result.turn_id。
2. 否则取事件里的 turn_id。
3. QuizViewer 用 sessionId + turnId + question_id 隔离答题状态。
```

这个设计避免同一会话里多个 `q_1` 串状态。

### 3.5 Web UI 组件完整

Web `QuizViewer` 管理：

```text
1. 当前题 idx。
2. answers。
3. completedCount。
4. 题号 chips 正确/错误/当前态。
5. choice / concept / fill_in_blank / short_answer / written / coding。
6. Check Answer。
7. Correct / Incorrect。
8. Retry。
9. Reference Answer / AI Judgment。
10. Bookmark / Category / Follow-up Chat。
11. Notebook 持久化。
12. AI Judge。
```

## 4. iOS 当前代码事实

### 4.1 iOS 已有 Quiz UI 文件

当前 iOS 代码已经不再是最初的单文件 Fixture 状态，已存在：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizCardView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizHeaderView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizQuestionBodyView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizAnswerInputView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizReviewPanelView.swift
```

说明：

```text
iOS 现在已经有自定义卡片组件雏形，但截图说明真实对话链路没有稳定进入该组件。
```

### 4.2 iOS 已有 Quiz 数据相关文件

当前已存在：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizExtractor.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizContentParser.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizAnswerStore.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizGrader.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizJudgeUseCase.swift
```

说明：

```text
这批文件说明 DEEPTUTORCHAT-000013 的部分落地已开始，但本轮截图暴露出真实 AI 输出的解析兼容不足。
```

### 4.3 iOS 当前 Prompt 方式

当前 `DeepTutorPromptBuilder.swift` 对 deepQuestion 的要求是：

```text
1. 生成 1-3 道结构化题。
2. 简短 Markdown 前置说明。
3. 最后追加一个 fenced code block，tag 为 `quiz_json`。
4. fenced block 内必须是 {"results":[{"qa_pair":{...}}]}。
```

问题：

```text
1. 这是 iOS 自己补的“文本 JSON 协议”，不是 Web 的首选事件协议。
2. 模型可能没有严格输出 ```quiz_json fenced block。
3. 模型可能输出裸 JSON、半 JSON、带 `PLAN/FINISH`、或者把 qa_pair 片段直接写入正文。
4. 当前 parser 只识别严格的 ` ```quiz_json `，所以截图中的裸字段会漏解析。
```

### 4.4 iOS 当前 Parser 限制

当前 `DeepTutorQuizContentParser.swift`：

```text
locateQuizJSONBlock(in:)
  -> 只查找 opener = "```quiz_json"
  -> 只读取 fenced block 内 JSON
  -> validatedSummaryJSON 要求顶层存在 results
```

截图中的 iOS 内容像是：

```text
"question": ...
"question_type": ...
"options": ...
"correct_answer": ...
"explanation": ...
```

这类内容可能缺少：

```text
1. ```quiz_json fence。
2. 顶层 {"results":[...]} 包装。
3. 完整合法 JSON 起止。
4. final result summaryJSON。
```

因此 parser 不会生成 `.result(summaryJSON:)`，后续 `DeepTutorQuizExtractor` 就拿不到题目。

### 4.5 iOS 当前 Reducer 依赖 extractor

当前 `DeepTutorMessageReducer.swift` 对 deepQuestion 的逻辑：

```text
let extracted = DeepTutorQuizExtractor.extract(from: message)
if let quiz = extracted.payload, quiz.questions.isEmpty == false {
  append .quiz(quiz)
}
```

如果 parser/extractor 没产出 payload：

```text
1. 不会生成 quiz block。
2. 原始 message.content 继续作为 text block 渲染。
3. 用户看到 JSON 正文。
```

### 4.6 iOS 当前结构化事件映射不完整

`DeepTutorMessageCodec+Compatibility.swift` 已有 Web 兼容修复：

```text
content + metadata.call_kind=quiz_question_emitted
  -> quizQuestionEmitted
```

但需要核实真实 AI Runtime 是否会产生这种事件。

当前 `DeepTutorAIRuntimeEventMapper.swift` 的 result metadata 主要包含：

```text
model
finishReason
promptTokens
completionTokens
toolName
source=ai-runtime
```

问题：

```text
1. 如果 AI Runtime 没有传递 Web 风格 `quiz_question_emitted` metadata，iOS 只能依赖文本 parser。
2. 如果文本 parser 只识别严格 fenced block，真实输出稍有偏差就失败。
3. Web 的自定义卡片依赖的是后端/事件层结构化输出，而不是让 UI 从普通 Markdown 猜 JSON。
```

## 5. 为什么 Web 有卡片而 iOS 没有的根因

### 5.1 根因一：协议层不一致

Web：

```text
后端 QuestionPipeline 发出结构化事件：
content event + metadata.call_kind=quiz_question_emitted + qa_pair
```

iOS：

```text
当前主要依赖模型按 prompt 输出 ```quiz_json 文本块。
```

风险：

```text
文本协议不稳定，模型容易把 JSON 当正文、漏 fence、漏 results 包装、加入解释文字。
```

### 5.2 根因二：parser 太严格

iOS 只识别：

```text
```quiz_json
{"results":[...]}
```
```

但真实截图显示可能是：

```text
裸 JSON 字段
qa_pair 片段
非 fenced block
普通代码块
带中文说明的伪 JSON
```

结果：

```text
parser 找不到结构化块 -> quiz block 不生成 -> JSON 作为正文显示。
```

### 5.3 根因三：流式期间没有“结构化内容隔离”

即使最终 parser 能解析，流式中也可能先把 JSON 片段显示出来：

```text
AI partial content
  -> state.messages
  -> text block
  -> UI 渲染
  -> 用户看到 JSON
  -> final 阶段 parser 才尝试清洗
```

Web 则是：

```text
quiz_question_emitted event 到达
  -> QuizViewer 立即渲染卡片
  -> 题目结构不作为正文显示
```

### 5.4 根因四：模型输出与 UI 消费缺少强契约

iOS Prompt 要求 JSON，但 UI 消费需要的是：

```text
DeepTutorQuizPayload / DeepTutorQuizQuestion
```

中间缺少强约束：

```text
1. AI Runtime structured output。
2. quiz tool / function schema。
3. 后端同源 QuestionPipeline。
4. 失败时的 parser fallback。
```

### 5.5 根因五：工具策略与 Web 问答管线不一致

Web 健康知识问答会出现：

```text
联网搜索
健康科普小知识
中国居民膳食指南 2022
世界卫生组织运动/睡眠建议
```

iOS deepQuestion 当前需要核实：

```text
1. 是否允许 web_search / knowledge 工具。
2. 是否使用与 Web 相同的 QuestionPipeline 语义。
3. 是否只是通用 chat 模型直接生成文本 JSON。
```

如果工具策略不一致：

```text
1. 数据来源不一致。
2. 题目质量不一致。
3. trace 展示不一致。
4. 卡片生成时机不一致。
```

## 6. 全面对齐目标架构

### 6.1 目标总链路

iOS 应对齐为：

```text
用户选择 Quiz capability
  -> DeepTutorPromptBuilder / ToolPolicyResolver 构造本轮策略
  -> AI Runtime 使用通用 .chat 场景消费项目已有模型
  -> 模型/工具输出结构化 quiz event 或 result summary
  -> DeepTutorAIRuntimeEventMapper 保留 metadata/qa_pair/turn_id
  -> DeepTutorQuizExtractor 生成 DeepTutorQuizPayload
  -> DeepTutorMessageReducer 生成 .quiz block
  -> Text block 只保留前置说明，不包含题目 JSON
  -> DeepTutorAssistantBubble 分流到 DeepTutorQuizCardView
  -> DeepTutorQuizAnswerStore 持久化答题状态
```

### 6.2 优先策略：事件协议优先，文本 JSON 兜底

目标优先级：

```text
P0 首选：结构化事件
  content event metadata.call_kind=quiz_question_emitted
  result metadata.summary.results

P0 兜底：文本 JSON parser
  ```quiz_json fenced block
  普通 ```json fenced block
  裸 {"results":[...]} JSON
  裸 qa_pair 数组/对象

禁止：
  parser 失败后仍把明显 quiz JSON 全量展示给用户。
```

### 6.3 自定义卡片接管规则

当满足任一条件：

```text
1. msg.capability == .deepQuestion。
2. content 中出现 quiz_json。
3. content 中出现 qa_pair / question_type / correct_answer 的结构化模式。
4. events 中出现 quizQuestionEmitted。
5. result summaryJSON 中有 results。
```

应该进入问答卡片候选流程：

```text
1. 尝试解析题目。
2. 成功：渲染 Quick Check 卡片，并从正文剥离结构化题目内容。
3. 失败：不渲染假卡片，但也不要完整暴露结构化 JSON；显示简短错误/普通说明，并记录 parser failure。
```

### 6.4 正文清洗规则

正文只允许保留：

```text
1. 前置说明，例如“现在为你出 3 道题。”
2. 题目前的素材说明。
3. 非结构化自然语言。
```

正文必须剥离：

```text
1. quiz_json fenced block。
2. 普通 json fenced block 内的 quiz results。
3. 裸 qa_pair/results JSON。
4. 重复的题干、options、correct_answer、explanation 结构。
```

如果剥离后正文为空：

```text
只显示 Quick Check 卡片，不显示空 AssistantResponse。
```

## 7. Web 与 iOS 对齐矩阵

| 对齐项 | Web 当前 | iOS 当前 | iOS 目标 |
| --- | --- | --- | --- |
| 能力入口 | `deep_question` capability | Quiz chip / `deepQuestion` | 保持 capability 对齐 |
| 模型场景 | DeepTutor 后端管线 | 项目 AIConfigCenter `.chat` | 继续 `.chat`，不新增 `.deepTutor` |
| 工具策略 | QuestionPipeline 可联网/检索 | 需核实 minimalAlwaysOnTools | 对齐 DEEPTUTORCHAT-000007 的本轮工具组合策略 |
| 结构化输出 | `quiz_question_emitted` / result summary | 主要依赖 `quiz_json` 文本 | 事件优先，文本兜底 |
| 题目解析 | `extractStreamingQuizQuestions` / `extractQuizQuestions` | `DeepTutorQuizExtractor` + strict parser | 兼容 Web 事件 + 宽容 parser |
| 正文分流 | 前置说明 + QuizViewer | JSON 可能进入正文 | 结构化内容从 text block 剥离 |
| 自定义卡片 | `QuizViewer` | `DeepTutorQuizCardView` 已有但未稳定接管 | 真实数据稳定渲染 |
| 答题状态 | React state + notebook | 本地 `DeepTutorQuizAnswerStore` | 本地持久化，turn/message 隔离 |
| 追问 | QuizFollowupContext | onFollowUp 雏形 | 普通 `.chat` follow-up |
| AI 评判 | `startQuizJudge` | `DeepTutorQuizJudgeUseCase` | 使用已有模型系统，UI 对齐 |
| Debug | Web 可通过 events/result 判断 | iOS 需要更多 parser/卡片日志 | 增加全链路日志 |

## 8. 关键代码位置

### 8.1 Web 参考代码

| 职责 | 文件 |
| --- | --- |
| 消息分流到 QuizViewer | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx` |
| Quick Check 卡片完整 UI | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx` |
| Quiz 数据提取 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts` |
| 题型归一化 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-question-type.ts` |
| 追问上下文 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/QuizFollowupContext.tsx` |
| Trace 中 quiz_question_emitted 识别 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx` |

### 8.2 iOS 当前代码

| 职责 | 文件 |
| --- | --- |
| 助手消息分流 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift` |
| Quick Check 容器 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizCardView.swift` |
| Quiz Header | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizHeaderView.swift` |
| 题干和 Meta | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizQuestionBodyView.swift` |
| 答题输入 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizAnswerInputView.swift` |
| 参考答案/AI 判断 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizReviewPanelView.swift` |
| Quiz 提取 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizExtractor.swift` |
| 文本 JSON parser | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizContentParser.swift` |
| Reducer 生成 block | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| AI 事件映射 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeEventMapper.swift` |
| Web content quiz 兼容 repair | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec+Compatibility.swift` |
| Prompt | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPromptBuilder.swift` |
| 工具策略 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift` |
| 发送/最终化 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |

## 9. 修复方案

### 9.1 P0：先修 parser，让截图里的内容不再直接展示

`DeepTutorQuizContentParser` 需要支持：

```text
1. ```quiz_json fenced block。
2. ```json fenced block，且内容符合 quiz shape。
3. 裸 JSON：{"results":[...]}。
4. 裸数组：[{"qa_pair":...}]。
5. 散落 qa_pair 片段的恢复。
6. 带 PLAN/FINISH 前缀后的 JSON。
7. 只出现 `"question"` / `"question_type"` / `"correct_answer"` 片段时的失败降级。
```

成功时：

```text
1. 生成 `.result(metadata: ["source": "quiz_content_parser"], summaryJSON: ...)`。
2. content 替换为 strippedContent。
3. strippedContent 不包含 question/options/correct_answer/explanation JSON。
4. Reducer 生成 `.quiz` block。
```

失败时：

```text
1. 记录 `deeptutor.quiz.content_parser.failed`。
2. 如果检测到明显 quiz JSON，不应完整展示给用户。
3. 可展示：“问答结构解析失败，请重试生成题目。”并保留 debug JSON 到调试面板。
```

### 9.2 P0：流式期间隔离 quiz JSON

目标：

```text
1. 当 capability == deepQuestion，检测到内容进入 quiz_json 或 JSON-like quiz 段后，临时不把该段追加到可见 text block。
2. 可见正文只显示前置说明。
3. 结构化段进入 pending parser buffer。
4. 当 buffer 可解析时立即生成 quiz block。
```

避免：

```text
用户在流式过程中看到完整 JSON 字段滚动出来。
```

### 9.3 P0：接入 Web 风格 quiz_question_emitted 事件

需要确认 AI Runtime 是否能输出 metadata：

```text
call_kind=quiz_question_emitted
qa_pair
question_index
turn_id
```

如果可以：

```text
1. DeepTutorAIRuntimeEventMapper 必须保留 metadata。
2. DeepTutorStreamEvent 支持 Web content event 直接映射为 quizQuestionEmitted。
3. DeepTutorQuizExtractor 优先使用 streaming questions。
```

如果当前项目 AI Runtime 不支持：

```text
1. 将本阶段定为文本 JSON 兼容方案。
2. 在工单风险中标明：与 Web 的实时逐题出现能力仍未完全一致。
3. 后续需要服务端/AI Runtime 支持结构化事件。
```

### 9.4 P0：final result 与 streaming 题目合并

规则：

```text
1. streaming 题目先出现，卡片可先渲染。
2. final result 到达后作为权威版本。
3. final result 只补全 explanation / difficulty / concentration / correct_answer。
4. 不得清空用户已经选择/提交的答案。
5. 不得让 currentIndex 回到 0。
```

### 9.5 P0：正文和卡片互斥渲染

在 `DeepTutorMessageReducer` / `DeepTutorAssistantBubble` 层保证：

```text
1. `.quiz` block 存在时，text block 只显示前置说明。
2. quiz JSON 不能再作为 text block。
3. 如果 text block 里仍包含 `"question_type"`、`"correct_answer"`，记录 `quiz.render_source_leak_detected`。
```

### 9.6 P0：工具策略对齐 Web

健康知识问答需要权威来源，工具策略应支持：

```text
1. 对健康知识题，根据用户问题识别是否需要 web_search / knowledge 工具。
2. 不要把所有工具都丢给模型。
3. 使用 DEEPTUTORCHAT-000007 的本轮工具组合策略层。
4. `deepQuestion` 不应固定只有 minimalAlwaysOnTools。
5. debug snapshot 显示本轮 `resolvedAllowedToolsForCurrentTurn` 和 `actualToolCalls`。
```

### 9.7 P1：UI 完整度继续对齐 Web

iOS 已有卡片后，还需按 Web 补齐：

```text
1. 卡片宽度、圆角、边框、背景、进度条。
2. 题号 chips 状态：current/correct/incorrect/unanswered。
3. choice/concept/fill_in_blank 的交互状态。
4. Bookmark / Category / Follow-up Chat 的可用状态。
5. AI Judge 的 loading / result / retry。
6. 参考答案/AI Judgment tab。
7. Markdown 题干、选项、解析保真。
```

## 10. 数据模型要求

### 10.1 Quiz Question

iOS 必须与 Web 字段对齐：

```text
question_id -> id
question -> question
question_type -> questionType
options -> [DeepTutorQuizOption(key,text)]
correct_answer -> correctAnswer
explanation -> explanation
difficulty -> difficulty
concentration -> concentration
knowledge_context -> knowledgeContext
```

### 10.2 Quiz Payload

```text
title
turnID
questions
source: streaming | result | contentParser | legacy
```

`source` 必须进入 debug 信息，方便判断为什么卡片显示或未显示。

### 10.3 Answer State

答题状态 key：

```text
conversationID + assistantMessageID + turnID + questionID
```

要求：

```text
1. 不因 reload 丢失。
2. 不因 final result 替换而丢失。
3. 不写入 AI 原始 content。
4. 本地存储可检查。
```

## 11. 日志需求

### 11.1 Parser 日志

新增或补齐：

```text
deeptutor.quiz.content_parser.start
deeptutor.quiz.content_parser.detected
deeptutor.quiz.content_parser.stripped
deeptutor.quiz.content_parser.failed
deeptutor.quiz.content_parser.raw_suppressed
```

字段：

```text
conversation
assistant
capability
pattern
contentLength
strippedLength
questionCount
failureReason
rawPreview
```

### 11.2 Extractor 日志

新增或补齐：

```text
deeptutor.quiz.extract.start
deeptutor.quiz.extract.done
deeptutor.quiz.extract.failed
deeptutor.quiz.extract.source_selected
deeptutor.quiz.extract.final_merge
```

字段：

```text
conversation
assistant
turnID
source
questionCount
questionIDs
questionTypes
hasOptions
hasExplanation
```

### 11.3 渲染泄漏日志

新增：

```text
deeptutor.quiz.render_source_leak_detected
deeptutor.quiz.block.missing
deeptutor.quiz.block.created
deeptutor.quiz.raw_json.hidden
```

字段：

```text
conversation
assistant
contentContainsQuestionType
contentContainsCorrectAnswer
quizBlockCount
textBlockCount
reason
```

### 11.4 工具策略日志

新增或补齐：

```text
deeptutor.quiz.tool_policy.resolved
deeptutor.quiz.tool_policy.web_search_enabled
deeptutor.quiz.tool_policy.schema_names
deeptutor.quiz.tool_policy.actual_calls
```

字段：

```text
conversation
assistant
userText
policyReason
allowedTools
actualTools
model
scenario
```

## 12. 验收用例

### 12.1 健康知识题不展示 JSON

步骤：

```text
1. 进入 iOS DeepTutorChat。
2. 选择 Quiz 能力。
3. 输入：健康知识给我来一些。
4. 等待 AI 完成。
```

期望：

```text
1. 不显示 `"question"`、`"question_type"`、`"options"`、`"correct_answer"`、`"qa_pair"` 原始字段。
2. 显示自然语言前置说明。
3. 显示 Quick Check 自定义卡片。
4. 卡片内至少 1 道真实题。
5. 如果模型生成 3 道题，顶部显示 0/3 或当前完成数/3。
```

### 12.2 Web 风格 Quick Check 卡片

期望：

```text
1. 顶部有上一题/下一题。
2. 有题号 chips。
3. 有 2px primary 进度条。
4. 有 Q1/Q2/Q3、difficulty、question_type chips。
5. choice 显示 A/B/C/D 选项。
6. concept 显示 对/错。
7. fill_in_blank 显示输入框。
8. 检查答案 disabled/enabled 状态正确。
9. 提交后显示正确/错误、重试、参考答案/解析。
```

### 12.3 Parser 兼容裸 JSON

输入/模拟：

```text
模型没有输出 ```quiz_json fence，只输出裸 {"results":[...]} 或 qa_pair 片段。
```

期望：

```text
1. parser 能识别并生成 quiz block。
2. 如果无法完整解析，原始 JSON 不直接展示给用户。
3. 调试日志有明确失败原因。
```

### 12.4 流式期间不泄漏结构化 JSON

期望：

```text
1. AI 还在 streaming 时，不滚动展示 quiz JSON 字段。
2. 可见正文只显示前置说明。
3. 题目解析成功后卡片逐步出现。
4. final 完成后 UI 不跳变成 JSON 正文。
```

### 12.5 工具使用对齐

期望：

```text
1. 健康知识问答需要权威来源时，iOS 能按策略启用搜索/知识工具。
2. 工具不是全量丢给模型，而是按本轮问题选择。
3. trace 展示与 Web 一致：思考、联网搜索/工具调用、题目生成。
4. debug snapshot 可看到 allowedTools 和 actualToolCalls。
```

### 12.6 刷新和持久化

期望：

```text
1. 退出会话再进入，Quick Check 仍是卡片，不退回 JSON 正文。
2. 已答题状态不丢失。
3. final result merge 不清空用户答案。
4. database_change 不触发卡片回退。
```

## 13. 实施拆分

### P0-1：诊断当前 iOS 为什么未生成 quiz block

检查：

```text
1. 本轮 message.capability 是否为 `.deepQuestion`。
2. message.content 是否包含 ```quiz_json。
3. message.content 是否为裸 JSON / qa_pair。
4. DeepTutorQuizContentParser 是否 foundBlock。
5. DeepTutorQuizExtractor 是否 questionCount > 0。
6. DeepTutorMessageReducer 是否 append .quiz。
7. DeepTutorAssistantBubble 是否收到 .quiz block。
```

### P0-2：宽容 parser 和 raw JSON 隐藏

实现目标：

```text
1. 支持 fenced quiz_json。
2. 支持 fenced json。
3. 支持裸 results JSON。
4. 支持 qa_pair 片段恢复。
5. parser 失败时隐藏明显结构化 JSON。
```

### P0-3：事件协议对齐

实现目标：

```text
1. AI Runtime metadata 不丢失。
2. quiz_question_emitted 能进入 DeepTutorStreamEvent.quizQuestionEmitted。
3. result summary 能进入 summaryJSON。
4. turnID 能进入 payload。
```

### P0-4：正文清洗和 block 分流

实现目标：

```text
1. quiz block 成功后移除 JSON 正文。
2. text block 保留前置说明。
3. UI 不重复显示题目。
4. debug 记录 quizBlockCount / textBlockCount。
```

### P0-5：工具策略对齐

实现目标：

```text
1. deepQuestion 根据问题选择搜索/知识工具。
2. 健康知识题能拿到权威来源。
3. 不使用全工具列表。
4. 继续使用 `.chat` 模型场景。
```

### P1：UI 与交互补齐

实现目标：

```text
1. 和 Web Quick Check 视觉细节一致。
2. Bookmark / Category / Follow-up Chat 状态清晰。
3. AI Judge 完整接入。
4. 问题银行/Notebook 后续对齐。
```

## 14. 风险与注意事项

### 14.1 不要把问题归因成“iOS 没有组件”

当前 iOS 已有 `DeepTutorQuizCardView` 等组件。真实问题是：

```text
真实 AI 输出没有被稳定转换为 quiz block。
```

### 14.2 不要只加 UI 样式

如果 parser/reducer 不修，UI 再像 Web 也不会出现。

### 14.3 不要依赖模型严格遵守 fenced block

模型输出格式不稳定。必须使用结构化事件优先，文本 JSON 宽容兜底。

### 14.4 不要把 JSON 暴露给用户

明显结构化数据属于内部协议，不应该作为最终回答正文展示。

### 14.5 不要新增 `.deepTutor` 场景

继续使用项目已有大模型系统和通用 `.chat` 场景，只在 capability / prompt / tool policy / output parser 上区分问答能力。

## 15. 最终验收标准

实现完成后必须满足：

```text
1. iOS 输入“健康知识给我来一些”后，显示 Web 风格 Quick Check 自定义消息卡片。
2. iOS 不再把 question/question_type/options/correct_answer/explanation JSON 展示给用户。
3. iOS 的题目来自真实 AI 输出，不是 Fixture。
4. iOS 支持 streaming quiz question 或 final result summary 两种来源。
5. iOS parser 支持 fenced quiz_json、fenced json、裸 results JSON、qa_pair 兜底。
6. iOS 正文只保留前置说明，题目进入 `.quiz` block。
7. iOS 工具使用策略与 Web 的本轮工具组合策略一致。
8. iOS 数据模型、模型消费、事件处理、Reducer、UI、刷新、本地持久化形成闭环。
9. iOS 答题交互、参考答案、重试、AI 评判与 Web 行为一致或有明确分阶段说明。
10. 调试日志能明确回答：本轮为什么显示卡片，或为什么没有显示卡片。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
