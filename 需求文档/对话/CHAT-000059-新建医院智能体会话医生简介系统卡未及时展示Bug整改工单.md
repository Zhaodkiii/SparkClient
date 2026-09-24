# CHAT-000059 新建医院智能体会话医生简介系统卡未及时展示 Bug 整改工单

> 工单状态：需求确认中  
> 工单类型：iOS / 医院智能体 / 新建会话 / 首屏消息同步 Bug  
> 创建时间：2026-09-05  
> 目标工程：SparkClient  
> 关联服务端：SparkService / hospital_care  
> 关联工单：CHAT-000054、CHAT-000055、CHAT-000056、CHAT-000057、CHAT-000058  
> 当前阶段：只做问题分析、需求确认和整改方案，不修改业务代码

## 1. 问题摘要

患者从院内名医列表开始咨询、创建新的医生智能体会话后，进入会话页面不能及时看到首条“医生智能体简介系统卡”。

该系统卡应展示：

- 医生头像。
- 医生姓名。
- 医生职称。
- 所属科室。
- 医院名称。
- 医生智能体标识。
- 医生公开擅长方向或简介摘要。
- 智能体服务边界。
- 点击后进入医生轻量详情页。

## 2. 诊断结论

初步结论为：**服务端已经在创建会话事务中写入简介卡，问题主要出在 iOS 新 Thread 首次打开时的本地消息加载、远端增量拉取和当前 UI 刷新之间存在时序断裂。**

不是优先怀疑服务端“没有生成卡片”，也不应通过客户端再伪造一张简介卡作为第一修复方案。

### 2.1 服务端已经做了什么

服务端创建医院智能体会话时，在同一个数据库事务内执行：

~~~text
创建 ChatThread
  → 创建 ClinicalConversationBinding
  → _create_doctor_intro_card(thread, agent)
  → 创建免责声明系统消息
  → 提交事务
~~~

当前代码位置：

- SparkService/hospital_care/services/conversation_service.py
- 函数 create_patient_conversation
- 函数 _create_doctor_intro_card
- 函数 _doctor_intro_snapshot

医生简介卡的 block kind 为 `hospitalDoctorIntroCard`，服务端 payload 同时包含 doctor、agent、professional_directions、introduction_excerpt 和 detail_route。

### 2.2 日志证明的关键事实

用户提供的脱敏日志显示：

1. HospitalCare.AgentRuntimeConfig 请求成功。
2. HospitalCare.CreateConversation 请求成功。
3. 创建接口返回新的 thread_id、agent、member、hospital 和服务状态。
4. 创建后客户端立即切换新 Thread。
5. `chat.detail.thread_switch.messages_loaded` 记录为 `count=0`。
6. 随后客户端才发起 ConversationContext 和 AgentRuntimeConfig 回源请求。

日志中出现的密钥类字段不写入本工单。若该日志中的真实凭证曾在真实环境暴露，应由管理员立即轮换相关凭证；本工单不执行轮换操作。

### 2.3 iOS 当前打开时序

当前 ChatView 的新 Thread 生命周期大致为：

~~~text
进入 .task(id: currentThreadID)
  → selectThread(id)
  → refreshChatModelPicker
  → refreshThreadImageDeliveryMode
  → loadMessagesIfNeeded(threadID)
      → 先从本地 Core Data 读取消息
      → 本地新 Thread 尚无消息，UI 得到空列表
      → Task { pullThreadMessagesIncrementalOnOpen(threadID) }
        后台启动，调用方不等待
  → resolveHospitalScope
  → 后台刷新 ConversationContext
  → 后台准备运行配置
  → mark read
  → refresh unified manifest
  → 医院会话跳过普通 guide card
  → trySendAutoSmallTaskIfReady
~~~

直接证据：

- SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift 的 `.task(id: currentThreadID)` 先调用 `loadMessagesIfNeeded`。
- SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift 的 `loadMessagesIfNeeded` 先执行本地 `satisfyLoadRequest`，之后以非等待的 `Task` 启动远端增量同步。
- 新医院会话不会走普通 `ensureFirstGuideCardInsertedForNewThreadIfNeeded`，避免插入错误的普通科普卡。

### 2.4 远端拉取后的 UI 风险

`ChatSyncEngine.pullThreadMessagesIncrementalOnOpen` 会调用远端 pull，并由 `ChatInboundPipeline` 写入 Core Data。写入后 `CoreDataChatStore` 会发布 `.messagesMerged` 通知。

`ChatDetailViewModel` 对 `.messagesMerged` 的处理会调度 `loadMessagesIfNeeded(syncRemote: false)`，理论上能把新卡重新读入 `ChatStateStore`。但当前日志只证明首轮本地加载是 0，不能证明：

- 远端 pull 是否真正拿到了新建事务中的两条系统消息。
- 新 Thread 是否有可用的远端消息 cursor。
- `ChatInboundPipeline` 是否成功映射 `hospitalDoctorIntroCard`。
- `.messagesMerged` 通知是否在当前 `selectedThreadID` 和当前成员上下文下被消费。
- 当前会话页面是否在通知刷新完成前已经切换了 Thread 或进入其他状态。

因此需要将此次问题定义为“首屏消息同步与刷新闭环缺失/不稳定”，而不是只改某个卡片 View。

## 3. 用户影响

| 场景 | 当前表现 | 影响 |
| --- | --- | --- |
| 首次创建医生智能体会话 | 会话页面可能为空或暂时没有医生简介卡 | 用户无法确认当前咨询的真实医生与智能体身份 |
| 新会话立即发送消息 | 简介卡可能晚于用户消息出现，甚至当前页面不出现 | 会话首屏顺序和身份认知不稳定 |
| 弱网或接口延迟 | 本地空列表长期保持空状态 | 用户误以为创建失败 |
| 重新进入同一会话 | 远端同步或已有本地缓存后可能正常出现 | 同一会话首次进入和再次进入体验不一致 |
| 医院会话误走普通 guide 修复 | 当前代码已主动避免 | 不允许用普通科普卡代替医生简介卡 |

## 4. 正确业务目标

新建医院智能体会话必须满足：

~~~text
CreateConversation 成功
  → 保存 hospital scope
  → 打开当前 Thread
  → 首屏优先读取本地已有消息
  → 对新建医院 Thread 强制完成一次远端消息拉取
  → 将服务端返回的简介卡和免责声明写入本地
  → 刷新当前 ChatStateStore
  → 展示医生简介卡
  → 允许用户继续咨询
~~~

要求：

- 简介卡的权威来源是服务端创建事务。
- 客户端不能根据 runtime-config 自行拼接简介卡。
- 客户端不能把普通 `chatGuideCard` 当成医院简介卡。
- 同一 Thread 的简介卡只能展示一份。
- 简介卡必须在服务端消息同步完成后进入当前消息状态。
- 消息同步失败时，页面可以展示明确的加载/重试状态，但不能静默显示“没有消息”。
- 在线咨询是否可发送沿用现有医院会话能力门禁，不由本 Bug 工单改变。

## 5. 初步修复方案

### 5.1 主方案：新建医院 Thread 的首屏消息拉取必须可观测并回灌 UI

建议调整新建 Thread 的打开编排，使“新建医院 Thread 的首次消息同步”成为当前会话初始化链路中的明确步骤：

~~~text
确定当前 Thread
  → 加载本地消息并显示
  → 判断是否为本次刚创建的医院 Thread
  → 等待一次 pullThreadMessagesIncrementalOnOpen
  → 重新读取该 Thread 的最新本地消息
  → 更新 ChatStateStore
  → 校验医院简介卡存在
  → 进入 ready
~~~

这不要求阻塞整个页面首屏：可以先显示空状态或骨架状态；但必须在首次远端同步成功后主动刷新当前消息列表，不能仅依赖一个可能错过的数据库通知。

### 5.2 推荐的状态区分

新增或明确以下初始化状态语义：

~~~text
hospitalNewThread
├── localLoading
├── remoteMessageSyncing
├── readyWithIntroCard
├── readyWithoutIntroCard
└── syncFailed
~~~

其中：

- `readyWithIntroCard`：已同步并展示医院简介卡，允许正常后续流程。
- `readyWithoutIntroCard`：远端同步成功但服务端没有简介卡，记录契约异常并展示重试/联系客服提示，不伪造卡片。
- `syncFailed`：远端消息同步失败，保留已有本地消息，显示重试，不把医院会话降级为普通会话。

### 5.3 保留现有幂等保护

服务端 `_create_doctor_intro_card` 已按 Thread 检查已有 block，具备幂等保护。客户端的重新读取也必须按 `clientMessageID` 或 block kind 去重，不能因为重试而出现两张简介卡。

### 5.4 不建议的修复

- 不在 iOS 根据 AgentRuntimeConfig 重新创建一张本地简介卡。
- 不在医院 Thread 走普通 `ensureFirstGuideCardInsertedForNewThreadIfNeeded`。
- 不把简介卡内容塞入创建接口返回的 conversation 元数据后再由客户端临时渲染为消息。
- 不通过固定延迟 sleep 等待服务端消息出现。
- 不把“首次消息数为 0”当作正常 ready 状态。
- 不通过清空整个本地数据库解决单 Thread 首屏同步问题。

## 6. 需要重点验证的根因分支

| 分支 | 检查点 | 可能结论 |
| --- | --- | --- |
| A | 新 Thread 首次 pull 请求是否返回服务端创建的简介卡和免责声明 | 若未返回，检查 cursor、pull 参数和服务端提交可见性 |
| B | pull 返回后 `ChatInboundPipeline` 是否落库两条系统消息 | 若未落库，检查 DTO 映射、block kind 和消息 owner |
| C | 落库是否发出 `.messagesMerged`，且事件 threadID 正确 | 若事件丢失，检查通知发布和线程 ID |
| D | 通知到达后当前 `selectedThreadID` 是否仍为新 Thread | 若不一致，检查切换竞态和 task 生命周期 |
| E | 通知刷新后 `ChatStateStore` 是否重新读取最新消息 | 若未刷新，补充显式 await 后的回灌逻辑 |
| F | `hospitalDoctorIntroCard` 是否能被消息解码和渲染 | 若失败，检查 JSON key、payload 包装层和 Codable 默认值 |
| G | 服务端事务提交后 pull 是否过早发生 | 若存在，增加创建接口响应可用性契约或重试策略，不使用固定 sleep |

## 7. 当前关键文件

### SparkClient

| 文件 | 当前职责 | 整改关注点 |
| --- | --- | --- |
| `SparkClient/Projects/Features/HospitalCare/Application/ResolveOrCreateHospitalConversationUseCase.swift` | 读取 runtime-config、创建会话、保存 scope | 创建结果需要向打开流程传递“本次新建医院 Thread”事实 |
| `SparkClient/Projects/Features/HospitalCare/Infrastructure/HospitalCareRemoteAPI.swift` | 调用创建会话接口 | 不新增简介卡拼装逻辑 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` | 新 Thread `.task(id:)` 初始化顺序 | 明确新建医院 Thread 的远端消息同步与 ready 条件 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` | 本地消息读取、远端拉取触发、状态刷新 | 不能只后台 fire-and-forget 后依赖通知；应提供显式刷新结果 |
| `SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` | Thread 消息增量拉取 | 增加结果可观测性或保持现有返回并由上层回读 |
| `SparkClient/Projects/Features/Chat/Infrastructure/ChatInboundPipeline.swift` | 远端消息映射和写入 | 验证医院简介 block 不丢失 |
| `SparkClient/Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift` | 本地消息落库与变更通知 | 验证 `.messagesMerged` 的 threadID 和 affected IDs |
| `SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift` | 当前 Thread 消息状态 | 远端同步结束后显式 setMessages |
| `SparkClient/Projects/Features/HospitalCare/Presentation/Components/HospitalDoctorIntroCardView.swift` | 医生简介卡渲染和详情跳转 | 保持现有卡片渲染，不承担消息创建 |
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift` | block kind、payload、消息模型 | 验证 hospitalDoctorIntroCard 解码 |

### SparkService

| 文件 | 当前职责 | 整改关注点 |
| --- | --- | --- |
| `hospital_care/services/conversation_service.py` | 创建医院会话并原子插入简介卡 | 保持当前事务和幂等逻辑 |
| `hospital_care/api/...` 消息同步接口 | 返回 Thread 消息增量 | 核对新建 Thread 首次 pull 的可见性和 cursor 语义 |
| `hospital_care/tests/test_patient_catalog.py` | 验证创建时简介卡和免责声明 | 增加首次 pull 返回两条系统消息的接口级测试 |
| `hospital_care/tests/test_agent_avatar.py` | 验证简介卡头像快照 | 保持头像字段兼容，不改变本 Bug 的消息时序目标 |

## 8. 验收标准（初稿）

### 8.1 正常创建

- 从院内名医列表点击“开始咨询”。
- 创建接口成功后打开新医院 Thread。
- 首次进入会话页面最终必须出现一张医生智能体简介卡。
- 简介卡内容来自服务端 payload，医生姓名、职称、科室和智能体 ID 正确。
- 简介卡显示顺序早于用户第一条消息。
- 简介卡点击可进入医生轻量详情页。
- 服务端免责声明仍保留，不被简介卡覆盖。

### 8.2 时序与重试

- 本地无消息时，页面显示“正在同步会话信息”或等价加载状态，不显示误导性的“暂无消息”。
- 远端同步完成后，当前页面自动刷新，不需要退出再进入。
- 首次同步失败时提供重试。
- 重试成功后只出现一张简介卡。
- 不因同步失败降级为普通会话。

### 8.3 旧会话回归

- 重新进入已有医院会话不重复插入简介卡。
- 已有医院会话中的简介卡仍正常渲染。
- 普通对话仍使用普通对话既有引导逻辑。
- 医院会话不出现普通科普问题卡替代简介卡。

## 9. 当前非目标

- 不修改医生简介卡的业务内容设计。
- 不新增另一种医院简介卡消息类型。
- 不改变医院智能体创建、绑定和 runtime-config 逻辑。
- 不改变 AI 回复、医生接管和风险等级逻辑。
- 不改变普通对话的引导卡生成策略。
- 不在客户端伪造服务端医院消息。

## 10. 一问一答确认记录

### 第 1 问：新建医院智能体会话时，简介卡的首屏展示策略是什么？

为什么要问：当前服务端已经在创建事务中写入简介卡，但 iOS 首次打开时本地消息为空，远端同步在后台执行。需要先明确“等待远端同步后再进入 ready”还是“允许先进入空会话再后台补齐”，这会直接决定 ChatView 的状态机、发送门禁和验收时序。

请选择：

- A. 允许页面先打开，但在远端消息同步完成前展示同步状态；同步成功并刷新出简介卡后才进入正常会话态（推荐）
  首屏不被网络完全阻塞，同时不会把空消息误判为正常会话；适合现有缓存优先架构。
- B. 创建接口成功后必须等待简介卡消息同步完成，再打开会话页面
  身份卡一致性最强，但弱网下进入会话明显变慢。
- C. 允许先进入正常会话，简介卡到达后再插入消息列表
  交互最快，但简介卡可能晚于用户消息，不能保证首条身份信息顺序。
- D. 创建接口直接返回简介卡，客户端先本地展示，消息同步再做服务端校准
  首屏最快，但会扩大创建接口契约和本地伪造消息的复杂度。

请选择 A、B、C 或 D。

#### 第 11 问确认

**已确认选择 A：必须确认服务端简介卡已成功落库到本地，并已按幂等规则出现在当前 Thread 消息集合中，才清除标记。**

落地约束：

- 不能以 HTTP 200、请求结束或本地消息数量大于 0 作为完成条件。
- 必须按 `threadID + blockKind + stableMessageID` 检查医院医生简介卡是否已经写入本地聊天数据库。
- 写入成功后重新读取当前 Thread 的消息集合，确认该卡可被当前消息渲染器识别，之后才能删除待同步标记。
- 重复同步不得产生第二张简介卡；已有卡片时只更新同一条记录或保持原记录，禁止追加重复卡。
- 历史会话不创建该标记，因此不因“缺少简介卡”触发补插。

## 11. 最终确认结论

| 范围 | 已确认方案 |
| --- | --- |
| 新建会话首屏 | 先进入正常会话；简介卡由远端同步完成后再插入，不阻塞会话使用 |
| 插入范围 | 仅新建医院智能体 Thread；历史会话进入不插入、不修复、不补造 |
| 插入位置 | 新建 Thread 的消息集合顶部；即使用户先发消息，成功同步后仍插入顶部 |
| 失败处理 | 正常咨询继续可用；后台自动重试 1 次，失败后显示轻量状态条和“重试” |
| 状态展示 | 顶部状态条占位；成功后原位替换为医生简介卡 |
| 手动重试 | 按钮立即禁用并显示“正在重试…”；同一 Thread 同时只允许一个重试请求 |
| 离开页面 | 取消页面 UI 订阅，不取消同步层任务；任务继续落库，返回时直接读取 |
| 前后台 | 不申请长时间后台任务；保存待同步标记，前台恢复或重进时补偿一次 |
| 持久化 | 复用现有聊天本地数据库，按账号、成员、医院、智能体、Thread 隔离 |
| 标记创建 | 服务端创建成功且 agent/member/hospital 校验通过后，先存 scope 与标记，再进入会话页 |
| 标记清除 | 只有本地确认简介卡已落库、可识别并出现在当前 Thread 消息集合后才清除 |

## 12. 问题定性与根因

### 12.1 服务端不是“没有创建简介卡”

现有服务端创建医院患者会话时，在事务内创建 Thread、临床绑定、医生简介系统卡和免责声明系统消息。服务端创建接口成功返回，说明简介卡已经具备服务端持久化条件。本工单不新增第二套简介卡创建接口，也不改服务端简介卡业务语义。

### 12.2 当前问题发生在客户端首屏与同步完成之间

当前 iOS 会话页采用本地优先加载：先从 Core Data 读取本地消息，再以非阻塞任务执行 Thread 增量同步。新建 Thread 尚无本地消息，因此首屏日志出现 `messages_loaded count=0`。远端同步完成后依赖数据库变更通知再次刷新页面，但现有链路没有把“新建医院 Thread 的简介卡同步完成”作为一个必须闭环确认的任务处理，容易出现以下窗口：

1. 页面已经显示空消息集合，用户误以为简介卡不存在。
2. 远端 pull 任务与页面订阅解耦，页面离开或 Thread 切换后结果没有可靠地回填当前 UI。
3. 仅依赖消息变更通知，不能证明简介卡已经被当前 Thread 消息集合读取并渲染。
4. 新建会话和历史会话没有明确的“只对新建会话补插”标志时，修复逻辑可能误伤历史对话。

### 12.3 修复原则

- 服务端创建仍是唯一简介卡来源，客户端不凭空生成医生身份卡。
- 新建会话需要一个持久化的待同步任务，形成“创建成功 → 标记 → 拉取 → 本地落库 → 当前集合确认 → 清标记”的闭环。
- 首屏不等待同步；同步失败不阻塞在线咨询。
- 任务属于同步层，不属于某个 SwiftUI 页面生命周期。
- 历史 Thread 没有待同步标记，禁止通过缺卡自动修复。

## 13. 完整业务流程

### 13.1 新建医院智能体会话

1. 患者在医生智能体详情页点击“开始咨询”，或在会话页点击已有“新建对话”。
2. 客户端调用现有创建患者会话接口，并传入当前成员、医院和医生智能体范围。
3. 服务端完成 agent、member、hospital 校验并创建 Thread；同时落库医生简介卡和免责声明。
4. 客户端收到成功响应后，先保存 Thread scope，再写入 `doctor_intro_pending` 待同步记录。
5. 客户端切换到新 Thread，立即展示正常会话页面和轻量状态条，不等待简介卡。
6. 同步层执行该 Thread 的增量消息拉取；优先使用现有 cursor/revision 逻辑。
7. 远端消息进入现有入站管线，按幂等键写入本地聊天数据库。
8. 同步层确认简介卡记录存在，并触发当前 Thread 消息集合重新读取。
9. 当前集合确认包含可渲染的简介卡后，状态条原位替换为简介卡，并清除待同步标记。
10. 用户随后可正常发送消息；简介卡同步失败不会改变在线咨询能力。

### 13.2 用户先发送消息

用户可以在简介卡同步完成前发送第一条消息。消息正常进入现有发送链路。简介卡同步成功后仍按 Thread 顶部位置插入，不能插入到用户消息之后，也不能覆盖用户消息。若消息排序依赖服务端时间，应使用简介卡的稳定排序规则或消息类型优先级保证顶部展示。

### 13.3 自动重试与手动重试

- 首次同步失败后自动重试 1 次。
- 第二次失败后，顶部状态条展示“医生简介暂时未加载”与“重试”。
- 用户点击“重试”后立即进入进行中状态，同一 Thread 的并发重试请求必须合并。
- 成功时将状态条替换为简介卡；失败时恢复“重试”，不影响输入框与在线消息。
- 失败次数、最近错误类型和最后尝试时间只用于诊断和展示，不向患者暴露敏感服务端错误。

### 13.4 页面离开、前台恢复和重启

- 页面离开：取消当前页面订阅，但同步层任务继续；同步结果写入本地。
- 应用进入后台：不申请长时间后台执行；待同步记录保留。
- 应用回到前台：同步层读取未完成记录，对目标 Thread 定向补偿一次。
- 应用重启：从聊天本地数据库读取待同步记录，不扫描全部历史医院会话。
- 重新进入 Thread：先显示本地状态，再优先执行一次补偿；如果简介卡已存在，直接清理残留标记。

### 13.5 历史会话

历史医院智能体 Thread 只按现有消息同步和展示，不插入新的医生简介卡。即使历史 Thread 当前消息集合没有简介卡，也不能将其当作新建 Thread 修复；历史 Thread 的已有消息仍可正常读取。

## 14. 状态机

```text
created
  └─ scope_persisted → pending
pending
  ├─ pull_started → syncing
  ├─ app_restarted/background → pending
  └─ historical_thread_guard → ignored
syncing
  ├─ remote_card_merged → verifying
  ├─ first_failure → retrying_once
  └─ page_left → syncing (task remains in sync layer)
retrying_once
  ├─ success → verifying
  └─ failure → failed
verifying
  ├─ local_card_exists + current_message_set_contains_card → completed
  └─ otherwise → failed (retain marker)
failed
  ├─ user_retry → syncing
  ├─ foreground/re-entry → syncing
  └─ online chat → continues independently
completed
  └─ marker removed; card rendered from local database
```

## 15. 本地数据与幂等设计

### 15.1 待同步记录

优先在现有聊天本地数据库增加同步任务类型或等价记录，不创建 UserDefaults 第二事实源。建议字段语义如下：

| 字段 | 说明 |
| --- | --- |
| `taskType` | 固定为 `doctorIntroCardSync` |
| `hospitalID` | 医院范围 |
| `agentID` | 医生智能体范围 |
| `memberID` | 当前患者成员范围 |
| `accountID` | 登录账号范围 |
| `threadID` | 服务端已创建的真实 Thread |
| `status` | pending / syncing / failed / completed |
| `attemptCount` | 自动与手动尝试次数 |
| `lastAttemptAt` | 最近尝试时间 |
| `lastErrorCode` | 客户端归一化错误码 |
| `createdAt` / `updatedAt` | 生命周期审计字段 |

唯一键建议为 `taskType + accountID + memberID + hospitalID + agentID + threadID`。重复收到创建结果、重复进入页面或重复触发通知时，只更新同一条任务。

### 15.2 简介卡消息幂等

服务端返回的简介卡应使用现有消息 ID 或稳定 block ID；客户端不能使用“每次拉取时生成 UUID”。合并前按 Thread、消息 ID、block kind 做去重。简介卡 payload 的医生、职称、科室、头像、智能体名称等以服务端快照为准，不在客户端重新拼接身份信息。

### 15.3 账号和成员隔离

待同步任务、消息缓存和 UI 订阅至少按 `accountID + memberID + hospitalID + agentID + threadID` 隔离。切换成员或退出登录时，取消旧 Thread 的 UI 订阅，不能把旧成员简介卡显示到新成员会话。

## 16. 服务端契约边界

本工单客户端修复优先复用现有接口和数据结构：

- 复用患者会话创建接口：返回新 Thread、绑定的医院、成员和医生智能体范围。
- 复用现有 Thread 消息增量同步接口：通过 cursor/revision 拉取医生简介卡及其他系统消息。
- 复用现有消息 block kind 和医生简介卡 payload，不新增客户端专用卡片格式。
- 服务端不因客户端首屏为空而重复创建简介卡；创建接口保持幂等。
- 若服务端返回智能体下架、成员不匹配、医院范围失效等业务错误，客户端按现有会话错误处理；不要将失败转换为普通 AI 会话。

本工单不要求修改 `AIScenarioModelBinding`、知识库、风险工具或普通对话协议。

## 17. 客户端关键文件与职责

以下位置是基于当前工程审计得到的主要落点，实际实现时以当前分支最新文件为准：

| 文件 | 责任 |
| --- | --- |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` | 判断新建医院 Thread、保存任务后进入会话、绑定页面订阅与状态条 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` | 本地首屏、远端完成后的显式重读、当前 Thread 防串线、状态机驱动 |
| `SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` | 定向拉取、自动重试一次、前台/重启补偿、任务完成确认 |
| `SparkClient/Projects/Features/Chat/Infrastructure/ChatInboundPipeline.swift` | 复用远端消息入库和幂等合并 |
| `SparkClient/Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift` | 消息与待同步记录持久化、按 scope 查询、变更通知 |
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage.swift` | 复用医生简介卡消息类型和 payload |
| `SparkClient/Projects/Features/Chat/Presentation/HospitalDoctorIntroCardView.swift` | 成功后的简介卡展示和医生详情跳转 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatMessageListView.swift`（如当前命名不同，以实际列表容器为准） | 顶部状态条/简介卡原位替换和排序 |

实现前必须先确认新建 Thread 的实际来源方法、Core Data 实体命名和同步层入口，不能仅凭文件名新增平行流程。

## 18. 伪代码级落地方案

### 18.1 创建成功后的顺序

```swift
let created = try await createHospitalConversation(scope)
try await chatStore.persistThreadScope(created.scope)
try await chatStore.upsertIntroCardSyncTask(
    threadID: created.threadID,
    scope: created.scope,
    status: .pending
)
navigateToChat(threadID: created.threadID)
```

### 18.2 新建 Thread 的同步闭环

```swift
func syncNewHospitalThread(_ task: IntroCardSyncTask) async {
    guard task.isNewHospitalThread else { return }
    do {
        try await markSyncing(task)
        try await pullThreadMessagesIncremental(task.threadID)
        guard try await chatStore.hasRenderableDoctorIntroCard(
            threadID: task.threadID,
            scope: task.scope
        ) else {
            throw IntroCardSyncError.cardNotFoundAfterPull
        }
        await refreshCurrentThreadIfStillSelected(task.threadID)
        try await markCompleted(task)
    } catch {
        try? await markFailed(task, normalizedError: error)
    }
}
```

### 18.3 页面刷新防串线

```swift
let threadID = task.threadID
await syncLayer.sync(task)
guard currentThreadID == threadID else { return }
await loadMessagesIfNeeded(for: threadID, syncRemote: false)
```

页面刷新只能更新当前仍选中的 Thread；即使同步任务属于旧 Thread，也必须保留本地结果但不得改写当前页面。

### 18.4 历史会话保护

```swift
guard threadScope.isHospitalAgent,
      threadScope.createdByNewHospitalConversation,
      pendingTaskExists(threadID: threadID) else {
    return
}
```

没有新建标记的历史 Thread 不进入简介卡补偿逻辑。

## 19. UI 原型与交互文案

### 19.1 首屏同步中

```text
┌──────────────────────────────────────────────┐
│  开开医生智能体 · 张医生 · 心内科             │
├──────────────────────────────────────────────┤
│  [系统提示] 正在加载医生简介                  │
│             您可以先正常咨询                  │
├──────────────────────────────────────────────┤
│                                              │
│              消息列表                         │
│                                              │
└──────────────────────────────────────────────┘
```

### 19.2 同步失败

```text
┌──────────────────────────────────────────────┐
│  [系统提示] 医生简介暂时未加载       [重试]   │
│  您可以继续正常咨询                          │
├──────────────────────────────────────────────┤
│              消息列表                         │
└──────────────────────────────────────────────┘
```

### 19.3 成功替换

```text
┌──────────────────────────────────────────────┐
│  [头像] 开开医生智能体        [医生智能体]   │
│         张医生 · 主任医师 · 心内科            │
│         健康信息与就医指导，不提供确诊或处方  │
│         [查看医生详情]                        │
├──────────────────────────────────────────────┤
│              用户和 AI 消息                   │
└──────────────────────────────────────────────┘
```

状态条与简介卡必须占用同一个顶部区域，避免同步成功后列表整体跳动；简介卡失败时只替换该区域，不改变输入框和既有消息。

## 20. 异常、并发和安全边界

- 网络失败：保留会话可用，任务进入 failed，按策略重试。
- 服务端返回空消息：不能清标记，进入失败状态。
- 简介卡 payload 无法解码：不能清标记，记录归一化解析错误。
- Thread 切换：旧任务可以继续落库，但不得更新新 Thread UI。
- 重复进入：通过任务唯一键和单飞锁避免重复请求。
- 退出登录：清理当前账号页面订阅；本地缓存按现有账号退出策略处理，禁止跨账号读取。
- 医院/成员/智能体校验失败：阻止后续医院 Thread 操作，按现有鉴权错误展示。
- 日志不得打印令牌、API Key、患者完整身份信息或简介卡中的敏感内容；仅记录 Thread、任务状态和归一化错误码。

## 21. 验收标准

### 功能验收

1. 新建医院医生智能体会话后，立即进入正常会话页，不等待简介卡。
2. 首屏可以暂时显示“正在加载医生简介”，用户可以发送消息。
3. 简介卡同步成功后显示在当前 Thread 消息列表顶部。
4. 用户先发送消息时，简介卡成功后仍显示在顶部，且消息不丢失、不重复。
5. 自动失败一次后自动重试一次；连续失败展示“重试”，在线咨询仍正常。
6. 手动重试期间按钮禁用，同一 Thread 不产生并发重试；成功后状态条原位变卡片。
7. 离开页面、切换 Thread、应用进入后台后，任务仍能落库；再次进入或前台恢复可补偿。
8. 只有简介卡已落库且被当前 Thread 消息集合确认后，待同步标记才被清除。
9. 历史医院会话进入时不新增简介卡、不显示简介卡同步失败、不修改历史消息。
10. 重复拉取、重复通知和重复进入不会产生重复简介卡。

### 回归验收

- 普通 AI 对话不显示医院医生简介卡逻辑。
- 成员切换不会串用旧成员的 Thread、任务或简介卡。
- 现有免责声明、风险工具、知识库同步和医生详情跳转不受影响。
- 服务端创建失败时不产生孤儿待同步任务。
- 真实设备弱网、杀进程、冷启动和重复点击场景均符合上述状态机。

## 22. 实施顺序与交付边界

1. 在测试环境确认服务端创建响应、简介卡 block kind、稳定消息 ID 和当前消息增量接口字段。
2. 在本地聊天数据库中复用或扩展同步任务存储能力，先完成 scope 隔离和唯一键。
3. 在新建会话成功路径写入 scope 与待同步标记。
4. 在同步层加入新建医院 Thread 的定向任务、一次自动重试和完成确认。
5. 在消息列表增加同步中/失败状态条，并复用现有医生简介卡渲染器。
6. 增加当前 Thread 重读与页面切换防串线逻辑。
7. 增加前台恢复、应用重启和重新进入补偿。
8. 完成单元测试、集成测试、弱网测试和手工验收。

本工单只完成问题分析和客户端整改设计，不直接修改业务代码。实施时必须保持现有服务端简介卡、消息、同步、缓存和医生详情模型复用，不新建平行协议。

## 23. 最终结论

问题本质是“服务端简介卡已创建，但 iOS 首屏本地读取先于远端同步，且新建 Thread 没有独立的可恢复同步闭环”，不是服务端没有生成简介卡。推荐修复为：新建会话成功后持久化待同步标记；会话页先正常打开并显示轻量状态条；同步层后台拉取并幂等落库；确认当前 Thread 消息集合已包含可渲染简介卡后原位替换状态条并清除标记；历史会话永不补插；失败只影响简介卡展示，不阻塞在线咨询。

#### 第 11 问确认

**已确认选择 A：必须确认服务端简介卡已成功落库到本地，并已按幂等规则出现在当前 Thread 消息集合中，才清除标记。**

落地约束：

- pull 请求返回成功不等于简介卡同步完成。
- 客户端必须在本地数据库查询当前 Thread，确认存在服务端返回的 `hospitalDoctorIntroCard`。
- 简介卡必须已经完成 DTO 映射、Core Data 落库和消息集合回读。
- 只有确认卡片可被当前消息状态读取和渲染后，才清除待同步标记。
- pull 成功但简介卡缺失、block 解码失败、落库失败或回读不到时，保留待同步标记并进入异常/重试路径。
- 历史对话不因为缺少简介卡而创建或保留本工单待同步标记。

## 11. 最终确认结论汇总

| 问题 | 最终结论 | 实施影响 |
| --- | --- | --- |
| Q1 首屏策略 | 新会话先进入正常会话，简介卡同步完成后再插入消息列表 | 不阻塞进入会话和正常发送 |
| Q2 插入范围和位置 | 只在新建对话插入；若晚于用户消息到达，固定插入消息列表顶部 | 历史对话不补插、不修复、不伪造 |
| Q3 同步失败 | 继续正常使用会话，后台重试；失败后提供重试 | 不降级为普通 AI，不出现普通科普卡 |
| Q4 自动重试次数 | 自动重试 1 次，仍失败立即提示 | 不持续循环，不影响其他 Thread |
| Q5 失败提示位置 | 消息列表顶部轻量状态条 | 成功后状态条原位替换简介卡，不遮挡输入区 |
| Q6 手动重试 | 当前 Thread single-flight，显示“正在重试…” | 防止重复请求、重复落库和重复插卡 |
| Q7 页面离开 | 取消 UI 订阅，保留同步层任务 | 结果继续落库，不强制返回原页面 |
| Q8 后台挂起 | 不申请长后台任务，保存待同步标记 | 前台恢复或重新进入时补偿一次 |
| Q9 进程终止 | 标记持久化到现有聊天本地数据库 | 下次启动由同步层统一补偿 |
| Q10 标记创建 | 服务端创建成功并完成范围校验后立即创建 | 先保存 scope 和标记，再进入会话 |
| Q11 标记清除 | 确认简介卡已落库且出现在当前 Thread 消息集合后清除 | pull 200 但缺卡时继续保留补偿状态 |

## 12. 最终业务流程

### 12.1 新建医院智能体会话

~~~text
患者点击“开始咨询”
  → ResolveOrCreateHospitalConversationUseCase
  → 读取或请求 AgentRuntimeConfig
  → POST CreateConversation(agent_id, member_id)
  → 校验返回 agent_id / member_id / hospital_id / binding
  → 持久化 HospitalConversationScope
  → 持久化 IntroCardPending(thread, account, member, agent, hospital)
  → 标记本次 Thread 为 newlyCreated
  → 切换到会话页面
  → 立即展示正常会话 UI
  → 启动当前 Thread 定向消息同步
  → 本地落库服务端简介卡和免责声明
  → 回读当前 Thread 消息集合
  → 确认 hospitalDoctorIntroCard 存在
  → 简介卡状态条替换为简介卡并固定在消息列表顶部
  → 清除 IntroCardPending
  → 允许后续正常会话流程继续
~~~

### 12.2 用户在简介卡到达前发送消息

~~~text
用户发送消息
  → 沿用现有医院会话发送门禁
  → 用户消息正常落库/发送
  → 简介卡同步完成
  → 以固定身份卡规则插入消息列表顶部
  → 不改变用户消息、AI 消息或医生消息顺序
~~~

### 12.3 页面离开、后台和重启

~~~text
页面离开
  → 取消当前页面 UI 订阅
  → 同步层继续当前 Thread 拉取
  → 成功则落库并清除待同步标记

应用进入后台
  → 不申请长时间后台任务
  → 当前未完成记录保持 pending

应用重新前台 / 重新启动
  → 同步层读取 pending 记录
  → 按 Thread single-flight 定向拉取
  → 发现简介卡并完成本地回读后清除 pending
~~~

### 12.4 历史医院会话

~~~text
进入已有医院 Thread
  → 读取本地已有消息
  → 按既有历史消息同步流程处理
  → 不调用简介卡补插逻辑
  → 不创建 IntroCardPending
  → 不因历史缺少简介卡显示本工单错误
~~~

## 13. 状态机

### 13.1 简介卡同步状态

~~~text
not_applicable
  └── 仅历史会话使用

pending
  ├── syncing
  │   ├── card_found_and_persisted → ready → clear_pending
  │   ├── pull_failed → retrying_once
  │   └── card_missing_or_decode_failed → failed
  ├── retrying_once
  │   ├── card_found_and_persisted → ready → clear_pending
  │   └── failed → failed
  └── failed
      └── user_retry → syncing
~~~

### 13.2 状态含义

| 状态 | UI | 是否允许发送 | 是否保留 pending |
| --- | --- | --- | --- |
| pending/syncing | 顶部显示“正在加载医生简介…” | 是 | 是 |
| retrying_once | 顶部显示“正在重试…” | 是 | 是 |
| failed | 顶部显示错误和“重试” | 是 | 是 |
| ready | 显示医生简介卡 | 是 | 否 |
| not_applicable | 不显示简介同步状态 | 按既有会话规则 | 否 |

## 14. 数据模型与本地持久化

### 14.1 服务端数据

服务端继续复用：

- ChatThread。
- ChatMessage。
- ChatMessageBlock。
- ChatMessageAttribution。
- ClinicalConversationBinding。
- ClinicalAgentProfile。

服务端不新增另一种简介卡消息。创建事务继续由 `create_patient_conversation` 调用 `_create_doctor_intro_card`，并使用现有 Thread/block 幂等检查。

### 14.2 客户端待同步记录

建议在现有聊天本地数据库增加一个轻量同步任务实体，或扩展现有 Thread 同步元数据；不使用 UserDefaults 作为唯一事实源。

建议字段：

~~~text
id                  UUID
ownerAccountID      Int64
hospitalID          UUID
memberID            Int
agentID             UUID
threadID            UUID
kind                hospitalDoctorIntroCard
status              pending | syncing | failed | completed
automaticRetryCount Int
manualRetryCount    Int
lastErrorCode       String?
lastAttemptAt       Date?
createdAt           Date
updatedAt           Date
~~~

建议唯一约束：

~~~text
ownerAccountID + hospitalID + memberID + agentID + threadID + kind
~~~

这样可以保证同一新建 Thread 只存在一条简介卡同步任务。

### 14.3 不保存的内容

- 不在待同步记录中保存医生简介正文。
- 不在待同步记录中保存 API Token、运行配置密钥或原始服务端响应。
- 不复制一份简介卡 JSON 到 UserDefaults。
- 不保存跨账号可复用的全局 Thread 状态。

## 15. 服务端接口契约

### 15.1 创建医院会话

~~~text
POST /api/v1/hospital-care/conversations/
~~~

请求：

~~~json
{
  "agent_id": "<agent_uuid>",
  "member_id": 767
}
~~~

当前服务端已返回 `thread_id` 和 conversation 绑定快照。服务端在创建事务中写入简介卡和免责声明。

客户端要求：

- 校验返回的 agent、member、hospital、binding 与当前配置一致。
- 校验成功后持久化 scope 和 pending 标记。
- 不要求创建接口额外返回简介卡正文。

### 15.2 医院 Thread 消息同步

继续使用现有聊天消息 pull/sync 契约，按当前 Thread 定向拉取：

~~~text
GET <现有聊天消息同步路径>
  thread_id=<thread_uuid>
  cursor=<thread_message_cursor>
  limit=<page_limit>
~~~

本 Bug 不新增单独的“简介卡接口”。同步结果必须经过现有 `ChatInboundPipeline` 和 Core Data 落库链路。

### 15.3 不新增的接口

- 不新增 `/intro-card/` 专用接口。
- 不新增客户端本地伪造消息接口。
- 不新增普通对话 fallback 接口。
- 不新增第二套医院消息同步接口。

## 16. 客户端落地位置与方案

| 文件 | 实施内容 |
| --- | --- |
| `Projects/Features/HospitalCare/Application/ResolveOrCreateHospitalConversationUseCase.swift` | 创建成功后输出“新建医院 Thread”事实；先保存 scope 和 pending |
| `Projects/Features/HospitalCare/Infrastructure/HospitalConversationScopeStore.swift` | 继续保存医院 Thread scope；与 pending 记录同账号隔离 |
| `Projects/Features/Chat/Presentation/ChatView.swift` | 新建医院 Thread 初始化时展示正常会话，并绑定简介卡同步状态；历史 Thread 不触发补插 |
| `Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` | 编排定向同步、回读消息、校验简介卡、更新当前状态 |
| `Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift` | 提供当前 Thread 定向 pull；维持 cursor 和 single-flight |
| `Projects/Features/Chat/Infrastructure/ChatSyncSupervisor.swift` | 页面离开后继续执行同步，并负责 pending 补偿调度 |
| `Projects/Features/Chat/Infrastructure/ChatInboundPipeline.swift` | 复用医院简介卡的远端消息映射和落库 |
| `Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift` | 新增/扩展 pending 元数据；保证落库通知和幂等写入 |
| `Projects/Features/Chat/Presentation/ChatStateStore.swift` | 简介卡落库后显式刷新当前 Thread 消息数组，并固定排序在顶部 |
| `Projects/Features/HospitalCare/Presentation/Components/HospitalDoctorIntroCardView.swift` | 保持现有简介卡渲染与医生详情跳转 |
| `Projects/Features/Chat/Infrastructure/ChatNotifications.swift` | 若需要，补充 pending/sync 完成的脱敏事件；不传消息正文 |

## 17. 核心伪代码

以下为设计示例，不是当前代码修改。

### 17.1 新建成功后的标记顺序

~~~swift
let created = try await remoteAPI.createConversation(agentID: agentID, memberID: memberID)
let conversation = created.conversation

try validateHospitalScope(
    conversation: conversation,
    expectedAgentID: agentID,
    expectedMemberID: memberID,
    expectedHospitalID: hospitalID,
    expectedBinding: runtimeConfig
)

let scope = HospitalConversationScope(
    threadID: created.threadID,
    agentID: agentID,
    memberID: memberID,
    hospitalID: hospitalID
)

try await scopeStore.remember(scope, accountID: accountID)
try await introCardSyncStore.upsertPending(
    accountID: accountID,
    scope: scope,
    kind: .hospitalDoctorIntroCard
)

return CreatedHospitalThread(threadID: created.threadID, scope: scope)
~~~

### 17.2 新建 Thread 消息同步

~~~swift
func syncNewHospitalThread(_ scope: HospitalConversationScope) async -> IntroCardSyncResult {
    guard await introCardSyncStore.claim(scope, kind: .hospitalDoctorIntroCard) else {
        return .alreadyRunning
    }

    do {
        try await syncSupervisor.pullThreadMessagesIncrementalOnOpen(threadID: scope.threadID)
        let messages = await loadMessagesUseCase.execute(threadID: scope.threadID, limit: nil, before: nil)

        guard messages.contains(where: { message in
            message.blocks.contains { $0.kind == .hospitalDoctorIntroCard }
        }) else {
            await introCardSyncStore.markFailed(scope, reason: .cardMissing)
            return .cardMissing
        }

        await introCardSyncStore.markCompleted(scope)
        await MainActor.run {
            stateStore.setMessages(messages, for: scope.threadID)
        }
        return .ready
    } catch {
        await introCardSyncStore.markFailed(scope, reason: .networkOrSync(error))
        return .failed
    }
}
~~~

### 17.3 自动重试一次

~~~swift
let first = await syncNewHospitalThread(scope)
if first == .failed || first == .cardMissing {
    let second = await syncNewHospitalThread(scope)
    if second == .failed || second == .cardMissing {
        await introCardSyncStore.markVisibleFailure(scope)
    }
}
~~~

实际实现必须将自动重试计数持久化，并保证页面离开后任务仍由同步层持有；以上示例只表达业务顺序。

### 17.4 历史 Thread 判断

~~~swift
guard stateStore.isThreadMarkedAsNewlyCreated(threadID) else {
    await loadExistingMessagesOnly(threadID)
    return
}

guard let scope = await scopeStore.scope(for: threadID, accountID: accountID) else {
    await loadExistingMessagesOnly(threadID)
    return
}

if scope.isHospital {
    await syncNewHospitalThread(scope)
}
~~~

历史 Thread 缺少简介卡时不得调用本地 `ensureFirstGuideCardInsertedForNewThreadIfNeeded` 作为替代。

## 18. UI 状态原型

### 18.1 同步中

~~~text
┌──────────────────────────────────────────────┐
│ 正在加载医生简介                              │
│ 医生智能体会话已打开，可以正常咨询            │
└──────────────────────────────────────────────┘
                                              ↓
用户消息、AI 消息正常展示和发送
~~~

### 18.2 失败后

~~~text
┌──────────────────────────────────────────────┐
│ 医生简介暂未加载                              │
│ 当前会话仍可正常使用                 [重试]   │
└──────────────────────────────────────────────┘
~~~

### 18.3 成功后

~~~text
┌──────────────────────────────────────────────┐
│ [医生头像] 戴雪梅                             │
│ 副主任中医师 · 内一科                         │
│ 戴雪梅医生智能体 · 医生智能体                 │
│ 健康信息与就医指导，不构成诊断或处方           │
│ 点击查看医生详情                               │
└──────────────────────────────────────────────┘
系统免责声明
患者消息 / AI 消息 / 医生消息
~~~

简介卡永远位于当前 Thread 消息列表顶部，但不应因为插入而强制把用户正在阅读的内容滚动回顶部。

## 19. 异常、并发和安全边界

### 19.1 异常处理

| 异常 | 处理 |
| --- | --- |
| 创建接口失败 | 不创建 scope、不创建 pending、不进入医院会话 |
| 创建返回范围不一致 | 视为 scopeMismatch，停止后续流程 |
| 首次消息 pull 失败 | 自动重试 1 次，失败显示顶部状态条 |
| pull 成功但缺少简介卡 | 不清除 pending，进入失败状态，不伪造卡片 |
| block 解码失败 | 不清除 pending，记录脱敏错误并允许重试 |
| Core Data 落库失败 | 保留 pending，后续补偿 |
| 页面离开 | UI 订阅取消，同步层继续 |
| 应用后台挂起 | 保存 pending，不维持长后台任务 |
| 应用重启 | 扫描 pending，定向补偿 |
| 历史会话缺卡 | 不补插、不提示本工单错误 |

### 19.2 并发规则

- 同一账号、医院、成员、智能体、Thread 的简介卡同步只能有一个活动任务。
- 自动重试和手动重试共用同一 single-flight key。
- 实时消息同步、前台恢复补偿和重新进入会话必须共享 Thread 级锁。
- 服务端简介卡创建和客户端落库都必须幂等。
- 页面销毁不能取消同步层拥有的任务。
- 已完成任务不得因重复通知再次写入或清除其他 Thread 状态。

### 19.3 隐私与日志

- 日志只记录脱敏后的 Thread 短 ID、agent 短 ID、同步阶段、重试次数、结果和错误码。
- 不记录医生简介正文、患者消息正文、Token、Cookie、Access Key 或 Secret。
- 待同步数据库记录不保存消息正文。
- 账号切换、退出登录时清理或隔离旧账号 pending 记录。
- 使用服务端返回的签名/受控头像 URL，不由客户端拼接敏感 OSS 路径。

## 20. 测试与验收

### 20.1 服务端

- 创建医院会话事务成功时，存在一条简介卡和一条免责声明。
- 重复调用相同幂等请求不会生成重复简介卡。
- 消息 pull 首次请求能够返回新建 Thread 的系统消息。
- 简介卡 payload 能被客户端现有 DTO 解码。
- 简介卡头像、医生信息和智能体信息字段完整。

### 20.2 iOS 新建流程

- 创建接口成功后能立即进入正常会话。
- 首轮本地消息为空时，页面不会被判定为“无消息完成”。
- 用户在简介卡到达前发送消息成功。
- 简介卡同步完成后自动出现在消息列表顶部。
- 简介卡晚于用户消息到达时，用户消息不丢失、不重排。
- 简介卡点击仍能进入医生轻量详情页。

### 20.3 重试和生命周期

- 自动只重试 1 次。
- 第二次失败后立即显示顶部状态条和“重试”。
- 点击手动重试后按钮禁用并显示“正在重试…”。
- 连续点击不会产生并发请求。
- 页面离开后任务仍能落库。
- 后台挂起后 pending 标记保留。
- 应用重启后能恢复 pending 并补偿。
- 成功前不清除 pending；确认卡片落库并回读后才清除。

### 20.4 历史会话

- 历史医院会话进入不补插简介卡。
- 历史医院会话缺卡不显示新建会话错误提示。
- 普通对话不触发医院简介卡同步流程。
- 重新进入已存在简介卡的 Thread 不重复展示。

### 20.5 非功能

- 同步失败不阻塞在线咨询。
- 不产生持续后台网络任务。
- 不扫描所有历史会话进行全量补偿。
- 不泄露患者消息和敏感凭证。
- 账号、成员和 Thread 切换时不会串用 pending 状态。

## 21. 实施顺序

1. 用服务端测试确认创建事务确实写入简介卡与免责声明。
2. 增加/完善 iOS 消息 pull、DTO 映射和简介卡落库的可观测日志。
3. 定义现有聊天本地数据库中的 IntroCardPending 持久化记录或等价扩展。
4. 修改创建用例输出新建 Thread 事实，并在范围校验后保存 scope 与 pending。
5. 将新建医院 Thread 的首次消息同步纳入明确的初始化编排。
6. 同步完成后显式回读当前 Thread 消息，并确认简介卡存在后更新 ChatStateStore。
7. 实现自动重试 1 次、顶部状态条和手动 single-flight 重试。
8. 实现页面离开、前台恢复、应用重启的 pending 补偿。
9. 固定简介卡在消息列表顶部的排序和幂等去重规则。
10. 增加新建、晚到、失败、重试、后台、重启和历史会话回归测试。
11. 执行真实设备/模拟器弱网验证，确认不阻塞发送。
12. 完成日志脱敏、凭证检查和最终验收。

## 22. 最终非目标

- 不改变服务端创建医院会话的业务绑定逻辑。
- 不重复实现服务端简介卡创建。
- 不在客户端根据 runtime-config 伪造简介卡。
- 不为历史会话补插或修复简介卡。
- 不修改普通对话科普卡业务。
- 不改变医院会话的 AI 回复、医生接管、风险等级和知识库同步逻辑。
- 不把同步失败降级成普通 AI 对话。
- 不新增长期后台轮询。


#### 第 1 问确认

**已确认选择 C：先进入正常会话，简介卡同步完成后再插入消息列表。**

落地约束：

- 创建接口成功并完成 Thread 绑定校验后，iOS 可以立即进入正常会话页面。
- 简介卡不作为进入会话的阻塞条件。
- 远端消息同步仍必须在新 Thread 打开后立即触发，并且同步完成后主动刷新当前 Thread 的本地消息状态。
- 简介卡到达前允许用户正常查看会话和发送消息，发送门禁继续沿用现有医院会话能力，不因本 Bug 新增阻塞。
- 简介卡到达后只能插入服务端返回的 `hospitalDoctorIntroCard`，不得由客户端根据 runtime-config 自行创建替代消息。
- 简介卡插入必须按消息 ID/block kind 幂等，重试、实时同步和重新进入不能产生重复卡片。
- 当前 UI 已有用户消息时，简介卡到达后的具体排序规则由第 2 问确认。

### 第 2 问：简介卡在用户已经发送消息后同步到达时，应插入到消息列表的什么位置？

为什么要问：选择 C 允许用户先发送消息，因此简介卡很可能晚于用户第一条消息到达。如果不固定插入规则，卡片可能出现在用户消息之后，或因本地重排导致消息顺序跳动，影响医生身份信息的可见性和会话时间线一致性。

请选择：

- A. 始终固定插入当前 Thread 消息列表最顶部（推荐）
  简介卡作为会话身份头信息，不参与普通消息时间排序；无论何时同步到达，都位于免责声明和用户消息之前。
- B. 严格按照服务端 created_at 参与时间排序
  时间线最严格，但简介卡晚到时可能出现在用户消息之后，首屏身份信息不稳定。
- C. 插入到当前可见消息底部
  实现简单且不影响当前滚动位置，但用户可能看不到简介卡，也不符合首条身份卡语义。
- D. 收到简介卡后重置消息列表并滚动到顶部
  强调身份信息，但会打断用户正在阅读或输入的会话，体验风险较高。

请选择 A、B、C 或 D。

#### 第 2 问确认

**最终确认：简介卡只在新建对话时插入；历史对话进入时不再插入。**

落地约束：

- 简介卡只属于新建医院智能体对话的初始化流程。
- 新建对话中，如果简介卡远端同步晚于用户消息到达，仍固定插入当前 Thread 消息列表最顶部。
- 历史医院对话进入时只读取和展示已有服务端消息，不再补插、修复或伪造简介卡。
- 历史对话缺少简介卡时，不因本工单自动修改历史消息数据。
- 新建流程插入简介卡时，不得清空、重建或改变已有用户消息、AI 消息和医生消息的顺序。
- 新建流程以 `hospitalDoctorIntroCard` block kind 或服务端消息 ID 做幂等判断，禁止重试产生重复卡片。

范围修订：本问最初的“所有 Thread 同步到达都固定插入顶部”方案被本次最终结论覆盖；最终只对新建对话生效。

### 第 3 问：简介卡远端同步失败时，正常会话应如何处理？

为什么要问：已确认新会话可以先正常使用。如果简介卡同步失败，需要明确是否继续允许咨询、如何提示用户以及何时重试，避免把身份卡缺失误处理成会话创建失败或普通会话降级。

请选择：

- A. 继续正常使用会话，静默后台重试；仅在连续失败后显示轻量提示和“重试”入口（推荐）
  不影响用户咨询，同时保留身份卡最终补齐能力。
- B. 继续正常使用会话，但立即显示“医生简介暂未加载”，提供手动重试
  状态透明，但首屏会出现明显错误提示。
- C. 暂停发送，必须同步成功并展示简介卡后才能继续咨询
  身份信息完整性高，但与第 1 问“先进入正常会话”的选择冲突，并会影响弱网使用。
- D. 同步失败后切换为普通 AI 对话
  可以继续使用，但会丢失医院智能体身份和服务边界，不符合院内会话隔离要求。

请选择 A、B、C 或 D。

#### 第 3 问确认

**已确认选择 A：继续正常使用会话，静默后台重试；连续失败后显示轻量提示和“重试”入口。**

落地约束：

- 新建医院智能体对话在简介卡未同步成功时，仍允许用户正常查看和发送消息。
- 简介卡同步失败不创建普通科普卡，不切换普通 AI 对话，不改变医院会话身份。
- 后台重试只针对当前新建 Thread，不能影响其他会话或触发全量消息重拉。
- 连续失败达到后续确认的阈值后，显示轻量状态提示和手动“重试”入口。
- 重试成功后将服务端简介卡插入消息列表顶部，并按幂等规则去重。
- 历史对话进入不触发简介卡补插，因此历史对话缺少简介卡不显示本工单的失败提示。

### 第 4 问：新建对话的简介卡后台重试，连续失败几次后显示“重试”入口？

为什么要问：第 3 问已经确定失败不阻塞咨询，但需要固定“静默”与“可见提示”的切换阈值。阈值过低会造成短暂网络抖动就打扰用户，阈值过高则会让简介卡长时间无反馈；同时该阈值还会影响日志、退避和测试验收。

请选择：

- A. 自动重试 3 次，仍失败后显示轻量提示和手动“重试”（推荐）
  适合当前移动端网络波动场景，重试次数明确，便于验收和日志统计。
- B. 自动重试 1 次，失败后立即显示轻量提示和手动“重试”
  用户反馈最及时，但短暂网络抖动更容易暴露错误状态。
- C. 自动重试 5 次，仍失败后才显示轻量提示和手动“重试”
  静默时间更长，但可能持续占用网络和同步任务。
- D. 不设固定次数，只要应用处于前台就持续静默重试
  卡片最终补齐概率高，但难以控制网络、耗电和任务生命周期。

请选择 A、B、C 或 D。

#### 第 4 问确认

**已确认选择 B：自动重试 1 次，失败后立即显示提示和手动“重试”入口。**

落地约束：

- 新建医院智能体 Thread 首次消息同步失败后，自动再重试 1 次。
- 第二次仍失败时立即结束自动重试，显示轻量错误状态和“重试”入口。
- 不持续循环重试，不使用固定延迟反复请求，不影响其他 Thread 的同步任务。
- 手动点击“重试”重新执行当前新建 Thread 的消息拉取，并沿用幂等插入规则。
- 失败状态不阻塞用户查看消息和发送消息，不切换普通 AI 对话。
- 历史医院对话进入不触发本工单的简介卡同步重试和失败提示。

### 第 5 问：简介卡同步失败后的提示和“重试”入口应放在哪里？

为什么要问：第 3、4 问已经允许用户继续咨询并要求失败后立即提示。需要固定提示的视觉位置，避免遮挡输入区、消息内容或被用户忽略，同时要保证重试按钮明确属于“医生简介卡同步”，而不是重新发送用户消息。

请选择：

- A. 固定显示在消息列表顶部的轻量状态条，简介卡成功后由状态条替换为简介卡（推荐）
  与简介卡最终位置一致，用户能明确知道身份卡正在加载或同步失败，不遮挡输入区。
- B. 使用页面底部 Toast，仅提示一次并提供“重试”按钮
  页面干净，但 Toast 容易消失，用户可能找不到后续重试入口。
- C. 固定显示在输入框上方的错误条，简介卡成功后自动消失
  操作入口明显，但会压缩输入区域，并容易被误解为发送失败。
- D. 只写入日志，不向用户展示提示
  界面最简单，但用户无法知道简介卡缺失，也无法主动恢复。

请选择 A、B、C 或 D。

#### 第 5 问确认

**已确认选择 A：固定显示在消息列表顶部的轻量状态条，简介卡成功后由状态条替换为简介卡。**

落地约束：

- 简介卡同步中、失败和重试状态都只显示在消息列表顶部。
- 状态条不占用输入区，不覆盖用户消息，也不伪装成消息发送失败。
- 同步成功后，状态条原位替换为服务端返回的医生智能体简介卡。
- 替换过程不清空或重排已有消息，不强制滚动当前会话。
- 失败状态条必须明确标识“医生智能体简介暂未加载”或等价语义，并提供“重试”。
- 该状态条只允许新建医院智能体 Thread 使用；历史医院对话不展示、不补插。

### 第 6 问：用户点击“重试”后，简介卡同步期间按钮和状态条如何表现？

为什么要问：手动重试可能被连续点击，也可能与实时同步、页面退出或用户发送消息并发。需要明确按钮的互斥状态和请求范围，避免重复请求、重复插卡或把重试误认为重新创建会话。

请选择：

- A. 点击后立即禁用按钮并显示“正在重试…”，当前 Thread 只允许一个重试请求；成功替换为简介卡，失败恢复“重试”（推荐）
  能防止重复请求，并且状态变化与当前 Thread 一一对应。
- B. 点击后允许重复触发多个并发重试，谁先成功谁更新页面
  响应可能更快，但会增加重复请求、竞态和重复插入风险。
- C. 点击后重新创建一个医院会话，再等待新会话的简介卡
  可以绕过当前同步异常，但会产生多余 Thread，破坏当前会话连续性。
- D. 点击后只刷新 ConversationContext，不重新拉取消息
  请求成本低，但无法解决简介卡消息尚未进入本地数据库的问题。

请选择 A、B、C 或 D。

#### 第 6 问确认

**已确认选择 A：点击后立即禁用按钮并显示“正在重试…”，当前 Thread 只允许一个重试请求；成功替换为简介卡，失败恢复“重试”。**

落地约束：

- 手动重试必须按 Thread 做 single-flight，同一 Thread 同时只能存在一个简介卡重试请求。
- 点击后立即禁用“重试”，状态条显示“正在重试…”。
- 成功后将服务端简介卡原位替换状态条，并恢复正常消息列表交互。
- 失败后保留状态条和错误提示，按钮恢复为“重试”。
- 重试不得重新创建会话、重新绑定智能体或只刷新 ConversationContext。
- 自动重试与手动重试共用同一 Thread 锁，避免两个任务并发拉取和重复写入。
- 用户重复点击、实时同步同时到达、消息通知重复到达，都不能产生重复简介卡。

### 第 7 问：用户在简介卡同步完成前离开当前新建会话页面时，后台同步任务如何处理？

为什么要问：简介卡同步是异步任务，用户可能返回名医列表、切换到其他会话或退出应用。若任务随页面销毁立即取消，简介卡可能永远没有落库；若无限后台运行，又可能继续更新已不可见页面或消耗资源。需要固定任务与页面生命周期的关系。

请选择：

- A. 取消当前页面的 UI 订阅，但保留当前 Thread 的同步任务在同步层继续完成；结果写入本地，用户下次进入直接读取（推荐）
  既不更新已离开的页面，也不丢失服务端消息；适合现有 ChatSyncEngine 的同步架构。
- B. 页面离开立即取消同步任务，下次进入时重新开始
  生命周期简单，但会增加重复请求，且可能延迟简介卡落库。
- C. 页面离开后继续同步并强制回到该会话页面展示简介卡
  能保证用户看到结果，但会打断用户当前操作，不符合会话导航预期。
- D. 页面离开后不再同步，也不保存失败状态
  资源消耗最低，但会造成新建会话长期缺少简介卡。

请选择 A、B、C 或 D。

#### 第 7 问确认

**已确认选择 A：取消当前页面的 UI 订阅，但保留当前 Thread 的同步任务在同步层继续完成；结果写入本地，用户下次进入直接读取。**

落地约束：

- 页面退出、返回名医列表或切换到其他 Thread 时，只解除当前页面对同步结果的订阅。
- `ChatSyncEngine` / `ChatSyncSupervisor` 继续负责当前 Thread 的消息拉取、落库和 cursor 保存。
- 同步完成后不强制导航回原会话，不更新已离开的页面 UI。
- 用户再次进入时优先读取本地已落库的简介卡；已存在的历史简介卡不重复插入。
- 当前 Thread 的同步任务必须继续受 single-flight 管理，避免重新进入后重复并发拉取。

### 第 8 问：应用进入后台或被系统挂起时，未完成的简介卡同步应如何处理？

为什么要问：第 7 问允许页面离开后继续由同步层完成，但 iOS 进入后台后普通异步任务可能被暂停或取消。需要明确后台时间不足时是否保存待同步标记，并在下次前台恢复或重新进入会话时补偿，避免把“页面离开”和“应用生命周期结束”混为一谈。

请选择：

- A. 后台不强行申请长时间任务；保存当前 Thread 的待同步标记，应用下次前台恢复或重新进入时优先补偿一次（推荐）
  符合 iOS 生命周期限制，控制资源消耗，并确保最终可恢复。
- B. 进入后台后申请后台执行时间，尽量完成当前同步；时间不足再保存待同步标记
  完成速度更快，但受系统后台执行时间限制，仍需补偿机制。
- C. 进入后台立即取消同步，不保存待同步标记
  实现简单，但用户再次进入前不会自动恢复，简介卡可能长期缺失。
- D. 持续保持后台网络任务直到同步成功
  对用户透明，但耗电、系统限制和审核风险较高。

请选择 A、B、C 或 D。

#### 第 8 问确认

**已确认选择 A：后台不强行申请长时间任务；保存当前 Thread 的待同步标记，应用下次前台恢复或重新进入时优先补偿一次。**

落地约束：

- 应用进入后台时不强行维持长时间网络任务，不引入持续后台轮询。
- 为当前新建医院 Thread 保存可持久化的“简介卡待同步”标记。
- 前台恢复时由同步层优先检查并补偿该 Thread；重新进入该会话时同样优先补偿一次。
- 补偿成功后清除待同步标记，并以本地已落库的服务端简介卡为准刷新页面。
- 补偿失败保留标记，进入会话时显示既定失败状态和“重试”入口。
- 历史医院对话不创建、不消费本工单的简介卡待同步标记。

### 第 9 问：应用被系统终止或用户强制退出后，简介卡待同步标记应如何恢复？

为什么要问：内存中的标记会随进程终止丢失。如果新建会话已成功但简介卡尚未同步就被系统杀掉，下一次启动必须知道哪些 Thread 需要补偿；否则只能依赖用户再次进入时的偶然请求，问题难以稳定修复和观测。

请选择：

- A. 将待同步标记持久化到现有聊天本地数据库，并以 Thread ID、账号和成员范围隔离；下次启动由同步层统一补偿（推荐）
  与现有消息、cursor 和 Thread 数据生命周期一致，应用重启后仍可恢复。
- B. 只保存在 UserDefaults，启动时读取后补偿
  实现成本较低，但与消息数据库存在双份状态，账号切换和清理容易不一致。
- C. 不保存标记，下次用户进入会话时临时判断本地是否缺简介卡
  不增加持久化字段，但无法区分新建会话和历史会话，也可能违反历史不补插规则。
- D. 每次应用启动都扫描所有医院会话并重新拉取消息
  兜底能力强，但请求量和隐私范围扩大，且会重复触发历史会话同步。

请选择 A、B、C 或 D。

#### 第 9 问确认

**已确认选择 A：将待同步标记持久化到现有聊天本地数据库，并以 Thread ID、账号和成员范围隔离；下次启动由同步层统一补偿。**

落地约束：

- 待同步状态必须跨进程终止、应用重启和前后台切换保留。
- 状态归属至少包含 accountID、memberID、threadID、agentID 和 hospitalID，禁止只用 threadID 全局判断。
- 优先复用现有聊天本地数据库和同步层，不另建 UserDefaults 与数据库的双份事实源。
- 应用启动、前台恢复和重新进入目标会话时，由同步层读取未完成记录并执行定向补偿。
- 补偿成功后清理或标记已完成；补偿失败保留失败次数和最近错误状态，供重试和日志使用。
- 仅处理新建医院智能体会话产生的记录，不扫描和修复历史医院会话。

### 第 10 问：简介卡“待同步”标记应在新建会话流程的哪个时机创建？

为什么要问：服务端创建会话成功后，客户端可能在保存 scope、切换 Thread、写入待同步状态之间被终止。创建过早会产生不存在的 Thread，创建过晚又可能丢失服务端已创建但尚未同步的 Thread。需要固定标记与创建响应的原子边界。

请选择：

- A. 服务端创建接口成功并完成 agent/member/hospital 校验后，客户端立即持久化 Thread scope 和待同步标记，再进入会话页面（推荐）
  能覆盖服务端已成功创建、但后续页面初始化被中断的窗口；标记只针对已校验的真实医院 Thread。
- B. 进入会话页面后再创建待同步标记
  页面流程较直观，但创建成功到页面初始化之间存在丢标记风险。
- C. 首次远端消息拉取失败后才创建待同步标记
  减少记录数量，但第一次拉取任务被终止时可能无法留下补偿依据。
- D. 在发起创建请求前就创建待同步标记
  可以覆盖请求中断，但可能留下没有服务端 Thread 的孤儿记录。

请选择 A、B、C 或 D。

#### 第 10 问确认

**已确认选择 A：服务端创建接口成功并完成 agent/member/hospital 校验后，客户端立即持久化 Thread scope 和待同步标记，再进入会话页面。**

落地约束：

- 创建响应返回并完成范围校验后，先保存医院 Thread scope。
- scope 保存成功后立即写入简介卡待同步记录，再允许页面切换到新 Thread。
- 任一校验失败不得写入待同步标记，也不得进入可发送的医院会话页面。
- 页面初始化中途被终止时，启动或下次进入仍能依据待同步记录补偿。
- 待同步记录只关联服务端已确认存在的 Thread，不提前创建孤儿 Thread 记录。

### 第 11 问：什么条件下可以清除新建医院会话的简介卡待同步标记？

为什么要问：仅判断“消息拉取请求成功”不够，因为服务端可能返回空消息、消息映射可能失败或简介卡 block 可能未被落库。需要明确标记是以“拉取成功”为完成，还是必须确认简介卡已经进入本地消息库，否则会出现标记过早清除、后续不再补偿的问题。

请选择：

- A. 必须确认服务端简介卡已成功落库到本地，并已按幂等规则出现在当前 Thread 消息集合中，才清除标记（推荐）
  能保证“同步完成”真正等价于“用户可展示简介卡”，服务端缺卡或客户端映射异常会继续保留补偿状态。
- B. 只要消息 pull 接口返回 200 就清除标记
  请求成功判断简单，但无法保证简介卡实际存在或能被渲染。
- C. 只要本地消息数量大于 0 就清除标记
  可能把免责声明或用户消息误当成简介卡，无法满足身份卡要求。
- D. 无论同步结果如何都保留标记，直到用户手动删除会话
  不容易丢失补偿，但会产生无效长期任务和重复请求。

请选择 A、B、C 或 D。
