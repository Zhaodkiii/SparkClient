# DEEPTUTORCHAT-000017 会话自动命名业务流程对齐 DeepTutor-main 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000017 |
| 工单类型 | P0 会话命名业务流程对齐 + 首轮完成后 AI 自动命名 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 关联工单 | `DEEPTUTORCHAT-000003`、`DEEPTUTORCHAT-000004`、`DEEPTUTORCHAT-000005`、`DEEPTUTORCHAT-000012` |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |

## 1. 本工单目标

对齐 DeepTutor-main 的会话自动命名业务流程。

DeepTutor-main 的核心规则：

```text
新对话创建时不立刻用用户首条消息命名。
新对话先使用哨兵标题 "New conversation"。
首轮 user + assistant 完成后，后端调用 LLM 生成短标题。
标题落库后，通过 session_meta(stage="title") 推给前端。
前端收到 session_meta 后更新当前 header 和会话列表。
```

iOS DeepTutorChat 当前偏差：

```text
1. 新建会话默认标题是 "DeepTutor Chat"，不是 "New conversation"。
2. 因为标题不再是哨兵值，后续自动命名逻辑即使实现也无法按 Web 条件触发。
3. iOS 当前本地仓储协议没有 updateConversationTitle 能力。
4. iOS 首轮完成后没有 `_maybe_generate_session_title` 等价流程。
5. iOS 没有 session_meta(title) 等价的本地事件 / reducer。
6. 会话列表和导航标题只显示当前存储 title，不支持“新对话占位态 -> AI 标题”平滑切换。
```

本工单只写需求与技术方案，不直接改 Swift 代码。

## 2. DeepTutor-main 对齐基线

### 2.1 后端统一对话主流程

DeepTutor-main 主站统一对话流程：

```text
Web start_turn，无 session_id
  -> unified_ws.py
  -> turn_runtime.start_turn()
  -> store.ensure_session(payload.session_id)
  -> create_session(title="New conversation")
  -> 执行首轮 user + assistant
  -> done 事件
  -> _maybe_generate_session_title()
  -> LLM 生成短标题
  -> store.update_session_title()
  -> StreamEventType.SESSION_META(stage="title")
  -> Web UnifiedChatContext 更新标题
```

### 2.2 关键文件

| 职责 | 文件 |
| --- | --- |
| WebSocket 入口 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/api/routers/unified_ws.py` |
| 首轮完成后触发标题生成 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py` |
| 标题清洗 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py` |
| SQLite 会话创建默认标题 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/sqlite_store.py` |
| PocketBase 会话创建默认标题 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/pocketbase_store.py` |
| 前端 session_meta 消费 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx` |
| 前端占位标题判断 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/session-title.ts` |
| 标题清洗测试 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/tests/services/session/test_turn_runtime_title.py` |
| unified_ws 标题事件测试 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/tests/api/test_unified_ws_turn_runtime.py` |

### 2.3 标题生成触发时机

DeepTutor-main 在 `done` 事件之后触发命名：

```text
if not is_regenerate and turn_status == "completed":
  await self._maybe_generate_session_title(...)
```

语义：

```text
1. 标题生成属于 post-turn metadata。
2. 不阻塞 assistant 正文保存。
3. 不阻塞 composer 停止计时。
4. WebSocket 在 done 后短暂保持连接，等待 session_meta 标题事件。
```

### 2.4 标题生成触发条件

`_maybe_generate_session_title()` 的关键条件：

```text
1. session_id 非空。
2. session 存在。
3. 当前 title 为空或仍是 "New conversation"。
4. 如果当前 title 不是 "New conversation"，直接 return。
5. 已有首条 user 消息。
6. 已有首条 assistant 消息。
7. 当前不是 regenerate。
```

重要结论：

```text
"New conversation" 是自动命名哨兵值。
如果客户端创建会话时直接写成 "DeepTutor Chat"，就等价于“用户/系统已经命名过”，自动命名不应再覆盖。
```

### 2.5 LLM 标题生成规则

DeepTutor-main 使用当前用户选择模型所在 LLM scope，调用 `deeptutor.services.llm.stream`。

中文 prompt：

```text
你需要为一段对话生成一个简洁的标题。
直接输出标题文本，不要引号、不要 Markdown 格式、
不要末尾标点、不要 "标题：" 这类前缀。
标题控制在 4-10 个汉字以内。
```

英文 prompt：

```text
Generate a concise, descriptive title.
Output only the title as plain text.
No quotes, no markdown, no trailing punctuation, no "Title:" prefix.
Keep it 4-8 words.
```

输入上下文：

```text
first_user: 截断 800 字
first_assistant: 截断 1500 字
temperature: 0.3
max_tokens: 80
timeout: 20s
```

失败兜底：

```text
title = first_user[:50] + ("..." if len(first_user) > 50 else "")
```

### 2.6 标题清洗规则

`_sanitize_session_title(raw)` 会处理：

```text
1. 清除 thinking 标签。
2. 只取第一行。
3. 去除 Markdown 包裹符号。
4. 去除 Title: / title: / 标题：/ 对话标题： 等前缀。
5. 去除中英文引号。
6. 去除末尾标点。
7. 最长 80 字符。
```

### 2.7 推送前端

DeepTutor-main 推送：

```text
StreamEvent(
  type=StreamEventType.SESSION_META,
  source="turn_runtime",
  stage="title",
  content=title,
  metadata={
    "title": title,
    "session_id": session_id
  }
)
```

Web 前端处理：

```text
event.type === "session_meta"
  -> 读取 event.metadata.title
  -> dispatch SET_SESSION_TITLE
  -> 更新 active header
  -> bump sidebar refresh
```

Web done 后连接保持：

```text
POST_DONE_DISCONNECT_DELAY_MS = 15_000
```

原因：

```text
done 后标题模型可能还需要几秒，如果立刻断开，会丢失 session_meta。
```

### 2.8 占位标题显示

Web 占位判断：

```text
const DEFAULT_SESSION_TITLE = "New conversation";

isPlaceholderSessionTitle(title):
  return title.trim() === "" || title.trim() === "New conversation"
```

UI 可将 `"New conversation"` 显示为本地化「新对话」和呼吸态，而不是直接暴露英文哨兵。

## 3. iOS 当前代码事实

### 3.1 会话标题展示

导航标题：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift

.navigationTitle(viewModel.conversation?.title ?? "DeepTutor")
```

会话列表标题：

```text
Text(item.conversation.title)
```

问题：

```text
1. 没有占位标题展示规则。
2. `"New conversation"` 如果写入本地库，会直接显示英文。
3. 没有“新对话”呼吸态。
```

### 3.2 会话创建默认标题

当前 ViewModel：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift

func createConversation(title: String = "DeepTutor Chat", refreshList: Bool = true)

let created = try await createConversation(title: "DeepTutor Chat", refreshList: false)
```

当前仓储：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift

func createConversation(title: String) async throws -> DeepTutorConversation
object.setValue(conversation.title, forKey: "title")
```

问题：

```text
1. 默认标题是 "DeepTutor Chat"，不是 "New conversation"。
2. 创建时就有非哨兵标题，无法对齐 Web 的“首轮后命名”。
3. 发送消息时 prompt 中会带 Current conversation title: DeepTutor Chat，可能污染模型上下文。
```

### 3.3 本地仓储协议缺少更新标题能力

当前协议：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatRepository.swift

func loadConversations()
func loadConversation(id:)
func createConversation(title:)
func deleteConversation(id:)
func loadMessages(...)
func upsertMessage(...)
```

缺少：

```text
func updateConversationTitle(id: UUID, title: String, source: ...)
```

影响：

```text
1. AI 标题生成后无法落库。
2. 会话列表无法从本地库恢复新标题。
3. App 重启后标题会回到创建时标题。
```

### 3.4 首轮完成后没有命名流程

当前发送完成流程：

```text
sendMessage()
  -> sendMessageUseCase(...)
  -> state.phase = .ready
  -> state.isStreaming = false
  -> reloadMessagesAfterGeneration()
  -> refreshConversations(source: "send")
```

问题：

```text
1. 没有判断是否首轮。
2. 没有判断 title 是否仍是哨兵。
3. 没有调用 LLM 生成标题。
4. 没有 update conversation title。
5. 没有本地 session_meta 等价事件。
```

### 3.5 AskUser 恢复也不应触发自动命名

AskUser 提交恢复流程也会走 AI 继续回答：

```text
submitAskUser(...)
  -> state.phase = .resolvingAskUser
  -> sendMessageUseCase.submitAskUser(...)
  -> reloadMessagesAfterGeneration()
```

要求：

```text
1. 如果这是首轮 user + assistant 尚未 completed，而只是 awaiting_user_input，则不能提前命名。
2. AskUser resume 完成同一首轮后，可以触发一次命名。
3. 后续 AskUser 或非首轮不再触发。
```

### 3.6 当前本地 scenario

日志显示当前 DeepTutorChat 使用：

```text
DeepTutorScenarioConstants.scenario
```

用户约束：

```text
模型消费继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor`。
```

会话命名也必须遵守：

```text
1. 使用 AIConfigCenter / ChatOrchestrator 已有 `.chat` 消费能力。
2. 不新增 deepTutor 专属模型场景。
3. 命名是 DeepTutorChat 的业务后处理，不是新模型配置入口。
```

## 4. 当前偏差清单

| 类型 | DeepTutor-main | iOS 当前 | 影响 |
| --- | --- | --- | --- |
| 新会话标题 | `New conversation` 哨兵 | `DeepTutor Chat` | 自动命名触发条件失效 |
| 命名时机 | 首轮 done 后 | 创建时已有固定标题 | 不符合业务流程 |
| 命名模型 | LLM 根据首条 user/assistant 总结 | 无 | 会话列表无语义标题 |
| 标题清洗 | `_sanitize_session_title` | 无 | LLM 输出可能带引号/前缀/标签 |
| 落库 | `update_session_title` | Repository 无更新标题方法 | 标题无法持久化 |
| 前端事件 | `session_meta(stage=title)` | 无本地等价事件 | UI 不能立即刷新标题 |
| 占位显示 | `New conversation` 显示为新对话态 | 直接显示 title | 体验不一致 |
| regenerate | 不触发命名 | 未定义 | 可能误覆盖标题 |
| 手动改名 | 不覆盖 | 未定义 | 后续扩展风险 |
| fallback | 首条 user 截断 50 字 | 无 | LLM 失败会一直停留占位 |

## 5. iOS 目标业务流程

### 5.1 新建会话

目标：

```text
createAndOpenConversation()
  -> createConversation(title: "New conversation")
  -> 本地库保存 "New conversation"
  -> UI 显示本地化「新对话」
  -> 会话列表显示「新对话」占位态
```

要求：

```text
1. 数据库真实值使用 "New conversation"，用于哨兵判断。
2. UI 层用 DeepTutorSessionTitlePresenter 转成本地化显示。
3. 不允许再默认写 "DeepTutor Chat"。
```

### 5.2 首轮发送

目标：

```text
sendMessage()
  -> 发送 user
  -> 生成 assistant
  -> assistant status ready/completed
  -> 判断是否需要自动命名
  -> 生成标题
  -> 清洗标题
  -> updateConversationTitle
  -> 更新 ViewModel.conversation
  -> 更新 conversations 列表
```

### 5.3 命名触发条件

iOS 等价条件：

```text
1. conversationID 存在。
2. conversation.title 为空或等于 "New conversation"。
3. 当前不是 retry/regenerate 分支。
4. 当前 turn 最终状态 completed / ready。
5. 至少已有第一条 user 消息和第一条 assistant 消息。
6. assistant.content 非空，或从 events 可恢复最终正文。
7. 当前没有用户手动改名标记。
8. 同一 conversation 只允许命名一次。
```

需要明确 `首轮`：

```text
首轮 = 可见消息中第一组 user + assistant。
如果会话已有 2 条以上 ready 消息且 title 仍是 New conversation，可补偿生成一次。
```

### 5.4 AskUser / awaiting_user_input 条件

AskUser 场景：

```text
用户：今天的天气怎么样
assistant：需要先问城市 -> awaiting_user_input
用户选择城市
assistant resume -> 最终回答 completed
```

命名要求：

```text
1. awaiting_user_input 阶段不命名。
2. AskUser resume 完成后，如果仍是首轮，允许命名。
3. 标题上下文应使用首条 user + 最终 assistant，而不是中间 ask_user 卡片文本。
```

### 5.5 regenerate / retry 条件

要求：

```text
1. regenerate 不触发自动命名。
2. retry 如果本质是同一首轮失败重试，且会话仍是 "New conversation"，完成后可命名。
3. 已有非哨兵标题时，任何 retry/regenerate 都不覆盖。
```

## 6. iOS 技术方案

### 6.1 新增标题常量与展示 Presenter

建议新增：

```text
DeepTutorSessionTitle.swift
```

职责：

```text
1. 定义 DEFAULT_SESSION_TITLE = "New conversation"。
2. isPlaceholder(title)。
3. displayTitle(title, language) -> "新对话" / "New chat"。
4. titleForPrompt(title) -> 占位标题不注入或注入空值。
```

要求：

```text
1. 哨兵值必须与 DeepTutor-main 完全一致。
2. UI 不直接判断字符串。
3. Prompt 不应把 "New conversation" 或 "DeepTutor Chat" 当作真实标题上下文。
```

### 6.2 扩展 Repository

当前协议需增加：

```text
func updateConversationTitle(
  id: UUID,
  title: String,
  source: DeepTutorConversationTitleSource
) async throws -> DeepTutorConversation
```

建议 source：

```text
enum DeepTutorConversationTitleSource {
  case autoGenerated
  case fallbackFromUserMessage
  case manual
  case repair
}
```

落库要求：

```text
1. 更新 Thread.title。
2. 更新 Thread.updatedAt 或增加 titleUpdatedAt。
3. 不改变消息 updatedAt。
4. 发送 database change event，但需要和 DEEPTUTORCHAT-000012 的 reload 解耦。
```

### 6.3 新增 Title UseCase

建议新增：

```text
GenerateDeepTutorConversationTitleUseCase.swift
```

职责：

```text
1. 判断是否需要命名。
2. 读取首条 user/assistant。
3. 使用项目已有 AIConfigCenter + ChatOrchestrator 走 `.chat` 场景。
4. 调用模型生成标题。
5. 清洗标题。
6. fallback 到首条 user 截断 50 字。
7. 调 Repository 更新标题。
8. 返回 title update result。
```

### 6.4 标题生成 prompt

中文：

```text
你需要为一段对话生成一个简洁的标题。
直接输出标题文本，不要引号、不要 Markdown 格式、
不要末尾标点、不要“标题：”这类前缀。
标题控制在 4-10 个汉字以内。

[用户]
{firstUser clipped 800}

[助手]
{firstAssistant clipped 1500}
```

英文：

```text
You generate a concise, descriptive title for a conversation.
Output only the title as plain text.
No quotes, no markdown, no trailing punctuation, no "Title:" prefix.
Keep it 4-8 words.

[User]
{firstUser clipped 800}

[Assistant]
{firstAssistant clipped 1500}
```

参数：

```text
temperature: 0.3
maxTokens: 80
timeout: 20s
scenario: .chat
tools: disabled
```

注意：

```text
标题生成不应带工具调用，避免为了命名触发 ToolHub。
```

### 6.5 标题清洗

iOS 需要实现与 Web 等价的清洗：

```text
sanitizeSessionTitle(raw):
  remove thinking tags
  first line only
  trim markdown wrappers
  remove prefixes:
    Title:
    title:
    TITLE:
    Title-
    标题：
    标题:
    对话标题：
    对话标题:
  remove quote pairs:
    "" '' “”
  trim trailing punctuation:
    .。!！?？,，;；、
  max length 80
```

如果清洗后为空：

```text
fallback = firstUser prefix 50
```

### 6.6 ViewModel 集成点

建议集成位置：

```text
DeepTutorChatViewModel.sendMessage()
  -> result 完成
  -> state.phase = .ready
  -> state.isStreaming = false
  -> maybeGenerateConversationTitle(...)
  -> reloadMessagesAfterGeneration / refreshConversations
```

更接近 Web 的顺序：

```text
1. assistant 完成后先停止 streaming。
2. UI 可立即恢复 composer。
3. 标题生成作为 post-turn metadata 异步任务。
4. 标题生成完成后只更新 conversation title 和 conversation list row。
5. 不触发消息列表全量 reload。
```

建议：

```text
Task.detached / Task { } 启动标题生成，但需要 generation token 防止旧任务覆盖新会话。
```

### 6.7 本地 session_meta 等价事件

iOS 不一定有 WebSocket `session_meta`，但需要等价本地事件：

```text
DeepTutorConversationTitleUpdatedEvent
  conversationID
  stage = "title"
  title
  source
```

ViewModel 消费后：

```text
1. 如果 activeConversationID 匹配，更新 `conversation?.title`。
2. 更新 conversations 中对应 item.conversation.title。
3. 导航标题刷新。
4. 不 reload messages。
```

### 6.8 会话列表与导航 UI

占位显示要求：

```text
database title: "New conversation"
navigation display: "新对话"
list display: "新对话"
```

呼吸态建议：

```text
1. 首轮 streaming 中，列表 title 显示「新对话」并可有轻微 loading/breathing 样式。
2. 首轮完成后，若标题生成中，仍显示「新对话」。
3. 标题生成完成后，平滑替换为 AI 标题。
```

不要：

```text
1. 直接显示英文 "New conversation"。
2. 直接显示 "DeepTutor Chat"。
3. 创建时用首条用户消息截断命名。
```

### 6.9 Prompt 中 conversationTitle 处理

当前发送时：

```text
let title = conversation?.title ?? "DeepTutor Chat"
conversationTitle: title
```

目标：

```text
let title = DeepTutorSessionTitle.titleForPrompt(conversation?.title)
```

规则：

```text
1. 如果 title 是占位值，prompt 中不应告诉模型 Current conversation title: New conversation。
2. 已生成真实标题后，可以作为上下文。
3. 默认 fallback 不再是 "DeepTutor Chat"。
```

## 7. 数据模型与本地数据库

### 7.1 Conversation 字段

当前：

```text
DeepTutorConversation:
  id
  title
  createdAt
  updatedAt
  isDeleted
  currentModelName
  temperature
  topP
  maxMessages
```

建议扩展：

```text
titleSource: String?
titleUpdatedAt: Date?
titleGenerationStatus: pending | generated | fallback | failed | manual
manualTitleEdited: Bool
```

如果数据库暂不扩字段：

```text
P0 至少要能通过 title == "New conversation" 判断是否待命名。
P1 再补 titleSource / manualTitleEdited。
```

### 7.2 本地存储兼容

历史数据：

```text
1. 旧会话 title="DeepTutor Chat"。
2. 旧会话可能已有多轮消息。
3. 旧会话不应全部被自动重命名，避免用户列表突然变化。
```

兼容策略：

```text
1. 新建会话开始使用 "New conversation"。
2. 旧的 "DeepTutor Chat" 不自动迁移，除非明确执行 repair。
3. 可增加一次性修复入口：仅对 messageCount <= 2 且 title == "DeepTutor Chat" 的会话，允许后台补偿生成标题。
4. 修复必须有日志，不默认静默覆盖。
```

## 8. 日志需求

日志不需要脱敏，按用户要求可记录完整问题和标题，但建议字段化。

### 8.1 创建会话日志

新增/调整：

```text
deeptutor.title.placeholder.created
```

字段：

```text
conversation
rawTitle
displayTitle
source
scenario
```

### 8.2 命名决策日志

新增：

```text
deeptutor.title.maybe.start
deeptutor.title.maybe.skipped
deeptutor.title.context.collected
```

字段：

```text
conversation
currentTitle
isPlaceholder
messageCount
firstUserLength
firstAssistantLength
isRegenerate
phase
skipReason
```

skipReason：

```text
not_placeholder
missing_user
missing_assistant
regenerate
manual_title
already_in_progress
already_generated
awaiting_user_input
```

### 8.3 LLM 标题生成日志

新增：

```text
deeptutor.title.llm.start
deeptutor.title.llm.raw
deeptutor.title.sanitized
deeptutor.title.fallback
deeptutor.title.llm.failed
deeptutor.title.llm.timeout
```

字段：

```text
conversation
model
language
rawTitle
sanitizedTitle
fallbackTitle
durationMs
error
```

### 8.4 落库与 UI 更新日志

新增：

```text
deeptutor.title.persist.start
deeptutor.title.persist.done
deeptutor.title.session_meta.local
deeptutor.title.ui.applied
deeptutor.title.ui.ignored_stale
```

字段：

```text
conversation
oldTitle
newTitle
source
activeConversation
listUpdated
navigationUpdated
durationMs
```

## 9. 验收用例

### 9.1 新建会话显示占位态

步骤：

```text
1. 点击新建 DeepTutorChat 对话。
2. 不发送消息。
```

期望：

```text
1. 本地数据库 title = "New conversation"。
2. 导航标题显示「新对话」或 DeepTutor 默认占位，不显示英文哨兵。
3. 会话列表显示「新对话」。
4. 不显示 "DeepTutor Chat"。
```

### 9.2 首轮完成后自动命名

步骤：

```text
1. 新建会话。
2. 发送：我最近的睡眠情况怎么样？
3. 等待 AI 正式回答完成。
```

期望：

```text
1. assistant 完成后 composer 立即恢复可输入。
2. 标题生成在后置任务执行。
3. 生成短标题，例如「睡眠情况分析」。
4. 本地库 title 更新。
5. 当前导航标题更新。
6. 会话列表对应行更新。
7. 不触发消息列表全量重载。
```

### 9.3 标题生成失败 fallback

步骤：

```text
1. 模拟标题 LLM 超时或失败。
2. 首轮完成。
```

期望：

```text
1. 不一直停留在 "New conversation"。
2. 使用首条 user 前 50 字兜底。
3. 日志出现 deeptutor.title.fallback。
4. UI 和会话列表更新 fallback 标题。
```

### 9.4 非首轮不覆盖标题

步骤：

```text
1. 首轮已生成标题。
2. 发送第二轮问题。
```

期望：

```text
1. 不再次调用标题 LLM。
2. 不覆盖已有标题。
3. 日志出现 skipped not_placeholder 或 already_generated。
```

### 9.5 regenerate 不触发命名

步骤：

```text
1. 对已有消息点击重试/重新生成。
```

期望：

```text
1. 不因为 regenerate 覆盖标题。
2. 如果标题已生成，保持不变。
3. 如果标题仍是哨兵，regenerate 本身也不触发自动命名，除非业务明确把失败首轮重试视为正常首轮完成。
```

### 9.6 AskUser 首轮恢复完成后命名

步骤：

```text
1. 新建会话。
2. 发送：今天的天气怎么样？先问我城市。
3. AI 进入 AskUser。
4. 选择城市并提交。
5. AI 完成最终天气回答。
```

期望：

```text
1. AskUser awaiting_user_input 阶段不命名。
2. resume 完成后触发一次命名。
3. 标题基于首条 user + 最终 assistant。
4. 不基于中间 ask_user 卡片生成「询问城市」这类偏题标题。
```

### 9.7 Prompt 不携带占位标题

步骤：

```text
1. 新建会话，首轮发送。
2. 打印 AI 请求调试信息。
```

期望：

```text
1. Prompt 中不出现 Current conversation title: DeepTutor Chat。
2. Prompt 中不出现 Current conversation title: New conversation，或明确以占位方式忽略。
3. 标题生成后，后续轮次可以携带真实标题。
```

## 10. 实施拆分

### P0-1：哨兵标题与 UI 展示

```text
1. 定义 DeepTutorSessionTitle.DEFAULT = "New conversation"。
2. 新建会话默认写入哨兵标题。
3. UI 显示本地化「新对话」。
4. 移除 "DeepTutor Chat" 作为新建默认标题。
```

### P0-2：Repository 更新标题能力

```text
1. DeepTutorLocalChatRepository 增加 updateConversationTitle。
2. DeepTutorLocalChatStore 实现 Thread.title 更新。
3. ViewModel 能局部更新 conversation 和 conversations。
```

### P0-3：标题生成 UseCase

```text
1. 新增 GenerateDeepTutorConversationTitleUseCase。
2. 实现触发条件。
3. 实现 prompt。
4. 接入 AIConfigCenter / ChatOrchestrator 的 `.chat` 场景。
5. 实现 sanitize + fallback。
```

### P0-4：首轮完成后集成

```text
1. sendMessage 完成后启动 post-turn title task。
2. AskUser resume 最终完成后也复用判断。
3. 不阻塞 composer。
4. 不 reload 消息列表。
```

### P1：手动改名与历史修复

```text
1. 增加 manualTitleEdited 标记。
2. 已手动改名永不自动覆盖。
3. 对旧的 "DeepTutor Chat" 可提供显式 repair 工具。
```

## 11. 风险与注意事项

### 11.1 不要创建时用首条消息命名

DeepTutor-main 的 unified_ws 主路径已经废弃“首条消息截断命名”。旧 `/chat` WebSocket 和 Partner 子系统不是本工单对齐目标。

### 11.2 不要用 "DeepTutor Chat" 作为哨兵

Web 业务哨兵是 `"New conversation"`。如果 iOS 使用不同哨兵，会造成跨端逻辑不一致。

### 11.3 不要阻塞首轮回答完成

标题生成应是 post-turn metadata。用户看到回答完成后，输入区应恢复，不应为了标题多等 20 秒。

### 11.4 不要让标题生成触发工具调用

命名是简单 LLM 总结，不应把 ToolHub 工具开放给标题模型，避免额外成本和不可控行为。

### 11.5 不要覆盖用户手动标题

一旦未来支持手动改名，自动命名必须 short-circuit。

## 12. 最终验收标准

实现完成后必须满足：

```text
1. 新建 DeepTutorChat 会话本地 title 为 "New conversation"。
2. UI 不直接显示英文哨兵，而显示本地化「新对话」占位态。
3. 首轮 user + assistant 完成后自动生成 AI 标题。
4. 标题生成使用项目已有 `.chat` 模型消费，不新增 `.deepTutor` 场景。
5. 标题生成不启用工具调用。
6. 标题清洗规则对齐 DeepTutor-main。
7. LLM 失败时 fallback 到首条 user 前 50 字。
8. 标题更新落库，App 重启后仍保留。
9. 当前导航标题和会话列表行能收到本地 session_meta 等价更新。
10. regenerate、非首轮、非占位标题不会触发覆盖。
11. AskUser awaiting_user_input 不提前命名，resume 完成后可按首轮规则命名一次。
12. 日志能完整追踪 maybe / llm / sanitize / persist / ui applied 全流程。
```

本工单只完成需求与技术方案创建，未修改 Swift 业务实现代码。
