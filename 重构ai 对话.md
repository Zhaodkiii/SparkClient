下面我会按“顶级架构评审”的标准直说：你现在的问题不是某个 `merge` 写得不够好，而是**系统把同一条消息的生命周期拆成了多个互相不知道的真相源**。这类架构在流式 AI + 异步工具 + 富卡片 + 多端同步里必然失控。

我会给出一个更彻底的蓝图：**事件溯源式 Message Timeline + 单一持久化真相源 + Actor 串行化副作用 + Outbox 自动同步**。

---

## 文档范围与前提（全新项目）

> **本文档面向从零搭建的新项目（greenfield），不面向在现有 SparkClient 聊天栈上做渐进式改造。**

| 前提 | 说明 |
|------|------|
| **不考虑数据迁移** | 无需兼容旧版 `streamingAssistants`、双管道 merge、`persistStreamingAttachmentsIfNeeded` 等历史实现；本地库可按新模型直接建表，无需双写、灰度或回滚路径。 |
| **不考虑 API / 协议兼容层** | 服务端与客户端按新契约一起设计；不为旧消息格式、旧 block 编码或旧同步字段保留适配器。 |
| **可以删除而非包裹** | 文中「当前架构诊断」仅用于说明**要避免的反模式**；落地时直接实现目标架构，不必在旧代码旁并行维护一套新链路。 |
| **实施顺序按能力切片** | 可按 Phase 分模块交付（先 MessageRunActor + 本地投影，再 Tool 事件流，再 SyncEngine），但每一 Phase 都应是**可替换的旧方案**，而不是与旧方案长期共存。 |
| **充分清理淘汰物** | 新链路落地后，必须**删除**被代替的类、方法、模块、Core Data 字段、DTO、测试与文档引用；禁止「先留着万一要用」式共存。 |
| **阶段闸门（Gate）** | **每一步重构完成后**必须跑完当步验收；**未达标不得进入下一步**，应在当前 Phase 内补实现、补测试、补删除，直至通过。 |

**一句话：** 按本文实现时，默认读者手里是一张白纸——**只设计「最终态」，不为「从现状迁过去」预留分支；旧实现不留尸骸。每一步都要「验过关门」再往下走。**

---

## 重构交付要求：淘汰物必须删净

重构不是「新代码叠在旧代码旁边」，而是**用新架构替换旧架构，并把被替换的一切从仓库里拿掉**。否则会出现：双入口、双合并、双同步、幽灵 API，比改之前更难维护。

### 1. 什么必须清掉

| 类别 | 清理对象（示例） | 验收标准 |
|------|------------------|----------|
| **类型 / 模块** | 整文件或整个 target 仅服务旧链路 | 工程内无 `import`、无 DI 注册、无 Feature Flag 指向旧模块 |
| **类 / struct / enum** | 被新 Actor、Repository、Query 取代的类型 | `rg` / IDE 引用为 0；对应单元测试已删或改绑新类型 |
| **方法 / 扩展** | 旧 `merge*`、`updateStreaming*`、`persistStreaming*`、`pushPending*`（UI 直调）等 | 无调用方；协议默认实现若仅为旧栈服务则一并删除 |
| **状态字段** | `streamingAssistants`、`streamingContentGeneration`（若仅用于影子消息）等 | `ChatStateStore` 只保留 draft、滚动、展开等 **纯 UI 瞬时态** |
| **协调器 / Reducer** | `StructuredHealthCardMergeCoordinator` 直写 UI、`ChatStreamingAssistantReducer` 作为 block 权威合并 | 职责迁入 `MessageRunActor` + DB upsert 后，原类型删除 |
| **数据模型** | Core Data 实体属性、JSON 键、已废弃的 `ChatAttachment` 展示字段 | Schema 与 `数据模型需求文档.md` 一致；无「仅为旧客户端可读」的列 |
| **同步 / 出站** | ViewModel 内 `pushPendingMessages`、`delay loadMessages` 等止血逻辑 | 仅 `SyncEngine` / `Outbox` 驱动；UI 层零同步调用 |
| **测试** | 测旧 merge 规则、旧双管道、旧 snapshot 组装的用例 | 改为测事件幂等、DB 投影、Actor 串行；过时用例删除而非 `@disabled` 堆积 |
| **文档 / 注释** | 仍描述「流式结束补写」「双真相源」的说明 | 与本文及新契约对齐，或删除 |

### 2. 清理原则（写进 Code Review）

```text
1. 新路径合并进 main 的同一 PR（或紧接的「删除 PR」）里，必须包含对旧路径的删除 diff，不能只加不减。
2. 禁止 @available 包裹旧 API「以备回滚」——回滚用 git revert，不用运行时双轨。
3. 禁止 `Legacy*` / `Old*` / `V1*` 旁路模块长期存在；若需对照，用分支或 tag，不留在主干。
4. 删除后全量编译 + 全量单测 + 主流程手工冒烟（发消息、工具卡、中断、重进会话、同步）。
5. Core Data 模型变更：greenfield 可直接删实体/属性；不做「保留列但不读」的僵尸字段。
6. 服务端若同步删字段，客户端不得保留「读到了就忽略」的死代码，除非协议层明确可选且文档化。
```

### 3. 建议的「淘汰清单」模板（每个 Phase 填表）

每个能力切片交付时，在 PR 描述或迭代记录中附表：

```markdown
## 本 Phase 新增
- MessageRunActor.handle(_:)
- ChatMessageRepository.upsertBlock(...)

## 本 Phase 删除（必须非空或说明 N/A）
- [ ] ChatStateStore.streamingAssistants 及关联 API
- [ ] ChatStreamingAssistantReducer（或缩减为仅 UI 动画，无 block 合并）
- [ ] StructuredHealthCardMergeCoordinator.mergeStreamingAssistantPresentation
- [ ] ChatDetailViewModel.persistStreamingAttachmentsIfNeeded
- [ ] …

## 数据模型
- [ ] 删除实体/属性：___
- [ ] 更新 数据模型需求文档.md

## 验证（阶段闸门，见「分步重构：阶段闸门与验收校验」）
- [ ] 本 Phase 目标达成（对照 P0–P6 表）
- [ ] INV-1 … INV-6 满足
- [ ] forbidden.txt / chat-refactor-gate CI 绿
- [ ] §4.4 Phase 完成检查表全 ✅
- [ ] 无对上述符号的引用（附 grep 结果）
- [ ] 未达标项：无（禁止带着未达标项进入下一 Phase）
```

### 3.1 SparkClient 当前落地状态（2026-05-20）

本轮已将 AI 对话主链路推进到 **DB-first + MessageRunActor + 自动 Outbox** 的目标形态：

- 已删除旧 UI 影子消息入口：`ChatStateStore.streamingAssistants`、`ChatStreamingAssistantReducer`、`ConversationRenderState`。
- 已删除旧 UI 手动同步入口：`OutboxCoordinator`、`SyncChatUseCase` 以及 ViewModel 内 `pushPendingMessages` / `syncThreadOnOpen` 类调用。
- 已将文本 partial、工具行、富卡片 ready/finalize 收束到 `MessageRunActor`，再由 Repository/Core Data upsert。
- 已将富卡片从“流式结束后补写”改成稳定 blockID 的幂等 upsert，重复事件只更新同一块。
- 已引入 `ChatSyncSupervisor` 监听数据库变化自动调度 Outbox；UI 不关心 push/pull 时机。
- 已补 `scripts/chat-refactor/check-forbidden.sh` 与 `ChatArchitectureGateTests`，用于阻止旧符号回流。

本轮针对流式刷新慢的修正：

- `MessageRunActor` 对 assistant partial 做 50ms coalescing，避免模型 token 被每次 DB 写入反压。
- `ChatLoadCoordinator` 从 debounce 改为 throttle/coalesce，连续 token 下不会反复取消刷新任务。
- `ChatDetailViewModel` 的 DB 通知刷新节奏调整为 60ms。
- `CoreDataChatStore.upsertMessageBlock(markPendingForSync: false)` 不再标记影响线程列表，流式 partial 不触发 Outbox。
- `ChatSyncSupervisor` 只对 `affectsThreadList == true` 的消息变更调度上送。

本轮继续完成的数据模型收尾：

- 已新增 `ChatMessageBlockEntity`，每个 block 独立持有 `id / clientMessageID / threadID / kind / status / revision / orderKey / payloadData`。
- `appendMessage`、`upsertLocalMessage`、远端 merge、完整 `updateMessageBlocks`、单块 `upsertMessageBlock` 都会同步维护 block 行。
- `loadMessages` 读取时只从 `ChatMessageBlockEntity` 投影 blocks；客户端 Core Data 已去除 `blocksData` 字段。
- 单块 upsert 不再解码整条消息 blocks 数组后重写，而是按 blockID + revision 幂等更新独立行。
- 服务端 `chat_sync` 已新增 `ChatMessageBlock` 表；push/pull 仍返回 message 下的 `blocks` 数组，但服务端不再把 blocks 存进 `ChatMessage.metadata`。
- 已新增服务端 schema migration `chat_sync/migrations/0011_chatmessageblock.py`，仅建新表，不做旧数据迁移。
- `StructuredHealthCardMergeCoordinator` 已重构为纯富卡片事件工厂：不持有 Repository、不轮询等待消息、不读 DB 合并；所有富内容直接转成 `ChatRunEvent` 进入 `MessageRunActor`，最终写入 `ChatMessageBlockEntity`。
- `ChatMessage.swift` 已对齐 `ChatMessageBlockEntity.payloadData`：`ChatMessageBlock` 编码/解码直接使用 `payload`，删除旧式平铺 block JSON 解析和未使用的 storage envelope。
- 详情页 DB 通知已从“所有 message 更新都整窗 reload”推进为“`.messagesUpdated` 按 `affectedClientMessageIDs` 局部取回并替换当前窗口消息”；流式 token 与富卡片 ready 不再默认触发整窗重读。

至此，本项目的 AI 对话主链路已经从“UI 影子状态 + 结束后补写”推进为“稳定消息行 + 独立 block 行 + Actor 串行副作用 + DB 变更驱动同步”。若后续要继续追求更强的 UI 增量性能，可把详情页从当前 DB 通知 throttle reload 替换为 `NSFetchedResultsController<ChatMessageBlockEntity>` 直接驱动列表 diff；这属于性能投影升级，不再是双真相源或同步架构缺陷。

剩余未完成项：

- **P4 可选性能投影**：详情页已支持 message 级局部投影；若要做到最高标准，可继续升级为 `NSFetchedResultsController<ChatMessageBlockEntity>` 级别的 block 增量 diff。
- **人工冒烟**：需要真机/模拟器走一遍“长流式回复、工具卡片晚到、杀进程重进、服务端 push/pull”。
- **CI 接入外部流水线**：本仓库已提供 `scripts/chat-refactor/gate.sh` 作为统一入口，覆盖旧符号扫描、iOS build、服务端 `chat_sync` check/migration/test；是否接入 GitHub Actions / Xcode Cloud / 自建 CI 取决于仓库流水线配置。

### 3.2 StructuredHealthCardMergeCoordinator 最新设计

旧版 `StructuredHealthCardMergeCoordinator` 的问题不是命名，而是职责越界：

```text
ToolHub 后台 Task
  ↓
StructuredHealthCardMergeCoordinator 轮询 repository.loadMessages
  ↓
等待 assistant message 出现
  ↓
读取当前 blocks、手动合并、再提交 MessageRunActor
```

这在 `ChatMessageBlockEntity` 独立行模型下是错误方向：

- **轮询等消息**：消息生命周期已经由 `SendChatMessageUseCase -> MessageRunActor.startAssistantMessage` 保证先建 assistant 行；富卡片协调器不应再用 60ms 轮询补架构时序。
- **读库合并**：结构化健康卡片的 delta 合并属于“同一消息运行内的副作用串行化”，应放在 `MessageRunActor`，而不是放在任意后台工具 Task。
- **补丁对象**：`PresentationPatch` 是旧 UI presentation 时代的概念；现在持久化单元是 `ChatMessageBlockEntity`，补丁应直接表达为 `ChatRunEvent`。
- **双重职责**：协调器同时负责等待、读取、合并、提交，导致它变成第二个 mini-reducer，破坏单向数据流。

最新目标态：

```text
ToolHub async result
  ↓
StructuredHealthCardMergeCoordinator
  只做：业务结果 -> ChatRunEvent
  ↓
MessageRunActor
  串行：partial flush / rich block ready / structured health delta merge
  ↓
ChatRepository.upsertMessageBlock
  ↓
ChatMessageBlockEntity(id, clientMessageID, kind, status, revision, orderKey, payloadData)
  ↓
Core Data notification
  ↓
UI projection
```

当前实现约束：

- `StructuredHealthCardMergeCoordinator` 只依赖 `MessageRunActor`。
- 对外 API 已收敛为 `publish*`：`publishKnowledgeCards`、`publishHealthSleepVisualization`、`publishTaskCards`、`publishCaptureCard` 等，命名不再暗示“等待消息就绪”。
- 普通富卡片走 `ChatRunEvent.richBlockReady`，由 `MessageRunActor.databaseRichBlock` 生成稳定 blockID 与 ready 状态。
- 结构化健康增量走 `ChatRunEvent.structuredHealthCardsDelta`，由 `MessageRunActor` 在串行上下文中读取当前 block、合并 delta、upsert 同一稳定 blockID。
- 若 assistant message 不存在，Actor 记录 warning 并丢弃该异常事件；正常发送链路中 assistant 行必须先于工具结果存在。

### 4. 与「不做迁移」的关系

**不做迁移** ≠ **不删旧代码**。恰恰相反：正因为不背迁移包袱，才更应该**一次性删净**，避免新旧两套聊天管线同时存活。若某旧模块「暂时还要给别的 Feature 用」，应明确归属并迁出 Chat 域，而不是挂在聊天重构分支里当备用轮子。

---

## 分步重构：阶段闸门与验收校验

重构按 **Phase（能力切片）** 推进。每个 Phase 有明确的 **目标态（Target）** 与 **退出条件（Exit Criteria）**。原则只有一条：

```text
当前 Phase 未通过验收 → 禁止开下一个 Phase 的功能开发；
先在当前 Phase 内补代码、补测试、删旧路径、修 CI，直到闸门关闭（Gate Closed）。
```

「差不多能跑」不算过关；**架构不变量 + 自动化 + 本 Phase 删除清单** 必须同时满足。

### 1. 三层校验（推荐固定顺序）

| 层级 | 目的 | 未通过时动作 |
|------|------|----------------|
| **L1 架构不变量** | 证明没有退回双真相源、双写路径 | 改设计或删旁路，**不**用 delay/merge 补丁糊住 |
| **L2 自动化** | CI 可重复证明幂等、串行、无幽灵引用 | 补单测/集成测/静态检查，修到绿 |
| **L3 人工冒烟** | 主路径真机/模拟器可走通 | 记缺陷，回到 L1/L2 根因修复，禁止「下步再修」 |

执行顺序：**L1 → L2 → L3**。L3 失败若暴露的是架构问题，应回到 L1 重新判定本 Phase 是否达标。

### 2. 全局架构不变量（每个 Phase 都要过）

以下任一条在本 Phase 涉及范围内被违反，**整 Phase 不算完成**：

```text
INV-1  消息内容（含流式中的 text/tool/卡片）只通过 Repository → Core Data 写入；UI Store 不持有 blocks 权威副本。
INV-2  同一 blockID 重复 upsert N 次，DB 中仍只有一行，revision 单调不减，payload 与最后一次一致。
INV-3  富卡片 pending → ready（或 failed）只更新同一 blockID，不产生第二块「影子卡」。
INV-4  Chat 业务模块内不存在本 Phase「淘汰清单」所列符号的引用（grep 为 0，见附录 B）。
INV-5  ViewModel / View 不调用 push/pull/sync（Sync 仅 SyncEngine）；本 Phase 若未做 Sync，则不得新增 UI 直调同步。
INV-6  工具异步结果以 ChatRunEvent 进 MessageRunActor，不 Task 直写 UI StateStore 的 message blocks。
INV-7  流式 token 刷新必须是 throttle/coalesce，不允许 debounce。连续 token 到达时 UI 至少每 50–100ms 有机会刷新一次，不能等 token 暂停后才整窗 reload。
INV-8  流式 partial 写库默认不触发 Outbox；只有最终 assistant blocks、富卡片 ready、用户显式编辑等 markPendingForSync=true 的变更才进入同步调度。
```

建议在仓库增加 `ChatArchitectureTests`（或 lint 脚本），对 INV-4 / INV-5 做 **禁止引用列表** 扫描，合并进 CI。

### 2.1 流式刷新性能红线

DB-first 不等于「每个 token 都阻塞 UI 等数据库完成整窗重载」。iMessage / 飞书这类通讯软件的实时输入体验，一般是**持久化真相源 + 前端投影节流刷新**：写入可以高频发生，但 UI projection 必须用 throttle 或 coalescing，以固定帧率消化变化，而不是 debounce。

本项目在落地 `MessageRunActor -> Repository -> Core Data -> UI` 后，曾出现过一个典型退化：每个 token upsert 后广播 DB 通知，而详情页刷新使用 debounce；连续 token 会反复取消刷新任务，直到模型输出出现空隙才 reload，体感变成约 1–1.5 秒跳一次。这违反 INV-7。

目标策略：

```text
1. MessageRunActor 可接收每个 token delta，但写库/通知应按 50–100ms 合并或至少 UI projection 按 50–100ms throttle。
2. UI 列表/详情收到 DB 通知后采用 throttle：有刷新在排队时只替换 latest operation，不取消并重新等待。
3. markPendingForSync=false 的流式 partial 只驱动本地投影刷新，不触发 Outbox debounce。
4. markPendingForSync=true 仅用于最终 blocks、富卡片 ready、用户操作产生的持久业务变更。
5. 验收时观察长回复：连续输出阶段不得出现超过 250ms 的常态空窗；异常峰值需能解释为模型端停顿而非 UI reload 策略。
```

### 3. 推荐 Phase 划分与当步目标

| Phase | 目标（本步结束时必须成立） | 本步应删除/禁止（摘录） |
|-------|---------------------------|------------------------|
| **P0 模型与仓库** | `ChatMessage` / `MessageBlock` / `BlockID` / `revision` 落库；`upsertBlock` 幂等可测 | 无「仅内存 blocks 数组」作为持久化来源 |
| **P1 MessageRunActor** | 发消息 → 先建 assistant 行（`.streaming`）→ 文本 delta 事件写 DB；UI 用 Query 看到打字 | 不用 `streamingAssistants` 存正文 |
| **P2 工具行 + 同步工具** | `toolCall` 事件写 tool block；模型 loop 可继续 | 不用 `ChatAssistantPartialDelta` 直写 UI 作为唯一路径 |
| **P3 富卡片事件** | `richBlockPending/Ready/Failed` 同 blockID；乱序到达测试通过 | 删除 `mergeStreamingAssistantPresentation`、`persistStreamingAttachmentsIfNeeded` |
| **P4 UI 纯投影** | `ChatTimelineQuery` 为列表唯一数据源；Store 仅 draft/滚动/展开 | 删除 `ChatStreamingAssistantReducer` 的 block 合并职责 |
| **P5 SyncEngine** | Outbox 由 DB 变更驱动；拉取幂等 merge | 删除 VM 内 `pushPendingMessages`、DB 通知 delay 止血 |
| **P6 收尾** | 附录 B 零引用；文档与 `数据模型需求文档.md` 一致 | 无 Legacy 模块、无 `@disabled` 堆积旧测 |

**注意：** 表中「应删除」项允许在 **声明删除的 Phase** 才强制为零引用；此前 Phase 不得提前依赖将被删除的 API。

### 4. 每 Phase 必跑的「最佳校验包」

将下列检查固化为 **PR 模板 + CI Job**（名称示例：`chat-refactor-gate`）：

#### 4.1 静态与引用（L1/L2，必过）

```bash
# 本 Phase 淘汰符号（按附录 B 与 Phase 填表维护 forbidden.txt）
xargs rg -l --from-file scripts/chat-refactor/forbidden.txt \
  --glob '*.swift' SparkClient/ && exit 1 || true

# UI 层禁止同步（P5 前可仅 warn，P5 起 error）
rg 'pushPendingMessages|pushOutboxOnly' \
  --glob '*ViewModel*.swift' SparkClient/Projects/Features/Chat/Presentation/ && exit 1 || true

# 禁止直写 streaming 内容块（P1 起 error）
rg 'streamingAssistants|mergeStreamingAssistantPresentation' \
  --glob '*.swift' SparkClient/ && exit 1 || true
```

#### 4.2 单元 / 集成测试（L2，必过）

| 测试用例 | 断言 |
|----------|------|
| `test_upsertBlock_idempotent` | 同一 `blockID` 连续 upsert 3 次 → 单行，`revision` 递增 |
| `test_textDelta_outOfOrder` | 乱序 `textDelta` → 最终 text 与按序一致 |
| `test_richBlock_pendingThenReady` | pending 后 ready → 同 ID，kind 不变，status 变 ready |
| `test_richBlock_readyBeforePending` | ready 先于 pending 到达 → 仍单行，最终 ready |
| `test_actor_serializesConcurrentEvents` | 并发 100 事件 → 无丢块、无 duplicate block 行 |
| `test_noStreamingShadowInStore` | 发流式消息后 `ChatStateStore` 无 assistant blocks 字段（P4） |

测试应用 **内存 Core Data** 或 TestHost，避免依赖真机网络。

#### 4.3 UI / 端到端冒烟（L3，必过）

每个 Phase 至少勾选与本步相关的项：

```markdown
- [ ] 发送文本：列表即时出现 user + streaming assistant，打字来自 DB 刷新而非内存 tail
- [ ] 工具调用：出现 tool 行，参数/输出与模型一致
- [ ] 健康/睡眠/知识卡：先 skeleton（pending）再内容（ready），无闪退、无重复两张卡
- [ ] 卡片晚于「发送完成」到达：仍显示在同一条 assistant 下，无需退出重进
- [ ] 中途取消：assistant 保留已生成 blocks，状态为 cancelled/failed
- [ ] 杀进程重进：流式中/刚完成的 message 与 blocks 与杀前一致（P1+）
- [ ] 切换会话再回来：无重复消息、无丢失卡片（P4+）
- [ ] 飞行模式发送 → 恢复网络：outbox 自动上送，状态变 sent（P5）
```

#### 4.4 Phase 完成检查表（PR 描述必填）

```markdown
## Phase: P__ 名称

### 目标达成（自评，须全 ✅ 才能合并）
- [ ] 上表「本 Phase 目标」每一条能在 PR 说明里对应到代码/测试
- [ ] INV-1 … INV-6 在本 Phase 范围内均满足
- [ ] 本 Phase「删除清单」已勾选，forbidden.txt 已更新
- [ ] `chat-refactor-gate` CI 全绿
- [ ] L3 冒烟清单已执行（注明设备/模拟器版本）

### 未达标时的处理（合并前必填其一）
- [ ] 无未达标项
- [ ] 未达标项列表 + 本 PR 内已修复说明
- [ ] **禁止**：未达标仍合并并「下個 Sprint 再补」

### 证据链接
- CI 运行链接：
- 关键测试类：
- grep 截图 / forbidden 扫描结果：
```

### 5. 「未达标」时怎么做（禁止跳步）

```text
1. 在 PR / Issue 列出：哪条 INV 或哪条 Exit Criteria 失败、复现步骤。
2. 只允许三类改动：补实现、补测试、删旧路径——不允许「先加 Feature Flag 绕过」。
3. 修到 L2 全绿后，再跑 L3；L3 仍失败则回到 L1 看是否模型/事件设计错了。
4. Phase 内可多个 PR，但 **Gate Closed** 以「本 Phase 检查表全 ✅」为准，不以「某个 PR 已合并」为准。
5. 若发现目标定错：先改本文档 Phase 目标与验收，再改代码——不要 silent 扩 scope 到下一 Phase。
```

### 6. 与「淘汰清单」模板的衔接

上文 **§3 建议的「淘汰清单」模板** 中「验证」一节扩展为：

```markdown
## 验证（Gate）
- [ ] forbidden.txt 扫描通过（附 CI job 链接）
- [ ] 本 Phase 目标达成表（§4.4）全 ✅
- [ ] 架构不变量 INV-1…6 自检
- [ ] 未达标项：无 / 已在本 Phase 关闭
```

---

## 一、当前架构诊断

### 1. 双重状态的罪恶

你现在有两套状态：

```swift
ChatStateStore.streamingAssistants   // UI 内存流式工作集
CoreDataChatStore                    // 持久化真相源
```

表面上它们职责分明：

- Core Data 是“最终真相”
- `streamingAssistants` 是“临时预览”

但问题在于：**富卡片并不是纯 UI 临时状态，它是消息内容的一部分**。

例如：

```swift
ToolHub -> Task { publishKnowledgeCards(...) }
```

这类卡片不是“动画状态”或“loading 状态”，而是最终应该进入 `ChatMessage.blocks` 的业务数据。可它先写入 `streamingAssistants`，再在流式结束时由：

```swift
persistStreamingAttachmentsIfNeeded()
```

补写进 Core Data。

于是系统出现了两个事实：

```text
事实 A：内存里这条 assistant message 已经有 health card
事实 B：Core Data 里这条 assistant message 暂时还没有 health card
```

一旦这时发生以下任意事件，就会出问题：

- DB 通知触发 `loadMessagesIfNeeded`
- 远端同步拉回旧版本消息
- 工具卡片晚于 assistant message 落库
- 多个卡片补丁乱序返回
- 用户切线程再回来
- App 被杀后恢复
- 同一个 toolCallID 被重复处理

你现在靠这些代码防守：

```swift
clearStreamingAssistant: false
delay 1000ms
skipRemoteSync: true
persistStreamingAttachmentsIfNeeded
updateMessageBlocksSnapshot
pushPendingMessages(source: ...)
```

这些不是架构，是止血贴。

现代 Swift 架构里，真正的 Single Source of Truth 应该是：

```text
UI = f(Database Projection)
```

而不是：

```text
UI = f(CoreData messages + in-memory streaming tail + delayed rich card patches)
```

更理想的设计是：**流式 token、工具调用、富卡片 pending、富卡片 ready 全部都是数据库中的消息事件或 block 状态**。UI 只订阅数据库投影。

也就是说，流式中的 assistant message 也应该是一条真实存在于本地数据库中的 message，只是状态是：

```swift
.status = .streaming
```

它的 blocks 也是真实存在的，只是部分 block 是：

```swift
.status = .pending
.status = .streaming
.status = .ready
.status = .failed
```

---

## 二、异步管道混乱：为什么现在会“合并错误”

你目前有两条管道写同一个状态：

```text
管道 A：模型流式 token / tool partial
AIRuntimeStreamEvent
→ ChatAssistantPartialDelta
→ updateStreamingAssistant
→ reducer.reduce

管道 B：工具后台 Task 富卡片
ToolHub
→ Task { StructuredHealthCardMergeCoordinator.publish* }
→ ChatRunEvent.richBlockReady / structuredHealthCardsDelta
→ MessageRunActor
→ ChatMessageBlockEntity upsert
```

它们的问题不是“异步”，而是**没有共同的消息事务上下文**。

### 当前 `ChatMessageBlockBuilder` 的隐患

它大概依赖这些字段合并：

```swift
kind
toolCallID
anchor
pending card id
```

这在简单场景能跑，但在复杂场景里会出现以下风险。

#### 风险 1：锚点不存在时的插入顺序不稳定

富卡片通过：

```swift
anchor: .toolCall(id)
```

希望插到对应工具行后面。

但如果富卡片先于 tool block 到达：

```text
T1: health card ready
T2: toolCall partial block created
```

那么 builder 只能：

- 暂时 append 到尾部
- 或等待
- 或后续 finalize 再调顺序

这意味着顺序不是由事件日志决定，而是由 merge 函数“猜”。

这就是隐患。

#### 风险 2：同一个 block 被不同生命周期重复写入

一张卡片可能经历：

```text
streaming cache 插入
finalizeStreamingPresentationBlocks 规范化
persistStreamingAttachmentsIfNeeded 写 DB
updateMessageBlocksSnapshot 更新内存快照
DB notification 再 load
remote pull 再 merge
```

每一步都可能重新排序、去重、覆盖。

只要其中某一步的判断条件不同，例如：

```swift
kind + toolCallID + anchor
```

和另一步用：

```swift
blockID
```

或没有稳定 `blockID`，就会产生重复、丢失或顺序漂移。

#### 风险 3：builder 承担了不该承担的业务语义

`ChatMessageBlockBuilder` 现在不是单纯的 UI builder，而是在做：

- 去重
- 替换
- 插入
- 锚点修正
- pending 卡片合并
- 流式最终排序
- 富卡片 patch 合并

这已经是一个“小型数据库合并引擎”。但它没有事务、没有版本、没有幂等键、没有 actor 隔离，所以它必然脆。

一句话：**当前的合并错误来自于把事件顺序、业务身份、UI 排序和持久化补偿混在了一个数组 merge 里。**

---

## 三、架构评级

如果满分 10 分，我会给当前架构：

```text
4 / 10
```

不是因为工程质量差，而是因为它已经进入了一个高复杂度业务，但核心模型还停留在“聊天消息数组 + 流式临时状态 + 后补卡片”的阶段。

### 最需要彻底抹平的设计

第一优先级：

```text
ChatStateStore.streamingAssistants 作为消息内容临时真相源
```

它应该被删除或降级为纯 UI ephemeral state，例如：

- 当前滚动位置
- 输入框 draft
- 是否展开 reasoning
- 光标动画状态
- 局部 hover/selection

但不能保存最终 message blocks。

第二优先级：

```text
StructuredHealthCardMergeCoordinator -> publish* -> ChatRunEvent
```

这个协调器不应该直接改 UI 工作集，也不应该轮询读库。它只应该产生**领域事件**，由 `MessageRunActor` 串行落库。

第三优先级：

```text
ViewModel 主动 pushPendingMessages / loadMessagesIfNeeded / delay 1000ms
```

同步不应该出现在 UI 层。UI 层只表达用户意图。

---

## 四、工业级参考

### Telegram / 飞书的模式

这类通讯软件通常不是“UI 先拼一个消息，结束后再落库”。它们会：

1. 先创建本地消息，带本地 ID。
2. 消息立即进入本地数据库。
3. UI 订阅数据库变化。
4. 网络发送、上传附件、富卡片解析都作为后台任务更新该消息或其子实体。
5. 服务端回执只更新状态和 server ID。
6. 重复回执、重复拉取必须幂等。

抽象上是：

```text
Local optimistic write
→ Database projection
→ UI render
→ Background sync
→ Remote ack
→ Database projection update
→ UI render
```

### iMessage 的模式

iMessage 里发送图片、链接预览、附件时，消息不是等所有东西准备好才出现。它会先出现一个 pending message，然后附件、link preview、delivery status 独立更新。

关键是：**UI 看到的每个阶段都来自同一个消息记录，而不是来自另一个内存缓存。**

### Apple Health 的模式

Health 更典型的是不可变样本 + 查询投影。它不是手动告诉每个页面“刷新一下”，而是：

```text
数据写入 store
查询/observer 被唤醒
UI 重新投影
```

你的聊天也应该是这个模式。

---

# 五、重构总原则

新的核心原则（**全新项目按此直接实现，无需为旧栈预留迁移分支**）：

```text
1. Message 永远先入库。
2. Streaming token 也是数据库事件。
3. Tool card pending 也是数据库 block。
4. Tool card ready 只更新同一个 blockID。
5. UI 只订阅数据库，不接收工具补丁。
6. 所有副作用通过一个 MessageRunActor 串行化。
7. Outbox 从数据库变化自动驱动，UI 永远不调用 push。
8. Pull / Push / Local patch 全部幂等。
9. 不实现「内存流式影子消息」与「结束后补写富卡片」的兼容路径——流式即 DB 中的 `.streaming` / `.pending` 状态。
10. 新能力合入的同时删除被替代的实现——代码、测试、模型字段、DI 注册、文档一并清理，主干上不保留 Legacy 旁路。
11. 每个 Phase 合并前通过「阶段闸门」：架构不变量 + 自动化 + 冒烟全满足；任一未达标则在本 Phase 内继续补充，不进入下一 Phase。
```

---

# 六、核心数据模型

我建议把消息建模成三层：

```text
ChatThread
  └── ChatMessage
        └── MessageBlock
              └── BlockPayload
```

并引入稳定身份：

```swift
struct MessageID: Hashable, Codable {
    let clientID: UUID
    var serverID: String?
}

struct BlockID: Hashable, Codable {
    let messageClientID: UUID
    let localKey: String
}
```

对于工具卡片，`BlockID` 不应该随机生成，而应该可推导：

```swift
BlockID(
    messageClientID: assistantMessageID,
    localKey: "tool:\(toolCallID):health-card"
)
```

这样重复生成 100 次，仍然命中同一个 block。

---

## Domain Model 骨架

```swift
enum MessageRole: String, Codable {
    case user
    case assistant
    case tool
    case system
}

enum MessageStatus: String, Codable {
    case composing        // 本地正在生成
    case streaming        // 模型流式输出中
    case waitingForTools  // 文本结束，但仍有工具卡片 pending
    case completed
    case failed
}

enum BlockKind: String, Codable {
    case text
    case reasoning
    case toolInvocation
    case healthCard
    case sleepChart
    case knowledgeCards
    case captureCard
}

enum BlockStatus: String, Codable {
    case pending
    case streaming
    case ready
    case failed
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID                 // clientMessageID
    var serverID: String?
    let threadID: UUID
    let role: MessageRole
    var status: MessageStatus
    var createdAt: Date
    var updatedAt: Date
    var logicalClock: Int64
}

struct MessageBlock: Identifiable, Codable, Equatable {
    let id: String               // stable blockID string
    let messageID: UUID
    let kind: BlockKind
    var status: BlockStatus
    var orderKey: Decimal
    var anchor: BlockAnchor?
    var payload: BlockPayload
    var revision: Int64
    var updatedAt: Date
}

enum BlockAnchor: Codable, Equatable {
    case afterBlock(String)
    case toolCall(String)
}

enum BlockPayload: Codable, Equatable {
    case text(TextPayload)
    case reasoning(ReasoningPayload)
    case toolInvocation(ToolInvocationPayload)
    case healthCard(HealthCardPayload)
    case sleepChart(SleepChartPayload)
    case knowledgeCards(KnowledgeCardsPayload)
    case captureCard(CaptureCardPayload)
}

struct TextPayload: Codable, Equatable {
    var text: String
}

struct ToolInvocationPayload: Codable, Equatable {
    let toolCallID: String
    let toolName: String
    var argumentsPreview: String?
    var resultPreview: String?
}

struct HealthCardPayload: Codable, Equatable {
    let toolCallID: String
    var title: String
    var metrics: [HealthMetric]
    var generatedAt: Date
}
```

重点是：**富卡片不是 attachment，也不是 UI patch，而是 MessageBlock 的一种。**

---

# 七、单向数据流设计

新的控制流可以像这样：

```text
UserIntent.sendMessage
→ ChatRunStore.reduce(.sendTapped)
→ MessageRunActor.startRun
→ DB.insert(user message)
→ DB.insert(assistant message status=.streaming)
→ DB.insert(text block status=.streaming)
→ DB.insert(tool placeholder block when toolCall appears)
→ DB.upsert(block payload updates)
→ DB.mark assistant completed
→ SyncEngine observes DB and syncs
→ UI observes DB and renders
```

UI 不再持有 `streamingAssistants`。

---

## 控制流中枢：Store + Actor

```swift
@MainActor
final class ChatViewStore: ObservableObject {
    @Published private(set) var viewState: ChatViewState = .empty

    private let query: ChatTimelineQuery
    private let runActor: MessageRunActor

    init(query: ChatTimelineQuery, runActor: MessageRunActor) {
        self.query = query
        self.runActor = runActor
    }

    func bind(threadID: UUID) {
        query.observeThread(threadID) { [weak self] snapshot in
            self?.viewState = ChatViewState(snapshot: snapshot)
        }
    }

    func send(text: String, threadID: UUID) {
        Task {
            await runActor.startUserMessageRun(
                threadID: threadID,
                text: text
            )
        }
    }
}
```

注意：ViewStore 不做：

```swift
pushPendingMessages
loadMessagesIfNeeded
persistStreamingAttachmentsIfNeeded
mergeStreamingAssistantPresentation
```

它只发用户意图。

---

# 八、Actor 隔离：把乱序副作用收束到一条管道

现在的 `ToolHub` 不应该随手：

```swift
Task { merge.publishCaptureCard(...) }
```

而应该返回一个结构化事件流：

```swift
enum ChatRunEvent {
    case assistantTextDelta(String)
    case reasoningDelta(String)

    case toolCallStarted(ToolCallDescriptor)
    case toolCallArgumentDelta(toolCallID: String, delta: String)
    case toolCallResultText(toolCallID: String, text: String)

    case richBlockPending(RichBlockDescriptor)
    case richBlockReady(RichBlockResult)
    case richBlockFailed(blockID: String, error: String)

    case runFinished
}
```

然后所有事件进入同一个 actor：

```swift
actor MessageRunActor {
    private let runtime: AIRuntimeService
    private let toolHub: ToolHub
    private let repository: ChatMessageRepository

    func startUserMessageRun(threadID: UUID, text: String) async {
        let userMessageID = UUID()
        let assistantMessageID = UUID()

        await repository.transaction {
            $0.insertUserMessage(
                id: userMessageID,
                threadID: threadID,
                text: text
            )

            $0.insertAssistantMessage(
                id: assistantMessageID,
                threadID: threadID,
                status: .streaming
            )

            $0.upsertBlock(
                MessageBlock.textStreaming(
                    messageID: assistantMessageID,
                    orderKey: 1000
                )
            )
        }

        do {
            let events = runtime.generateChatRunEvents(
                threadID: threadID,
                assistantMessageID: assistantMessageID,
                input: text,
                toolHub: toolHub
            )

            for try await event in events {
                await apply(
                    event,
                    threadID: threadID,
                    assistantMessageID: assistantMessageID
                )
            }

            await finishRun(assistantMessageID)
        } catch {
            await failRun(assistantMessageID, error)
        }
    }

    private func apply(
        _ event: ChatRunEvent,
        threadID: UUID,
        assistantMessageID: UUID
    ) async {
        switch event {
        case .assistantTextDelta(let delta):
            await repository.appendTextDelta(
                messageID: assistantMessageID,
                blockID: StableBlockID.text(assistantMessageID),
                delta: delta
            )

        case .reasoningDelta(let delta):
            await repository.appendReasoningDelta(
                messageID: assistantMessageID,
                blockID: StableBlockID.reasoning(assistantMessageID),
                delta: delta
            )

        case .toolCallStarted(let tool):
            await repository.upsertBlock(
                MessageBlock.toolInvocation(
                    messageID: assistantMessageID,
                    toolCallID: tool.id,
                    toolName: tool.name,
                    orderKey: tool.orderKey,
                    status: .streaming
                )
            )

            if let placeholder = tool.expectedRichBlock {
                await repository.upsertBlock(
                    MessageBlock.richPlaceholder(
                        messageID: assistantMessageID,
                        descriptor: placeholder,
                        status: .pending
                    )
                )
            }

        case .toolCallResultText(let toolCallID, let text):
            await repository.updateToolInvocationResult(
                messageID: assistantMessageID,
                toolCallID: toolCallID,
                resultPreview: text,
                status: .ready
            )

        case .richBlockPending(let descriptor):
            await repository.upsertBlock(
                MessageBlock.richPlaceholder(
                    messageID: assistantMessageID,
                    descriptor: descriptor,
                    status: .pending
                )
            )

        case .richBlockReady(let result):
            await repository.upsertBlock(
                MessageBlock.richReady(
                    messageID: assistantMessageID,
                    result: result
                )
            )

        case .richBlockFailed(let blockID, let error):
            await repository.markBlockFailed(
                blockID: blockID,
                reason: error
            )

        case .runFinished:
            await repository.markMessageCompletedIfNoPendingBlocks(
                messageID: assistantMessageID
            )
        }
    }
}
```

核心点：

```text
所有更新必须经过 MessageRunActor.apply(event)
```

不再允许：

```swift
Task { stateStore.mergeSomething(...) }
```

---

# 九、ToolHub 的新职责

旧职责：

```text
执行工具
返回文本
顺手开 Task 写富卡片到 UI cache
```

新职责：

```text
执行工具
返回 AsyncStream<ChatRunEvent>
```

示例：

```swift
protocol ChatTool {
    func execute(
        request: ToolRequest
    ) -> AsyncThrowingStream<ChatRunEvent, Error>
}
```

健康卡工具：

```swift
struct GenerateHealthCardTool: ChatTool {
    func execute(
        request: ToolRequest
    ) -> AsyncThrowingStream<ChatRunEvent, Error> {
        AsyncThrowingStream { continuation in
            let blockID = StableBlockID.richCard(
                messageID: request.assistantMessageID,
                toolCallID: request.toolCallID,
                kind: .healthCard
            )

            continuation.yield(.richBlockPending(
                RichBlockDescriptor(
                    blockID: blockID,
                    toolCallID: request.toolCallID,
                    kind: .healthCard,
                    anchor: .toolCall(request.toolCallID)
                )
            ))

            Task {
                do {
                    let healthData = try await fetchHealthData(request)
                    let payload = HealthCardPayload(
                        toolCallID: request.toolCallID,
                        title: "健康概览",
                        metrics: healthData.metrics,
                        generatedAt: Date()
                    )

                    continuation.yield(.richBlockReady(
                        RichBlockResult(
                            blockID: blockID,
                            kind: .healthCard,
                            anchor: .toolCall(request.toolCallID),
                            payload: .healthCard(payload)
                        )
                    ))

                    continuation.finish()
                } catch {
                    continuation.yield(.richBlockFailed(
                        blockID: blockID.rawValue,
                        error: error.localizedDescription
                    ))
                    continuation.finish()
                }
            }
        }
    }
}
```

这就把“后台富卡片乱飞”收束成了：

```text
ToolHub event stream → MessageRunActor → Database → UI
```

---

# 十、占位符与最终一致性

对于飞书、iMessage 这类体验，复杂卡片最好不要等 ready 后才插入。正确策略是：

```text
工具调用出现时，立即插入一个稳定位置的 pending block。
卡片完成后，原地替换 payload。
失败后，原地显示 failed state。
```

例如：

```swift
enum RichCardRenderState {
    case pending(title: String)
    case ready(payload: BlockPayload)
    case failed(message: String)
}
```

UI 渲染：

```swift
struct MessageBlockView: View {
    let block: MessageBlock

    var body: some View {
        switch block.kind {
        case .text:
            TextBlockView(block)

        case .toolInvocation:
            ToolInvocationRow(block)

        case .healthCard:
            switch block.status {
            case .pending:
                HealthCardSkeletonView()
            case .ready:
                HealthCardView(payload: block.payload.healthCard)
            case .failed:
                FailedCardView()
            case .streaming:
                HealthCardSkeletonView()
            }

        default:
            EmptyView()
        }
    }
}
```

这样不会出现“卡片突然插进来导致消息重排”的突兀感，也不会依赖后续 `finalizeStreamingPresentationBlocks` 修正顺序。

---

# 十一、全新生命周期流程图

```text
用户发送消息
  ↓
MessageRunActor 创建 user message + assistant message
  ↓
Core Data 写入 assistant message(status: streaming)
  ↓
UI 通过数据库 observer 显示 assistant 气泡
  ↓
模型开始流式输出
  ↓
text delta 追加到 text block
  ↓
模型触发 health tool
  ↓
DB upsert toolInvocation block
  ↓
DB upsert healthCard block(status: pending, anchor: toolCallID)
  ↓
UI 原地显示 HealthCardSkeleton
  ↓
工具异步获取 HealthKit / server / model structured data
  ↓
工具返回 richBlockReady event
  ↓
MessageRunActor 用稳定 blockID upsert 原 block
  ↓
UI 原地从 skeleton 切到真实 HealthCard
  ↓
模型流结束
  ↓
若无 pending block：assistant message -> completed
若仍有 pending block：assistant message -> waitingForTools
  ↓
所有 block ready/failed
  ↓
assistant message -> completed
  ↓
SyncEngine 观察 persistent history 自动 push
  ↓
远端 ack / pull merge 通过 messageID + blockID 幂等合并
```

这条链路里没有：

```text
streaming cache
手动合并 UI blocks
流式结束后补写 DB
ViewModel pushPendingMessages
延迟 1000ms load
```

---

# 十二、离线优先同步引擎

UI 绝对不应该知道：

```swift
OutboxCoordinator.pushPendingMessages(...)
```

同步引擎应该作为后台 actor 常驻：

```swift
actor SyncEngine {
    private let repository: ChatMessageRepository
    private let remote: ChatRemoteAPI
    private let historyObserver: PersistentHistoryObserver
    private var isRunning = false

    func start() async {
        for await change in historyObserver.localChanges() {
            await scheduleSync(reason: change)
        }
    }

    private func scheduleSync(reason: LocalDatabaseChange) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await pushPendingMutations()
        await pullRemoteChanges()
    }

    private func pushPendingMutations() async {
        let mutations = await repository.fetchPendingOutbox(limit: 100)

        for mutation in mutations {
            do {
                let ack = try await remote.applyMutation(mutation.payload)
                await repository.markOutboxAcked(
                    mutationID: mutation.id,
                    remoteAck: ack
                )
            } catch {
                await repository.markOutboxRetryable(
                    mutationID: mutation.id,
                    error: error
                )
            }
        }
    }

    private func pullRemoteChanges() async {
        let cursor = await repository.currentSyncCursor()
        let page = try? await remote.pullChanges(after: cursor)

        guard let page else { return }

        await repository.mergeRemoteChanges(
            page.changes,
            nextCursor: page.nextCursor
        )
    }
}
```

本地任何需要同步的 DB 写入，同时写 outbox：

```swift
struct OutboxMutation: Identifiable, Codable {
    let id: UUID
    let aggregateID: String
    let mutationKey: String
    let payload: MutationPayload
    var status: OutboxStatus
    var createdAt: Date
}
```

关键是 `mutationKey` 幂等：

```text
message:create:\(clientMessageID)
block:upsert:\(blockID):revision:\(revision)
message:status:\(messageID):completed
```

重复 push 不会产生重复远端数据。

---

# 十三、UI 响应式驱动

可以用三种方式。

### 方案 A：NSFetchedResultsController

适合 UIKit / SwiftUI bridge，成熟稳定。

```swift
final class ChatTimelineQuery: NSObject, NSFetchedResultsControllerDelegate {
    private let controller: NSFetchedResultsController<MessageBlockEntity>
    private var continuation: AsyncStream<ChatTimelineSnapshot>.Continuation?

    func snapshots(threadID: UUID) -> AsyncStream<ChatTimelineSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            try? controller.performFetch()
            continuation.yield(makeSnapshot())
        }
    }

    func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        continuation?.yield(makeSnapshot())
    }
}
```

### 方案 B：Core Data Persistent History Tracking

适合同步引擎和跨进程/后台变化。

```swift
final class PersistentHistoryObserver {
    func localChanges() -> AsyncStream<LocalDatabaseChange> {
        AsyncStream { continuation in
            NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: nil
            ) { _ in
                Task {
                    let changes = await self.fetchHistoryTransactions()
                    for change in changes {
                        continuation.yield(change)
                    }
                }
            }
        }
    }
}
```

### 方案 C：SwiftData `@Query`

如果数据模型简单可以用，但对于复杂聊天同步，我更倾向 Core Data + history tracking，因为你需要强事务、批处理、merge policy、background context 和精确 outbox。

---

# 十四、幂等合并算法

远端 pull 和本地 rich card ready 必须都走同一个 upsert 规则。

核心原则：

```text
Message 主键：clientMessageID 优先，serverMessageID 辅助映射
Block 主键：blockID，全局稳定
Mutation 主键：mutationKey
排序字段：orderKey，不靠数组位置
版本字段：revision / updatedAt / originDeviceID
```

合并规则：

```swift
struct MergePolicy {
    func merge(local: MessageBlock?, incoming: MessageBlockEnvelope) -> MessageBlock {
        guard let local else {
            return incoming.toLocalEntity()
        }

        if incoming.revision > local.revision {
            return local.replacingPayload(with: incoming)
        }

        if incoming.revision == local.revision {
            return local.mergedMetadata(with: incoming)
        }

        return local
    }
}
```

对于富卡片：

```text
pending block revision = 1
ready block revision = 2
failed block revision = 2
remote old pending 再回来，不会覆盖本地 ready
```

对于重复本地生成：

```text
同一个 blockID + 同一个 revision + 同一个 payloadHash
→ no-op
```

---

# 十五、Repository 事务骨架

```swift
protocol ChatMessageRepository: Sendable {
    func transaction(
        _ body: @Sendable (inout ChatWriteTransaction) async throws -> Void
    ) async rethrows

    func appendTextDelta(
        messageID: UUID,
        blockID: String,
        delta: String
    ) async

    func upsertBlock(_ block: MessageBlock) async

    func markMessageCompletedIfNoPendingBlocks(messageID: UUID) async
}

struct ChatWriteTransaction {
    mutating func insertUserMessage(
        id: UUID,
        threadID: UUID,
        text: String
    ) {
        // Insert message
        // Insert text block
        // Insert outbox mutation message:create
    }

    mutating func insertAssistantMessage(
        id: UUID,
        threadID: UUID,
        status: MessageStatus
    ) {
        // Insert assistant message
        // Insert outbox mutation message:create
    }

    mutating func upsertBlock(_ block: MessageBlock) {
        // Upsert by block.id
        // If changed, bump revision
        // Insert outbox mutation block:upsert:blockID:revision
    }
}
```

---

# 十六、最关键的一段注释

这段注释应该写在新的 `MessageRunActor` 或 `ChatRunPipeline` 顶部：

```swift
/// Chat run architecture:
///
/// A running assistant message is not represented by an in-memory shadow copy.
/// The assistant message and every block it may render are created in the local
/// database first, then updated by stable, idempotent events.
///
/// When a tool such as HealthCard generation is triggered, the pipeline first
/// inserts a pending MessageBlock with a deterministic blockID derived from:
///
///     assistantMessageID + toolCallID + blockKind
///
/// The UI observes Core Data and renders that pending block as a skeleton.
/// When the asynchronous tool result arrives later, it does not merge into UI
/// state directly. It emits a `richBlockReady` event back into MessageRunActor.
/// The actor serializes the event, upserts the same blockID in the database,
/// and the UI naturally re-renders from the database projection.
///
/// Because all text deltas, tool rows, pending cards, ready cards, remote pulls,
/// and retry pushes converge on the same database upsert path, arrival order
/// does not matter. Repeating the same event is a no-op, older revisions cannot
/// overwrite newer blocks, and no ViewModel code needs to manually push, pull,
/// delay, or reconcile streaming cache with persistence.
```

---

# 十七、最终目标架构

最终应该变成：

```text
SwiftUI View
  ↓ user intent
ChatViewStore
  ↓ command
MessageRunActor
  ↓ serialized ChatRunEvent
ChatRepository / Core Data
  ↓ fetched projection
ChatTimelineQuery
  ↓ snapshot
SwiftUI View

Core Data History
  ↓
SyncEngine
  ↓ push / pull
Remote Server
  ↓
ChatRepository.mergeRemoteChanges
  ↓
ChatTimelineQuery
  ↓
SwiftUI View
```

一句话总结：

```text
让数据库成为流式消息的实时投影，而不是流式结束后的归档目标。
```

这就是从“补丁式聊天 UI”升级到“工业级离线优先消息系统”的关键跃迁。

---

## 聊天消息树形时间线需求（新增，2026-05-20）

### 1. 当前缺陷

本轮排查发现，DB-first 改造后仍保留了一个旧 UI 习惯：`ChatMessageBubbleContentView` 直接 `ForEach(message.blocks)` 平铺渲染。这样会带来三类问题：

- 工具调用块与其产出的可视化卡片仍是平级节点，只靠 `toolCallID` 弱关联。
- 睡眠、运动、结构化健康、提醒等异步卡片晚到时，只能被追加为独立 block，语义上无法表达“这是某个工具调用的输出”。
- 当后台正在生成富卡片时，UI 没有明确的 pending 意图，用户只能看到工具行或空白，误以为卡片丢失。

因此，消息展示层必须从“扁平 block 列表”升级为“语义化树形时间线投影”。

### 2. 目标语义

单条助手消息由顶层时间线和工具内部子树组成：

```text
ChatMessage
└── timeline
    ├── text("今天建议多喝水")
    ├── tool(create_reminder, status: streaming/success)
    │   └── presentations
    │       └── smallTaskCard("明天 08:00 喝水提醒")
    └── text("已帮你预约明天早上 8 点提醒")
```

规则：

- 只有文本、思考、工具、图片、文件这类一等节点能直接出现在顶层时间线。
- 所有工具输出展示，包括健康结构化卡片、睡眠/运动可视化、知识卡、提醒卡、HTML 卡片、采集卡片，都必须成为对应 `toolCallID` 工具节点的子节点。
- 工具节点和子呈现按同一个 `toolCallID` 强归属；如果卡片比工具行先到达，投影层创建隐式工具占位，稍后工具行到达时填充信息，不做全局重排。
- 工具节点的 pending 与 ready 互斥：没有 ready presentation 时显示“正在创建/结构化/生成”；ready 后隐藏等待态并展示完整卡片。

### 3. 本轮落地范围

已按最终目标推进到运行时与持久化：

- `ChatMessageBubbleContentView` 不再直接平铺 `effectiveBlocks`，而是通过 `ChatMessageTimelineProjector` 投影成 `ChatMessageTimelineNode`。
- `ChatMessageTimelineProjector` 优先使用 `nodeRole / parentToolCallID` 将 presentation block 收进 `ChatToolTimelineNode.presentations`。
- `ChatToolTimelineNodeView` 对无 presentation 的工具显示旧工具执行态；对已有 presentation 的工具只渲染子卡片，避免工具行和卡片重复平铺。
- `ChatMessageBlock.render` 对 pending/streaming 的富卡片显示等待意图，例如“正在结构化健康数据...”“正在生成睡眠可视化...”“正在创建提醒...”。
- `MessageRunActor` 已从“整段 answer 一个 text block”升级为文本段状态机：工具调用首次出现时关闭当前 text segment，工具后的文本写入新的 `ChatStableBlockID.textSegment(messageID:index:)`。
- `ChatMessageBlockEntity` 已补齐 `nodeRole / parentToolCallID / parentBlockID`；服务端 `ChatMessageBlock` 同步表也保存并回传这些字段。
- `chatBlocksLinkedToToolCall()` 已删除，工具详情关联块改为读取 block 自身的父子语义字段。

这一步解决“可视化卡片不展示”“异步卡片缺少等待态”以及“文本-工具-文本无法表达”的核心问题。

### 4. 同步补强：MessageBlock Delta，而不是整条消息重传

任务卡片确认、忽略、成员切换、结构化健康卡保存等操作，本质上只修改一个 `ChatMessageBlockEntity`。这些操作不得再把整条 assistant message 的 text/tool 大块重新上送。

最新约束：

- `ChatMessageBlockEntity.isPendingSync` 是 block 级 outbox 标记。
- `updateMessageBlocks(... markPendingForSync: true)` 可以继续接收本地完整 blocks 快照，但只会把发生变化的 block 行标记为待同步。
- `ChatOutboxPipeline` 优先消费 `ChatPendingMessageBlock`，通过 `block_updates` 上送 `{ thread_id, client_message_id, block }`。
- 服务端 `ChatMessageBlock` 对 `block_updates` 只执行单行幂等 upsert，不删除同消息下未出现在 payload 里的兄弟 blocks。
- 只有新消息发送、重试失败消息等 message 生命周期事件才走完整 `messages` payload。

这条规则直接修复“任务卡片创建成功后，聊天同步把整段 answer 与全部 tool 日志一起上送”的问题。

### 5. 增量刷新契约：列表与详情只拉 delta

最新同步交互按两个入口拆开：

- 对话列表下拉刷新：`refreshThreadListIncremental()`，只执行 `pull thread deltas`，再对 changed threads 执行消息增量拉取；不主动 push 本地 outbox。
- 进入会话：先立即从本地 DB 加载最新窗口并滚动到底部，再后台执行 `syncThreadOnOpen(threadID:)`，只拉当前 thread 的消息增量；merge 后由 DB 通知刷新详情页并再次滚动到底部。
- 首次进入某会话时，若本地已有消息，则 cursor 使用 message sync cursor 或本地最新 server activity；若本地完全没有消息，则 cursor=nil 拉服务端首屏消息。
- 会话内向上翻页仍只读本地旧消息分页，不触发远端全量拉取。
- 本地待发消息/块的上送仍由 Outbox 自动调度；列表下拉和进入会话不承担主动 push 职责。

这保证了“列表刷新”和“进入会话”都只加载增量，同时保留本地优先打开体验。

### 6. 已关闭的模型升级

新的运行时块序列为：

```text
text segment 0(orderKey: 1000) = 工具前文本
tool block(orderKey: 2000, nodeRole: tool)
presentation block(parentToolCallID: toolCallID, parentBlockID: tool block id, nodeRole: toolPresentation)
text segment 1(orderKey: 3000) = 工具后文本
```

当前验收状态：

- 代码中不再需要 `chatBlocksLinkedToToolCall()` 这类为工具详情手动重建父子关系的方法。
- 不再需要任何 `stabilize*Order` 或全局数组修复排序。
- 更新一个卡片只更新对应工具节点的子 presentation block，不影响其他顶层节点。
- 文本-工具-文本可以作为三个独立顶层节点按真实生成顺序渲染。

## 附录：与「迁移 / 兼容」相关的明确不做项

全新项目下，**刻意不实现**下列仅为旧架构止血而存在的能力：

| 不做项 | 原因 |
|--------|------|
| `streamingAssistants` 与 Core Data 双真相源 | 流式内容即 DB 内 message/block 状态 |
| `persistStreamingAttachmentsIfNeeded` 类「流式结束补写」 | 富卡片在 `richBlockPending` / `richBlockReady` 事件时即 upsert 同一 `blockID` |
| `clearStreamingAssistant: false` + DB 通知 delay | UI 只订阅 DB，无影子状态可被冲掉 |
| 旧 `ChatMessageBlockBuilder` 数组 merge 作为权威合并 | 合并收敛为 `MessageRunActor` + 幂等 `blockID` upsert |
| 旧客户端消息格式 / 旧 sync cursor 的读兼容 | 与服务端按新契约一次性对齐 |

若未来确有「从旧 App 升级」需求，应单独立项做**一次性数据迁移工具**，不污染运行时聊天管线。

---

## 附录 B：建议优先清理的淘汰物对照表（SparkClient 现状 → 目标态）

下表供 greenfield 或在本仓库内落地重构时作 **删除检查清单**（实现目标态后，左侧项应从工程中消失或职责被彻底吸收）：

| 淘汰 / 收缩 | 原职责 | 替代 |
|-------------|--------|------|
| `ChatStateStore.streamingAssistants` 及 `start/update/finish/mergeStreaming*` | 内存中的助手消息与 blocks | DB 中 `message.status == .streaming` + block 行 |
| `ChatStreamingAssistantReducer.reduce` / `mergePresentation` 作为内容权威 | 流式 block 合并 | `MessageRunActor` 事件 + `upsertBlock` |
| `StructuredHealthCardMergeCoordinator` → `mergeStreamingAssistantPresentation` | 工具异步写 UI 缓存 | `ChatRunEvent.richBlockPending/Ready` → Actor → DB |
| `ChatDetailViewModel.persistStreamingAttachmentsIfNeeded` | 流式结束补写富卡片 | 工具事件即时 upsert 同一 `blockID` |
| `ChatDetailViewModel` 内 `pushPendingMessages` / DB 通知 `delay 1000` | UI 层止血同步 | `SyncEngine` + Persistent History |
| `ChatMessageBlockBuilder` 复杂数组 merge（若仍作唯一写路径） | 乱序补丁合并 | 稳定 `blockID` 幂等 upsert + 展示序由查询投影决定 |
| `ChatAssistantPartialDelta` 直驱 UI（若保留） | 多参数字段回调 | `ChatRunEvent` 进 Actor，UI 只读 Query |
| `SendChatMessageUseCase` 内 UI 回调式 `onAssistantPartial`（若改为 Query） | VM 订阅增量 | ViewModel 订阅 `ChatTimelineQuery` |
| 旧 `ChatAttachment` 承载 tool/knowledge 展示 | 重复存储 | 仅 `MessageBlock` + `BlockPayload` |
| Core Data / API 中为旧编码预留的字段 | 兼容读 | 按 `数据模型需求文档.md` 新 schema，删未使用列 |

**合并完成定义（Definition of Done）：** 上表相关符号在业务模块内 **零引用**，对应测试已迁移或删除，文档无旧流程描述，且主路径仅存在 **一条** 从用户发送到 UI 展示的管线。

---

## 附录 C：Phase 闸门速查（未达标 → 不得进入下一步）

| 若你正准备开始… | 必须先关闭的闸门（上一 Phase） |
|-----------------|--------------------------------|
| P1 Actor 流式写 DB | P0：`upsertBlock` 幂等测试绿 + schema 与需求文档一致 |
| P2 工具 loop | P1：无 `streamingAssistants` 存正文 + 文本流式冒烟绿 |
| P3 富卡片事件 | P2：tool block 入库 + INV-6 无 Task 直写 UI |
| P4 UI 纯 Query | P3：`persistStreaming*` / `mergeStreaming*Presentation` 已删且 forbidden 扫描绿 |
| P5 Sync | P4：列表仅 Query 驱动 + 切换会话冒烟绿 |
| P6 全量收尾 | P5：UI 零 `pushPending` + 离线发送恢复冒烟绿 |

**最终关门（全项目）：** 附录 B 零引用 + 附录「不做项」无运行时实现 + §分步重构 L3 全清单曾至少执行一轮回归。

```text
Gate Closed = 本 Phase §4.4 检查表全 ✅ 且 CI chat-refactor-gate 绿
Gate Open   = 任一 INV 失败 / forbidden 命中 / 本 Phase 目标未举证 → 只许补当前 Phase
```
