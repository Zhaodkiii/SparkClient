# DEEPTUTORCHAT-000013 Quick Check 卡片对齐 DeepTutor-main 交互与数据链路工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000013 |
| 工单类型 | P0 Quiz / Quick Check 卡片 UI 对齐 + 数据链路补齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 用户附件 | `/Users/hua/.codex/attachments/556d7bf2-23b0-4da3-b4ce-deaedd85e110/pasted-text.txt`、`/Users/hua/.codex/attachments/c651fdf1-cc0f-4b86-8eb7-f7447d1a1289/pasted-text.txt`、`/Users/hua/.codex/attachments/0e3574a1-c6f7-42f2-8dd3-4615671ac844/pasted-text.txt`、`/Users/hua/.codex/attachments/928f5914-39c4-466a-9e95-2a68d7e504ca/pasted-text.txt` |
| 创建日期 | 2026-08-05 |
| 关联工单 | `DEEPTUTORCHAT-000001`、`DEEPTUTORCHAT-000010`、`DEEPTUTORCHAT-000012` |

## 1. 本工单目标

当前 iOS DeepTutorChat 的 Quick Check 卡片与 DeepTutor-main Web 差距过大，需要按 Web 的 `QuizViewer` 实现进行对齐。

本工单目标：

```text
1. Quick Check 卡片 UI 效果、信息层级、交互状态对齐 DeepTutor-main。
2. iOS 不再使用硬编码 Fixture 题目和 Fixture 标签。
3. iOS 支持 Web 已有的题目类型：choice、concept、fill_in_blank，后续预留 short_answer / written / coding。
4. iOS 支持逐题导航、完成进度、选择/填空、检查答案、正确/错误反馈、重试、参考答案/解析折叠。
5. iOS 从真实 AI 事件 / result metadata 中解析 quiz 数据，而不是 Reducer 固定插入占位数据。
6. iOS 的 Quick Check 状态需要可本地持久化，避免刷新后答题状态丢失。
```

本工单只写需求与技术方案，不直接改 Swift 代码。

## 2. DeepTutor-main Web 对齐基线

### 2.1 Web 卡片所在链路

Web 消息链路：

```text
ChatMessages.tsx
  -> AssistantMessage
  -> quizQuestions = extractStreamingQuizQuestions(msg.events) 或 extractQuizQuestions(resultEvent.metadata)
  -> <AssistantResponse content={msg.content} />
  -> <QuizViewer questions={quizQuestions} sessionId={sessionId} turnId={quizTurnId} language={language} />
```

关键文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/quiz/QuizViewer.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-types.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/quiz-question-type.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/QuizFollowupContext.tsx
```

### 2.2 Web 数据来源

Web 不靠前端硬编码题目。它从助手消息事件流中提取题目：

```text
优先级 1：final result event
  result.metadata.summary.results[].qa_pair

优先级 2：streaming content event
  event.type === "content"
  event.metadata.call_kind === "quiz_question_emitted"
  event.metadata.qa_pair
  event.metadata.question_index
```

Web 关键逻辑：

```text
extractStreamingQuizQuestions(events)
  -> 按 question_id / question_index 去重
  -> 按 question_index 排序
  -> 返回 QuizQuestion[]

extractQuizQuestions(resultMetadata)
  -> 从 summary.results 提取最终权威题目

extractQuizTurnId(events)
  -> 用 turn_id 隔离同一会话内不同 quiz 的答题状态
```

### 2.3 Web 支持的题目字段

Web `QuizQuestion` 语义字段：

| 字段 | 说明 | iOS 当前状态 |
| --- | --- | --- |
| `question_id` | 题目稳定 ID | 当前只有 `id`，来源是 Fixture |
| `question` | Markdown 题干 | 当前 `prompt` 文本 |
| `question_type` | `choice` / `concept` / `fill_in_blank` / `short_answer` / `written` / `coding` | 当前没有类型字段 |
| `options` | 选项字典，例如 `A/B/C/D -> 文本` | 当前是 `[String]`，丢失选项 key |
| `correct_answer` | 正确答案，可为 `A`、`false`、`2` 等 | 当前是 `correctIndex` |
| `explanation` | 解析 Markdown | 当前没有 |
| `difficulty` | `easy` / `medium` / `hard` | 当前没有 |
| `concentration` | 题目知识点/分类 | 当前没有 |
| `knowledge_context` | 知识上下文 | 当前没有 |
| `user_answer` | 用户答案 | 当前没有 |
| `is_correct` | 是否正确 | 当前没有 |
| `ai_judgment` | AI 评判结果 | 当前没有 |

### 2.4 Web 视觉结构

用户提供的 Web DOM 显示，Quick Check 卡片结构如下：

```text
外层卡片
  overflow-hidden
  rounded-xl
  border border-[var(--border)]
  bg-[var(--card)]

顶部导航栏
  左箭头 32x32
  完成数/总题数，例如 0/3、1/3、3/3
  题号圆点 chips：1、2、3
  右箭头 32x32

进度条
  高度 2px
  背景 muted
  当前进度 primary
  transition duration 300ms

内容区域
  padding x=16 y=12
  meta chips：Q1 / easy / concept
  已提交后右侧显示 收藏 / 添加分类 / 追问对话
  Markdown 题干
  答题控件
  操作区
  已提交后显示参考答案/解析卡片
```

### 2.5 Web 题型展示

#### choice 多选一

结构：

```text
space-y-1.5
每个选项为整行 button
  rounded-lg border
  px-3 py-2
  左侧 20x20 圆形 key badge：A/B/C/D
  右侧 Markdown 选项文本
```

状态：

```text
未选择：border + background
已选择未提交：primary border + primary tint + ring
提交后正确项：green border + green background + 左侧 check
提交后错误选择：red border + red background
提交后其他项：disabled neutral
```

#### concept 判断题

结构：

```text
两个等宽按钮
  对
  错
高度约 44px
rounded-lg border
text 14px semibold
```

状态：

```text
未选择：neutral
已选择未提交：primary tint
提交后正确：green
提交后用户错误选择：red
```

#### fill_in_blank 填空题

结构：

```text
标签：填空题
单行 input
placeholder：在此输入答案…
border rounded-lg
font-size 13px
```

状态：

```text
未提交：background + focus primary border
提交后：muted background + disabled
```

#### short_answer / written / coding 后续预留

Web 已支持：

```text
short_answer：textarea rows=3
written：textarea rows=5
coding：textarea rows=6 + mono font
非自动评分题支持图片作为答案
```

本工单 iOS 第一阶段可先完成 `choice`、`concept`、`fill_in_blank`，但数据模型必须预留以上类型，不要再设计成只能容纳 `[String] + correctIndex`。

### 2.6 Web 答题后区域

未提交：

```text
按钮：检查答案
图标：Eye
disabled 条件：
  choice / concept 未选择
  fill_in_blank 未输入
```

提交后：

```text
正确/错误 badge
重试按钮
AI 评判按钮
参考答案 / AI Judgment 折叠面板
```

参考答案面板：

```text
rounded-lg border
bg background
px-3 py-2.5
header：参考答案 / AI Judgment
chevron 折叠
内容：
  参考答案：非 choice/concept 时显示 correct_answer
  解析：explanation Markdown
```

### 2.7 Web 的 Notebook / Follow-up 能力

Web 已接入：

```text
lookupNotebookEntry(sessionId, questionKey, turnId)
upsertNotebookEntry(...)
updateNotebookEntry(...)
listCategories()
addEntryToCategory(...)
createCategory(...)
QuizFollowupContext.openFollowupTab(...)
recordQuizResults(...)
startQuizJudge(...)
```

iOS 当前阶段如果暂不接入服务端 Notebook，也必须在工单中明确：

```text
1. 本地先持久化答题状态。
2. 收藏、分类、追问对话、AI 评判先做入口和状态设计。
3. 后续接服务端时字段不能重构。
```

## 3. iOS 当前代码事实

### 3.1 当前挂载位置

iOS Quick Check 仍然位于助手消息气泡 block 内：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift

case .quiz(let payload):
  DeepTutorQuizCardView(payload: payload)
```

### 3.2 当前卡片组件

当前组件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorQuizCardView.swift
```

当前实现问题：

```text
1. 只有标题 + 全量题目列表 + option rows。
2. 没有顶部题目导航。
3. 没有进度条。
4. 没有当前题索引状态。
5. 没有题型、难度、知识点 chips。
6. 没有 choice/concept/fill_in_blank 分支。
7. 没有选择态、提交态、正确/错误态。
8. 没有检查答案、重试、AI 评判。
9. 没有参考答案/解析面板。
10. 显示 `Fixture` 标签，暴露占位实现。
11. 使用 `correctIndex`，与 Web `correct_answer` 不一致。
```

### 3.3 当前数据模型

当前 iOS 模型：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift

DeepTutorQuizPayload:
  title: String
  questions: [DeepTutorQuizQuestion]

DeepTutorQuizQuestion:
  id: String
  prompt: String
  options: [String]
  correctIndex: Int?
```

问题：

```text
1. 无法表达 Web 的 question_type。
2. 无法表达 fill_in_blank。
3. 无法表达 explanation。
4. 无法表达 difficulty / concentration。
5. 无法表达 options key，例如 A/B/C/D。
6. 无法表达 correct_answer 的原始值。
7. 无法表达用户答案和提交状态。
8. 无法用 turnId 隔离同一会话内不同 quiz。
```

### 3.4 当前 Reducer 仍硬编码 Fixture

当前代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift

if message.capability == .deepQuestion {
  return DeepTutorQuizPayload(
    title: "Quick Check",
    questions: [
      DeepTutorQuizQuestion(
        id: "q1",
        prompt: "Which option best summarizes the concept?",
        options: ["Option A", "Option B", "Option C"],
        correctIndex: 1
      )
    ]
  )
}
```

问题：

```text
1. 与 AI 真实输出无关。
2. 会覆盖或掩盖模型真正生成的问题。
3. 卡片永远只有一题，无法展示 Web 的 3 题导航。
4. `Fixture` 标签是当前 UI 差距的直接来源。
```

### 3.5 当前 Prompt 仍不保证结构化 Quiz 输出

当前代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPromptBuilder.swift

Mode: quiz / knowledge check.
Produce a short quiz with 1-3 multiple-choice questions when appropriate.
After the quiz, explain the correct answers briefly.
```

问题：

```text
1. 只要求 multiple-choice，不包含 concept / fill_in_blank。
2. 没有要求 JSON / qa_pair / summary.results 格式。
3. 没有要求 question_id、question_type、correct_answer、explanation、difficulty。
4. iOS 因此无法稳定从普通 Markdown 中解析 Quick Check。
```

### 3.6 当前工具策略限制 deepQuestion

当前线索：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift

case .deepQuestion, .mathAnimator, .visualize:
  allowedToolNames: minimalAlwaysOnTools
```

需要排查：

```text
1. minimalAlwaysOnTools 是否足够生成权威健康题。
2. Web 示例中 deep_question 会进行联网搜索并收集健康科普素材。
3. 如果 iOS deepQuestion 不允许 web_search / health knowledge 工具，会导致题目质量和 Web 不一致。
4. 需要与 DEEPTUTORCHAT-000007 的“本轮工具组合策略层”一起处理。
```

## 4. 当前差距清单

| 类型 | DeepTutor-main Web | iOS 当前 | 差距等级 |
| --- | --- | --- | --- |
| 数据来源 | 事件流 / result metadata 解析真实题目 | Reducer 硬编码 Fixture | P0 |
| 题目数量 | 1-N 题，示例 3 题 | 固定 1 题 | P0 |
| 题目类型 | choice / concept / fill_in_blank / free text | 只有 options 列表 | P0 |
| 顶部导航 | 左右箭头 + 题号 chips + 完成数 | 无 | P0 |
| 进度条 | 2px primary 进度条 | 无 | P0 |
| 状态 | 未答/选择/提交/正确/错误/重试 | 无交互状态 | P0 |
| 答案检查 | Check Answer 自动判分 | 无 | P0 |
| 解析 | 参考答案/解析折叠面板 | 无 | P0 |
| AI 评判 | 支持 Judging / Re-judge | 无 | P1 |
| 收藏分类 | Bookmark / FolderPlus | 无 | P1 |
| 追问对话 | Follow-up Chat | 无 | P1 |
| Markdown | 题干/选项/解析都 Markdown 渲染 | prompt/options 纯 Text | P0 |
| 持久化 | turnId 隔离 + notebook | 无本地答题状态 | P0 |
| UI 质感 | border/card/primary/green/red/amber 精细状态 | 简单 secondarySurface + shadow | P0 |

## 5. iOS 目标架构

### 5.1 目标链路

目标链路应对齐 Web：

```text
DeepTutor AI Stream
  -> DeepTutorStreamEvent
  -> DeepTutorMessageReducer
  -> extractStreamingQuizQuestions / extractQuizQuestions
  -> DeepTutorQuizPayload
  -> DeepTutorQuizCardView
  -> 本地 QuizAnswerState
  -> 本地数据库持久化
```

### 5.2 iOS 目标文件拆分

建议新增或重构为以下职责：

```text
Domain/
  DeepTutorQuizModels.swift
    DeepTutorQuizPayload
    DeepTutorQuizQuestion
    DeepTutorQuizQuestionType
    DeepTutorQuizAnswerState
    DeepTutorQuizJudgmentState

Application/
  DeepTutorQuizExtractor.swift
    从 events/result metadata 提取 quiz questions

  DeepTutorQuizAnswerStore.swift
    本地持久化答题状态

Presentation/Cards/
  DeepTutorQuizCardView.swift
    容器、导航、状态组合

  DeepTutorQuizHeaderView.swift
    顶部箭头、完成数、题号 chips、进度条

  DeepTutorQuizQuestionBodyView.swift
    meta chips、Markdown 题干

  DeepTutorQuizAnswerInputView.swift
    choice / concept / fillBlank / freeText

  DeepTutorQuizReviewPanelView.swift
    参考答案 / 解析 / AI judgment 折叠
```

如果当前阶段不拆文件，也必须在 `DeepTutorQuizCardView.swift` 内按以上职责拆成 private subviews，避免一个巨大 View。

## 6. 数据模型要求

### 6.1 Quiz Payload

iOS 目标模型：

```text
DeepTutorQuizPayload
  id: String?
  title: String
  turnID: String?
  questions: [DeepTutorQuizQuestion]
  source: streaming | result | legacy
```

说明：

```text
1. `turnID` 必须来自 events，防止同一会话多个 Quiz 答案串台。
2. `source` 用于 debug，确认当前卡片来自 streaming 还是 final result。
```

### 6.2 Quiz Question

iOS 目标模型：

```text
DeepTutorQuizQuestion
  id: String
  question: String
  questionType: DeepTutorQuizQuestionType
  options: [DeepTutorQuizOption]
  correctAnswer: String
  explanation: String
  difficulty: String?
  concentration: String?
  knowledgeContext: String?
```

### 6.3 Quiz Option

```text
DeepTutorQuizOption
  key: String
  text: String
```

要求：

```text
1. Web options 是 Record<string, string>，iOS 必须保留 key。
2. UI 左侧 badge 显示 key：A/B/C/D。
3. 不能只保存 `[String]`，否则无法稳定判断用户选择是否等于 correct_answer。
```

### 6.4 Question Type

```text
DeepTutorQuizQuestionType
  choice
  concept
  fillInBlank
  shortAnswer
  written
  coding
```

兼容别名需要对齐 Web：

```text
multiple_choice -> choice
multiple-choice -> choice
mcq -> choice
true_false -> concept
true-false -> concept
tf -> concept
judgement -> concept
fill-in-the-blank -> fillInBlank
fill_in_the_blank -> fillInBlank
cloze -> fillInBlank
open_ended / open-ended / open_response / essay -> written
code / programming -> coding
```

### 6.5 Answer State

iOS 目标本地状态：

```text
DeepTutorQuizAnswerState
  conversationID: UUID
  assistantMessageID: UUID
  turnID: String?
  questionID: String
  questionIndex: Int
  selectedKey: String?
  typedText: String
  submitted: Bool
  isCorrect: Bool?
  submittedAt: Date?
  aiJudgment: String?
  reviewCollapsed: Bool
```

持久化 key：

```text
conversationID + assistantMessageID + turnID + questionID
```

如果 `turnID` 为空：

```text
1. 只能做 local-only。
2. 不允许继承其他 quiz 的答案状态。
3. 日志标记 `turn_missing_local_only`。
```

## 7. UI 详细设计规格

### 7.1 外层卡片

Web 对齐：

```text
cornerRadius: 12
border: 1px var(--border)
background: var(--card)
overflow hidden
shadow: Web 无明显大阴影，iOS 不要使用过重 bubble shadow
```

iOS 建议：

```text
RoundedRectangle(cornerRadius: 12, style: .continuous)
stroke: DeepTutorPalette.border / system separator
fill: card background
clipShape: RoundedRectangle
```

禁止：

```text
1. 使用大圆角 22/26 造成和 Web 卡片形态不一致。
2. 使用强阴影让卡片像独立浮层。
3. 在卡片外再套一层大 padding 破坏消息列宽度。
```

### 7.2 顶部导航栏

布局：

```text
height: 48 左右
horizontal padding: 12
vertical padding: 8
gap: 8
bottom border: 1px
```

元素：

```text
Prev button:
  32x32
  rounded 6
  border
  muted background 60%
  disabled opacity 40%

完成数:
  font 11 semibold
  muted foreground
  格式 completedCount/total

题号 chips:
  24x24
  circle
  font 10 semibold
  current: primary + white + small shadow
  unanswered: muted + mutedForeground
  correct: green tint + green text
  incorrect: red tint + red text
  submitted open-ended: primary tint + primary text

Next button:
  同 Prev
```

交互：

```text
1. 点击题号切换当前题。
2. 上一题/下一题到边界时 disabled。
3. 切题不清空当前题输入。
4. chips 用颜色表达已提交结果，数字仍保留，便于导航。
```

### 7.3 进度条

规格：

```text
height: 2
background: muted
foreground: primary
width: (currentIndex + 1) / total
animation: 300ms ease
```

注意：

```text
Web 进度条表达当前浏览到第几题，不是完成率。
完成率由 completedCount/total 表达。
```

### 7.4 Meta Chips

布局：

```text
content padding: x=16 y=12
meta row margin-bottom: 8
gap: 6
```

chips：

```text
Q1:
  bg muted
  text mutedForeground
  uppercase
  font 10 medium
  radius 6
  px 6 py 2

difficulty:
  easy: green tint
  medium: amber tint
  hard: red tint

question_type:
  bg muted
  text mutedForeground
```

### 7.5 已提交后右侧操作

Web 已提交后显示：

```text
收藏 Bookmark
添加到分类 FolderPlus
追问对话 MessageSquarePlus + 文案
```

iOS 阶段要求：

```text
P0：可先隐藏收藏/分类/追问，避免空按钮。
P1：补齐按钮，但必须明确不可用/本地状态。
P2：接入项目已有收藏、分类或会话系统。
```

如果显示按钮，必须：

```text
1. 未提交不显示。
2. 未接入服务时 disabled 或显示“待接入”日志，不做假成功。
3. 追问对话应创建普通 `.chat` 场景上下文，不新增 `.deepTutor` 场景。
```

### 7.6 题干 Markdown

规格：

```text
font-size: 14
line-height: relaxed
margin-bottom: 12
renderer: DeepTutorMarkdownRenderer
```

要求：

```text
1. 题干支持 Markdown。
2. 选项支持 Markdown。
3. 解析支持 Markdown。
4. 保留中英文、数字、source 引用、粗体、公式等。
```

### 7.7 Choice 选项

未提交：

```text
row:
  full width
  border 1
  rounded 8
  px 12 py 8
  gap 10
  background card/background
  hover 在 iOS 替换为 pressed/tint

key badge:
  20x20
  circle
  border
  font 11 bold
```

已选择未提交：

```text
row border primary
row bg primary opacity 0.06
ring primary opacity 0.2
badge bg primary text white
```

提交后正确项：

```text
row border green
row bg green tint
badge bg green text white
badge icon check
```

提交后用户错误项：

```text
row border red
row bg red tint
badge bg red text white
```

提交后其他项：

```text
disabled neutral
```

### 7.8 Concept 判断题

布局：

```text
HStack gap 8
两个按钮等宽
height: 44
rounded 8
font 14 semibold
```

文案：

```text
中文：对 / 错
英文：True / False
```

判分：

```text
correct_answer 支持：
  true / false
  对 / 错
  yes / no
  correct / incorrect
  A / B 如果模型输出映射
```

### 7.9 Fill in Blank

布局：

```text
label: 填空题
font 10 semibold uppercase tracking
input height 36-40
font 13
rounded 8
border
placeholder: 在此输入答案…
```

状态：

```text
未提交：可编辑，focus primary border
提交后：disabled，bg muted，保留用户答案
```

判分：

```text
1. trim 后大小写不敏感。
2. 中文数字和阿拉伯数字需要可配置兼容，例如 “2” / “两”。
3. 后续可支持多个答案别名，用 `acceptedAnswers` 扩展。
```

### 7.10 操作区

未提交：

```text
Check Answer 按钮
icon: Eye
height: 30 左右
bg primary
text white
font 12 medium
disabled opacity 30%
```

提交后：

```text
correct/incorrect badge
Retry 按钮
AI Judge 按钮
```

P0：

```text
1. 必须实现 correct/incorrect badge。
2. 必须实现 Retry。
3. AI Judge 可先 disabled 或隐藏，但工单中保留状态设计。
```

### 7.11 参考答案/解析面板

显示条件：

```text
ans.submitted == true
且 q.explanation 非空 或 fill_blank/free_text 有 correct_answer
```

结构：

```text
margin-top: 12
rounded 8
border
background: var(--background)
padding x=12 y=10

header:
  参考答案 / AI Judgment
  chevron

body:
  可折叠
  参考答案 label
  correct_answer Markdown
  解析 label
  explanation Markdown
```

默认：

```text
1. 提交后默认展开。
2. 用户折叠状态按 questionID 保持。
3. 切题再回来，不应丢失折叠状态。
```

## 8. 数据解析与 Reducer 方案

### 8.1 不再由 `quiz(from:)` 硬编码题目

要求：

```text
1. 删除或废弃固定 Fixture 题目路径。
2. 如果真实 events 中没有 quiz 数据，不渲染 Quick Check 卡片。
3. 不允许为了展示卡片而注入 Option A/B/C。
```

### 8.2 从 streaming event 提取题目

对齐 Web：

```text
event.type == content
event.metadata.call_kind == quiz_question_emitted
event.metadata.qa_pair
event.metadata.question_index
```

iOS 需要在 `DeepTutorStreamEvent` / metadata 中保留：

```text
type
metadata.call_kind
metadata.qa_pair
metadata.question_index
turn_id
```

如果当前 `DeepTutorStreamEvent` 已经丢失上述字段，需要补充事件模型和 codec。

### 8.3 从 final result 提取题目

对齐 Web：

```text
result.metadata.summary.results[].qa_pair
```

final result 是权威来源：

```text
1. 流式中可以逐题出现。
2. final result 到达后，以 final result 覆盖/补全 streaming 题目。
3. 覆盖时必须保留用户已答状态。
```

### 8.4 Quiz block 生成规则

Reducer 目标：

```text
if message.capability == .deepQuestion:
  quiz = DeepTutorQuizExtractor.extract(message.events)
  if quiz.questions.isEmpty == false:
    append .quiz(quiz)
```

去重：

```text
primary key: question_id
fallback key: question_index
fallback key: normalized question text hash
```

排序：

```text
question_index 升序
没有 index 时按事件出现顺序
```

### 8.5 正文与 Quiz 卡片关系

对齐 Web：

```text
1. Quiz 前置说明正文显示在卡片上方。
2. 每道题不应重复以 Markdown 正文形式出现在卡片外。
3. 如果模型输出了题目 Markdown + 结构化 events，Reducer 需要剥离重复题目正文。
```

这与 `DEEPTUTORCHAT-000012` 的 Markdown render source 保真相关，不能把 quiz JSON 或题目正文压缩到普通 text block。

## 9. 本地持久化方案

当前版本要求本地优先，需要使用已有本地数据库。

### 9.1 持久化范围

必须持久化：

```text
1. 当前题索引 idx。
2. 每题 selectedKey / typedText。
3. submitted。
4. isCorrect。
5. reviewCollapsed。
6. aiJudgment 文本，如果实现。
```

可暂不持久化：

```text
1. hover/pressed 瞬时状态。
2. category dropdown 打开状态。
3. AI Judge streaming 中间态。
```

### 9.2 存储位置

建议方案：

```text
方案 A：作为 quiz block payload 内的 localState 字段持久化
优点：随消息一起加载，离线恢复简单。
风险：频繁答题会更新 message block。

方案 B：单独 DeepTutorQuizAnswer 表
优点：状态独立、避免修改原始 AI 产物。
风险：需要 join 或加载后 merge。
```

建议：

```text
P0 使用方案 B 或等价独立状态，避免用户答案污染 AI 原始消息块。
```

### 9.3 刷新一致性要求

对齐 `DEEPTUTORCHAT-000012`：

```text
1. 用户选择答案只更新本地 QuizAnswerState，不触发整条会话 reload。
2. Submit 后只局部刷新当前卡片。
3. database_change 不得把当前 UI 的选择态回滚。
4. 切题状态需要稳定，不因为消息列表 diff 重建而回到 Q1。
```

## 10. AI 生成与工具策略要求

### 10.1 Prompt 输出必须结构化

iOS deepQuestion Prompt 需要要求模型输出结构化 quiz 结果：

```text
question_id
question
question_type
options
correct_answer
explanation
difficulty
concentration
```

如果当前 AI Runtime 支持工具/structured output：

```text
优先使用专门 quiz result schema 或 event metadata。
```

如果只能用文本：

```text
1. 必须定义 JSON contract。
2. Reducer 解析 JSON。
3. 解析失败时不展示 Fixture 卡片，只展示普通回答并记录日志。
```

### 10.2 deepQuestion 工具策略要对齐 Web

Web 示例中生成健康题时会联网搜索：

```text
联网搜索：健康科普小知识 常见误区 问答 国家卫健委
联网搜索：中国居民膳食指南 2022 ...
联网搜索：成年人睡眠时长 运动建议 世界卫生组织 ...
```

iOS 当前 deepQuestion 使用 minimalAlwaysOnTools，可能无法达到 Web 的题目质量。

要求：

```text
1. deepQuestion 本轮工具组合策略需要重新评估。
2. 健康/科普题应允许项目已有 Web Search / Knowledge 工具。
3. 工具策略仍需按 DEEPTUTORCHAT-000007 的本轮策略层决策，不要把所有工具直接丢给模型。
4. debug snapshot 必须显示 resolvedAllowedToolsForCurrentTurn。
```

### 10.3 继续使用通用 `.chat` 场景约束

用户此前要求：

```text
继续使用通用 .chat 的场景，不要 .deepTutor。
```

本工单要求：

```text
1. AI 模型消费仍接项目已有 AIConfigCenter。
2. 不新增 `.deepTutor` 模型场景。
3. deepQuestion 只是 capability，不是新的模型消费场景。
```

## 11. 日志需求

### 11.1 Quiz 提取日志

新增：

```text
deeptutor.quiz.extract.start
deeptutor.quiz.extract.streaming_question
deeptutor.quiz.extract.result_question
deeptutor.quiz.extract.done
deeptutor.quiz.extract.failed
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
hasExplanation
durationMs
failureReason
```

### 11.2 Quiz UI 状态日志

新增：

```text
deeptutor.quiz.ui.navigate
deeptutor.quiz.ui.answer_selected
deeptutor.quiz.ui.answer_typed
deeptutor.quiz.ui.submit
deeptutor.quiz.ui.retry
deeptutor.quiz.ui.review_toggle
```

字段：

```text
conversation
assistant
turnID
questionID
questionIndex
questionType
selectedKey
typedLength
submitted
isCorrect
```

日志不需要脱敏，按用户要求可以记录完整问题与答案，但建议字段化，便于排查。

### 11.3 持久化日志

新增：

```text
deeptutor.quiz.answer.persist.start
deeptutor.quiz.answer.persist.done
deeptutor.quiz.answer.load.done
deeptutor.quiz.answer.merge.done
deeptutor.quiz.answer.turn_missing_local_only
```

字段：

```text
conversation
assistant
turnID
questionID
stateKey
submitted
isCorrect
durationMs
```

### 11.4 与 Web 对齐调试快照

`DeepTutorChat` 右上角调试信息需要增加：

```text
quizBlockCount
quizQuestionCount
quizQuestionTypes
quizTurnID
quizAnsweredCount
quizCurrentIndex
quizExtractSource
quizDecodeFailureCount
```

## 12. 验收用例

### 12.1 生成 3 道健康 Quick Check

步骤：

```text
1. 选择 Quiz / deepQuestion 能力。
2. 输入：帮我出 3 道健康科普小问答。
3. 等待 AI 完成。
```

期望：

```text
1. 卡片显示 3 道题。
2. 顶部显示 0/3。
3. 题号 chips 显示 1、2、3。
4. 左箭头在 Q1 disabled，右箭头可用。
5. 进度条 Q1 为 33.333%。
6. 不出现 Option A/B/C Fixture 占位题。
7. 不出现 Fixture 标签。
```

### 12.2 Concept 判断题

步骤：

```text
1. 打开 Q1 concept。
2. 选择“对”。
3. 点击“检查答案”。
```

期望：

```text
1. 未选择时检查答案 disabled。
2. 选择后检查答案 enabled。
3. 提交后正确项绿色，错误选择红色。
4. 显示“正确”或“错误”badge。
5. 显示“重试”。
6. 显示参考答案/解析面板。
```

### 12.3 Choice 单选题

步骤：

```text
1. 切换到 Q2 choice。
2. 选择 B。
3. 点击检查答案。
```

期望：

```text
1. 选项是整行按钮。
2. 左侧 badge 显示 A/B/C/D。
3. 选择态为 primary tint。
4. 提交后正确项显示 green + check。
5. 如果 B 错误，B 显示 red。
6. Q2 chip 颜色跟随正确/错误。
```

### 12.4 Fill in Blank 填空题

步骤：

```text
1. 切换到 Q3 fill_in_blank。
2. 输入“哈哈哈”。
3. 点击检查答案。
```

期望：

```text
1. input 提交后 disabled。
2. 用户输入保留。
3. 显示错误 badge。
4. 参考答案面板显示正确答案，例如 2。
5. 解析显示 Markdown。
```

### 12.5 重试

步骤：

```text
1. 对已提交题目点击“重试”。
```

期望：

```text
1. 当前题 submitted=false。
2. 清空 selectedKey 或 typedText。
3. 正确/错误 badge 消失。
4. 参考答案面板隐藏。
5. completedCount 减 1。
6. 当前题 chip 回到 current 或 unanswered 状态。
```

### 12.6 切题与刷新

步骤：

```text
1. 回答 Q1。
2. 切到 Q2。
3. 返回 Q1。
4. 退出会话再进入。
```

期望：

```text
1. Q1 答题状态不丢失。
2. 当前题索引可按设计恢复。
3. 不因消息 reload 回到 Fixture 卡。
4. 不因 database_change 清空用户答案。
```

### 12.7 对齐 Web 视觉

期望：

```text
1. 卡片宽度跟随助手消息列。
2. 圆角、边框、背景、padding 与 Web 接近。
3. 顶部导航、进度条、meta chips、答题控件层级一致。
4. iOS 不出现明显更大的阴影或更重的卡片外壳。
5. 中文字体大小和行高与 Web 观感接近。
```

## 13. 实施拆分

### P0-1：模型扩展与兼容解码

```text
1. 扩展 DeepTutorQuizPayload / DeepTutorQuizQuestion。
2. 增加 questionType、options key、correctAnswer、explanation、difficulty。
3. 保持旧 Fixture payload 可兼容 decode，但不再主动生成。
4. 增加 QuizExtractor。
```

### P0-2：真实 Quiz 数据接入

```text
1. 从 streaming content event metadata 提取题目。
2. 从 final result metadata 提取题目。
3. Reducer 用真实数据生成 quiz block。
4. 没有真实题目时不显示 Quick Check 卡。
```

### P0-3：Quick Check UI 对齐

```text
1. 实现顶部导航栏。
2. 实现进度条。
3. 实现 meta chips。
4. 实现 choice / concept / fill_in_blank。
5. 实现 Check Answer / Correct / Incorrect / Retry。
6. 实现参考答案/解析折叠面板。
```

### P0-4：本地状态持久化

```text
1. 设计 answer state key。
2. 答题后写入本地数据库。
3. 加载消息时 merge answer state。
4. 防止刷新回滚。
```

### P1：AI Judge / 收藏 / 分类 / 追问

```text
1. AI Judge 接入项目已有模型系统，仍使用 `.chat` 场景。
2. 收藏与分类先对接已有本地能力或标记待服务端。
3. 追问对话创建普通 chat follow-up，上下文带 question + answer + explanation。
```

### P2：长题型与图片答案

```text
1. short_answer / written / coding。
2. textarea 高度对齐 Web。
3. 图片作为答案。
4. multimodal AI judgment。
```

## 14. 风险与注意事项

### 14.1 不要只照着 DOM 写静态卡片

Quick Check 的核心是状态机和数据链路。只复刻外观但仍用 Fixture 数据，会继续与 Web 偏离。

### 14.2 不要把用户答案写回 AI 原始消息正文

用户答案是本地交互状态，不是 AI 生成内容。应独立持久化或作为 local state merge，不要污染 `message.content`。

### 14.3 不要用 `correctIndex` 作为最终模型

Web 的正确答案是 `correct_answer`。`correctIndex` 只能作为旧数据兼容字段，不能作为新协议主字段。

### 14.4 不要让不同 Quiz 串状态

同一会话内可能多次生成 `q_1`。必须使用 `turnID` / `assistantMessageID` 隔离。

### 14.5 不要在没有真实题目时显示卡片

如果 AI 没有输出结构化题目，应该显示普通回答和解析错误日志，而不是显示假 Quick Check。

## 15. 最终验收标准

实现完成后必须满足：

```text
1. iOS Quick Check 卡片不再出现 Fixture 文案。
2. iOS Quick Check 使用真实 AI 输出题目。
3. iOS 支持 3 题导航、完成数、题号 chips、进度条。
4. iOS 支持 choice、concept、fill_in_blank 三种题型。
5. iOS 支持检查答案、正确/错误反馈、重试、参考答案/解析。
6. iOS 的题干、选项、解析均支持 Markdown 渲染。
7. iOS 答题状态可本地持久化，刷新/切会话后不丢失。
8. iOS 不因 message reload 回到占位卡或清空答案。
9. iOS deepQuestion 数据链路对齐 DeepTutor-main 的 events/result metadata。
10. UI 视觉层级、尺寸、颜色、间距与用户提供的 Web Quick Check DOM 基本一致。
```

本工单只完成需求与技术方案创建，未修改 Swift 业务实现代码。
