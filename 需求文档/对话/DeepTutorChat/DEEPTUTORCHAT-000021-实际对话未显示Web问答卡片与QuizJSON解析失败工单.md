# DEEPTUTORCHAT-000021 实际对话未显示 Web 问答卡片与 QuizJSON 解析失败工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000021 |
| 工单类型 | P0 问答卡片数据链路修复 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 用户发送“健康知识问答”后，iOS 只展示引导文本和 trace，没有展示 Web 对应 Quick Check 问答卡片 |
| 关联工单 | `DEEPTUTORCHAT-000013`、`DEEPTUTORCHAT-000019`、`DEEPTUTORCHAT-000020` |
| 核心约束 | 不要通过硬编码 fixture 或自创题目补效果；必须接通真实结构化题目数据到 iOS 卡片 |

## 1. 本工单目标

本工单解决的问题：

```text
对比实际对话消息，iOS 没有看到对应的 Web 问答卡片。
需要找出问题并创建新的问题工单。
```

目标：

```text
1. 基于本次真实日志确认 iOS 没有展示 Quick Check 卡片的直接原因。
2. 对比 DeepTutor-main Web 的 QuizViewer 触发条件和数据来源。
3. 明确 iOS 当前不是单纯 UI 未对齐，而是结构化 quiz 数据没有成功进入消息 block。
4. 给出修复方案：结构化输出、解析容错、事件归约、卡片渲染、日志验收全链路补齐。
5. 明确禁止通过本地 fixture、关键词自创、假卡片方式绕过真实数据链路。
```

## 2. 本次实际对话问题证据

### 2.1 用户操作

实际对话：

```text
用户输入：健康知识问答
当前 capability：deep_question
模型：doubao-seed-evolving
AI 场景：chat
```

日志证据：

```text
deeptutor.capability.effective conversation=03EB3ED8 selected=deep_question effective=deep_question
发送 DeepTutor 对话开始，conversation=03EB3ED8, capability=deep_question, userContent=健康知识问答
deeptutor.capability.snapshot conversation=03EB3ED8 requestSnapshot=deep_question message=deep_question
```

结论：

```text
本轮确实进入了 deep_question 能力，不是 capability 未选中导致的卡片缺失。
```

### 2.2 最终调试快照

调试快照显示：

```text
phase=ready
isStreaming=false
messageCount=2
blockKinds=envelope=2,text=2,trace=1
askUserBlockCount=0
eventTypes=contentDelta=1,reasoningDelta=1,result=1
activeCapability=deep_question
latestAllowedTools=ask_user_question,read_web_page,search_online
```

关键缺失：

```text
blockKinds 没有 quiz
quizBlockCount 没有出现有效值
eventTypes 没有 quiz_question_emitted
result event metadata 没有 summary 或 summary_json
```

结论：

```text
iOS 消息最终只归约出了 envelope、trace、text，没有归约出 quiz block。
因此 DeepTutorQuizCardView 没有被挂载，页面自然看不到 Web 对应卡片。
```

### 2.3 模型返回内容事实

本次 assistant 的 `contentDelta` 包含：

```text
下面是 3 道健康知识小测验，帮你快速检查日常健康常识。

```quiz_json

  "results":

      "qa_pair":
        "question_id": "q_1",
        "question": "一般情况下，健康成年人每天适宜的饮水量大约是多少？",
        "question_type": "choice",
        "options":
          "A": "500 毫升以下",
          "B": "1500—1700 毫升",
          "C": "3000—4000 毫升",
          "D": "完全不渴就不用喝"
        },
        "correct_answer": "B",
        ...
```

该内容不是合法 JSON：

```text
1. fenced block 内缺少最外层 `{`。
2. `"results"` 后缺少数组 `[]`。
3. 每个 `"qa_pair"` 缺少对象包裹 `{}`。
4. `"options"` 缺少对象包裹 `{}`。
5. 第 3 题 `"options":` 后直接进入 `"correct_answer"`，字段结构残缺。
6. 虽然文本看起来像 quiz_json，但不能被 JSONSerialization 解析。
```

结论：

```text
模型没有稳定输出符合 prompt 要求的合法 quiz_json。
iOS 当前解析器在发现 quiz_json 后隐藏了原始结构块，但解析失败，没有生成 summaryJSON。
最终 UI 只剩引导句：“下面是3道健康知识小测验，帮你快速检查日常健康常识。”
```

### 2.4 反复失败日志

流式过程中大量出现：

```text
deeptutor.quiz.extract.failed conversation=03EB3ED8 assistant=FB85E1BE turnID=- reason=no_quiz_data durationMs=0.000
deeptutor.stream.partial.mapped ... answerLen=0 reasoningLen=... events=reasoning(...) blocks=envelope=1,trace=1
```

结论：

```text
DeepTutorQuizExtractor 在每次 partial 映射时都会尝试提取 quiz 数据。
由于没有 result.summaryJSON，也没有 quiz_question_emitted，持续输出 no_quiz_data。
这既是问题证据，也是日志噪声，需要在修复中节流或按状态记录一次。
```

## 3. DeepTutor-main Web 对标事实

### 3.1 Web 消息分支入口

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

`AssistantMessage` 中的问答卡片分支：

```text
if msg.capability !== "deep_question" return null
if resultEvent exists -> extractQuizQuestions(resultEvent.metadata)
else -> extractStreamingQuizQuestions(msg.events)
quizQuestions && quizQuestions.length > 0 -> render QuizViewer
```

UI 分支：

```text
AssistantActivity
AssistantResponse for quiz preface
QuizViewer
```

结论：

```text
Web 不是因为 capability 是 deep_question 就强行画卡片。
Web 必须拿到 quizQuestions，才会进入 QuizViewer。
```

### 3.2 Web 的结构化题目来源

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts
```

Web 支持两类来源：

```text
1. 流式题目事件：
   event.type == "content"
   event.metadata.call_kind == "quiz_question_emitted"
   event.metadata.qa_pair 是结构化题目
   event.metadata.question_index 用于排序

2. 最终 result：
   result.metadata.summary.results[]
   results[].qa_pair 是结构化题目
```

Web 注释明确：

```text
QuestionPipeline 会逐题发出 quiz_question_emitted content events。
QuizViewer 可以在题目生成时立即渲染卡片，不必等最终 result。
最终 result 是 settled/persisted 路径的权威数据。
```

结论：

```text
DeepTutor-main 的关键不是“解析模型普通文本里的伪 JSON”，而是运行时/后端问答流水线会提供结构化事件或结构化 result。
iOS 当前走的是普通 AI runtime contentDelta，缺少 Web 的 QuestionPipeline 结构化事件语义。
```

### 3.3 Web QuizViewer 组件职责

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx
```

组件职责：

```text
1. 接收 questions、sessionId、turnId、language。
2. 管理当前题 idx。
3. 管理 answers、judgments、reviewCollapsed。
4. 按 turnId 读写 notebook entry，避免不同轮 q_1/q_2 答案串用。
5. 支持上一题、下一题、题号 chip、进度条、答案检查、收藏、追问对话。
```

对齐要求：

```text
iOS DeepTutorQuizCardView 只能消费真实 questions payload。
如果 payload 没有进入 message.blocks，则再完备的 SwiftUI 卡片也不会出现。
```

## 4. iOS 当前链路事实

### 4.1 iOS 卡片挂载点

iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
```

当前渲染分支：

```text
case .quiz(let payload):
    DeepTutorQuizCardView(...)
```

结论：

```text
渲染入口存在。
没有展示卡片的直接原因是 message.blocks 中没有 `.quiz`。
```

### 4.2 iOS block 生成入口

iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
```

当前逻辑：

```text
case .deepQuestion:
    let extracted = DeepTutorQuizExtractor.extract(from: message)
    if let quiz = extracted.payload, quiz.questions.isEmpty == false {
        append .quiz block
    } else if DeepTutorQuizContentParser.looksLikeQuizJSON(message.content) {
        log quizBlockMissing structured_content_unparsed
    }
```

结论：

```text
Reducer 已经有 `.quiz` 插入逻辑。
问题在 `DeepTutorQuizExtractor.extract(from:)` 没有拿到 payload。
```

### 4.3 iOS quiz 提取器

iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizExtractor.swift
```

当前提取顺序：

```text
1. extractFromResult(events)
   读取 result.summaryJSON 或 metadata["summary_json"]

2. extractFromStreaming(events)
   读取 .quizQuestionEmitted

3. 都没有则记录 no_quiz_data
```

本次事件事实：

```text
eventTypes=contentDelta=1,reasoningDelta=1,result=1
result.metadata={
  model=doubao-seed-evolving,
  finishReason=stop,
  source=ai-runtime
}
```

结论：

```text
result 没有 summaryJSON。
metadata 没有 summary_json。
events 没有 quizQuestionEmitted。
所以 Extractor 必然返回 no_quiz_data。
```

### 4.4 iOS quiz 内容解析器

iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizContentParser.swift
```

当前能力：

```text
1. 识别 ```quiz_json fenced block。
2. 识别 ```json fenced block。
3. 识别 bare results object。
4. 识别 bare results array。
5. 识别 bare qa_pair object。
6. 校验合法 JSON 后生成 summaryJSON。
7. 解析失败时隐藏结构化源码，只保留 intro 或解析失败提示。
```

本次失败原因：

```text
当前模型输出不是“合法 JSON 的轻微变体”，而是缺少对象和数组结构的残缺文本。
`validatedSummaryJSON(from:)` 依赖 JSONSerialization。
因此它无法从这段残缺 `quiz_json` 生成 summaryJSON。
```

结论：

```text
ContentParser 的隐藏逻辑生效了，解析逻辑没有成功。
这解释了为什么页面没有 JSON 泄漏，但也没有 Web 卡片。
```

## 5. 根因归纳

### 5.1 直接根因

```text
DeepTutorQuizCardView 依赖 `.quiz` block。
`.quiz` block 依赖 `DeepTutorQuizExtractor` 提取到 `DeepTutorQuizPayload`。
本次真实事件没有 Web 标准的 `quiz_question_emitted`，也没有 result summaryJSON。
模型普通文本中的 quiz_json 又是非法 JSON。
所以 iOS 没有任何可用的结构化题目数据，最终无法生成 `.quiz` block。
```

### 5.2 架构根因

```text
iOS 当前用 prompt 要求模型在普通文本里输出 quiz_json。
Web DeepTutor-main 的目标链路是 QuestionPipeline 产出结构化事件或 result summary。
两者不是同一个交付契约。
```

偏差：

```text
1. iOS 把结构化问答数据寄托在模型遵守文本格式上。
2. Web 把问答数据作为事件 metadata/result summary 消费。
3. iOS 缺少“模型输出不合法时”的结构化重试、修复或失败卡片。
4. iOS 的日志在流式 partial 阶段重复打印 no_quiz_data，降低排查效率。
5. iOS UI 层无法区分“没有题目”“题目解析失败”“等待题目事件中”。
```

### 5.3 当前不应做的错误修复

禁止方案：

```text
1. 不要在 iOS 里硬编码健康知识题目。
2. 不要用 Fixture 卡片伪装成真实 AI 题目。
3. 不要因为命中“健康知识问答”关键词就自创题目。
4. 不要只改 DeepTutorQuizCardView 样式来解决卡片缺失。
5. 不要把非法 JSON 原样展示给用户。
6. 不要在解析失败时静默吞掉，让用户以为 AI 只回答了一句话。
```

## 6. 目标对齐方案

### 6.1 P0 方案一：对齐 Web QuestionPipeline 结构化事件

目标：

```text
让 iOS 接收到与 Web 同语义的结构化题目事件。
```

要求：

```text
1. deep_question 能力最终应产生 `quiz_question_emitted` 等价事件。
2. 每道题的 qa_pair 必须在 metadata 或等价 payload 中独立出现。
3. 每个事件必须带 question_index。
4. 每个事件必须带 turn_id。
5. 最终 result 必须携带 summary.results[]。
6. iOS `DeepTutorStreamEvent` 需要保持与 Web 事件字段语义一致。
```

iOS 落地点：

```text
DeepTutorStreamEvent
DeepTutorChatViewModel stream mapping
DeepTutorQuizExtractor.extractFromStreaming
DeepTutorQuizExtractor.extractFromResult
DeepTutorMessageReducer.blocks(for:)
DeepTutorQuizCardView
```

验收：

```text
eventTypes 包含 quizQuestionEmitted 或 result.summaryJSON。
blockKinds 包含 quiz。
quizBlockCount=1。
questionCount=3。
页面出现 Web 对应 Quick Check 卡片。
```

### 6.2 P0 方案二：最终 result summaryJSON 权威化

如果当前 iOS 暂时不能拿到 Web 的逐题流式事件，至少要保证最终 result 可落库和恢复。

要求：

```text
1. AI 完成后必须将合法结构写入 result.summaryJSON 或 metadata["summary_json"]。
2. summaryJSON 统一使用 Web 的 `results[].qa_pair` 结构。
3. result.summaryJSON 是最终持久化和会话恢复的权威来源。
4. contentDelta 只保留 intro，不承载题目主体。
5. DeepTutorQuizExtractor.extractFromResult 必须能稳定解析该结构。
```

目标结构：

```json
{
  "results": [
    {
      "qa_pair": {
        "question_id": "q_1",
        "question": "题干",
        "question_type": "choice",
        "options": {
          "A": "选项 A",
          "B": "选项 B",
          "C": "选项 C",
          "D": "选项 D"
        },
        "correct_answer": "B",
        "explanation": "解释",
        "difficulty": "easy",
        "concentration": "知识点"
      }
    }
  ]
}
```

### 6.3 P0 方案三：非法 quiz_json 的确定性修复或结构化重试

当前真实模型会输出残缺 quiz_json，因此只靠 prompt 不够。

需要新增的处理策略：

```text
1. Parser 检测到 `quiz_json` fenced block 但 JSONSerialization 失败时，不直接结束。
2. 先记录 parse failure reason，包含 missing_object_start、missing_results_array、missing_options_object 等分类。
3. 可选做 deterministic repair：
   - 给 fenced block 补最外层 `{}`。
   - 将 `"results":` 后的多个 qa_pair 修复成数组。
   - 将 `"options":` 后连续 A/B/C/D 修复成对象。
   - 对 fill_in_blank 缺失 options 的情况转成空对象或 nil。
4. repair 后必须再次走同一套 validatedSummaryJSON。
5. 如果 deterministic repair 失败，只允许触发一次结构化重试。
6. 结构化重试必须使用同一 `.chat` 场景和项目已有 AI 模型消费体系，不新建 `.deepTutor` 场景。
7. 重试 prompt 只做格式修复，不重新创作题目，避免内容漂移。
8. 修复仍失败时展示解析失败卡片，不展示残缺 JSON。
```

注意：

```text
deterministic repair 是对模型已输出内容的结构修复，不是 iOS 自创题目。
```

### 6.4 P1 方案四：UI 失败态卡片

当检测到 `foundStructuredPayload=true` 但无法生成 `.quiz` block 时，iOS 不应静默只显示 intro。

目标 UI：

```text
DeepTutorQuizParseErrorCard
标题：问答结构解析失败
说明：题目数据未能解析为可交互卡片，请重新生成。
操作：重新生成
调试入口：仅 debug build 显示解析失败原因和 source message id
```

展示位置：

```text
AssistantActivity
AssistantResponse intro
DeepTutorQuizParseErrorCard
操作栏
```

目的：

```text
用户能明确知道不是“没有题目”，而是“题目结构解析失败”。
开发者可以通过调试信息继续定位。
```

### 6.5 P1 方案五：日志节流与全链路埋点

当前 `deeptutor.quiz.extract.failed reason=no_quiz_data` 在流式期间重复出现，建议改为状态化日志。

新增或优化日志：

```text
deeptutor.quiz.pipeline.expected
字段：conversation、assistant、capability、source、expectedSources

deeptutor.quiz.content_parser.detected
字段：conversation、assistant、pattern、contentLength

deeptutor.quiz.content_parser.parse_failed
字段：conversation、assistant、pattern、reason、rawLength

deeptutor.quiz.content_parser.repair_attempt
字段：conversation、assistant、strategy、rawLength

deeptutor.quiz.content_parser.repair_done
字段：conversation、assistant、questionCount、durationMs

deeptutor.quiz.content_parser.structured_retry_start
字段：conversation、assistant、model、scenario

deeptutor.quiz.extract.skipped_no_new_data
字段：conversation、assistant、phase、reason

deeptutor.quiz.extract.done
字段：conversation、assistant、source、questionCount、questionIDs、questionTypes

deeptutor.quiz.block.created
字段：conversation、assistant、questionCount、source

deeptutor.quiz.block.missing_after_final
字段：conversation、assistant、reason、hasQuizJson、hasResultSummary、hasStreamingQuestions

deeptutor.quiz.render.error_card_shown
字段：conversation、assistant、reason
```

节流规则：

```text
1. streaming partial 阶段没有新 content/result/quiz event 时，不重复打印 extract.failed。
2. 同一个 assistant message 的同一种 failureReason 只打印一次 warning。
3. final ready 阶段仍无 quiz block 时打印一次 P0 级 missing_after_final。
4. debug snapshot 必须显示 quizBlockCount、quizQuestionCount、quizExtractionSource、quizParseFailureReason。
```

## 7. iOS 目标文件级改造清单

### 7.1 Application 层

| 文件 | 当前职责 | 目标改造 |
| --- | --- | --- |
| `DeepTutorQuizContentParser.swift` | 从普通文本中提取 quiz_json，合法 JSON 才生成 summaryJSON | 增加非法 JSON 分类、确定性 repair、结构化重试触发标记、失败原因输出 |
| `DeepTutorQuizExtractor.swift` | 从 result.summaryJSON 或 quizQuestionEmitted 提取 payload | 保持 Web 优先级语义，补充 source 判定和无新数据节流 |
| `DeepTutorMessageReducer.swift` | deepQuestion 下插入 `.quiz` block | 当 structured payload 解析失败时插入 parse error block 或记录 final missing；禁止静默只有 intro |
| `DeepTutorChatViewModel.swift` | 组包、流式映射、消息落库 | 确保 final result summaryJSON 注入 message.events；确保 debug snapshot 暴露 quiz 关键字段 |
| `DeepTutorToolPolicyResolver.swift` | deepQuestion 工具策略 | 继续对齐 Web 工具组合策略，不通过关键词补问答卡片 |

### 7.2 Domain 层

| 模型 | 目标字段 |
| --- | --- |
| `DeepTutorQuizPayload` | `title`、`turnID`、`questions`、`source` |
| `DeepTutorQuizQuestion` | `id/question/questionType/options/correctAnswer/explanation/difficulty/concentration/knowledgeContext` |
| `DeepTutorStreamEvent` | 需要保留 `quizQuestionEmitted` 或等价结构化事件、`result(summaryJSON:)` |
| `DeepTutorMessageBlock` | 继续支持 `.quiz`；建议补充 `.quizParseError` 或等价失败态 |

### 7.3 Presentation 层

| 文件 | 当前职责 | 目标改造 |
| --- | --- | --- |
| `DeepTutorAssistantBubble.swift` | 按 block 渲染 trace/text/askUser/quiz 等 | 保持 block 驱动，不在 UI 层从 raw content 自行解析 |
| `DeepTutorQuizCardView.swift` | 渲染 Quick Check 问答卡片 | 只消费真实 payload；移除 Fixture/占位语义；样式继续对齐 Web |
| `DeepTutorQuizHeaderView.swift` | 题号 chip、进度、上一题/下一题 | 对齐 Web 0/3、圆形 chip、进度条和 disabled 状态 |
| `DeepTutorQuizAnswerInputView.swift` | 选择题/判断题/填空题输入 | 对齐 Web choice/concept/fill_in_blank 的输入和检查答案状态 |
| 新增 `DeepTutorQuizParseErrorCard` | 暂未确认存在 | 展示结构解析失败，提供重新生成入口 |

## 8. 数据模型对齐要求

### 8.1 题目字段

| Web 字段 | iOS 字段 | 必填 | 说明 |
| --- | --- | --- | --- |
| `question_id` | `id` | 是 | q_1/q_2/q_3；不能跨 turn 复用答题状态 |
| `question` | `question` | 是 | 题干 |
| `question_type` | `questionType` | 是 | `choice`、`concept`、`fill_in_blank` |
| `options` | `options` | choice 必填 | A-D 选项；concept 可用 true/false 或对/错；fill 可为空 |
| `correct_answer` | `correctAnswer` | 是 | 选择题为选项 key；判断题为 true/false；填空题为文本 |
| `explanation` | `explanation` | 是 | 检查答案后的解释 |
| `difficulty` | `difficulty` | 否 | easy/medium/hard |
| `concentration` | `concentration` | 否 | 知识点 |
| `knowledge_context` | `knowledgeContext` | 否 | 来源或知识上下文 |

### 8.2 Turn 隔离

要求：

```text
1. 每轮问答必须有 turnID。
2. 答题状态 key 必须包含 conversationID + turnID + questionID。
3. 不能只用 q_1/q_2/q_3 做本地状态 key。
4. 会话恢复后不能串用上一轮问答答案。
```

Web 对标：

```text
QuizViewer 注释明确：turn identity 用于避免不同 quiz 的 q_1/q_2 状态继承。
```

## 9. UI 对齐要求

### 9.1 正常状态

页面结构：

```text
用户消息气泡
助手 Activity / trace
助手 intro 文本
Quick Check 卡片
消息操作栏
Composer
```

Quick Check 卡片必须包含：

```text
1. 外层圆角卡片。
2. 顶部导航条：上一题按钮、完成进度、题号 chip、下一题按钮。
3. 顶部细进度条。
4. 题目标签：Q1/Q2/Q3、difficulty、question_type。
5. 题干 markdown 渲染。
6. choice：两个或多个选项按钮。
7. concept：对/错按钮。
8. fill_in_blank：输入框。
9. 检查答案按钮。
10. 提交后解释/判断区域。
11. 收藏和追问入口。
```

### 9.2 本次失败状态

当前截图中的错误效果：

```text
1. 只展示 trace 和一句 intro。
2. 没有 Quick Check 卡片。
3. 用户无法答题。
4. debug snapshot 也没有直接暴露 quizBlockCount 和 parseFailureReason。
```

目标失败态：

```text
1. 如果检测到 quiz_json 但无法解析，展示“问答结构解析失败”卡片。
2. 卡片内提供“重新生成”。
3. debug 入口显示 parseFailureReason。
4. 不展示非法 JSON。
```

## 10. 验收标准

### 10.1 正常生成验收

Given：

```text
用户选择 Quiz 能力
输入：健康知识问答
```

When：

```text
AI 完成回答
```

Then：

```text
1. 页面展示 Quick Check 问答卡片。
2. 卡片中有 1-3 道题。
3. 不展示 raw quiz_json。
4. debug snapshot 中：
   - blockKinds 包含 quiz
   - quizBlockCount=1
   - quizQuestionCount > 0
   - quizExtractionSource 为 streaming/result/contentParser/repair 之一
5. 日志出现 quiz.extract.done。
6. 日志出现 quiz.block.created。
7. final 阶段不再出现重复 no_quiz_data 噪声。
```

### 10.2 非法 JSON 兜底验收

Given：

```text
模型返回包含 `quiz_json` fenced block，但 JSON 缺少外层对象或 options 对象。
```

When：

```text
iOS final reducer 处理 assistant message。
```

Then：

```text
1. Parser 记录 parse_failed reason。
2. 系统尝试 deterministic repair 或一次结构化重试。
3. 如果修复成功，生成 quiz block。
4. 如果修复失败，展示解析失败卡片。
5. 不展示 raw quiz_json。
6. 不使用 fixture 题目。
```

### 10.3 Web 对齐验收

对比 DeepTutor-main Web：

```text
1. iOS 的卡片出现条件与 Web 一致：必须有 quizQuestions。
2. iOS 的题目来源与 Web 一致：streaming question events 或 final result summary。
3. iOS 的 intro + Quiz 卡片结构与 Web 一致。
4. iOS 的 turnID 隔离与 Web 一致。
5. iOS 的答题状态、检查答案、解释、追问入口继续按 `DEEPTUTORCHAT-000013` 对齐。
```

## 11. 实施拆分

### P0.1 结构化数据源收敛

```text
1. 冻结 iOS deep_question 消费结构：优先 quizQuestionEmitted，其次 result.summaryJSON。
2. 检查当前 AI runtime 是否能返回 Web 等价 summary metadata。
3. 如果不能，新增 iOS 侧合法 summaryJSON 注入策略，但必须来源于真实模型输出或结构化重试。
```

### P0.2 Parser 修复与失败态

```text
1. 为 DeepTutorQuizContentParser 增加非法 JSON 分类。
2. 支持有限 deterministic repair。
3. repair 失败后生成 parse error 状态。
4. Reducer 根据 parse error 插入失败卡片或明确错误 block。
```

### P0.3 Extractor 与 Reducer 稳定性

```text
1. Extractor 增加 no_new_data 判断，避免 partial 阶段重复失败日志。
2. Reducer final ready 后检查 deep_question 是否缺 quiz block。
3. 缺失时输出 missing_after_final，并携带 hasQuizJson/hasResultSummary/hasStreamingQuestions。
```

### P0.4 UI 对齐

```text
1. 确认 DeepTutorQuizCardView 完全由 payload 驱动。
2. 去掉 Fixture/占位标签。
3. 对齐 Web 顶部导航、进度条、题号 chip、题型标签、检查答案按钮。
4. 增加解析失败卡片。
```

### P0.5 Debug Snapshot 补齐

```text
1. 增加 quizBlockCount。
2. 增加 quizQuestionCount。
3. 增加 quizExtractionSource。
4. 增加 quizParseFailureReason。
5. 增加 hasQuizJsonInContent。
6. 增加 resultHasSummaryJSON。
7. 增加 streamingQuizQuestionEventCount。
```

## 12. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 真实模型持续输出非法 JSON | 卡片仍无法生成 | 需要结构化输出约束、一次格式修复重试或接入 Web 等价 QuestionPipeline |
| 只靠 prompt 约束不稳定 | 回归概率高 | 不把 prompt 当唯一保证，必须有 parser/validator/retry |
| iOS 与 Web 事件协议不一致 | 无法完全复用 Web 语义 | 冻结 `quiz_question_emitted` 和 `summary.results` 契约 |
| 没有 turnID | 答题状态串轮 | result/streaming event 必须补 turnID |
| 日志重复刷屏 | 排查困难 | 按 messageID + failureReason 节流 |
| 解析失败静默吞掉 | 用户以为 AI 未出题 | 必须展示失败卡片或重试入口 |

待确认：

```text
1. 当前项目 AI runtime 是否支持强 JSON schema / tool-call structured output。
2. deep_question 是否应由后端 QuestionPipeline 统一生成结构化事件。
3. iOS 是否允许在 final 后发起一次“仅修复格式”的模型调用。
4. 本地数据库是否已持久化 result.summaryJSON / quizQuestionEmitted 事件。
5. Debug snapshot 是否可以直接展开完整 quiz payload 方便排查。
```

## 13. 结论

本次问题的准确结论：

```text
iOS 没有显示 Web 对应问答卡片，不是因为 DeepTutorQuizCardView 单独失效。
真实原因是 deep_question 的结构化题目数据没有成功形成：
没有 Web 的 quiz_question_emitted 事件，
没有 result.summaryJSON，
普通 contentDelta 中的 quiz_json 又是非法 JSON。
解析器隐藏了非法结构块后，只剩 intro 文本，因此页面看不到 Quick Check 卡片。
```

后续修复重点：

```text
1. 先对齐 Web 的结构化题目事件/result summary 契约。
2. 再补非法 JSON 的确定性修复或结构化重试。
3. 最后完善 UI 失败态和日志节流。
4. 禁止用 fixture、本地硬编码或关键词自创题目绕过真实数据链路。
```
