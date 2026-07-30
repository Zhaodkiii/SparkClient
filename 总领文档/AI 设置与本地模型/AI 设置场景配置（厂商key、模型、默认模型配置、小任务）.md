# AI 设置场景配置（厂商 Key、模型、默认模型配置、小任务）需求

## 一、模块目标

本模块负责维护账号级 AI 配置目录，并将用户在设置页维护的厂商 Key、模型、场景绑定、默认模型参数和小任务配置转换为 AI 运行时可以直接解析的场景 bundle。它覆盖配置的首次种子初始化、读取、编辑、保存、校验、运行时缓存和 Pro 远端覆盖。

当前 iOS 实现采用 SwiftUI + MVVM 风格的设置页、`AISettingsSnapshot` 聚合模型、Core Data 账号级目录、UserDefaults 轻量偏好，以及 `AIConfigCenter`/`AIRuntimeConfigStore` 内存运行时配置。本文只描述已在 `SparkClient` 中确认的实现；未发现的能力标记为当前缺口或建议演进。

## 二、AI 设置场景配置模块结构

```text
SparkClient/
├── SparkClient/Projects/Features/AISettings/
│   ├── Domain/
│   │   ├── AISettingsSnapshot.swift
│   │   ├── AISettingsDomainModels.swift
│   │   ├── AISettingsRepository.swift
│   │   └── AISettingsSeedCatalog.swift
│   ├── Infrastructure/
│   │   └── DefaultAISettingsRepository.swift
│   └── Presentation/
│       ├── Root/AISettingsViewModel.swift
│       ├── Providers/APIKeysSettingsView.swift
│       ├── Models/ModelScenarioBindingsEditorView.swift
│       └── SmallTasksSettingsView.swift
├── SparkClient/Projects/Core/AI/
│   ├── AIConfigCenter.swift
│   ├── AIConfigModels.swift
│   ├── AILocalScenarioBundleBuilder.swift
│   ├── AIRuntimeConfigAssembler.swift
│   ├── AIRuntimeConfigStore.swift
│   └── ScenarioPolicyResolver.swift
├── SparkClient/Projects/Core/Networking/API/AI/AIConfigAPI.swift
├── SparkClient/Projects/App/Resources/AISettings/
│   ├── AllModels.json
│   ├── APIKeys.json
│   └── ScenarioModelBindings.json
└── SparkClient/Tests/AI/AISettingsAndResolverTests.swift
```

| 子能力 | 主要职责 | 结果 |
| --- | --- | --- |
| 厂商 Key 配置 | 保存 provider 标识、请求地址、密钥、启用状态和隐私同意 | `APIKeys`，落入 `AIProviderEntity` |
| Pro 模型申请卡片 | 展示试用资格/审核状态，确认隐私条款后提交 Pro 模型试用申请 | `AITrialState`，状态写入账号偏好并由通知触发刷新 |
| 模型目录配置 | 保存模型名称、身份、能力、厂商、默认参数和本地模型信息 | `AllModels`，落入 `AIModelEntity` |
| 场景模型绑定 | 将模型绑定到 `AIScenario`，记录排序、启用、默认、温度和 token 上限 | `AIScenarioModelBinding` |
| 默认模型解析 | 从场景绑定、运行时覆盖、Pro overlay 中解析最终模型 | `AIScenarioRemoteBundle` + `AIScenarioConfig` |
| 小任务配置 | 保存本地小任务，并与 Pro 小任务合并 | `SmallTask`，本地配置按 code 覆盖 Pro |
| 设置页同步 | 管理草稿、保存、错误和运行时重建 | `AISettingsViewModel` |

## 三、真实能力与业务规则

### 3.1 厂商 Key 配置

#### 需求说明

用户可以维护 AI 厂商的请求地址和 API Key，并通过稳定的 `providerID` 将厂商与模型目录关联。Key 还包含隐私政策链接、同意状态、启用状态和来源，用于控制该厂商是否能参与场景 bundle 构建。

#### 基础要求与业务规则

- `providerID` 通过 `AIProviderIdentifier.normalize` 规范化；未显式传入时由 `company` 推导。
- 只有 `isEnabled == true` 的厂商 Key 才会被 `AILocalScenarioBundleBuilder` 匹配。
- Key 为空时，模型行仍可构建，但 `apiKey` 映射为 `nil`；是否允许请求由下游 gateway 决定。
- `source` 区分 `system`、`custom`、`pro`，保存时按账号和 `id` 做 upsert。
- `privacyPolicyAccepted` 与 `privacyPolicyAcceptedAt` 随 Provider 配置保存；Pro 申请卡片另有独立的客户端提交前隐私同意门禁，但申请接口当前只提交 `note`。

#### 主流程

```text
APIKeysSettingsView
  ↓
AISettingsViewModel 修改 snapshot.apiKeys
  ↓
300ms 草稿防抖 applyDraftSnapshot
  ↓
用户保存或单条保存
  ↓
DefaultAISettingsRepository.replaceProviders
  ↓
AIProviderEntity(ownerAccountID)
  ↓
AILocalScenarioBundleBuilder 按 providerID + isEnabled 匹配
```

#### 失败、重试和恢复

保存失败时 ViewModel 保留未保存状态和错误信息，下一次保存可重试。请求地址为空会导致非本地模型无法生成有效场景行；当前 builder 会跳过该行。未登录保存会记录日志并跳过持久化，不能当作成功保存。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift`：`APIKeys`、`AIProviderIdentifier`。
- `SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift`：`replaceProviders`、`upsertProvider`、`fetchProviders`。
- `SparkClient/Projects/App/Resources/SparkClient.xcdatamodeld/SparkClient.xcdatamodel/contents`：`AIProviderEntity`。
- `SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift`：设置页入口。

#### 验收标准

1. 同一账号保存后能恢复厂商 Key、请求 URL、启用状态和隐私同意信息。
2. 不同账号不能读取或覆盖彼此的 `AIProviderEntity`。
3. 启用厂商能被相同 `providerID` 的模型绑定引用；禁用厂商不会生成对应云端模型行。
4. 未登录保存不会误写入全局账号数据。

#### 3.1.1 Pro 模型申请卡片

##### 需求说明

厂商 Key 设置页内包含 Pro 模型试用申请卡片。卡片用于承载服务端试用策略对应的模型 API 能力申请，不直接编辑厂商目录；申请通过后，服务端以试用状态和场景模型策略控制可用模型。

##### 基础要求与业务规则

| 规则 | 当前实现 |
| --- | --- |
| 卡片入口 | `APIKeysSettingsView` 在 `viewModel.shouldShowTrialEntry` 为 true 时插入 `AITrialSettingsView`。当前入口条件为试用已激活或设备被识别为目标地区。 |
| 卡片展示模型 | 卡片展示固定的模型品牌 badge；试用已激活时，另按 `trialModelPolicy` 的 endpoint 匹配本地 `apiKeys`，展示服务端策略内的厂商列表。 |
| 初始状态 | `none`/非 active：显示隐私说明、同意开关和“提交申请”。 |
| 审核中 | `pending`：显示“申请审核中”，按钮不可重复提交。 |
| 申请拒绝或过期 | `rejected`、`expired`：显示可再次申请入口。 |
| 已开通 | `active`：显示开通状态和剩余天数；不再显示申请同意区域。 |
| 隐私门禁 | 用户未勾选隐私同意时，客户端阻止提交并显示错误；同意状态是卡片本地 UI 状态。 |
| 申请幂等/并发 | `AIConfigAPI.applyTrial` 使用高优先级、不可幂等的 POST；ViewModel 通过 `trialOperationInFlight` 禁止重复点击。 |
| 申请结果 | 提交接口不被视为最终审核结果；客户端将快照状态更新为返回的 status，并保持 `isActive=false`，等待推送或再次刷新。 |

##### 主流程

```text
打开 APIKeysSettingsView
  ↓
AITrialSettingsView.task → AISettingsViewModel.refreshTrialStatus
  ↓
GET /api/v1/ai/trial/status/
  ↓
更新 AITrialState，并持久化 PreferencesPayload
  ↓
根据 status 渲染申请卡片
  ↓
用户勾选隐私同意并点击提交
  ↓
POST /api/v1/ai/trial/apply/，body: { note }
  ↓
写入服务端返回的 status，置 isActive=false
  ↓
持久化本地快照并请求通知权限/APNs 注册
  ↓
收到 ai_trial_application_result 推送
  ↓
刷新本地运行时配置、Pro overlay 和试用状态
```

##### 失败、重试和恢复

| 场景 | 当前行为 | 恢复方式 |
| --- | --- | --- |
| 未勾选隐私同意 | 不发请求，卡片显示 `need_consent` | 勾选后重新提交 |
| 状态查询失败 | `errorMessage` 记录错误，保留上一次状态 | 页面刷新、重新进入或手动下拉刷新 |
| 申请请求失败 | `errorMessage` 记录网络/服务端错误，`trialOperationInFlight` 复位 | 用户可再次点击申请；拒绝/过期状态也允许再次申请 |
| 提交成功但尚未审核 | 不立即刷新最终 Pro 能力，只保存返回状态 | 等待 `ai_trial_application_result` 推送或刷新页面 |
| 推送到达 | `HandleRemoteNotificationUseCase` 发布通知 | `AISettingsViewModel` 刷新状态和运行时配置；`AppBootstrapper` 刷新远端配置 |
| 通知权限未决定 | 提交成功后请求授权并注册 APNs | 用户拒绝通知时，仍可通过页面刷新获取状态 |

##### 技术细节与设计代码位置

- `SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift`：试用卡片入口和 Provider 列表。
- `SparkClient/Projects/Features/AISettings/Presentation/Providers/AITrialSettingsView.swift`：卡片 UI、状态文案、隐私同意门禁、重复提交禁用和状态展示。
- `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift`：`refreshTrialStatus`、`submitTrialApplication`、提交后持久化和通知刷新。
- `SparkClient/Projects/Core/Networking/API/AI/AIConfigAPI.swift`：`fetchTrialStatus` 对应 `GET /api/v1/ai/trial/status/`；`applyTrial` 对应 `POST /api/v1/ai/trial/apply/`，申请体当前只有 `note`。
- `SparkClient/Projects/Core/AI/AIConfigModels.swift`：`AITrialState`、`AITrialApplicationSubmission`、`AITrialModelPolicyItem`。
- `SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift`：试用状态和 `trialModelPolicy` 属于 `PreferencesPayload`，保存到账号级 UserDefaults。
- `SparkClient/Projects/Features/AISettings/Application/AITrialNotifications.swift`：`aiTrialApplicationResultReceived` 通知名。
- `SparkClient/Projects/Core/Notification/Application/HandleRemoteNotificationUseCase.swift`：处理 `ai_trial_application_result` 推送并发布本地通知。
- `SparkClient/Projects/App/Sources/App/AppBootstrapper.swift`：收到申请结果通知后刷新 Pro 远端配置。

##### 当前实现限制

- 卡片同意开关只作为提交前客户端门禁，没有在 `applyTrial` 请求体中传递独立的 consent 字段；隐私同意时间也没有由该卡片写入 `APIKeys.privacyPolicyAcceptedAt`。
- `AITrialSettingsView.isSignedIn` 当前实现固定返回 true，真实登录权限主要由后端鉴权和上层会话链路承担。
- 申请接口被标记为不可幂等，客户端只有 UI 层防重复提交，未发现 request id 或服务端幂等键。

##### 验收标准

1. 满足入口条件时，厂商 Key 设置页展示 Pro 模型申请卡片；不满足时不显示。
2. 卡片能正确展示 `none`、`pending`、`rejected`、`expired`、`active` 状态及对应操作。
3. 未勾选隐私同意时不会调用申请接口；勾选后能提交申请。
4. 申请请求使用认证 POST `/api/v1/ai/trial/apply/`，提交期间不可重复点击。
5. 提交成功后客户端不伪造最终审核通过，只保存服务端返回状态并等待刷新。
6. 收到 `ai_trial_application_result` 推送后，试用状态和 Pro 远端配置都会刷新。
7. 网络失败、服务端失败和通知权限拒绝均有可恢复路径，不会清空已有本地 AI 配置。

### 3.2 模型目录配置

#### 需求说明

模型目录描述用户可选的基础模型和 Agent，包括名称、显示名、身份、厂商、能力标记、默认参数、本地模型文件名和来源。模型只有被场景绑定后，才会出现在该场景的候选列表中。

#### 基础要求与业务规则

- `AllModels.identity` 区分 `.model` 与 `.agent`；Agent 还可以关联工具场景和小任务。
- `isEnabled == false` 的模型不会进入本地场景 bundle。
- `localFilename` 记录本地 `.gguf` 文件名；`isLocalModel` 通过本地 provider 和模型身份判断。
- 模型的能力标记决定搜索、多模态、推理、工具、语音和图像能力是否可以在 UI/运行时使用。
- 删除模型时，ViewModel 同步删除与该模型相关的场景绑定及 Agent 关联配置。

#### 主流程

```text
模型设置页新增/编辑模型
  ↓
AISettingsViewModel 更新 allModels
  ↓
准备或替换 scenarioBindings
  ↓
保存 snapshot
  ↓
DefaultAISettingsRepository.replaceModels
  ↓
AIModelEntity
  ↓
AILocalScenarioBundleBuilder 仅使用已启用且有绑定的模型
```

#### 失败、重试和恢复

模型目录写入失败时保留页面草稿。模型存在但没有任何场景绑定时不会被推断加入 Chat 或医疗场景，这是现有测试明确保护的规则。模型被删除后若仍存在悬挂绑定，ViewModel 的清理逻辑应一并移除；仓储层自身只按快照替换，不承担跨快照业务修复。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift`：`AllModels`、模型能力字段、`localFilename`。
- `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift`：模型增删改、`upsertLocalBaseModel`、绑定同步。
- `SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift`：`replaceModels`、`upsertModel`、`fetchModels`。
- `SparkClient/Projects/App/Resources/SparkClient.xcdatamodeld/SparkClient.xcdatamodel/contents`：`AIModelEntity`。

#### 验收标准

1. 模型目录可以按账号保存并重新加载。
2. 禁用模型、无场景绑定模型不会进入相应场景候选列表。
3. 删除模型不会留下可被运行时使用的绑定。
4. 本地模型的 `localFilename` 能在保存后恢复。

### 3.3 场景模型绑定与默认配置

#### 需求说明

场景绑定是模型目录与业务 AI 场景之间的显式关系。每条绑定记录场景、模型 ID、模型身份、是否激活、位置、是否默认、温度、最大 token、系统提示词、工具场景和关联小任务。

#### 基础要求与业务规则

- `scenario` 使用 `AIScenario.rawValue`，当前 builder 为多个 Chat、医疗提取、报告解读、营养等场景分别生成 bundle。
- 只有 `isActive == true`、模型存在且模型已启用的绑定才参与构建。
- 同一场景允许多个候选模型，但默认绑定应保持唯一；ViewModel 在设置一条绑定为默认时，会清除同场景其他默认标记。
- 候选排序优先使用 `position`，再用 UUID 字符串保证稳定顺序。
- 场景绑定不存在时，该场景返回空 bundle，不根据模型目录自动推断绑定。
- 绑定上的温度和最大 token 进入 `AIScenarioRemoteModelRow`，最终解析时随模型配置返回。

#### 主流程

```text
模型编辑页/场景配置页
  ↓
创建或修改 AIScenarioModelBinding
  ↓
同场景默认标记归一化
  ↓
AISettingsViewModel 保存 snapshot
  ↓
DefaultAISettingsRepository.replaceScenarioBindings
  ↓
AILocalScenarioBundleBuilder.buildCollection
  ↓
每个 AIScenario 生成候选模型和 defaultModelName
```

#### 失败、重试和恢复

绑定引用不存在的模型、模型被禁用或云模型没有可用厂商 URL 时，builder 丢弃该候选行；如果场景最终没有候选模型，解析器会抛出 `AIConfigError.missingModelForScenario`。当前保存流程没有发现面向用户的“绑定引用完整性”预检报告，缺陷主要在运行时解析阶段暴露。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift`：`AIScenarioModelBinding`。
- `SparkClient/Projects/Features/AISettings/Presentation/Models/ModelScenarioBindingsEditorView.swift`：场景绑定编辑和默认切换。
- `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift`：绑定增删改和默认归一化。
- `SparkClient/Projects/Core/AI/AILocalScenarioBundleBuilder.swift`：绑定过滤、排序、模型行生成。

#### 验收标准

1. 一个场景可以维护多个候选模型，并按 position 稳定排序。
2. 设置某模型为默认后，同场景只保留一个默认绑定。
3. 无绑定场景不会隐式获得模型。
4. 场景没有可用模型时，运行时返回可识别的 `missingModelForScenario`。

### 3.4 本地与 Pro 配置合并

#### 需求说明

本地账号配置形成基础场景 bundle；Pro 用户从远端获得场景模型和小任务 overlay。运行时需要合并两者，同时保留本地配置的优先级和账号隔离。

#### 基础要求与业务规则

- `AIRuntimeConfigAssembler` 先放入本地模型行，再加入 Pro 行。
- 本地与 Pro 同名模型时，本地行优先，Pro 同名行被丢弃。
- 默认模型优先使用有效的本地默认，其次是有效的 Pro 默认，最后是合并后第一行。
- 小任务通过 code 合并，本地任务覆盖 Pro 同 code 任务；没有本地覆盖的 Pro 任务保留。
- Pro overlay 不写入账号本地目录，保存在 `AIRuntimeConfigStore` 的运行时状态中，并带 revision。

#### 主流程

```text
本地 snapshot → build local bundles → AIRuntimeConfigStore.localBundles
远端 AIConfigAPI → AIRemoteSettingsPatch → setProOverlay
两组 bundles → AIRuntimeConfigAssembler.merge
运行时 resolve → 返回合并后的场景策略
```

#### 失败、重试和恢复

Pro 请求失败时保留已有本地配置，启动流程可以继续使用本地 bundle。远端 overlay 结构无法解析时由 API 层映射为失败；当前未发现远端 revision 的持久化回滚机制。账号切换时必须重新绑定本地快照，避免复用旧账号的缓存。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Core/AI/AIRuntimeConfigAssembler.swift`：本地/Pro 合并和默认选择。
- `SparkClient/Projects/Core/AI/AIRuntimeConfigStore.swift`：本地 bundle、Pro overlay、revision、小任务缓存。
- `SparkClient/Projects/Core/AI/AIConfigCenter.swift`：`refreshRemoteConfig`、`setProOverlay` 调用链。
- `SparkClient/Projects/Core/Networking/API/AI/AIConfigAPI.swift`：远端配置响应映射。

#### 验收标准

1. Pro 不可用时，本地有效场景仍可解析。
2. 同名模型本地配置优先。
3. 本地默认失效时可以回退到有效 Pro 默认或首个候选。
4. 本地小任务能覆盖同 code 的 Pro 小任务。

### 3.5 小任务配置

#### 需求说明

小任务是可被 Chat/Agent 或工具流程引用的短任务配置，包含 code、名称、简介、图标、提示词、工具列表和来源。设置页允许管理本地任务，运行时同时暴露本地和 Pro 任务。

#### 基础要求与业务规则

- 任务 code 是本地更新、删除和本地覆盖 Pro 的稳定键，更新前会做 trim/规范化。
- 本地任务使用 `source == .local`，远端任务使用 `source == .service`。
- 本地任务新增 ID 根据当前本地任务最大 ID 加一生成；远端 ID 不应直接参与本地 ID 分配。
- Agent 配置可通过 `relatedTaskCodes` 关联小任务；删除本地任务时应同步移除本地任务记录，现有代码需由 UI/运行时决定如何处理悬挂关联。
- 当前首次种子初始化构造的 `AISettingsSnapshot` 将 `smallTasks` 设为空；小任务默认主要来自用户编辑或 Pro overlay，需以实际资源和远端响应为准。

#### 主流程

```text
SmallTasksSettingsView / Agent 编辑页
  ↓
AISettingsViewModel upsertLocalSmallTask / removeLocalSmallTask
  ↓
snapshot.smallTasks 更新
  ↓
保存到 AISmallTaskEntity
  ↓
AIRuntimeConfigStore.localSmallTasks
  ↓
effectiveSmallTasks：本地按 code 覆盖 Pro
```

#### 失败、重试和恢复

本地任务保存失败时保留草稿。code 为空或重复时，当前可见代码主要通过规范化和数组替换处理，未发现完整的用户侧重复校验错误模型。任务被 Agent 引用但删除后，当前未确认是否有统一的级联清理验收，属于风险项。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift`：`SmallTask`。
- `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift`：小任务 upsert、删除、本地 ID 生成、`effectiveSmallTasks`。
- `SparkClient/Projects/Features/AISettings/Presentation/SmallTasksSettingsView.swift`：小任务设置页。
- `SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift`：`replaceSmallTasks`、`fetchSmallTasks`。
- `SparkClient/Projects/Core/AI/AIRuntimeConfigStore.swift`：本地/Pro 小任务合并。

#### 验收标准

1. 本地小任务可新增、编辑、删除并按账号恢复。
2. 同 code 本地任务覆盖 Pro 任务，不同 code 的 Pro 任务仍可用。
3. Agent 关联任务 code 能被保存并可在编辑页重新展示。
4. 任务保存失败不会清除已有持久化配置。

### 3.6 场景策略最终解析

#### 需求说明

场景 bundle 只描述候选模型；实际请求前还要根据用户偏好、运行时 override 和 bundle 默认值解析出唯一的 `AIScenarioConfig`。

#### 基础要求与业务规则

`ScenarioPolicyResolver` 的当前优先级为：

```text
preferredModelName
  > AIRuntimeStore 中的 runtime override
  > 当前场景 bundle.defaultModelName / 默认行
  > 无可用模型时抛出 missingModelForScenario
```

解析结果必须包含 endpoint、model、apiKey、temperature、maxTokens 和来源信息。非法 endpoint 会进入 `AIConfigError.invalidEndpoint`，缺少模型进入 `missingModelForScenario`。

#### 主流程

```text
AIRuntimeService.generateTextStream
  ↓
AIConfigCenter.resolve(scenario, preferredModelName)
  ↓
ScenarioPolicyResolver.resolve
  ↓
AIRuntimeStore runtime override / merged bundle
  ↓
AIScenarioConfig
```

#### 失败、重试和恢复

解析失败不会自动凭空创建模型。上层启动流程对 `missingModelForScenario` 有降级处理；请求侧应将错误映射到用户可见状态。当前测试覆盖 runtime override 优先级、场景默认选择和 Pro 来源保持。

#### 技术细节与设计代码位置

- `SparkClient/Projects/Core/AI/ScenarioPolicyResolver.swift`：最终优先级和错误。
- `SparkClient/Projects/Core/AI/AIConfigCenter.swift`：运行时配置入口。
- `SparkClient/Projects/Core/AI/AIRuntimeService.swift`：请求前 resolve。
- `SparkClient/Tests/AI/AISettingsAndResolverTests.swift`：解析优先级测试。

#### 验收标准

1. 指定模型存在时优先使用指定模型。
2. runtime override 存在时能覆盖默认策略。
3. 无 override/选择时使用场景默认模型。
4. 场景无可用模型时返回明确错误，不返回空请求。

## 四、整体业务流程

### 4.1 冷启动与首次配置

```mermaid
flowchart TD
    A[登录账号] --> B[AppBootstrapper.bootstrapIfNeeded]
    B --> C[AIConfigCenter.prewarm(ownerAccountID)]
    C --> D[Repository.loadSnapshot]
    D --> E{是否完成种子初始化}
    E -- 否 --> F[读取 AISettingsSeedCatalog]
    F --> G[写入账号级 Core Data]
    E -- 是 --> H[读取账号级 Core Data]
    G --> I[组合 AISettingsSnapshot]
    H --> I
    I --> J[AILocalScenarioBundleBuilder]
    J --> K[AIRuntimeConfigStore]
    K --> L[可供场景解析]
```

### 4.2 设置页编辑与保存

```text
打开 AI 设置页
  ↓
加载显式 ownerAccountID 的 snapshot
  ↓
修改 Provider / Model / Binding / SmallTask
  ↓
snapshot 变化，标记 hasUnsavedChanges
  ↓
300ms 防抖，仅应用内存草稿
  ↓
点击保存
  ↓
校正搜索 revision，Repository.save 全量替换账号快照
  ↓
AIConfigCenter.rebuildRuntimeCache
  ↓
刷新小任务和场景解析结果
```

### 4.3 运行时请求

```text
业务请求指定 AIScenario
  ↓
AIConfigCenter.resolve
  ↓
ScenarioPolicyResolver 选择模型
  ↓
检查 endpoint / provider / localFilename
  ↓
OpenAICompatibleTextGateway 或本地 gateway
  ↓
返回流式文本或结构化错误
```

## 五、状态模型

| 状态 | 触发 | 数据来源 | 用户/调用方可见结果 |
| --- | --- | --- | --- |
| 未加载 | 设置页或启动预热尚未完成 | 无 | 显示加载态，不能假定默认模型可用 |
| 未登录空快照 | ownerAccountID 为空 | `AISettingsSnapshot.default`/空目录 | 不读其他账号；保存被跳过或需等待登录 |
| 首次初始化中 | 账号无 `AISettingsSeedStateEntity` | bundle 资源 | 初始化成功后进入已加载 |
| 已加载 | Core Data/UserDefaults 成功读取 | 账号快照 | 设置页展示目录 |
| 草稿已修改 | snapshot 变化 | 内存 | `hasUnsavedChanges=true`，可预览但未持久化 |
| 已保存 | Repository.save 成功 | Core Data + UserDefaults + runtime cache | 草稿清除，运行时更新 |
| 远端覆盖可用 | Pro 配置请求成功 | 内存 overlay | 与本地合并后解析 |
| 部分可用 | Pro 失败或部分场景无模型 | 本地 bundle | 保留本地能力，具体场景可能解析失败 |
| 配置失败 | 读取、保存或解析异常 | 错误模型 | 展示错误或由启动流程降级 |

账号切换是边界事件：`AIConfigCenter` 和 `AIRuntimeConfigStore` 必须按新的 ownerAccountID 重新加载并验证缓存归属，不能把上一账号的 current snapshot 当作当前配置。

## 六、数据与持久化

### 6.1 聚合快照

`AISettingsSnapshot` 是设置页和仓储之间的聚合对象，至少包含 `allModels`、`apiKeys`、`searchKeys`、`scenarioBindings`、`smallTasks`、`promptRepo` 和各类运行偏好。轻量偏好通过 `PreferencesPayload` 单独编码，目录数据不以整包 JSON 作为唯一持久化源。

### 6.2 Core Data 映射

| 领域对象 | Core Data 实体 | 关键字段 |
| --- | --- | --- |
| `APIKeys` | `AIProviderEntity` | id、providerID、key、requestURL、isEnabled、ownerAccountID |
| `AllModels` | `AIModelEntity` | id、name、identity、providerID、baseModelName、localFilename、能力字段、ownerAccountID |
| `AIScenarioModelBinding` | `AIScenarioModelBindingEntity` | modelID、scenario、identity、isActive、isDefault、position、temperature、maxTokens、ownerAccountID |
| `SmallTask` | `AISmallTaskEntity` | id、code、name、prompt、toolListData、source、ownerAccountID |
| 搜索厂商 | `AISearchProviderEntity` | id、key、requestURL、isUsing、priority、revision、ownerAccountID |
| 提示词 | `PromptRepoEntity` | id、title、content、isSystem、position、ownerAccountID |
| 初始化标记 | `AISettingsSeedStateEntity` | ownerAccountID、catalogVersion、updatedAt |

### 6.3 初始化和保存策略

`ensureSeedDataIfNeeded` 只以是否存在账号级种子状态行判断首次初始化；`AISettingsSeedCatalog.version` 当前用于记录和排查，不会触发已初始化账号自动重灌。`persist` 采用“删除快照中已不存在的旧行 + upsert 当前行”的替换策略，保存范围限定为显式 ownerAccountID。

## 七、错误模型

| 错误/异常 | 来源 | 当前处理 |
| --- | --- | --- |
| 未登录 ownerAccountID | Repository/AIConfigCenter | 返回空快照或跳过写入并记录日志 |
| Core Data 读取/写入失败 | `DefaultAISettingsRepository` | 上层捕获；加载失败回退空快照，保存失败保留草稿 |
| 种子 JSON 为空或解码失败 | `AISettingsSeedCatalog`/loader | 模型为空时不写初始化标记，下次重试 |
| `missingModelForScenario` | `ScenarioPolicyResolver` | 启动流程可降级；运行时请求失败 |
| `invalidEndpoint` | AI 配置解析 | 拒绝无效 endpoint |
| Provider 被禁用或 URL 为空 | `AILocalScenarioBundleBuilder` | 跳过对应云模型行 |
| Pro 试用状态查询失败 | `AIConfigAPI.fetchTrialStatus` | 保留已有状态并记录 `errorMessage`，页面刷新可重试 |
| Pro 申请未同意隐私条款 | `AITrialSettingsView` | 客户端不发申请请求，提示先完成同意 |
| Pro 申请失败或重复提交 | `AIConfigAPI.applyTrial` / ViewModel | 显示错误并复位 in-flight 状态；当前仅 UI 层防重复 |
| 远端 Pro 配置失败 | `AIConfigCenter.refreshRemoteConfig` | 保留本地配置，Pro overlay 不应替换本地基础配置 |
| 小任务 code 冲突 | ViewModel/合并器 | 本地按 code 覆盖 Pro；当前未发现统一的重复提示 |

当前未确认：是否存在统一的 Core Data 错误 UI、保存重试次数、远端 overlay 回滚和小任务删除后的 Agent 关联清理机制。

## 八、与其他模块的接口边界

### 本模块负责

- 维护账号级 AI 配置目录及其初始化状态。
- 将设置页编辑映射为领域快照和运行时 bundle。
- 维护本地/Pro 场景配置和小任务的合并结果。
- 向运行时提供可解析的模型候选和场景策略。

### 本模块不负责

- 不负责具体文本生成、流式传输或医疗业务结果解析。
- 不负责 API Key 的服务端验证和计费授权。
- 不负责本地 GGUF 推理引擎的底层实现。
- 不负责文件下载以外的通用文件/OSS 业务。

### 依赖和交接

| 交接方 | 输入 | 输出/约束 |
| --- | --- | --- |
| `AppBootstrapper` | 当前登录账号 ID | 请求预热、远端刷新和场景解析 |
| `AIConfigAPI`/remote provider | 会话和 Pro 权限 | `AIRemoteSettingsPatch`，不直接写本地目录 |
| `AIRuntimeService` | `AIScenario`、可选 preferred model | 依赖 `AIConfigCenter.resolve` 得到 `AIScenarioConfig` |
| 设置页 | 用户编辑动作 | 修改 `AISettingsSnapshot`，保存由 ViewModel 编排 |
| Core Data | 账号级领域对象 | 持久化并按 ownerAccountID 隔离 |

## 九、关键代码对应关系

| 责任 | 关键文件/符号 |
| --- | --- |
| 快照聚合 | `Projects/Features/AISettings/Domain/AISettingsSnapshot.swift` / `AISettingsSnapshot` |
| 领域对象 | `Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` / `APIKeys`、`AllModels`、`AIScenarioModelBinding`、`SmallTask` |
| 仓储协议与实现 | `Domain/AISettingsRepository.swift`、`Infrastructure/DefaultAISettingsRepository.swift` |
| 种子目录 | `Domain/AISettingsSeedCatalog.swift`、`Projects/App/Resources/AISettings/` |
| 设置页编排 | `Presentation/Root/AISettingsViewModel.swift` |
| 场景 bundle | `Core/AI/AILocalScenarioBundleBuilder.swift` |
| 本地/Pro 合并 | `Core/AI/AIRuntimeConfigAssembler.swift`、`AIRuntimeConfigStore.swift` |
| 最终策略 | `Core/AI/ScenarioPolicyResolver.swift`、`AIConfigCenter.swift` |
| 远端配置 | `Core/Networking/API/AI/AIConfigAPI.swift` |
| 数据模型 | `Projects/App/Resources/SparkClient.xcdatamodeld/SparkClient.xcdatamodel/contents` |
| 测试 | `Tests/AI/AISettingsAndResolverTests.swift` |

## 十、测试策略

### 已有测试

- `testAPIKeysSeedJSONDecodesToNonEmptyCatalog`：防止 APIKeys 种子资源因 Codable key 不匹配而静默变为空表。
- `testLocalBundleDoesNotInferModelsWithoutScenarioBindings`：保护“无显式绑定不自动推断场景模型”。
- `testScenarioResolverPrefersRuntimeOverride`：保护运行时 override 优先级。
- `testTrialPolicyFallsBackToDefaultFlagWhenNoSelection`、`testScenarioDefaultModelOverridesChatPicker`：保护默认策略选择。
- Pro overlay 来源保持相关测试：保护远端模型来源和 preferred model 解析。

### 当前应补充的高风险测试

1. Repository 的两个账号互读隔离、删除快照旧行和 UserDefaults payload 损坏恢复。
2. 首次种子成功、空模型种子不写 seed state、重复启动不覆盖用户修改。
3. 同场景多个默认绑定归一化、绑定引用缺失、Provider 禁用和 URL 为空。
4. 本地任务按 code 覆盖 Pro 任务、同 code 更新、删除任务后的 Agent 关联处理。
5. 账号切换后 `currentSnapshot` 和 runtime cache 不复用旧账号。
6. 保存失败时 ViewModel 的 `hasUnsavedChanges`、错误信息和运行时缓存状态。
7. Pro 申请卡片的状态渲染、隐私同意门禁、申请 POST、提交后 pending 状态和推送刷新。

## 十一、当前实现、缺口与演进

### 当前实现

- 厂商、模型、场景绑定、小任务均有领域模型、Core Data 映射和设置页入口。
- 首次账号初始化和全量快照保存已经接入 `DefaultAISettingsRepository`。
- 本地 bundle、Pro overlay、默认模型解析和 runtime override 已形成可调用链路。
- 现有测试覆盖部分优先级、种子解码和显式绑定规则。

### 当前缺口

- 未发现保存前统一的配置完整性校验报告，很多错误要到 bundle 构建或运行时解析才暴露。
- 未发现完整的 Core Data 持久化集成测试，账号隔离和失败恢复主要依赖实现逻辑。
- 小任务删除后的 Agent 关联清理、重复 code 的用户提示和并发保存策略尚未完全确认。
- 初始化使用固定“首次写入”语义，不会自动把新版本 bundle 目录迁移到已有账号。

### 建议演进

- 增加 `AISettingsValidator`，在保存前检查 Provider URL、模型引用、场景默认唯一性、小任务 code 和本地文件存在性；代价是需要定义面向 UI 的字段级错误模型。
- 为种子目录引入显式迁移版本和只追加/只修复策略，避免整包覆盖用户修改；需要维护迁移记录和回滚边界。
- 将“快照保存、runtime cache 重建、远端 overlay 失效”整理为可观测的事务状态，降低保存成功但运行时未刷新时的排查成本。

## 十二、整体验收标准

1. 登录账号首次加载时，能以 `AISettingsSeedCatalog` 初始化该账号的 Provider、模型、场景绑定、搜索 Key 和提示词目录。
2. 账号切换后，设置页、运行时缓存和 Core Data 读取均只使用当前账号数据。
3. 用户能够维护厂商 Key、模型目录、场景绑定、默认模型参数和本地小任务，并在保存后重新加载。
4. 场景 bundle 只包含已启用、存在绑定且具有有效 endpoint 的模型；本地模型使用 `local://chat/completions` 作为配置端点标识。
5. 场景默认模型、preferred model、runtime override、Pro overlay 的优先级与代码一致，并在无模型时返回明确错误。
6. 本地小任务按 code 覆盖 Pro 同名任务，其他 Pro 任务仍可见。
7. 保存失败、Core Data 失败、无账号、种子为空、Provider 禁用和场景无模型等情况均不会静默产生错误配置。
8. 测试至少覆盖现有解析优先级和种子/绑定规则，并补齐账号隔离、初始化幂等、保存失败和小任务合并测试。

## 十三、UI 设计文档：页面、组件与交互

### 13.1 UI 设计边界

本节依据以下真实 SwiftUI 代码整理页面、组件和点击后的效果：

- `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Providers/ProviderSettingsEditorView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsSettingsView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Models/ModelManagementView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Models/AddOnlineModelSheet.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIModelPreferencesView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Models/ModelScenarioBindingsEditorView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Root/SmallTasksSettingsView.swift`
- `SparkClient/Projects/Features/AISettings/Presentation/Root/SmallTaskEditorView.swift`

截图展示的视觉方向为本模块参考：浅灰背景、白色圆角分组、蓝色图标和开关、粗体页面标题、右侧返回/新增/保存操作。当前代码的真实容器仍主要是 SwiftUI `List`、`Form`、`Section` 和系统导航栏；实现时必须以代码行为为准，视觉卡片化不能改变保存、校验、刷新和错误处理语义。

### 13.2 全局交互规范

| 组件 | 默认状态 | 点击/编辑效果 | 关闭、失败和恢复 |
| --- | --- | --- | --- |
| 返回 | 导航栏左侧系统返回 | 返回上一级 | 不清除已保存配置；草稿由当前页面生命周期处理 |
| 保存 | 右侧确认操作；无效输入时禁用 | 校验草稿，更新 `snapshot`，按当前 ViewModel 路径持久化并刷新 runtime cache | 失败保留草稿和错误，可再次保存 |
| 取消 | Sheet 编辑页左侧 | 关闭当前 Sheet，不提交纯草稿 | 已经发生的即时保存不回滚 |
| 整行按钮/导航行 | 行末显示 chevron | 推入子页面或打开编辑 Sheet | 子页面失败显示 alert，不破坏父页面数据 |
| Toggle | 蓝色启用，灰色关闭 | 立即更新内存；Provider 开关、Key 编辑开关会持久化 | 缺少 Key、未同意隐私政策或保存失败时恢复原值 |
| Picker | 显示当前值 | 弹出选项或切换来源，写入对应偏好 | 没有候选模型时显示空状态，不产生无效选择 |
| 刷新 | 页面可下拉时显示系统刷新控件 | 重新拉取模型目录、Pro overlay、试用状态 | 失败保留上一份本地数据 |
| 删除 | 左滑出现 destructive Delete | 删除模型、小任务或场景绑定 | 小任务先二次确认；取消不删除 |
| 信息按钮 | 模型行显示 info | 展示能力、价格、来源或说明 | 详情缺失时仍显示已有字段 |

### 13.3 页面导航树

```text
AI 设置
├── 模型密钥
│   ├── Pro 试用申请卡片
│   ├── Provider 编辑
│   │   ├── 隐私政策 Web 页面
│   │   └── 模型管理
│   │       └── 手动添加在线模型
│   └── 新增自定义供应商
├── 模型
│   ├── 搜索/身份筛选/排序/编辑模式
│   ├── 在线模型编辑
│   ├── 本地模型下载/导入
│   └── Agent 编辑
├── 默认模型配置
│   └── 各 AI 场景的来源与模型选择
└── 小任务
    └── 新建/编辑小任务
        ├── 图标选择
        ├── Prompt 输入
        └── 工具选择
```

### 13.4 页面一：AI 设置首页

页面入口为 `AISettingsView`，加载时执行 `viewModel.load()`。分为“模型设置”和“工具/检索/知识”两组。

```text
┌──────────────────────────────────────┐
│                 AI 设置              │
├──────────────────────────────────────┤
│ 模型设置                             │
│  🔑 模型密钥        厂商密钥与端点  › │
│  ─────────────────────────────────── │
│  ▱  模型            模型目录与能力开关›│
│  ─────────────────────────────────── │
│  ☷  默认模型配置    按场景配置本地/Pro›│
│                                      │
│ 工具/检索/知识                        │
│  ☑  小任务          维护本地小任务   › │
└──────────────────────────────────────┘
```

| 组件 | 点击后的效果 | 代码事实 |
| --- | --- | --- |
| 模型密钥行 | 推入 `APIKeysSettingsView` | 读取 `snapshot.apiKeys` |
| 模型行 | 推入 `ModelsSettingsView` | 管理模型、Agent、本地模型 |
| 默认模型配置行 | 推入 `AIModelPreferencesView` | 创建场景偏好 ViewModel 并加载 bundle |
| 小任务行 | 推入 `SmallTasksSettingsView` | 只展示本地小任务 |
| 首页错误弹窗 | 点击确定关闭 | 调用 `viewModel.clearError()` |
| 注释掉的入口 | 当前不展示搜索工具、Prompt、记忆档案、翻译词典 | 不得在验收时视为已实现 |

### 13.5 页面二：模型密钥列表

入口为 `APIKeysSettingsView`，过滤本地 Provider，按显示名排序。截图中的白色卡片分组是目标视觉形态。

```text
┌──────────────────────────────────────┐
│ ‹              模型密钥             ＋│
├──────────────────────────────────────┤
│ [Pro 试用申请卡片：按状态动态显示]     │
│                                      │
│ 模型厂商                             │
│  ◉ 302.AI                         › ○│
│  ─────────────────────────────────── │
│  ◉ 推理时代                        › ○│
│  ─────────────────────────────────── │
│  ◉ Anthropic                       › ○│
│  ─────────────────────────────────── │
│  ◉ 字节豆包                        › ○│
└──────────────────────────────────────┘
```

| 组件 | 交互和副作用 |
| --- | --- |
| 右上角 `+` | 打开 `AddCustomProviderSheet`；空表单保存禁用 |
| Provider 行 | 点击进入 `ProviderSettingsEditorView`；自定义 Provider 显示铅笔图标 |
| Provider 开关 | 开启前必须有 Key；成功调用 `setProviderEnabledAndPersist`，失败恢复并弹错误 |
| Pro 试用卡片 | `shouldShowTrialEntry` 为 true 时出现在列表顶部，内部按钮按试用状态变化 |
| 下拉刷新 | 调用 `refreshProviderRuntimeConfiguration`，刷新远端模型、Pro 配置、试用状态和本地快照 |
| 错误 alert | 新增或切换 Provider 失败时显示，确认后保留旧列表 |

#### 新增自定义供应商 Sheet

```text
┌──────────────────────────────────────┐
│ 取消        新增自定义供应商       保存│
├──────────────────────────────────────┤
│ 供应商名称  [                    ]    │
│ API Key     [••••••••••••••••••••]    │
│ 请求地址    [https://             ]   │
│ [补全 /v1/chat/completions]           │
│ 错误信息（URL 不合法时）              │
└──────────────────────────────────────┘
```

- 名称、Key、请求地址任一为空，保存禁用。
- URL 必须以 `http://` 或 `https://` 开头；否则点击保存不关闭 Sheet，在表单内显示错误。
- URL 未以 `/v1/chat/completions` 结尾时显示补全按钮；点击后去除尾部 `/` 并追加路径。
- 保存生成 `CUSTOM_XXXXXXXX` Provider ID，通过 `addProviderAndPersist` 写入并立即持久化。
- 取消只关闭 Sheet，不创建 Provider。

### 13.6 页面三：Provider 编辑

入口为 `ProviderSettingsEditorView`，负责 Provider 总开关、端点、密钥、隐私政策、模型列表和 API 测试。

```text
┌──────────────────────────────────────┐
│ ‹            编辑密钥             保存│
├──────────────────────────────────────┤
│ [✓] 字节豆包                         │
│ 请求地址  https://...                │
│ API Key   ••••••••••••••••            │
│ 查看隐私政策                         │
│ [✓] 我已阅读并同意该厂商隐私政策      │
│                                      │
│ 该厂商模型                         ＋│
│  ◉ Doubao Seed 1.6       ⓘ       [✓]│
│  ─────────────────────────────────── │
│  ◉ Doubao Seed 1.6 Lite  ⓘ       [✓]│
│                                      │
│ API 测试                             │
│ 测试模型       Doubao Seed 1.6    ˅  │
│ 测试 API          [加载中/成功/失败]  │
└──────────────────────────────────────┘
```

| 组件 | 点击/编辑效果 |
| --- | --- |
| Provider 总开关 | 更新 `isHidden` 并持久化；开启时 Key 为空显示需要 Key 提示 |
| 请求地址 TextField | 编辑 `provider.requestURL`，关闭自动纠错和自动大写 |
| API Key SecureField | 编辑 `provider.key`，只以密文输入，日志和 UI 不得展示明文 |
| 查看隐私政策 | 打开 `ProviderPrivacyPolicyWebSheet`；URL 无效时不显示 |
| 隐私同意开关 | 修改 `privacyPolicyAccepted`；有政策且未同意时保存按钮禁用 |
| 模型行开关 | 修改模型启用状态，最终影响场景 bundle |
| 模型行信息按钮 | 展示模型能力、价格和来源 |
| 模型行左滑删除 | 删除模型并清理相关绑定；失败恢复行 |
| 模型区 `+` | 打开 `ModelManagementView` |
| 测试模型 Picker | 仅列出已启用且支持文本生成的模型；没有模型时测试禁用 |
| 测试 API | 调用 `testProviderConnection`；显示 ProgressView，完成后显示成功/失败和错误文本 |
| 保存 | 隐私同意通过后保存并退出；失败保留草稿 |

### 13.7 页面四：模型管理

`ModelManagementView` 是 Provider 编辑页打开的 Sheet，分为自动刷新、已添加模型、远端可用模型。

```text
┌──────────────────────────────────────┐
│ 关闭       ARK_API_KEY 模型       ＋ ↻│
├──────────────────────────────────────┤
│ 自动刷新                             │
│ 进入页面自动拉取一次模型列表；        │
│ 也支持下拉或右上角手动刷新             │
│                                      │
│ 已添加 (2)                           │
│  ◉ Doubao Seed 1.6              [✓] │
│  ◉ Doubao Seed 1.6 Lite          [✓]│
│                                      │
│ 远端可用 (118)                       │
│  ◉ deepseek-r1-250120          [添加]│
│  ◉ deepseek-r1-250528          [添加]│
│                                      │
│ 🔍 搜索模型                          │
└──────────────────────────────────────┘
```

- 关闭退出 Sheet；`+` 打开手动添加在线模型；刷新和下拉刷新均调用 `refreshModels()`。
- 已添加模型的开关改变 `isEnabled`；远端模型的“添加”按钮写入当前 Provider 的本地模型目录。
- 搜索只过滤显示，不删除数据；无结果显示空状态。
- Key 为空、加载中、网络失败都要有区块级状态；失败保留已添加模型。

### 13.8 页面五：添加在线模型

入口为 `AddOnlineModelSheet`。

```text
┌──────────────────────────────────────┐
│ 取消        添加在线模型           添加│
├──────────────────────────────────────┤
│ 基本信息                             │
│ 🔎 系统名称  [用于 API 请求         ] │
│ 格式        [显示名称（自定义）     ] │
│ 🏢 厂商      [字节豆包             ˅] │
│                                      │
│ 价格                                 │
│ ￥ 价格档位                  免费 ˅  │
│                                      │
│ 能力                                 │
│ ◉ 默认隐藏                         ○ │
│ ✨ 自动模型能力探测                  ›│
│ 注意：自动探测可能产生 API 费用       │
│ 字  支持文本                        ✓ │
│ ▣  支持多模态                      ○ │
│ ⚛  支持推理                        ○ │
│ 💡 思考可控                        ○ │
│ 🔨 支持工具                        ○ │
│ ◇  支持生图                        ○ │
└──────────────────────────────────────┘
```

| 组件 | 点击/编辑效果 |
| --- | --- |
| 系统名称/显示名称 | 必填，分别写入 API 名和展示名 |
| 厂商 Picker | 只能选择已配置 Key 的 Provider |
| 价格档位 Picker | 免费/经济/标准/高级，影响价格 badge |
| 默认隐藏 | 写入 `isHidden`，隐藏模型不应成为默认候选 |
| 自动能力探测 | 调用 `ClientModelCapabilityProbeService`，打开结果 Sheet；失败弹 alert |
| 能力开关 | 写入文本、多模态、推理、思考可控、工具调用、生图字段 |
| 添加 | 校验三个必填字段和 Provider；成功保存模型并关闭，失败保留草稿 |
| 取消 | 关闭 Sheet，丢弃草稿 |

当前代码中“使用场景”和“工具”区块被注释，不应在当前版本验收中当作已实现；场景绑定通过绑定编辑页完成。

### 13.9 页面六：模型目录

`ModelsSettingsView` 提供模型搜索、身份筛选、编辑态、排序、本地模型下载、在线模型添加和 Agent 入口。

```text
┌──────────────────────────────────────┐
│ ‹                 模型       编辑/完成│
├──────────────────────────────────────┤
│ 🔍 搜索模型                          │
│ [模型 ▾] [排序 ↕]                     │
│                                      │
│ ◉ Doubao Seed 1.6     工具 视觉  ✓ › │
│ ◉ Qwen 3 0.6B         文本  本地  ✓ ›│
│ ◉ Health Agent        工具 任务  ✓ › │
│                                      │
│ ＋ 添加在线模型                       │
│ ↓ 下载本地模型                        │
└──────────────────────────────────────┘
```

- 搜索按名称、显示名或厂商过滤；身份 Picker 过滤模型/Agent。
- 编辑按钮切换编辑态，完成按钮退出；排序菜单提供当前代码支持的排序和重置排序。
- 模型行进入 `ModelsAdvancedEditorView`；编辑态支持删除，删除时同步清理场景绑定和 Agent 关联。
- 在线添加打开 `AddOnlineModelSheet`；本地下载打开 `LocalModelDownloadSheet`；Agent 打开 `ModelsSettingsAgentSheet`。
- 错误由 alert 展示，保留未受影响的模型。

### 13.10 页面七：默认模型配置

入口为 `AIModelPreferencesView`，按 `AIScenario.allCases` 展示各业务场景。用户可以选择本地 Key 或 Pro 试用来源，再选择该来源下的模型。

```text
┌──────────────────────────────────────┐
│ ‹              默认模型配置           │
├──────────────────────────────────────┤
│ 🔍 搜索场景                          │
│                                      │
│ 普通聊天                             │
│      聊天场景使用的模型说明           │
│ [本地 Key] [Pro 试用]                 │
│ 模型选择       Doubao Seed 1.6     ˅  │
│ ◉ 字节豆包  Doubao Seed 1.6           │
│                                      │
│ 报告解读                             │
│      报告分析场景说明                 │
│ 模型选择       尚未配置               │
└──────────────────────────────────────┘
```

| 组件 | 点击/编辑效果 |
| --- | --- |
| 搜索场景 | 按本地化场景名/关键词过滤；无结果显示放大镜和提示 |
| 场景说明 | 只读，说明用途 |
| 来源 segmented Picker | 在本地 Key 与 Pro 试用间切换并刷新 bundle |
| 模型 Picker | 只能选择当前 bundle 中的模型或“未选择”，写入场景偏好 |
| 摘要行 | 显示厂商图标、展示名、原始模型名，原始名可复制 |
| 无模型状态 | 显示“请先配置 Key/模型”，不产生无效默认值 |

当前实现没有独立保存按钮，场景选择由 `ScenarioModelPreferencesViewModel` 写入 `PreferencesPayload`。如果视觉稿增加保存按钮，必须同时增加 dirty state 和保存语义，不能只增加按钮外观。

### 13.11 页面八：模型-场景绑定编辑

入口为 `ModelScenarioBindingsEditorView`，把一个模型绑定到一个或多个 AI 场景。

```text
┌──────────────────────────────────────┐
│ ‹              使用场景             ＋│
├──────────────────────────────────────┤
│ 普通聊天                             │
│ 默认  0.70  4096                     │
│                                      │
│ 报告解读                             │
│ 0.20   8192   未启用                 │
└──────────────────────────────────────┘
```

- 点击已有行进入编辑；右上角 `+` 新增；所有场景均已绑定时 `+` 禁用；左滑删除。
- 新增表单包含场景 Picker；编辑表单包含启用 Toggle、默认 Toggle、temperature、maxTokens、描述、系统提示词、工具场景和关联小任务。
- 保存默认绑定时，自动清除同一场景的其他默认标记，保证一个场景最多一个默认模型。
- 新增绑定按该场景当前最大 `position + 1` 排序。
- 取消不调用 `onPersist`；保存通过 `upserted`，删除通过 `deletedID` 通知上层。
- 列表行必须显示场景名、默认、temperature、maxTokens 和未启用状态，不能只显示模型名。

### 13.12 页面九：小任务列表

入口为 `SmallTasksSettingsView`，只显示 `source == .local` 的小任务，并按 `code` 排序。

```text
┌──────────────────────────────────────┐
│ ‹                小任务              ＋│
├──────────────────────────────────────┤
│ ☑ 摘要整理                           │
│    将长文本整理成摘要                 │
│ ───────────────────────────────────── │
│ ☑ 健康术语解释                       │
│    使用通俗语言解释医学术语           │
└──────────────────────────────────────┘
```

- 空列表显示空状态文案。
- 点击整行打开 `SmallTaskEditorView`。
- 右上角 `+` 创建 `SmallTask.newDraft(id: nextLocalSmallTaskID())`，生成稳定的 `Local_<id>` code。
- 左滑删除先弹“删除小任务？”确认框；确认调用 `deleteLocalSmallTaskAndPersist(code:)`，取消只关闭弹窗。
- 删除后必须检查 Agent/场景绑定中的 `relatedTaskCodes`；当前是否自动清理未完全确认，属于验收风险。

### 13.13 页面十：新建/编辑小任务

```text
┌──────────────────────────────────────┐
│ 取消          新建小任务           保存│
├──────────────────────────────────────┤
│ 图标                                 │
│                 [  ☑  ]              │
│ 基本信息                             │
│ 名称        [                    ]    │
│ 简述        [                    ]    │
│ Prompt                               │
│ [输入 Prompt                    🎙  ]│
│ 工具                         全部   › │
└──────────────────────────────────────┘
```

| 组件 | 点击/编辑效果 |
| --- | --- |
| 图标按钮 | 打开 `ModelIconPickerSheet`，选择结果回填 `icon` |
| 名称 | 必填，保存时去除首尾空白 |
| 简述 | 可选，列表副标题为空时回退显示 code |
| Prompt 输入 | 编辑提示词；文本抽屉支持翻译/OCR，语音按钮打开语音输入 Sheet |
| 工具行 | 推入 `GroupedToolSelectionView`，显示“全部”“无”或 `n/total` |
| 保存 | 名称和 Prompt 非空时可用，调用 `SmallTask.createLocalTask` 后关闭 |
| 取消 | 关闭 Sheet，丢弃纯草稿 |
| 输入失败 | 翻译、OCR、语音错误不清除已输入 Prompt |

### 13.14 Pro 试用申请卡片

卡片由 `AITrialSettingsView` 渲染，位于模型密钥列表顶部；显示条件由 `shouldShowTrialEntry` 决定。

```text
┌──────────────────────────────────────┐
│ 🔑 模型密钥 / 试用权限                │
│    配置 API Key 后可启用对应模型能力  │
│                                      │
│ ✓ 试用已开通       剩余 80 天          │
│ [OpenAI] [Gemini] [Claude] [DeepSeek] │
│ [✓] 我已阅读并同意隐私政策             │
│              提交申请                │
└──────────────────────────────────────┘
```

- `none`/拒绝/过期显示隐私同意和申请按钮；未同意时不发请求。
- `pending` 显示审核中并禁用提交，避免重复 POST。
- `active` 显示剩余天数和服务端模型策略，不显示重复申请控件。
- 提交成功只保存服务端返回状态并等待推送，不提前渲染为 active。
- 请求失败恢复按钮并显示错误；通知权限被拒绝不影响下拉刷新查询。

### 13.15 UI 状态矩阵

| 页面 | 加载 | 空数据 | 编辑中 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| AI 设置首页 | `isLoading` | 固定入口仍显示 | 由子页承担 | 子页返回 | 首页 alert |
| 模型密钥 | 列表加载 | 无 Provider 空分组 | 新增 Provider Sheet | 列表刷新 | alert，保留旧列表 |
| Provider 编辑 | 表单加载 | 无模型 empty 文案 | `provider` 草稿 | 保存退出 | alert/状态文本 |
| 模型管理 | 自动刷新 | 两个分区分别空 | 手动添加 Sheet | 列表刷新 | alert，保留已添加 |
| 添加在线模型 | 表单状态 | 无 Provider 不可保存 | 本地 draft | 添加后关闭 | alert，保留草稿 |
| 默认模型配置 | bundle reload | 无场景/模型空状态 | Picker 即时改 | 写入偏好 | 保留上一选择 |
| 小任务 | 依赖父快照 | 空任务文案 | 编辑 Sheet | upsert 更新 | 保留旧任务 |
| 场景绑定 | 读取绑定 | “未设置” | 添加/编辑 Sheet | `onPersist` 更新 | 不改变旧绑定 |

### 13.16 UI 与代码验收清单

1. 每个入口行都能进入对应真实 View；未启用功能不在当前 UI 出现。
2. 每个保存按钮都有禁用条件、成功退出和失败保留草稿行为。
3. Provider、模型、小任务、场景绑定的修改都能回到 `AISettingsViewModel.snapshot` 并按当前路径持久化。
4. API Key 使用密文输入；日志、错误弹窗和摘要不得展示明文。
5. Provider 禁用后关联云模型不进入场景 bundle；模型禁用后场景候选同步减少。
6. 默认模型配置只允许选择当前 bundle 中存在的模型；没有模型时显示配置引导。
7. 新增、删除、编辑模型后不得产生悬挂场景绑定或 Agent 关联。
8. 删除小任务后，引用其 code 的 Agent/场景绑定要清理或明确阻断。
9. Pro 申请的 `none`、`pending`、`rejected`、`expired`、`active` 五态均有对应 UI，不把提交成功误显示为 active。
10. UI 自动化至少覆盖：新增自定义 Provider、Provider 开关、API 测试、添加在线模型、默认场景切换、新增小任务、删除小任务、删除场景绑定。

### 13.17 截图设计与当前实现差异

| 项目 | 截图方向 | 当前代码事实 | 处理要求 |
| --- | --- | --- | --- |
| 容器 | 白色圆角卡片分组 | `List`/`Form`/`Section` | 视觉重构保持 Section 语义和可访问性 |
| 导航标题 | 大号左对齐或居中 | 主要是系统 `navigationTitle` | 只调整样式，不改变页面层级 |
| 保存 | 顶部胶囊按钮 | toolbar confirmation item | 保持 disabled 条件和副作用 |
| 模型能力 | 图标、彩色标签、右侧开关 | `ModelsSettingsMainRow` 和能力字段 | 不隐藏启用、价格、Provider 来源 |
| 搜索 | 底部浮动搜索胶囊 | SwiftUI `.searchable` | 可替换样式，但保留可访问搜索入口 |
| API 测试 | 卡片内测试入口 | Provider 编辑 Section | 保持测试模型筛选、加载、成功、失败四态 |
| 默认模型 | 按场景卡片 | `Form` 的场景 Section | 仍需区分 localKey 与 trial source |

本节是 AI 设置场景配置模块的 UI 设计基线。新增页面、字段、按钮或交互时，必须同步补充导航树、Plain text UI 草图、组件行为表和状态矩阵，并在对应 SwiftUI View 与 `AISettingsViewModel` 中确认实现位置后再标记为“已实现”。

## 十四、截图补充维护：模型、默认配置、智能体与小任务

本节根据本轮新增截图补充深色模式下的页面结构。截图中的黑色背景、深灰分组、白色主文字、灰色辅助文字、蓝色强调色和绿色启用开关，作为本模块的深色视觉基线；页面行为仍以当前 SwiftUI 实现为准。

### 14.1 深色模式视觉令牌

| 令牌 | 设计值/语义 | 使用位置 |
| --- | --- | --- |
| 页面背景 | `#000000` 或系统 `systemBackground` 深色态 | 页面根背景 |
| 分组背景 | `#1C1C1E` 附近 | 表单卡片、模型卡片、Prompt 容器 |
| 分组分隔线 | `#3A3A3C` 附近 | 卡片内部行分隔 |
| 主文字 | 白色/高对比度 | 标题、名称、主要按钮 |
| 辅助文字 | `secondary` | 说明、模型原始名、数量、状态 |
| 强调色 | 系统蓝色 | 图标、链接、导航、能力入口 |
| 启用色 | 模型页蓝色；编辑能力页可使用绿色 | Toggle 开启态 |
| 禁用色 | 深灰轨道 + 白色圆点 | Toggle 关闭态 |

实现要求：优先使用 SwiftUI 的语义颜色（`.primary`、`.secondary`、`.tint`、`.background`），避免在代码中硬编码只适用于截图的黑色。圆角卡片必须保持稳定内边距，长模型名和长 Prompt 不得遮挡操作按钮。

### 14.2 截图一：编辑小任务

对应代码：`SmallTaskEditorView`、`PromptInputEditorView`、`ModelIconPickerSheet`、`GroupedToolSelectionView`。

```text
┌──────────────────────────────────────┐
│ 取消                               保存│
│                                      │
│ 编辑小任务                           │
│                                      │
│ 图标选择                             │
│                 [  ✓☷  ]             │
│                                      │
│ 基础信息                             │
│ ┌──────────────────────────────────┐ │
│ │ 名称                             │ │
│ │ ──────────────────────────────── │ │
│ │ 简介                             │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Prompt                               │
│ ┌──────────────────────────────────┐ │
│ │                                  │ │
│ │                         输入工具 🎙⌃│ │
│ │ 在系统提示词中追加当前日期   [ ○ ]│ │
│ └──────────────────────────────────┘ │
│                                      │
│ 工具                                 │
│ ┌──────────────────────────────────┐ │
│ │ 工具                       未设置 ›│ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

| 组件 | 点击后的效果 | 保存条件/数据 |
| --- | --- | --- |
| 取消 | 关闭编辑 Sheet，不调用 `onSave` | 草稿丢弃 |
| 保存 | 调用 `save()`，构造 `SmallTask.createLocalTask` 后关闭 | `name` 和 `prompt` 去除空白后均非空 |
| 图标按钮 | 打开 `ModelIconPickerSheet`，选择 SF Symbol 回填 `icon` | 默认 `checklist` |
| 名称 | 编辑任务显示名 | 必填 |
| 简介 | 编辑列表副标题 | 可选；为空时列表显示 code |
| Prompt 编辑器 | 编辑 Prompt；底部显示输入工具、语音入口、展开/收起入口和追加日期开关 | Prompt 是任务执行的核心输入 |
| 输入工具 | 打开 `SparkPromptInputDrawerSheet`，支持翻译/OCR 等工具 | 工具异常不得清空当前 Prompt |
| 麦克风 | 打开 `SparkVoiceInputSheet`，语音结果回填 Prompt | 取消录音不修改已有文本 |
| 追加当前日期 | 仅改变 Prompt 编辑器对应开关/草稿语义 | 需明确最终写入的是 Prompt 还是执行时动态变量 |
| 工具行 | 推入 `GroupedToolSelectionView`，多选工具并返回数量摘要 | 选择结果写入 `toolList` |

当前代码已经实现图标、名称、简介、Prompt 和工具选择；截图中的“追加当前日期”视觉控件需要确认是否已经由 `PromptInputEditorView` 完整持久化，若没有，应在验收中标为待实现，不得只补一个 Toggle 外观。

### 14.3 截图二：默认模型配置

对应代码：`AIModelPreferencesView`、`ScenarioModelPreferencesViewModel`、`AIScenario`。

截图展示了按模型能力分类的配置卡片：对话、向量模型、语音模型。代码中的 `AIScenario` 当前包含 `chat`、`embedding`、`voice` 以及医疗结构化、报告解读、营养等更多业务场景，因此“分类卡片”属于 UI 分组层，不应删减底层场景枚举。

```text
┌──────────────────────────────────────┐
│ ‹              默认模型配置           │
├──────────────────────────────────────┤
│ 对话                                 │
│ ┌──────────────────────────────────┐ │
│ │              [对话图标]           │ │
│ │ 对话模型用于日常问答、内容生成与多轮│ │
│ │ 对话。                            │ │
│ │ ───────────────────────────────── │ │
│ │       本地模型       Pro 模型      │ │
│ │ ───────────────────────────────── │ │
│ │ 场景模型              Doubao ˅     │ │
│ │ ───────────────────────────────── │ │
│ │ ◉ Doubao Seed 1.6                 │ │
│ │   doubao-seed-1-6                 │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 向量模型                             │
│ ┌──────────────────────────────────┐ │
│ │              [向量图标]            │ │
│ │ 向量模型用于知识索引、相似度检索与│ │
│ │ 语义召回。                        │ │
│ │       本地模型       Pro 模型      │ │
│ │ 暂无可用模型：请配置 API Key 或模型│ │
│ └──────────────────────────────────┘ │
│                                      │
│ 语音模型                             │
│ ┌──────────────────────────────────┐ │
│ │              [语音图标]            │ │
│ │ 语音模型用于文本转语音与语音播报。 │ │
│ │       本地模型       Pro 模型      │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

| 组件 | 点击后的效果 |
| --- | --- |
| 返回 | 返回 AI 设置首页，不改动未提交的页面状态 |
| 搜索场景 | 当前代码的 `.searchable` 过滤 `AIScenario.allCases`；深色卡片布局必须保留搜索入口 |
| 场景分类标题 | 只读分组标题；由场景的 `localizedTitle` 和设计分组映射生成 |
| 场景图标 | 只读说明图标，使用 `scenario.introIconSystemName` |
| 本地模型/Pro 模型 segmented control | 写入 `AIModelSelectionSource.localKey` 或 `.trial`，随后切换当前 bundle |
| 场景模型 Picker | 从当前 bundle 的模型中选择；选择结果调用 `setSelectedModel` |
| 模型摘要行 | 显示厂商图标、展示名和原始模型名，原始名支持复制 |
| 无模型状态 | 显示“请配置 Key/模型”，不展示假的下拉选择 |

验收要求：本地/Pro 切换只改变当前场景的来源，不得把本地模型配置覆盖成 Pro 配置；没有 Pro bundle 时不显示 Pro 切换控件。

### 14.4 截图三：新建智能体

对应代码：`ModelsSettingsAgentSheet`。截图中的“智能体名称”“图标选择”“智能体设定”“基座模型”“关联小任务”等字段，均能在该 View 找到对应状态。

```text
┌──────────────────────────────────────┐
│ 取消                             创建 │
│                                      │
│ 新建智能体                           │
│                                      │
│ 图标选择                             │
│                 [  stethoscope  ]    │
│                                      │
│ 基础信息                             │
│ ┌──────────────────────────────────┐ │
│ │ 智能体名称                       │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 智能体设定                           │
│ ┌──────────────────────────────────┐ │
│ │ Prompt                           │ │
│ │                       自动填写 🎙⌃│ │
│ ├──────────────────────────────────┤ │
│ │ 关联小任务                    0 ›│ │
│ └──────────────────────────────────┘ │
│                                      │
│ 基座模型                             │
│ ┌──────────────────────────────────┐ │
│ │ 基座模型             Doubao ˅    │ │
│ │ Doubao Seed 1.6                  │ │
│ │ doubao-seed-1-6  工具 推理       │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 使用场景与工具                       │
│ 使用场景                         0 › │
│ 工具                           全部 ›│
└──────────────────────────────────────┘
```

| 组件 | 点击后的效果 | 必要条件 |
| --- | --- | --- |
| 取消 | `dismiss()` 关闭 Sheet | 不创建 Agent |
| 创建 | 调用 `onCreate`，由 `createLocalAgentAndPersist` 持久化 | 名称、基座模型、系统 Prompt 非空 |
| 图标按钮 | 打开 `ModelIconPickerSheet` | 默认 `stethoscope` |
| 智能体名称 | 编辑 `displayName` | 必填 |
| Prompt 编辑器 | 编辑 `systemPrompt`；支持自动填写、翻译、OCR、语音输入 | 名称为空时自动填写禁用 |
| 自动填写 | 异步调用 `autoFillAgentPrompt(displayName, baseModelName)` | 显示进行中状态；再次点击可恢复原 Prompt |
| 关联小任务 | 推入 `MultiSelectOptionsView`，按 `SmallTask.code` 多选 | 写入 `selectedTaskCodes` |
| 基座模型 Picker | 从可用文本模型中选择 | 仅显示已启用且本地文件存在或有有效 API Key 的模型 |
| 基座模型预览 | 显示模型名、原始名、本地/服务、推理/工具/多模态能力标签 | 只读 |
| 使用场景 | 推入 `ModelScenarioBindingsEditorView`，编辑 Agent 的场景绑定 | 新建 Agent 还未落盘时绑定变更不调用父级持久化回调 |
| 工具 | 推入 `GroupedToolSelectionView`，显示全部或 `n/total` | 写入 `aiToolScenarios` |

### 14.5 截图四：添加在线模型

对应代码：`AddOnlineModelSheet`。截图使用深色卡片布局，字段对应当前代码的 `name`、`displayName`、`selectedProviderID`、`priceTier` 和能力开关。

```text
┌──────────────────────────────────────┐
│ 取消                             添加 │
│                                      │
│ 添加在线模型                         │
│ 基本信息                             │
│ ┌──────────────────────────────────┐ │
│ │ 🔎 系统名称（用于 API 请求）      │ │
│ │ ───────────────────────────────── │ │
│ │ 格式    显示名称（自定义）        │ │
│ │ ───────────────────────────────── │ │
│ │ 🏢 厂商                    302.AI ˅│ │
│ └──────────────────────────────────┘ │
│ 价格                                 │
│ ┌──────────────────────────────────┐ │
│ │ ￥ 价格档位                  免费 ˅│ │
│ └──────────────────────────────────┘ │
│ 能力                                 │
│ ┌──────────────────────────────────┐ │
│ │ 默认隐藏                      ○  │ │
│ │ 自动模型能力探测              ›  │ │
│ │ 注意：探测可能产生 API 费用      │ │
│ │ 支持文本                      ●  │ │
│ │ 支持多模态                    ○  │ │
│ │ 支持推理                      ○  │ │
│ │ 思考可控                      ○  │ │
│ │ 支持工具调用                  ○  │ │
│ │ 支持生图                      ○  │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

- 系统名称为空时显示 API 模型名错误；显示名称为空时显示展示名错误；未选中有效 Provider 时显示厂商错误。
- “自动模型能力探测”显示费用提示，点击后运行探测并打开 `ModelCapabilityProbeSheet`。
- 添加成功后写入 `AllModels`，模型出现在模型目录；失败保持表单草稿。
- 截图中的能力开关必须和 `supportsText`、`supportsMultimodal`、`supportsReasoning`、`reasoningControllable`、`supportsToolUse`、`supportsImageGen` 一一对应。

### 14.6 截图五：编辑模型

对应代码：`EditSparkModelSheet`。模型行的 info 按钮或左滑编辑都会进入该页面；Agent 行则进入 `ModelsSettingsAgentSheet` 编辑模式。

```text
┌──────────────────────────────────────┐
│ 取消                             保存 │
│                                      │
│ 编辑模型                             │
│ 名称                                 │
│ ┌──────────────────────────────────┐ │
│ │ Doubao Seed 1.6                  │ │
│ └──────────────────────────────────┘ │
│ 图标                                 │
│                 [  ◌  ]              │
│                                      │
│ 使用场景与工具                       │
│ ┌──────────────────────────────────┐ │
│ │ 使用场景                    15 › │ │
│ │ 工具                        全部 ›│ │
│ │ 关联小任务                   0 › │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 能力                                 │
│ ┌──────────────────────────────────┐ │
│ │ 支持文本                      ●  │ │
│ │ 支持多模态                    ●  │ │
│ │ 支持推理                      ●  │ │
│ │ 思考可控                      ●  │ │
│ │ 支持工具调用                  ●  │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

| 组件 | 点击后的效果 |
| --- | --- |
| 名称输入 | 编辑 `displayName`，保存时去除首尾空白 |
| 图标按钮 | 打开图标选择器并回填 `iconSymbol` |
| 使用场景 | 推入 `ModelScenarioBindingsEditorView`；显示当前绑定数量 |
| 工具 | 推入工具多选页，更新 `aiToolScenarios` |
| 关联小任务 | 推入多选页，更新 `relatedTaskCodes` |
| 能力开关 | 更新模型能力字段；只有非本地、非系统模型允许编辑能力 |
| 保存 | 调用 `replaceModelAndPersist`；成功后关闭，失败保留页面 |
| 取消 | 关闭 Sheet，不保存当前编辑 |

注意：当前 `EditSparkModelSheet` 代码中“能力”区块位于 `canEditCapabilities == true` 条件内。对本地 GGUF 模型仍可编辑显示名和图标，但不能在 UI 中承诺可以修改云端能力探测结果。

### 14.7 截图六：模型列表

对应代码：`ModelsSettingsView`、`ModelsSettingsMainRow`。

```text
┌──────────────────────────────────────┐
│ ‹    ＋     [全部|模型|智能体]      ☰ │
│                                      │
│ 模型                                 │
│ ┌──────────────────────────────────┐ │
│ │ ◉ Doubao Seed 1.6          ⓘ  ● │ │
│ │   工具   视觉   思考   经济       │ │
│ │ ───────────────────────────────── │ │
│ │ ◉ Doubao Seed 1.6 Lite      ⓘ  ○ │ │
│ │   工具   文本   思考   经济       │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

| 组件 | 当前代码行为 |
| --- | --- |
| 左上角返回 | 返回 AI 设置首页 |
| 加号 Menu | 提供添加在线模型、添加本地模型、添加智能体和高级模型编辑入口 |
| 中间分段 Picker | 在全部、模型、智能体间切换；切换后同步标题和搜索提示 |
| 右上角编辑/完成 | 切换 `isEditing`；编辑态允许拖动排序和删除，完成退出编辑态 |
| 搜索 | 过滤 displayName，包含拼音搜索；只影响显示，不修改数据 |
| 试用模型区 | Pro active 且服务端策略有模型时显示；每行 Toggle 控制 `trialChatPickerDisabledModelNames` |
| 模型行图标 | Agent 使用 `iconSymbol`；普通模型使用 Provider 图标 |
| 能力标签 | 根据 `supportsToolUse`、`supportsMultimodal`、`supportsText`、`supportsImageGen`、`supportsVoiceGen`、`supportsReasoning` 渲染 |
| info 按钮 | 普通模型打开 `EditSparkModelSheet`；Agent 打开 Agent 编辑 Sheet |
| 右侧 Toggle | 开启前检查有效 API Key；没有 Key 时显示错误提示并不改变开关 |
| 左滑编辑 | 打开对应编辑页面 |
| 右滑删除 | 执行模型删除；上层负责清理关联场景绑定/Agent 配置 |

截图中的 `☰` 对应当前代码的编辑入口图标 `line.3.horizontal`；视觉实现可以换成更明确的编辑/排序图标，但必须保留 `isEditing` 的行为。截图中的蓝色开关必须对应 `model.isHidden == false`，不能只做静态装饰。

### 14.8 本轮截图新增验收项

1. 深色模式下所有页面的页面背景、分组背景、分隔线、主文字和辅助文字有稳定层级，不能出现白色 Form 默认背景穿透。
2. 编辑小任务页面的图标、名称、简介、Prompt、输入工具、语音和工具选择均可操作；保存按钮遵守名称和 Prompt 必填规则。
3. 默认模型配置至少能展示对话、向量、语音三个能力分类，并与 `chat`、`embedding`、`voice` 场景绑定；其他医疗场景继续由 `AIScenario.allCases` 生成。
4. 新建智能体必须能够选择有效基座模型、填写系统 Prompt、关联小任务、选择工具和场景，并在名称、基座模型、Prompt 缺失时禁用创建。
5. 添加在线模型必须完成系统名、显示名、Provider 校验；自动能力探测有加载、结果、失败三态和费用提示。
6. 编辑模型必须区分普通模型和 Agent：普通模型进入 `EditSparkModelSheet`，Agent 进入 `ModelsSettingsAgentSheet`。
7. 模型列表的全部/模型/智能体筛选、搜索、编辑排序、信息入口、显隐 Toggle、侧滑编辑/删除均可工作。
8. 对没有有效 API Key 的云端模型，打开显隐开关必须阻止启用并给出明确提示。
9. 所有深色页面的长名称、长 Prompt、长模型原始名都不能遮挡右侧操作或突破卡片边界。
