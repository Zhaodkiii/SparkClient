# DEEPTUTORCHAT-000032 Apple 天气查询回复口径与 DeepTutorChat 真实天气工具接入工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000032 |
| 工单类型 | P1 Apple/审核回复口径 + 天气工具真实数据源接入 + DeepTutorChat 工具链路验收 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 工具中枢目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub` |
| AI 设置目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 需要准备“Apple 天气查询”相关回复，同时 DeepTutorChat 的 `query_weather` 仍缺少真实天气供应商闭环 |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000008`、`DEEPTUTORCHAT-000011`、`DEEPTUTORCHAT-000012`、`DEEPTUTORCHAT-000030` |
| 核心约束 | 不能让模型假装已经查询天气；如未接真实天气源，应向 Apple/用户说明能力边界；如产品承诺支持天气查询，则必须让 `query_weather` 走真实 provider |

## 1. 本工单目标

本工单解决两件事：

```text
1. 为 Apple/审核或外部说明准备天气查询功能的准确回复口径。
2. 将 DeepTutorChat 中已开放的 `query_weather` 从“工具占位/路由说明”推进到“真实天气数据源接入并可验收”。
```

目标结果：

```text
1. Apple 回复不夸大能力，不声称已接入未完成的数据源。
2. DeepTutorChat 能识别“今天的天气怎么样”“北京今天下雨吗”等天气意图。
3. 城市不明确时先追问城市或使用已授权定位。
4. 城市明确时先 `query_location` 获取经纬度，再 `query_weather` 查询天气。
5. 工具失败时给出可行动错误，不让模型编造天气。
```

## 2. 当前现状

### 2.1 DeepTutorChat 已有天气意图与工具面

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorStructuredToolIntent.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorDomainToolExtensionResolver.swift
```

当前天气关键词包含：

```text
天气、气温、weather、下雨、温度、forecast、附近、路线、导航、定位、在哪、哪个城市、city
```

当前天气工具面：

```text
query_weather
query_location
get_current_location（仅在有定位权限时挂载）
```

结论：

```text
DeepTutorChat 已经能把天气问题识别为 weather_location 领域意图，并给模型开放天气/位置相关工具。
```

### 2.2 query_weather Schema 已存在

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift
```

当前 `query_weather` 参数：

```text
latitude: number
longitude: number
timeRange: string
```

结论：

```text
工具协议要求模型提供经纬度，因此城市文本不能直接进入 `query_weather`。
需要 `query_location` 或系统定位先把城市转换为坐标。
```

### 2.3 天气工具当前仍属于外部工具占位风险

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Shared.swift
```

现有注释指出：

```text
联网/网页读取优先走本地搜索网关；地图/天气/日历等外部工具暂按 `toolKeys` 返回路由说明。
```

总领文档也记录：

```text
位置、天气、日历等外部工具仍占位。
```

结论：

```text
如果 Apple 或用户询问“天气查询是否可用”，当前不能简单回复“已完整支持实时天气查询”。
需要区分：聊天意图和工具流程已有，真实天气 provider 数据源接入仍需完成。
```

### 2.4 AI 设置里已有 OpenWeatherMap 工具 Key 种子

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
```

当前 `toolKeys` 种子包含：

```text
name: OpenWeatherMap
company: OPENWEATHER
requestURL: https://api.openweathermap.org/data/2.5/weather
toolClass: weather
isUsing: false
```

结论：

```text
项目已预留天气供应商配置位，但还需要设置入口、Key 保存、provider 适配和 ToolHub 执行链路闭环。
```

## 3. Apple 回复口径

### 3.1 如果当前版本尚未上线真实天气数据源

建议回复：

```text
当前版本的 AI 对话已具备天气意图识别和城市追问流程，但实时天气查询能力仍处于接入阶段。应用不会在未连接真实天气数据源时向用户展示伪造的实时天气结果。我们会在接入并验证天气服务供应商后，再开放完整的实时天气查询体验。
```

中文内部口径：

```text
能识别天气问题，也能引导用户提供城市；但如果真实 provider 未配置或请求失败，必须明确提示无法获取实时天气，而不是用模型知识猜测。
```

### 3.2 如果本工单完成并已接入真实天气源

建议回复：

```text
应用内 AI 对话支持天气查询。用户可以询问某个城市或当前位置的天气；如缺少城市或定位授权，应用会先请求用户提供位置。天气数据通过用户在设置中启用的天气服务供应商获取，AI 仅基于返回的实时结果进行总结，不会凭空生成实时天气信息。
```

### 3.3 隐私说明要点

对 Apple/审核说明时需要包含：

```text
1. 只有用户主动询问天气时才触发天气查询。
2. 当前位置天气需要用户授权定位；未授权时改为询问城市。
3. 位置仅用于本次天气查询，不用于后台持续追踪。
4. 天气供应商 API Key 在本地设置中管理，日志不输出密钥。
5. 查询失败时展示失败原因，不伪造实时天气。
```

## 4. 产品目标流程

### 4.1 城市明确

示例：

```text
用户：北京今天的天气怎么样？
```

目标流程：

```text
DeepTutorStructuredToolIntent -> weather_location
DeepTutorDomainToolExtensionResolver -> query_location + query_weather
模型调用 query_location(keyword="北京")
ToolHub 返回北京经纬度
模型调用 query_weather(latitude, longitude, timeRange="today")
ToolHub 返回真实天气
助手基于工具结果回复
```

### 4.2 城市不明确

示例：

```text
用户：今天的天气怎么样？
```

目标流程：

```text
如果已有定位权限：
  get_current_location -> query_weather

如果没有定位权限：
  ask_user_question 询问城市
  用户选择/输入城市后
  query_location -> query_weather
```

### 4.3 Apple 天气类提问

示例：

```text
用户：Apple 天气显示今天下雨，你帮我查一下上海天气。
用户：苹果天气说明天北京有雨吗？
```

目标处理：

```text
1. “Apple/苹果天气”在这里通常是用户引用的信息源或比较对象，不应误判为 Apple 公司新闻。
2. 如果用户问的是实时天气，仍走 weather_location 工具链路。
3. 如果用户问的是“Apple Weather 这个产品/API”，则走普通知识问答或联网搜索，不调用 query_weather。
```

## 5. 技术实施方案

### 5.1 天气供应商配置

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings
```

要求：

```text
1. 在设置中暴露外部工具/天气供应商配置入口，至少支持 OpenWeatherMap。
2. 保留后续接入 Apple WeatherKit 的扩展位，但不要默认承诺 WeatherKit 可用。
3. `toolClass=weather` 的 active provider 必须唯一或有明确优先级。
4. 启用非内置天气 provider 前必须校验 API Key 和 endpoint。
```

### 5.2 ToolHub 执行真实 query_weather

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Shared.swift
```

要求：

```text
1. `query_weather` 不再只返回路由说明。
2. 从 AISettings 当前 snapshot 中读取 `toolClass=weather && isUsing=true` 的 provider。
3. 根据 provider 组装请求。
4. 返回标准化天气结果：地点、时间、温度、体感温度、天气现象、降水概率、湿度、风力、数据源。
5. 请求失败时返回结构化错误。
```

建议新增模型：

```text
WeatherRuntimeConfig
WeatherProviderID
WeatherGateway
WeatherResult
WeatherRuntimeError
```

### 5.3 城市解析和天气查询串联

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorDomainToolExtensionResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift
```

要求：

```text
1. 城市明确时必须允许 `query_location` 和 `query_weather`。
2. 城市不明确且无定位权限时，优先 `ask_user_question`，不要让模型直接编造坐标。
3. `query_weather` schema 可增加可选 `locationName` 仅用于展示，但真实查询仍以经纬度为准。
4. AskUser resume 后必须恢复 `query_location/query_weather`，避免重复追问城市。
```

### 5.4 Apple WeatherKit 扩展边界

如果后续决定接 Apple WeatherKit，需要另行确认：

```text
1. Apple Developer 账号能力与 WeatherKit entitlement。
2. Token/JWT 生成方式。
3. 客户端直连还是服务端代理。
4. 请求配额和失败降级。
5. 中国大陆地区可用性和备用 provider。
```

本工单 MVP 建议：

```text
先接 OpenWeatherMap 或已有可用天气供应商，保留 WeatherKit provider id，不阻塞基础天气查询验收。
```

## 6. 日志与脱敏

新增日志建议：

```text
deeptutor.weather.intent conversation=<id> input=<redacted> matched=true locationHint=<city|none>
deeptutor.weather.config_resolved conversation=<id> provider=OPENWEATHER keyID=<uuid> endpointHost=<host>
deeptutor.weather.query_start conversation=<id> lat=<rounded> lon=<rounded> timeRange=today
deeptutor.weather.query_result conversation=<id> provider=OPENWEATHER condition=<text> temp=<value> elapsedMs=<n>
deeptutor.weather.query_failed conversation=<id> provider=OPENWEATHER error=<type>
```

脱敏要求：

```text
1. 不输出天气 API Key。
2. 经纬度日志只保留约 2 位小数，避免精确定位泄露。
3. 不输出完整 URL query。
4. Apple/WeatherKit token 不得进入日志。
```

## 7. 测试计划

### 7.1 单元测试

建议新增/更新：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/Tests/DeepTutorChat/DeepTutorToolPolicyResolverTests.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/AI/WeatherRuntimeConfigResolverTests.swift
```

测试项：

```text
1. “北京今天的天气”命中 weather_location。
2. “Apple 天气显示上海会下雨吗”命中 weather_location，而不是 web_search 优先。
3. “Apple WeatherKit 是什么”不命中 query_weather，走知识问答/联网搜索。
4. 无定位权限且无城市时，先 ask_user_question。
5. AskUser 回答城市后，恢复 query_location/query_weather。
6. weather provider 未配置时返回可读错误。
7. API Key 不出现在日志和 debug export。
```

### 7.2 手工验收

验收用例：

```text
1. 北京今天的天气怎么样？
2. 今天的天气怎么样？
3. Apple 天气说上海今天下雨，你帮我确认一下。
4. Apple WeatherKit 是什么？
5. 关闭天气供应商后再问天气。
```

通过标准：

```text
1. 明确城市问题直接进入 query_location/query_weather。
2. 未明确城市时不编造天气，先追问或请求定位。
3. Apple 天气作为天气来源引用时，不误判成 Apple 公司新闻。
4. Apple WeatherKit 产品/API 问题不调用天气查询工具。
5. 天气供应商关闭或失败时，回答清楚说明无法获取实时天气。
```

## 8. 完成定义

本工单完成时必须满足：

```text
1. 已形成可对 Apple/审核使用的天气查询回复口径。
2. `query_weather` 有真实 provider 执行链路或明确降级说明。
3. DeepTutorChat 天气意图、城市追问、AskUser resume、真实查询全链路可验收。
4. 日志可定位 provider 和失败原因，但不泄露 API Key 或精确位置。
5. Apple WeatherKit 与普通天气查询的边界清楚，不混淆“Apple 公司/API 问答”和“实时天气查询”。
```
