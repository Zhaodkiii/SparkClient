# DEEPTUTORCHAT-000036 天气设置初始三厂商与通用头部导航对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000036 |
| 工单类型 | P1 初始天气厂商灌库 + 设置页通用头部导航对齐 + Tab 头部保留 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标设置页 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIWeatherToolSettingsView.swift` |
| 初始配置目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Domain` |
| 参考工程 | `/Users/hua/Documents/DreamHealth/HealthClient` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 当前天气设置页进入后显示“暂无天气供应商”，必须直接可选到 OpenWeather、Qweather、苹果天气三个厂商；设置页面头部要和主流设置页一致，不隐藏通用头部/Tab，并增加返回按钮 |
| 关联工单 | `DEEPTUTORCHAT-000035`、`DEEPTUTORCHAT-000034`、`DEEPTUTORCHAT-000032` |
| 核心约束 | 初始厂商配置必须在首次启动/首次进入设置时本地可见；页面导航不能变成孤立全屏页；头部、返回、Tab 行为要和通用 Settings 体验对齐 |

## 1. 本工单目标

本工单聚焦两个收口点：

```text
1. 天气设置初始厂商配置：QWEATHER、OPENWEATHER、APPLEWEATHER 三个 ToolKeys 必须启动后即可选到。
2. 天气设置页面头部：不隐藏通用设置头部，不破坏 Tab/Settings 导航层级，页面自身增加明确返回按钮。
```

完成后用户应看到：

```text
AI 设置 / 天气查询
  -> Enable Weather
  -> Weather service provider selection
       OpenWeather
       Qweather
       苹果天气 / AppleWeather
  -> Function List
```

且这三项不是临时 mock，也不是只有代码默认值，要进入本地配置事实源并可持久化。

## 1.1 当前截图证据

当前截图：

```text
/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-3e1ea675-2e7c-4b73-9128-85c58d665059.png
```

实际现象：

```text
1. 页面标题已经显示“天气查询”。
2. 顶部说明卡、启用天气卡、功能列表已经出现。
3. “天气服务商选择（最多只能开启一个）”下面只显示“暂无天气供应商”。
4. OpenWeather、Qweather、苹果天气三项都没有出现在 Provider 列表里。
```

结论：

```text
这是 P0 配置灌库/迁移缺失，不是 UI 文案问题。
用户进入设置页时没有任何天气供应商可选，天气工具后续一定无法完成真实配置。
```

## 2. 初始三厂商配置要求

### 2.1 必须对齐的 ToolKeys

参考 HealthClient 与用户指定配置，SparkClient 初始天气厂商必须包含：

```swift
ToolKeys(
    name: "QWEATHER_KEY",
    company: "QWEATHER",
    key: "",
    requestURL: "",
    price: 0,
    isUsing: false,
    toolClass: "weather",
    help: "https://console.qweather.com/project?lang=zh"
)

ToolKeys(
    name: "OPENWEATHER_KEY",
    company: "OPENWEATHER",
    key: "",
    requestURL: "api.openweathermap.org",
    price: 0,
    isUsing: false,
    toolClass: "weather",
    help: "https://home.openweathermap.org/api_keys"
)

ToolKeys(
    name: "APPLEWEATHER_KEY",
    company: "APPLEWEATHER",
    key: "",
    requestURL: "",
    price: 0,
    isUsing: false,
    toolClass: "weather",
    help: "https://developer.apple.com/documentation/weatherkit"
)
```

SparkClient 当前 `ToolKeys` 结构如没有 `price` 字段，允许不落 `price`，但其余字段语义必须完整保留。

### 2.2 启动即可选到

要求：

```text
1. 首次安装启动后，进入 AI 设置 -> 天气查询，三厂商都必须显示。
2. 已安装老用户如本地缺少 QWEATHER 或 APPLEWEATHER，需要在加载 AISettings 时做种子补齐，不要求用户清库。
3. 补齐种子不能覆盖用户已有同 company 的 key/requestURL/isUsing/timestamp。
4. 三厂商初始 `isUsing=false`，不能默认启用任何第三方天气服务。
5. `toolClass` 必须全部为 `weather`，页面列表不能靠硬编码数组展示。
```

### 2.2.1 不允许的实现

当前问题说明，单纯在默认值里写三条种子并不足够。以下实现不算完成：

```text
1. 只改 `AISettingsDefaults.toolKeys`，但当前账号已有持久化 payload 时不补齐缺失项。
2. 只在 UI 里硬编码三行 Provider，但没有写入 ToolKeys 本地事实源。
3. 只在清库/新安装时可见，老用户升级后仍显示“暂无天气供应商”。
4. 因 `weatherToolPreferences.useWeather=false` 就隐藏 Provider 列表；关闭总开关只能置灰，不能让列表消失。
5. 把 Apple 天气继续命名成 WEATHERKIT 导致页面找不到 APPLEWEATHER。
```

必须实现：

```text
AISettingsRepository.loadSnapshot
  -> 读取持久化 snapshot/payload
  -> mergeWeatherToolSeedIfNeeded
  -> 保留用户已有配置
  -> 补齐 OPENWEATHER / QWEATHER / APPLEWEATHER
  -> normalizeWeatherProviderSelection
  -> 返回给 AIWeatherToolSettingsView
```

### 2.3 去重与迁移规则

本地存储中可能已存在旧记录：

```text
OPENWEATHER / OpenWeather / OpenWeatherMap
WEATHERKIT
APPLEWEATHER
QWEATHER
```

迁移规则：

```text
1. company 统一大写。
2. `WEATHERKIT` 与 `APPLEWEATHER` 需要建立兼容关系，UI 显示 AppleWeather / Apple Weather。
3. 如果同时存在 WEATHERKIT 和 APPLEWEATHER，优先保留用户有 key、requestURL、isUsing 或更新时间更新的一条，并合并 help。
4. 同一 company 只保留一个 weather ToolKeys。
5. 迁移后仍然保证最多一个 weather provider `isUsing=true`。
```

## 3. 设置页头部导航要求

### 3.1 不隐藏通用头部

用户要求：

```text
设置页面头部需要和主流设置一致，不要隐藏头部，视同通用的 Tab 头部，增加返回按钮。
```

目标解释：

```text
1. 天气查询页不是独立沉浸式落地页，不应隐藏 Settings / Tab 的通用导航上下文。
2. 如果从 AI 设置进入，应保留当前 App 的通用设置页头部或导航栏规则。
3. 页面内部可以有 Weather Enquiry 大标题，但不能取代系统导航返回能力。
4. 返回按钮必须清楚可见，和主流设置页返回行为一致。
```

### 3.2 需要整改的当前风险

当前风险点：

```text
1. `AISettingsView` 中进入 `AIWeatherToolSettingsView` 时存在 `.hidesMainTabBarWhenPushed()`，可能和“不要隐藏头部/通用 Tab 头部”冲突。
2. 天气页自定义 header 有圆形返回按钮，但如果同时隐藏系统导航栏，可能丢失通用设置层级。
3. 截图风格的大标题适合内容区，但设置页仍要遵守宿主导航：返回、Tab、Settings 上下文不能消失。
```

### 3.3 目标导航结构

建议结构：

```text
Settings Tab
  -> SettingsView / AISettingsView
      -> Weather Enquiry / 天气查询
          - 保留 NavigationStack 返回能力
          - 保留 Tab/Settings 头部策略
          - 内容区展示天气查询大标题和卡片
```

实现要求：

```text
1. 移除或条件化天气页 `.hidesMainTabBarWhenPushed()`，按通用设置页策略显示 Tab/头部。
2. 页面顶部增加返回按钮，但不要只依赖自定义按钮；系统返回手势也必须可用。
3. 如果保留截图圆形返回按钮，应绑定 `dismiss()`，并与系统 back 不重复造成两个明显返回入口。
4. 导航标题可以使用 `天气查询` / `Weather Enquiry`，大标题可以在内容区显示。
5. 头部高度、安全区、状态栏不要被自定义背景遮挡。
```

## 4. UI 对齐范围

天气设置页内容仍按 `DEEPTUTORCHAT-000035` 的截图目标态，但本工单新增以下硬性要求：

```text
1. Provider 列表必须是三项：OpenWeather、Qweather、苹果天气 / AppleWeather。
2. 三项启动即可显示，不需要先点击“新增”。
3. AppleWeather 不能藏在“预留能力”导致用户找不到。
4. 如果 AppleWeather 当前未完成 WeatherKit 调用，行内必须显示不可启用原因或状态。
5. 页面头部必须有返回能力，并保留通用 Settings/Tab 上下文。
6. 即使 Enable Weather 关闭，Provider 列表仍必须显示，只是 switch 置灰或启用时报“请先启用天气”。
```

Provider 行展示建议：

```text
OpenWeather
  图标：openweather
  key 图标：显示
  switch：未配置 key/host 前不可启用或启用时报错

Qweather
  图标：qweather
  key 图标：显示
  switch：未配置 key/host 前不可启用或启用时报错

AppleWeather
  图标：apple / weather
  key 图标：不按普通 API Key 展示
  switch：WeatherKit 能力完成前不可启用；完成后走 Apple 天气授权/服务端配置校验
```

## 5. 工具调用对齐补充

三厂商可选后，工具调用必须按 active provider 分流：

```text
OPENWEATHER
  -> OpenWeatherProvider
  -> 支持 geocode/current/tomorrow forecast

QWEATHER
  -> QWeatherProvider
  -> 如本期未实现，设置页不可启用；如实现，则 WeatherGateway 分流到 QWeatherProvider

APPLEWEATHER
  -> WeatherKitProvider / AppleWeatherProvider
  -> 需要 WeatherKit entitlement/token/服务端代理能力
```

失败路径：

```text
1. 三厂商都未启用：`missingActiveProvider`。
2. Enable Weather=false：不开放天气工具或返回天气功能未启用。
3. active provider 未配置凭据：设置页应阻止，不应等到工具调用才失败。
4. AppleWeather 未完成 WeatherKit 能力：不能启用；如历史状态中已启用，启动迁移时必须关闭并提示。
```

## 6. 开发拆分

### Phase 1：初始三厂商灌库

```text
1. 在 `AISettingsDefaults.toolKeys` / seed catalog 中确保 QWEATHER、OPENWEATHER、APPLEWEATHER 三项存在。
2. 在 AISettings load/seed 阶段补齐老用户缺失项。
3. 做 company 去重与 WEATHERKIT -> APPLEWEATHER alias 兼容。
4. 保证首次启动即可在天气设置页看到三项。
5. 如果当前页面显示“暂无天气供应商”，加载完成后必须自动修复为三项列表。
```

### Phase 2：头部与 Tab 导航对齐

```text
1. 检查 `AISettingsView` 进入天气页时是否隐藏 TabBar。
2. 按通用 Settings 规则保留头部/Tab，不做孤立全屏页。
3. 增加或保留返回按钮，确保系统返回和自定义返回行为一致。
4. 验证状态栏、安全区、页面大标题不遮挡。
```

### Phase 3：三厂商 UI 状态

```text
1. Provider 列表按 Qweather / OpenWeather / AppleWeather 展示。
2. OpenWeather/Qweather 显示 key 图标与编辑入口。
3. AppleWeather 显示 WeatherKit/Apple 天气状态，不套普通 API Key 文案。
4. 三者只有一个可处于启用状态。
```

### Phase 4：工具调用分流

```text
1. WeatherProviderID 支持 QWEATHER、OPENWEATHER、APPLEWEATHER。
2. WeatherGateway 根据 active provider 分流。
3. 未实现 provider 禁止启用。
4. DeepTutorChat query_weather 使用 active provider 并记录 provider 日志。
```

## 7. 验收标准

### 7.1 初始配置验收

```text
1. 清空本地数据后首次启动，进入天气设置页可直接看到 Qweather、OpenWeather、AppleWeather。
2. 三项初始均为 isUsing=false。
3. 老用户升级后如果缺少任一项，会自动补齐。
4. 补齐不会覆盖用户已填写的 OpenWeather key 和 requestURL。
5. 本地数据中不会出现 WEATHERKIT 与 APPLEWEATHER 两条重复可选项。
6. 当前截图中的“暂无天气供应商”状态不得再出现，除非本地存储损坏且恢复失败，此时必须有错误提示和重建入口。
7. Enable Weather 关闭时仍能看到 OpenWeather、Qweather、苹果天气三项，只是不可启用或置灰。
```

### 7.2 头部导航验收

```text
1. 从 Settings / AI 设置进入天气查询页后，通用设置头部/Tab 上下文不丢失。
2. 页面可通过返回按钮返回上一层。
3. 系统返回手势可用。
4. 页面没有双重冲突的导航栏标题和自定义大标题。
5. 状态栏、顶部安全区、底部 TabBar 均不被遮挡。
```

### 7.3 工具调用验收

```text
1. 启用 OpenWeather 后，DeepTutorChat 天气问题走 OpenWeatherProvider。
2. Qweather 未实现时不可启用；实现后天气问题可走 QWeatherProvider。
3. AppleWeather 未完成 WeatherKit 能力时不可启用；完成后可走 Apple 天气。
4. 切换 active provider 后，DeepTutorChat 日志显示对应 provider。
5. 未启用任何 provider 时不编造天气。
```

## 8. 完成定义

本工单完成时必须满足：

```text
1. 三个天气厂商 QWEATHER、OPENWEATHER、APPLEWEATHER 启动后即可在设置页选择。
2. 初始三厂商配置本地持久化并支持老用户补齐迁移。
3. 天气设置页头部与主流设置页一致，不隐藏通用头部/Tab，并有明确返回按钮。
4. Provider 列表、启用规则、编辑入口和错误提示符合 HealthClient WeatherSettingView 语义。
5. DeepTutorChat 工具调用能按 active provider 分流，未配置或未支持时明确失败，不伪造天气。
```
