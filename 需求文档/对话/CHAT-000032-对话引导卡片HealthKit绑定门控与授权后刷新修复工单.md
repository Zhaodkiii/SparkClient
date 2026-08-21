# CHAT-000032 对话引导卡片 HealthKit 绑定门控与授权后刷新修复工单

## 背景

对话引导卡片健康数据滑块已改为页面实时读取数据，不再持久化 `metric_sections`。真机验证时发现两个问题：

1. 新建对话在当前成员未绑定苹果健康的情况下，仍会先触发 HealthKit 读取，导致系统授权弹窗提前出现。
2. 进入会话后点击「去绑定」并完成 HealthKit 授权，返回对话页面后运动、饮食滑块仍展示未授权，未自动刷新为实时数据。

科普问题生成流程保持不变，本工单只处理健康数据滑块。

## 当前日志结论

现有日志能看到：

- 新会话本地创建完成后，`thread.member_id` 已存在。
- 引导卡片插入前后有线程同步、消息拉取、成员 complete-data 拉取。
- 现有日志缺少引导卡片健康滑块的权限判定结果，无法直接确认“哪一次 build 触发了 HealthKit 读取”。

结合代码可确定一个直接问题：

- `EnsureChatGuideSystemMessageUseCase.execute(threadID:)` 插入首条 system 引导卡片时调用 `guideCardBuilder.build(memberID:)`，未显式传入 `healthDataAuthorized`，而 builder 默认值为 `true`。
- 因此未绑定成员的新建对话，在初始 payload 构建阶段仍会进入 HealthKit 读取分支。

结合代码还可判断第二个问题的高概率原因：

- 页面卡片当前使用 `.task(id: payload.memberID)` 加载实时滑块数据。
- 完成 HealthKit 绑定/授权后，`payload.memberID` 没变，卡片不会自动重新执行 `.task`。
- 因此页面仍保留之前的未授权滑块状态。

## 修复方案

### 1. 初始插卡前统一走 HealthDataAccessGate

修改 `EnsureChatGuideSystemMessageUseCase`：

- 新增 `HealthDataAccessGate` 依赖。
- 插入首条 system 引导卡片前调用：

```swift
await accessGate.checkAccess(for: .appleHealth, memberId: memberID)
```

- 仅当 `result.isGranted == true` 时，才允许 `ChatGuideCardPayloadBuilder` 读取 HealthKit。
- 未绑定、成员不匹配、未授权、设备不可用时，传入 `healthDataAuthorized: false`，滑块展示未授权/去绑定态。

### 2. 页面实时加载同样走 HealthDataAccessGate

修改 `ChatDetailViewModel.loadGuideMetricSections(memberID:)`：

- 不再用 `member.isSelfMember` 作为 HealthKit 读取条件。
- 改为复用 `HealthDataAccessGate.checkAccess`。
- 保证引导卡片、运动健康首页、AI 工具读取使用一致的绑定与授权判断。

### 3. 补齐身材管理 HealthKit 门控

`SparkHealthTool.fetchBodyManagementSummary(days:)` 内部会调用 `requestAuthorization()`。

因此 `ChatGuideCardPayloadBuilder.makeBodyManagementSection` 也必须接入 `healthDataAuthorized`：

- 未授权/未绑定时不调用 `fetchBodyManagementSummary`。
- 返回 `unauthorized` 状态和「去绑定」动作。

### 4. 授权完成返回对话页后刷新滑块

新增通知：

```swift
Notification.Name.chatGuideHealthBindingDidChange
```

绑定 sheet 关闭时发送通知：

```swift
NotificationCenter.default.post(name: .chatGuideHealthBindingDidChange, object: nil)
```

`ChatGuideMessageCardView` 订阅该通知：

- 收到后重新调用 `metricSectionsProvider(payload.memberID)`。
- 更新 `realtimeMetricSections`。
- 不回写消息 payload。
- 不触发科普问题生成。

## 临时日志

为真机排查新增以下单行日志：

```text
chat.guide.metrics.initial_access thread=<thread> member=<id|nil> granted=<true|false> reason=<reason>
chat.guide.metrics.page_access member=<id|nil> granted=<true|false> reason=<reason>
chat.guide.metrics.reload_start member=<id|nil> reason=<task|binding_changed>
chat.guide.metrics.reload_done member=<id|nil> reason=<task|binding_changed> states=movement:<state>,body:<state>,nutrition:<state>,medical:<state>
chat.guide.metrics.binding_sheet_closed
```

重点观察：

- 未绑定新建对话时，`initial_access granted=false reason=no_binding/member_not_bound`，且不应出现 HealthKit 系统授权弹窗。
- 页面首屏加载时，`page_access granted=false`，滑块展示「去绑定」。
- 完成绑定并关闭 sheet 后，应出现 `binding_sheet_closed`。
- 随后应出现 `reload_start reason=binding_changed` 和 `reload_done`。
- 若 `page_access granted=true` 但 `reload_done` 仍是 `movement:unauthorized`，问题在 builder 状态生成。
- 若绑定后仍 `page_access granted=false`，问题在设备绑定存储、账号隔离或 HealthKit 授权状态判断。

## 涉及文件

- `SparkClient/Projects/Features/Chat/Application/EnsureChatGuideSystemMessageUseCase.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift`
- `SparkClient/Projects/Features/Chat/Application/ChatGuideCardPayloadBuilder.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/Guide/ChatGuideMetricCarouselView.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/Guide/ChatGuideMessageCardView.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`
- `SparkClient/Projects/App/Sources/App/AppContainer.swift`

## 验收标准

1. 未绑定苹果健康的新建对话不弹 HealthKit 系统授权框。
2. 未绑定时运动、身材管理、饮食营养滑块不读取 HealthKit，展示未授权态与「去绑定」入口。
3. 完成绑定/授权并回到对话页后，引导卡片滑块自动刷新。
4. 健康滑块数据不写回 system message payload，不通过 CoreData 或服务端持久化。
5. 科普问题生成、兜底、点击发送流程不受影响。
