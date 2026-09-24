# CHAT-000058 Pro 通用模型与医院医生智能体配置隔离需求确认工单

> 状态：需求确认中  
> 创建时间：2026-09-04  
> 适用系统：SparkService、SparkClient iOS  
> 关联工单：CHAT-000054、CHAT-000055、CHAT-000057、BACKOFFICE-HOSPITAL-AGENT-000001  
> 工作方式：逐题确认；每个答案确认后回写本工单，再继续下一题  
> 当前阶段：只维护需求与落地方案，不修改业务代码

## 1. 工单目标

隔离“Pro 普通 AI 模型目录”和“医院真实医生智能体目录”，避免医院创建的医生智能体被通用 AI bootstrap 下发给所有 Pro 用户，也避免医生智能体会话继续展示或切换到普通通用模型。

目标分为三层：

1. 通用 Pro bootstrap 不返回医院医生智能体。
2. 患者从院内名医进入医生智能体会话前，单独查询当前医生智能体的运行配置。
3. 医生智能体会话中的智能体选项只展示当前医生的智能体，不展示任何通用 AI 模型。

## 2. 问题证据

本次请求日志显示：

~~~text
GET /api/v1/ai/config/bootstrap?platform=ios&client_version=1.9.1
HTTP 200
响应体约 367 KB
chat.models 中同时存在普通模型、通用智能体和医院医生智能体绑定
~~~

日志中可以识别到：

- chat 场景共返回多条 identity=agent 的绑定。
- 其中包含多条以真实医生姓名命名的医院医生智能体。
- 所有这些绑定都被标记为 source=pro。
- iOS 无法仅根据 source=pro 区分“通用智能体”和“医院医生智能体”。
- 响应还包含模型供应商敏感配置字段。本工单不复制任何密钥值。

安全提醒：

- 本次日志已经出现明文敏感凭证，相关凭证应按泄露事件处理并尽快轮换。
- 工单、测试样例和日志不得继续复制真实凭证。
- 医院智能体专用接口是否仍向客户端返回供应商凭证，需要在后续问题中单独确认。

## 3. 已确认的业务方向

| 编号 | 已确认事项 | 状态 |
| --- | --- | --- |
| C-001 | Pro 通用 bootstrap 返回的医生智能体过多，需要从通用模型目录隔离 | 已确认 |
| C-002 | 通用 Pro bootstrap 不返回医院医生智能体 | 已确认 |
| C-003 | 进入医生智能体对话前，客户端新增当前医生智能体专用查询 | 已确认 |
| C-004 | 医生智能体会话的选项只展示当前医生的智能体 | 已确认 |
| C-005 | 医生智能体会话不展示通用 AI 模型 | 已确认 |
| C-006 | 普通 AI 对话继续使用通用 Pro 模型目录 | 已确认 |
| C-007 | 本工单继续采用一问一答、选项确认方式 | 已确认 |

## 4. 当前代码事实

### 4.1 SparkService 通用 bootstrap

当前入口：

~~~text
GET /api/v1/ai/config/bootstrap/
ai_config/views.py
AIBootstrapConfigView
~~~

当前实现特征：

- Pro 用户进入 AIBootstrapConfigView._build_pro_scenarios。
- 服务端按 scenario 查询全部 is_active=true 的 AIScenarioModelBinding。
- 查询没有区分“通用场景绑定”和“医院 ClinicalAgentProfile 专属绑定”。
- identity=agent 只表示“这是一条智能体绑定”，不能表达它是否属于医院。
- bootstrap_name 通过 AIScenarioModelBinding 主键生成技术名称。
- 当前响应会输出 endpoint 和 api_key 等运行字段。

直接原因：

~~~text
AIScenarioModelBinding(chat, active)
  ├── 普通模型 identity=model
  ├── 通用智能体 identity=agent
  └── 医院医生智能体 identity=agent

当前 bootstrap 对三类数据统一遍历并下发。
~~~

### 4.2 医院智能体与场景绑定关系

ClinicalAgentProfile 已通过 scenario_binding 外键绑定 AIScenarioModelBinding：

~~~text
ClinicalAgentProfile
  → scenario_binding_id
  → AIScenarioModelBinding
~~~

因此服务端无需通过显示名称、Prompt 文本或“医生智能体”后缀猜测归属。可以通过 ClinicalAgentProfile.scenario_binding_id 集合精确排除医院绑定。

### 4.3 SparkService 患者侧医院接口

当前已有：

~~~text
GET  /api/v1/hospital-care/hospitals/{hospital_id}/agents/
GET  /api/v1/hospital-care/agents/{agent_id}/
GET  /api/v1/hospital-care/conversations/
POST /api/v1/hospital-care/conversations/
GET  /api/v1/hospital-care/conversations/{thread_id}/context/
~~~

已有接口可以完成：

- 按医院和科室列出已发布医生智能体。
- 读取某个已发布智能体的公开资料。
- 按 agent_id + member_id 创建医院会话。
- 读取会话绑定的 hospital、agent、member、capabilities 和知识库 Manifest。

当前缺口：

- 智能体公开详情不包含该医生智能体完整运行配置。
- 会话 context 当前只返回智能体摘要，不返回可供 AI 运行时解析的单条模型配置。
- 客户端进入会话前没有独立加载“当前 agent_id 对应运行配置”的步骤。

### 4.4 iOS 通用模型目录

当前链路：

~~~text
AIConfigAPI
  → /api/v1/ai/config/bootstrap
  → AIConfigCenter
  → effectiveScenarioBundles()
  → bundles.chat.models
  → ChatDetailViewModel.chatScenarioModels
  → ChatComposerModelPickerRow
~~~

ChatDetailViewModel.refreshChatModelPicker 当前直接执行：

~~~text
chatScenarioModels = bundles.chat.models
~~~

它没有按医院会话 scope 做数据源分流，也没有排除医院医生智能体。

### 4.5 iOS 医院智能体目录和会话

当前已有：

- HospitalCareRemoteAPI.listAgents
- HospitalCareRemoteAPI.fetchAgent
- HospitalCareRemoteAPI.createConversation
- ResolveOrCreateHospitalConversationUseCase
- HospitalConversationScopeStore
- ResolveHospitalConversationScopeUseCase
- FetchHospitalConversationContextUseCase
- HospitalKnowledgeSyncCoordinator

医院目录卡片已经持有明确 agentID。创建会话时也将 agentID 发送给服务端，因此客户端不需要用医生姓名、显示名或 bootstrap_name 反查智能体。

当前 ResolveOrCreateHospitalConversationUseCase 只负责：

1. 复用最近会话，或创建新医院会话。
2. 保存 threadID、agentID、memberID、hospitalID 的 scope。

它尚未加载和保存当前医生智能体的运行配置。

### 4.6 医院会话选择器偏差

当前 ChatView 无论普通会话还是医院会话，HanlinChatComposerView 都接收同一份：

~~~text
detailViewModel.chatScenarioModels
~~~

因此医院会话仍可能展示：

- 默认通用模型。
- Pro 普通模型。
- 通用智能体。
- 其他医生的医院智能体。

这与本工单目标不一致。

## 5. 必须坚持的数据边界

### 5.1 普通 AI 对话

普通 AI 对话只消费通用模型目录：

~~~text
identity=model 的通用模型
允许公开给普通对话的通用 identity=agent
~~~

不得消费任何已被 ClinicalAgentProfile 引用的 AIScenarioModelBinding。

### 5.2 医院医生智能体对话

医院会话的数据来源必须是：

~~~text
HospitalConversationScope.agentID
  → 医院智能体专用查询
  → 当前 ClinicalAgentProfile
  → 当前 scenario_binding
  → 单条医生智能体运行配置
~~~

不得从通用 bundles.chat.models 中扫描、匹配或猜测。

### 5.3 客户端身份判断

客户端判断医院会话继续复用现有 scope 和 conversation kind：

~~~text
ConversationKind.hospitalAgent
HospitalConversationScope
~~~

不得使用以下方式判断：

- 模型 display_name 是否包含“医生”。
- 模型 name 是否以 agent- 开头。
- systemProvision 是否包含医院名称。
- identity 是否等于 agent。
- source 是否等于 pro。

以上字段都不足以证明它是当前会话绑定的医生智能体。

## 6. 初步目标流程

具体接口形态与失败策略等待逐题确认。

~~~text
App 启动或 Pro 配置刷新
  → 请求通用 bootstrap
  → 只得到普通 AI 可选模型/通用智能体
  → 不得到医院医生智能体

患者打开院内名医
  → 获取医院医生智能体目录
  → 点击某位医生
  → 已持有 hospital_id、agent_id、member_id
  → 进入会话前查询当前医生智能体专用配置
  → 校验智能体仍已发布、医院仍启用
  → 复用最近会话或创建新会话
  → 打开会话页
  → 输入栏智能体选项只有当前医生智能体
  → 不展示“默认”和任何普通通用模型
~~~

## 7. 预期服务端改造方向

### 7.1 通用 bootstrap 排除医院绑定

候选实现：

~~~python
hospital_binding_ids = ClinicalAgentProfile.objects.values_list(
    "scenario_binding_id",
    flat=True,
)

bindings = (
    AIScenarioModelBinding.objects
    .select_related("model")
    .filter(scenario=scenario_key, is_active=True)
    .exclude(id__in=hospital_binding_ids)
    .order_by("position", "id")
)
~~~

最终实现需要继续确认：

- 只排除已发布医院智能体，还是排除所有 ClinicalAgentProfile 绑定。
- 通用 identity=agent 是否继续保留在 Pro bootstrap。
- 被排除行如果当前是 chat 默认模型，默认模型如何回退。
- bootstrap revision 是否仍受医院绑定 updated_at 影响。

### 7.2 医院智能体专用配置

专用查询至少需要返回：

~~~text
agent_id
hospital_id
doctor
department
publication_status
agent name / avatar / summary
scenario_binding_id
唯一运行名称
base model
system provision
temperature
max tokens
AI tools
server tools 或服务端能力摘要
config revision
~~~

是否返回 endpoint、api_key 和完整运行配置，等待后续确认。

### 7.3 会话绑定不允许换成通用模型

医院会话的运行配置必须由服务端绑定关系决定：

~~~text
thread_id
  → ClinicalConversationBinding.agent_id
  → ClinicalAgentProfile.scenario_binding_id
~~~

客户端选择器只是展示当前绑定，不具有把医院会话改绑到普通模型的权限。

## 8. 预期 iOS 改造方向

### 8.1 双数据源

~~~text
普通会话
  → AIConfigCenter.effectiveScenarioBundles().chat.models

医院医生智能体会话
  → HospitalCare 专用单智能体配置
~~~

两类数据不合并。

### 8.2 进入会话前加载

院内名医卡片点击流程需要增加专用查询。请求成功后才能建立医生智能体运行上下文；是否必须等待查询成功才打开页面，等待后续确认。

### 8.3 医院会话模型行

医院会话可以把专用响应适配成 AIScenarioRemoteModelRow 供现有 Chat 运行时复用，但数组最多只包含当前医生智能体一条：

~~~text
chatScenarioModels = [currentDoctorAgentRow]
~~~

不得：

- 与 bundles.chat.models 合并。
- 显示“默认”选项。
- 显示其他医生智能体。
- 允许 currentModelName 切换到通用模型。

### 8.4 会话恢复

从统一会话列表打开历史医院会话时，客户端应先通过 thread context 取得 agent_id，再读取对应专用运行配置，不能依赖启动时通用 bootstrap 中存在该医生智能体。

## 9. 当前关键文件

### 9.1 SparkService

| 文件 | 当前职责 | 本工单关注点 |
| --- | --- | --- |
| ai_config/views.py | 组装 Pro bootstrap | 排除 ClinicalAgentProfile 绑定 |
| ai_config/models.py | AIScenarioModelBinding | 继续作为底层运行配置，不复制模型 |
| ai_config/tests.py | bootstrap 契约测试 | 增加医院绑定隔离测试 |
| hospital_care/models/agent_profiles.py | ClinicalAgentProfile 与 scenario_binding | 医院绑定归属的单一事实源 |
| hospital_care/models/conversations.py | Thread 与 agent 绑定 | 禁止医院会话切换到通用模型 |
| hospital_care/api/patient/views.py | 患者侧医院接口 | 新增或扩展专用智能体运行配置查询 |
| hospital_care/api/patient/urls.py | 医院患者端路由 | 注册专用查询路由 |
| hospital_care/api/patient/serializers.py | 请求校验 | 按最终接口补请求参数 |
| hospital_care/api/presenters.py | 智能体与会话输出 | 增加安全运行配置 Presenter |
| hospital_care/selectors/patient_catalog.py | 已发布智能体目录与详情 | 精确查找当前可用 agent |
| hospital_care/services/conversation_service.py | 创建医院会话 | 继续以 agent_id 固定绑定 |

### 9.2 SparkClient iOS

| 文件 | 当前职责 | 本工单关注点 |
| --- | --- | --- |
| Projects/Core/AI/AIConfigCenter.swift | 通用 AI 配置中心 | 普通会话继续使用；医院配置不写入通用 bundle |
| Projects/Core/AI/AIConfigModels.swift | AIScenarioRemoteModelRow | 评估是否复用为医生智能体运行行 |
| Projects/Features/Chat/Presentation/ChatDetailViewModel.swift | 组装选择器和校验 currentModelName | 按会话类型选择数据源 |
| Projects/Features/Chat/Presentation/ChatView.swift | 会话 scope、输入栏和发送门禁 | 医院会话只注入当前医生智能体 |
| Projects/Features/Chat/Presentation/Composer/ChatComposerModelPickerRow.swift | 模型/智能体横滑选择 | 支持医院单条锁定展示或专用展示态 |
| Projects/Features/HospitalCare/Infrastructure/HospitalCareRemoteAPI.swift | 医院 API | 增加专用查询方法 |
| Projects/Features/HospitalCare/Infrastructure/HospitalCareDTO.swift | 医院 DTO | 增加运行配置 DTO |
| Projects/Features/HospitalCare/Application/ResolveOrCreateHospitalConversationUseCase.swift | 复用/创建医院会话 | 接入进入前配置加载 |
| Projects/Features/HospitalCare/Application/ResolveHospitalConversationScopeUseCase.swift | 历史会话 scope 恢复 | 恢复后加载对应 agent 配置 |
| Projects/Features/HospitalCare/Infrastructure/HospitalConversationScopeStore.swift | 保存 thread 与 agent 关系 | 继续作为本地路由依据，不保存密钥 |
| Projects/Features/HospitalCare/Presentation/HospitalAgentDirectoryViewModel.swift | 院内名医点击流程 | 在导航前触发专用查询 |

## 10. 当前非目标

- 不删除 AIScenarioModelBinding。
- 不为医生智能体复制第二套基座模型。
- 不通过客户端名称过滤代替服务端隔离。
- 不允许医院会话回退为普通 AI 会话。
- 不改变患者、医院、医生和科室实体关系。
- 不改变现有知识库 Manifest 与同步流程。
- 不在本工单内重新设计医生工作台。
- 本阶段不修改任何业务代码。

## 11. 问答确认记录

### 第 1 问确认：专用配置接口查询标识

**已确认选择 A：按 `agent_id` 查询单个已发布医生智能体运行配置。**

落地约束：

- 新增 `GET /api/v1/hospital-care/agents/{agent_id}/runtime-config/`，只接受路径中的 `agent_id`；不接受客户端提交 `doctor_id`、模型名称或绑定 ID 作为替代查询条件。
- 接口先验证当前登录患者对医院、该医生智能体和当前患者成员的可访问性，再返回 `published` 且可供患者端使用的唯一智能体配置；未发布、停用、跨医院或无权限时统一拒绝，不返回其他智能体作为替代结果。
- 进入首次咨询时，iOS 先获取该专用配置，再创建带同一 `agent_id` 的医院会话；恢复会话时以 Thread 已绑定的 `agent_id` 为准，禁止因“同一医生最新智能体”发生静默切换。
- 医院会话的模型选择数据源只能是本接口返回的唯一医生智能体；不合并、不过滤、不回退读取 Pro Bootstrap 的 `chat.models`。
- 通用 `/api/v1/ai/config/bootstrap` 同时必须排除所有被 `ClinicalAgentProfile.scenario_binding` 引用的医生智能体绑定，避免专用配置仍从通用目录泄漏。

### 第 2 问确认：模型调用链路

**已确认选择 A：专用接口返回模型连接参数，iOS 仍直接调用模型服务。**

落地约束：

- `GET /api/v1/hospital-care/agents/{agent_id}/runtime-config/` 返回当前唯一医生智能体的公开资料、`agent_id`、绑定版本、模型标识、模型 endpoint、请求所需凭证和聊天运行参数；字段命名、认证形式和流式协议与现有 Pro `chat.models` 保持兼容，避免新建第二套聊天传输协议。
- iOS 在进入医院医生智能体对话前调用专用接口，将响应转换为仅含一个元素的医院专用模型目录；对话输入、流式回复、取消、重试和错误展示复用现有直连模型链路。
- 医院会话创建后必须持久化 `hospital_id`、`member_id`、`agent_id`、`thread_id` 与专用配置版本；发送消息时只能使用该会话 scope 中的模型参数，禁止用户在选择器中切换到普通模型或其他医生智能体。
- 专用接口不得返回其他医生、其他医院或通用 Pro 目录条目；通用 Bootstrap 也不得再返回任何医生智能体条目，两个入口互不作为兜底。
- 因已确认采用直连方式，模型 endpoint 与访问凭证会进入患者设备。服务端必须做到：仅向已鉴权且具备当前医生智能体访问权的用户签发；配置停用后立即拒绝新签发；响应禁止写入应用日志、埋点、崩溃上报、聊天正文和本地持久化缓存；iOS 仅在内存保存，退出登录、切换账号、成员或医院时清除。
- 现有附件日志中出现的真实访问密钥不得再复制到工单、前端日志或测试数据；该密钥应由凭证管理员独立完成轮换。本工单只记录风险与后续控制要求，不包含密钥值。

### 第 3 问：医生智能体专用运行配置加载失败时，患者端如何处理？

为什么要问：本期要求进入医生智能体对话前先查询专用配置；弱网、智能体刚停用或访问被撤回都可能导致加载失败。若直接回退到普通模型，会违背“院内对话只能使用当前医生智能体”的已确认边界。

请选择：

- A. 不创建或打开医生智能体会话，展示失败原因与“重试”  
  边界最严格；首次咨询不能在无有效专用配置时开始，历史会话也不允许继续发送。

- B. 有有效内存配置时允许打开并尝试发送；没有配置则显示重试（推荐）  
  首次进入必须成功获取专用配置；已打开的会话在当前前台生命周期内可使用尚未过期的内存配置继续尝试发送，但服务端/模型拒绝后立即停止，不回退到普通模型。

- C. 加载失败后自动改为普通 AI 对话  
  体验连续，但会把患者从医院医生智能体静默切换到通用模型，不符合本工单边界。

- D. 仍打开会话并允许离线编辑，网络恢复后自动补发  
  需要离线队列、配置有效期和撤销处理；患者可能误以为消息已经送达医生智能体。

请选择 A、B、C 或 D。

#### 第 3 问确认

**已确认选择 A：不创建或打开医生智能体会话，展示失败原因与“重试”。**

落地约束：

- 点击“开始咨询”或“继续咨询”后，iOS 必须先完成当前 `agent_id` 的专用运行配置查询；查询成功后才允许创建新 Thread、恢复 Thread 或打开可发送的聊天页面。
- 网络失败、服务端超时、401/403、智能体未发布/已停用、模型绑定失效或响应校验失败时，停留在院内名医列表或当前入口页，展示可理解的失败说明和“重试”；不生成空 Thread、不打开空白聊天页、不提交待发送消息。
- 不得自动切换到普通对话、通用 Pro 模型、其他医生智能体或该医生的“最新智能体”；必须由患者重新从有效的医生智能体入口发起。
- 历史医院会话在无法获取当前专用配置时仅可由服务端明确提供只读历史能力；本期默认不打开会话详情，也不允许继续发送，避免患者误以为消息已送达医生智能体。
- “重试”只重新请求同一 `agent_id` 的专用配置；成功后重新执行原操作。连续失败不改变当前医院、成员、医生或会话 scope。

### 第 4 问：进入医院医生智能体会话后，输入框的模型选择入口如何呈现？

为什么要问：当前 `ChatComposerModelPickerRow` 会显示“默认模型”和完整 `chat.models` 列表。医院会话已确认只能使用当前医生智能体；若仍保留可点击选择器，患者会误以为可以切换模型，甚至造成实现误用通用目录。

请选择：

- A. 隐藏模型选择入口，只在输入框上方显示固定的“正在咨询：{医生姓名}医生智能体”标识（推荐）  
  最符合医院服务语义。模型不可切换；名称、医生、职称和科室可点击进入医生详情。

- B. 保留选择器外观，但仅展示一个当前医生智能体且置灰不可点击  
  能说明复用了现有框架，但会保留没有实际用途的控件。

- C. 保留选择器并允许选择同一医院其他医生智能体  
  患者可在会话中换医生，但会打破“当前会话固定当前医生”的绑定关系。

- D. 保留选择器并同时显示普通模型和当前医生智能体  
  不符合已确认的隔离边界。

请选择 A、B、C 或 D。

#### 第 4 问确认

**已确认选择 B：保留选择器外观，但仅展示一个当前医生智能体且置灰不可点击。**

落地约束：

- 医院医生智能体会话继续复用 `ChatComposerModelPickerRow` 与既有输入框布局，避免单独维护一套聊天编辑器。
- 数据源只能是专用运行配置转换出的单元素列表：当前会话 scope 对应的 `agent_id`；不得混入“默认模型”、通用 Pro `chat.models`、其他医院或其他医生智能体。
- 该唯一行始终禁用点击、禁用展开、禁用切换；点击区域不发起 Bootstrap、模型选择或会话重绑请求。无障碍标签应说明“当前医生智能体，已固定，不可切换”。
- 行内展示智能体名称，并使用“医生智能体 / 已固定”状态说明；医生姓名、职称、科室取专用配置中的公开资料，不以模型内部名称代替。
- 当会话没有已验证的专用配置时，不渲染可用选择器，也不以旧的通用默认模型填充占位。

### 第 5 问：医生在后台更新、停用或更换智能体模型后，已打开的医院会话何时刷新专用配置？

为什么要问：已确认 iOS 直连模型，并在进入会话前取一次专用配置。若医生后台修改模型、停用智能体或更换绑定，患者已打开的页面可能继续使用旧内存参数；每次发消息都重拉又会增加延迟并影响对话连续性。

请选择：

- A. 本次前台会话固定进入时的配置；退出后再次进入才重新查询（推荐）  
  当前会话体验稳定；下次进入会话前重新校验，后台更新从下一次进入开始生效。若直连模型返回授权/停用错误，则立即停止发送并提示重试。

- B. 每发送一条消息前都重新查询专用配置  
  配置变化生效最快，但每条消息多一次请求，弱网下会明显拖慢发送。

- C. 在后台定时刷新并在当前会话无感替换模型参数  
  体验表面连续，但会使同一会话前后使用不同配置，且难以解释失败与回答差异。

- D. 后台更新后继续永久使用本地旧配置直到 App 重启  
  实现简单，但停用或撤销权限不会及时生效，风险较高。

请选择 A、B、C 或 D。

#### 第 5 问确认

**已确认选择 A：本次前台会话固定进入时的配置；退出后再次进入才重新查询。**

落地约束：

- iOS 成功打开医生智能体会话后，将该次专用配置保留在当前 `ChatDetailViewModel` 的内存会话范围内；当前前台会话内发送、流式回复、取消与重试均使用同一份已验证配置。
- 不在每条消息发送前重新请求运行配置，不做后台定时刷新，也不在会话展示期间无感替换模型 endpoint、凭证或模型标识。
- 用户退出会话页面、关闭该会话详情、切换医院/成员/账号或 App 终止后，专用配置均失效；下次从医院入口进入或恢复该 Thread 时必须重新请求同一 `agent_id` 的运行配置。
- 即使当前会话采用固定配置，直连模型返回 401、403、停用、凭证失效或绑定已撤回时，也必须立即停止本次发送与后续自动重试，提示患者退出后重试；不得改用普通模型或其他医生智能体。
- 新配置只影响下一次进入会话；历史消息、Thread 绑定的 `agent_id` 与医生身份展示不因配置版本变化而改写。

### 第 6 问：服务端应依据什么规则，从 Pro 通用 Bootstrap 中排除医生智能体？

为什么要问：不能仅凭名称包含“医生智能体”过滤，也不能简单排除全部 `identity=agent`，否则会误伤非医院的通用智能体。必须选择与医院业务实体有明确关系的规则，确保专用医生智能体不会再次出现在普通模型目录。

请选择：

- A. 排除所有被 `ClinicalAgentProfile.scenario_binding` 引用的 `AIScenarioModelBinding`（推荐）  
  以现有医院医生智能体实体关系为唯一事实来源；只要一个场景绑定被医生智能体资料引用，即不进入 Pro Bootstrap。

- B. 排除所有 `identity=agent` 的场景绑定  
  实现最简单，但会同时隐藏不属于医院的通用智能体。

- C. 按智能体名称、标签或提示词中包含“医生”“医院”等关键词过滤  
  无迁移成本，但不可审计、易漏项，也会误排普通内容。

- D. Pro Bootstrap 保持不变，仅在 iOS 端按医院字段过滤  
  服务端仍向不应访问的客户端返回医生智能体和模型参数，不符合隔离要求。

请选择 A、B、C 或 D。

#### 第 6 问确认

**已确认选择 A：排除所有被 `ClinicalAgentProfile.scenario_binding` 引用的 `AIScenarioModelBinding`。**

落地约束：

- `AIBootstrapConfigView` 构建 Pro `chat.models` 时，以 `ClinicalAgentProfile.scenario_binding_id` 的有效关联集合为排除条件；不使用名称、标签、提示词或客户端传参判断。
- 所有被任一 `ClinicalAgentProfile` 引用的 `AIScenarioModelBinding` 都不得进入通用 Bootstrap，即使其 `identity=agent`、`is_active=True` 或已有通用显示名称。
- 未被 `ClinicalAgentProfile` 引用的 `identity=agent` 仍按现有通用规则进入 Bootstrap，避免误伤非医院的通用智能体。
- 医生智能体改绑、停用、删除资料或解绑场景绑定后，应由 `ClinicalAgentProfile.scenario_binding` 的真实当前关系决定下一次 Bootstrap 是否可见；不得依赖缓存名称或手工维护排除名单。
- 查询应在服务端一次性形成排除集合，避免逐模型查询产生 N+1；覆盖 Bootstrap 序列化测试，验证医生智能体永不出现在通用响应中、普通智能体仍保留。

### 第 7 问：专用运行配置接口应如何绑定“当前患者成员”的访问权限？

为什么要问：同一登录账号可以切换多个成员。医生智能体、医院会话和知识库同步都已经以 `member_id` 为边界；若专用运行配置只按登录账号发放，成员切换时可能取得不属于当前就诊成员的配置，也无法与后续 Thread 的患者范围严格对应。

请选择：

- A. 请求显式携带 `member_id`，服务端校验当前登录用户对该成员的管理权及智能体可见性（推荐）  
  建议为 `GET /api/v1/hospital-care/agents/{agent_id}/runtime-config/?member_id={member_id}`。成功响应与后续创建会话使用同一成员；切换成员必须重新查询。

- B. 只按登录账号和 `agent_id` 校验，不携带 `member_id`  
  接口简单，但无法把配置签发与当前患者身份对应起来。

- C. 用 `thread_id` 推导成员，不提供 `member_id`  
  历史会话可用，但首次创建会话时没有 Thread，无法满足进入前查询。

- D. 由客户端传 `hospital_id`、`doctor_id` 和 `member_id`，服务端只校验字段存在  
  参数很多且容易伪造；医院与医生应从 `agent_id` 关联关系服务端推导。

请选择 A、B、C 或 D。

#### 第 7 问确认

**已确认选择 A：请求显式携带 `member_id`，服务端校验当前登录用户对该成员的管理权及智能体可见性。**

落地约束：

- 专用配置接口确定为 `GET /api/v1/hospital-care/agents/{agent_id}/runtime-config/?member_id={member_id}`；`agent_id` 来自院内名医卡片或历史 Thread 绑定，`member_id` 来自当前已选就诊成员。
- 服务端依次校验登录态、该登录用户对 `member_id` 的管理权、`agent_id` 对应的医院和医生实体、智能体已发布且可用、当前成员在该医院服务范围内可访问；任一条件不满足即拒绝，不返回模型连接参数。
- `hospital_id`、`doctor_id`、`scenario_binding_id`、模型名称和模型 endpoint 均由服务端从 `agent_id` 的关联实体解析，客户端不得在此接口提交这些字段影响路由。
- iOS 创建或恢复医院会话时继续带同一 `member_id`，并校验响应中的 `agent_id`、`member_id` 与当前 scope 完全一致；成员切换时废弃旧配置、清除输入中的待发送状态并重新查询。
- 请求、内存 scope 与错误日志只记录必要的内部关联 ID；不得把模型访问凭证、完整患者身份资料或响应正文写入日志、埋点或持久化缓存。

### 第 8 问：医生智能体取消发布或停用后，患者端名医列表如何展示？

为什么要问：名医列表会使用本地缓存并后台刷新。医生在后台取消发布、停用或移除患者端主智能体后，客户端可能暂时仍持有旧卡片；必须明确新患者是否还能看见、点击后如何处理，以及是否与“配置加载失败不进入会话”的规则一致。

请选择：

- A. 刷新成功后立即从名医列表移除；旧缓存卡片点击时提示“当前服务暂不可用”并可刷新（推荐）  
  新患者不再进入已停用智能体；已缓存页面不会误创建会话，且不需要单独维护禁用卡片状态。

- B. 保留卡片并显示“暂停服务”，禁止开始咨询  
  信息更透明，但需要明确历史会话、医生详情和排序中的停用状态。

- C. 已停用智能体仍可继续被新患者咨询，直到医院手动删除  
  与停用语义冲突，且容易继续使用不应签发的模型配置。

- D. 取消发布后自动切换到同一医生最新可用智能体  
  患者体验连续，但会改变患者选择的服务对象并违反当前 `agent_id` 固定原则。

请选择 A、B、C 或 D。

#### 第 8 问确认

**已确认选择 A：刷新成功后立即从名医列表移除；旧缓存卡片点击时提示“当前服务暂不可用”并可刷新。**

落地约束：

- 院内名医列表的服务端查询只返回仍可供患者端使用的已发布医生智能体；取消发布、停用、删除患者端主智能体或模型绑定不可用后，不再出现在下一次成功刷新结果。
- iOS 延续既定“先显示缓存、后台静默刷新”策略。后台刷新成功后，以服务端完整列表替换缓存和当前页面，立即移除已失效卡片；不保留“暂停服务”占位卡片。
- 旧缓存尚未刷新时，点击失效卡片仍先调用同一 `agent_id + member_id` 的专用配置接口；服务端拒绝后展示“当前服务暂不可用”，提供“刷新列表”和“返回”操作，不创建 Thread、不打开会话、不回退通用 AI。
- 刷新列表成功后若该卡片已不存在，回到更新后的名医列表；若仍存在但配置暂时请求失败，仅保留可重试错误状态，不将其视为可咨询。
- 不自动替换为同一医生的其他智能体。患者再次选择新的有效医生智能体时，按新的 `agent_id` 独立进入和建会话。

### 第 9 问：医生智能体停用后，患者已有历史医院会话如何处理？

为什么要问：患者可能已与该智能体形成 Thread。若完全删除历史消息，会破坏就医沟通的可追溯性；若继续允许发送，则会使用已停用的模型配置，与第 8 问的下架规则冲突。

请选择：

- A. 历史会话可读，禁止继续咨询；页面明确显示“当前服务已不可用”（推荐）  
  保留患者自己的历史记录与医生身份，隐藏或禁用输入区；不请求、不使用旧运行配置。

- B. 停用后完全隐藏历史会话  
  边界最简单，但患者无法回看曾经获得的健康指导与沟通记录。

- C. 历史会话仍可继续发送，直至患者主动新建咨询  
  会使已停用智能体继续对外服务，且无法保证模型绑定有效。

- D. 自动将历史会话迁移到同一医生的最新智能体并继续发送  
  会混合不同智能体、配置和回答责任，历史 Thread 的语义不再稳定。

请选择 A、B、C 或 D。

#### 第 9 问确认（已被最终范围覆盖）

**早期曾选择 A；后续最终确认改为：本工单不处理历史会话问题。**

落地约束：

- 本次不新增历史 Thread 的读取、状态判断、停用提示、只读改造、迁移、删除或兼容逻辑。
- 历史会话相关行为保持当前系统既有实现，不作为本工单验收范围。
- 若后续需要处理历史 Thread，必须创建独立工单，重新确认历史记录、权限和下架策略。

### 第 10 问：隔离上线前，普通 Pro 对话中已经选中过医生智能体的存量会话如何处理？

为什么要问：当前 Bootstrap 已经把医生智能体混入通用模型目录，部分用户可能已在非医院入口创建了使用医生智能体的普通 Thread。上线后若直接从通用目录移除，存量会话可能无法恢复或继续发送；若继续允许，会绕开医院、成员与专用配置的边界。

请选择：

- A. 存量会话保留只读；禁止继续发送，并提示从院内名医入口重新发起咨询（推荐）  
  不迁移、不篡改历史，也不让旧通用 Thread 继续绕过医院专用授权。

- B. 将存量普通 Thread 自动迁移为医院会话  
  表面连续，但旧会话通常没有可靠的 `hospital_id`、`member_id` 和患者授权上下文，迁移风险高。

- C. 存量会话继续按旧方式发送，只有新会话采用隔离规则  
  改动最小，但会长期保留绕过隔离的入口。

- D. 上线时直接删除所有此类存量会话  
  边界干净，但会不可逆地丢失用户历史消息，不适合医疗沟通记录。

请选择 A、B、C 或 D。

#### 第 10 问确认

**已确认：本工单不处理历史会话问题。**

落地约束：

- 不新增存量普通 Pro Thread 的识别、迁移、只读改造、删除、提示或兼容逻辑。
- 本工单只覆盖本次改造后的新建医院医生智能体会话，以及当前新入口所触发的运行配置查询。
- 历史会话既有行为不作为本次医院医生智能体隔离方案的验收范围；后续如需治理，另立独立工单。

### 第 11 问：专用运行配置中的提示词、模型参数和医生资料应分别以什么为准？

为什么要问：医生智能体已经同时存在 `ClinicalAgentProfile` 和 `AIScenarioModelBinding`。客户端直连模型时必须取得实际运行参数；若由客户端任意拼接医生资料、简介与提示词，容易造成展示信息与实际模型行为不一致，或绕过既有场景绑定配置。

请选择：

- A. `AIScenarioModelBinding` 是运行时唯一来源；`ClinicalAgentProfile` 只提供医院业务资料与患者端展示信息（推荐）  
  专用接口由服务端组合返回：模型 endpoint、凭证、模型名、系统提示词和采样参数来自已关联的绑定；医生姓名、职称、科室、头像、公开简介和发布状态来自 Profile。iOS 不拼接或覆盖提示词。

- B. `ClinicalAgentProfile` 作为运行时提示词唯一来源，覆盖场景绑定  
  医生编辑更直观，但会把已有场景模型配置拆成两套事实来源。

- C. iOS 依据医生资料自行拼接提示词，再叠加场景绑定参数  
  客户端可自由展示，但不同端可能生成不同提示词，且难以审计与统一更新。

- D. 专用接口只返回医生资料，iOS 从通用 Bootstrap 取得提示词和模型参数  
  会重新依赖已隔离的通用目录，不可采用。

请选择 A、B、C 或 D。

#### 第 11 问确认

**已确认选择 A：`AIScenarioModelBinding` 是运行时唯一来源；`ClinicalAgentProfile` 只提供医院业务资料与患者端展示信息。**

落地约束：

- 专用运行配置由服务端按 `agent_id` 找到 `ClinicalAgentProfile`，再沿 `scenario_binding` 读取唯一有效的 `AIScenarioModelBinding`；模型 endpoint、凭证、模型标识、系统提示词和采样参数均来自绑定实体。
- 医生姓名、职称、科室、头像、公开简介、服务边界和发布状态均来自 `ClinicalAgentProfile` 与其医生/科室关联；这些展示字段不能反向覆盖运行参数。
- iOS 只负责把接口响应映射到现有直连聊天模型配置，不自行拼接、追加、裁剪或覆盖系统提示词；客户端展示文本与模型系统提示词分离。
- 若 Profile 存在但没有有效场景绑定、绑定不活跃或模型配置不完整，专用接口失败；不得使用 Profile 文本临时组成可运行模型，也不得从 Pro Bootstrap 兜底。
- 服务端响应应携带 `agent_id`、`profile_version`、`binding_id` 或等价版本信息，便于 iOS 校验本次会话配置与智能体身份一致；不返回其他绑定作为候选列表。

### 第 12 问：医生智能体专用运行配置在 iOS 上应缓存到什么范围？

为什么要问：直连方案会把模型 endpoint、凭证和系统提示词下发到患者设备。医院智能体页面可以使用缓存提升打开速度，但长期保存会扩大凭证泄露、成员串用和停用后继续调用的风险，必须与普通知识库目录缓存区分。

请选择：

- A. 仅保存在当前前台会话内存中，离开会话立即清除（推荐）  
  与已确认的“进入时获取、前台会话固定”一致；不写入 Core Data、UserDefaults、文件、Keychain、普通缓存或崩溃日志。

- B. 按 `account_id + member_id + hospital_id + agent_id` 写入本地持久化缓存  
  再次进入速度快，但模型凭证和提示词会长期留在设备上，停用与退出清理复杂。

- C. 写入 Keychain，直到智能体版本变化后再删除  
  比普通文件安全，但仍属于长期保存，而且无法仅依赖版本变化覆盖立即停用场景。

- D. 复用普通 Pro Bootstrap 的全局模型缓存  
  会重新混合通用模型与医院医生智能体，且无法按当前成员和智能体隔离。

请选择 A、B、C 或 D。

#### 第 12 问确认

**已确认选择 C：写入 Keychain，直到智能体版本变化后再删除。**

落地约束：

- Keychain 缓存键必须至少包含 `account_id`、`member_id`、`hospital_id`、`agent_id` 和运行配置版本；不同账号、成员、医院或智能体不得共享同一配置记录。
- 缓存内容仅限本次直连所需的模型运行配置，不保存完整 Pro Bootstrap，不保存其他医生智能体，不保存医院列表或患者会话正文。
- 智能体版本变化时删除旧版本配置并写入新版本；版本值以服务端专用接口返回为准，不能由 iOS 根据名称、时间或本地递增猜测。
- 由于 Keychain 属于长期保存，退出登录、切换账号、切换成员、切换医院、服务端明确撤销访问或智能体停用时，必须立即删除对应配置；“版本变化后删除”不是唯一清理条件。
- Keychain 读取失败、解密失败、字段缺失或版本不匹配时，按未命中处理并重新请求专用接口；不得从通用 Bootstrap 恢复。
- 日志、埋点、崩溃信息和调试导出中不得记录 endpoint、凭证、系统提示词或 Keychain 原文。

### 第 13 问：进入医生智能体会话时，Keychain 中已有配置是否仍需服务端重新校验？

为什么要问：第 12 问允许长期保存 Keychain，但第 8、9 问已经确认智能体停用后不得新建或继续发送。若客户端仅依据本地版本直接使用，服务端刚停用智能体时仍可能继续直连，因此必须明确本地缓存的使用前置条件。

请选择：

- A. 每次进入会话前都请求专用接口重新校验；成功后更新 Keychain，再使用配置（推荐）  
  Keychain 只作为安全保存和响应复用容器，不作为是否可用的事实来源；停用、撤销或权限变化可及时生效。

- B. 先直接使用 Keychain，后台再静默校验  
  首屏更快，但在校验完成前可能已使用失效配置，不符合“配置失败不进入/不发送”的边界。

- C. 只有检测到版本变化时才请求服务端  
  无法发现同版本内的停用、凭证撤销或成员权限变化。

- D. Keychain 配置永远优先，服务端只在发送失败后校验  
  会把安全控制推迟到模型拒绝之后，可能造成错误请求或敏感参数泄露。

请选择 A、B、C 或 D。

#### 第 13 问确认

**已确认选择 B：先直接使用 Keychain，后台再静默校验。**

落地约束：

- Keychain 命中、数据完整且版本可识别时，iOS 可以先打开医生智能体会话，并使用本地配置完成首屏与发送；同时在后台请求同一 `agent_id + member_id` 的专用接口进行校验和刷新。
- Keychain 未命中、读取失败、字段缺失、无法解密或没有可识别版本时，仍执行第 3 问规则：不得创建或打开可发送的医生智能体会话，只展示失败原因与“重试”。
- 后台校验成功时，用服务端返回的新配置替换 Keychain 中对应版本，并保持当前前台会话继续使用“进入时固定”的配置；新配置从下次进入会话开始生效。
- 后台校验失败时，不把普通模型或其他医生智能体作为替代；应由下一题定义当前已打开会话的发送收敛方式。
- 后台校验请求不得阻塞已经打开的会话首屏，但其结果必须更新本地可用状态，避免页面继续显示“配置已确认”而实际已被撤回。

### 第 14 问：后台校验发现 Keychain 配置已失效时，当前已打开的医院会话如何处理？

为什么要问：第 13 问允许使用缓存配置快速打开页面，但后台校验可能发现智能体已停用、成员权限被撤回、模型绑定失效或凭证已过期。此时必须明确当前页面还能否继续发消息，以及如何避免用户误以为消息已经由医生智能体处理。

请选择：

- A. 校验失败后立即停止后续发送，当前正在进行的请求允许完成；页面显示“当前服务已不可用”  
  已发出的请求不强行中断，新的发送、重试和自动重试立即禁用；若当前请求失败，按失败消息展示，不改投普通 AI。

- B. 当前正在进行的请求也立即取消，随后停止发送  
  收敛最严格，但可能丢失已经发出的用户消息对应的模型响应，需要清楚标记请求状态。

- C. 当前会话继续使用 Keychain，等用户退出后再停止  
  能保持连续体验，但会继续使用服务端已判定失效的配置。

- D. 校验失败后自动重新请求其他有效医生智能体  
  会改变当前会话的 `agent_id` 和医生身份，不符合会话固定原则。

请选择 A、B、C 或 D。

#### 第 14 问确认

**已确认选择 A：校验失败后立即停止后续发送，当前正在进行的请求允许完成；页面显示“当前服务已不可用”。**

落地约束：

- 后台校验返回明确失败后，iOS 立即将当前医院会话置为不可发送；输入框、发送、重试和自动重试均禁用，模型选择器保持置灰但不再显示为可用。
- 已经发往模型服务的请求不强制取消，允许当前流式响应完成；完成后不再启动下一次请求。若当前请求失败，按原请求失败状态展示，不重新投递、不改投普通 AI。
- 页面统一展示“当前服务已不可用”，并提供返回名医列表或重新刷新入口；重新进入时重新走 `agent_id + member_id` 专用配置流程。
- Keychain 中对应的失效配置立即删除；不因当前请求尚未完成而保留到下一次进入。
- 失效事件不得修改历史消息的发送者、医生智能体名称或 Thread 绑定；仅更新当前会话的可发送状态与提示状态。

### 第 15 问：专用运行配置接口的异常响应是否需要区分具体原因？

为什么要问：客户端需要分别处理网络失败、登录失效、成员无权访问、智能体已停用和模型绑定失效。若服务端全部返回同一个错误，iOS 无法决定是展示重试、要求重新登录，还是返回名医列表并清理缓存。

请选择：

- A. 使用稳定业务错误码区分原因，HTTP 状态码与现有接口约定保持一致（推荐）  
  至少区分未登录/令牌失效、成员无权、智能体不存在或已下架、运行配置失效、请求超时/服务暂不可用；客户端按业务码映射提示，不依赖错误文案。

- B. 所有失败统一返回 404“智能体不存在”  
  客户端处理简单，但无法区分权限、网络和配置故障，也不利于排查。

- C. 所有失败统一返回 403“无权限”  
  能隐藏资源状态，但会把网络、停用和登录失效错误混为一谈。

- D. 接口始终返回 200，由客户端解析 `message` 文案判断失败原因  
  容易受文案变更影响，且会把失败响应误当成有效运行配置。

请选择 A、B、C 或 D。

#### 第 15 问确认

**已确认选择 A：使用稳定业务错误码区分原因，HTTP 状态码与现有接口约定保持一致。**

落地约束：

- 专用配置接口至少区分：未登录/令牌失效、成员无权、智能体不存在或已下架、运行配置失效、请求超时和服务暂不可用；客户端根据业务码映射页面状态，不解析错误文案决定流程。
- 认证失效进入现有登录恢复流程；成员无权清理当前成员对应的专用配置并返回成员选择；智能体下架/不存在返回名医列表刷新；运行配置失效清理 Keychain 并停止当前会话后续发送；网络/服务暂不可用保留可重试入口。
- 服务端业务码、HTTP 状态码、客户端状态枚举和用户提示需要在接口契约中固定，新增码不得复用既有含义；响应失败时不携带 endpoint、凭证、系统提示词或其他医生智能体候选。
- 错误响应可以包含内部 request ID 供排查，但不得把模型访问密钥和完整患者数据放入 request ID、日志或客户端错误上报。

### 第 16 问：院内名医列表的数据源应如何隔离？

为什么要问：当前 Pro Bootstrap 的 `chat.models` 混有通用模型、通用智能体和医院医生智能体。即使客户端最终只展示医生卡片，也不能继续从 Bootstrap 取院内目录，否则会让医院数据边界依赖客户端过滤。

请选择：

- A. 完全使用现有医院专用智能体目录接口，不从 Pro Bootstrap 组装名医列表（推荐）  
  继续使用 `GET /api/v1/hospital-care/hospitals/{hospital_id}/agents/`；列表只由医院、科室、医生和已发布主智能体关系返回，进入会话后再按 `agent_id` 查询专用运行配置。

- B. 继续从 Pro Bootstrap 取模型，再由 iOS 过滤出医院医生智能体  
  会让服务端继续向客户端下发不应进入通用目录的医生模型，隔离不完整。

- C. 新增一个全局智能体目录接口，同时保留医院专用接口  
  会出现两个列表事实来源，需要额外处理排序、发布状态和缓存一致性。

- D. 名医列表由本地固定配置生成，服务端只提供头像和简介  
  无法及时反映医院后台发布、停用、主智能体变更和成员可见性。

请选择 A、B、C 或 D。

#### 第 16 问确认

**已确认选择 A：完全使用现有医院专用智能体目录接口，不从 Pro Bootstrap 组装名医列表。**

落地约束：

- 院内名医列表继续调用 `GET /api/v1/hospital-care/hospitals/{hospital_id}/agents/`；服务端按医院、科室、医生、患者端主智能体和发布状态返回卡片数据。
- 列表页面不读取、不解析、不过滤 Pro Bootstrap 的 `chat.models`；Pro Bootstrap 只服务普通 AI 对话目录，且按第 6 问规则排除医院医生智能体绑定。
- 点击医生卡片后，iOS 使用卡片中的 `agent_id` 和当前 `member_id` 请求专用运行配置；专用配置成功后才创建或恢复医院 Thread。
- 名医列表缓存与 Pro Bootstrap 缓存分离，缓存键包含医院上下文；后台刷新成功后按第 8 问规则移除已停用或已取消发布的医生智能体。
- 列表响应只返回患者端所需公开资料和状态，不返回模型 endpoint、访问凭证、系统提示词或其他智能体候选。

### 第 17 问：新建医院医生智能体会话应如何识别会话类型？

为什么要问：本次不处理历史会话，因此只需要保证从院内名医入口新建的会话，在当前生命周期内明确使用医院医生智能体模式，避免新会话误读通用 Pro 模型目录。

请选择：

- A. 以新建流程明确传入的医院会话 scope 为判断依据：`hospital_id + member_id + agent_id + thread_id`（推荐）  
  从医院名医入口创建 Thread 时保存 scope；当前页面只处理该新建流程返回的医院会话，不增加历史会话识别逻辑。

- B. 依据 Thread 的模型名称或 `bootstrap_name` 判断  
  可以少改数据结构，但名称可能变化，且无法可靠表达医院、成员和医生智能体关系。

- C. 只依据用户从哪个页面点击进入  
  首次进入可用，但页面状态无法独立证明会话已经绑定医院、成员和医生智能体。

- D. 由客户端读取消息内容或系统消息推断是否为医院会话  
  不稳定，且会把展示文案当作安全边界，无法阻止模型切换。

请选择 A、B、C 或 D。

#### 第 17 问确认

**已确认选择 A：以新建流程明确传入的医院会话 scope 为判断依据：`hospital_id + member_id + agent_id + thread_id`。**

同时确认：本次不处理历史会话问题；第 17 问只适用于本次新建的医院医生智能体会话。

落地约束：

- 新建医院会话以医院入口返回的 `hospital_id`、当前 `member_id`、选定 `agent_id` 和新建成功后的 `thread_id` 组成会话 scope。
- iOS 仅对本次新建流程进入医院智能体模式；不增加历史 Thread 的识别、迁移、改造、只读提示或兼容逻辑。
- 前文第 9、10 问中关于历史会话处置的选项与确认，均由本范围决定覆盖，不纳入本工单验收范围；后续如需处理历史会话，另立工单。
- 新建流程返回的 scope 与专用运行配置中的 `agent_id`、`member_id` 必须一致；不一致即视为失败，不打开可发送页面。

### 第 18 问：新建医院医生智能体会话时，专用配置与 Thread 创建的调用顺序如何确定？

为什么要问：专用运行配置需要 `agent_id + member_id`，而创建会话需要把同一组身份写入 Thread。顺序不明确时，可能先创建没有有效配置的空 Thread，或出现配置对应的智能体与 Thread 绑定不一致。

请选择：

- A. 先查询专用运行配置，成功后再创建医院 Thread；创建成功后使用同一配置打开会话（推荐）  
  不产生无效空会话；服务端创建接口再次校验 `agent_id`、`member_id` 和医院关系，客户端校验返回 scope 后才进入可发送状态。

- B. 先创建 Thread，再异步查询专用运行配置  
  页面响应快，但配置失败时会留下未能使用的空 Thread，需要额外清理和状态处理。

- C. 先从 Pro Bootstrap 选模型创建 Thread，之后再替换成医生智能体  
  会让医院会话先使用通用模型，破坏医生智能体绑定边界。

- D. 由客户端本地生成 Thread 标识，配置成功后再补交服务端  
  无法保证服务端 Thread、患者成员和医院关系一致，也不符合现有会话创建流程。

请选择 A、B、C 或 D。

#### 第 18 问确认

**已确认选择 A：先查询专用运行配置，成功后再创建医院 Thread；创建成功后使用同一配置打开会话。**

落地约束：

- iOS 从医院名医入口取得 `agent_id`，结合当前 `member_id` 请求专用运行配置；只有响应成功且字段校验通过，才调用现有医院会话创建接口。
- 创建接口继续接收医院、成员和医生智能体业务关联所需字段；服务端再次校验 `agent_id`、`member_id`、医院关系、发布状态和场景绑定有效性，不能信任客户端先前查询结果。
- 创建成功后，iOS 校验返回的 `hospital_id`、`member_id`、`agent_id`、`thread_id` 与本地预期完全一致，再将页面切换为医院医生智能体模式。
- 任一阶段失败都不创建或不打开可发送 Thread；不使用通用 Pro 模型作为兜底，不自动换用其他医生智能体。
- 专用配置请求与 Thread 创建应具备请求关联 ID 供排查，但不得在日志中记录模型凭证、系统提示词或完整患者资料。

### 第 19 问：创建医院医生智能体 Thread 时，服务端是否需要再次固定运行绑定？

为什么要问：第 18 问确定客户端先取配置再创建 Thread，但两次请求之间可能发生后台停用、换绑或配置更新。若创建接口只保存客户端传入的模型名称，Thread 可能最终绑定到与专用配置不同的模型。

请选择：

- A. 服务端按 `agent_id` 重新解析并固定当前有效的 `AIScenarioModelBinding`，客户端不能提交模型绑定覆盖它（推荐）  
  创建时再次读取 Profile 与场景绑定关系，将 `agent_id`、绑定 ID 和配置版本写入 Thread scope；若已失效则拒绝创建。

- B. 客户端提交 `binding_id`、模型名称和配置版本，服务端直接保存  
  调用简单，但客户端可以提交与 `agent_id` 不匹配或已失效的绑定。

- C. 创建接口不保存绑定，只保存医生姓名和智能体名称  
  展示可用，但无法保证后续发送继续使用同一医生智能体运行配置。

- D. 创建时始终使用 Pro Bootstrap 的默认模型，页面再显示医生智能体资料  
  会造成展示身份与实际模型不一致，不符合医院医生智能体边界。

请选择 A、B、C 或 D。

#### 第 19 问确认

**已确认选择 A：服务端按 `agent_id` 重新解析并固定当前有效的 `AIScenarioModelBinding`，客户端不能提交模型绑定覆盖它。**

落地约束：

- 创建 Thread 时服务端重新读取 `ClinicalAgentProfile`、医生/科室关系和 `scenario_binding`，校验绑定仍有效后，将 `hospital_id`、`member_id`、`agent_id`、绑定 ID 和配置版本写入医院会话 scope。
- 客户端不得提交 `binding_id`、模型名称、endpoint、凭证或提示词来决定 Thread 的运行绑定；客户端先前查询的运行配置只用于当前直连模型和页面展示。
- 若 Profile 已停用、场景绑定已替换、模型配置不完整或医院/成员关系失效，创建接口直接拒绝，不创建空 Thread，不回退普通模型。
- 创建成功响应中的 `agent_id`、绑定 ID 和配置版本必须与客户端专用配置对应；不一致时客户端不得打开可发送页面，并按配置失效处理。
- Thread 后续发送仍固定当前医院 scope；新配置不会在当前前台会话中无感替换，下一次进入时重新查询。

### 第 20 问：医院会话与普通 Pro 会话的模型目录状态是否需要完全分离？

为什么要问：现有 iOS 会话页和模型选择器使用通用 `chatScenarioModels` 状态。若医院会话仅临时覆盖该状态，离开医院会话或切换页面时可能把医生智能体带入普通对话，或把普通模型带回医院会话。

请选择：

- A. 分别维护普通 Pro 模型目录和医院医生智能体单项目录，状态、缓存和选择结果完全隔离（推荐）  
  普通会话继续使用 Bootstrap 的通用目录；医院会话只使用当前专用配置生成的单项置灰目录，两者不互相覆盖、不共享最后选择项。

- B. 复用同一个模型目录，进入医院会话时临时过滤  
  改动较少，但状态恢复、异步请求竞态和缓存命中时容易产生跨场景污染。

- C. 全局只保留最近一次使用的模型目录  
  实现简单，但无法同时满足普通 Pro 与医院医生智能体的不同数据边界。

- D. 所有会话都只使用医院医生智能体目录  
  会破坏普通 AI 对话的既有功能范围。

请选择 A、B、C 或 D。

#### 第 20 问确认

**已确认选择 A：分别维护普通 Pro 模型目录和医院医生智能体单项目录，状态、缓存和选择结果完全隔离。**

落地约束：

- 普通会话继续读取 Pro Bootstrap 的通用目录；医院会话只使用当前专用运行配置生成的单项、置灰模型目录。
- 两种目录不得共用 `chatScenarioModels` 的最终状态、最后选中模型、Keychain 配置、请求竞态标识或错误状态；从普通会话离开时不能把普通模型带入医院会话，反之亦然。
- 医院模型目录的唯一元素必须携带当前 `agent_id`、配置版本和“固定不可切换”状态；普通目录不得出现医院医生智能体绑定。
- 医院专用配置失败只影响医院入口和医院会话，不清空、不替换普通 Pro 目录；普通 Bootstrap 失败也不能让医院会话回退到普通模型。
- 验收需覆盖普通会话与医院会话快速连续切换、后台异步请求乱序、App 冷启动和成员切换，确保两类状态不交叉污染。

### 第 21 问：iOS 进入院内名医入口时，`hospital_id` 应从哪里取得？

为什么要问：专用名医列表、智能体配置和成员授权都依赖医院上下文。若客户端从 Pro Bootstrap、列表第一项或本地硬编码推导医院，排序变化和多医院账号会造成患者进入错误医院或拿到错误智能体目录。

请选择：

- A. 使用现有医院上下文/医院列表选择结果；缺少有效上下文时先加载医院列表并要求确定当前医院（推荐）  
  `hospital_id` 由服务端医院实体和当前客户端选择共同确定；进入名医列表、专用配置和创建 Thread 全程沿用同一值。

- B. 从医院列表接口取第一家医院作为当前医院  
  可以少一步交互，但医院排序变化时可能进入错误医院。

- C. 从 Pro Bootstrap 的模型或智能体字段反推医院  
  通用 Bootstrap 不承担医院目录语义，无法可靠建立医院归属。

- D. 在 iOS 客户端内固定演示医院 ID  
  演示环境简单，但无法复用真实医院切换和服务端授权逻辑。

请选择 A、B、C 或 D。

#### 第 21 问确认

**已确认选择 A：使用现有医院上下文/医院列表选择结果；缺少有效上下文时先加载医院列表并要求确定当前医院。**

落地约束：

- `hospital_id` 由服务端医院实体和当前客户端选择共同确定；进入院内名医列表、专用运行配置和创建医院 Thread 全程沿用同一值。
- 客户端不得从 Pro Bootstrap 的模型条目、智能体名称、列表第一项或本地硬编码推导医院；医院上下文缺失或已失效时，先完成医院列表加载/选择，再请求医院专用接口。
- 医院切换立即废弃当前医院名医列表缓存、专用配置内存状态和未完成请求；切换后的名医、配置和 Thread 创建必须使用新 `hospital_id`。
- 医院列表缓存可以用于首屏，但服务端专用接口仍须校验医院有效性与当前用户可访问范围；客户端不得仅凭缓存决定授权。

### 第 22 问：`member_id` 在院内名医列表、专用配置和新建 Thread 链路中应如何取得？

为什么要问：当前 iOS 支持登录账号下的成员切换。医生智能体运行配置、知识库同步和医院会话都必须绑定当前患者成员；如果客户端使用上一次成员或默认成员，可能把医院咨询上下文串到错误患者。

请选择：

- A. 复用当前已选成员上下文；缺少有效成员时先走现有成员选择流程（推荐）  
  名医列表可以按医院加载，但点击医生进入配置查询和创建 Thread 时必须携带当前成员；成员切换后重新查询，不复用旧配置。

- B. 自动使用登录账号的第一个成员  
  减少一步操作，但多成员账号可能在错误患者身份下发起咨询。

- C. 从医院智能体接口返回的患者资料中选择成员  
  会把成员选择权交给医院目录接口，破坏现有账号成员管理边界。

- D. 不携带 `member_id`，只按登录账号绑定医院医生智能体  
  无法满足当前成员授权、知识库同步和会话隔离要求。

请选择 A、B、C 或 D。

#### 第 22 问确认

**已确认选择 A：复用当前已选成员上下文；缺少有效成员时先走现有成员选择流程。**

落地约束：

- 院内名医列表可以按 `hospital_id` 加载；点击医生进入专用运行配置查询和创建 Thread 时，必须携带当前有效 `member_id`。
- `member_id` 只来自现有登录成员/患者切换上下文，不由医院目录、医生智能体响应或本地上一次会话推导；缺少有效成员时先走现有成员选择流程。
- 成员切换后立即废弃旧成员对应的专用配置、当前医院医生智能体选择和未完成请求；下一次点击医生时以新成员重新查询。
- 成员切换不改变 Pro 普通会话目录；普通会话与医院会话继续按第 20 问分别维护状态。
- 专用接口和 Thread 创建接口都必须由服务端重新校验登录账号对该 `member_id` 的管理权；客户端仅传递当前上下文，不承担授权判断。

### 第 23 问：成员切换时，已打开的院内名医页面应如何处理？

为什么要问：名医目录本身按医院加载，但专用配置和会话创建绑定患者成员。若成员切换后仍保留原医生选中态或继续使用旧配置，患者可能在错误成员身份下进入咨询。

请选择：

- A. 立即清空当前医生选择和专用配置，保留医院名医列表；下一次点击医生时按新成员重新查询（推荐）  
  列表可继续复用医院级缓存，但不保留旧成员的可发送状态、Keychain 配置引用或待创建 Thread。

- B. 保留当前医生和专用配置，等发送消息时再校验新成员  
  页面反馈快，但会在成员切换后短暂展示错误患者上下文。

- C. 成员切换时同时清空医院名医列表并重新请求  
  边界清楚，但医院目录与成员授权不完全同源，会增加不必要的请求和首屏等待。

- D. 允许当前会话继续使用原成员配置，下一次新建才切换成员  
  可能造成患者以错误成员身份继续咨询，不符合成员隔离要求。

请选择 A、B、C 或 D。

#### 第 23 问确认

**已确认选择 A：立即清空当前医生选择和专用配置，保留医院名医列表；下一次点击医生时按新成员重新查询。**

落地约束：

- 成员切换后保留医院级名医列表缓存，但清空当前医生、当前 `agent_id`、专用运行配置、当前医院会话创建状态和待发送消息状态。
- 不保留旧成员的可发送状态、Keychain 配置引用、专用模型目录选择结果或待创建 Thread；旧成员配置不因医院相同而复用。
- 下一次点击医生时使用新的 `member_id` 请求专用运行配置；成功后才允许创建医院 Thread。
- 成员切换不触发历史会话处理，不增加历史 Thread 识别或迁移逻辑。

## 12. 最终确认结论汇总

| 编号 | 已确认结论 | 对落地的约束 |
| --- | --- | --- |
| C-001 | 专用运行配置按 `agent_id` 查询 | 不按医生猜测，不按名称过滤，不从 Bootstrap 选取 |
| C-002 | 专用接口返回模型连接参数，iOS 直连模型 | 复用现有流式聊天链路；凭证必须严格控制暴露、日志和缓存范围 |
| C-003 | 配置无缓存且查询失败时不进入会话 | 不创建空 Thread，不打开可发送页面，不回退普通 AI |
| C-004 | 医院会话模型选择器保留外观但只有一个置灰项 | 只显示当前医生智能体，禁止展开、切换和重新绑定 |
| C-005 | 前台会话固定进入时配置 | 当前会话不无感换模；退出后再次进入重新处理 |
| C-006 | Pro Bootstrap 排除被 Profile 引用的 Binding | 排除依据为 `ClinicalAgentProfile.scenario_binding`，不按名称和客户端过滤 |
| C-007 | 专用接口携带 `member_id` | 服务端校验账号对成员的管理权和智能体可见性 |
| C-008 | 停用智能体刷新后从名医列表移除 | 旧缓存点击只提示不可用并刷新，不创建会话 |
| C-009 | 本工单不处理历史会话 | 不做历史识别、迁移、只读改造、删除或兼容；前文历史选项由此结论覆盖 |
| C-010 | 运行参数来自 `AIScenarioModelBinding` | Profile 只提供医生业务资料和患者端展示信息，iOS 不拼提示词 |
| C-011 | 专用配置写入 Keychain | 按账号、成员、医院、智能体和版本隔离；停用/退出/切换时强制清理 |
| C-012 | 有 Keychain 时先使用，后台静默校验 | 无 Keychain 时必须先成功查询；后台校验失败停止后续发送 |
| C-013 | 后台校验失败允许当前请求完成 | 新发送、重试和自动重试立即禁用，页面显示服务不可用 |
| C-014 | 专用接口返回稳定业务错误码 | 客户端按错误码处理，不依赖错误文案 |
| C-015 | 名医列表只使用医院专用目录接口 | 不从 Pro Bootstrap 组装医院名医列表 |
| C-016 | 新建医院会话使用明确 scope | `hospital_id + member_id + agent_id + thread_id` 作为当前新建会话识别依据 |
| C-017 | 先查配置，再创建 Thread | 配置失败不产生空会话 |
| C-018 | 创建 Thread 时服务端重新固定 Binding | 客户端不得提交 Binding 覆盖服务端解析结果 |
| C-019 | 普通与医院模型目录完全隔离 | 目录、缓存、选择结果、错误状态和并发请求不互相覆盖 |
| C-020 | `hospital_id` 来自现有医院上下文 | 缺失时先选择医院，不从 Bootstrap、第一家医院或硬编码推导 |
| C-021 | `member_id` 来自当前已选成员 | 缺失时走现有成员选择流程 |
| C-022 | 成员切换清空医生与专用配置 | 保留医院名医列表，但下一次点击医生时重新按新成员查询 |

## 13. 最终业务流程

### 13.1 进入院内名医列表

```text
普通 AI 入口
    │
    ├─ 继续走 Pro Bootstrap → 普通模型目录
    │
    └─ 院内名医入口
          │
          ├─ 取得现有 hospital context
          │    └─ 无有效 hospital_id → 走现有医院列表/选择流程
          │
          ├─ 取得当前 member context
          │    └─ 无有效 member_id → 走现有成员选择流程
          │
          ├─ 先显示医院级名医列表缓存
          │
          └─ 后台刷新 GET /hospital-care/hospitals/{hospital_id}/agents/
                  ├─ 成功：替换医院名医列表缓存，移除已停用智能体
                  └─ 失败：保留缓存；无缓存时显示重试
```

名医列表阶段只需要 `hospital_id`；`member_id` 在点击具体医生、请求专用配置和创建 Thread 时强制带入。

### 13.2 点击医生智能体

```text
点击医生卡片
    │
    ├─ 读取当前 hospital_id
    ├─ 读取当前 member_id
    ├─ 读取卡片 agent_id
    │
    ├─ Keychain 命中当前 scope 的配置？
    │      ├─ 是：先打开当前医生智能体页面；后台静默校验
    │      └─ 否：展示加载态并请求专用运行配置
    │
    ├─ 专用运行配置成功？
    │      ├─ 否：不创建/打开可发送会话，展示业务错误和重试
    │      └─ 是：校验 agent_id、member_id、hospital_id、version
    │
    ├─ 调用医院 Thread 创建接口
    │      ├─ 服务端重新校验 Profile、成员、医院和 Binding
    │      ├─ 失败：不创建空 Thread，展示错误
    │      └─ 成功：返回 thread scope
    │
    └─ 校验 scope 一致后进入医院医生智能体会话
```

### 13.3 医院医生智能体会话页

- 页面使用现有对话框架和流式响应能力。
- 模型选择器保留现有控件外观，但只放入一个当前医生智能体项目并置灰。
- 不显示“默认模型”、通用 Pro 模型、其他医生智能体或可展开切换菜单。
- 页面使用当前前台会话固定的专用运行配置。
- 同时启动后台专用配置校验；校验成功更新 Keychain，当前前台会话不无感换模。
- 校验失败时停止后续发送，当前已发请求允许完成；页面显示“当前服务已不可用”。

### 13.4 成员切换

```text
成员 A → 成员 B
    │
    ├─ 取消成员 A 的专用配置请求和列表相关请求
    ├─ 清空当前医生、agent_id、专用配置和医院模型单项目录
    ├─ 清空待发送文本、发送状态和待创建 Thread 状态
    ├─ 删除/失效成员 A 对应 Keychain 配置引用
    ├─ 保留医院级名医列表缓存
    └─ 下次点击医生时，使用 member B 重新请求专用配置并创建 Thread
```

## 14. 服务端落地方案

### 14.1 Pro Bootstrap 排除规则

目标文件：`ai_config/views.py` 的 `AIBootstrapConfigView` 与 `_build_pro_scenarios`。

建议处理顺序：

1. 查询所有被 `ClinicalAgentProfile.scenario_binding_id` 引用的 Binding ID，形成一次性排除集合。
2. 构建普通 Pro 场景模型列表时排除集合中的 Binding。
3. 保留未被医院医生 Profile 引用的普通模型和通用智能体。
4. 保持普通 Bootstrap 原有响应结构，避免普通会话重复适配。
5. 增加回归测试：医生 Binding 不出现、普通 Binding 仍出现、无 Profile 引用的通用 agent 不被误排除。

伪代码示例：

```python
def build_pro_models(scenario_key):
    hospital_agent_binding_ids = set(
        ClinicalAgentProfile.objects
        .filter(scenario_binding_id__isnull=False)
        .values_list("scenario_binding_id", flat=True)
    )

    bindings = (
        AIScenarioModelBinding.objects
        .filter(scenario=scenario_key, is_active=True)
        .exclude(id__in=hospital_agent_binding_ids)
        .select_related("model")
    )

    return [serialize_pro_model(binding) for binding in bindings]
```

说明：以上为方案级核心代码示例，不是本工单内的实际代码修改；最终实现需按现有 QuerySet、序列化器和错误处理约定调整。

### 14.2 专用运行配置接口

建议接口：

```http
GET /api/v1/hospital-care/agents/{agent_id}/runtime-config/?member_id={member_id}
Authorization: Bearer <patient-token>
```

服务端处理顺序：

1. 校验登录态。
2. 校验 `member_id` 属于当前登录账号，且当前账号具备成员管理/访问权。
3. 按 `agent_id` 查询 `ClinicalAgentProfile`，不得按医生或名称猜测。
4. 校验 Profile 已发布、可供患者端使用，并且属于当前医院上下文。
5. 从 Profile 的 `scenario_binding` 解析唯一 `AIScenarioModelBinding`。
6. 校验 Binding 活跃、模型配置完整、模型 endpoint 和凭证可用。
7. 返回一个医生智能体运行配置，不返回其他模型候选。

建议成功响应示例：

```json
{
  "agent_id": "agent-profile-uuid",
  "hospital_id": "hospital-uuid",
  "member_id": "member-uuid",
  "doctor": {
    "doctor_id": "doctor-uuid",
    "name": "张医生",
    "title": "主任医师",
    "department_name": "心内科",
    "avatar_url": "https://..."
  },
  "profile": {
    "name": "张医生智能体",
    "description": "健康信息与就医指导",
    "status": "published",
    "profile_version": 4
  },
  "runtime": {
    "binding_id": "binding-uuid",
    "binding_version": 8,
    "model_id": "model-id",
    "endpoint": "https://model.example.com/v1",
    "credential": "short-or-scoped-runtime-credential",
    "system_prompt": "由 AIScenarioModelBinding 提供",
    "streaming": true
  }
}
```

凭证字段名称需沿用现有客户端模型配置协议；示例中的值只能是测试占位值，不能写入真实密钥。

### 14.3 创建医院 Thread

建议继续复用现有医院会话创建接口，不创建第二套 Thread 表：

```http
POST /api/v1/hospital-care/conversations/
Authorization: Bearer <patient-token>
Content-Type: application/json
```

客户端业务请求只提交业务身份：

```json
{
  "hospital_id": "hospital-uuid",
  "member_id": "member-uuid",
  "agent_id": "agent-profile-uuid"
}
```

客户端不得提交以下字段影响运行绑定：

- `binding_id`
- `model_id`
- `endpoint`
- `credential`
- `system_prompt`

服务端创建时重新解析 Profile 和 Binding，并返回：

```json
{
  "thread_id": "thread-uuid",
  "hospital_id": "hospital-uuid",
  "member_id": "member-uuid",
  "agent_id": "agent-profile-uuid",
  "binding_id": "binding-uuid",
  "binding_version": 8,
  "status": "active"
}
```

### 14.4 业务错误码建议

| 业务码 | HTTP | 含义 | iOS 行为 |
| --- | ---: | --- | --- |
| `AUTH_REQUIRED` | 401 | 未登录或令牌失效 | 走现有登录恢复 |
| `MEMBER_ACCESS_DENIED` | 403 | 当前账号无权访问成员 | 清理当前成员专用状态，回成员选择 |
| `HOSPITAL_ACCESS_DENIED` | 403 | 当前账号无权访问医院 | 清理医院专用状态，回医院选择 |
| `AGENT_NOT_FOUND` | 404 | 智能体不存在 | 刷新名医列表 |
| `AGENT_UNAVAILABLE` | 409 | 智能体已下架/停用 | 移除卡片或显示服务不可用 |
| `AGENT_BINDING_INVALID` | 409 | 场景绑定无效 | 清理 Keychain，禁止进入/发送 |
| `RUNTIME_CONFIG_INVALID` | 409 | 运行配置缺失或不完整 | 清理配置，显示重试 |
| `REQUEST_TIMEOUT` | 408/网关约定 | 请求超时 | 保留可重试状态 |
| `SERVICE_UNAVAILABLE` | 503 | 服务暂不可用 | 缓存可用则继续显示，否则重试 |

错误响应不返回其他医生智能体、不返回普通模型候选、不返回 endpoint、凭证或系统提示词。

## 15. iOS 落地方案

### 15.1 关键文件位置

以下路径基于当前 SparkClient 工程实际结构，实施前以分支最新文件为准：

- `SparkClient/.../HospitalCareRemoteAPI.swift`  
  新增医院专用运行配置请求方法；复用医院列表、智能体列表和会话创建请求风格。
- `SparkClient/.../HospitalCareDTO.swift`  
  增加 RuntimeConfig DTO、业务错误 DTO 和医院会话 scope DTO；不污染普通 Pro 模型 DTO。
- `SparkClient/.../ResolveOrCreateHospitalConversationUseCase.swift`  
  调整为“专用配置成功 → 创建 Thread → 校验 scope → 返回会话上下文”的流程。
- `SparkClient/.../ChatDetailViewModel.swift`  
  增加医院会话模式、单项医院模型目录、Keychain 读取/校验状态和后台刷新状态；普通 `chatScenarioModels` 不被覆盖。
- `SparkClient/.../ChatView.swift`  
  根据医院会话 scope 传入医院专用模型目录，复用现有聊天页面。
- `SparkClient/.../ChatComposerModelPickerRow.swift`  
  支持“单项置灰、不可展开、无切换动作”的展示状态。
- 医院名医入口对应的 ViewModel/UseCase 目录  
  继续使用医院专用 agents API；点击卡片前取得当前医院和当前成员上下文。
- 现有成员切换协调器/登录退出清理流程  
  增加医院医生智能体专用状态清理，不改变普通会话和普通模型目录。

### 15.2 iOS 状态模型示例

```swift
enum ConversationSurface {
    case generalPro
    case hospitalDoctorAgent(HospitalConversationScope)
}

struct HospitalConversationScope: Equatable {
    let hospitalID: String
    let memberID: String
    let agentID: String
    let threadID: String
}

struct HospitalRuntimeConfig {
    let scope: RuntimeScope
    let bindingID: String
    let bindingVersion: Int
    let modelID: String
    let endpoint: URL
    let credential: String
    let systemPrompt: String
}

struct RuntimeScope: Equatable {
    let accountID: String
    let hospitalID: String
    let memberID: String
    let agentID: String
}
```

### 15.3 新建会话伪代码

```swift
func startHospitalAgentConversation(agentID: String) async throws -> HospitalConversationScope {
    let hospitalID = try hospitalContext.requireCurrentHospitalID()
    let memberID = try memberContext.requireCurrentMemberID()

    let runtime = try await remoteAPI.fetchRuntimeConfig(
        agentID: agentID,
        memberID: memberID
    )
    try runtimeValidator.validate(
        runtime,
        hospitalID: hospitalID,
        memberID: memberID,
        agentID: agentID
    )

    let created = try await remoteAPI.createHospitalConversation(
        hospitalID: hospitalID,
        memberID: memberID,
        agentID: agentID
    )
    try scopeValidator.validate(
        created,
        hospitalID: hospitalID,
        memberID: memberID,
        agentID: agentID
    )

    runtimeStore.saveForCurrentConversation(runtime)
    return created.scope
}
```

### 15.4 Keychain 缓存策略示例

Keychain key 建议：

```text
hospital-agent-runtime/
{account_id}/
{hospital_id}/
{member_id}/
{agent_id}/
{binding_version}
```

写入规则：

- 只保存当前医生智能体直连所需的运行配置。
- 不保存 Pro Bootstrap 全量响应。
- 不保存其他医生智能体候选。
- 不保存聊天正文、患者资料或知识库正文。
- Keychain 命中后可先使用，并立即启动同一 scope 的后台静默校验。
- 校验成功写入服务端返回的新版本；当前前台会话仍使用进入时固定版本。
- 服务端返回停用、无权、配置失效时删除对应 Keychain 条目。
- 退出登录、切换账号、切换成员、切换医院时清除对应 scope。

### 15.5 成员切换伪代码

```swift
func didChangeMember(to newMemberID: String) {
    hospitalAgentTask?.cancel()
    hospitalAgentTask = nil

    currentHospitalAgent = nil
    hospitalRuntimeConfig = nil
    hospitalComposerModels = []
    pendingHospitalThreadCreation = nil
    pendingMessage = nil

    keychainStore.invalidateHospitalAgentReferences(
        accountID: accountID,
        hospitalID: currentHospitalID,
        memberID: oldMemberID
    )

    // 保留医院级名医列表，不重新把旧成员的医生状态带入页面
    refreshHospitalAgentsIfNeeded()
}
```

### 15.6 模型选择器示例

```swift
let models: [ChatModel] = surface.isHospitalDoctorAgent
    ? [ChatModel(
        id: runtime.agentID,
        displayName: runtime.agentDisplayName,
        isEnabled: false,
        isSelectable: false,
        source: .hospitalDoctorAgent
      )]
    : generalProModels
```

医院项目的 `isSelectable` 必须为 `false`；点击时不发起任何切换、Bootstrap 或重新绑定请求。

## 16. 缓存与并发控制

### 16.1 缓存分层

| 缓存 | 作用域 | 内容 | 成员切换 | 医院切换 |
| --- | --- | --- | --- | --- |
| 普通 Pro Bootstrap | 账号/客户端 | 普通模型目录 | 不受医院成员切换影响 | 不混入医院数据 |
| 医院名医列表 | `hospital_id` | 医生公开资料、主智能体卡片 | 保留 | 清除旧医院引用 |
| 医院 Runtime Config | `account + hospital + member + agent + version` | 直连配置 | 失效/清理 | 清除 |
| 医院当前会话状态 | 前台会话 scope | 当前 Thread 和固定配置引用 | 清空 | 清空 |

### 16.2 请求 single-flight

同一 `account_id + hospital_id + member_id + agent_id` 的专用配置请求应复用进行中的任务；但成员、医院或智能体变化时必须取消旧任务，不能让旧响应回写新页面。

伪代码：

```swift
let requestKey = "\(accountID):\(hospitalID):\(memberID):\(agentID)"

if let running = runtimeTasks[requestKey] {
    return try await running.value
}

let task = Task { try await remoteAPI.fetchRuntimeConfig(...) }
runtimeTasks[requestKey] = task
defer { runtimeTasks.removeValue(forKey: requestKey) }
return try await task.value
```

响应回写前必须再次确认当前页面上下文仍等于请求创建时的 scope。

## 17. 安全与敏感数据要求

由于本次确认采用 iOS 直连模型，模型 endpoint 和凭证会进入患者设备，必须单独作为高风险配置处理：

- 服务端只向已经通过患者、医院、成员和医生智能体校验的请求返回。
- 不在普通 Bootstrap 返回医院医生智能体运行参数。
- 不在日志、埋点、崩溃上报、调试导出和网络诊断中记录 endpoint、凭证和完整系统提示词。
- 不把专用配置写入普通模型缓存、Core Data、UserDefaults 或聊天历史。
- Keychain 访问使用最小可用权限，设备锁定/退出登录/成员切换时按策略清理。
- 真实密钥不能出现在源码、工单、截图、测试数据或接口示例中；附件日志中出现的真实密钥应由凭证管理员完成轮换。
- 服务端错误响应不返回其他模型候选，避免错误分支重新暴露 Pro 目录。
- 客户端不能因为 UI 显示“医生智能体”就信任配置；每次发送前仍受当前前台配置状态和服务端/模型服务响应约束。

## 18. 验收标准

### 18.1 普通 Pro 对话

- Pro Bootstrap 中不出现任何被 `ClinicalAgentProfile.scenario_binding` 引用的 Binding。
- 普通未被医院 Profile 引用的模型/通用智能体仍正常返回。
- 普通对话模型选择器和缓存行为不受医院功能影响。
- 普通会话不会因为医院接口失败而切换模型目录。

### 18.2 医院名医列表

- 列表只调用医院专用 agents 接口。
- 列表卡片包含服务端返回的医生公开资料和 `agent_id`。
- 已停用智能体在刷新成功后被移除。
- 旧缓存点击停用卡片时不创建 Thread，只提示不可用并支持刷新。
- 无医院上下文时不能从 Pro Bootstrap 或第一家医院推导。

### 18.3 新建医院会话

- 点击医生时使用当前 `hospital_id`、当前 `member_id` 和卡片 `agent_id`。
- 专用配置查询成功后才创建 Thread。
- 专用配置失败不创建空 Thread、不打开可发送页面、不回退普通 AI。
- 创建接口服务端重新解析并固定 `AIScenarioModelBinding`。
- 返回 scope 与客户端预期不一致时不进入可发送页面。
- 医院模型选择器只展示一个置灰、不可点击项目。

### 18.4 缓存和切换

- Keychain 命中时可以快速打开并后台静默校验。
- Keychain 未命中时必须先成功请求专用配置。
- 后台校验失败后立即禁用后续发送，当前请求允许完成。
- 成员切换清空医生选择、运行配置、医院单项模型目录和待创建 Thread 状态，但保留医院名医列表。
- 医院切换不复用旧医院的名医列表选择、运行配置或会话状态。
- 普通模型目录和医院单项模型目录不发生交叉覆盖。

### 18.5 历史会话范围

- 本工单不新增历史会话处理逻辑。
- 不以历史 Thread 识别医院医生智能体，不做历史迁移、删除、只读改造或兼容。
- 历史行为不作为本次验收依据；后续需求必须单独创建工单。

## 19. 实施顺序

### 阶段一：服务端隔离

1. 为 Pro Bootstrap 增加基于 `ClinicalAgentProfile.scenario_binding` 的排除集合。
2. 为医院医生智能体增加按 `agent_id + member_id` 查询专用运行配置的接口。
3. 固定专用接口错误码和响应 DTO。
4. 强化医院 Thread 创建时的服务端 Binding 重解析和 scope 返回。
5. 增加服务端单元测试、接口测试和敏感字段日志检查。

### 阶段二：iOS 数据边界

1. 增加专用 Runtime Config DTO 与医院会话 scope DTO。
2. 分离普通 Pro 模型目录状态和医院单项目录状态。
3. 改造医院入口点击流程，先配置查询再创建 Thread。
4. 接入 Keychain 缓存和后台静默校验。
5. 实现成员切换、医院切换和退出登录清理。

### 阶段三：iOS 对话 UI

1. 复用现有 Chat 页面和流式发送逻辑。
2. 将模型选择器改为单项置灰模式。
3. 增加运行配置失败、智能体下架和校验失效状态。
4. 验证医生资料展示与运行参数分离。

### 阶段四：联调与验收

1. 普通 Pro、医院名医列表和医院会话三条链路分别抓包验证。
2. 验证响应中不存在跨医院、跨医生和通用模型泄漏。
3. 验证配置更新、停用、成员切换、医院切换和弱网场景。
4. 验证日志、崩溃上报、Keychain 和请求错误中不出现敏感字段。
5. 通过全部验收用例后再合并客户端与服务端分支。

## 20. 本工单交付边界

本工单完成的是客户端医院医生智能体与普通 Pro 模型目录隔离的需求确认和落地设计，不代表已经修改服务端或 iOS 代码。实际开发必须以本工单确认结论、现有服务端接口契约和当前 SparkClient 工程状态为准。
