# DEEPTUTORCHAT-000052 AI 天气设置页天气预览窗口与定位权限闭环工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000052 |
| 工单类型 | P1 AI 设置天气工具预览窗口 + 定位权限闭环 + Apple WeatherKit 数据来源日志 |
| 当前范围 | 已按本工单完成 Swift 实现，保留本文作为验收说明 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标设置页 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIWeatherToolSettingsView.swift` |
| 建议新增组件目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/WeatherPreview/` |
| 运行时依赖 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Weather`、`/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Location/SparkLocationService.swift` |
| DreamHua 参考包 | `/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Component/WeatherKit/UI/` |
| 创建日期 | 2026-08-11 |
| 触发问题 | 用户在 AI 天气设置页开启天气并启用供应商后，应直接看到一个真实天气预览窗口；没有定位权限时，组件内要给出清晰状态和跳转系统设置入口 |
| 关联工单 | `DEEPTUTORCHAT-000032`、`DEEPTUTORCHAT-000034`、`DEEPTUTORCHAT-000035`、`DEEPTUTORCHAT-000036` |
| 核心约束 | 预览窗口必须是独立组件；天气数据来自真实 active provider；Apple 天气必须标记数据来源并产生日志；无定位权限时不能伪造天气或静默失败 |

## 0.1 实施记录

| 字段 | 内容 |
| --- | --- |
| 实施日期 | 2026-08-11 |
| 新增组件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/WeatherPreview/AIWeatherPreviewPanel.swift` |
| 接入位置 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIWeatherToolSettingsView.swift` |
| 定位能力补充 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Location/SparkLocationService.swift` |
| 本地化补充 | `en.lproj/Localizable.strings`、`zh-Hans.lproj/Localizable.strings`、三语 `InfoPlist.strings` |
| 构建结果 | 天气相关文件已通过 Swift 编译；完整工程当前被任务模块既有 `TaskCenterViewController.swift:64` 参数不匹配阻断 |

## 1. 背景与目标

当前 `AIWeatherToolSettingsView` 已具备天气总开关、供应商列表、供应商编辑和功能列表，但用户开启天气后缺少即时反馈：无法确认当前 provider 是否真的可用，也无法确认定位权限是否满足“当前位置天气”查询。

本工单要求在 `AIWeatherToolSettingsView` 中增加一个天气预览窗口：

```text
当 Enable Weather = true
并且存在已启用且可用的 weather provider
进入页面后自动打开/展示天气预览窗口
```

预览窗口目标：

```text
1. 先检查定位权限。
2. 无权限时在组件内部展示“无法获取位置”，并提供跳转系统设置开启位置的入口。
3. 已授权时获取用户当前位置。
4. 使用当前 active weather provider 查询实时天气和短期预报。
5. UI 样式参考 DreamHua 天气组件，但按 SparkClient 当前 AI 设置页视觉做优化。
6. Apple WeatherKit 场景必须展示并记录天气数据来源。
```

## 2. 参考范围

DreamHua 天气组件参考：

```text
/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Component/WeatherKit/UI/WeatherWeekChoose.swift
/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Component/WeatherKit/UI/DailyWeather.swift
/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Component/WeatherKit/UI/WeekModule.swift
/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Component/WeatherKit/UI/TenDayForcastView.swift
/Users/hua/Documents/DreamHealth/参考包/DreamHua/DreamHua/View/Map/Trail/UI/TrailHomepage.swift
```

需要吸收的点：

```text
1. 顶部横向日期选择条：日期 + 星期 + 选中胶囊。
2. 主天气区：大温度、天气状态、H/L、风速、日出、日落。
3. WeatherKit 场景展示 `Apple Weather` 数据来源和 Legal Attribution 入口。
```

需要优化的点：

```text
1. DreamHua `fetchCurrentWeek()` 当前只生成 6 天，SparkClient 应实现 7 天预览。
2. 日期格式使用 `yyyy`，避免 `YYYY` 跨年错误。
3. 不在 SwiftUI View 内散落 WeatherService/WeatherGateway 状态；预览组件通过独立 view model 或 loader 管理状态。
4. forecast 下标必须做 bounds check。
5. 组件要覆盖 loading、permissionDenied、providerMissing、providerDisabled、success、failed 状态。
```

## 3. 触发与展示规则

### 3.1 自动展示条件

进入 `AIWeatherToolSettingsView` 时满足以下条件，直接展示天气预览窗口：

```text
1. `viewModel.snapshot.weatherToolPreferences.useWeather == true`
2. `WeatherRuntimeConfigResolver.activeWeatherKey(from: viewModel.snapshot) != nil`
3. active provider 已通过 `weatherProviderValidationError` 校验
```

展示位置建议：

```text
introCard
enableWeatherCard
providerCard
weatherPreviewCard
functionListCard
```

当用户在页面内切换 Enable Weather 或 provider：

```text
1. 关闭 Enable Weather：预览窗口收起或变为“天气未启用”轻量状态。
2. 开启 Enable Weather 但无 active provider：显示“请选择天气供应商”状态。
3. 启用 provider 成功：自动打开预览并刷新天气。
4. provider 配置变更：根据 `weatherConfigRevision` 重新加载。
```

### 3.2 不允许的行为

```text
1. 不允许使用固定城市、固定经纬度或 mock 数据作为真实预览。
2. 不允许总开关未开时自动请求定位。
3. 不允许 provider 未启用时调用天气接口。
4. 不允许 WeatherKit 失败后用模型或静态文案生成天气。
5. 不允许在日志中输出完整 API Key、WeatherKit token、用户精确坐标。
```

## 4. 组件设计

建议新增独立组件，不把预览状态直接堆在 `AIWeatherToolSettingsView` 主文件中：

```text
AIWeatherPreviewPanel
AIWeatherPreviewViewModel
AIWeatherPreviewPermissionState
AIWeatherPreviewDaySelector
AIWeatherPreviewCurrentCard
AIWeatherPreviewAttributionFooter
```

推荐目录：

```text
SparkClient/Projects/Features/AISettings/Presentation/Preferences/WeatherPreview/
```

组件输入：

```swift
struct AIWeatherPreviewPanel: View {
    let snapshot: AISettingsSnapshot
    let configRevision: WeatherRuntimeConfigRevision
}
```

状态模型建议：

```text
idle
disabled
missingProvider
needsLocationPermission
locationDenied
loadingLocation
loadingWeather
loaded(WeatherPreviewModel)
failed(message)
```

数据模型建议：

```text
WeatherPreviewModel
  providerName
  sourceName
  locationName
  observedAt
  currentTemperatureC
  condition
  highTemperatureC
  lowTemperatureC
  windSpeedText
  sunriseText
  sunsetText
  days: [WeatherPreviewDay]
```

## 5. 定位权限闭环

### 5.1 权限检查

预览组件进入时先读取定位权限：

```text
authorizedWhenInUse / authorizedAlways
  -> 调用 `SparkLocationService.currentCoordinate()`
  -> 查询天气

notDetermined
  -> 组件内展示“需要位置权限以预览当前位置天气”
  -> 用户点击后触发系统定位授权请求

denied / restricted
  -> 组件内展示“无法获取位置”
  -> 提供“去系统设置开启位置”按钮
```

当前 `SparkLocationService.currentCoordinate()` 在 `notDetermined` 下会抛错，不会主动 request authorization。本工单要求为设置页预览补齐授权请求入口，可以新增面向 UI 的定位权限协调器，或扩展现有 Location service，但不要破坏聊天工具链路的现有语义。

### 5.2 无权限 UI

无权限状态必须在天气预览组件内部展示，不使用全局 alert 作为唯一反馈：

```text
标题：无法获取位置
说明：开启位置权限后，可以预览当前位置的实时天气和未来天气。
主按钮：去设置开启
次按钮：稍后再说 / 重新检查
图标：location.slash 或 cloud.slash
```

跳转设置要求：

```text
UIApplication.openSettingsURLString
```

返回 App 后：

```text
1. 监听 scenePhase 变为 active。
2. 重新检查定位权限。
3. 如果已授权，自动拉取当前位置并刷新预览。
```

## 6. 天气预览 UI 要求

视觉参考 DreamHua，但需要适配 SparkClient 当前天气设置页的浅灰背景、白色圆角卡片和 iOS 设置体验。

结构建议：

```text
天气预览卡片
  顶部：当前位置 / provider 状态 / 刷新按钮
  日期选择条：7 天横向滚动，黑色或深色胶囊选中态
  主天气：大温度 + 天气状态 + 图标
  指标区：H/L、风速、日出、日落
  底部：数据来源与 attribution
```

具体要求：

```text
1. 日期条必须显示 7 天，今天默认选中。
2. 选中态参考 DreamHua 黑色胶囊，但尺寸和间距要适配 SparkClient 卡片宽度。
3. 主温度字号建议 52-64，保留强视觉锚点。
4. 天气图标可用 SF Symbols，颜色随天气状态做轻微区分，但不要做一屏纯蓝。
5. 卡片圆角、阴影、间距沿用 `WeatherEnquiryPalette`，避免另起一套冲突视觉。
6. 加载态用 ProgressView + “正在获取当前位置天气”。
7. 失败态展示错误原因和“重试”按钮。
```

## 7. 数据来源与 Apple WeatherKit 日志

### 7.1 UI 数据来源

所有 provider 都要在预览底部显示数据来源：

```text
OpenWeather：Weather data: OpenWeather
QWeather：Weather data: QWeather
Apple Weather：Weather data: Apple Weather
```

当 provider 是 Apple WeatherKit 时，必须显示：

```text
Apple Weather
Legal Attribution
```

`Legal Attribution` 链接：

```text
https://weatherkit.apple.com/legal-attribution.html
```

### 7.2 日志要求

Apple WeatherKit 查询成功、失败、降级都需要有结构化日志，至少包含：

```text
event: ai_weather_preview.apple_weather.query
provider: APPLEWEATHER / WEATHERKIT
source: Apple Weather
result: success / failure
timeRange
locationPrecision: rounded
revision
errorCode: optional
```

日志禁止包含：

```text
1. WeatherKit token / JWT
2. 第三方 provider API Key
3. 用户完整精确经纬度
4. HTTP response body 原文中的敏感字段
```

坐标日志建议：

```text
纬度、经度最多保留 2 位小数，或仅记录 geohash/city 级别信息。
```

## 8. 运行时接入要求

预览组件应复用现有天气运行时，不单独写一套 provider 请求：

```text
1. 通过 `WeatherRuntimeConfigResolver.resolve(from:)` 获取 active provider 配置。
2. 通过 `WeatherGateway.queryWeather(...)` 查询天气。
3. 当前位置通过 `SparkLocationService` 或新增 UI 权限协调器获取。
4. provider 切换、总开关变化、配置 revision 变化后刷新预览。
5. 错误消息使用 `WeatherRuntimeError.localizedDescription` 或本地化文案映射。
```

Apple WeatherKit 要求：

```text
1. 不需要 API Key。
2. iOS 16 以下不可启用或不可预览，并给出系统版本说明。
3. 如果 WeatherKit entitlement 或服务不可用，展示明确失败态。
4. 不允许在客户端硬编码 WeatherKit 私钥或长期 token。
```

## 9. 本地化与权限文案

需要新增本地化 key，至少覆盖简体中文、繁体中文、英文：

```text
ai_settings.weather.preview.title
ai_settings.weather.preview.loading_location
ai_settings.weather.preview.loading_weather
ai_settings.weather.preview.disabled
ai_settings.weather.preview.missing_provider
ai_settings.weather.preview.location_unavailable_title
ai_settings.weather.preview.location_unavailable_message
ai_settings.weather.preview.open_settings
ai_settings.weather.preview.retry
ai_settings.weather.preview.source_format
ai_settings.weather.preview.apple_legal_attribution
```

InfoPlist 定位说明当前偏向“对话中搜索附近地点和规划路线”。本工单验收时需要确认文案覆盖天气预览用途：

```text
Look健康需要使用你的位置，用于搜索附近地点、规划路线和预览当前位置天气。
```

## 10. 验收标准

功能验收：

```text
1. Enable Weather 关闭时，进入天气设置页不请求定位，不调用天气接口。
2. Enable Weather 开启但没有 active provider 时，展示“请选择天气供应商”状态。
3. Enable Weather 开启且 provider 启用时，进入页面直接展示天气预览窗口。
4. 定位权限未决定时，组件内能触发授权请求。
5. 定位权限被拒绝时，组件内展示“无法获取位置”，并可跳转系统设置。
6. 从系统设置开启位置并返回 App 后，预览自动刷新。
7. 已有定位权限时，预览展示当前位置天气。
8. 切换 7 天日期条时，天气详情同步切换，且不会越界崩溃。
9. provider 切换后，预览使用新 provider 刷新。
10. 天气请求失败时展示失败态和重试按钮，不展示旧数据冒充新结果。
```

Apple WeatherKit 验收：

```text
1. Apple Weather 预览底部展示 `Apple Weather` 和 Legal Attribution。
2. Apple Weather 查询成功日志包含 source/provider/result/revision，不含 token、API Key 和精确坐标。
3. Apple Weather 查询失败日志包含失败原因，不输出敏感 response。
4. iOS 16 以下 Apple Weather 不进入真实查询路径。
```

UI 验收：

```text
1. 卡片风格与 `AIWeatherToolSettingsView` 当前浅灰背景、白卡、蓝色强调一致。
2. 日期选择条参考 DreamHua 的黑色胶囊选中态，但生成 7 天。
3. 大温度、天气图标、H/L、风速、日出日落布局在小屏不重叠。
4. 动态字体下文本不溢出按钮或卡片。
5. 加载、失败、无权限、成功四种状态都在预览组件内部完成。
```

## 11. 测试建议

单元测试：

```text
1. `AIWeatherPreviewViewModel` 状态转移：disabled / missingProvider / needsPermission / denied / loaded / failed。
2. 日期生成固定为 7 天，跨年使用 `yyyy`。
3. forecast 下标选择超出范围时返回安全失败态。
4. Apple WeatherKit 日志脱敏：不包含 token、key、完整经纬度。
```

集成测试：

```text
1. 使用 fake `WeatherGateway` 验证 active provider 查询参数。
2. 使用 fake location authorization provider 验证权限状态 UI。
3. `weatherConfigRevision` 变化后触发刷新。
4. Enable Weather 关闭时不触发 location/weather 调用。
```

手工验收：

```text
1. 首次安装，未授予定位，进入天气设置页，开启天气和供应商后看到权限引导。
2. 拒绝定位后，预览卡显示无法获取位置和去设置按钮。
3. 系统设置打开定位后回到 App，自动出现天气预览。
4. OpenWeather/QWeather/AppleWeather 分别启用时，数据来源展示正确。
5. 断网或 provider key 错误时，错误状态可读且可重试。
```

## 12. 实施拆分建议

建议按以下提交拆分：

```text
1. 新增 WeatherPreview 独立组件与状态模型，不接真实网络，先接 fake preview loader。
2. 接入定位权限协调器和系统设置跳转。
3. 接入 WeatherRuntimeConfigResolver + WeatherGateway 真实查询。
4. 完成 DreamHua 风格日期条和主天气卡视觉优化。
5. 补齐 Apple WeatherKit attribution 和结构化日志。
6. 补本地化、单元测试和手工验收截图。
```

## 13. 完成定义

本工单完成后，用户在 AI 设置的天气页面里，不需要进入聊天就能验证天气工具是否真实可用：

```text
开启天气 + 开启供应商
  -> 立即看到当前位置天气预览

没有定位权限
  -> 在组件内看到无法获取位置和去设置入口

Apple Weather
  -> 明确显示 Apple Weather 数据来源
  -> 记录脱敏日志
  -> 不伪造、不泄密、不绕过 attribution
```
