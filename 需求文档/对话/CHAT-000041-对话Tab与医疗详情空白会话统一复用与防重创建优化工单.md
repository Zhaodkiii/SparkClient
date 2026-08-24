# CHAT-000041 对话 Tab 与医疗详情空白会话统一复用与防重创建优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | `CHAT-000041` |
| 工单类型 | P1 问题修复 / Chat / Thread 复用 / 幂等创建 |
| 当前阶段 | 待开发 |
| 目标工程 | `SparkClient` |
| 影响入口 | 对话 Tab 自动进入；病历、体检、检查、处方、用药计划、药箱等医疗资料详情快捷对话 |
| 关联工单 | `CHAT-000037`、`CHAT-000038`、`CHAT-000039`、`CHAT-000040` |
| 创建日期 | 2026-08-24 |
| 优先级 | P1 |

## 一、问题背景

当前对话 Tab 和医疗资料详情快捷对话共用“最近 5 分钟活跃 Thread”选择规则：

1. 5 分钟内存在符合条件的 Thread 时，复用最近一条。
2. 没有命中时，创建新 Thread。

该规则只把“活跃时间”作为是否复用的判定条件，没有识别“已创建但用户尚未发送任何消息”的未开始会话。用户创建对话后直接离开，超过 5 分钟再进入，旧空白 Thread 超出活跃时窗，系统会再创建一条新 Thread。重复操作会持续产生多条空白对话。

医疗资料详情入口也使用同一个 5 分钟选择器，因此同样存在该问题：用户从医疗详情创建对话、没有发送消息，超过 5 分钟再从医疗详情进入时，可再次产生空白 Thread。

### 1.1 用户可见现象

- 对话列表出现多条标题相同、没有用户问题与 AI 回答的“新对话”。
- 用户每次隔一段时间进入对话 Tab，都可能多一条空白对话。
- 用户从医疗详情多次点击快捷对话，可能把同类资料分散到多个未开始 Thread。
- 快速连点或多入口近乎同时请求时，“先查找、后创建”之间缺少原子性，理论上仍可同时创建多条 Thread。

## 二、复现步骤

### 2.1 对话 Tab

1. 进入对话 Tab，当前没有 5 分钟内活跃会话。
2. 系统自动创建一条新对话并进入。
3. 不输入、不发送任何消息，直接离开对话。
4. 等待超过 5 分钟。
5. 重新进入对话 Tab。
6. 实际结果：旧空白对话不再命中活跃时窗，系统再创建一条空白对话。

### 2.2 医疗资料详情

1. 进入任一已接入快捷对话的医疗资料详情页。
2. 点击快捷对话，当前没有同成员 5 分钟内活跃 Thread。
3. 系统创建同成员新 Thread，并把当前医疗资料加入 Composer 预览区。
4. 不发送消息，直接离开。
5. 等待超过 5 分钟，再次从相同或其他医疗资料详情页进入快捷对话。
6. 实际结果：原 Thread 超出 5 分钟时窗，再创建一条同成员空白 Thread。

## 三、根因分析

### 3.1 公共选择器只支持时间窗

`RecentActiveChatThreadSelector` 当前只筛选 `latestMessageAt >= now - 5 minutes` 的 Thread。超过 5 分钟的 Thread 无论是否真正开始过对话，都会被排除。

### 3.2 `latestMessageAt` 无法表达“用户是否已开始对话”

`CoreDataChatStore.makeThreadListProjectionItem` 当前使用：

```text
latestMessageAt = latestMessage.createdAt ?? thread.updatedAt
```

新 Thread 没有任何消息时，会使用 `thread.updatedAt`。进入新对话后，系统还可能幂等插入引导卡片 system message。因此仅判断“消息数是否为 0”也不足以稳定识别用户未开始的对话。

### 3.3 创建决策缺少公共语义

对话 Tab 和 `HealthResourceConversationCoordinator` 虽然共用最近活跃选择器，但“命中失败后是否应创建”仍由两个入口分别编排。如果只修复其中一处，两个入口会再次出现规则漂移。

### 3.4 检查与创建不是原子操作

当前流程是先读取 `stateStore.threadItems` 再单独调用 `createThread`。两个并发请求可能都读到“无可复用 Thread”，然后分别创建。医疗详情快速连点、多页面同时发出请求时尤其需要防护。

## 四、目标与非目标

### 4.1 目标

1. 5 分钟内无活跃 Thread 时，检查候选范围内的最近一条 Thread；仅当该 Thread 没有用户发送消息时复用。
2. 对话 Tab 与所有医疗资料详情入口使用同一套 Thread 决策语义。
3. 已开始的历史对话仍保持当前 5 分钟活跃复用规则，不无限期复用旧对话。
4. 并发请求下同一复用范围最多创建一条新 Thread。
5. 医疗资料复用时继续保持成员隔离、资料去重、最多 5 份资料限制和失败回滚语义。
6. 不通过删除用户现有 Thread 来掩盖重复创建问题。

### 4.2 非目标

- 不合并、删除或自动归档已经存在的历史空白 Thread。
- 不修改服务端 Chat API 或消息协议。
- 不改变用户手动点击“新建对话”的明确语义；手动新建仍应创建新 Thread。
- 不自动发送文本或医疗资料，不自动触发 AI 回答。
- 不改变新会话引导卡片的生成和修复规则。
- 不把标题是否为“新对话”作为空白会话判定依据。

## 五、统一业务定义

### 5.1 “未开始会话”定义

本工单统一使用下列领域语义：

```text
isUnstartedConversation = 当前 Thread 不存在未删除的 user role 持久化消息
```

具体规则：

1. 没有任何消息的 Thread 属于未开始会话。
2. 只有系统自动插入的引导卡片 system message，仍属于未开始会话。
3. Composer 中只有未发送文本、附件或医疗资料引用，仍不视为“已开始消息对话”；复用时必须完整保留这些草稿内容。
4. 存在至少一条未删除的 user role 持久化消息后，属于已开始历史对话。即使 AI 请求失败或尚未返回 assistant message，也不得当作空白会话。
5. 系统消息、引导卡片、工具占位和标题文案不能单独作为“已开始”证据。
6. 判断必须来自本地持久化事实，不依赖当前页面是否已加载消息缓存。

### 5.2 复用范围

| 入口 | 候选范围 |
| --- | --- |
| 对话 Tab 自动进入 | 当前账号下、未删除、`scenario == .chat` 的 Thread；保持现有全局成员语义 |
| 医疗资料详情 | 当前账号下、未删除、`scenario == .chat`、`thread.memberID == resource.memberID` 的 Thread |

医疗资料入口禁止复用无成员 Thread 或其他成员 Thread，也禁止为了复用而自动改绑。

### 5.3 “最近对话”定义

1. “最近对话”是候选范围内按 `latestMessageAt` 降序后的第一条 Thread。
2. 如果 `latestMessageAt` 相同，使用 UUID 建立稳定次序，不依赖数组原始顺序。
3. 医疗资料入口的“最近对话”是严格同成员候选范围内的最近 Thread，不是账号全局最近 Thread。
4. 5 分钟内无活跃 Thread 时，只检查这一条最近 Thread；如果它已有 user message，直接新建，不继续向后搜索更早的空白 Thread。

## 六、方案对比

### 6.1 方案 A：延长或取消 5 分钟时窗

做法：把 5 分钟改为更长时间，或始终复用最近 Thread。

优点：

- 改动较小。
- 短期内可降低重复创建频率。

缺点：

- 只是延迟问题，超过新时窗仍会重复创建空白对话。
- 取消时窗会把新问题无限期追加到已开始的老对话，破坏现有上下文边界。
- 不推荐。

### 6.2 方案 B：创建前删除或清理旧空白 Thread

做法：未命中 5 分钟活跃 Thread 时，先删除旧空白 Thread，再创建新 Thread。

优点：

- 列表中最终可以只保留一条新空白 Thread。

缺点：

- 会丢失未发送文本、附件、医疗资料引用、成员绑定或用户自定义外观。
- 需要处理软删除、远端同步、失败回滚与多端冲突。
- 用“删除结果”代替“防止重复创建”，风险较高。
- 不推荐作为本期修复。

### 6.3 方案 C：为 Thread 增加显式草稿状态字段

做法：在 Thread 实体增加 `lifecycleStatus = draft/started` 或等价字段，首条 user message 成功持久化时转为 `started`。

优点：

- 业务语义最明确，查询效率高。
- 适合未来引入草稿箱、自动归档和跨端草稿状态。

缺点：

- 需要 Core Data 模型迁移、Thread 领域模型改造、服务端字段和多端协议对齐。
- 旧数据需要反推并回填状态。
- 对当前本地可直接从消息事实判定的问题而言，实施成本偏高。
- 可作为长期演进方向，不建议本期引入。

### 6.4 方案 D（推荐）：“近期活跃优先 + 最近 Thread 空白检查 + 公共单飞编排”

做法：

1. 列表读模型增加可测试的“是否存在 user 持久化消息”事实，例如 `hasUserMessage`。
2. 公共 Thread 决策器首先查找当前 5 分钟内最近活跃 Thread。
3. 没有近期活跃 Thread 时，取同一候选范围内的最近 Thread，检查它是否 `hasUserMessage == false`。
4. 最近 Thread 没有 user message 时直接复用；已有 user message 或候选范围为空时创建新 Thread。不继续查找更早的空白 Thread。
5. 用公共单飞/串行化编排保证同一复用范围的并发请求共享一次“重新查找 → 必要时创建”结果。

优点：

- 直接解决“超过 5 分钟的空白会话被遗弃”的根因。
- 保留已开始对话的 5 分钟上下文边界。
- 不需要服务端协议和 Core Data 模型迁移。
- 对话 Tab 与医疗详情可复用同一个选择器和并发门。
- 保留 Composer 草稿和医疗资料引用，不需要破坏性清理。

缺点：

- 列表投影需增加用户消息存在性查询或等价聚合信息。
- 需要补充选择器与并发场景测试。

**架构结论：本项目推荐方案 D。**

## 七、推荐方案详细设计

### 7.1 统一决策顺序

对话 Tab 与医疗资料详情必须使用以下同一套主干算法：

```text
加载当前账号 Thread 列表
  ↓
按入口构造候选范围
  ├─ 对话 Tab：当前账号的全部 Chat Thread
  └─ 医疗详情：当前账号 + 严格同成员 Chat Thread
  ↓
是否有 5 分钟内最近活跃 Thread？
  ├─ 是 → 复用该 Thread，decision=recentActive
  └─ 否
      ↓
候选范围内是否有最近 Thread？
  ├─ 否 → 进入新建检查
  └─ 是
      ↓
该最近 Thread 是否没有 user message？
  ├─ 是 → 直接打开该 Thread，decision=latestUnstarted
  └─ 否 → 进入新建检查，不查找更早 Thread
      ↓
检查是否有可用 Chat 模型
  ├─ 否 → 显示现有 AI 设置引导，不创建
  └─ 是
      ↓
在公共单飞门内再次读取并复核候选
  ├─ 复核命中 → 复用
  └─ 仍未命中 → 仅创建 1 条新 Thread
```

优先级必须是“5 分钟内最近活跃”高于“最近 Thread 空白检查”。第二步只能检查最近一条 Thread，不得遍历所有历史会话搜索更早的空白 Thread。

### 7.2 列表读模型扩展

建议在 `ChatThreadListItem` 增加明确的持久化事实，命名可为：

```text
hasUserMessage: Bool
```

具体要求：

1. 数据来自当前账号、当前 Thread 下 `role == user && isTombstone == false` 的持久化消息是否存在。
2. 不通过 `latestMessagePreview`、Thread 标题、`latestMessageAt` 或引导卡片类型反推。
3. 不依赖 `ChatStateStore.messagesByThread`，因为列表中的消息不一定都已加载进内存。
4. 优先使用 `fetchLimit = 1` 的存在性查询或在列表投影加载中做聚合，避免加载所有消息对象。
5. 如果实测显示每 Thread 额外查询成为性能热点，应在同一工单内改为一次性批量聚合，不在 UI 层延迟查询。
6. 本期不建议为此增加 Core Data Thread 字段，避免数据迁移。

### 7.3 公共选择结果

建议将公共选择器从只返回 `UUID?` 扩展为能表达决策原因的结果，例如：

```text
reuse(threadID, reason: recentActive | latestUnstarted)
noReusableThread
```

要求：

- 选择器仍保持为纯逻辑，可注入 `now`，不直接创建 Thread。
- 统一处理 `.chat`、删除状态、可选 memberID 和时间边界。
- 先按 `latestMessageAt` 与 UUID 得到候选范围内唯一的最近 Thread，再检查该 Thread 的 `hasUserMessage`。
- 最近 Thread 已有 user message 时返回 `noReusableThread`，即使更早位置存在空白 Thread 也不复用。
- 旧版本已经产生的多条空白 Thread 不在本期自动删除。

### 7.4 公共单飞与二次复核

为了防止并发请求同时创建，建议在 Chat Application 层增加公共“获取可复用 Thread，必要时创建”编排能力，不把锁放在 SwiftUI View 中。

建议单飞 key：

| 入口 | 建议 key |
| --- | --- |
| 对话 Tab 自动进入 | `accountID + chat + global` |
| 医疗资料详情 | `accountID + chat + memberID` |

编排要求：

1. 同一 key 同时只允许一个“选择/创建”任务运行，其他请求等待并共享结果，或在前一任务完成后重新选择。
2. 真正创建前必须重新加载/复核 Thread 列表，避免使用进入单飞门前的过期快照。
3. 单飞任务失败或取消后必须清理 in-flight 状态，不得永久卡住后续创建。
4. 账号切换时清空旧账号的 in-flight 状态，不跨账号共享 Thread。
5. 入口业务仍自行处理后续差异：对话 Tab 负责呈现；医疗资料入口负责追加 `HealthResourceRef` 与失败回滚。
6. 手动点击“新建对话”不进入该复用门，保持用户明确要求新建的语义。

### 7.5 对话 Tab 接入要求

`ChatConversationListPage.handleInitialAutoNavigationIfNeeded()` 的外层语义保持：

1. Sheet 会话选择模式不自动进入、不自动创建。
2. 当前选中 Thread 存在未发文本草稿时，继续跳过自动导航。
3. 无文本草稿时，调用公共 Thread 决策能力。
4. 命中近期活跃 Thread，或最近 Thread 没有 user message 时，都走自动历史恢复呈现，不调用 `createThread()`。
5. 无近期活跃 Thread，且最近 Thread 已有 user message 或不存在任何 Thread 时，才检查可用模型并创建。
6. 复用最近未开始 Thread 时不得再次调用 `markThreadAsNewlyCreated`，避免重复触发“本次新建”副作用。
7. 进入前继续选中 Thread、预加载消息并锁定底部视口。

修复后的关键场景：

```text
新建 Thread 后未发消息
  ↓
离开 30 分钟 / 1 天 / 更长时间
  ↓
再进入对话 Tab
  ↓
复用原未开始 Thread，Thread 总数不增加
```

### 7.6 医疗资料详情接入要求

`HealthResourceConversationCoordinator.prepare(_:)` 改为消费同一套公共决策：

1. 先按 `request.identity.memberID` 构造严格同成员候选范围。
2. 同成员 5 分钟内存在活跃 Thread 时，保持 `CHAT-000039` 现有逻辑，复用最近活跃 Thread。
3. 无近期活跃 Thread 时，只检查同成员候选范围内的最近 Thread；它没有 user message 时复用，已有 user message 时新建。
4. 复用时按现有规则追加当前 `HealthResourceRef`，保留原文本、附件和已有资料引用。
5. 同一资料已存在时幂等打开，不重复追加。
6. 复用仍需通过成员一致性校验，不允许跨成员。
7. 复用旧 Thread 时不执行新建失败补偿删除；只允许回滚本次追加的资料引用。
8. 无近期活跃 Thread，且最近同成员 Thread 已有 user message 或不存在时，才检查模型并创建同成员 Thread。
9. 从 API Key 设置返回后重试时，必须重新执行整个选择流程，不沿用之前的“无命中”结论。
10. 病历、体检、检查、处方、用药计划和药箱等详情页不各自实现选择逻辑，继续统一通过该 Coordinator。

修复后的关键场景：

```text
成员 A 的医疗详情创建 Thread，只加入资料但未发消息
  ↓
超过 5 分钟后，再从成员 A 的医疗详情进入
  ↓
复用原 Thread，追加/去重资料引用，Thread 总数不增加

超过 5 分钟后，从成员 B 的医疗详情进入
  ↓
不得复用成员 A Thread；检查成员 B 的最近 Thread，无 user message 则复用，否则创建 B Thread
```

## 八、建议代码边界

> 本节仅用于指导后续实现，本工单不修改代码。

| 职责 | 建议位置 | 要求 |
| --- | --- | --- |
| 用户消息存在性投影 | `Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift` | 从本地持久化消息生成 `hasUserMessage` |
| Thread 列表读模型 | `Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift` | `ChatThreadListItem` 承载选择所需事实 |
| 纯选择策略 | `Projects/Features/Chat/Application/RecentActiveChatThreadSelector.swift` 或重命名后的公共选择器 | 近期活跃优先，否则只检查最近 Thread 是否未开始，支持 memberID 过滤 |
| 幂等获取/创建编排 | `Projects/Features/Chat/Application/` 新的公共 Coordinator/UseCase | 单飞、二次复核、返回决策原因 |
| 对话 Tab 接入 | `Projects/Features/Chat/Presentation/ChatConversationListPage.swift` | 只消费统一决策，保留草稿跳过与呈现逻辑 |
| 医疗详情接入 | `Projects/Features/Chat/Application/HealthResourceConversationCoordinator.swift` | 同成员复用后追加资料，无命中才新建 |
| 单元测试 | `Tests/Chat/` | 选择器、成员隔离、并发去重与入口编排测试 |

### 8.1 不建议的实现方式

- 不在 `ChatConversationListPage` 和 `HealthResourceConversationCoordinator` 各复制一份“空白 Thread”筛选代码。
- 不用标题、预览文案或 `updatedAt` 猜测用户是否发过消息。
- 不仅依赖进程内 `newlyCreatedThreadMarkers`；该标记只有 120 秒有效期，且 App 重启后消失。
- 不仅用 SwiftUI `hasLoaded` / `hasHandledInitialAutoNavigation` 防重；它们只能保护单个 View 生命周期。
- 不在复用路径调用 `markThreadAsNewlyCreated`。
- 不自动删除用户已有 Thread。
- 不为快速连点仅增加 UI debounce；debounce 可改善视觉交互，但不能代替业务层幂等。

### 8.2 核心技术决策

| 技术点 | 落地决策 | 原因 |
| --- | --- | --- |
| 空白会话判定 | 持久化层投影 `hasUserMessage` | 不受引导 system message、标题和内存消息缓存影响 |
| 最近会话选择 | 在纯选择器内按 `latestMessageAt` + UUID 稳定选择 | 不依赖列表当前可能包含置顶规则的排序 |
| 5 分钟规则 | 保留 `RecentActiveChatThreadSelector.defaultActiveInterval` | 与 `CHAT-000039` 现有产品语义一致 |
| 决策可观测性 | 返回 `recentActive/latestUnstarted/create` 原因 | 便于页面选择 presentation source、日志和测试断言 |
| 并发防重 | `ChatListViewModel` 内以 `accountID + scope` 为 key 共享 in-flight Task | 该 ViewModel 是对话 Tab 与医疗入口共享的账号级实例 |
| 创建前二次复核 | 单飞 Task 内重载列表后再选择 | 关闭“首次查找”与“实际创建”之间的竞态窗口 |
| 数据迁移 | 不增加 Core Data Thread 字段 | 当前可从 message 事实实时投影，不需要 schema migration |
| 服务端改造 | 不需要 | 本次只改变本地 Thread 选择与创建编排 |

### 8.3 需要改动的代码文件

| 文件 | 必须改动 | 预计改动类型 |
| --- | --- | --- |
| `Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift` | `ChatThreadListItem` 新增 `hasUserMessage` | 读模型字段 |
| `Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift` | 在 Thread 列表投影中查询未 tombstone 的 user message 是否存在 | 本地持久化查询 |
| `Projects/Features/Chat/Application/RecentActiveChatThreadSelector.swift` | 扩展为三级决策，返回 Thread ID 与复用原因 | 纯函数选择策略 |
| `Projects/Features/Chat/Presentation/ChatListViewModel.swift` | 新增预检查、幂等复核/创建、in-flight Task 表及 session reset 清理 | Application 编排与并发门 |
| `Projects/Features/Chat/Presentation/ChatConversationListPage.swift` | 自动入口消费统一决策；新增 `automaticLatestUnstartedThread` 来源 | UI 决策接入 |
| `Projects/Features/Chat/Application/HealthResourceConversationCoordinator.swift` | 改用统一预检查和幂等创建；根据结果区分复用/创建回滚 | 医疗资料编排接入 |
| `Tests/Chat/RecentActiveChatThreadSelectorTests.swift` | 更新 `ChatThreadListItem` 构造，补齐三级决策矩阵 | 单元测试 |
| `Tests/Chat/` 下新建编排测试文件 | 验证同 scope 并发最多创建一次 | 并发/幂等测试 |

不需要改动 `ChatStoreProtocols.swift`、`ChatQueryService.swift`、`LoadChatThreadsUseCase.swift`、Core Data model 文件或服务端 API；`hasUserMessage` 作为既有 `ChatThreadListItem` 投影的新字段随原查询链返回。

### 8.4 读模型与 Core Data 投影落地

#### 8.4.1 `ChatThreadListItem` 改动

```swift
struct ChatThreadListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let thread: ChatThread
    let latestMessagePreview: String
    let latestMessageAt: Date
    let unreadCount: Int
    let latestListImageAttachment: ChatAttachment?

    /// 是否存在未删除的用户持久化消息。
    /// system 引导卡片不影响该值。
    let hasUserMessage: Bool
}
```

当前项目中 `ChatThreadListItem(...)` 只有两个已确认构造点，必须同步更新：

1. `CoreDataChatStore.makeThreadListProjectionItem(...)`。
2. `RecentActiveChatThreadSelectorTests.makeItem(...)`。

#### 8.4.2 Core Data 用户消息存在性查询

在 `makeThreadListProjectionItem(...)` 已有 latest message 和 unread count 投影附近增加：

```swift
let userMessageRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
userMessageRequest.fetchLimit = 1
userMessageRequest.includesPropertyValues = false
userMessageRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
    ownerPredicate(ownerAccountID),
    NSPredicate(format: "threadID == %@", threadID as CVarArg),
    NSPredicate(format: "isTombstone == NO"),
    NSPredicate(format: "role == %@", ChatMessageRole.user.rawValue),
])
let hasUserMessage = try context.fetch(userMessageRequest).isEmpty == false
```

构造投影时回填：

```swift
return ChatThreadListItem(
    id: thread.id,
    thread: thread,
    latestMessagePreview: preview,
    latestMessageAt: latestMessage?.createdAt ?? thread.updatedAt,
    unreadCount: unreadCount,
    latestListImageAttachment: Self.firstListThumbnailAttachment(from: latestMessage),
    hasUserMessage: hasUserMessage
)
```

该查询不加载消息 blocks，不解码附件，命中一条即停止。上线前必须用大量 Thread 数据检查列表加载时间；如果额外的逐 Thread 查询成为热点，在 `loadThreadListItems()` 内一次性批量查出所有 user message 的 `threadID` 集合，再传给投影构造器，不将查询下放到 UI。

### 8.5 公共选择器落地

#### 8.5.1 新增选择结果

```swift
enum ChatAutomaticThreadReuseReason: String, Equatable, Sendable {
    case recentActive
    case latestUnstarted
}

struct ChatAutomaticThreadMatch: Equatable, Sendable {
    let threadID: UUID
    let reason: ChatAutomaticThreadReuseReason
}
```

#### 8.5.2 核心选择算法

`RecentActiveChatThreadSelector` 可保留现有名称以降低调用面改动，但新增的方法必须表达完整三级决策：

```swift
static func reusableThread(
    in items: [ChatThreadListItem],
    within interval: TimeInterval = defaultActiveInterval,
    memberID: Int? = nil,
    now: Date = Date()
) -> ChatAutomaticThreadMatch? {
    guard interval >= 0 else { return nil }

    let eligible = items
        .filter { item in
            item.thread.scenario == .chat
                && item.thread.isDeleted == false
                && item.thread.deletedAt == nil
                && (memberID == nil || item.thread.memberID == memberID)
        }
        .sorted { lhs, rhs in
            if lhs.latestMessageAt != rhs.latestMessageAt {
                return lhs.latestMessageAt > rhs.latestMessageAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }

    guard let latest = eligible.first else { return nil }

    let cutoff = now.addingTimeInterval(-interval)
    if latest.latestMessageAt >= cutoff {
        return ChatAutomaticThreadMatch(
            threadID: latest.id,
            reason: .recentActive
        )
    }

    guard latest.hasUserMessage == false else { return nil }
    return ChatAutomaticThreadMatch(
        threadID: latest.id,
        reason: .latestUnstarted
    )
}
```

该算法的关键不变式：

1. 先筛选候选范围，再选最近一条。
2. 最近一条在 5 分钟内，直接复用，不检查 `hasUserMessage`。
3. 超过 5 分钟后，只检查这一条的 `hasUserMessage`。
4. 最近 Thread 已有 user message 时返回 `nil`，不查找更早空白 Thread。
5. `memberID == nil` 表示对话 Tab 的账号全局范围；非 nil 表示医疗入口的严格同成员范围。

现有 `mostRecentActiveThreadID(...)` 可保留为兼容包装，或在一次改造中替换所有调用；不得同时保留两套产品决策。

### 8.6 复用范围与决策结果类型

```swift
enum ChatAutomaticThreadScope: Hashable, Sendable {
    case global
    case member(Int)

    var memberID: Int? {
        switch self {
        case .global:
            return nil
        case .member(let memberID):
            return memberID
        }
    }
}

enum ChatAutomaticThreadResolution: Equatable, Sendable {
    case reused(threadID: UUID, reason: ChatAutomaticThreadReuseReason)
    case created(threadID: UUID)

    var threadID: UUID {
        switch self {
        case .reused(let threadID, _), .created(let threadID):
            return threadID
        }
    }
}
```

`global` 只用于对话 Tab 自动入口；`member(Int)` 用于医疗资料详情。手动新建不使用该 scope。

### 8.7 `ChatListViewModel` 单飞与创建前复核

`HealthResourceConversationCoordinator` 在 `SignedInMainTabHostView` 中当前是计算属性，每次访问可构造新实例，因此不能把 in-flight Task 表放在该 Coordinator 内。`ChatListViewModel` 由账号运行时共享，且同时持有 session、Thread 列表读取与创建用例，是当前项目最小改动的并发门位置。

#### 8.7.1 in-flight key 与容器

```swift
private struct AutomaticResolutionKey: Hashable {
    let accountID: Int64
    let scope: ChatAutomaticThreadScope
}

private struct AutomaticResolutionFlight {
    let token: UUID
    let task: Task<ChatAutomaticThreadResolution?, Never>
}

private var automaticResolutionFlights: [
    AutomaticResolutionKey: AutomaticResolutionFlight
] = [:]
```

`token` 用于防止较早调用的清理逻辑误删后来新建的 flight。

#### 8.7.2 无副作用预检查

```swift
func reusableAutomaticThread(
    scope: ChatAutomaticThreadScope
) async -> ChatAutomaticThreadMatch? {
    await loadForListIfNeeded()
    return RecentActiveChatThreadSelector.reusableThread(
        in: stateStore.threadItems,
        memberID: scope.memberID
    )
}
```

该方法必须在模型可用性检查之前调用；命中复用 Thread 时，允许用户先打开历史内容，不因当前没有模型而阻塞。

#### 8.7.3 幂等复核并必要时创建

```swift
func resolveOrCreateAutomaticThread(
    scope: ChatAutomaticThreadScope
) async -> ChatAutomaticThreadResolution? {
    guard case .signedIn(let session) = sessionStore.state else { return nil }
    let key = AutomaticResolutionKey(accountID: session.accountID, scope: scope)

    if let flight = automaticResolutionFlights[key] {
        // 等待者不拥有前一请求创建的 Thread。
        // 等待完成后重读列表，并以 reused 身份返回。
        guard await flight.task.value != nil else { return nil }
        await reloadThreads(selectFirstIfNeeded: false)
        guard let match = RecentActiveChatThreadSelector.reusableThread(
            in: stateStore.threadItems,
            memberID: scope.memberID
        ) else { return nil }
        return .reused(threadID: match.threadID, reason: match.reason)
    }

    let token = UUID()
    let task = Task { @MainActor [weak self] () -> ChatAutomaticThreadResolution? in
        guard let self, Task.isCancelled == false else { return nil }

        // 创建前重读本地事实，关闭竞态窗口。
        await self.reloadThreads(selectFirstIfNeeded: false)
        if let match = RecentActiveChatThreadSelector.reusableThread(
            in: self.stateStore.threadItems,
            memberID: scope.memberID
        ) {
            self.stateStore.setSelectedThreadID(match.threadID)
            return .reused(threadID: match.threadID, reason: match.reason)
        }

        guard Task.isCancelled == false else { return nil }
        switch scope {
        case .global:
            guard let threadID = await self.createThread() else { return nil }
            return .created(threadID: threadID)

        case .member(let memberID):
            let title = L10n.text("chat.default_thread_title")
            let threadID = await self.createThread(memberID: memberID, title: title)
            return .created(threadID: threadID)
        }
    }

    automaticResolutionFlights[key] = AutomaticResolutionFlight(
        token: token,
        task: task
    )
    let result = await task.value

    if automaticResolutionFlights[key]?.token == token {
        automaticResolutionFlights[key] = nil
    }
    return result
}
```

实际实现时还必须在 `resetForSessionSwitch()` 中取消并清空 flight：

```swift
for flight in automaticResolutionFlights.values {
    flight.task.cancel()
}
automaticResolutionFlights.removeAll()
```

上述单飞保证的是“同一账号 + 同一 scope”的幂等性。两个同成员医疗请求会共享同一个 Task；对话 Tab 使用 global scope。

必须区分“共享任务结果”与“Thread 创建所有权”：

1. 创建 flight 的发起者可收到 `.created(threadID:)`。
2. 已有 flight 的等待者不直接返回共享 Task 中的 `.created`。
3. 等待者必须在 flight 完成后重载列表并重新选择，以 `.reused(...)` 返回同一 Thread。
4. 这样只有真正创建 Thread 的请求才有资格在后续注入失败时做新建 Thread 补偿删除；其他等待者不得删除。

### 8.8 对话 Tab 关键改造

#### 8.8.1 presentation source 增加细分

```swift
enum ChatPresentationSource: String, Equatable, Sendable {
    case automaticRecentThread
    case automaticLatestUnstartedThread
    case automaticNewThread
    // 其他现有 case 保持

    var isAutomatic: Bool {
        switch self {
        case .automaticRecentThread,
             .automaticLatestUnstartedThread,
             .automaticNewThread:
            return true
        default:
            return false
        }
    }
}
```

`SignedInMainTabHostView` 当前只使用 `source.isAutomatic` 决定全屏对话左上角行为，因此新 case 只需正确归入 `isAutomatic`，不需要改造全屏路由数据结构。

#### 8.8.2 替换初始自动导航主干

```swift
private func handleInitialAutoNavigationIfNeeded() async {
    guard hasHandledInitialAutoNavigation == false else { return }
    hasHandledInitialAutoNavigation = true
    guard shouldSkipInitialAutoNavigation == false else { return }

    let scope = ChatAutomaticThreadScope.global
    if let match = await listViewModel.reusableAutomaticThread(scope: scope) {
        await navigateToThread(
            match.threadID,
            source: presentationSource(for: match.reason)
        )
        return
    }

    guard await detailViewModel.hasAvailableChatModel() else {
        showNoAvailableChatModelAlert = true
        return
    }

    pushAdapter?.requestAuthorizationIfNotDetermined()
    guard let resolution = await listViewModel.resolveOrCreateAutomaticThread(
        scope: scope
    ) else { return }

    let source: ChatPresentationSource
    switch resolution {
    case .reused(_, let reason):
        source = presentationSource(for: reason)
    case .created:
        source = .automaticNewThread
    }
    await navigateToThread(resolution.threadID, source: source)
}

private func presentationSource(
    for reason: ChatAutomaticThreadReuseReason
) -> ChatPresentationSource {
    switch reason {
    case .recentActive:
        return .automaticRecentThread
    case .latestUnstarted:
        return .automaticLatestUnstartedThread
    }
}
```

右上角新建和空列表新建继续使用现有 `createThreadIfAvailable(source:)`，不进入自动复用选择。为减少误用，可在后续实现中将该方法重命名为 `createManualThreadIfAvailable(source:)`，但不是必须项。

### 8.9 医疗资料详情关键改造

`HealthResourceConversationCoordinator.prepare(_:)` 保留请求校验、`HealthResourceRef` 构造和 `prepareReference(...)` 回滚逻辑，只替换 Thread 选择/创建主干：

```swift
let scope = ChatAutomaticThreadScope.member(request.identity.memberID)

if let match = await listViewModel.reusableAutomaticThread(scope: scope) {
    return await prepareReference(
        ref,
        request: request,
        threadID: match.threadID,
        createdByThisRequest: false
    )
}

guard await detailViewModel.hasAvailableChatModel() else {
    return .requiresAISettings
}

guard let resolution = await listViewModel.resolveOrCreateAutomaticThread(
    scope: scope
) else {
    return .failed(message: L10n.text(
        "chat.health_resource_conversation.prepare_failed",
        fallback: "对话准备失败，请稍后重试。"
    ))
}

let createdByThisRequest: Bool
switch resolution {
case .reused:
    createdByThisRequest = false
case .created:
    createdByThisRequest = true
}

return await prepareReference(
    ref,
    request: request,
    threadID: resolution.threadID,
    createdByThisRequest: createdByThisRequest
)
```

关键边界：

1. 预检查命中时不检查模型，直接复用并追加资料。
2. 预检查未命中后才检查模型。
3. 模型检查通过后，单飞 Task 内必须再选一次；如果其他请求已创建 Thread，当前请求改为复用。
4. `createdByThisRequest` 必须来自 `resolution`，不能因“首次预检查未命中”就设为 true。
5. 只有 `.created` 后资料注入失败，才能删除本次新建 Thread；`.reused` 不得删除。
6. 两个同成员请求最终得到同一 Thread，之后分别调用现有 `appendHealthResourceRefs` 幂等追加各自的资料。只有 flight 发起者可能得到 `.created`，等待者必须得到 `.reused`。

### 8.10 不需要改动的展示与路由链

以下逻辑继续复用，不需要重写：

- `navigateToThread(...)` 继续负责选中 Thread、预加载消息和锁定底部视口。
- `onPresentChat(...)` 继续把自动入口交给根级 full-screen cover。
- `SignedInMainTabHostView.chatFullScreenCover(...)` 继续根据 `source.isAutomatic` 显示主页/关闭操作。
- `prepareReference(...)` 继续负责成员校验、资料去重、上限、注入验证和回滚。
- `createThreadIfAvailable(source:)` 继续服务手动新建入口。
- API Key 设置页、推送权限和 ChatView 发送时模型门控保持现有逻辑。

### 8.11 落地后的完整时序

#### 8.11.1 对话 Tab

```text
ChatConversationListPage.task
  → ChatListViewModel.loadForListIfNeeded
  → 草稿保护检查
  → reusableAutomaticThread(.global)
      ├─ recentActive → navigateToThread
      ├─ latestUnstarted → navigateToThread
      └─ nil
          → hasAvailableChatModel
          → resolveOrCreateAutomaticThread(.global)
              → 单飞内 reload + 二次选择
              ├─ reused → navigateToThread
              └─ created → navigateToThread
```

#### 8.11.2 医疗资料详情

```text
HealthResourceConversationCoordinator.prepare
  → 校验 resourceID/memberID/type
  → reusableAutomaticThread(.member(memberID))
      ├─ recentActive/latestUnstarted
      │   → prepareReference(createdByThisRequest: false)
      └─ nil
          → hasAvailableChatModel
          → resolveOrCreateAutomaticThread(.member(memberID))
              → 单飞内 reload + 二次选择
              ├─ reused → prepareReference(false)
              └─ created → prepareReference(true)
```

### 8.12 关键实现检查清单

- [ ] `hasUserMessage` 只统计未 tombstone 的 `.user` 消息。
- [ ] 系统引导卡片不会让 `hasUserMessage` 变为 true。
- [ ] 选择器自行决定最近 Thread，不依赖置顶后的列表首项。
- [ ] 最近 Thread 超过 5 分钟且已有 user message 时，不扫描更早空白 Thread。
- [ ] 医疗入口在选择阶段就使用 memberID 过滤，不先选全局 Thread 再做失败回退。
- [ ] 预检查命中不要求可用模型。
- [ ] 创建前在单飞内执行第二次选择。
- [ ] 只有自动入口进入复用决策，手动新建始终创建。
- [ ] 账号切换时取消并清理所有 in-flight Task。
- [ ] 日志区分 `recentActive/latestUnstarted/create`，不记录消息或医疗内容。

## 九、验收标准

### 9.1 对话 Tab

- [ ] 无可复用 Thread 时，首次进入只创建 1 条新 Thread。
- [ ] 最近 Thread 未发送用户消息，6 分钟后再进入，直接打开该 Thread，Thread 总数不增加。
- [ ] 最近 Thread 未发送用户消息，App 重启且超过 5 分钟后再进入，仍复用该 Thread。
- [ ] 最近 Thread 只有自动引导 system message 时，仍视为无用户发送消息并直接打开。
- [ ] Thread 有未发送草稿时，保留原草稿，不覆盖、不清空。
- [ ] 已存在 5 分钟内活跃 Thread 时，继续优先复用该 Thread，不进入最近 Thread 空白检查。
- [ ] 无 5 分钟活跃 Thread，最近 Thread 已有 user message，但更早 Thread 为空白时，仍创建新 Thread，不复用更早空白 Thread。
- [ ] 所有 Thread 均已有 user message 且超出 5 分钟时，自动创建 1 条新 Thread。
- [ ] 手动点击右上角或空态“新建对话”时，仍明确创建新 Thread，不复用旧空白 Thread。
- [ ] 无可用模型但命中近期活跃 Thread，或最近 Thread 无 user message 时，允许直接进入；只有必须新建时才显示模型设置引导。

### 9.2 医疗资料详情

- [ ] 成员 A 的最近 Thread 无 user message 且超过 5 分钟后，再从成员 A 资料详情进入，复用该 Thread。
- [ ] 成员 A 的未开始 Thread 不得被成员 B 的医疗资料入口复用。
- [ ] 同成员存在 5 分钟内已开始活跃 Thread 时，优先复用该活跃 Thread。
- [ ] 同成员无近期活跃 Thread 时，只检查同成员最近 Thread；无 user message 则复用，已有 user message 则新建。
- [ ] 同成员最近 Thread 已有 user message，但更早 Thread 为空白时，不复用更早 Thread。
- [ ] 复用时追加当前资料引用，原文本、附件和已有资料引用保留。
- [ ] 同一资料连续点击不重复追加，Thread 总数不增加。
- [ ] 当前 Thread 已有 5 份医疗资料时，显示现有上限提示，不创建第二条 Thread 规避上限。
- [ ] 复用旧 Thread 后资料注入失败时，不删除旧 Thread，只回滚本次变更。
- [ ] 病历、体检、检查、处方、用药计划和药箱等已接入页面的行为一致。

### 9.3 并发与账号边界

- [ ] 同一账号同一复用范围内 10 个并发请求，最多创建 1 条 Thread。
- [ ] 成员 A 和成员 B 的并发请求不共享 Thread。
- [ ] 账号切换前后的请求不共享 Thread 或 in-flight 任务。
- [ ] 创建失败或任务取消后可再次正常尝试，不会被残留单飞状态阻塞。

## 十、测试计划

### 10.1 纯选择器测试

扩展 `Tests/Chat/RecentActiveChatThreadSelectorTests.swift` 或在选择器重命名后新建对应测试：

- 5 分钟边界仍命中近期活跃 Thread。
- 301 秒且已有 user message 时不命中。
- 最近 Thread 距今 301 秒、1 天或经过 App 重启，但无 user message 时仍命中。
- 最近 Thread 只有 system 引导消息时，仍视为无 user message。
- 存在近期活跃 Thread 时，直接复用最近活跃 Thread。
- 无近期活跃 Thread 时，按 `latestMessageAt` 与 UUID 稳定得到唯一最近 Thread。
- 最近 Thread 已有 user message，更早 Thread 无 user message 时返回无可复用 Thread。
- 删除 Thread、非 chat Thread 和不同成员 Thread 被正确排除。

### 10.2 编排测试

- 对话 Tab 的最近 Thread 无 user message 时不调用 CreateThreadUseCase。
- 医疗详情的最近同成员 Thread 无 user message 时追加资料但不新建。
- 两个并发医疗请求都未命中时，创建调用计数为 1。
- 第一个请求创建完成后，第二个请求复核并复用第一个 Thread。
- 并发创建的 flight 发起者返回 `.created`，等待者返回 `.reused`，两者 threadID 一致。
- 等待者的资料注入失败时不会删除 flight 发起者创建的 Thread。
- 模型不可用但存在可复用 Thread 时不返回 `requiresAISettings`。
- 只有必须创建时才调用模型可用性检查。

### 10.3 持久化投影测试

- 无消息、只有 system message、存在 user message、user message 已 tombstone 四种数据正确投影 `hasUserMessage`。
- 投影受 owner account 边界限制，不读取其他账号消息。
- 大量 Thread 下列表加载耗时不出现明显回归。

## 十一、日志与可观测性

不记录消息正文、医疗资料摘要、API Key 或其他健康隐私内容。建议统一记录：

- `source=chatTab | healthResource`
- `decision=recentActive | latestUnstarted | create`
- Thread 短 ID
- 医疗入口的 memberID 与 resource type，不记录资料内容
- `singleFlightJoined=true/false`
- 候选 Thread 数量与创建调用次数

建议用于验收的核心指标：

| 指标 | 目标 |
| --- | --- |
| 自动入口产生的空白 Thread 重复创建率 | 0 |
| 同一 memberID 并发医疗快捷对话创建 Thread 数 | 最多 1 |
| 跨成员 Thread 误复用 | 0 |
| 已开始且超时 Thread 误复用 | 0 |

## 十二、实施顺序建议

1. 先为 `ChatThreadListItem` 补充 `hasUserMessage` 持久化投影与测试。
2. 扩展/重命名公共选择器，增加“无近期活跃时只检查最近 Thread”规则和决策原因，保持原 5 分钟测试全部通过。
3. 在 Application 层建立按账号/成员分区的单飞编排和创建前二次复核。
4. 将对话 Tab 自动进入接到统一决策上，手动新建保持不变。
5. 将 `HealthResourceConversationCoordinator` 接到同一决策上，保留成员过滤、资料追加和回滚。
6. 补齐并发、App 重启、超过 5 分钟、系统引导卡片和多成员场景测试。
7. 执行对话 Tab 与全部已接入医疗详情页的真机验收，核对 Thread 总数及日志 decision。

## 十三、完成定义

同时满足以下条件才可将本工单标记为完成：

- 对话 Tab 和医疗资料详情使用同一套“5 分钟内最近活跃优先；无命中时只检查最近 Thread”选择规则。
- 超过 5 分钟的最近 Thread 在无 user message 时可被复用，有 user message 时创建新 Thread。
- 最近 Thread 已有 user message 时，不得跳过它去复用更早的空白 Thread。
- 有 user message 的已开始 Thread 仍受 5 分钟时窗限制。
- 医疗资料入口严格保持账号和成员隔离。
- 并发选择/创建在同一复用范围内幂等，测试证明最多新建 1 条 Thread。
- 手动新建、草稿保留、引导卡片、医疗资料去重/上限/回滚、模型门控和全屏呈现均无回归。
