# AISETTINGS-000002 AI 场景配置授权管理设置菜单需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | AISETTINGS-000002 |
| 工单类型 | P1 AI 设置 / 工具授权管理 / 模型出境授权 / 工具详情 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `Features/AISettings`、`Core/AIRuntime/ToolHub`、`Features/Chat/Presentation/ToolInteraction` |
| 创建日期 | 2026-08-13 |
| 入口路径 | AI 设置 -> 场景配置 -> 授权设置 |
| 关联工单 | `CHAT-000012`、`CHAT-000017`、`DEEPTUTORCHAT-000052` |
| 明确非目标 | 本工单不实现代码；不新增具体工具能力；不改变系统级权限申请流程；不直接调整模型推理协议 |

## 1. 背景与现状

当前 Chat 工具调用已经存在“模型出境授权 / 将工具结果发送至 AI”的二次确认机制。其目标是：工具在本地执行完成后，如果结果包含健康、位置、天气等敏感信息，需要在发送给远端模型前获得用户确认。

现有能力覆盖了运行时弹窗 / 内联卡片确认，但缺少统一的设置管理入口：

1. 用户只能在触发工具时被动处理授权，无法提前查看哪些工具会请求授权。
2. 已经点过“允许并不再询问此工具”的记录只在本地存储中生效，没有可视化管理页。
3. 缺少“永久拒绝”“下次询问”“始终运行”的显式策略配置。
4. 用户看不到每个授权项涉及哪些数据、哪些工具、数据会发给哪个模型供应商。
5. 授权项无法跳转到相关工具详情页，导致数据来源、工具能力和授权边界割裂。

本工单目标是在 AI 场景配置中新增“授权设置”菜单，把运行时授权沉淀为可查看、可解释、可配置、可撤销的管理能力。

## 2. 关键代码位置

### 2.1 当前模型出境授权链路

| 文件 | 当前职责 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift` | `executeToolCall` 执行工具后调用 `applyModelEgressConsentIfNeeded`，决定是否需要模型出境授权 |
| `SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Consent.swift` | 模型出境授权主逻辑：请求用户确认、拒绝时返回 `ConsentGate` 提示 |
| `SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Consent/ToolConsentPermissionStore.swift` | 当前“始终允许此工具”的本地存储；以工具名为粒度持久化 |
| `SparkClient/SparkClient/Projects/Core/AIRuntime/ConsentPayloadBuilder.swift` | 将工具结果、调用参数、供应商、模型、endpoint 组装为授权弹窗 payload |
| `SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Consent/ToolConsentPresentationModels.swift` | 授权展示模型，包括工具名、友好标题、参数文本、结果文本 |
| `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionCoordinator.swift` | 工具交互协调入口，负责授权卡片 / Sheet 的排队、回调与 continuation |
| `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/Sheets/ExternalToolDataConsentSheet.swift` | 当前 Sheet 形态授权 UI |
| `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ToolInteraction/ChatToolInteractionMessageCards.swift` | 当前消息内授权卡片 UI |

### 2.2 当前受控工具范围

当前 `ToolConsentPermissionStore.swift` 中的模型出境授权策略已经覆盖以下工具：

| 工具 | 数据类型 | 授权原因 |
| --- | --- | --- |
| `fetch_step_details` | Apple 健康步数明细 | 健康敏感数据 |
| `fetch_energy_details` | Apple 健康能量消耗 | 健康敏感数据 |
| `fetch_nutrition_details` | 营养摄入明细 | 健康敏感数据 |
| `fetch_sleep_details` | 睡眠明细 | 健康敏感数据 |
| `fetch_workout_details` | 运动训练明细 | 健康敏感数据 |
| `query_weather` | 经纬度关联天气结果 | 位置相关数据 |
| `query_location` | 地点解析结果 | 位置相关数据 |
| `get_current_location` | 当前经纬度 | 位置敏感数据 |

注意：当前策略类型命名为 `AppleHealthToolConsentPolicy`，但实际已经覆盖天气与位置工具。后续实现建议重命名为更通用的 `ToolModelEgressConsentPolicy` 或新增一层通用策略包装。

### 2.3 AI 设置入口现状

| 文件 | 当前职责 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` | AI 设置主入口，已有模型、工具、小任务、天气查询等入口 |
| `SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift` | AI 设置页状态、保存和配置刷新 |
| `SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` | AI 设置相关偏好模型，包括工具交互展示方式 |
| `SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift` | AI 设置快照，负责持久化配置聚合 |

## 3. 需求目标

1. 在 AI 场景配置中新增“授权设置”菜单入口。
2. 新增授权管理列表，展示所有受模型出境授权策略控制的工具。
3. 列表每个授权项以卡片展示，包含工具名称、数据类型、当前策略、最近触发时间、关联模型 / 供应商摘要。
4. 点击授权卡片进入授权详情页。
5. 详情页解释该授权会涉及哪些数据、为什么需要发送给 AI、发送给哪个模型供应商、拒绝后的影响。
6. 每个授权项支持配置三种策略：永久拒绝、下次询问、始终运行。
7. 提供通用默认策略配置，用于新工具或未单独配置的工具。
8. 授权详情页展示数据来源相关联的工具，并支持点击进入工具详情页。
9. 授权设置必须和运行时授权弹窗共用同一套策略，不允许出现设置页显示允许但运行时仍频繁弹窗的状态漂移。

## 4. 产品结构

### 4.1 新增入口

建议在 AI 设置的“工具”或“场景配置”区域新增：

```text
AI 设置
  -> 场景配置
      -> 授权设置
```

入口行建议信息：

| 字段 | 建议内容 |
| --- | --- |
| 标题 | 授权设置 |
| 副标题 | 管理工具结果发送给 AI 前的确认策略 |
| 图标 | `shield.checkered` 或 `lock.shield` |
| 状态摘要 | `3 个始终运行，1 个永久拒绝` |

如果当前 AI 设置页尚未有明确“场景配置”二级页，可以先放在 `AISettingsView` 的工具配置 Section 下，并在文案中保持“授权设置”语义。

### 4.2 授权管理列表

授权管理列表展示两类内容：

1. 通用授权策略卡片。
2. 工具级授权卡片列表。

页面结构：

```text
授权设置
  通用策略
    默认处理方式：下次询问 / 始终运行 / 永久拒绝

  工具授权
    获取当前位置
    查询天气
    查询地点
    睡眠明细
    步数明细
    ...
```

工具授权卡片字段：

| 字段 | 说明 |
| --- | --- |
| 工具显示名 | 例如“获取当前位置” |
| 工具 API 名 | 例如 `get_current_location` |
| 数据类型 | 位置、天气、健康、营养、运动等 |
| 当前策略 | 永久拒绝 / 下次询问 / 始终运行 |
| 数据去向 | 当前默认模型供应商，例如 `DOUBAO`；未知时显示“按当前 AI 模型配置” |
| 最近使用 | 最近一次工具触发时间；没有记录时显示“尚未使用” |
| 风险提示 | 对高敏感工具显示“包含当前位置”“包含健康明细”等短标签 |

### 4.3 授权详情页

点击卡片进入授权详情页：

```text
授权设置
  -> 获取当前位置
      -> 授权策略
      -> 将发送的数据
      -> 使用场景
      -> 关联工具
      -> 最近记录
```

详情页必须解释：

1. 该工具会读取什么数据。
2. 哪些数据会发送给 AI。
3. 为什么模型需要这些数据。
4. 用户拒绝后会发生什么。
5. 当前策略是否只对本工具生效。
6. 当前策略是否跟随账号、设备或本地存储。

示例说明文案：

```text
获取当前位置会在本地读取当前经纬度。允许发送后，经纬度会作为工具结果进入模型上下文，用于继续回答天气、附近服务或位置相关问题。

如果选择不允许，AI 只会收到“用户未授权发送位置结果”的提示，不会收到具体经纬度。
```

### 4.4 策略配置

每个授权项支持三种策略：

| 策略 | 语义 | 运行时行为 |
| --- | --- | --- |
| 永久拒绝 | 默认阻止该工具结果发送给 AI | 工具执行后不弹窗，直接返回 `ConsentGate` 拦截提示 |
| 下次询问 | 每次触发时询问用户 | 工具执行后弹出授权卡片 / Sheet，由用户决定本次是否发送 |
| 始终运行 | 默认允许该工具结果发送给 AI | 工具执行后不弹窗，直接把工具结果返回给模型 |

命名说明：

1. “永久拒绝”必须允许用户在设置页改回“下次询问”或“始终运行”，不能设计成不可逆。
2. “始终运行”表示跳过模型出境确认，不表示跳过系统权限。例如位置工具仍然需要 iOS 位置权限。
3. “下次询问”是推荐默认值，尤其适用于健康与位置数据。

### 4.5 通用默认策略

授权设置页需要支持一个通用默认策略，用于没有单独配置的工具：

| 默认策略 | 推荐值 | 说明 |
| --- | --- | --- |
| 新敏感工具默认处理方式 | 下次询问 | 避免新工具上线后默认外发敏感数据 |

工具级策略优先级高于通用策略：

```text
工具级策略存在
  -> 使用工具级策略
工具级策略不存在
  -> 使用通用默认策略
```

设置页需要展示“继承默认策略”的状态，避免用户误以为每个工具都有独立记录。

### 4.6 关联工具详情页

授权详情页需要展示“关联工具”区域：

| 字段 | 说明 |
| --- | --- |
| 工具名称 | 友好名称，例如“获取当前位置” |
| API 名 | `get_current_location` |
| 工具分类 | 位置 / 天气 / 健康 |
| 数据来源 | CoreLocation / WeatherGateway / HealthKit / 医疗档案等 |
| 可点击 | 点击进入工具详情页 |

工具详情页至少展示：

1. 工具用途。
2. 工具入参 schema。
3. 工具输出示例。
4. 是否涉及敏感数据。
5. 是否受模型出境授权控制。
6. 关联的授权策略。

如果项目已经规划工具详情页，本工单只要求授权详情页跳转到该工具详情页；如果没有，则本工单需要新增最小可用工具详情页。

## 5. 数据模型建议

### 5.1 授权策略枚举

建议新增通用枚举：

```swift
nonisolated enum ToolModelEgressConsentMode: String, Codable, CaseIterable, Sendable {
    case alwaysDeny
    case askEveryTime
    case alwaysAllow
}
```

展示文案：

| 枚举 | 中文 |
| --- | --- |
| `alwaysDeny` | 永久拒绝 |
| `askEveryTime` | 下次询问 |
| `alwaysAllow` | 始终运行 |

### 5.2 工具级授权配置

建议新增：

```swift
nonisolated struct ToolModelEgressConsentPreference: Codable, Equatable, Sendable, Identifiable {
    var id: String { toolName }
    var toolName: String
    var mode: ToolModelEgressConsentMode
    var updatedAt: Date
    var lastUsedAt: Date?
    var lastProviderCompany: String?
    var lastModelName: String?
}
```

### 5.3 全局授权配置

建议挂到 AI 设置快照：

```swift
nonisolated struct ToolModelEgressConsentPreferences: Codable, Equatable, Sendable {
    var defaultMode: ToolModelEgressConsentMode
    var toolPreferences: [ToolModelEgressConsentPreference]
}
```

默认值：

```swift
ToolModelEgressConsentPreferences(
    defaultMode: .askEveryTime,
    toolPreferences: []
)
```

### 5.4 持久化落地方案

本工单按全新授权体系设计，不考虑旧版 `spark.tool_consent.allowed_tools.v1` 迁移。上线后所有工具授权从新存储读取；历史“允许并不再询问此工具”不再作为新页面和新策略的输入。

结合当前项目，推荐把授权设置作为账号级 AI 偏好保存，而不是做全局设备级开关：

| 方案 | 结论 | 原因 |
| --- | --- | --- |
| 挂到 `AISettingsSnapshot.PreferencesPayload` | 推荐 | 当前 AI 设置轻量偏好已经由 `DefaultAISettingsRepository` 按 `ownerAccountID` 写入 UserDefaults，和模型、工具、天气、小任务配置同属 AI 设置域 |
| 单独全局 UserDefaults key | 不推荐 | 无法自然按账号隔离，账号切换后容易复用上一账号的敏感授权 |
| Core Data 独立表 | 暂不推荐 | 本期是本机 AI 偏好，不需要查询复杂关系；后续若做服务端同步和审计再升级 |
| 服务端持久化 | 本期不做 | 授权是本设备对“工具结果发给当前模型”的确认，先按本机账号级偏好落地 |

建议新增字段：

```swift
extension AISettingsSnapshot {
    var toolModelEgressConsentPreferences: ToolModelEgressConsentPreferences
}
```

并将该字段纳入：

| 文件 | 落地要求 |
| --- | --- |
| `AISettingsSnapshot.swift` | 新增快照字段、默认值、`PreferencesPayload` 编解码字段 |
| `AISettingsDomainModels.swift` | 放置 `ToolModelEgressConsentMode`、`ToolModelEgressConsentPreference`、`ToolModelEgressConsentPreferences` |
| `DefaultAISettingsRepository.swift` | 随 `preferencesPayload` 按 `ownerAccountID` 保存和读取 |
| `AIConfigCenter.swift` | 暴露当前账号快照读取能力，供运行时策略读取最新授权配置 |
| `AIRuntimeConfigStore.swift` | 缓存快照时同步包含授权偏好，保证运行时和设置页一致 |

### 5.5 UserDefaults key 与账号隔离

不新增散落的全局 key。授权设置跟随现有 AI 设置偏好载荷保存。

当前仓储注释已经说明：

```text
AllModels / APIKeys / SearchKeys / PromptRepo 存 Core Data；其余轻量偏好用 AISettingsSnapshot.PreferencesPayload 存 UserDefaults。
```

因此授权偏好应作为 `PreferencesPayload` 的一个字段，跟随现有账号级 key。实际 key 继续由 `DefaultAISettingsRepository.UserDefaultsKey` 统一管理，不在授权模块内自行拼接。

账号隔离规则：

1. 同一设备上不同登录账号拥有独立授权配置。
2. 退出账号后，不清除该账号授权偏好；下次登录同账号可继续读取。
3. 游客 / 设备账号使用当前项目已有的 ownerAccountID 解析结果，不单独创建匿名全局授权。
4. 运行时没有解析到 ownerAccountID 时，使用内存默认值 `askEveryTime`，并不写入持久化。

### 5.6 工具级配置与默认策略合并

运行时需要有一个纯函数式解析入口，避免 UI 和 ToolHub 各自实现一套判断：

```swift
struct ToolModelEgressConsentResolver {
    func resolve(
        toolName: String,
        preferences: ToolModelEgressConsentPreferences
    ) -> ToolModelEgressConsentMode
}
```

解析规则：

1. 先用标准化后的 `toolName` 查找工具级配置。
2. 找到则返回工具级 `mode`。
3. 找不到则返回 `defaultMode`。
4. 工具名标准化规则必须和当前 `ToolConsentPermissionStore.normalize` 一致：去除首尾空白并转小写。
5. 受控工具清单不应从用户偏好里推导，必须来自代码内的工具描述注册表或策略白名单。

### 5.7 写入时机

| 场景 | 写入内容 |
| --- | --- |
| 用户在授权详情页修改策略 | 更新对应 `ToolModelEgressConsentPreference.mode`、`updatedAt` |
| 用户修改通用默认策略 | 更新 `defaultMode` |
| 运行时点击“允许发送” | 只放行本次，不写工具级持久化 |
| 运行时点击“允许并不再询问此工具” | 写入该工具 `mode = alwaysAllow` |
| 运行时点击“不允许” | 只拒绝本次，不写工具级持久化 |
| 设置页选择“永久拒绝” | 写入该工具 `mode = alwaysDeny` |
| 工具成功触发授权判定 | 可更新 `lastUsedAt`、`lastProviderCompany`、`lastModelName`，但不得记录原始工具结果 |

### 5.8 持久化失败策略

授权策略属于隐私相关配置，失败时必须偏保守：

1. 读取失败：回退 `defaultMode = askEveryTime`。
2. 写入“始终运行”失败：不得在 UI 上显示已成功，运行时仍按旧值或默认询问。
3. 写入“永久拒绝”失败：提示用户保存失败，不应假装已拒绝。
4. 运行时更新 `lastUsedAt` 失败：不影响本次工具回答，但需要写 warning 日志。
5. 解码到未知枚举值：按 `askEveryTime` 处理，并保留可恢复日志。

## 6. 运行时策略

### 6.1 工具执行主流程

目标流程：

```text
模型 tool_call
  -> ToolHub.executeToolCall
  -> execute(invocation)
  -> 得到 rawResult
  -> ToolModelEgressConsentPolicy.evaluate(result, context)
      -> alwaysAllow: 直接返回 rawResult 给模型
      -> askEveryTime: 展示授权卡片 / Sheet
      -> alwaysDeny: 返回 ConsentGate 拦截提示
  -> appendAudit
  -> 模型继续生成
```

### 6.2 和系统权限的边界

模型出境授权不替代系统权限：

| 权限类型 | 示例 | 负责内容 |
| --- | --- | --- |
| 系统权限 | iOS 位置权限、HealthKit 权限 | App 是否可以读取本机数据 |
| 模型出境授权 | 将工具结果发送至 AI | App 是否可以把读取结果发送给模型 |

例如 `get_current_location`：

```text
系统位置权限允许
  -> App 可以读取经纬度
模型出境授权允许
  -> 经纬度可以进入模型上下文
```

任一层拒绝都不能把真实经纬度发送给模型。

### 6.3 拒绝时返回内容

永久拒绝或本次拒绝时，模型只能收到通用提示，不得收到原始工具结果。

建议沿用当前 `PromptLocalizer.consentBlockedHint`：

```text
[ConsentGate] 用户未授权将该工具结果发送给第三方模型。
```

如果工具结果已经生成富内容卡片，UI 可以展示本地结果摘要，但必须明确该摘要没有发送给模型。

## 7. UI 与交互要求

### 7.1 授权列表状态

列表需要区分以下状态：

| 状态 | 展示 |
| --- | --- |
| 继承默认 | 标签显示“下次询问（默认）” |
| 单独始终运行 | 标签显示“始终运行” |
| 单独永久拒绝 | 标签显示“永久拒绝” |
| 单独下次询问 | 标签显示“下次询问” |

### 7.2 详情页策略切换

详情页推荐使用单选列表或分段控件：

```text
授权策略
  永久拒绝
  下次询问
  始终运行
```

切换到“始终运行”时需要展示一次轻量确认：

```text
开启后，该工具结果会直接发送给当前使用的 AI 模型，不再每次询问。
```

切换到“永久拒绝”时需要说明：

```text
开启后，该工具结果不会发送给 AI。AI 可能需要改为询问你补充城市、时间范围或其他非敏感信息。
```

### 7.3 授权卡片复用

运行时授权卡片和设置页授权详情应共用同一份展示模型或至少共用同一份数据解释源，避免文案不一致。

建议把当前 `ConsentPayloadBuilder` 拆分为两层：

1. `ToolConsentDescriptorProvider`：静态解释工具会访问哪些数据、为什么需要授权。
2. `ConsentPayloadBuilder`：运行时补充本次参数、结果、供应商、模型和 endpoint。

## 8. 埋点与审计

建议新增客户端日志：

| 事件 | 触发时机 | 字段 |
| --- | --- | --- |
| `ai_settings.tool_consent.list.open` | 打开授权设置列表 | `accountID`、`defaultMode` |
| `ai_settings.tool_consent.detail.open` | 打开授权详情 | `toolName`、`mode` |
| `ai_settings.tool_consent.mode.change` | 修改工具授权策略 | `toolName`、`oldMode`、`newMode` |
| `ai_settings.tool_consent.default.change` | 修改默认策略 | `oldMode`、`newMode` |
| `tool_consent.runtime.evaluate` | 运行时判定授权策略 | `toolName`、`mode`、`providerCompany`、`modelName` |
| `tool_consent.runtime.blocked` | 运行时阻止发送 | `toolName`、`reason` |

审计注意：

1. 日志不记录原始经纬度、健康数值、报告文本。
2. 可以记录工具名、策略、供应商、模型和是否发送。
3. 如果记录 payload 长度，只记录字符数，不记录原文。

## 9. 验收标准

### 9.1 设置入口

1. AI 场景配置中能看到“授权设置”入口。
2. 点击入口进入授权管理列表。
3. 列表展示通用默认策略和当前受控工具。

### 9.2 授权列表

1. 每个工具卡片展示工具名、API 名、数据类型、当前策略。
2. 已配置工具和继承默认策略工具有清晰视觉区分。
3. 点击卡片能进入详情页。

### 9.3 授权详情

1. 详情页能说明该授权会涉及哪些数据。
2. 详情页能展示关联工具。
3. 点击关联工具能进入工具详情页。
4. 详情页可修改策略为永久拒绝、下次询问、始终运行。

### 9.4 运行时策略

1. `下次询问`：工具执行后继续弹出当前授权卡片 / Sheet。
2. `始终运行`：工具执行后不弹授权确认，结果直接返回给模型。
3. `永久拒绝`：工具执行后不弹授权确认，模型只收到 `ConsentGate` 拦截提示。
4. 位置系统权限未授权时，即使工具策略是 `始终运行`，也不能绕过 iOS 权限读取位置。
5. 本地模型或 providerCompany 为 `LOCAL` 时，保持无需模型出境授权。

### 9.5 全新持久化

1. 新授权设置不读取、不迁移旧版 `spark.tool_consent.allowed_tools.v1`。
2. 首次进入授权设置时，所有工具默认继承通用策略 `askEveryTime`。
3. 修改工具级策略后，退出并重新进入 AI 设置，策略仍保持一致。
4. 切换账号后，不复用其他账号的授权策略。
5. 无 ownerAccountID 时，运行时默认按 `askEveryTime` 处理，并不写入持久化。

## 10. 风险与注意事项

1. 当前授权记忆只按工具名，不按供应商 / 模型区分。新增设置时需要明确是否继续按工具粒度，还是升级为工具 + provider 粒度。
2. “始终运行”容易被误解为自动调用工具。文案必须说明它只表示“工具结果发送给 AI 时不再询问”。
3. “永久拒绝”不能阻止工具本地执行，除非后续另做“工具运行授权”。本工单只控制模型出境。
4. 授权详情展示本次参数 / 结果时要注意敏感信息脱敏，设置页默认不应展示历史原始结果。
5. 如果通用默认策略设置为“始终运行”，需要强提示其影响所有未单独配置的敏感工具。

## 11. 推荐实现拆分

### 阶段一：设置页只读展示

1. 新增授权设置入口。
2. 新增授权列表与详情页。
3. 读取当前受控工具清单。
4. 暂不改变运行时策略。

### 阶段二：账号级三态策略落库

1. 新增 `ToolModelEgressConsentMode`。
2. 新增 `ToolModelEgressConsentPreferences` 并挂入 `AISettingsSnapshot.PreferencesPayload`。
3. 通过 `DefaultAISettingsRepository` 随 ownerAccountID 持久化。
4. 设置页可修改默认策略和工具级策略。
5. 不读取、不迁移旧版 `spark.tool_consent.allowed_tools.v1`。

### 阶段三：运行时接入

1. 将 `AppleHealthToolConsentPolicy` 收口为通用模型出境授权策略。
2. `applyModelEgressConsentIfNeeded` 接入三态策略。
3. 完成 `alwaysDeny`、`askEveryTime`、`alwaysAllow` 三种行为。
4. 保持当前授权卡片 / Sheet 的交互能力。

### 阶段四：工具详情联动

1. 建立工具描述注册表。
2. 授权详情页展示关联工具。
3. 点击进入工具详情页。
4. 工具详情页反向展示当前授权策略入口。
