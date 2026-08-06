# DEEPTUTORCHAT-000006 会话列表对齐、日志分析、思考自动折叠与手势收键盘工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000006 |
| 工单类型 | P0/P1 缺陷分析 + DeepTutor Web 对齐补充 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 | `/Users/hua/.codex/attachments/cfd7f3de-03e3-4c96-8b5d-3746353b2851/pasted-text.txt` |
| 创建日期 | 2026-08-05 |
| AI 场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 键盘约束 | 必须复用 iOS 项目已有公共键盘收起能力，不在 DeepTutorChat 内另造私有方案 |

## 1. 本工单目标

本工单解决 4 个新问题：

```text
1. 梳理消息会话列表，检查没有对齐 DeepTutor Web / 项目通用 Chat 的部分，并形成对齐要求。
2. 分析本次日志，梳理当前启动、AIConfig、DeepTutorChat 可观测性问题。
3. AI 回复进入正式回答时，需要自动收起思考部分。
4. 会话列表和消息列表内，键盘收起需要支持联动手势下拉收起键盘，并使用 iOS 通用公共方法实现。
```

本工单与上一份工单的关系：

| 文档 | 已覆盖 | 本工单补充 |
| --- | --- | --- |
| `DEEPTUTORCHAT-000005` | 新建会话入库、发送消息刷新、发送后收键盘 | 继续细化列表 UI 对齐、日志分析、trace 自动折叠、交互式拖拽收键盘 |
| `DEEPTUTORCHAT-000004` | DeepTutor-main 流程、消息卡片、输入区对齐 | 补齐会话列表与 iOS 公共交互一致性 |
| `DEEPTUTORCHAT-000003` | 接入真实 AIConfigCenter `.chat` 模型 | 基于实际日志确认 AIConfig bootstrap 已拉到 `.chat` 模型配置 |

## 2. 当前代码事实

### 2.1 DeepTutor 会话列表页面

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

当前列表入口：

```swift
struct DeepTutorConversationListPage: View {
    @ObservedObject var viewModel: DeepTutorChatViewModel
    @State private var hasLoaded = false
    @State private var showsCreationError = false

    var body: some View {
        List {
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.conversations) { item in
                    Button {
                        viewModel.selectedConversationID = item.id
                    } label: {
                        conversationRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

当前 row：

```swift
private func conversationRow(_ item: DeepTutorConversationListItem) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(item.conversation.title)
            .font(.headline)
        Text(previewText(for: item))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}
```

当前 preview：

```swift
private func previewText(for item: DeepTutorConversationListItem) -> String {
    let preview = item.latestPreview.trimmingCharacters(in: .whitespacesAndNewlines)
    if preview.isEmpty || preview == "…" {
        return "暂无消息"
    }
    return preview
}
```

结论：

```text
会话列表已有基础空态、row、点击打开和 preview 兜底，但还没有达到 DeepTutor Web / 项目通用 Chat 的产品化列表体验。
```

需要继续对齐：

| 类别 | 当前状态 | 需要补齐 |
| --- | --- | --- |
| 列表展示 | 标题 + 一行 preview | 需要时间、生成中/失败状态、选中态、置顶/排序反馈 |
| 空会话 | 可显示“暂无消息” | 需要确认空对话不被过滤，row 仍可打开 |
| 刷新 | `.task` 初载 + `.refreshable` | 需要数据库通知、返回刷新、发送完成刷新都可靠 |
| 手势收键盘 | 当前 DeepTutor 列表未显式接入公共 keyboard dismiss | 需要复用项目通用 `KeyboardDismissHelper` / `.scrollDismissesKeyboard(.interactively)` |
| 视觉层级 | 系统 List 默认样式 | 需要按 DeepTutor Web 消息会话风格调整为更轻、更连续的会话入口 |

### 2.2 DeepTutor 本地会话查询

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

当前查询事实：

```swift
let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
    Self.ownerPredicate(accountID),
    NSPredicate(format: "scenario == %@", DeepTutorScenarioConstants.scenario),
    NSPredicate(format: "isSoftDeleted == NO"),
])
request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
let threads = try context.fetch(request)
```

结论：

```text
本地查询已经按 accountID、scenario、isSoftDeleted 过滤，并按 updatedAt 倒序排序。
```

仍需要验收：

| 验收点 | 原因 |
| --- | --- |
| 新建空 thread 是否一定进入 `threads` | 如果 `toConversation` 或 `latestPreview` 对空消息处理有异常，列表仍可能不显示 |
| `latestPreview` 是否不会因为空消息抛错 | 空对话必须显示“暂无消息” |
| 发送消息后 thread.updatedAt 是否更新 | 否则列表不会置顶 |
| 发送失败后 preview 是否保留 | 否则用户看不到失败会话 |
| 数据库通知是否触发 ViewModel 刷新 | 否则写库成功但 UI 仍旧 |

### 2.3 DeepTutor 消息列表 UIKit 容器

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
```

当前事实：

```swift
let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
cv.translatesAutoresizingMaskIntoConstraints = false
cv.delegate = self
cv.alwaysBounceVertical = true
view.addSubview(cv)
```

普通 Chat 已有对照实现：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListViewController.swift
```

普通 Chat 当前事实：

```swift
cv.keyboardDismissMode = .interactive // 互动模式收起键盘
```

差距：

```text
DeepTutorMessageListViewController 当前没有设置 `keyboardDismissMode = .interactive`。
这会导致用户在消息列表上下拖动时，键盘不能像 iOS 原生聊天一样跟随手势下拉收起。
```

### 2.4 项目已有公共键盘收起能力

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/KeyboardDismissHelper.swift
```

当前事实：

```swift
enum KeyboardDismissHelper {
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    func chatScrollDismissesKeyboardInteractively() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }
}
```

结论：

```text
项目已经存在公共键盘收起方法，DeepTutorChat 必须复用它。
```

不得新增：

```text
DeepTutorKeyboardDismissHelper
DeepTutorDismissKeyboardUtil
DeepTutorUIApplicationResignWrapper
```

除非后续把 `KeyboardDismissHelper` 上移到 `Projects/Core/UI`，否则 DeepTutorChat 应先复用已有公共实现，避免同一 App 内多套键盘策略。

### 2.5 DeepTutor Trace 面板当前实现

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift
```

当前事实：

```swift
struct DeepTutorTracePanelView: View {
    let payload: DeepTutorTraceBlockPayload
    @State private var isExpanded: Bool
    @State private var expandedToolIDs: Set<String> = []

    init(payload: DeepTutorTraceBlockPayload) {
        self.payload = payload
        _isExpanded = State(initialValue: payload.isExpanded)
    }

    private var isStreaming: Bool {
        payload.isStreaming
    }
}
```

当前风险：

```text
isExpanded 只在 init 时读取 payload.isExpanded。
如果消息从“思考/工具调用中”切换到“正式回答中”，payload.isExpanded 后续变化不一定能自动驱动已存在 View 的折叠状态。
```

需要对齐 Web：

```text
自动状态：思考/工具中默认展开，进入正式回答阶段自动收起。
用户状态：用户手动点击后，尊重用户选择，不再被自动状态反复覆盖。
```

## 3. DeepTutor Web 对齐依据

### 3.1 Web AssistantActivity 自动折叠逻辑

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
```

Web 关键逻辑：

```ts
function isFinalAnswerPhase(
  events: StreamEvent[],
  isStreaming: boolean,
  hasFinalContent: boolean,
): boolean {
  if (!isStreaming) return true;
  if (hasFinishMarker(events)) return true;
  const mode = detectStreamingMode(events, hasFinalContent, true);
  if (mode === "responding" || mode === "responded") {
    return !isChatLoopTurn(events);
  }
  return false;
}
```

```ts
const [userOpen, setUserOpen] = useState<boolean | null>(null);
const open = hasTrace && (userOpen ?? !finalPhase);
```

语义总结：

| Web 状态 | Trace 展示 |
| --- | --- |
| 没有 trace | 不展示 trace 面板 |
| 正在思考/探索/工具调用 | 默认展开 |
| 进入正式回答 | 自动折叠 |
| 回答完成 | 保持折叠 |
| 用户点击展开 | 尊重用户选择 |
| 用户点击收起 | 尊重用户选择 |

### 3.2 iOS 需要落地的同构状态机

iOS 不需要照搬 TypeScript，但必须保留同样产品语义：

```text
traceAutoExpanded = hasTrace && !isFinalAnswerPhase
userPinnedExpansion: Bool? = nil
effectiveExpanded = hasTrace && (userPinnedExpansion ?? traceAutoExpanded)
```

状态定义：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `hasTrace` | Bool | 是否存在可渲染 thinking/tool/ask_user/error trace |
| `isStreaming` | Bool | 当前 assistant 是否仍在流式输出 |
| `hasFinalContent` | Bool | assistant 正文是否已有正式回答内容 |
| `hasFinishMarker` | Bool | 是否收到 finish/complete 事件 |
| `isFinalAnswerPhase` | Bool | 是否进入正式回答阶段 |
| `userPinnedExpansion` | Bool? | 用户是否手动固定展开/收起 |
| `effectiveExpanded` | Bool | 最终 UI 是否展开 |

## 4. 会话列表对齐工单

### 4.1 列表信息架构

目标列表 row：

```text
┌─────────────────────────────────────┐
│ DeepTutor Chat                 13:42 │
│ 解释一下胰岛素抵抗，以及如何改善…    │
│ 正在回答 / 已完成 / 失败可重试       │
└─────────────────────────────────────┘
```

当前 row 只有：

```text
标题
preview
```

需要补齐：

| UI 元素 | 必须性 | 说明 |
| --- | --- | --- |
| 标题 | 必须 | `conversation.title` |
| 最新时间 | 必须 | `latestMessageAt ?? conversation.updatedAt` |
| 最新预览 | 必须 | `latestPreview`，空对话显示“暂无消息” |
| 会话状态 | 建议 P1 | streaming/failed/completed，本地如果已有状态即可展示 |
| 未完成提示 | 建议 P1 | 正在回答时显示轻量 loading |
| 选中/按压态 | 必须 | Button row 需有原生按压反馈或自定义高亮 |
| 删除入口 | P1 | 后续补齐 Web delete turn/list delete 语义 |

### 4.2 列表刷新链路

必须覆盖 5 个刷新入口：

| 入口 | 触发 | 预期 |
| --- | --- | --- |
| 首次进入 | `.task` | 加载本地 conversations |
| 手动下拉 | `.refreshable` | 从本地库重新读 |
| 新建会话 | `createAndOpenConversation` | 插入新 row 并可打开 |
| 发送消息 | `upsertMessage` / `refreshConversations(source: "send")` | preview、updatedAt、排序刷新 |
| 返回列表 | `selectedConversationID` 变 nil | 刷新列表，确保最新状态 |

验收用例：

```text
Given DeepTutor 对话列表为空
When 新建一个空对话
Then 列表展示一条“DeepTutor Chat / 暂无消息”
```

```text
Given 已打开会话并发送消息
When 返回会话列表
Then 该会话 row 置顶
And preview 显示最新消息
And 时间为最新消息时间
```

```text
Given AI 正在回答
When 返回会话列表
Then 会话不消失
And row 可显示“正在回答”或至少保持最新 preview
```

### 4.3 列表与普通 Chat 的一致性

普通 Chat 已有：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatConversationListPage.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListViewController.swift
SparkClient/Projects/Features/Chat/Presentation/KeyboardDismissHelper.swift
```

DeepTutorChat 应对齐：

| 能力 | 普通 Chat | DeepTutorChat 目标 |
| --- | --- | --- |
| 列表加载 | 本地/服务端会话列表 | 本地 DeepTutor 会话列表 |
| row 点击 | 打开会话 | 打开 DeepTutor 会话 |
| 键盘收起 | 公共 helper + interactive | 复用同一套 |
| 消息滚动 | UIKit CollectionView | DeepTutor 已使用 UICollectionView，补齐 keyboardDismissMode |
| 下拉刷新 | 支持 | DeepTutor 已支持 refreshControl，需确认与键盘联动不冲突 |

### 4.4 不对齐风险

| 风险 | 用户感知 |
| --- | --- |
| row 信息太少 | 不知道哪个会话是最新 |
| preview 不刷新 | 以为消息没发送 |
| 空对话不展示 | 以为新建失败 |
| 没有时间 | 无法判断会话顺序 |
| 没有交互式收键盘 | 列表/会话页不像 iOS 原生聊天 |
| DeepTutor 与普通 Chat 键盘策略不同 | 同一 App 内体验割裂 |

## 5. 日志分析工单

### 5.1 附件日志观察到的启动链路

附件日志显示启动大链路：

```text
Backend 初始化完成
AppContainer 开始组合各领域 Assembly
AIAssembly 装配 AI 配置与运行时
ChatAssembly 装配聊天核心
启动流程：网络恢复后执行会话恢复
刷新 token
拉取 /api/v1/auth/session/
账号运行时切换到 accountID=265
AIConfigCenter.prewarm
拉取 /api/v1/ai/config/bootstrap/?platform=ios&client_version=1.8.3
医疗首页/成员/任务等领域继续加载
```

已确认：

| 事项 | 日志证据 | 结论 |
| --- | --- | --- |
| Backend 基础设施已初始化 | `Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache` | 网络基础设施可用 |
| AIConfigCenter 已预热 | `AIConfigCenter.prewarm 开始/结束` | 本地 AI 配置缓存已加载 |
| AI bootstrap 已请求 | `/api/v1/ai/config/bootstrap/` | 服务端 AI 多场景配置已拉取 |
| `.chat` 场景存在 | bootstrap body 中包含 `scenarios.chat.default_model` | DeepTutorChat 继续消费 `.chat` 有基础 |
| 当前默认模型 | `doubao-seed-evolving` / display `doubao` | 当前正式 AI 回复应走豆包模型 |
| 模型支持能力 | `supports_reasoning=true`、`supports_tool_use=true`、`supports_deep_reasoning=true` | 支持 thinking/tool trace 对齐 |

### 5.2 附件日志暴露的问题

#### 问题 A：日志缺少 DeepTutorChat 业务段落

附件主要看到：

```text
启动
认证
AIConfig
设备登记
医疗数据
任务同步
版本检查
```

但没有清晰看到：

```text
DeepTutorChat 列表进入
DeepTutorChat loadConversations
DeepTutorChat createConversation
DeepTutorChat openConversation
DeepTutorChat sendMessage
DeepTutorChat streaming event
DeepTutorChat trace auto collapse
DeepTutorChat keyboard dismiss
```

影响：

```text
当用户反馈“会话列表没看到”“发送后消息没更新”“思考没收起”“键盘没收起”时，日志无法快速定位是在 UI、ViewModel、Repository、数据库、AI runtime、还是 keyboard gesture 层失败。
```

#### 问题 B：日志体量过大，业务重点被淹没

附件中医疗数据接口返回了大量完整 JSON，AIConfig bootstrap 也输出完整模型配置。

影响：

```text
1. DeepTutorChat 相关日志很容易被启动/医疗/配置日志淹没。
2. 排查交互问题时，需要大量搜索才能找到关键 phase。
3. 日志文件过大时，移动端调试和上传反馈成本变高。
```

本项目此前用户要求：

```text
日志不需脱敏。
```

因此本工单不要求 DeepTutorChat 业务文本脱敏，但仍建议按模块和 phase 做结构化聚焦。

#### 问题 C：凭据类内容进入原始报文日志

附件中可见：

```text
refresh token
access token
AI api_key
设备标识
完整用户医疗记录 JSON
```

用户此前说“日志不需脱敏”，但工程层面仍应区分：

| 类型 | DeepTutorChat 本地调试是否可记录 |
| --- | --- |
| 用户问题全文 | 可以 |
| 助手回答全文 | 可以 |
| thinking 全文 | 可以 |
| tool input/output | 可以 |
| conversationID/messageID/phase | 可以 |
| access_token/refresh_token/API Key/Cookie/密码/验证码 | 不应进入普通日志 |

说明：

```text
这不是恢复“问题正文脱敏”要求，而是把凭据从普通业务日志里隔离出来。
DeepTutorChat 的问题正文、回答正文、思考正文仍按用户要求允许完整记录。
```

#### 问题 D：AIConfig 日志可确认 `.chat`，但 DeepTutorChat 消费链路未闭环

日志能确认：

```text
scenarios.chat.default_model = doubao-seed-evolving
supports_reasoning = true
supports_tool_use = true
```

但仍需要 DeepTutorChat 自己记录：

```text
DeepTutorChat.resolveModel scenario=chat model=doubao-seed-evolving provider=DOUBAO
DeepTutorChat.send.start conversationID=... messageID=...
DeepTutorChat.stream.reasoningDelta len=...
DeepTutorChat.stream.answerDelta len=...
DeepTutorChat.stream.toolCallStarted tool=...
DeepTutorChat.stream.finish reason=...
```

否则无法证明 DeepTutorChat 正式回答真的消费了项目已有 AIConfigCenter `.chat` 模型。

### 5.3 DeepTutorChat 日志补齐清单

| 阶段 | 日志名 | 必须字段 |
| --- | --- | --- |
| 列表出现 | `deeptutor.list.appear` | accountID、scenario、route |
| 列表加载开始 | `deeptutor.list.load.start` | accountID、scenario |
| 列表加载完成 | `deeptutor.list.load.done` | count、firstConversationID、durationMs |
| row 渲染 | `deeptutor.list.row.render` | conversationID、title、preview、updatedAt |
| 新建开始 | `deeptutor.conversation.create.start` | source、accountID、scenario |
| 新建写库 | `deeptutor.conversation.create.persisted` | conversationID、title |
| 新建刷新 | `deeptutor.conversation.create.refresh` | expectedID、containsCreated、count |
| 打开会话 | `deeptutor.conversation.open` | conversationID、messageCount |
| 发送点击 | `deeptutor.message.send.tap` | conversationID、text、capability |
| 键盘收起 | `deeptutor.keyboard.dismiss` | trigger、method |
| 手势收键盘启用 | `deeptutor.keyboard.interactive.enabled` | surface=list/messageList |
| AI 模型解析 | `deeptutor.ai.resolve` | scenario=chat、provider、model、supportsReasoning、supportsToolUse |
| reasoning delta | `deeptutor.stream.reasoning` | messageID、deltaLen、totalLen |
| answer delta | `deeptutor.stream.answer` | messageID、deltaLen、totalLen |
| tool start | `deeptutor.stream.tool.start` | messageID、toolName、toolCallID |
| tool result | `deeptutor.stream.tool.result` | messageID、toolName、toolCallID、result |
| 正式回答阶段 | `deeptutor.trace.final_phase` | messageID、isStreaming、hasFinalContent、hasFinishMarker |
| trace 自动折叠 | `deeptutor.trace.auto_collapse` | messageID、fromExpanded、toCollapsed、reason |
| trace 用户切换 | `deeptutor.trace.user_toggle` | messageID、expanded |
| 发送完成 | `deeptutor.message.send.done` | userMessageID、assistantMessageID、durationMs |
| 发送失败 | `deeptutor.message.send.failed` | conversationID、error |

## 6. 正式回答时自动收起思考工单

### 6.1 产品目标

用户要求：

```text
ai 回复正式回答的时候，需要自动的收起思考部分。
```

目标体验：

```text
1. AI 正在思考、搜索、调用工具时，思考/工具 trace 默认展开。
2. AI 开始输出正式回答时，思考/工具 trace 自动折叠。
3. 折叠后只保留状态 header，例如“已完成 · 1m 17s”。
4. 用户可以手动点开查看思考/工具详情。
5. 用户手动点开或收起后，当前消息尊重用户选择，不再被 streaming 状态反复覆盖。
```

### 6.2 正式回答阶段判定

iOS 推荐判定：

```text
isFinalAnswerPhase = 
  !message.status.isStreaming
  OR message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  OR events contain finish/complete marker
  OR reducer 已生成 markdown/text block
```

更精确的阶段：

| 信号 | 说明 | 是否 final |
| --- | --- | --- |
| `message.status == .completed` | 回答结束 | 是 |
| `message.content` 已出现正式答案 delta | 正文开始流式 | 是 |
| `toolResult` 后仍没有正文 | 工具刚结束 | 否 |
| `reasoningDelta` | 仍在思考 | 否 |
| `finishMarker` / complete event | 工具链或回答完成 | 是 |
| `askUser` 等待用户 | 不是正式回答 | 否 |

### 6.3 iOS 状态机

推荐状态机：

```text
enum TraceExpansionSource {
    case automatic
    case userPinned
}

struct TraceExpansionState {
    var userPinnedExpansion: Bool?

    func effectiveExpanded(
        hasTrace: Bool,
        isFinalAnswerPhase: Bool
    ) -> Bool {
        hasTrace && (userPinnedExpansion ?? !isFinalAnswerPhase)
    }
}
```

实现要求：

| 要求 | 说明 |
| --- | --- |
| 初始 thinking/tool 阶段展开 | 让用户看到 AI 正在做什么 |
| 进入正式回答自动折叠 | 对齐 Web，减少正文阅读干扰 |
| 用户点击 header 切换 | header 是 disclosure toggle |
| 用户点击后固定本消息状态 | 不再被后续事件自动展开/折叠 |
| 新消息重新使用自动模式 | 每条 assistant message 独立 |

### 6.4 当前 iOS 需要修正的点

当前：

```swift
@State private var isExpanded: Bool

init(payload: DeepTutorTraceBlockPayload) {
    self.payload = payload
    _isExpanded = State(initialValue: payload.isExpanded)
}
```

问题：

```text
SwiftUI @State 初始化后，不会因为 init 参数 payload.isExpanded 变化就自动重置。
如果同一个 TracePanelView 持续存在，正式回答阶段到来时可能仍保持展开。
```

目标：

```text
1. 区分自动展开状态与用户固定状态。
2. 当 payload.isExpanded 从 true 变 false 且用户未手动固定时，自动折叠。
3. 当用户手动展开后，payload 更新不覆盖用户选择。
4. 当 messageID 变化时，重置 userPinnedExpansion = nil。
```

### 6.5 验收用例

```text
Case 1: 思考阶段默认展开
Given AI 正在 reasoningDelta
When TracePanel 出现
Then 思考内容默认展开显示
```

```text
Case 2: 正式回答开始自动折叠
Given TracePanel 当前展开
When assistant content 收到第一段正式回答
Then TracePanel 自动折叠
And 正文回答在下方成为视觉重点
```

```text
Case 3: 用户手动展开后保持
Given 正式回答阶段 TracePanel 已自动折叠
When 用户点击 header 展开
Then TracePanel 展开
And 后续 answer delta 不再自动收起
```

```text
Case 4: 新 assistant 消息重置自动模式
Given 上一条消息用户手动展开了 trace
When 发送下一条消息
Then 下一条消息仍按“思考展开、正式回答收起”的自动规则执行
```

## 7. 会话列表/消息列表手势收键盘工单

### 7.1 产品目标

用户要求：

```text
会话列表内键盘收起需要支持联动手势下拉收起键盘，使用 iOS 通用的公共方法实现。
```

目标体验：

```text
1. 输入框聚焦时，用户在消息列表向下拖动，键盘跟随手势交互式收起。
2. 输入框聚焦时，用户在会话列表滚动或下拉，也能触发系统交互式收键盘。
3. 点击发送仍立即收起键盘。
4. 不新增 DeepTutor 私有 keyboard helper，复用项目公共方法。
```

### 7.2 UIKit CollectionView 实现要求

DeepTutor 消息列表是 UIKit `UICollectionView`：

```swift
let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
```

应对齐普通 Chat：

```swift
cv.keyboardDismissMode = .interactive
```

验收：

```text
Given Composer 输入框聚焦，键盘展开
When 用户向下拖动消息列表
Then 键盘随手势下移
And 松手后按系统行为完成收起或回弹
```

### 7.3 SwiftUI List/ScrollView 实现要求

会话列表是 SwiftUI `List`：

```swift
List { ... }
```

项目已有公共扩展：

```swift
extension View {
    func chatScrollDismissesKeyboardInteractively() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }
}
```

DeepTutor 会话列表应复用：

```swift
List { ... }
    .chatScrollDismissesKeyboardInteractively()
```

或者如果公共方法后续上移到 Core UI：

```swift
List { ... }
    .sparkScrollDismissesKeyboardInteractively()
```

命名以项目最终公共 API 为准，但原则是：

```text
DeepTutorChat 不新增重复 helper。
```

### 7.4 点击发送收键盘

点击发送继续复用：

```swift
KeyboardDismissHelper.dismissKeyboard()
```

触发点：

```text
Presentation 层 Composer onSend wrapper
```

顺序：

```text
校验非空
  -> KeyboardDismissHelper.dismissKeyboard()
  -> onSend()
```

禁止：

```text
在 UseCase、Repository、AI Runtime 中调用 KeyboardDismissHelper。
```

### 7.5 验收用例

```text
Case 1: 消息列表拖拽收键盘
Given DeepTutorChat 会话页输入框聚焦
When 用户在消息列表向下拖动
Then 键盘交互式收起
```

```text
Case 2: 会话列表拖拽收键盘
Given 会话列表存在搜索/输入态或从详情返回键盘未完全收起
When 用户拖动列表
Then 键盘交互式收起
```

```text
Case 3: 点击发送收键盘
Given 输入有效文本
When 点击发送按钮
Then 键盘立即收起
And 消息发送
```

```text
Case 4: 停止生成不误收
Given AI 正在回答
When 点击停止按钮
Then 不强制触发发送式收键盘逻辑
```

## 8. 实施拆分

### 8.1 P0-1 会话列表对齐检查

任务：

```text
1. 检查 DeepTutorLocalChatStore.loadConversations 是否返回空 thread。
2. 检查 latestPreview 空值是否安全。
3. 检查发送消息后 thread.updatedAt 是否更新。
4. 检查 ViewModel.handleDatabaseChange 是否刷新 conversations。
5. 检查 row 是否显示时间、preview、状态。
6. 对照普通 ChatConversationListPage，补齐必要的 iOS 原生交互。
```

验收：

```text
新建空对话显示在列表。
发送消息后 row 置顶。
preview 和时间正确。
返回列表后仍正确。
```

### 8.2 P0-2 日志补齐与问题定位

任务：

```text
1. 为 DeepTutorChat 增加 list/create/open/send/stream/trace/keyboard 的 phase 日志。
2. 确认 AI 模型解析日志显示 scenario=chat。
3. 保留用户问题、回答、thinking、tool 内容的完整业务日志。
4. 将凭据类 token/api_key 从普通原始报文日志隔离。
5. 控制大 JSON 日志对 DeepTutorChat 排障的干扰，至少支持按 module 过滤。
```

验收：

```text
用户反馈列表/消息/trace/键盘问题时，单看 DeepTutorChat module 日志即可定位失败阶段。
```

### 8.3 P0-3 正式回答自动收起思考

任务：

```text
1. 在 reducer 或 payload 中明确 `isFinalAnswerPhase`。
2. `payload.isExpanded` 默认由 `!isFinalAnswerPhase` 决定。
3. TracePanelView 区分 automatic 与 userPinned。
4. 正式回答第一段 content 出现时自动折叠。
5. 用户点击后固定当前消息展开状态。
6. 新消息重置自动模式。
```

验收：

```text
AI 思考时 trace 展开。
AI 正式回答时 trace 自动折叠。
用户可重新展开。
后续 answer delta 不覆盖用户选择。
```

### 8.4 P0-4 交互式手势收键盘

任务：

```text
1. DeepTutorMessageListViewController.collectionView 设置 keyboardDismissMode = .interactive。
2. DeepTutorConversationListPage 的 List 接入公共 `.chatScrollDismissesKeyboardInteractively()`。
3. 点击发送复用 `KeyboardDismissHelper.dismissKeyboard()`。
4. 不新增 DeepTutor 私有 keyboard helper。
5. 如公共 helper 位置不合理，另开基础设施工单把它从 Chat 上移到 Core UI。
```

验收：

```text
消息列表拖拽可交互式收键盘。
会话列表拖拽可交互式收键盘。
发送有效消息立即收键盘。
DeepTutorChat 和普通 Chat 行为一致。
```

## 9. 回归测试矩阵

| 编号 | 场景 | 操作 | 预期 |
| --- | --- | --- | --- |
| T001 | 空会话展示 | 新建对话不发送消息 | 列表显示“暂无消息” row |
| T002 | 列表置顶 | 旧会话发送新消息 | 该会话移动到顶部 |
| T003 | preview 更新 | 发送消息并返回列表 | preview 是最新消息摘要 |
| T004 | 时间更新 | 发送消息并返回列表 | 时间显示最新消息时间 |
| T005 | 日志定位列表 | 进入列表 | 有 `deeptutor.list.load.*` 日志 |
| T006 | 日志定位发送 | 发送消息 | 有 send、AI resolve、stream、done 日志 |
| T007 | AI 场景 | 发送正式消息 | 日志显示 scenario=chat |
| T008 | 思考默认展开 | reasoningDelta 中 | trace 展开 |
| T009 | 正式回答收起 | answer delta 出现 | trace 自动折叠 |
| T010 | 用户重新展开 | 点击 trace header | trace 展开并保持 |
| T011 | 消息列表手势 | 键盘展开时拖消息列表 | 键盘交互式收起 |
| T012 | 会话列表手势 | 键盘展开时拖会话列表 | 键盘交互式收起 |
| T013 | 发送收键盘 | 输入有效文本点击发送 | 键盘立即收起 |
| T014 | 空发送 | 空白内容点击发送 | 不发送，不触发发送式收键盘 |
| T015 | 停止生成 | streaming 中点击停止 | 不误触发发送式键盘逻辑 |

## 10. 关键代码位置

### 10.1 iOS 必查文件

| 文件 | 关注点 |
| --- | --- |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` | 会话列表、row、空态、刷新、SwiftUI List keyboard dismiss |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift` | UICollectionView、diffable、滚动、`keyboardDismissMode` |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift` | trace 展开/折叠状态、用户 toggle |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` | trace block、正式回答阶段、payload.isExpanded |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorTraceFormatter.swift` | trace title、rows、isStreaming、elapsed |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorAssistantResponseView.swift` | thinking 与 markdown 正文分离 |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` | 会话列表查询、latestPreview、updatedAt |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift` | DeepTutorChat 专属日志格式 |
| `SparkClient/Projects/Features/Chat/Presentation/KeyboardDismissHelper.swift` | 公共键盘收起能力 |
| `SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListViewController.swift` | 普通 Chat interactive keyboard 对照 |

### 10.2 Web 必查文件

| 文件 | 关注点 |
| --- | --- |
| `DeepTutor-main/web/components/chat/home/TracePanels.tsx` | `isFinalAnswerPhase`、`AssistantActivity`、自动折叠 |
| `DeepTutor-main/web/components/chat/home/ChatMessages.tsx` | AssistantActivity 在正文前渲染、消息状态 |
| `DeepTutor-main/web/components/common/AssistantResponse.tsx` | 正式回答正文、thinking block 分离 |
| `DeepTutor-main/web/components/chat/home/ChatComposer.tsx` | 发送/停止、输入区状态 |

## 11. 完成定义

本工单完成必须满足：

```text
1. DeepTutor 会话列表的 row 信息、刷新、preview、时间、状态达到可验收标准。
2. 新建空对话和发送后会话都能在列表正确展示。
3. DeepTutorChat 日志能覆盖 list/create/open/send/stream/trace/keyboard 全链路。
4. 日志能确认 DeepTutorChat 使用通用 `.chat` 场景和正式 AI 模型。
5. AI 思考/工具阶段 trace 默认展开。
6. AI 正式回答开始后 trace 自动折叠。
7. 用户手动展开/收起 trace 后，当前消息尊重用户选择。
8. 消息列表拖拽支持交互式收键盘。
9. 会话列表拖拽支持交互式收键盘。
10. 点击发送复用项目公共 `KeyboardDismissHelper.dismissKeyboard()`。
11. 不新增 DeepTutorChat 私有键盘收起工具。
```

## 12. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| TracePanelView 的 `@State` 不跟随 payload 更新 | 正式回答时无法自动折叠 | 增加 automatic/userPinned 状态机 |
| 只用 `message.status == completed` 判断 final | 流式正式回答期间不会提前折叠 | 增加 `hasFinalContent` / finish marker 判断 |
| 用户手动展开后仍被自动折叠覆盖 | 用户无法查看思考详情 | 用户点击后固定当前消息状态 |
| DeepTutorMessageList 未设置 interactive keyboard | 拖拽列表键盘不收 | 对齐普通 Chat 设置 `keyboardDismissMode = .interactive` |
| SwiftUI List 未接公共 dismiss 扩展 | 会话列表无法联动收键盘 | 接入 `.chatScrollDismissesKeyboardInteractively()` |
| 公共 KeyboardDismissHelper 在 Chat Feature 内 | DeepTutor 复用存在模块边界争议 | 后续可另开工单上移到 `Projects/Core/UI` |
| 日志过于庞大 | DeepTutor 问题定位困难 | 增加 DeepTutorChat module/phase 日志 |
| 原始报文包含凭据 | 调试日志传播风险高 | 区分业务内容完整日志与凭据隔离 |

## 13. 建议执行顺序

```text
1. 先补 DeepTutorMessageListViewController 的 interactive keyboard dismiss。
2. 再补 Composer 点击发送复用 KeyboardDismissHelper。
3. 再补会话列表 List 的公共 scroll dismiss。
4. 再修 TracePanel 自动折叠状态机。
5. 再补 DeepTutorChat 专属日志。
6. 最后做会话列表 UI 信息架构对齐和回归验收。
```

原因：

```text
键盘与 trace 折叠是用户当前最直接可感知的问题；
日志补齐能帮助后续定位列表/刷新问题；
列表 UI 对齐依赖数据刷新稳定，适合最后做精细化验收。
```
