# DEEPTUTORCHAT-000034 参考 HealthClient 接入天气 AI 设置配置收口工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000034 |
| 工单类型 | P1 AI 设置天气工具配置收口 + HealthClient 参考迁移 + DeepTutorChat 天气 Provider 验收 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| AI 设置目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 天气运行时目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather` |
| 参考工程 | `/Users/hua/Documents/DreamHealth/HealthClient` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 需要参考 HealthClient 的天气工具配置方式，把 SparkClient 的 AI 设置天气 Provider 配置、启用规则、真实查询链路做成可验收闭环 |
| 关联工单 | `DEEPTUTORCHAT-000030`、`DEEPTUTORCHAT-000032`、`DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000011`、`DEEPTUTORCHAT-000012` |
| 核心约束 | 天气 Provider 配置属于工具配置，不是大模型 API Key；DeepTutorChat 只消费配置，不在聊天模块写死 Key、host 或 provider |

## 1. 本工单目标

本工单目标：

```text
1. 参考 HealthClient 的 WeatherSettingView / ToolKeys 设计，收口 SparkClient AI 设置中的天气工具配置。
2. 明确天气 Provider 配置模型、默认种子、单选启用规则、Key/endpoint 校验和持久化规则。
3. 确保 DeepTutorChat 的 query_location / query_weather 能读取同一份 AISettings snapshot。
4. 建立验收标准：设置中启用 OpenWeatherMap 后，DeepTutorChat 可以真实查询天气；未配置时不伪造结果。
```

本工单不是新增一个普通天气问答工单。它专注于：

```text
AI 设置天气工具配置
  -> WeatherRuntimeConfigResolver
  -> WeatherGateway
  -> ToolHub query_location/query_weather
  -> DeepTutorChat 工具链路
```

## 2. HealthClient 参考结论

### 2.1 参考文件

```text
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Data/Models/Al/ToolKeys.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Core/Services/DataServices/InfoServices.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Presentation/Views/Settings/Tools/WeatherSettingView.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/Presentation/Views/Settings/Tools/MapSettingView.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/ExyteChat/ZDKOpenChat/Store/ZDKOpenChatStore+UserFlags.swift
/Users/hua/Documents/DreamHealth/HealthClient/HealthClient/ExyteChat/ZDKOpenChat/Store/ZDKOpenChatStore+ExternalDataConsent.swift
```

### 2.2 ToolKeys 模型

HealthClient 的 `ToolKeys` 是 SwiftData 模型：

```text
name
company
key
requestURL
price
isUsing
toolClass
help
timestamp
```

结论：

```text
天气、地图、日历等外部工具供应商用 `ToolKeys` 统一表达。
天气供应商通过 `toolClass == "weather"` 筛选，不混入 AI 大模型 `APIKeys`。
```

### 2.3 天气默认 Provider 种子

HealthClient 默认工具 Key 中的天气项：

```text
QWEATHER
  name: QWEATHER_KEY
  requestURL: 空
  toolClass: weather
  help: https://console.qweather.com/project?lang=zh

OPENWEATHER
  name: OPENWEATHER_KEY
  requestURL: api.openweathermap.org
  toolClass: weather
  help: https://home.openweathermap.org/api_keys

APPLEWEATHER
  当前为注释预留
  help: https://developer.apple.com/documentation/weatherkit
```

迁移判断：

```text
1. SparkClient 可以直接沿用 `toolClass=weather` 的配置事实源。
2. SparkClient 当前已支持 OpenWeatherMap 本地适配，QWeather 可作为后续扩展项。
3. Apple WeatherKit 只能作为预留项，除非完成 entitlement、JWT、配额和可用性验证。
```

### 2.4 WeatherSettingView 交互规则

HealthClient 的天气设置页规则：

```text
1. 顶部说明天气功能用途。
2. 有全局“启用天气”开关。
3. 天气服务商列表通过 `toolClass == "weather"` 查询。
4. “最多只能开启一个”天气服务商。
5. 启用非 AppleWeather 供应商前必须校验 API Key。
6. 启用非 AppleWeather 供应商前必须校验 API Host。
7. 点击供应商进入编辑页，编辑 API Key 和 Host。
8. 保存时刷新 timestamp。
```

SparkClient 需要吸收的关键点：

```text
1. 天气工具应有独立入口和明确的“使用中”状态。
2. active provider 必须唯一。
3. 未填 API Key / endpoint 时禁止启用。
4. WeatherKit 预留项不能按普通 API Key provider 处理。
```

### 2.5 UserInfo.useWeather 工具开关

HealthClient 的聊天侧通过：

```text
ZDKOpenChatStore.isWeatherEnabled() -> UserInfo.useWeather
```

判断天气能力是否启用。

SparkClient 当前没有完全同名的 `useWeather` 用户开关，建议采用：

```text
1. MVP：是否存在 active weather ToolKeys 作为天气工具启用条件。
2. P1：如产品需要独立总开关，在 AISettingsSnapshot 增加 weatherToolPreferences.useWeather。
3. DeepTutorToolPolicyResolver 挂载天气工具时，应同时满足 weather intent + 配置可用或允许先追问城市。
```

## 3. SparkClient 当前事实

### 3.1 已存在 AI 设置天气入口

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIWeatherToolSettingsView.swift
```

当前入口：

```text
AI 设置
  -> 工具
  -> 天气工具
```

当前页面能力：

```text
1. 展示天气供应商列表。
2. 显示“使用中”状态。
3. 编辑供应商名称、company、API Key、请求 URL。
4. 启用前校验 provider 是否支持、是否有本地 adapter、是否填写 key、endpoint 是否有效。
5. 启用一个 provider 时关闭其它 weather provider。
```

结论：

```text
SparkClient 已经吸收了 HealthClient WeatherSettingView 的核心交互，但还需要补齐总开关语义、默认种子差异、真实工具调用验收和测试。
```

### 3.2 已存在天气运行时

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather/WeatherRuntimeModels.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather/WeatherRuntimeConfigResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather/WeatherGateway.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather/Providers/OpenWeatherProvider.swift
```

当前 provider：

```text
OPENWEATHER：已本地适配
WEATHERKIT：仅预留，hasLocalAdapter=false
```

当前能力：

```text
1. OpenWeather geocode。
2. OpenWeather current weather。
3. OpenWeather forecast 中的 tomorrow 支持。
4. week / 本周暂不支持并返回 forecastUnavailable。
5. WeatherRuntimeConfigRevision 用于审计和缓存失效。
```

结论：

```text
SparkClient 的技术底座已经比 HealthClient 更接近完整运行时，需要重点验证 ToolHub 是否真正调用 WeatherGateway，而不是仍走外部连接器占位。
```

### 3.3 风险点

当前仍需重点检查：

```text
1. AIWeatherToolSettingsView 入口是否在当前构建目标中包含。
2. ToolHub query_location/query_weather 是否已经路由到 WeatherGateway。
3. DeepTutorChat weather intent 挂工具时，是否考虑“天气 provider 未配置”的错误路径。
4. WeatherKit 预留项是否会让用户误以为可用。
5. OpenWeather 默认 URL 是否统一：HealthClient 用 host，SparkClient 用完整 URL。
```

## 4. 目标设计

### 4.1 配置模型

继续使用 SparkClient 当前模型：

```text
ToolKeys
  name
  company
  key
  requestURL
  isUsing
  toolClass
  help
  source
  timestamp
```

天气约束：

```text
toolClass 必须为 weather
company 必须能解析为 WeatherProviderID
同一时间最多一个 weather provider isUsing=true
非本地适配 provider 不能启用
非免密 provider 必须填写 API Key
requestURL 必须是合法 URL
```

### 4.2 默认 Provider 种子

建议默认：

```text
OpenWeatherMap
  company: OPENWEATHER
  requestURL: https://api.openweathermap.org/data/2.5/weather
  help: https://home.openweathermap.org/api_keys
  isUsing: false
  hasLocalAdapter: true

Apple WeatherKit
  company: WEATHERKIT
  requestURL: https://weatherkit.apple.com
  help: https://developer.apple.com/documentation/weatherkit
  isUsing: false
  hasLocalAdapter: false
  UI 显示“预留/暂未支持”
```

可选后续：

```text
QWeather
  company: QWEATHER
  help: https://console.qweather.com/project?lang=zh
  需要新增 WeatherProviderID 与 provider adapter 后再开放启用
```

### 4.3 设置页交互

目标交互：

```text
1. AI 设置 -> 天气工具 可见。
2. 顶部说明真实天气查询用途与边界。
3. Provider 列表显示图标、名称、company、Key 状态、使用中状态。
4. 启用 OpenWeatherMap 前必须填写 API Key 和完整 endpoint。
5. WeatherKit 显示预留说明，不允许启用，或启用按钮禁用并提示“暂未接入”。
6. 启用一个 provider 时自动关闭其它天气 provider。
7. 修改配置后刷新 weatherConfigRevision。
```

### 4.4 DeepTutorChat 消费规则

天气问题链路：

```text
用户输入天气问题
  -> DeepTutorStructuredToolIntent 命中 weather_location
  -> DeepTutorDomainToolExtensionResolver 挂载 query_location/query_weather
  -> ToolHub 执行 query_location
  -> ToolHub 执行 query_weather
  -> WeatherRuntimeConfigResolver 读取 active ToolKeys
  -> WeatherGateway 调 OpenWeatherProvider
  -> 工具结果进入模型上下文
```

未配置天气 provider：

```text
1. 城市明确时，query_weather 返回 missingActiveProvider。
2. 助手应说明“尚未配置天气服务，请在 AI 设置 -> 天气工具中启用供应商”。
3. 不允许模型根据常识猜测实时天气。
```

## 5. 与 DEEPTUTORCHAT-000032 的分工

`DEEPTUTORCHAT-000032`：

```text
天气查询能力、Apple/审核回复口径、真实天气工具接入整体方案。
```

本工单：

```text
专注 AI 设置天气供应商配置，参考 HealthClient 的 ToolKeys + WeatherSettingView 交互，把配置事实源和验收补齐。
```

## 6. 开发拆分

### Phase 1：配置入口与 Provider 列表收口

```text
1. 确认 `AIWeatherToolSettingsView` 已加入 `AISettingsView` 且能进入。
2. 对照 HealthClient `WeatherSettingView` 检查顶部说明、功能列表、使用中状态、编辑页。
3. 补齐 OpenWeather help URL。
4. WeatherKit 显示“预留/暂未接入”，避免误启用。
```

### Phase 2：配置规则与持久化

```text
1. 启用 provider 时保持 weather 单选。
2. 校验 API Key 和 endpoint。
3. 修改 Key/URL/company 后刷新 weatherConfigRevision。
4. 删除或禁用 active provider 后，DeepTutorChat 能收到 missingActiveProvider。
```

### Phase 3：工具运行链路验收

```text
1. query_location 可将城市转换为经纬度。
2. query_weather 使用 WeatherRuntimeConfigResolver。
3. OpenWeatherProvider 请求成功后返回标准 WeatherResult。
4. ToolHub 不再对 query_weather 只返回“路由说明”。
5. DeepTutorChat 展示“查询天气”工具状态与最终回答。
```

## 7. 测试计划

### 7.1 单元测试

建议新增/更新：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/AI/WeatherRuntimeConfigResolverTests.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/Tests/DeepTutorChat/DeepTutorToolPolicyResolverTests.swift
```

测试项：

```text
1. 无 active weather provider 时抛 missingActiveProvider。
2. OPENWEATHER 缺 key 时抛 missingAPIKey。
3. endpoint 无 scheme 时抛 invalidEndpoint。
4. WEATHERKIT 因 hasLocalAdapter=false 不允许启用。
5. 多个 weather provider 同时 isUsing=true 时只保留最新 active。
6. 修改 weather ToolKeys 后 weatherConfigRevision 递增。
7. 天气意图问题挂载 query_location/query_weather。
```

### 7.2 手工验收

步骤：

```text
1. 打开 AI 设置 -> 天气工具。
2. 编辑 OpenWeatherMap，填写 API Key 和 endpoint。
3. 启用 OpenWeatherMap，确认列表只显示它“使用中”。
4. 回到 DeepTutorChat，发送“北京今天的天气怎么样？”
5. 查看日志确认 query_location -> query_weather。
6. 关闭 OpenWeatherMap，再问同样问题。
```

通过标准：

```text
1. 配置页可达、可编辑、可保存。
2. Provider 单选规则生效。
3. 未配置 key 时不能启用。
4. 配置成功后 DeepTutorChat 使用真实天气结果回答。
5. 未配置时返回可行动错误，不编造天气。
6. 日志不输出 API Key，坐标只做低精度展示。
```

## 8. 完成定义

本工单完成时必须满足：

```text
1. SparkClient 天气工具配置与 HealthClient 的 ToolKeys/WeatherSettingView 核心规则对齐。
2. AI 设置中天气工具入口、Provider 列表、编辑页、启用校验、单选状态全部可用。
3. WeatherRuntimeConfigResolver 可以稳定解析 active provider。
4. DeepTutorChat query_weather 能消费同一份配置。
5. WeatherKit 预留项不会被误认为已支持。
6. 单元测试和手工验收覆盖配置成功、配置缺失、provider 不支持、工具调用成功四类路径。
```
