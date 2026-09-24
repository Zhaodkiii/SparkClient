# CHAT-000056 医生 Web 消息应用内实时更新需求工单

## 1. 工单信息

| 项目 | 内容 |
| --- | --- |
| 状态 | 需求确认完成，待开发 |
| 目标客户端 | iOS 患者端 SparkClient |
| 关联服务端 | SparkService |
| 核心场景 | 医生在 Web 工作台发送消息后，患者正在 App 内使用时，会话内容直接实时更新 |
| 文档维护方式 | 一问一答；每确认一题，更新本文件的决策记录、业务流程、技术方案与验收标准 |
| 本工单边界 | 完整需求与技术落地规格；本轮只维护本文档，不修改业务代码 |

项目位置：

- iOS：`/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient`
- 服务端：`/Users/hua/Documents/project/Reference/SparkService`

## 2. 问题定义

医生已经可以在医院 Web 工作台向患者会话发送消息，服务端也已经通过 WebSocket 向患者账号发送“会话同步已更新”事件。但患者正在 iOS App 的会话页内时，新消息不会立即显示；只有重新进入会话或触发远端拉取后，消息才可能出现。

本工单要建立以下闭环：

```text
医生 Web 发送消息
  → 服务端保存 ChatMessage
  → 服务端发送 chat.sync.updated
  → iOS 收到实时更新提示
  → iOS 拉取并合并新增消息
  → Core Data 发出数据库变化通知
  → 当前会话 ViewModel 刷新
  → 患者无需退出页面即可看到医生消息
```

## 3. 目标与非目标

### 3.1 本期目标

1. 患者已登录且 App 正在前台时，医生发送的新消息可以自动进入客户端现有消息数据链路。
2. 患者正停留在对应会话页时，无需返回、下拉刷新或重新打开页面即可看到消息。
3. 复用现有 `ChatMessage`、拉取接口、消息合并、Core Data 和页面数据库通知机制。
4. 对重复 WebSocket 通知、连续消息、网络闪断和重连具备可恢复性，不重复显示、不漏消息。
5. 保留服务端数据库与增量同步接口作为消息事实源。

### 3.2 暂不纳入

1. App 位于后台或被系统终止时，通过 APNs 推送唤醒和通知患者。
2. 医生消息的通知文案、声音、角标和系统通知权限策略。
3. 重写现有会话数据模型、Core Data 模型或消息渲染框架。
4. 将 WebSocket 改造成独立于现有同步接口的第二套消息存储协议，除非后续问答明确选择该方案。

## 4. 当前代码事实

### 4.1 服务端已经具备实时通知链路

| 环节 | 当前实现 | 代码位置 |
| --- | --- | --- |
| 医生发送消息 | 创建角色为 `assistant` 的 `ChatMessage`，并写入医生归属信息 | `/Users/hua/Documents/project/Reference/SparkService/hospital_care/services/doctor_message_service.py` |
| 消息保存监听 | `ChatMessage` 保存后，在事务提交成功时通知对应用户 | `/Users/hua/Documents/project/Reference/SparkService/chat_sync/signals.py` |
| 实时事件 | 发布 `chat.sync.updated`，当前包含 `cursor`、`message_ids` | `/Users/hua/Documents/project/Reference/SparkService/chat_sync/events.py` |
| WebSocket | 患者登录后加入 `user_{user_id}` 分组，并接收同步更新事件 | `/Users/hua/Documents/project/Reference/SparkService/chat_sync/consumers.py` |
| WebSocket 地址 | `/ws/chat/sync/` | `/Users/hua/Documents/project/Reference/SparkService/chat_sync/routing.py` |

结论：医生消息保存后，服务端具备向患者账号发出实时“有新数据”提示的能力。

### 4.2 iOS 已经建立 WebSocket，但收到事件后没有拉取消息

| 环节 | 当前实现 | 代码位置 |
| --- | --- | --- |
| WebSocket 客户端 | 连接 `/ws/chat/sync/`，识别 `chat.sync.updated` 并取出 `cursor` | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatRealtimeSyncClient.swift` |
| 实时同步入口 | `startRealtimeSync` 将事件交给 `performRealtimeHintSync(cursor:)` | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` |
| 当前关键行为 | `performRealtimeHintSync` 丢弃服务端 cursor，仅上送本地待同步数据，不执行远端消息拉取 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` |
| 打开会话时同步 | `pullThreadMessagesIncrementalOnOpen(threadID:)` 可以执行会话消息增量拉取 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` |
| 页面刷新 | `ChatDetailViewModel` 监听 `.sparkChatDatabaseDidChange`，数据库合并远端消息后可刷新当前页面 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ViewModels/ChatDetailViewModel.swift` |
| 远端消息入库 | `ChatInboundPipeline.applyRemoteMessages` 负责将服务端消息合并并写入本地仓储 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatInboundPipeline.swift` |

### 4.3 当前不能立即更新的根因

```text
WebSocket 事件到达 iOS
  → ChatRealtimeSyncClient 只把 cursor 交给 ChatSyncEngine
  → ChatSyncEngine 丢弃 cursor，并明确不执行 pull
  → 医生的新消息没有写入 Core Data
  → sparkChatDatabaseDidChange 不会因该远端消息触发
  → ChatDetailViewModel 没有新数据可刷新
```

因此，问题不在消息卡片渲染，也不在医生 Web 发送失败；核心缺口是“实时提示到达后，客户端如何可靠拉取对应的新消息”。

### 4.4 当前生命周期与断线恢复现状

| 场景 | 当前代码事实 | 对本工单的影响 |
| --- | --- | --- |
| WebSocket 断线 | `ChatRealtimeSyncClient` 已按 1、2、4 秒递增并最高 30 秒执行指数退避重连 | 重连能力可复用，不需要新建另一套连接管理器 |
| WebSocket 重连成功 | `.connected` 只把 `reconnectAttempt` 清零，没有通知 `ChatSyncEngine` 执行全局补偿 | 断线期间漏掉的事件不会因为连接恢复而自动拉回 |
| App 回到前台 | `RouteCoordinator → AppLifecycleCoordinator.syncForegroundWorkIfNeeded()` 已统一接管前台恢复 | 现有流程会同步知识、记忆和任务，但没有调用聊天全局增量同步 |
| 网络恢复 | `AppCoordinatorView` 已持有 `NetworkPathMonitor`，知识和记忆同步也已有 `networkRecovered` 触发语义 | 聊天同步尚未接入网络恢复触发，需要复用统一网络状态而不是另建监控器 |
| 首次登录/冷启动 | `AccountSessionRuntime.activateUser` 会停止旧实时连接并重置账号状态，但当前正常账号激活路径没有明确调用 `startRealtimeSync()` | 必须收口“账号准备完成后启动一次实时连接”，否则只有部分账号切换恢复路径会启动 WebSocket |
| 账号切换/登出 | 开始切换和登出时已经调用 `stopRealtimeSync()`；同账号升级或切换失败时会恢复连接 | 账号隔离基础可复用，新增同步任务仍需绑定账号 generation，防止旧任务迟到写入新账号 |

结论：本工单不仅需要恢复“事件到达后拉取”，还需要补齐实时连接的账号启动入口，以及重连、前台恢复、网络恢复三个全局补偿触发点。

## 5. 实现原则

1. **服务端消息是事实源**：医生消息必须先成功落库，再通知客户端。
2. **WebSocket 用于提示变化**：断线可能丢提示，因此不能只依赖单次 WebSocket 数据完成最终一致性。
3. **复用现有拉取与入库链路**：实时更新最终仍进入 `ChatInboundPipeline → Repository/Core Data → ViewModel`。
4. **实时性与可恢复性并存**：前台当前会话追求快速定向刷新；重连、恢复前台时必须能够补齐遗漏。
5. **并发收口**：连续到达多个事件时需要 single-flight、合并提示或串行拉取，避免游标倒退和重复请求。
6. **幂等合并**：重复收到同一 `message_id` 不得生成重复消息。

## 6. 候选技术方案

| 方案 | 实现概要 | 优点 | 代价与风险 |
| --- | --- | --- | --- |
| A. 带 `thread_id` 的定向拉取，并用全局拉取补偿 | 服务端事件补充 `thread_id`；当前打开的会话立即按 thread 增量拉取，其他会话刷新列表状态；重连或回前台执行全局增量补偿 | 当前会话响应快、流量小；保留最终一致性；复用现有会话拉取链路 | 需要扩展服务端事件字段；客户端要维护当前活跃 thread；需定义后台会话未读刷新 |
| B. 每次提示执行全局增量拉取 | 收到任意 `chat.sync.updated` 后，直接按账号 cursor 拉取所有变化 | 无需增加 `thread_id`；所有会话统一更新；逻辑入口集中 | 高频消息会扩大请求和合并范围；需严格处理 cursor、并发提示和重复拉取 |
| C. WebSocket 直接推送完整消息 | 事件携带完整消息 DTO，iOS 收到后直接走入库合并 | 理论显示延迟最低；一次事件即可渲染 | WebSocket 与 REST 形成两套消息协议；重放、鉴权、附件、版本兼容和断线恢复更复杂，仍需补偿拉取 |

已确认采用 **A**：实时事件负责定位会话，现有 REST 增量同步负责取回完整消息；重连和前台恢复再使用全局同步兜底。方案 B、C 不作为本期主链路。

## 7. 一问一答需求确认

### Q1：iOS 收到 `chat.sync.updated` 后，采用哪一种拉取策略？

**为什么要问：** 当前事件只有 `cursor` 和 `message_ids`，没有明确的 `thread_id`。如果每次都全局拉取，实现改动较少但请求范围更大；如果定向拉取当前会话，需要扩展事件字段，却更符合“正在会话页立即更新”的体验。这个选择会决定服务端事件契约、iOS 同步入口、并发控制和后续验收方式。

请选择：

- **A. 定向拉取 + 全局补偿（推荐）**  
  服务端事件增加 `thread_id`。患者正打开该会话时立即拉取此 thread；其他会话先更新未读/列表状态；重连和回到前台时执行全局增量同步补齐遗漏。
- **B. 每次事件都执行全局增量拉取**  
  不扩展 `thread_id`，收到提示后按账号 cursor 拉取全部会话变化，实现入口更统一。
- **C. WebSocket 携带完整消息并直接入库**  
  实时事件直接提供消息 DTO；客户端收到后合并本地，同时保留重连后的 REST 补偿同步。

**确认结果：A. 定向拉取 + 全局补偿。**

落地约束：

1. `chat.sync.updated` 增加 `thread_id`，保留现有 `cursor`、`message_ids`。
2. WebSocket 不携带完整消息正文；完整消息继续通过现有 REST 增量拉取接口获取。
3. 当前活跃会话收到匹配的 `thread_id` 后，执行该 thread 的定向增量拉取。
4. WebSocket 重连成功、App 从非活跃状态恢复前台、网络恢复时，执行账号级全局增量补偿。
5. 定向拉取与全局补偿最终都经过同一套远端消息转换、幂等合并和 Core Data 入库链路。
6. 事件 cursor 只作为“服务端已有更新”的提示；在确认游标属于同一序列前，不直接覆盖客户端已提交的同步 cursor。

### Q2：App 在前台但患者没有停留在消息所属会话时，是否也立即拉取该会话的新消息？

**为什么要问：** Q1 已确定事件会带 `thread_id`。接下来必须确定“应用内实时更新”的作用范围。如果只同步当前打开的会话，流量最小，但患者返回院内名医列表或切换会话时可能暂时看不到最新状态；如果前台所有会话都按事件定向同步，则本地数据和未读状态更及时，但需要维护非当前会话的刷新与提示规则。

请选择：

- **A. App 前台时，所有收到事件的会话都定向拉取（推荐）**  
  当前会话立即显示消息；非当前会话也后台拉取并更新本地消息与可续聊会话映射，但不打断当前页面，也不改变院内名医目录的展示规则。
- **B. 只拉取当前正在打开的会话**  
  非当前会话只记录有更新，等患者打开该会话或触发全局补偿时再拉取正文。
- **C. 仅在“对话”Tab 内执行实时拉取**  
  患者处于首页、健康或其他 Tab 时暂不拉取，回到对话 Tab 后统一同步。

**确认结果：A. App 前台时，所有收到事件的会话都定向拉取。**

落地约束：

1. 实时同步连接属于登录账号运行时，不依赖当前选择的 Tab 或当前是否打开会话详情。
2. App 前台收到合法 `thread_id` 后，对该 thread 执行定向增量拉取，无须先判断是不是当前详情页。
3. 如果事件属于当前会话，Core Data 入库后由现有数据库变化通知驱动 `ChatDetailViewModel` 刷新并直接显示。
4. 如果事件属于非当前会话，消息同样写入本地；不得导航、弹窗或打断当前页面。院内名医目录只更新“可继续咨询”映射，不展示未读、摘要、时间，也不按消息时间重排。
5. 多个不同 thread 的事件可分别排队；同一 thread 的连续事件必须合并或串行，避免并发拉取同一个会话 cursor。
6. App 进入后台后不要求继续维持前台实时拉取；恢复前台时通过全局补偿收敛。

### Q3：全局补偿同步具体在哪些时机触发？

**为什么要问：** 当前项目虽然已有 WebSocket 自动重连和统一前台生命周期，但聊天模块没有在“重连成功、回到前台、网络恢复”后主动拉取。只选择其中一个时机可能继续漏消息；增加固定轮询则更稳，但会增加请求量、电量消耗和同步并发复杂度。

请选择：

- **A. 账号启动、WebSocket 每次连接成功、App 回前台、网络恢复时触发（推荐）**  
  四个事件统一进入同一个账号级全局增量补偿入口；使用 single-flight 合并并发触发，不增加定时轮询。
- **B. 仅 App 回前台和网络恢复时触发**  
  WebSocket 自身重连成功不立即补偿，等待下一个生命周期或网络事件，改动较少但消息恢复可能延迟。
- **C. 采用 A，并增加前台固定周期轮询**  
  除四个事件外，App 前台每隔固定时间执行全局增量同步，容错更强，但请求、电量和游标竞争成本最高。

**确认结果：A. 账号启动、WebSocket 每次连接成功、App 回前台、网络恢复时触发。**

落地约束：

1. 不引入前台定时轮询；WebSocket 提示和四个生命周期事件共同保证实时性与最终一致性。
2. 四个触发点均调用同一个账号级 `syncNowWithPull()` 类能力，不能各自复制“拉线程 + 拉消息”的实现。
3. 同一账号已经有全局补偿任务时，新的触发只复用或标记该任务，不并行运行第二个全局拉取。
4. 全局补偿完成后，使用服务端返回的 cursor 持久化本地；实时事件中的 hint cursor 不直接覆盖本地同步 cursor。
5. 账号退出、账号切换开始或鉴权失效时，取消未完成的聊天补偿任务与重连任务，避免旧账号结果写入新账号存储。

### Q4：同一会话在短时间内连续收到多条医生消息时，客户端如何收口拉取？

**为什么要问：** 当前 `ChatSyncEngine.runSingleFlight(scope: .thread)` 能让同一 thread 复用进行中的拉取任务，但“新事件在该任务即将结束时到达”可能被复用后不再发起第二次请求，造成消息要等下一次补偿才能出现。完全逐条串行拉取则不会漏，但会造成大量重复请求和页面延迟。

请选择：

- **A. 立即拉取 + dirty 重跑一次（推荐）**  
  第一条事件立即开始定向拉取；同一 thread 拉取期间再收到事件，只标记 `dirty`；当前拉取结束后若为 dirty，自动再拉一次。可额外用约 200–300ms 合并同时到达的事件。
- **B. 同一 thread 的每一条事件都进入串行队列**  
  不合并事件，严格一次事件对应一次拉取；实现直观，但连续消息会多次请求同一增量区间。
- **C. 只复用现有 single-flight，不追加重拉**  
  改动最小，但边界时机到达的消息可能要等重连、回前台等全局补偿才出现。

**确认结果：A. 立即拉取 + dirty 重跑一次。**

落地约束：

1. 每个 `thread_id` 维护独立的实时拉取状态：`idle / pulling / dirty`；不得用一个全局布尔值阻塞全部会话。
2. 空闲 thread 收到第一条 hint 后立即启动定向拉取；可将同一主运行循环内约 200–300ms 到达的 hint 合并为一次请求。
3. `pulling` 状态再次收到相同 thread 的 hint 时，不新开并行请求，只把该 thread 标为 `dirty`。
4. 当前定向拉取结束后，如该 thread 为 `dirty`，清除标记并立即补拉一次；补拉期间又有新 hint 时，重复此规则直到没有 dirty 事件。
5. 不同 thread 允许各自独立拉取；账号级全局补偿开始时，继续复用现有 `runSingleFlight` 语义，等待或吸收 thread 级任务，避免 cursor 写入竞争。
6. 消息去重继续以服务端消息 ID 和现有 `ChatInboundPipeline` 合并策略为准，dirty 重拉不得产生重复消息。

### Q5：非当前医生会话收到新消息后，院内名医目录如何提示患者？

**为什么要问：** Q2 已确认非当前会话也会在前台完成本地同步。现有院内名医产品规则明确：目录是医生智能体目录，不是历史会话列表；卡片只显示“开始咨询 / 继续咨询”，不展示最近消息、时间和未读数。当前聊天基础数据层已有 `unreadCount`、最新消息时间和排序能力，但直接套用会破坏已确认的医院目录信息架构。

请选择：

- **A. 静默更新，仅保持“继续咨询”和已咨询优先（推荐）**  
  医生卡不显示红点、未读数、摘要或时间；数据同步后卡片仍为“继续咨询”，已咨询医生保持稳定前置，组内仍按医院后台顺序。
- **B. 医生卡显示一个未读红点**  
  不展示内容摘要，但让患者知道某位医生智能体有新消息；需要新增已读时机和红点清除规则。
- **C. 医生卡按最新消息时间重新排序，并显示时间**  
  即时性最强，但会替代已确认的“已咨询优先、后台顺序其次”规则，使目录接近历史聊天列表。

**确认结果：A. 静默更新，仅保持“继续咨询”和已咨询优先。**

落地约束：

1. 院内名医目录不展示历史消息摘要、时间、未读数或红点；不把目录改造成聊天历史列表。
2. 当前成员的某医生智能体一旦存在可续聊会话，该卡片 CTA 即为“继续咨询”；新医生消息不改变 CTA 文案。
3. 目录排序固定为“已咨询医生稳定前置 → 每组内保持医院后台返回顺序”；不得按最新医生消息重排。
4. 普通聊天列表的 `unreadCount`、`latestMessageAt` 仍可保留在聊天基础数据中，但医院目录不读取或展示这些字段。
5. 目录重新出现、成员切换或 ViewModel 因本地数据库变化重组时，使用最新本地会话映射，不额外请求历史消息摘要。

### Q6：患者正在当前会话阅读历史内容时，医生新消息到达后如何处理滚动？

**为什么要问：** 实时入库后，当前 `ChatDetailViewModel` 已通过数据库通知刷新消息，现有会话渲染层也有“底部锁定 / 用户交互后不强制贴底”的基础能力。但产品仍需明确患者正在向上阅读时是否被拉回底部，以及是否给出“有新消息”的可见入口；这直接影响咨询阅读体验。

请选择：

- **A. 位于底部时自动跟随；阅读历史时不跳动，并显示“有新消息”按钮（推荐）**  
  患者当前在最新消息附近时直接看到医生回复；已向上滚动时保持位置，在会话底部区域显示可点击的“有 N 条新消息”按钮，点击后滚到底部并清除提示。
- **B. 位于底部时自动跟随；阅读历史时不跳动，也不显示提示**  
  最大程度不打扰，但患者必须自己再次滚动到底部才知道有新消息。
- **C. 无论阅读位置都强制滚动到底部**  
  最直接，但会打断患者查阅既往咨询内容，不适合医疗对话。

**确认结果：A. 位于底部时自动跟随；阅读历史时不跳动，并显示“有新消息”按钮。**

落地约束：

1. 新消息写入当前 thread 后，若消息列表已贴近底部且用户没有主动向上阅读，复用现有 `lockBottomViewport` / `scrollToBottomRequestGeneration` 机制自动跟随到底部。
2. 用户向上滚动阅读历史时，远端消息入库和列表增量更新不得改变当前可视锚点。
3. 阅读历史期间每个当前 thread 维护未展示的新消息数量；同一批远端消息合并后按新增条数累加，不按 WebSocket hint 次数累加。
4. 会话底部显示“有 N 条新消息”浮动按钮；点击后显式递增该 thread 的 `scrollToBottomRequestGeneration`，滚至底部并清零计数。
5. 用户手动滚回底部时，同样清零该 thread 的新消息计数；切换 thread、退出详情或账号切换时清理仅用于 UI 的临时计数。
6. SwiftUI 与 UIKit 两条会话渲染实现必须使用同一状态事实，避免一端自动贴底、另一端不显示按钮。

### Q7：患者切换家庭成员时，正在进行或刚完成的实时拉取结果如何处理？

**为什么要问：** WebSocket 按登录账号接收事件，而医院会话和医生目录按 `member_id` 组织。当前代码已在医院会话 scope、创建会话和服务端会话 context 中保留成员归属，但实时拉取是账号级的：如果成员 A 的拉取在切换到成员 B 后才完成，不能让 A 的消息、医生卡状态或“有新消息”按钮出现在 B 的界面。

请选择：

- **A. 消息可按账号落本地，但界面严格按成员隔离（推荐）**  
  已授权账号下的结果可以落入本地 thread；所有 UI 更新都再次校验 `thread.memberID` 与当前成员。成员切换后，旧成员的详情 UI、目录状态和新消息提示全部失效；切回该成员后再展示其已同步内容。
- **B. 成员切换时取消并丢弃所有进行中的定向拉取结果**  
  隔离最直观，但会丢掉已完成网络请求，需要患者后续再次进入会话或等待全局补偿。
- **C. 成员切换后仍在当前页面展示原成员的消息，并提示归属**  
  实现较少，但会混淆当前成员上下文，不适合家庭健康数据场景。

**确认结果：A. 消息可按账号落本地，但界面严格按成员隔离。**

落地约束：

1. 聊天消息仓储继续按登录账号的本地数据域保存；不因 UI 成员切换而物理删除已授权成员的 thread 消息。
2. 任意实时拉取、数据库变化回调、目录重组和“有新消息”计数更新前，均校验目标 `thread.memberID` 是否仍等于当前成员；不相等则不得更新当前 UI。
3. 成员切换时递增成员 UI generation 或取消 UI 层订阅，使旧成员异步回调即使晚到也只能完成数据落库，不能修改当前详情、目录或滚动状态。
4. 当前打开的医院会话若其绑定成员不再是当前成员，禁止继续发送；患者需切回该成员或从当前成员重新进入对应医生卡发起咨询。
5. 切回旧成员后，目录和会话从本地已同步数据重新组合；必要时仍可通过全局补偿确认服务端最新状态。

### Q8：医生智能体下架或医院会话终结时，实时收到的消息与输入框如何处理？

**为什么要问：** 现有医院方案已经定义“智能体下架后历史可读、禁止继续咨询、停止知识库同步”。当前客户端也已有 `canSendMessage` 与 `readOnlyReason` 能力模型，服务端会话 context 能返回是否可发送。但实时消息拉取后，如果不立即刷新这份能力状态，患者可能刚看到医生最后一条消息，输入框却仍短暂可发送，造成无效请求或医疗流程误解。

请选择：

- **A. 拉取消息后立即刷新会话能力，并切换只读（推荐）**  
  已入库的历史和医生最后消息保持可读；若服务端返回智能体下架或会话已结束，马上禁用输入、显示只读原因，停止该会话知识库同步，不再允许新建该智能体咨询。
- **B. 只在患者下次重新进入会话时刷新能力**  
  改动少，但当前页面可能短暂显示错误的可发送状态。
- **C. 下架或终结后直接删除本地会话和医生消息**  
  边界最强，但破坏患者的历史可追溯性，也与既有方案冲突。

**确认结果：A. 拉取消息后立即刷新会话能力，并切换只读。**

落地约束：

1. 医生最后消息、既有系统卡和历史咨询记录继续保留在本地并可查看；不得因下架或终结删除会话内容。
2. 定向拉取完成后，对受影响医院 thread 刷新现有会话 context / capabilities；若 `canSendMessage == false`，当前页面立即禁用输入和发送动作。
3. 输入区域展示服务端的 `readOnlyReason`；已有 `agent_unpublished` 文案和只读能力模型继续复用，不新增平行状态字段。
4. 停止该 thread 的医院知识库 manifest、正文、切块与向量同步，并按既有医院知识库方案处理已缓存内容。
5. 医生目录在下一次本地重组或服务端目录刷新后不再提供该下架智能体的新咨询入口；已存在会话仅保留“历史可读”。
6. 服务端仍是发送权限的最终裁决。客户端只读切换用于及时反馈，不能代替服务端拒绝终结/下架会话的发送请求。

### Q9：实时定向拉取失败或会话 cursor 失效时，如何恢复？

**为什么要问：** 当前同步引擎会在成功拉取后保存每个 thread 的消息 cursor，但没有针对实时拉取的失败队列或“仅重置一个 thread cursor”的专用恢复路径。网络抖动、5xx、超时不应让客户端跳过消息；反过来，任何失败都清空全账号同步状态会造成不必要的全量拉取和重复合并。

请选择：

- **A. 保留本地数据与 cursor；分类重试，失效时仅重置该 thread（推荐）**  
  网络/超时/5xx：保留 cursor 和本地消息，按有限退避重试，并继续接受后续 hint 与全局补偿；服务端明确返回 cursor 无效时，只清除该 `thread_id` 的消息 cursor，再从该会话首屏安全拉取并幂等合并。
- **B. 失败后不自动重试，等待下一次实时事件或生命周期补偿**  
  实现最少，但医生消息可能长时间不可见。
- **C. 任意失败都清空全账号聊天 cursor 并全量重拉**  
  恢复路径简单，但流量大、影响所有会话，也扩大重复合并风险。

**确认结果：A. 保留本地数据与 cursor；分类重试，失效时仅重置该 thread。**

落地约束：

1. 网络不可用、超时、连接中断、服务端 5xx 时：保留已落库消息和原有 cursor；该 thread 保持 dirty，采用有限指数退避重试，并允许后续 hint 或全局补偿合并触发。
2. 每个 thread 的自动重试次数与等待时间必须有上限；达到上限后不弹出全局错误，不影响其他会话，等待下一次网络恢复、前台恢复或新的 hint 再尝试。
3. 服务端明确返回“cursor 无效 / 已过期 / 不属于该会话”时：只清除该 `thread_id` 的消息 cursor，从该会话首屏重新拉取；消息仍通过现有 ID 幂等合并，不能先删除本地历史。
4. 未明确为 cursor 错误的 4xx（鉴权失效、成员撤权、会话不存在）不得重置 cursor 重试；按既有鉴权/成员/只读能力处理。
5. 账号级全局 cursor 与其他 thread 的消息 cursor 不受单会话失败影响。
6. 每一次失败、重试、cursor 重置和恢复成功都记录最小诊断字段：账号哈希、thread 短 ID、触发源、错误分类、尝试次数、耗时和最终结果；日志中不写消息正文。

### Q10：医生 Web 消息与患者正在进行的 AI 流式回复同时存在时，如何呈现？

**为什么要问：** 当前患者端的 AI 回复由 `MessageRunActor` 创建本地流式消息并持续更新；医生 Web 消息则由服务端以独立 `ChatMessage` 写入，并携带医生归属。实时同步将两者汇入同一个 `ChatInboundPipeline`。如果没有明确规则，可能出现医生消息被延迟、错误中断患者主动发起的 AI 回复，或两条消息在视觉上无法分辨。

请选择：

- **A. 两者并存，不自动取消 AI 流式回复（推荐）**  
  医生消息一到即按服务端时间插入，并突出“真人医生”身份；患者主动发起的 AI 回复继续完成。最终以服务端消息 ID、服务端时间和既有幂等合并规则收敛排序。
- **B. 医生消息到达即中断当前 AI 流式回复**  
  医生消息优先级最高，客户端停止当前流；需要处理服务端已在生成的 AI 消息和中断文案。
- **C. AI 回复结束后再显示医生消息**  
  视觉顺序简单，但会延迟真人医生消息，不符合“实时到达”的目标。

**确认结果：A. 两者并存，不自动取消 AI 流式回复。**

落地约束：

1. 医生消息收到实时 hint 后立即走定向拉取，不等待本地 AI 流式 run 结束。
2. 患者主动发起的 AI 流式回复继续完成；医生消息到达不得调用 AI run 的取消逻辑，也不得将流式消息标记为失败。
3. 两类消息使用不同的身份信息呈现：医生消息以服务端 `ChatMessageAttribution` / sender snapshot 的真人医生信息为准；AI 消息继续显示医生智能体身份，不能混淆为真人消息。
4. 最终排序以服务端确认后的消息 ID、服务端创建/更新时间和现有消息合并策略为准；本地流式临时消息在服务端确认后幂等替换或合并，不因医生消息插入生成重复卡片。
5. 当患者正在阅读历史时，医生消息和 AI 流式更新均遵循 Q6 的滚动策略；“有新消息”计数按实际新增消息累加。
6. 若医生消息导致会话 capabilities 变为只读，按 Q8 禁用后续输入，但不取消已经在运行的 AI 流式回复；其最终是否成功仍由既有服务端 run 结果决定。

### Q11：“应用内直接实时更新”的验收时限和超时反馈如何定义？

**为什么要问：** “立即更新”需要可测试的时间边界。链路包含医生消息落库、事务提交、WebSocket 推送、iOS 定向拉取、Core Data 合并和 UI 渲染；不定义时限，就无法判断是正常网络延迟、后台重试，还是实时链路失效。同时，过早展示“同步失败”会让患者误以为消息丢失。

请选择：

- **A. 前台正常网络目标 3 秒内显示；超时静默重试并记录诊断（推荐）**  
  从服务端事务提交到当前会话出现消息，目标 P95 ≤ 3 秒；超过目标不向患者展示技术错误，继续按 Q9 重试和补偿，仅记录诊断指标。
- **B. 前台正常网络目标 1 秒内显示；超过 1 秒显示“正在同步”状态**  
  体验感更强，但移动网络波动下容易频繁出现状态提示，且需要新增 UI。
- **C. 不设置量化目标，只要最终同步成功即可**  
  实现与验收最宽松，但无法判断实时能力是否真正达标。

**确认结果：A. 前台正常网络目标 3 秒内显示；超时静默重试并记录诊断。**

落地约束：

1. 计时起点为服务端医生消息事务成功提交；终点为 iOS 当前会话的消息已经完成本地合并并进入可渲染 UI 状态。
2. 正常前台网络下目标为 P95 ≤ 3 秒；该目标适用于已登录、WebSocket 连接可用、服务端无故障的主链路，不将 App 后台、网络断开或服务端异常计入主链路 SLA。
3. 超过 3 秒时不向患者展示“同步失败”或技术异常；继续执行 Q9 的有限重试和 Q3 的全局补偿。
4. 超时、失败与恢复成功进入诊断指标；若当前会话最终同步成功，患者只看到正常消息，不看到历史技术状态。
5. 验收测试必须分别覆盖：网络正常、WebSocket 断线重连、App 前后台切换、网络恢复、连续医生消息、成员切换和智能体只读切换。

### Q12：实时链路记录哪些诊断数据，如何保护医疗内容？

**为什么要问：** Q11 的 3 秒目标需要可观测数据来定位到底慢在服务端提交、WebSocket、客户端拉取、入库还是 UI 刷新。医院消息属于敏感健康信息；如果日志写入消息正文、医生建议或患者身份信息，会引入不必要的泄露风险。

请选择：

- **A. 记录脱敏链路指标与最小定位日志，不记录正文（推荐）**  
  用 `message_id`、`thread_id` 短 ID/哈希、账号哈希、事件时间、触发源、耗时、错误分类、重试次数和最终状态关联链路；服务端和客户端均不写消息正文、附件内容、患者姓名、病历字段。
- **B. 只记录匿名聚合时延，不记录单条链路日志**  
  隐私边界最小，但出现个别医生消息未到达时很难定位。
- **C. 保存完整 WebSocket payload 和消息正文用于排查**  
  定位最快，但不符合医疗消息最小化记录原则，风险最高。

**确认方向：C. 需要保存完整 WebSocket payload 和消息正文用于排查。**

该选择**不能作为普通应用日志方案直接落地**。医生消息、患者提问、附件引用和 sender 信息均可能构成敏感医疗信息；将原文写入 iOS 控制台、崩溃收集、第三方分析平台、标准服务端日志或任意可全文检索日志，会扩大副本、访问面和泄露风险。服务端 `ChatMessage` 本身已保存原始业务消息，诊断应优先以消息 ID 从受控业务数据恢复，而非复制到普通日志。

在用户明确需要保留原文诊断能力的前提下，后续实现必须满足：

1. 原文仅进入医院自管的加密诊断审计库，或从已授权的 `ChatMessage` 业务存储按 `message_id` 受控回放；不得写入客户端持久化日志、Crashlytics、分析 SDK、stdout 或通用日志平台。
2. 原文与结构化链路指标分离存储；常规监控仍只使用脱敏的 thread/message 短 ID、耗时和错误分类。
3. 每次原文查看必须要求医院授权角色、记录查看人、用途、时间、目标消息与导出行为；默认不允许批量导出。
4. 访问端必须使用服务端短时授权查询；iOS 只上传/展示排查结果，不长期缓存完整 payload。
5. 留存期、可访问角色、脱敏展示、导出限制和审计责任仍需由 Q13 明确；未确认前不得实现任何原文诊断写入。

### Q13：完整 payload / 消息正文用于诊断时，存放在哪里、谁能查看？

**为什么要问：** 原文诊断的价值在于定位单条消息，但复制到普通日志会失去医院对病历类内容的最小访问控制。当前服务端已拥有 `ChatMessage` 业务事实源，因此可以在需要排查时按消息 ID 受控查询；也可以另建加密审计副本。两者的存储成本、留存、权限和泄露面不同。

请选择：

- **A. 仅医院服务端受控审计查询；iOS 不保存原文（推荐）**  
  原文继续由 `ChatMessage` 业务库或其加密审计副本保存；只有医院指定审计/运维角色通过短时授权按 message/thread 查询。客户端和常规日志只保留脱敏关联 ID。
- **B. 服务端受控审计查询 + iOS 本地加密诊断缓存**  
  离线排查更方便，但患者设备增加一份医疗正文副本，需要额外的设备加密、TTL、登出清除和越狱风险控制。
- **C. 写入现有通用服务端日志和客户端日志**  
  接入最快，但无法满足医疗内容最小副本和最小访问面要求，不建议采用。

**架构收口：A. 仅医院服务端受控审计查询；iOS 不保存原文。**

说明：用户已确认需要完整 payload / 正文诊断能力，但未继续选择存放位置。为使工单可落地且不把医疗正文扩散到日志，按最小副本原则收口为 A：正文继续以服务端 `ChatMessage` 业务数据为事实源，排查时按授权、按消息 ID 受控查询；不再复制到 iOS 日志或通用日志。若医院后续要求改变存放方式，必须另开安全评审工单，不在开发时自行放宽。

### 问答收口状态

Q1–Q12 已按用户回答确认；Q13 因涉及医疗正文副本，按最小副本原则采用服务端受控查询的架构安全默认。当前没有阻塞开发的待确认问题；后续只在出现新的实现边界或验收异常时补充。

## 8. 已确认业务流程

```text
前置条件：患者已登录，医生与患者共享同一服务端会话

1. 医生在 Web 工作台输入并发送消息。
2. 服务端校验医生对会话的操作范围。
3. 服务端在事务内创建医生消息并提交。
4. 事务提交后，chat_sync 向患者账号发送包含 thread_id、cursor、message_ids 的 chat.sync.updated。
5. iOS ChatRealtimeSyncClient 收到事件，解析为结构化实时同步提示并交给 ChatSyncEngine。
6. ChatSyncEngine 以事件 thread_id 为同步范围；只要 App 在前台，无论当前页面在哪里，都立即调用现有 thread 增量拉取能力。
7. 同一 thread 已有拉取任务时，新事件合并到该 thread 的待处理状态，不并行拉取同一个 thread。
8. 当前会话与非当前会话都进入相同本地入库链路；区别只发生在入库后的 UI 响应。
9. ChatInboundPipeline 解析、去重并合并消息。
10. Repository 将消息写入 Core Data，并发出数据库变化通知。
11. ChatDetailViewModel 判断变化是否属于当前 thread，重新读取消息状态。
12. 如果变化属于当前会话，会话页插入医生消息，并保持既有消息排序、滚动与医生身份展示规则。
13. 如果变化属于非当前会话，只完成本地消息与会话映射更新，不打断当前页面；院内名医目录不展示未读、摘要、时间，也不按最新消息重排。
14. 账号启动、WebSocket 每次连接成功、App 回前台、网络恢复时，均触发同一账号级全局增量补偿，补齐断线或后台期间遗漏的全部会话变化。
15. 同一 thread 连续事件按“立即拉取 + dirty 重跑一次”收口，直到该 thread 没有新的待处理 hint。
16. 非当前医生会话入库后，院内名医目录静默更新“继续咨询”映射与已咨询稳定分组；不显示未读、红点、时间或消息摘要。
17. 当前会话处于底部时自动跟随医生消息；阅读历史时保持锚点并显示“有 N 条新消息”，点击或手动回到底部后清除。
18. 成员切换期间，旧成员结果可以完成账号级入库，但绝不改变新成员的详情、目录、滚动状态或新消息计数。
19. 医院会话终结或智能体下架时，已同步消息仍可读；实时拉取后立即刷新 capabilities，禁用输入并停止该会话知识同步。
20. 定向拉取失败和 cursor 失效时，保留本地消息与 cursor，分类重试；明确 cursor 失效只重置对应 thread 后重新拉取。
21. 医生消息与 AI 流式回复并存，医生消息实时拉取展示，不自动取消 AI；按服务端消息身份、时间和 ID 收敛排序。
22. 前台正常网络的消息可见目标为 P95 ≤ 3 秒；超时静默执行后台重试与补偿，不向患者展示技术错误。
23. 实时链路需要保留完整 payload / 正文的诊断能力；原文不得进入普通日志，具体受控存放与查看策略按 Q13 的确认结果执行。
```

## 9. 基础验收标准

最终数值和边界将在问答完成后补齐。当前基础标准如下：

1. 患者正在目标医生会话页，医生 Web 发送一条文本消息后，患者无需重新进入页面即可看到该消息。
2. 连续发送多条消息时，客户端不丢失、不重复，顺序与服务端确定顺序一致。
3. 同一个实时事件重复到达时，本地只保留一条对应消息。
4. WebSocket 短暂断开后恢复，遗漏消息可以通过补偿同步出现。
5. 患者正在其他医生会话时，不得把消息插入错误的 thread。
6. 患者切换登录账号或退出登录后，旧账号事件不得进入当前账号会话。
7. 实时拉取失败不删除现有消息；网络恢复后可以重试并收敛到服务端状态。
8. 现有患者发送消息、AI 流式回复、打开会话增量同步和本地消息渲染不得回归。

## 10. 技术落点草案

> 本节仅记录可能修改位置，不代表当前已经授权或完成代码实现。

### 服务端

- `chat_sync/events.py`：给 `chat.sync.updated` 增加 `thread_id`，并保留 `cursor`、`message_ids`；不下发完整消息正文。
- `chat_sync/signals.py`：从已保存消息获得 thread 信息，并保持事务提交后再通知；同一批消息跨多个 thread 时按 thread 分组通知。
- `chat_sync/consumers.py`：继续只负责鉴权、用户分组和事件转发，不在 Consumer 内查询消息正文。
- 现有消息增量拉取接口：继续作为完整消息 DTO 的事实来源。

### iOS

- `ChatRealtimeSyncClient.swift`：把当前仅传递 `String? cursor` 的回调改为结构化 `ChatSyncHint(threadID, cursor, messageIDs)`；连接层不直接查询 Core Data 或更新 UI。
- `ChatRealtimeSyncClient.swift`：在 `.connected` 状态转换成功后回调“连接已恢复”；断开、鉴权失效和重连退避仍复用现有实现。
- `ChatSyncEngine.swift`：收到任意前台会话 hint 后，按 `threadID` 调用会话增量拉取；在现有 `SyncScope.thread` single-flight 基础上，按 Q4 增加 pending/dirty 重拉语义；保留独立的账号级全局补偿 single-flight。
- `ChatSyncSupervisor.swift`：新增账号启动、连接成功、前台恢复和网络恢复的统一补偿入口；对页面暴露稳定同步生命周期，避免多个页面重复启动 WebSocket 或并行拉取。
- `ChatInboundPipeline.swift`：继续负责统一远端消息转换、幂等合并和本地落库。
- `ChatDetailViewModel.swift`：继续通过数据库变化通知刷新当前 thread，不直接消费 WebSocket 消息 DTO。
- `HospitalAgentDirectoryViewModel.swift` 与 `LoadHospitalAgentDirectoryUseCase.swift`：实时入库后重新组合“当前成员 + 医生智能体”的最近可续聊会话；目录展示必须按 Q5 确认结果，而不是直接复用普通聊天列表的 `unreadCount` 与最新时间排序。
- `ChatStateStore.swift`、`ChatSwiftUIConversationView.swift` 与 `ConversationMessageListViewController.swift`：复用现有底部锁定、用户滚动状态和滚到底部 generation；增加 per-thread 的“有新消息”计数与按钮，不能因远端消息到达强制改变用户的历史阅读位置。
- `MemberContextStore.swift`、`ChatDetailViewModel.swift` 与 `HospitalAgentDirectoryViewModel.swift`：成员变化后使旧成员的 UI 异步回调失效；实时入库和目录/会话 UI 映射规则按 Q7 确认，不能只按登录账号判断。
- `FetchHospitalConversationContextUseCase.swift`、`HospitalKnowledgeModels.swift` 与 `ChatView.swift`：实时消息合并后按 Q8 刷新 `canSendMessage`、`readOnlyReason`、知识同步开关；复用既有“下架历史可读、输入禁用”的能力模型，不另建状态字段。
- `ChatSyncEngine.swift`、`ChatStoreProtocols.swift`、`CoreDataChatRepository.swift` 与 `CoreDataChatStore.swift`：按 Q9 增加 per-thread 实时拉取失败状态、有限退避和仅清除指定 `thread_id` 消息 cursor 的能力；不得在单会话失败时清空账号级聊天 cursor。
- `MessageRunActor.swift`、`ChatInboundPipeline.swift`、消息合并策略与会话渲染层：按 Q10 收口医生服务端消息与本地 AI 流式消息的并存/中断规则；医生归属以服务端 attribution 为准，不能被普通 AI 助手样式覆盖。
- `ChatRealtimeSyncClient.swift`、`ChatSyncEngine.swift`、`ChatSyncSupervisor.swift` 与日志/指标基础设施：按 Q11 采集事务提交至事件到达、拉取完成、Core Data 合并和 UI 可见的链路耗时；超时处理不改变 Q9 的后台重试语义。
- 服务端 `doctor_message_service.py`、`chat_sync/signals.py`、`chat_sync/events.py` 与 iOS 聊天同步链路：按 Q12/Q13 接入端到端关联 ID、脱敏日志和指标；完整正文只允许走受控审计查询或加密审计库，禁止写进应用日志或分析事件。
- `AccountSessionRuntime.swift`：账号准备完成后先启动一次聊天实时连接，再触发账号启动补偿；账号切换开始和登出继续停止连接，并取消旧账号未完成同步任务。
- `AppLifecycleCoordinator.swift`：在现有 `syncForegroundWorkIfNeeded()` 中接入聊天全局补偿，不另建前台通知监听器。
- `AppCoordinatorView.swift` / 现有网络状态编排：将“网络从不可用恢复为可用”转交 `ChatSyncSupervisor` 的全局补偿入口；不得在聊天模块内部创建第二个 `NWPathMonitor`。

### 10.1 核查：医院会话右上角“新建对话”是否丢失医生智能体绑定

#### 核查结论

**当前工作区源码未发现该问题。** 当前实现已经具备医院智能体继承分支；若运行中的 App 仍创建出默认模型会话，优先怀疑运行的不是当前代码版本、医院 scope 解析失败/依赖未注入，或日志与请求实际走入了普通会话分支。该结论基于静态代码核查，仍需按下方验收步骤在真机或模拟器验证。

#### 已核对的真实链路

| 步骤 | 当前代码事实 | 代码位置 |
| --- | --- | --- |
| 右上角入口 | `plus.bubble` 调用 `createThreadInsideCurrentChat()` | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 医院身份判定 | 新建前读取缓存 scope；未确定时调用 `resolveHospitalScope`，再通过服务端 conversation context 回源；解析失败直接阻断，不静默降级为普通会话 | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 医院会话新建 | 判定为 `.hospital(scope)` 后，调用 `createHospitalThreadInsideCurrentChatIfNeeded(scope:from:)`，而不是 `listViewModel.createThread()` | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 智能体继承 | 医院创建方法明确使用 `scope.agentID` 作为 `agentID` 参数；当前成员来自既有成员选择上下文 | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 服务端创建请求 | `ResolveOrCreateHospitalConversationUseCase` 调用 `HospitalCareRemoteAPI.createConversation(agentID:memberID:)`；成功后立即保存新 thread 的 `HospitalConversationScope(threadID, agentID, memberID, hospitalID)` | `SparkClient/Projects/Features/HospitalCare/Application/ResolveOrCreateHospitalConversationUseCase.swift` |
| 默认模型路径 | 仅在 scope 为 `.ordinary` 或没有医院上下文时，才调用普通 `listViewModel.createThread()` | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 新 thread 初始化 | 内部切换后重置医院身份判定为 `.undetermined`，再按新 thread 重新解析 scope、加载医院 context 和知识库能力 | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |

#### 与所述现象的对照

```text
当前医生智能体会话
  → 点击右上角“新建对话”
  → 解析 HospitalConversationScope
  → createConversation(agent_id = scope.agentID, member_id = 当前成员)
  → 服务端创建医院 Thread
  → scopeStore 立即记住新 Thread 的同一 agentID
  → ChatView 原地切换新 Thread
  → 新 Thread 重新回源医院 context
```

该链路不应创建默认模型普通 Thread。

#### 若运行时仍复现，按此顺序定位

1. 确认 App 二进制包含当前 `ChatView.swift` 的医院分支，而非旧构建或未合入分支的版本。
2. 查看日志 `chat.detail.new_thread_button.create_success`：医院链路必须带 `hospital=1`；没有该标记表示已走普通新建分支。
3. 记录创建请求 `/api/v1/hospital-care/conversations/` 的 body，验证 `agent_id` 是否等于原会话 `HospitalConversationScope.agentID`，`member_id` 是否等于当前选择成员。
4. 若日志显示 scope 解析为 `.ordinary`：检查 `hospitalCare` 依赖是否注入、`HospitalConversationScopeStore` 是否存在旧会话映射，以及 `fetchConversationContext(threadID:)` 是否正确返回医院 context。
5. 若请求带正确 `agent_id` 但返回的 thread 仍是默认模型：服务端应检查创建会话接口是否忽略 `agent_id`；这属于服务端会话创建契约问题。

#### 当前无需新增修复代码；防回归验收

| 验收场景 | 预期 |
| --- | --- |
| 从已加载 scope 的医生智能体会话点击新建 | 请求使用原 `agent_id`；新 thread 为医院会话，且保留同一医生智能体 |
| 清除本地 scope 缓存后，从历史医生会话点击新建 | 客户端通过服务端 context 回源识别医院会话；仍使用原 `agent_id` |
| 服务端 context 回源失败 | 阻断新建并提示“无法确认院内会话身份”；绝不创建普通默认模型 thread |
| 普通对话点击新建 | 仍走普通模型线程创建，不被医院逻辑影响 |
| 新医院 thread 创建后 | 不插入普通科普引导卡；重新加载医院能力和关联知识库 scope |

## 11. 风险记录

1. **游标语义不清**：事件 cursor 与拉取接口 cursor 如果不属于同一序列，不能直接拿事件 cursor 覆盖本地 cursor。
2. **提示风暴**：医生连续发送消息可能产生多次事件，需要合并而不是无限并发拉取。
3. **先通知后可读**：必须确保事务提交后再发通知，避免 iOS 收到提示却暂时拉不到消息。
4. **多设备同步**：同一患者多个设备在线时，每台设备都要独立按自己的本地 cursor 收敛。
5. **账号与成员边界**：WebSocket 按登录账号分组，会话展示还需校验患者成员和 thread 归属。
6. **消息排序**：医生消息、AI 消息和患者本地待发送消息并存时，不能仅按客户端接收时间排序。
7. **页面滚动干扰**：患者正在阅读历史内容时，新消息到达不应强制抢占滚动位置，已由 Q6 明确“底部自动跟随、历史阅读显示新消息按钮”。
8. **医院新建继承回归**：任何 scope 解析失败都不得静默落入默认模型创建路径；需保留并覆盖第 10.1 节的验收场景。

## 12. 决策记录

| 序号 | 决策项 | 结论 | 状态 |
| --- | --- | --- | --- |
| Q1 | 实时事件后的拉取策略 | 定向拉取 + 全局补偿；事件增加 `thread_id` | 已确认 |
| Q2 | App 前台但不在目标会话时的同步范围 | 前台所有收到事件的会话都按 `thread_id` 定向拉取 | 已确认 |
| Q3 | 全局补偿同步触发时机 | 账号启动、WebSocket 每次连接成功、App 回前台、网络恢复；不定时轮询 | 已确认 |
| Q4 | 同一 thread 连续事件的拉取收口 | 立即拉取 + dirty 重跑一次；同一运行循环约 200–300ms hint 可合并 | 已确认 |
| Q5 | 非当前医院会话的新消息目录提示 | 静默更新；只保持“继续咨询”和已咨询稳定前置 | 已确认 |
| Q6 | 当前会话阅读历史时的新消息滚动行为 | 底部自动跟随；历史阅读不跳动并显示“有 N 条新消息”按钮 | 已确认 |
| Q7 | 成员切换期间实时拉取结果的归属与展示 | 消息可按账号落库；界面严格按当前成员隔离 | 已确认 |
| Q8 | 智能体下架或会话终结后的实时表现 | 历史可读；拉取后立即刷新能力并切换只读、停止知识同步 | 已确认 |
| Q9 | 实时拉取失败与 cursor 失效恢复 | 保留本地数据与 cursor；分类重试；cursor 失效时仅重置对应 thread | 已确认 |
| Q10 | 医生消息与 AI 流式回复并发时的行为 | 两者并存；医生消息即时展示，不自动取消 AI 流式回复 | 已确认 |
| Q11 | 前台实时显示时限与超时反馈 | 前台正常网络 P95 ≤ 3 秒；超时静默重试并记录诊断 | 已确认 |
| Q12 | 实时链路诊断数据与医疗内容保护 | 需要完整 payload / 正文诊断能力，但不得写入普通日志 | 已确认，受 Q13 存储策略约束 |
| Q13 | 原文诊断的存放位置与查看边界 | 服务端按授权从 `ChatMessage` 受控查询；iOS 与通用日志不保存原文 | 架构安全默认 |

## 13. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-09-02 | 需求确认收口：Q13 按最小副本原则采用服务端受控审计查询；工单状态更新为“需求确认完成，待开发” |
| 2026-09-02 | 记录 Q12：需要完整 payload 与正文用于诊断；明确其不得进入普通日志、崩溃分析或第三方埋点，必须通过医院受控审计能力访问；加入 Q13 |
| 2026-09-02 | 确认 Q11：前台正常网络 P95 ≤ 3 秒，超时静默重试并记录诊断；加入 Q12，确认端到端观测与医疗内容最小化记录边界 |
| 2026-09-02 | 确认 Q10：医生消息与 AI 流式回复并存，医生消息即时展示且不自动取消 AI；加入 Q11，明确实时链路的量化验收和超时反馈 |
| 2026-09-02 | 将 Q9 结果落实为分类重试和 thread 级 cursor 恢复；完成“医院会话内新建是否丢失医生智能体绑定”源码核查，当前未复现；补充医生消息与 AI 流式并发的 Q10 |
| 2026-09-02 | 确认 Q9：保留本地数据和 cursor，分类重试；cursor 失效只重置对应 thread；核查“医院会话右上角新建丢失智能体绑定”问题，当前源码未复现，记录完整链路、运行时定位与防回归验收 |
| 2026-09-02 | 确认 Q8：实时消息合并后立即刷新会话 capabilities，历史可读、输入禁用并停止知识同步；分析现有 per-thread cursor 持久化缺口，加入 Q9 |
| 2026-09-02 | 确认 Q7：账号级落库、成员级界面隔离；核对现有下架只读能力与服务端会话能力契约，加入 Q8 |
| 2026-09-02 | 确认 Q6：底部自动跟随，阅读历史时保留锚点并提供“有新消息”按钮；核对账号级实时事件与成员级医院会话边界，加入 Q7 |
| 2026-09-02 | 确认 Q5：院内名医目录静默更新，保持“继续咨询”和已咨询医生稳定前置；核对现有底部锁定实现，加入 Q6 |
| 2026-09-02 | 确认 Q4：按 thread 立即拉取、dirty 标记并补拉一次，连续事件可短窗口合并；对照院内名医目录既有展示边界，加入 Q5 |
| 2026-09-02 | 确认 Q3：账号启动、连接成功、前台恢复和网络恢复均执行账号级全局补偿，不引入轮询；结合现有 `runSingleFlight` 分析连续事件边界，加入 Q4 |
| 2026-09-02 | 确认 Q2：App 前台所有会话事件均定向拉取；补充当前连接启动、重连、前台恢复和网络恢复的代码现状与具体技术落点；加入 Q3 |
| 2026-09-02 | 确认 Q1：采用带 `thread_id` 的会话定向拉取，并在重连、恢复前台和网络恢复时执行账号级全局补偿；加入 Q2 |
| 2026-09-02 | 创建工单；记录当前服务端与 iOS 实时链路、根因、候选方案、Q1 和基础验收标准 |

## 14. 最终方案总览

### 14.1 交付结果

本工单完成后，医生在 Web 工作台发送消息，患者只要已登录且 App 在前台，无论停留在哪个 Tab，iOS 都会按事件中的 `thread_id` 拉取对应会话。当前会话在正常网络下目标 P95 3 秒内显示；非当前会话静默入库。WebSocket 只负责通知，REST 增量接口和服务端数据库继续作为消息事实源。

### 14.2 不新建第二套消息系统

| 能力 | 复用现状 | 本工单增量 |
| --- | --- | --- |
| 消息业务模型 | `ChatThread`、`ChatMessage`、`ChatMessageBlock` | 不新增医院消息表；扩展可选 sender 快照 |
| 医生身份 | `ChatMessageAttribution`、`build_sender_snapshot` | 投影到现有聊天同步 payload |
| 通知 | Channels `/ws/chat/sync/` | 事件增加 `thread_id`、版本和诊断关联字段 |
| 完整消息 | 现有 `sync/pull/?thread_id=...` | 恢复实时 hint 后的定向拉取 |
| 本地消息 | Core Data、`ChatInboundPipeline`、合并策略 | 保存可选 sender；继续幂等合并 |
| 页面更新 | `.sparkChatDatabaseDidChange`、`ChatDetailViewModel` | 增加新消息计数和成员隔离检查 |
| 医院能力 | conversation context、`canSendMessage`、Manifest | 实时拉取后刷新受影响医院会话能力 |

### 14.3 架构决策

1. WebSocket 是可丢失的变化提示，不承载完整消息正文。
2. REST pull 是完整消息的唯一网络读取契约。
3. 服务端 `ChatMessage` 是业务事实源；Core Data 是账号级离线投影。
4. 实时调度集中在账号级同步 actor 内，页面不得直接消费 WebSocket。
5. 医生与 AI 身份来自消息级 sender，不再根据“会话存在医生简介卡”推断每条 assistant 消息。
6. 医疗正文不进入普通日志；需要原文排查时，从服务端业务库按授权受控查询。

## 15. 必须先修正的当前实现缺口

### 15.1 P0：实时 hint 到达后没有 pull

`ChatRealtimeSyncClient` 当前能够收到 `chat.sync.updated`，但只向下传递 cursor；`ChatSyncEngine.performRealtimeHintSync` 丢弃 cursor 并只上送 outbox。修复后必须把 hint 解析为结构化对象，并进入 thread 定向拉取调度器。

### 15.2 P0：事件没有 `thread_id`

`ChatSyncNotifier.notify_user_sync` 当前只发送 `cursor` 和 `message_ids`。客户端无法可靠判断该拉取哪个会话。服务端 signal 已持有 `ChatMessage.thread_id`，应在事务提交后一起下发。

### 15.3 P0：增量消息 payload 丢失医生身份

当前 `chat_sync.views._to_payload` 不投影 `ChatMessageAttribution`；现有回归测试甚至明确断言 payload 中没有 `actor_type`。iOS 的 `ChatRemoteMessageDTO` 和 `ChatMessage` 也没有 sender 字段。

同时，`ChatMessageSenderHeaderResolver` 当前只要在会话内找到医生简介系统卡，就把所有 assistant 消息推断为医生。这会导致医生智能体 AI 回复和真人医生消息身份混淆。

落地要求：

1. 复用 `ChatMessageAttribution`，不新建第二套医生消息表。
2. 同步 payload 增加可选 `sender`；普通历史消息可以没有该字段。
3. iOS 在 DTO、Domain、Core Data、合并和渲染链路保存 sender 快照。
4. sender 存在时严格按 `actor_type` 渲染；sender 缺失的旧消息才使用兼容性降级规则。
5. 更新原“payload 不包含 actor_type”的回归测试，改为普通消息不受影响、医院 attribution 正确投影。

### 15.4 P0：实时连接启动和补偿入口不完整

首次账号激活没有明确启动聊天 WebSocket；连接成功、App 回前台和网络恢复也没有调用聊天全局补偿。必须收口到 `AccountSessionRuntime`、`AppLifecycleCoordinator` 和现有网络状态编排。

### 15.5 P1：会话内新建智能体继承需保留验收

当前源码已有正确医院分支，静态核查未发现丢失 `agent_id`；本工单不重复实现。开发完成后必须执行第 10.1 节防回归验收，确保实时同步改造没有破坏 scope 继承。

## 16. 服务端事件与接口契约

### 16.1 WebSocket v2 事件

服务端事务提交后，按 thread 发送以下逻辑字段：

```json
{
  "type": "chat.sync.updated",
  "payload_version": 2,
  "event_id": "uuid",
  "thread_id": "uuid",
  "cursor": "server cursor or legacy timestamp",
  "message_ids": ["server-message-id"],
  "emitted_at": "ISO-8601"
}
```

| 字段 | 必填 | 语义 |
| --- | --- | --- |
| `type` | 是 | 固定 `chat.sync.updated` |
| `payload_version` | 是 | 本期为 2；旧客户端忽略新增字段 |
| `event_id` | 是 | 单次通知关联 ID，用于去重和诊断，不作为消息 ID |
| `thread_id` | 是 | 本次变化所属会话；跨 thread 批量变化必须拆分事件 |
| `cursor` | 否 | 提示服务端已有更新；iOS 不用它直接覆盖持久化 cursor |
| `message_ids` | 是 | 受影响的服务端消息 ID，可多条；用于诊断和拉取完成校验 |
| `emitted_at` | 是 | 服务端事件发送时间，用于链路耗时 |

兼容规则：

- 服务端只新增字段，不改变事件 type 和 WebSocket 地址。
- 新客户端若收到 v1 事件（无 `thread_id`），不得猜测当前 thread；触发一次账号级全局补偿。
- 无法解析 `thread_id` 的 v2 事件记录脱敏错误并走全局补偿。
- `event_id` 重复只允许合并调度，不得阻止 REST 最终补偿。

### 16.2 消息 pull 契约

继续复用现有 `sync/pull/`：

| 参数 | 值 |
| --- | --- |
| `thread_id` | 事件中的 thread UUID |
| `cursor` | 该 thread 本地已提交的 message cursor；首次为空 |
| `limit` | 复用现有分页上限，当前客户端为 200 |

响应继续包含 `cursor`、`messages`、`has_more`。客户端分页直到 `has_more == false`、cursor 不前进或达到安全页数上限。

### 16.3 sender 扩展契约

每条消息增加可选 sender：

```json
{
  "actor_type": "doctor | ai_agent | patient | system",
  "actor_id": "stable-id",
  "display_name": "snapshot",
  "avatar_url": "optional-url",
  "title": "optional-title",
  "department_name": "optional-department",
  "source": "doctor_console | system | other"
}
```

规则：

1. 医生消息必须返回 `actor_type=doctor`，并使用发送时快照；医生后续改名不修改历史显示。
2. 医生智能体 AI 消息返回 `actor_type=ai_agent`；如果旧链路暂时不能提供，至少保留 `model_name` 并明确降级为“医生智能体”，不能显示“真人医生”。
3. sender 为空表示旧普通消息，不能自动判为真人医生。
4. 服务端拉取 queryset 需预取 attribution、doctor/agent 关系，避免逐消息 N+1。
5. 普通消息 payload 原字段保持不变；sender 为向后兼容可选字段。

### 16.4 错误语义

| 分类 | 客户端行为 |
| --- | --- |
| 网络断开、超时、5xx | 保留 cursor，有限退避，thread 保持 dirty |
| 明确 cursor 无效/过期 | 只清除该 thread cursor，重新拉该 thread，不删除历史 |
| 401/设备会话失效 | 停止 WebSocket 和同步任务，进入现有鉴权失效流程 |
| 成员撤权 | 历史缓存可读；禁止拉远端、发送和知识同步 |
| thread 404 | 结束该 thread 的自动重试；刷新医院 context/本地会话状态 |
| 智能体下架/会话结束 | 消息可读；capabilities 切只读，停止知识同步 |

## 17. iOS 核心状态模型

### 17.1 结构化实时提示

`ChatRealtimeSyncClient` 向同步层传递一个结构化值，至少包含：`eventID`、`payloadVersion`、`threadID`、`cursor`、`messageIDs`、`emittedAt`。网络层只解析和鉴权，不直接访问 Core Data 或 ViewModel。

### 17.2 per-thread 调度状态机

```text
idle
  └─ hint → scheduled(200–300ms 合并窗口)
scheduled
  └─ 到期 → pulling
pulling
  ├─ 同 thread 新 hint → dirty
  ├─ 成功且非 dirty → idle
  ├─ 成功且 dirty → pulling（再拉一轮）
  └─ 可重试失败 → retryWaiting → pulling
```

实现约束：

- 状态字典按 `thread_id` 隔离。
- dirty 表示“本轮开始后又有变化”，不能用 hint 次数代表消息数量。
- 每轮成功后保存该 thread 的服务端响应 cursor。
- 取消账号、登出或 generation 变化后，旧任务结果不得写入新账号域。
- 自动重试有上限；新的 hint、网络恢复或全局补偿可以重新激活。

### 17.3 全局补偿状态机

触发源固定为：账号启动、WebSocket 每次连接成功、App 回前台、网络恢复。

```text
globalIdle
  └─ 任一触发 → globalPulling
globalPulling
  ├─ 再次触发 → globalDirty
  ├─ 成功且非 dirty → globalIdle
  └─ 成功且 dirty → globalPulling（再执行一次）
```

全局与 thread 调度由同一个 actor 协调。全局运行期间到达的 thread hint 必须留下 dirty 标记；全局完成后如果无法证明已覆盖该 hint，就补一次 thread pull。不得让现有 `single-flight` 的“复用任务后直接返回”吞掉后到事件。

### 17.4 sender 本地模型

在现有 `ChatMessage` 上增加可选 sender 快照，不新建并行消息模型。Core Data 的 `ChatMessageEntity` 增加可选 sender 字段或单个可版本化 sender JSON；推荐字段化保存 `actorType`、`actorID`、`displayName`、`avatarURL`、`title`、`departmentName`、`source`，便于迁移与调试。

旧数据库迁移必须是轻量可选字段迁移；已有消息 sender 为空时仍可打开，不做全库回填。

### 17.5 页面新消息状态

`ChatStateStore` 按 thread 保存仅用于 UI 的 `unseenRemoteMessageCount`。该值不等同于普通会话未读数：

- 当前列表贴底：新增消息直接跟随，计数为 0。
- 用户正在阅读历史：按真实新增消息数累加，显示“有 N 条新消息”。
- 点击按钮或手动回到底部：计数清零。
- 切 thread、退出详情、成员切换、账号切换：清理对应临时状态。
- 医院名医目录不读取该值。

## 18. 完整业务流程

### 18.1 医生消息正常实时到达

1. 医生 Web 校验当前医生对目标会话的权限、会话版本和终结状态。
2. 服务端事务内创建 `ChatMessage`、文本 block 和 `ChatMessageAttribution(actor_type=doctor)`。
3. 事务成功提交后，signal 取得 user、thread、message ID 和时间。
4. Notifier 向患者账号组发送 v2 hint。
5. iOS 前台 WebSocket 解析 hint，账号 generation 校验通过后交给调度器。
6. 调度器按 thread 合并短窗口事件并调用现有 REST pull。
7. DTO 映射消息、block 和 sender，`ChatInboundPipeline` 按消息 ID 幂等合并。
8. Core Data 保存消息、sender 和 thread cursor，发出数据库变化通知。
9. 当前成员匹配时，`ChatDetailViewModel` 只重载受影响 thread。
10. 当前页面贴底则直接跟随；阅读历史则保持锚点并增加新消息按钮计数。
11. 医院 thread 拉取完成后刷新 conversation capabilities；如已结束或下架，输入立即只读。

### 18.2 App 前台但不在目标会话

1. 仍按 thread 定向拉取并落库。
2. 不导航、不弹窗、不显示医院目录红点。
3. 当前成员的医生卡保持“继续咨询”和已咨询稳定前置；组内后台顺序不变。
4. 患者下次打开该医生时直接读取已经同步的新消息。

### 18.3 WebSocket 断线或事件遗漏

1. 客户端按现有 1、2、4 秒递增、最高 30 秒退避重连。
2. 每次连接成功都触发全局补偿，包括首次连接。
3. 回前台和网络恢复也触发同一补偿入口。
4. single-flight/dirty 合并重复触发；不增加周期轮询。

### 18.4 成员切换

1. 网络结果仍可写入当前账号的正确 thread。
2. UI 更新前再次比较 `thread.memberID` 与当前成员。
3. 不匹配时不更新目录、当前消息列表、滚动和新消息按钮。
4. 切回该成员后，从本地数据重组并按需补偿。

### 18.5 AI 流式与医生消息并发

1. 医生消息不等待 AI run，立即同步并显示。
2. 既有 AI 流式 run 不取消、不标失败。
3. sender 显式区分“真人医生”和“医生智能体”。
4. 最终按服务端确认时间、消息 ID 和现有合并策略收敛；不得按客户端接收先后永久排序。

### 18.6 医院会话内新建

1. 新建前解析原 thread 的医院 scope。
2. hospital scope 成功时使用同一 `agent_id` 和当前 `member_id` 调医院创建接口。
3. context 回源失败时阻断新建，不降级普通默认模型。
4. 新 thread 立即保存 scope，并重新加载 capabilities/知识 Manifest。

## 19. 代码落点与开发任务拆分

### 19.1 服务端 P0

| 文件 | 任务 | 验收事实 |
| --- | --- | --- |
| `chat_sync/events.py` | v2 hint 增加 event_id、payload_version、thread_id、emitted_at；批量按 thread 分组 | 客户端能确定目标 thread |
| `chat_sync/signals.py` | `transaction.on_commit` 后传 thread_id；避免闭包读取错误实例 | 通知一定晚于消息可读 |
| `chat_sync/consumers.py` | 原样转发 v2 事件；连接成功事件保持兼容 | 不在 Consumer 查正文 |
| `chat_sync/views.py` | pull payload 增加可选 sender projection，并预取 attribution | 医生/AI 身份随消息返回，无 N+1 |
| `hospital_care/services/sender.py` | 继续作为 sender snapshot 规则源 | 不复制医生展示字段规则 |
| `hospital_care/services/doctor_message_service.py` | 保证消息、block、attribution 在同一事务完成后才通知 | 不出现先通知后 sender 不可读 |
| 服务端测试 | 更新 payload 回归、事件契约、事务提交、权限、分页和 sender 测试 | 普通聊天不回归 |

### 19.2 iOS P0

| 文件 | 任务 | 验收事实 |
| --- | --- | --- |
| `ChatRemoteAPI.swift` | DTO 增加可选 sender | 旧 payload 仍可解码 |
| `ChatSyncDTOMapper.swift` | sender DTO 映射 Domain | 医生身份进入消息模型 |
| `ChatMessage.swift` | 增加可选 sender snapshot，并在 replacing/merge 中保留 | 流式与远端合并不丢 sender |
| Core Data model/store/repository | 轻量迁移 sender 可选字段；增加清除单 thread cursor 能力 | 旧库可启动，局部 cursor 可恢复 |
| `ChatRealtimeSyncClient.swift` | 解析 v1/v2 hint、连接成功回调、结构化错误 | 不直接更新 UI |
| `ChatSyncEngine.swift` | 恢复 pull；per-thread debounce/dirty/retry；全局补偿 dirty；账号 generation | 不吞连续事件、不跨账号写入 |
| `ChatSyncSupervisor.swift` | 暴露账号启动、连接成功、前台、网络恢复统一入口 | 生命周期只有一个协调入口 |
| `AccountSessionRuntime.swift` | 账号准备完成后启动 realtime；切换/登出停止并取消任务 | 首次登录也建立连接 |
| `AppLifecycleCoordinator.swift` | 前台恢复接全局补偿 | 不另加前台监听器 |
| `AppCoordinatorView.swift` / 网络编排 | 网络恢复触发补偿 | 不新建第二个网络监控器 |

### 19.3 iOS P1

| 文件 | 任务 | 验收事实 |
| --- | --- | --- |
| `ChatMessageSenderHeaderResolver.swift` | 优先使用消息 sender；删除“有医生简介卡即所有 assistant 都是真医生”的推断 | AI/真人身份不混淆 |
| 消息 Row/Header | 展示真人医生头像、姓名、职称/科室可选标签；AI 保留智能体标识 | 无 sender 旧消息安全降级 |
| `ChatDetailViewModel.swift` | 数据库变化后按 thread 和 member 刷新；远端新增数传给 UI 状态 | 非当前成员不串 UI |
| `ChatStateStore.swift` | per-thread 新消息计数与清理 | 阅读历史不跳动 |
| SwiftUI/UIKit 会话列表 | 共用底部状态与“有 N 条新消息”按钮 | 两套渲染行为一致 |
| Hospital context/knowledge coordinator | 拉取后刷新能力，下架/终结立即只读和停止知识同步 | 历史仍可读 |
| 医院目录 ViewModel/UseCase | 静默消费最新会话映射，不展示未读/摘要/时间 | 排序规则不回归 |

## 20. 失败、重试与并发矩阵

| 场景 | 数据处理 | UI | 后续动作 |
| --- | --- | --- | --- |
| 同 thread 连续 hints | 首次立即拉，期间标 dirty | 最终增量更新 | 当前轮后再拉，直到 clean |
| 不同 thread hints | 各自排队，可受统一并发上限约束 | 只更新对应 thread | 独立 cursor |
| hint v1 无 thread | 不猜当前会话 | 无技术错误 | 全局补偿 |
| pull 超时/5xx | 不推进 cursor，不删消息 | 当前已有内容保持 | 有限退避 + dirty |
| cursor 无效 | 只清该 thread cursor | 历史保持 | 从该 thread 首屏重拉 |
| WebSocket 断线 | 无消息变更 | 不提示 | 退避重连，成功全局补偿 |
| App 后台期间有消息 | 不要求后台实时 | 无 | 回前台全局补偿 |
| 账号切换 | 取消旧 generation 任务 | 重置账号 UI | 新账号独立连接/同步 |
| 成员切换 | 旧成员结果可正确落库 | 不更新新成员 UI | 切回后显示 |
| 智能体下架 | 保留历史 | 输入只读 | 停止知识同步 |
| AI 流与医生消息并发 | 两条消息独立合并 | 身份区分、均可见 | AI 不自动取消 |

## 21. 验收与测试矩阵

### 21.1 服务端测试

1. 保存医生消息并提交事务后，事件包含正确 user、thread、message ID。
2. 事务回滚不发送事件。
3. 医生消息 pull 返回 sender.actor_type=doctor 和发送时快照。
4. 医生智能体消息不得误返回 doctor。
5. 普通历史消息无 sender 时仍保持原 payload 可用。
6. 同时间戳多消息使用 v2 cursor tie-breaker 不漏不重。
7. 其他用户传入 thread_id 不能读取目标会话。
8. 已结束会话拒绝医生继续发送的既有测试继续通过。

### 21.2 iOS 单元测试

1. v1、v2 hint 均可解析；v1 触发全局补偿。
2. v2 hint 定向到正确 thread。
3. 同 thread 拉取中再来 hint 会 dirty 重拉。
4. 不同 thread 不串 cursor。
5. 全局任务期间到达 hint 不被吞掉。
6. 网络错误不推进 cursor；cursor 错误只清单 thread。
7. sender 在 DTO→Domain→Core Data→Domain 往返不丢失。
8. 医生 sender 显示真人医生；AI sender 显示智能体；旧消息不误标真人。
9. 成员切换后旧回调不更新当前 UI。
10. 阅读历史时新增消息保留锚点并累加按钮；贴底时自动跟随。

### 21.3 集成/真机验收

| 用例 | 操作 | 预期 |
| --- | --- | --- |
| 当前会话实时消息 | 医生 Web 发一条 | 正常网络 P95 3 秒内出现，身份为真人医生 |
| 非当前页面 | 患者停留健康首页，医生发消息 | 静默入库；回医生会话可见，无目录红点 |
| 连续消息 | 医生快速发 5 条 | 顺序正确、不丢、不重，请求被合并 |
| 断网恢复 | 断网发送后恢复 | 网络恢复全局补偿，消息最终出现 |
| WebSocket 重连 | 主动断开连接后医生发送 | 重连成功补偿消息 |
| 后台恢复 | App 后台时发送，随后回前台 | 回前台补齐 |
| 阅读历史 | 上滚后医生发送 | 位置不跳，出现新消息按钮 |
| 家庭成员 | A 有消息时切到 B | A 消息不出现在 B；切回 A 可见 |
| AI 并发 | AI 正流式时医生发消息 | 医生即时出现，AI 继续完成，身份不混淆 |
| 下架/终结 | 医生最后消息后结束会话 | 历史可读，输入立即只读，知识同步停止 |
| 医院内新建 | 医生会话右上角新建 | 新 thread 继承同 agent_id，不使用默认模型 |
| context 失败 | 清 scope 且让 context 失败后新建 | 阻断并提示，不创建普通 thread |

### 21.4 性能验收

- 主链路指标：服务端事务提交到 iOS UI 可见 P95 ≤ 3 秒。
- 同 thread 5 条突发消息不得产生 5 个并发 pull。
- WebSocket 事件不携带正文，单事件尺寸保持轻量。
- sender 预取后，pull 查询数不能随消息条数线性增长。
- 全局补偿不周期轮询，前台空闲时不产生持续聊天请求。

## 22. 可观测性与受控诊断

### 22.1 常规指标

记录：event ID、消息 ID/会话 ID 的短值或哈希、账号哈希、事件发送/接收时间、pull 开始/结束、入库完成、UI 可见、触发源、重试次数、错误分类、最终状态。

禁止：常规日志、控制台、第三方分析或崩溃平台记录消息正文、附件内容、患者姓名、证件、病历字段或访问令牌。

### 22.2 完整 payload/正文排查

用户确认需要完整原文诊断能力。最终按安全默认实现为：

1. 不额外复制到 iOS 或普通日志。
2. 从服务端已有 `ChatMessage`、block、attribution 按 message/thread ID 受控查询。
3. 查询必须有医院授权角色、用途、操作人和时间审计。
4. 默认禁止批量导出；任何导出都进入医院审计记录。
5. 如未来需要独立加密审计库，另开安全评审工单。

## 23. 发布顺序与兼容策略

1. **先发服务端兼容扩展**：事件和 pull 只新增可选字段，旧 iOS 可继续运行。
2. **再发 iOS**：新 iOS 支持 v1/v2；若服务端尚未返回 thread_id，走全局补偿。
3. **观察指标**：验证 v2 事件解析率、定向 pull 成功率、P95 时延、dirty 重拉率和 sender 缺失率。
4. **稳定后收口**：保留 v1 兼容至少一个客户端发布周期；后续删除需另开迁移工单。
5. **不得以功能开关关闭 REST 补偿**：即使 WebSocket 稳定，前台/重连补偿仍是最终一致性保障。

## 24. 完成定义（Definition of Done）

本工单只有同时满足以下条件才可关闭：

- 服务端 v2 hint 与 sender payload 契约完成并有自动化测试。
- iOS 账号启动、连接成功、前台恢复、网络恢复四个入口全部接入。
- 定向 pull、dirty 重拉、全局补偿、分类重试、单 thread cursor 重置全部通过测试。
- 医生与医生智能体身份在同一会话中逐条正确显示。
- 当前会话、非当前会话、成员切换、AI 并发、只读切换均通过真机验收。
- 医院会话内新建始终继承原 `agent_id`，scope 失败不降级默认模型。
- 正常前台网络端到端 P95 ≤ 3 秒。
- 普通聊天、AI 流式、消息发送、历史打开和知识库同步无回归。
- 常规日志不包含医疗正文；完整原文只能通过服务端授权审计查询。
