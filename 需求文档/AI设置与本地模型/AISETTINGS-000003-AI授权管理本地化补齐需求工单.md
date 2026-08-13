# AISETTINGS-000003 AI 授权管理本地化补齐需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | AISETTINGS-000003 |
| 工单类型 | P1 AI 设置 / 授权管理 / 本地化 / 文案治理 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `Features/AISettings`、`Core/AIRuntime/ToolHub/Consent`、`Projects/App/Resources` |
| 创建日期 | 2026-08-14 |
| 关联工单 | `AISETTINGS-000002` |
| 明确非目标 | 不改变授权策略语义；不调整默认授权值；不改变工具调用流程；不新增工具能力 |

## 1. 背景与问题

`AISETTINGS-000002` 已新增 AI 授权管理设置入口、授权列表、授权详情页和工具详情页授权区。当前实现中，部分新增 UI 文案、授权说明文案和运行时拦截原因仍直接写在 Swift 代码中，未进入 `Localizable.strings`。

这会导致：

1. 英文环境、繁体中文环境无法获得对应文案。
2. 授权说明这种敏感合规文案无法统一审校。
3. 后续产品调整文案时需要改 Swift 代码，增加回归风险。
4. `ToolModelEgressConsentDescriptor` 中的数据范围、数据来源、拒绝影响等文案无法按语言精确表达。

本工单目标是补齐授权管理相关本地化键值，并收口新增授权文案的命名空间和资源文件。

## 2. 当前资源现状

| 资源文件 | 当前状态 | 处理要求 |
| --- | --- | --- |
| `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | 存在 | 补齐简体中文授权文案 |
| `SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | 存在 | 补齐英文授权文案 |
| `SparkClient/Projects/App/Resources/zh-Hant.lproj/Localizable.strings` | 缺失 | 新增繁体中文 Localizable 资源或按项目约定补齐 |
| `InfoPlist.strings` / `Prompts.strings` / `ToolPrompts.strings` | 非本工单主目标 | 不承载授权管理 UI 文案 |

## 3. 未本地化检查结果

### 3.1 已使用 `L10n.text` 但资源键未补齐

| 文件 | 文案 / key | 问题 |
| --- | --- | --- |
| `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` | `ai_settings.row.tool_consent` | 入口标题只有 fallback，需要写入资源 |
| `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` | `ai_settings.row.tool_consent.subtitle` | 入口副标题只有 fallback，需要写入资源 |
| `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` | `ai_settings.tool_consent.mode.*` | 模式文案已有 key，但需要确认 `zh-Hans`、`en`、`zh-Hant` 都有值 |

### 3.2 授权管理页硬编码文案

文件：`SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIToolConsentSettingsView.swift`

| 区域 | 当前硬编码文案 | 本地化要求 |
| --- | --- | --- |
| 页头 | `发送给 AI 授权` | 提取为 `ai_settings.tool_consent.title` |
| 页头说明 | `管理工具结果在发送给模型前的授权策略...` | 提取为说明文案 key |
| Section | `通用设置`、`授权管理` | 提取为 section key |
| Footer | `仅对会把敏感工具结果发送给远端模型的场景生效...` | 提取为 footer key |
| 状态 | `跟随通用策略`、`单独配置`、`跟随通用` | 提取为状态 key |
| Picker | `发送给 AI`、`跟随通用策略（...）` | 提取为 picker key 和 format key |
| 操作 | `恢复跟随通用策略` | 提取为 action key |
| 详情 Section | `将会授权的数据`、`数据来源`、`为什么需要发送给 AI`、`拒绝后的影响` | 提取为 detail section key |
| 最近记录 | `最近使用`、`模型厂商`、`模型名称`、`最近发送`、`配置更新时间` | 提取为 metadata key |
| 列表摘要 | `当前继承默认策略：...`、`最近发送：...` | 提取为 format key |
| 分类判断 | `位置`、`天气`、`健康` | 分类展示值需要来自 descriptor 的本地化分类 key，不能用中文字符串参与 UI 判断 |

### 3.3 工具详情授权区硬编码文案

文件：`SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIToolSettingsView.swift`

| 区域 | 当前硬编码文案 | 本地化要求 |
| --- | --- | --- |
| 状态 | `当前跟随通用策略`、`当前为单独配置` | 提取为工具详情状态 key |
| Section | `发送给 AI 授权` | 复用授权标题 key |
| CTA | `查看授权数据范围、来源和默认策略` | 提取为 link hint key |
| Footer | `该工具结果可能包含敏感位置或健康数据...` | 提取为 footer key |

### 3.4 授权策略描述模型硬编码文案

文件：`SparkClient/Projects/Core/AIRuntime/ToolHub/Consent/ToolConsentPermissionStore.swift`

| 类型 | 当前硬编码内容 | 本地化要求 |
| --- | --- | --- |
| 拒绝原因 | `用户已将该工具配置为永久拒绝发送到 AI。` | 提取为 runtime key |
| 分类 | `位置`、`天气`、`健康` | 改为 category key 或 category enum |
| 工具摘要 | `将当前位置作为模型上下文输入...` 等 | 每个受控工具提取独立 summary key |
| 数据项 | `当前经纬度`、`温度、体感、天气状态` 等 | 每个工具的数据行提取数组式 key |
| 发送原因 | `模型需要当前位置结果...` 等 | 每个工具提取 why key |
| 拒绝影响 | `拒绝后，AI 只能...` 等 | 每个工具提取 deny impact key |
| 数据来源 | `当前位置工具结果`、`天气厂商工具结果`、`HealthKit ... 数据` | 提取为 source line key |

说明：`CoreLocation`、`WeatherGateway`、`HealthKit` 属于技术名词，可保留英文，但承载业务含义的“当前位置工具结果”“天气厂商工具结果”等仍需要本地化。

## 4. 需求目标

1. 授权管理新增文案全部使用 `L10n.text` 或项目已有本地化方式。
2. 授权模式、授权入口、授权列表、授权详情、工具详情授权区均补齐 `zh-Hans`、`en`、`zh-Hant` 文案。
3. `ToolModelEgressConsentDescriptor` 不再直接持有已翻译中文文案，改为持有本地化 key 或通过本地化构造器生成展示文案。
4. 不使用中文展示文本作为逻辑判断条件，例如不能通过 `categoryTitle == "位置"` 判断图标和颜色。
5. 运行时返回给模型或展示给用户的授权拒绝原因需要本地化。
6. 保持 `AISETTINGS-000002` 已实现的授权策略和默认值不变。

## 5. 建议实现方案

### 5.1 key 命名空间

建议统一使用：

```text
ai_settings.tool_consent.*
```

推荐分层：

| key 前缀 | 用途 |
| --- | --- |
| `ai_settings.tool_consent.mode.*` | 永久拒绝 / 下次询问 / 始终运行 |
| `ai_settings.tool_consent.list.*` | 授权列表页 |
| `ai_settings.tool_consent.detail.*` | 授权详情页 |
| `ai_settings.tool_consent.tool_detail.*` | AI 工具详情页授权区 |
| `ai_settings.tool_consent.category.*` | 位置 / 天气 / 健康 |
| `ai_settings.tool_consent.descriptor.<tool>.*` | 单工具说明 |
| `ai_settings.tool_consent.runtime.*` | 运行时拦截提示 |

### 5.2 descriptor 结构调整

当前 `ToolModelEgressConsentDescriptor` 直接保存展示文案。建议调整为保存稳定语义：

```swift
nonisolated enum ToolModelEgressConsentCategory: String, Codable, Sendable {
    case location
    case weather
    case health
}
```

`ToolModelEgressConsentDescriptor` 建议字段：

```swift
let toolName: String
let category: ToolModelEgressConsentCategory
let localizationKeyPrefix: String
let relatedToolNames: [String]
```

展示层通过 key prefix 读取：

```swift
summary = L10n.text("\(prefix).summary")
dataLines = L10n.array("\(prefix).data_lines")
whyItNeedsAI = L10n.text("\(prefix).why")
denyImpact = L10n.text("\(prefix).deny_impact")
dataSourceLines = L10n.array("\(prefix).data_sources")
```

如果当前没有 `L10n.array`，可先使用编号 key：

```text
ai_settings.tool_consent.descriptor.get_current_location.data.1
ai_settings.tool_consent.descriptor.get_current_location.data.2
ai_settings.tool_consent.descriptor.get_current_location.data.3
```

### 5.3 图标和颜色逻辑

当前授权卡片通过中文分类判断：

```swift
case "位置":
case "天气":
case "健康":
```

需要改为枚举判断：

```swift
switch descriptor.category {
case .location:
case .weather:
case .health:
}
```

这样切换语言后图标、颜色不受展示文案影响。

### 5.4 资源文件要求

必须补齐：

1. `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings`
2. `SparkClient/Projects/App/Resources/en.lproj/Localizable.strings`
3. `SparkClient/Projects/App/Resources/zh-Hant.lproj/Localizable.strings`

如果 `zh-Hant.lproj/Localizable.strings` 当前不存在，需要新增并确保 Xcode target 包含该资源。项目如果通过 file system synchronized group 管理资源，新增文件后仍需要本地构建验证。

## 6. 文案清单

### 6.1 页面入口

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `ai_settings.row.tool_consent` | 授权管理 | Authorization Management | 授權管理 |
| `ai_settings.row.tool_consent.subtitle` | 管理工具结果发送给 AI 前的确认策略 | Manage confirmation rules before tool results are sent to AI | 管理工具結果傳送給 AI 前的確認策略 |

### 6.2 模式

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `ai_settings.tool_consent.mode.always_deny` | 永久拒绝 | Always Deny | 永久拒絕 |
| `ai_settings.tool_consent.mode.ask_every_time` | 下次询问 | Ask Every Time | 下次詢問 |
| `ai_settings.tool_consent.mode.always_allow` | 始终运行 | Always Run | 始終執行 |
| `ai_settings.tool_consent.mode.always_deny.short` | 永久拒绝 | Deny | 永久拒絕 |
| `ai_settings.tool_consent.mode.ask_every_time.short` | 下次询问 | Ask | 下次詢問 |
| `ai_settings.tool_consent.mode.always_allow.short` | 始终运行 | Run | 始終執行 |

### 6.3 页面通用文案

| key | zh-Hans |
| --- | --- |
| `ai_settings.tool_consent.title` | 发送给 AI 授权 |
| `ai_settings.tool_consent.intro` | 管理工具结果在发送给模型前的授权策略。你可以统一配置默认行为，也可以对位置、天气、健康等敏感工具逐个设置。 |
| `ai_settings.tool_consent.section.general` | 通用设置 |
| `ai_settings.tool_consent.section.management` | 授权管理 |
| `ai_settings.tool_consent.default_mode` | 默认策略 |
| `ai_settings.tool_consent.default_mode.footer` | 未单独配置的工具将继承这个默认策略。 |
| `ai_settings.tool_consent.remote_only.footer` | 仅对会把敏感工具结果发送给远端模型的场景生效。本地模型默认不弹出这类出境授权。 |
| `ai_settings.tool_consent.follow_default` | 跟随通用策略 |
| `ai_settings.tool_consent.custom` | 单独配置 |
| `ai_settings.tool_consent.follow_default.short` | 跟随通用 |
| `ai_settings.tool_consent.picker.send_to_ai` | 发送给 AI |
| `ai_settings.tool_consent.picker.follow_default_format` | 跟随通用策略（%@） |
| `ai_settings.tool_consent.action.restore_default` | 恢复跟随通用策略 |
| `ai_settings.tool_consent.effective_mode_format` | 当前生效：%@。如果该工具没有单独配置，就会继承通用默认策略。 |
| `ai_settings.tool_consent.inherited_default_format` | 当前继承默认策略：%@ |
| `ai_settings.tool_consent.last_sent_format` | 最近发送：%@ |

英文和繁体中文需由产品或实现阶段按同义完整补齐，不能只保留 fallback。

### 6.4 详情页 section 与元数据

| key | zh-Hans |
| --- | --- |
| `ai_settings.tool_consent.detail.data_to_authorize` | 将会授权的数据 |
| `ai_settings.tool_consent.detail.data_sources` | 数据来源 |
| `ai_settings.tool_consent.detail.why_send_to_ai` | 为什么需要发送给 AI |
| `ai_settings.tool_consent.detail.deny_impact` | 拒绝后的影响 |
| `ai_settings.tool_consent.detail.recent_usage` | 最近使用 |
| `ai_settings.tool_consent.detail.related_tools` | 关联工具 |
| `ai_settings.tool_consent.metadata.provider` | 模型厂商 |
| `ai_settings.tool_consent.metadata.model` | 模型名称 |
| `ai_settings.tool_consent.metadata.last_sent` | 最近发送 |
| `ai_settings.tool_consent.metadata.updated_at` | 配置更新时间 |

### 6.5 工具详情授权区

| key | zh-Hans |
| --- | --- |
| `ai_settings.tool_consent.tool_detail.following_default` | 当前跟随通用策略 |
| `ai_settings.tool_consent.tool_detail.customized` | 当前为单独配置 |
| `ai_settings.tool_consent.tool_detail.link_hint` | 查看授权数据范围、来源和默认策略 |
| `ai_settings.tool_consent.tool_detail.footer` | 该工具结果可能包含敏感位置或健康数据；发送给远端模型前，会根据这里的授权策略决定是否继续。 |

### 6.6 分类

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `ai_settings.tool_consent.category.location` | 位置 | Location | 位置 |
| `ai_settings.tool_consent.category.weather` | 天气 | Weather | 天氣 |
| `ai_settings.tool_consent.category.health` | 健康 | Health | 健康 |

### 6.7 受控工具描述

每个工具至少补齐以下 key：

```text
ai_settings.tool_consent.descriptor.<tool_name>.summary
ai_settings.tool_consent.descriptor.<tool_name>.data.1
ai_settings.tool_consent.descriptor.<tool_name>.data.2
ai_settings.tool_consent.descriptor.<tool_name>.data.3
ai_settings.tool_consent.descriptor.<tool_name>.why
ai_settings.tool_consent.descriptor.<tool_name>.deny_impact
ai_settings.tool_consent.descriptor.<tool_name>.source.1
ai_settings.tool_consent.descriptor.<tool_name>.source.2
```

首批工具范围：

| 工具 | 分类 | 备注 |
| --- | --- | --- |
| `get_current_location` | location | 当前位置经纬度 |
| `query_location` | location | 地点解析结果 |
| `query_weather` | weather | 天气查询结果 |
| `fetch_step_details` | health | 步数明细 |
| `fetch_energy_details` | health | 活动能量 |
| `fetch_nutrition_details` | health | 营养摄入 |
| `fetch_sleep_details` | health | 睡眠明细 |
| `fetch_workout_details` | health | 运动训练 |

### 6.8 运行时文案

| key | zh-Hans |
| --- | --- |
| `ai_settings.tool_consent.runtime.always_deny_reason` | 用户已将该工具配置为永久拒绝发送到 AI。 |

该文案可能会进入模型上下文或用户可见的拦截结果。实现时需要确认调用点是否适合按当前 App 语言本地化；如果该文本只发给模型，也需要评估是否应跟随会话语言而不是系统语言。

## 7. 验收标准

1. 授权管理入口、列表、详情页、工具详情授权区不再出现新增中文硬编码 UI 文案。
2. `ToolModelEgressConsentDescriptor` 不再以中文字符串作为分类逻辑判断依据。
3. `zh-Hans`、`en`、`zh-Hant` 三套授权文案完整可用。
4. 英文系统语言下，授权管理页不出现中文 UI 文案。
5. 繁体中文系统语言下，授权管理页不回退到简体中文或英文。
6. `AISETTINGS-000002` 的授权策略行为不变：永久拒绝、下次询问、始终运行仍按原逻辑生效。
7. 新增或调整本地化 key 后，`xcodebuild` 至少完成一次 Debug 构建验证。
8. 增加或更新测试，覆盖位置 / 天气默认 `alwaysAllow` 以及 descriptor 分类不依赖展示文案。

## 8. 回归检查建议

1. 切换系统语言为英文，进入 `AI 设置 -> 授权管理`，检查入口、列表、详情、工具详情授权区。
2. 切换系统语言为繁体中文，重复检查授权管理链路。
3. 触发 `get_current_location`、`query_weather`、`fetch_sleep_details` 等工具，检查运行时授权文案。
4. 检查“始终运行 / 下次询问 / 永久拒绝”切换后保存、重进页面、实际运行行为一致。
5. 检查位置、天气、健康分类对应图标和颜色在英文 / 繁中环境下不变化。

## 9. 实施注意事项

1. 本工单只治理 `AISETTINGS-000002` 新增授权管理相关文案，不扩散到全项目历史中文日志和旧功能文案。
2. 日志类中文文案可暂不纳入本工单，除非它会展示给用户或进入模型可见内容。
3. `fallback` 可以保留作为兜底，但不能作为目标语言的唯一来源。
4. 如果 `L10n` 当前没有数组读取能力，优先使用编号 key，避免为本工单引入过大的本地化框架改造。
5. 新增 `zh-Hant.lproj/Localizable.strings` 时需确认资源被 Xcode target 收录。
