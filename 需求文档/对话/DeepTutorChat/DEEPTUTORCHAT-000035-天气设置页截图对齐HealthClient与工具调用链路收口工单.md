# DEEPTUTORCHAT-000035 天气设置页截图对齐 HealthClient 与工具调用链路收口工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000035 |
| 工单类型 | P1 设置页 UI 对齐 + HealthClient 工具配置对齐 + DeepTutorChat 天气工具调用链路验收 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标设置页 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIWeatherToolSettingsView.swift` |
| 目标工具链路 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub`、`/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather` |
| 参考工程 | `/Users/hua/Documents/DreamHealth/HealthClient` |
| 参考截图 | `/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-46c7e49a-70f9-4fd5-92f7-152f6b1769a5.png` |
| 创建日期 | 2026-08-06 |
| 触发问题 | SparkClient 天气设置页需要和截图一致，并与 HealthClient 的天气工具配置、本地化存储、Apple 天气支持、工具调用执行链路对齐 |
| 关联工单 | `DEEPTUTORCHAT-000032`、`DEEPTUTORCHAT-000034`、`DEEPTUTORCHAT-000030`、`DEEPTUTORCHAT-000011`、`DEEPTUTORCHAT-000012` |
| 核心约束 | UI 不是普通 SwiftUI Form 默认样式；天气配置必须本地持久化并按账号隔离；天气工具调用不能停留在配置页可见，必须真实驱动 `query_location` / `query_weather`；Apple 天气不能只写预留，必须明确支持方案 |

## 1. 对标范围与结论

本工单覆盖两条线：

```text
1. 天气设置页 UI：必须对齐截图中的 Weather Enquiry 页面结构、视觉层级、卡片样式、开关与供应商列表。
2. 天气配置存储：必须参考 HealthClient 的 `WeatherSettingView` + SwiftData `ToolKeys` 本地化存储，确保开关、Provider、Key、Host 本地保存并可恢复。
3. 天气工具调用：必须对齐 HealthClient 的 ToolKeys / useWeather / 单一供应商启用 / 工具外发确认 / query_weather 执行语义。
4. Apple 天气支持：必须把 Apple 天气作为正式目标 Provider 设计，而不是仅作为不可用预留文案。
```

当前 SparkClient 已经具备：

```text
1. `AIWeatherToolSettingsView`。
2. `AIWeatherToolPreferences.useWeather`。
3. `ToolKeys(toolClass="weather")`。
4. `WeatherRuntimeConfigResolver`。
5. `WeatherGateway` 与 `OpenWeatherProvider`。
6. ToolHub 中 `runWeatherTool` / `runLocationTool` 的初步路由。
```

但仍存在核心差距：

```text
1. 设置页视觉仍偏系统 Form，未对齐截图的大标题、浅灰背景、圆角白卡、底部 Tab、供应商列表结构。
2. Provider 集合与截图/HealthClient 不一致：截图要求 OpenWeather + Qweather；补充要求还需要支持 Apple 天气。
3. UI 文案、图标、分组标题需要按截图英文目标态或 HealthClient 多语言规则统一。
4. 工具调用要确认 `useWeather=false`、无 active provider、Key 缺失、Provider 未适配时，DeepTutorChat 不暴露或不伪造天气结果。
5. 天气工具结果属于可能与位置相关的数据，外发给第三方 AI 前需要对齐 HealthClient 的敏感工具确认策略。
```

## 2. 截图级 UI 差距清单

| 模块 | 截图 / HealthClient 参考 | SparkClient 当前 | 差距判断 | 优先级 |
| --- | --- | --- | --- | --- |
| 页面容器 | 淡冷灰背景，顶部状态栏下方大圆形返回按钮，大标题 `Weather Enquiry` | `Form` + `navigationTitle("天气查询")` | 页面类型不一致，当前像系统表单，不像独立工具设置页 | P1 |
| 顶部说明卡 | 白色大圆角卡片，中心天气图标，说明文案居中 | Form section 中 VStack，默认 inset/grouped 样式 | 信息有但视觉层级不一致，卡片尺寸、圆角、留白不足 | P2 |
| 启用天气 | 独立白色胶囊卡，左侧 `Enable Weather`，右侧大号蓝色 switch | Form Section Toggle | 控件语义相同，但容器样式、间距、字号不一致 | P2 |
| Provider 分组标题 | 灰色粗体标题：`Weather service provider selection (only one can be enabled)` | `Section("天气服务商选择（最多只能开启一个）")` | 文案语义接近，但视觉权重、语言、换行和位置未对齐 | P2 |
| Provider 列表 | 单张白色圆角卡，两行：OpenWeather、Qweather；左图标、中名称、右蓝色 key 图标 + switch；行间细分隔线 | SwiftUI row；当前 provider 可能是 OpenWeather + WeatherKit，带“使用中/预留”胶囊 | Provider 集合、图标语义、行结构不一致；WeatherKit 不应出现在截图目标态 | P1 |
| Function List | 灰色分组标题 + 白色圆角卡，两行功能：`Check Real-time Weather`、`Future Weather Forecast` | 当前含 `城市地理编码（query_location）` | 截图只展示用户可理解功能，不展示内部工具名；需移除 query_location 用户文案 | P1 |
| 底部 Tab | 首页、知识库、Models、Settings，Settings 选中胶囊 | AISettings 子页通常隐藏主 Tab | 如果目标页面需要完全复刻截图，则底部 Tab 需保留或由宿主统一显示；当前 `.hidesMainTabBarWhenPushed()` 可能不符合截图 | P1 待确认 |
| 颜色 | 背景 `#F4F4F8`，主蓝 `#0A84FF`，副标题灰 `#8E8E93`，卡片白 | SwiftUI 默认 Form 颜色 | 颜色职责未按截图固定 | P2 |

## 3. UI 目标结构

天气设置页目标层级：

```text
WeatherEnquirySettingsPage
  -> custom background #F4F4F8
  -> top back circular button
  -> large page title
  -> intro card
       icon cloud.sun
       centered description
  -> enable weather card
       title
       switch
  -> provider section title
  -> provider card
       OpenWeather row
       Qweather row
  -> function list title
  -> function card
       Check Real-time Weather
       Future Weather Forecast
  -> bottom tab bar behavior according to host navigation decision
```

实现要求：

```text
1. 不直接使用默认 `Form` 外观作为最终态。
2. 可以继续使用 SwiftUI，但需要自定义 ScrollView + VStack + rounded card。
3. 卡片圆角建议 24-28，截图接近大圆角；不要使用普通 8px 工具卡。
4. 页面左右边距约 20-24。
5. 大标题字号约 44-48，weight black/bold。
6. 分组标题使用灰色、较粗、允许两行。
7. Provider row 高度约 72，行内图标 24-28，key 图标使用蓝色。
8. switch 右侧对齐，禁用态灰色。
```

## 4. 颜色与视觉 token

| UI 部位 | 截图观感 | 建议色值 | 说明 |
| --- | --- | --- | --- |
| 页面背景 | 淡冷灰 | `#F4F4F8` | 全页背景 |
| 卡片背景 | 纯白 | `#FFFFFF` | 说明卡、开关卡、Provider 卡、功能卡 |
| 主文字 | 近黑 | `#0B0B0F` | 大标题、行标题 |
| 次级文字 | 中灰 | `#8E8E93` | 分组标题、说明文 |
| 主蓝 | iOS 蓝 | `#0A84FF` | 天气图标、key 图标、选中 switch、Settings 选中 |
| 分隔线 | 浅灰 | `#E5E5EA` | Provider 行、功能行之间 |
| 禁用 Switch | 灰色 | `#C7C7CC` | 未启用 provider |
| OpenWeather 图标 | 橙红 | `#F26B4F` | 与截图图标接近 |
| Qweather 图标 | 黑色 | `#111111` | 与截图黑色旋涡图标接近 |

## 5. 本地化存储与 Provider 配置对齐要求

### 5.0 本地化存储要求

HealthClient 参考：

```text
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Data/Models/Al/ToolKeys.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/App/HealthClientApp.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Presentation/Views/Settings/Tools/WeatherSettingView.swift
```

HealthClient 做法：

```text
1. `ToolKeys` 是 SwiftData `@Model`，字段包含 name/company/key/requestURL/isUsing/toolClass/help/timestamp。
2. App 启动时在 ModelContainer 注册 `ToolKeys.self`。
3. 首次启动通过 `preloadToolKeysIfNeeded` 灌入 weather/map/calendar 等工具供应商种子。
4. `WeatherSettingView` 通过 `@Query(filter: toolClass == "weather")` 读取本地天气供应商。
5. `useWeather` 存在本地 `UserInfo` 中，页面 onAppear 读取、onDisappear 保存。
```

SparkClient 目标：

```text
1. 天气设置必须是本地可持久化配置，不依赖远端临时内存。
2. `ToolKeys(toolClass="weather")`、`AIWeatherToolPreferences.useWeather`、`weatherConfigRevision` 必须能落到本地存储并在重启后恢复。
3. 账号切换时，天气配置要遵循 SparkClient 现有 AISettings 按账号隔离策略。
4. 如果继续采用 `AISettingsSnapshot.PreferencesPayload + UserDefaults` 保存 ToolKeys 和天气偏好，必须在工单中明确这是 SparkClient 对 HealthClient SwiftData 本地化存储的等价实现。
5. 如果后续改为 Core Data/SwiftData 独立表保存 ToolKeys，必须提供迁移策略，不能丢失用户已填 API Key。
6. API Key 当前如仍存 `ToolKeys.key`，至少要做日志脱敏；若按更高安全标准，应改为 Keychain ref，本工单允许作为 P2 安全增强项。
```

本地化存储验收：

```text
1. 配置 OpenWeather/Qweather/Apple 天气任意一项后，杀进程重启仍能看到配置。
2. 关闭/开启 Enable Weather 后，重启仍保持状态。
3. 切换 active provider 后，重启只保留一个 provider `isUsing=true`。
4. weatherConfigRevision 在配置变化后递增，ToolHub 读取到最新配置。
5. 日志不得输出完整 API Key、WeatherKit token、JWT。
```

### 5.1 Provider 集合

截图与 HealthClient 目标态：

```text
OpenWeather
Qweather
```

SparkClient 目标：

```text
1. OpenWeather：当前必须可配置、可启用、可真实调用。
2. Qweather：必须在设置页出现配置项；如本期要求可用，则新增 QWeather provider adapter；如本期只做 UI 对齐，则显示但不可启用并提示暂未接入。
3. Apple 天气：必须作为正式支持目标加入 Provider 设计。UI 可显示为 Apple Weather / 苹果天气；实现上优先走 WeatherKit，不允许长期只写“预留”。
```

### 5.1.1 Apple 天气支持要求

Apple 天气目标 Provider：

```text
company: APPLEWEATHER 或 WEATHERKIT（二选一后统一全工程命名）
displayName: Apple Weather / 苹果天气
toolClass: weather
help: https://developer.apple.com/documentation/weatherkit
```

必须确认并实现：

```text
1. Provider 命名统一：HealthClient 历史注释使用 `APPLEWEATHER`，SparkClient 当前使用 `WEATHERKIT`。本工单要求统一 alias：UI 显示 Apple Weather，内部可规范为 `WEATHERKIT`，同时兼容旧 `APPLEWEATHER`。
2. `WeatherProviderID` 增加 Apple Weather 解析别名：`APPLEWEATHER` -> `.weatherKit`。
3. `WeatherProviderID.hasLocalAdapter` 只有在 WeatherKit 真实 adapter 完成后才能为 true。
4. WeatherKit 需要 Apple Developer entitlement、JWT / token 生成、服务端或客户端调用策略、配额与地区可用性验证。
5. 如果客户端无法安全生成/保存 WeatherKit token，应采用服务端代理，不在客户端硬编码私钥。
6. Apple 天气启用前不应要求普通 API Key；应按 WeatherKit 认证方式展示“使用 Apple WeatherKit 授权/服务端配置”。
7. Apple 天气请求失败时必须明确降级到用户启用的其它 provider，或提示当前 Apple 天气不可用，不编造结果。
```

Apple 天气分阶段：

```text
Phase A：UI 与本地配置支持 Apple Weather 行，显示文档入口和当前接入状态。
Phase B：实现 WeatherKitProvider，完成 current weather / forecast 标准化输出。
Phase C：启用 Apple Weather provider，参与单选 provider 规则。
Phase D：补充 WeatherKit 单元测试、真机/沙盒验收、失败降级。
```

Apple 天气不可接受状态：

```text
1. UI 显示 Apple 天气可用，但 ToolHub 实际返回 unsupportedProvider。
2. Apple 天气不需要 key 的文案照搬 HealthClient，但没有 WeatherKit entitlement/token。
3. 在客户端仓库中写死 WeatherKit 私钥或长期 token。
```

### 5.2 单选启用

对齐 HealthClient：

```text
1. `useWeather=true` 是天气功能总开关。
2. `ToolKeys.toolClass == "weather"` 筛选天气服务商。
3. 同一时间最多一个天气 provider `isUsing=true`。
4. 启用某个 provider 时自动关闭其它 weather provider。
5. 关闭总开关后 provider switch 禁用或置灰，DeepTutorChat 不应调用天气工具。
```

### 5.3 Key / Host 编辑

对齐 HealthClient：

```text
1. 点击 provider row 进入编辑页。
2. 编辑页显示 provider 图标、说明、help link。
3. OpenWeather/Qweather 启用前必须填写 API Key。
4. OpenWeather/Qweather 启用前必须填写 requestURL / Host。
5. Apple 天气启用前必须完成 WeatherKit 认证能力检查，不按普通 API Key 规则校验。
6. 保存时刷新 timestamp 和 weatherConfigRevision。
```

## 6. 工具调用链路对齐要求

### 6.1 HealthClient 参考链路

参考文件：

```text
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/ExyteChat/ZDKOpenChat/Store/ZDKOpenChatStore+UserFlags.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/ExyteChat/ZDKOpenChat/Store/ZDKOpenChatStore+ExternalDataConsent.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/ExyteChat/ZDKOpenChat/Store/ZDKOpenChatStore+OpenAISDK.swift
```

需要吸收：

```text
1. `isWeatherEnabled()` 从用户设置读取天气总开关。
2. `query_weather` 是敏感工具之一，结果发送到第三方 AI 前需要确认。
3. 工具执行状态显示为“正在查询天气 / Querying Weather”。
4. 工具友好名显示为“查询天气 / Query weather”。
```

### 6.2 SparkClient 目标链路

目标链路：

```text
AIWeatherToolSettingsView
  -> AIWeatherToolPreferences.useWeather
  -> ToolKeys(weather).isUsing
  -> WeatherRuntimeConfigResolver.resolve(snapshot)
  -> ToolHub.runLocationTool / runWeatherTool
  -> WeatherGateway.geocode / queryWeather
  -> DeepTutorChat trace / rich block / assistant response
```

必须满足：

```text
1. `useWeather=false` 时，DeepTutorChat 不应主动开放 `query_weather`，或工具调用返回“天气功能未启用”。
2. 无 active provider 时，返回 `missingActiveProvider`，并提示去 AI 设置 -> 天气工具启用。
3. provider 缺 key / endpoint 时，不允许启用；运行时也要 fail closed。
4. `query_location` 必须能与 weather provider 协同，城市明确时先 geocode，再 weather。
5. `query_weather` 失败时不让模型编造天气。
6. 工具结果进入第三方模型前，位置/天气内容按敏感工具策略确认或脱敏。
```

### 6.3 DeepTutorChat 表现

用户示例：

```text
北京今天的天气怎么样？
Apple 天气说上海会下雨，你帮我确认一下。
明天杭州天气适合跑步吗？
```

预期：

```text
1. 工具策略命中 weather_location。
2. allowedTools 包含 query_location/query_weather。
3. trace 显示“查询位置”与“查询天气”。
4. OpenWeather 成功时展示实时天气/未来预报结果。
5. Qweather 未接 adapter 时，设置页不可启用或工具返回明确 unsupportedProvider。
```

## 7. 整改方案

### Phase 1：截图级 UI 重构

```text
1. 将 `AIWeatherToolSettingsView` 从默认 Form 外观改为截图目标态的自定义 ScrollView 页面。
2. 页面标题改为 `Weather Enquiry` 或接入 L10n：中文 `天气查询` / 英文 `Weather Enquiry`。
3. 顶部说明卡、启用天气卡、Provider 卡、Function List 卡按截图结构重建。
4. Provider 主列表优先按截图展示 OpenWeather 和 Qweather；Apple 天气作为正式支持目标，可按产品确认展示在主列表第三行或独立 Apple Weather 区域，但状态和能力必须清楚。
5. Function List 只展示面向用户的两项：实时天气、未来预报；不要展示内部 `query_location`。
```

### Phase 2：配置模型对齐

```text
1. Seed 中补齐 QWEATHER ToolKeys，保持 toolClass=weather。
2. `WeatherProviderID` 增加 QWEATHER，初期 `hasLocalAdapter=false` 或完成 adapter 后设为 true。
3. `WeatherProviderID` 增加 Apple Weather / WeatherKit，并兼容 `APPLEWEATHER` 与 `WEATHERKIT` 两种 company。
4. OpenWeather requestURL 使用完整 URL。
5. Provider 启用规则与 HealthClient 一致：总开关 + 单一 provider + Key/Host 校验；Apple 天气走 WeatherKit 能力校验。
6. 明确 SparkClient 的本地化存储方案：继续使用账号级 PreferencesPayload，或迁移为本地 ToolKeys 表；无论哪种方案都必须重启可恢复。
7. 每次配置变化刷新 weatherConfigRevision。
```

### Phase 3：Apple 天气 Provider 接入

```text
1. 新增 WeatherKitProvider 或 AppleWeatherProvider。
2. 明确认证方式：客户端 WeatherKit token、服务端代理，或 Apple 官方推荐路径。
3. WeatherGateway 支持 `.weatherKit` 的 geocode/current/forecast 能力；如 WeatherKit 不提供 geocode，则必须明确依赖地图 provider 或用户坐标。
4. 将 WeatherKit 返回结构标准化为 WeatherResult。
5. 补 Apple 天气失败降级：无授权、无 token、地区不可用、配额耗尽、网络失败。
```

### Phase 4：工具调用链路收口

```text
1. DeepTutorDomainToolExtensionResolver 挂天气工具前检查 weatherToolPreferences.useWeather。
2. ToolHub 对 `query_weather` 使用 WeatherGateway，不走占位。
3. ToolHub 对 `query_location` 优先使用 WeatherGateway.geocode 或地图 provider geocode，避免城市到坐标断链。
4. 外发第三方 AI 前，将 query_weather/query_location 纳入敏感工具确认。
5. DeepTutorChat 日志记录 provider、revision、elapsedMs，不记录 API Key 和精确坐标。
```

## 8. 验收标准

### 8.1 UI 验收

```text
1. 页面视觉结构与截图一致：大标题、浅灰背景、白色圆角卡、Provider 双行卡、Function List 卡。
2. Provider 主列表展示 OpenWeather 和 Qweather；Apple 天气按产品确认显示在主列表或高级/Apple Weather 区域，但必须可配置状态清楚。
3. 开启天气总开关后，Provider switch 可用；关闭后置灰。
4. 只能启用一个天气 provider。
5. 未填写 Key/Host 时启用 OpenWeather/Qweather 有错误提示。
6. Apple 天气不走普通 API Key 文案；未完成 WeatherKit 能力时不能伪装成可启用。
7. Function List 不出现 `query_location` 等内部工具名。
```

### 8.2 工具调用验收

```text
1. 启用 OpenWeather 并配置 Key 后，问“北京今天的天气怎么样”能走 query_location -> query_weather。
2. `deeptutor.weather.query_start` 和 `deeptutor.weather.query_result` 日志出现。
3. 关闭 Enable Weather 后，同一问题不应真实调用天气 provider。
4. 未配置 provider 时，回答引导用户去 AI 设置 -> 天气工具配置，不编造天气。
5. Qweather 未实现 adapter 时不能启用；若实现 adapter，则需完成同等测试。
6. Apple 天气启用后，问“Apple 天气说上海会下雨，你帮我确认一下”能走 Apple Weather/WeatherKit 或明确降级到 active provider，不能编造。
7. Apple 天气未完成认证/授权时，设置页和工具结果必须明确说明不可用原因。
8. 工具结果外发第三方 AI 前按敏感工具确认规则处理。
```

### 8.3 本地化存储验收

```text
1. OpenWeather/Qweather/Apple 天气配置保存后，重启 App 配置仍存在。
2. Enable Weather 开关保存后，重启 App 状态仍存在。
3. 切换 active provider 后，重启 App 仍只有一个 provider 启用。
4. 账号切换后，不读取另一个账号的天气配置。
5. 首次安装时能灌入 OpenWeather、Qweather、Apple Weather 的本地种子数据。
```

## 9. 风险与待确认项

```text
1. 截图显示底部 TabBar；当前 SparkClient 的 AI 设置二级页可能隐藏 TabBar。需要确认目标是“完整复刻截图”还是“仅内容区复刻”。
2. Qweather 是否必须本期实现真实 adapter。如果只是 UI 对齐，应显示但不可启用；如果要求可用，需要新增 QWeatherProvider。
3. Apple 天气是否本期必须真实可用。如果必须可用，需要先确认 WeatherKit entitlement、token/JWT、服务端代理策略和地区可用性。
4. 页面语言截图为英文，HealthClient 源码为中文。SparkClient 需要走 L10n，不应硬编码单语言。
5. 天气和位置数据是否必须弹出外发确认，需要和现有 ToolHub consent 策略统一。
6. OpenWeather/Qweather API Key 存储目前在 ToolKeys 中，后续如有更高安全要求，应迁移到 Keychain 引用。
7. Apple WeatherKit 私钥绝不能写入客户端本地明文配置；如果涉及私钥，必须服务端托管。
```

## 10. 完成定义

本工单完成时必须同时满足：

```text
1. 天气设置页截图级对齐完成。
2. OpenWeather / Qweather / Apple 天气 Provider 配置语义与 HealthClient 对齐。
3. 天气配置本地化持久化完成，重启、切账号、首次灌库都可验收。
4. `Enable Weather` 总开关真实影响 DeepTutorChat 天气工具开放和执行。
5. `query_location` / `query_weather` 可完成真实工具调用或给出明确失败结果。
6. Apple 天气支持路径明确并完成本期承诺的可用范围，不能停留在误导性预留。
7. 天气工具结果外发、日志、错误提示符合隐私和脱敏要求。
8. UI 截图验收、配置验收、本地存储验收、工具调用验收四类测试均通过。
```
