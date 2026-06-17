# iOS 用药模块日常工单需求文档

> 文档性质：需求文档 + 详细设计文档。本文仅记录 `Medications/MedicationExecutionCenter` 用药执行中心的日常工单需求、现状缺口、详细设计、交互要求和验收标准，不直接修改代码。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICATION-EXECUTION-000001` | 用药执行中心多日进度圆环与记录窗口优化 | 需求设计中 | 参考 iOS 健康“用药”效果，检查并补齐 `MedicationExecutionCenter` 未完整实现部分；重点优化顶部日期进度圆环 View，使其展示选中日前后多天用药进度，并按“当前选中日前后 4 天”加载记录数据 |
| `MEDICATION-EXECUTION-000002` | 用药本地通知闭环详细设计 | 需求设计中 | 基于 `用药通知需求讨论文档.md` 已确认结论，首版只做客户端本地通知：计划变更同步通知、离线提醒、点击通知走冷启动目标页面公共调度、切换成员并打开用药记录 Sheet、打卡后清理当前剂次通知、通用设置医疗隐私开关 |
| `MEDICATION-EXECUTION-000003` | 用药通知查看与管理页 | 需求设计中 | 在服药计划列表右上角增加“已有通知”入口，查看本机已注册/已送达用药本地通知，支持补齐通知、取消单条、清除全部；参考 HealthClient 通知管理页，但落地需符合 SparkClient 的本地通知、LaunchIntent、L10n 与 Home 依赖架构 |
| `MEDICATION-EXECUTION-000004` | 共享成员用药通知协同详细设计 | 需求设计中 | 基于 `MEDICATION-NOTIFICATION-000002`，落地非本人成员用药提醒归属判断、成员分享优先流程、服务端开启提醒计划汇总接口、计划级他人本机提醒授权登记、公共健康资源变更 APNs 告知、客户端清理本地 consent 并统一走服务端授权 |
| `MEDICATION-EXECUTION-000005` | 用药通知计划级服务端授权收敛改造 | 需求设计中 | 在 `000004` 基础上进一步收敛为“只认服务端计划级授权”方案：授权粒度精确到 `medication_plan_id`，客户端删除 `MedicationReminderConsentStore` 业务依赖，授权状态挂到 `RemoteMedicationPlan` 当前用户视角字段中，通过现有用药计划保存/查询链路维护，不再新增独立授权查询接口 |
| `MEDICATION-EXECUTION-000006` | 用药计划编辑页提醒开关与旧协同流程收敛讨论 | 需求讨论中 | 围绕 `MedicationPlanStepperView` 的确认页协同提醒模块改造成开关：新增/编辑默认关闭，服务端编辑回填历史授权状态，本地编辑不展示；保存成功后按计划 ID 异步同步授权/取消授权；同时清理旧的分享、本机提醒协同后置处理流程 |
| `MEDICATION-EXECUTION-000007` | 用药计划编辑页提醒开关与授权同步详细设计 | 需求详细设计中 | 基于 `000006` 的确认结论，输出可落地的客户端/服务端详细设计：确认页保留邀请他人通知并引入本机提醒开关、服务端编辑默认回填历史授权、保存成功后按计划 ID 异步同步授权、清理旧 post-save 流程、定义接口入参、返回字段、日志与验收标准 |

## 工单 `MEDICATION-EXECUTION-000001`：用药执行中心多日进度圆环与记录窗口优化

### 工单状态

需求设计中。

## 1. 背景

当前用药执行中心路径：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter
```

现有模块已经具备基础能力：

| 能力 | 当前情况 |
| --- | --- |
| 页面入口 | `MedicationExecutionCenterPage` 已提供用药执行中心页面 |
| 日期切换 | 顶部 `dateStrip` 已支持横向滚动日期条，并有居中吸附逻辑 |
| 日期范围 | `dateStripDays` 当前生成 `Date()` 前后 45 天，共 91 天 |
| 计划剂次计算 | `MedicationExecutionPlanner.scheduledDoses(...)` 可按日期、计划和记录计算当天剂次 |
| 进度计算 | `MedicationExecutionPlanner.progress(...)` 可按日期计算完成比例 |
| 记录加载 | `loadRecords(for:preferInitialRecords:)` 当前按单日请求服药记录 |
| 记录保存 | `saveSelections(...)` 已支持新增或更新用药记录 |
| 待记录卡片 | `MedicationExecutionPendingCard` 已按时间分组展示待记录剂次 |
| 已记录卡片 | `MedicationExecutionCompletedGroup` 已展示已完成或跳过记录 |
| 按需用药 | `MedicationExecutionAsNeededCard` 已提供入口 |

本工单参考图片：

```text
/Users/hua/Downloads/IMG_2464.PNG
/Users/hua/Downloads/IMG_2463.PNG
```

参考效果是 iOS 健康“用药”页面：顶部日期条不仅展示当前选中日，还展示多个连续日期的圆形进度状态。日期被选中时，星期文本上方或附近存在选中态；未选中的日期圆环仍能体现该日完成进度，例如半圆、整圆、空圆。

## 2. 当前缺口

### 2.1 多日圆环数据不完整

当前 `MedicationExecutionCenterPage` 只有一个 `records` 状态：

```swift
@State private var records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
```

页面切换日期时，`loadRecords(for:preferInitialRecords:)` 只加载选中日 `[start, end)` 的记录，并直接覆盖 `records`。

这会导致顶部 `dateStrip` 中每个日期调用：

```swift
MedicationExecutionPlanner.progress(
    plans: medicationPlans,
    medicineBoxes: medicineBoxes,
    records: records,
    on: item.date,
    calendar: calendar
)
```

实际只能用当前选中日的记录去计算所有日期的圆环。结果是：

1. 选中日进度相对准确。
2. 非选中日期缺少该日真实记录，圆环进度不可靠。
3. 顶部日期条无法稳定体现“多天用药进度”。
4. 保存记录后只能更新当前 `records`，相邻日期圆环不会形成缓存窗口。

### 2.2 圆环 View 与参考图不一致

当前 `MedicationExecutionDateDot` 的状态圆点尺寸为 `18 x 18`，未选中态使用描边圆 + `trim` 环形进度：

```swift
Circle()
    .stroke(Color(uiColor: .systemGray4), lineWidth: 2)

Circle()
    .trim(from: 0, to: clampedProgress)
    .stroke(Color(uiColor: .systemTeal), style: StrokeStyle(lineWidth: 4, lineCap: .round))
```

参考图表现更接近“填充式圆形进度”：

1. 日期项整体尺寸更大。
2. 空状态是浅灰实心圆。
3. 完成比例以蓝绿色填充面积表达，例如半圆、整圆。
4. 选中日期的星期文字有黑底白字圆形标记。
5. 标题下方有黑色三角指示当前中心日期。
6. 横向日期条两侧可露出相邻日期，形成连续滚动的多日上下文。

当前 UI 的小尺寸环形描边与参考图差异明显，且选中态只展示一个小圆点，不足以表达参考图中的多日进度圆环。

### 2.3 加载策略未按“前后 4 天”设计

用户要求：

```text
前几天的加载策略：只加载当前选中的前后 4 天的用药，在进度圆环内体现用药。
```

当前实现没有“日期窗口缓存”概念，每次选择日期只拉取当天记录。需要改为：

```text
选中日 - 4 天 <= 需要加载的记录日期 < 选中日 + 5 天
```

共覆盖 9 天：前 4 天、选中日、后 4 天。

## 3. 目标

### 3.1 核心目标

1. 顶部日期进度圆环 View 参考 iOS 健康用药效果重做视觉。
2. 日期条中每个日期都能展示该日期的用药完成进度。
3. 页面只加载当前选中日前后 4 天的用药记录，用于驱动多日圆环。
4. 选择不同日期时，待记录与已记录区域展示当前选中日内容。
5. 切换日期时，如果新选中日已在缓存窗口内，不重复发起网络请求。
6. 切换日期超出当前缓存窗口时，重新加载新选中日前后 4 天记录。
7. 保存用药记录后，当前选中日列表和对应日期圆环立即更新。
8. 保持现有服药计划、药箱图片、按需用药、记录保存接口不变。

### 3.2 非目标

1. 不新增服务端接口。
2. 不修改 `RemoteMedicationRecord` 数据结构。
3. 不修改服药计划创建、药箱、处方详情等页面。
4. 不实现 iOS 健康完整用药模块的所有功能，例如药物相互作用、提醒权限设置、共享 Tab。
5. 不改变服务端用药记录保存规则。
6. 不做离线持久化缓存，第一期只做页面内内存缓存。

## 4. 影响范围

### 4.1 主要文件

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionCenterPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionDateStrip.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionPlanner.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionModels.swift
```

### 4.2 关联接口

现有接口已满足窗口查询：

```swift
func listMedicationRecords(
    memberID: Int? = nil,
    planID: Int? = nil,
    status: String? = nil,
    scheduledFrom: Date? = nil,
    scheduledTo: Date? = nil
) async throws -> [SparkMedicalSyncAPI.RemoteMedicationRecord]
```

建议复用 `scheduledFrom` 和 `scheduledTo`：

```text
scheduledFrom = startOfDay(selectedDate - 4 天)
scheduledTo = startOfDay(selectedDate + 5 天)
```

## 5. 详细设计

### 5.1 页面状态设计

将当前单日记录状态升级为窗口记录缓存。

建议新增页面状态：

```swift
@State private var recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]] = [:]
@State private var loadedWindow: ClosedRange<Date>?
@State private var loadingWindowID: String?
```

说明：

| 状态 | 职责 |
| --- | --- |
| `recordsByDayID` | 按日期 ID 缓存窗口内记录，日期 ID 复用 `MedicationExecutionDateItem.id(for:calendar:)` |
| `loadedWindow` | 记录当前已加载的日期窗口，覆盖选中日前后 4 天 |
| `loadingWindowID` | 避免快速滑动日期条时重复加载同一窗口 |

保留或替换现有 `records` 的方式：

1. 推荐替换为计算属性 `selectedDayRecords`，减少状态重复。
2. 如果为降低改动风险保留 `records`，则它只能作为当前选中日派生值，不再作为日期条进度的唯一数据源。

推荐计算属性：

```swift
private var selectedDayRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord] {
    recordsByDayID[MedicationExecutionDateItem.id(for: selectedDayStart, calendar: calendar)] ?? []
}
```

`scheduledDoses`、`pendingDoses`、`completedDoses` 改用 `selectedDayRecords`。

### 5.2 日期窗口计算

新增窗口计算方法：

```swift
private func recordWindow(for day: Date) -> (start: Date, endExclusive: Date) {
    let dayStart = calendar.startOfDay(for: day)
    let start = calendar.date(byAdding: .day, value: -4, to: dayStart) ?? dayStart
    let end = calendar.date(byAdding: .day, value: 5, to: dayStart) ?? dayStart.addingTimeInterval(5 * 86_400)
    return (start, end)
}
```

窗口范围解释：

| 日期 | 是否加载 | 用途 |
| --- | --- | --- |
| 选中日前第 5 天及更早 | 不加载 | 日期条可显示空/未知态，不进入本次数据窗口 |
| 选中日前第 4 天 | 加载 | 展示圆环进度 |
| 选中日前第 1 天 | 加载 | 展示圆环进度 |
| 选中日 | 加载 | 展示列表和圆环进度 |
| 选中日后第 1 天 | 加载 | 展示圆环进度 |
| 选中日后第 4 天 | 加载 | 展示圆环进度 |
| 选中日后第 5 天及以后 | 不加载 | 日期条可显示空/未知态，不进入本次数据窗口 |

### 5.3 窗口加载流程

将 `loadRecords(for:preferInitialRecords:)` 改造为 `loadRecordWindow(centeredAt:preferInitialRecords:)`。

流程：

```text
进入页面
  -> 以今天为中心计算 [-4, +4] 日期窗口
  -> 如果 initialRecords 可覆盖今天，先写入今天缓存
  -> 请求窗口内 records
  -> 按 scheduledAt 所在日期分组写入 recordsByDayID
  -> selectedDayRecords 驱动当天列表
  -> recordsByDayID 驱动顶部多日圆环

选择日期
  -> 判断新日期是否在 loadedWindow 内
  -> 在窗口内：不请求，只更新 selectedDate，列表从 recordsByDayID 读取
  -> 不在窗口内：请求新日期前后 4 天记录，替换或合并缓存
```

是否替换缓存：

1. 第一期建议保留最近窗口缓存并合并，不强制清空旧窗口，避免用户来回滑动时闪烁。
2. 如担心内存，可只保留最近 15 天缓存：新窗口写入后清理距离选中日超过 7 天的数据。
3. 不需要持久化到磁盘。

### 5.4 日期条进度计算

新增按日期取记录的方法：

```swift
private func records(for day: Date) -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
    let id = MedicationExecutionDateItem.id(for: day, calendar: calendar)
    return recordsByDayID[id] ?? []
}
```

`MedicationExecutionDateDot` 的 `progress` 参数改为使用对应日期记录：

```swift
progress: MedicationExecutionPlanner.progress(
    plans: medicationPlans,
    medicineBoxes: medicineBoxes,
    records: records(for: item.date),
    on: item.date,
    calendar: calendar
)
```

这样每个圆环用自己的日期记录计算进度。

### 5.5 保存后缓存更新

当前 `upsertRecord(_:)` 只更新单一 `records` 数组。改造后需要按记录的 `scheduledAt` 写入对应日期缓存。

建议逻辑：

```text
saveDose 成功
  -> 根据 saved.scheduledAt 计算 dayID
  -> 在 recordsByDayID[dayID] 中按 record.id upsert
  -> 如果当前选中日等于 saved.scheduledAt 所在日，列表立即更新
  -> 顶部对应日期圆环立即重新计算
```

注意：

1. 按需用药生成的 `scheduledAt` 使用选中日 + 当前时间，保存后也应落入选中日缓存。
2. 更新已有记录时，仍按 `record.id` 替换。
3. 如果服务端返回的 `scheduledAt` 与本地剂次不同，以服务端返回为准。

### 5.6 初始记录兼容

`MedicationsListPage` 当前传入 `todayMedicationRecords` 作为 `initialRecords`。窗口加载后仍需兼容：

1. 进入页面时，如果 `initialRecords` 非空，先写入今天对应的 `recordsByDayID`。
2. 随后仍请求今天前后 4 天窗口，确保非今天记录完整。
3. 如果窗口请求成功，用服务端返回结果覆盖窗口内对应日期缓存。
4. 如果窗口请求失败，至少保留 `initialRecords`，页面可展示今天数据。

## 6. 日期进度圆环 UI 设计

### 6.1 参考视觉

参考图片中的顶部日期条结构：

```text
页面标题：用药
日期标题：6月11日 今天
黑色向下三角
横向日期条：星期文字 + 大圆形进度
```

圆形进度要求：

1. 空状态：浅灰实心圆。
2. 部分完成：圆形底色浅灰，蓝绿色填充对应比例。
3. 全部完成：蓝绿色实心圆。
4. 选中日：星期文字使用黑底白字小圆标记。
5. 未选中日：星期文字使用灰色。
6. 当前中心日期与标题下方三角保持对齐。

### 6.2 推荐尺寸

当前圆点 `18 x 18` 偏小，建议调整为：

| 元素 | 建议尺寸 |
| --- | --- |
| 日期项宽度 | `68pt` 到 `76pt` |
| 进度圆直径 | `46pt` 到 `52pt` |
| 星期选中标记 | `24pt` 到 `28pt` |
| 星期与圆间距 | `8pt` 到 `10pt` |
| 日期条垂直高度 | `84pt` 到 `96pt` |

`dateStripItemWidth` 应与日期项真实宽度一致，否则居中吸附会偏移。

### 6.3 填充式圆形进度实现

建议将 `MedicationExecutionDateDot` 的圆环实现从描边 `trim` 改为“圆形裁剪 + 底部填充”。

视觉逻辑：

```text
progress = 0
  -> 显示浅灰圆

0 < progress < 1
  -> 底层浅灰圆
  -> 蓝绿色矩形从底部向上填充 progress 高度
  -> 整体 clipShape(Circle())

progress = 1
  -> 显示蓝绿色圆
```

这样可匹配参考图里的半圆填充效果。

注意：

1. 填充高度应使用 `circleDiameter * progress`。
2. 蓝绿色建议使用 `systemTeal` 或与项目药品主题色一致。
3. 空圆底色建议使用 `systemGray6` / `secondarySystemGroupedBackground`，但需要保证在白底上可见。
4. 若当天没有计划剂次，`progress` 不应显示成完成，保持空状态。

### 6.4 选中态规则

选中态不再把进度圆替换为小圆点，而是：

1. 仍显示该日真实进度圆。
2. 星期文字显示黑色圆形背景。
3. 标题下方三角指向选中日期。
4. 日期条滚动吸附后，选中项居中。

这样可以同时满足“选中日明确”和“圆环体现用药进度”。

### 6.5 未加载日期的显示

日期条仍可展示前后 45 天，但只有选中日前后 4 天有真实记录窗口。

未加载日期处理规则：

1. 如果日期不在当前 `loadedWindow` 内，圆形显示空状态，不展示伪进度。
2. 不额外显示 loading 骨架，避免日期条闪烁。
3. 用户滑动并选中未加载日期后，触发新窗口加载。
4. 加载成功后，该日期前后 4 天圆环更新为真实进度。

可选增强：

```swift
let isLoaded = isDateInLoadedWindow(item.date)
```

`MedicationExecutionDateDot` 可接收 `isLoaded`，用于决定空状态辅助文案：

```text
未加载：暂无加载
已加载但无计划：无定时用药
已加载且有计划但无记录：未完成
```

第一期 UI 不必须区分，但无障碍文案建议区分。

## 7. 记录区交互设计

### 7.1 选择日期后列表展示

记录区只展示当前选中日：

1. `记录` 区展示当前选中日未完成的定时用药。
2. `已记录` 区展示当前选中日已完成或跳过的用药。
3. `按需用药` 使用当前选中日作为 `scheduledAt` 日期部分。
4. 日期标题同步显示 `M月d日 今天` 或 `M月d日 星期X`。

### 7.2 加载中状态

窗口加载时：

1. 保留现有居中 `ProgressView` 方案。
2. 如果当前选中日已有缓存，不清空列表，后台刷新即可。
3. 如果当前选中日无缓存且正在加载，显示加载状态。
4. 加载失败时保留已有缓存，并通过 `notificationClient.error` 提示。

### 7.3 快速滑动与吸附

当前已有 `dateStripSettleTask` 和 `applyDateStripSnapToCenterItem`。本工单保留该机制，只补充：

1. 吸附导致 `selectedDate` 变化后，调用窗口加载判断。
2. 快速滑动期间不应并发触发多个同窗口请求。
3. 若旧请求晚于新请求返回，需要用 `loadingWindowID` 或请求窗口校验，避免旧数据覆盖新窗口状态。

## 8. 详细实现建议

### 8.1 模型补充

可在 `MedicationExecutionModels.swift` 增加轻量模型：

```swift
struct MedicationExecutionRecordWindow: Equatable {
    let start: Date
    let endExclusive: Date
}
```

或直接在页面内用 `(start: Date, endExclusive: Date)`，第一期不强制新增模型。

### 8.2 Planner 保持纯函数

`MedicationExecutionPlanner` 当前保持纯函数，建议继续只负责：

1. 计算某天计划剂次。
2. 计算某天进度。
3. 判断计划在某天是否生效。
4. 生成按需剂次。

不建议把网络加载、缓存窗口、页面状态放入 Planner。

### 8.3 DateStrip 组件职责

`MedicationExecutionDateStrip.swift` 主要负责 UI 展示：

1. 接收 `progress`。
2. 接收 `isSelected`。
3. 可选接收 `isLoaded`。
4. 不在 DateDot 内查询数据。

### 8.4 进度含义

进度计算沿用当前逻辑：

```text
progress = 已完成或已跳过的剂次数 / 当天计划剂次数
```

其中 `isCompleted` 当前定义为：

```swift
status == "taken" || status == "skipped"
```

说明：

1. `taken` 和 `skipped` 都视为该剂次已处理。
2. 没有计划剂次时，进度为 `0`，显示空圆。
3. 有计划但未记录时，进度为 `0`，显示空圆。
4. 部分剂次已记录时，显示对应比例填充。

## 9. 验收标准

### 9.1 数据加载验收

1. 首次进入用药执行中心，以今天为中心加载前后 4 天服药记录。
2. 选中日期在当前窗口内时，不重复请求记录接口。
3. 选中日期超出当前窗口时，加载新选中日前后 4 天记录。
4. 接口请求使用 `scheduled_from` 和 `scheduled_to` 时间窗。
5. 请求失败时不清空已有缓存，并显示错误提示。
6. 快速滑动日期条时，不出现旧请求覆盖新选中日数据的问题。

### 9.2 圆环展示验收

1. 顶部日期条至少可同时看到多个连续日期的进度圆。
2. 选中日前后 4 天内的圆环可展示真实进度。
3. 进度为 `0` 时显示浅灰圆。
4. 进度为 `0.5` 左右时显示半圆填充效果。
5. 进度为 `1` 时显示蓝绿色实心圆。
6. 选中日仍显示该日真实进度，不被小圆点替代。
7. 选中日星期文字有明显选中态，参考黑底白字圆形标记。
8. 日期标题下方三角与居中日期对齐。

### 9.3 记录列表验收

1. 切换日期后，`记录` 区只展示该日期未完成剂次。
2. 切换日期后，`已记录` 区只展示该日期已完成或跳过剂次。
3. 当前日期无待记录剂次时，展示全部完成卡片或空状态。
4. 保存用药记录后，当前列表立即更新。
5. 保存用药记录后，对应日期圆环立即更新。
6. 按需用药保存后，落入当前选中日记录。

### 9.4 回归验收

1. 服药计划频率规则仍按 `daily`、`weekly`、`every_n_days` 生效。
2. 结束日期之前和之后的计划显示规则不变。
3. 药品图片展示不受影响。
4. 记录保存、跳过、更新已有记录能力不受影响。
5. `MedicationsListPage` 传入的今日初始记录仍可被使用。
6. 无成员 ID 时不发起记录加载请求，页面不崩溃。

## 10. 测试建议

### 10.1 单元测试建议

如项目已有对应测试目标，建议覆盖：

1. `MedicationExecutionPlanner.progress` 多剂次进度计算。
2. `taken` / `skipped` 都计入完成。
3. 无计划剂次时进度为 `0`。
4. `weekly` 计划只在指定星期生效。
5. `every_n_days` 计划按间隔日期生效。

### 10.2 手工测试场景

| 场景 | 准备数据 | 预期 |
| --- | --- | --- |
| 今日 3 次待服药，完成 1 次 | 今日 3 个 reminder，1 条 taken record | 今日圆环约 1/3 填充 |
| 前一天全部完成 | 昨日剂次均有 taken/skipped record | 昨日圆环满圆 |
| 前两天无记录 | 有计划但无 record | 对应日期空圆 |
| 切换到 5 天前 | 当前窗口外日期 | 发起新窗口加载 |
| 保存当前剂次 | 点击记录并完成 | 当前列表移动到已记录，圆环填充增加 |
| 快速滑动日期条 | 连续横滑多天 | 页面不卡顿，最终选中日期数据正确 |

## 11. 风险与注意事项

1. 日期窗口使用本地 `Calendar.current`，需要与现有计划剂次计算保持一致。
2. `scheduledTo` 应使用开区间结束时间，即选中日后第 5 天零点，避免漏掉后第 4 天全天数据。
3. 记录按 `scheduledAt` 分组，不按 `takenAt` 分组，否则补记录会归到错误日期。
4. 保存记录后要用服务端返回记录更新缓存，避免本地状态与服务端字段不一致。
5. 如果日期条圆形尺寸变大，需要同步调整 `dateStripItemWidth`、`dateStripSidePadding` 和吸附计算。
6. 参考图底部还有“你的药品”区域和底部 Tab，本工单只处理 `MedicationExecutionCenter` 顶部日期进度和记录区域，不扩大到药品列表页整体重构。

## 12. 建议实施拆分

### 第一步：数据窗口

1. 新增 `recordsByDayID` 缓存。
2. 新增选中日前后 4 天窗口加载。
3. 将当前列表改为读取 `selectedDayRecords`。
4. 保存记录后按日期 upsert 缓存。

### 第二步：多日圆环

1. 日期条每个 item 使用对应日期记录计算进度。
2. 补充未加载日期空态。
3. 确保切换日期后圆环立即更新。

### 第三步：UI 对齐参考图

1. 放大日期项和进度圆尺寸。
2. 将描边圆环改为填充式圆形进度。
3. 选中日星期文字改为黑底白字圆形标记。
4. 调整日期条高度、间距和吸附宽度。

### 第四步：回归验证

1. 验证定时用药、按需用药、跳过、保存、更新记录。
2. 验证快速滑动和请求失败场景。
3. 对照参考图片检查 UI 一致性。

---

## 工单 `MEDICATION-EXECUTION-000002`：用药本地通知闭环详细设计

### 工单状态

需求设计中。

### 需求依据

```text
SparkClient/需求文档/医疗档案/用药日常工单/用药通知需求讨论文档.md
SparkClient/需求文档/启动/冷启动目标页面公共调度需求文档.md
```

本工单将“用药通知需求讨论文档”中已经确认的首版方向整理为可实施的详细设计：

```text
只做客户端本地通知闭环；
不新增服务端调度；
不做家属代提醒；
不做跨设备统一去重；
不做长期未来所有通知一次性注册。
```

## 1. 背景

当前用药计划已经具备提醒相关字段：

```swift
struct RemoteMedicationPlan: Codable, Sendable, Equatable {
    var id: Int
    var member: Int
    var medicineBox: Int?
    var drugName: String
    var dosePerTime: String
    var doseValue: Double?
    var doseUnit: String
    var frequencyType: String
    var everyNDays: Int?
    var weeklyWeekdays: [Int]
    var frequencyText: String
    @CodableReminderTimesList var reminderTimes: [ReminderTime]
    var startDate: Date
    var endDate: Date?
    var instructions: String
    var reminderEnabled: Bool
    var status: String
    var updatedAt: Date
}
```

当前用药执行中心也具备记录用药能力：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionCenterPage.swift
```

其中已经存在：

```swift
@State private var logSheet: MedicationExecutionLogSheetContext?
```

以及：

```swift
.sheet(item: $logSheet) { context in
    MedicationExecutionLogSheet(...)
}
```

因此首版用药通知不需要新增服务端调度，也不需要新增“记录用药页面”。核心是：

```text
用药计划 -> 客户端编译未来提醒 -> 注册本地通知 -> 到点触发 -> 点击通知 -> 切换成员 -> 进入执行中心 -> 打开 logSheet -> 保存记录 -> 清理当前剂次通知
```

## 2. 已确认目标

### 2.1 核心目标

1. 创建、编辑、删除、停用用药计划后，本机通知立即同步。
2. 用药提醒能在无网情况下触发。
3. 点击通知走冷启动目标页面公共调度组件。
4. Home 先切换到通知 `member_id` 对应成员。
5. 等目标成员首页数据加载完成后，再进入用药执行中心。
6. 用药执行中心切换到 `scheduled_at` 对应日期。
7. 定位 `plan_id + dose_sequence` 对应剂次。
8. 直接设置 `logSheet`，打开 `MedicationExecutionLogSheet`。
9. 服药打卡后，当前剂次提醒不再重复出现。
10. 在系统通用设置 `GeneralSettingsView` 内新增“医疗”模块，提供“通知中显示药品名称”开关。

### 2.2 非目标

1. 不新增 SparkService 接口。
2. 不新增服务端通知调度表。
3. 不接入服务端 APNs 兜底。
4. 不做家属代提醒。
5. 不做多设备主设备策略。
6. 不做跨设备统一去重。
7. 不做 Apple Watch 独立交互。
8. 不做通知 Action，例如“已服用 / 跳过 / 稍后提醒”。
9. 不自动判断漏服并生成记录。
10. 不做 AI 自动调整提醒时间。

## 3. 当前项目可复用能力

| 能力 | 文件 | 复用方式 |
| --- | --- | --- |
| 用药计划模型 | `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 直接使用 `RemoteMedicationPlan` 的频次、时间、开始结束日期、提醒开关 |
| 用药记录模型 | `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 用于判断目标剂次是否已完成 |
| 记录用药 Sheet | `MedicationExecutionCenterPage.swift` / `MedicationExecutionLogSheet.swift` | 通知点击定位后直接打开 |
| 剂次计算 | `MedicationExecutionPlanner.swift` | 复用计划展开和剂次计算规则，避免通知和页面算法不一致 |
| 系统通知委托 | `PushAdapter.swift` | 复用 `UNUserNotificationCenterDelegate` 前台/点击回调能力 |
| 应用内通知 | `NotificationClient` / `NotificationHostView` | 前台收到本地用药通知时展示应用内 banner |
| 冷启动目标调度 | `LaunchIntent.swift` / `LaunchIntentCoordinator.swift` / `HomeLaunchIntentConsumer.swift` | 通知点击后延迟到 Home 就绪再消费 |
| 通用设置页 | `GeneralSettingsView.swift` | 增加医疗模块和药品名称隐私开关 |

## 4. 总体架构设计

### 4.1 模块划分

建议新增目录：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/
```

建议新增文件：

```text
MedicationReminderModels.swift
MedicationReminderScheduleCompiler.swift
MedicationReminderNotificationManager.swift
MedicationReminderPermissionCoordinator.swift
MedicationReminderSyncCoordinator.swift
MedicationReminderRouteIntent.swift
MedicationReminderPreferencesStore.swift
```

模块职责：

| 模块 | 职责 |
| --- | --- |
| `MedicationReminderModels` | 定义本地提醒事件、通知 payload、聚合分组、调度结果 |
| `MedicationReminderScheduleCompiler` | 把用药计划编译为未来 7 天的提醒事件 |
| `MedicationReminderNotificationManager` | 注册、取消、重建 `UNNotificationRequest` |
| `MedicationReminderPermissionCoordinator` | 处理通知权限检查、系统设置跳转、权限状态 |
| `MedicationReminderSyncCoordinator` | 响应计划变更、打卡、账号切换、时区变化，统一重建通知 |
| `MedicationReminderRouteIntent` | 定义通知点击后进入用药执行中心所需的 LaunchIntent 数据 |
| `MedicationReminderPreferencesStore` | 保存“用药通知总开关”“通知中显示药品名称”等本地偏好 |

### 4.2 职责边界

页面不直接调用 `UNUserNotificationCenter.add`。

正确边界：

```text
MedicationsListPage / MedicationExecutionCenterPage
  -> 发出“计划已保存 / 记录已保存 / 计划已删除”的事件
  -> MedicationReminderSyncCoordinator
  -> MedicationReminderScheduleCompiler
  -> MedicationReminderNotificationManager
  -> UNUserNotificationCenter
```

不推荐：

```text
页面 View
  -> 直接拼 notification identifier
  -> 直接 add/remove 通知
```

原因：

1. 用药提醒触发点很多，分散在页面里容易漏。
2. identifier 规则必须统一。
3. 账号切换、时区变化、权限恢复等不是单个页面能处理的。
4. 后续如果增加诊断页或服务端登记，需要统一 coordinator。

## 5. 数据模型设计

### 5.1 本地提醒事件

建议定义：

```swift
struct MedicationReminderEvent: Identifiable, Equatable, Sendable {
    let id: String
    let accountID: Int64
    let memberID: Int
    let scheduledAt: Date
    let timeText: String
    let items: [MedicationReminderItem]
    let title: String
    let body: String
}

struct MedicationReminderItem: Equatable, Sendable {
    let planID: Int
    let doseSequence: Int
    let drugName: String
    let plannedDose: String
}
```

说明：

1. `MedicationReminderEvent` 是最终注册通知的粒度。
2. 首版建议按“同一账号 + 同一成员 + 同一分钟”聚合。
3. `items` 内保留多个计划剂次，用于点击后在 Sheet 内展示多条。
4. `body` 由当前隐私设置决定是否显示药品名称。

### 5.2 通知 userInfo

建议本地通知 `userInfo`：

```json
{
  "type": "medication_reminder",
  "route": "medication_execution",
  "account_id": 265,
  "member_id": 100,
  "scheduled_at": "2026-06-15T08:00:00+08:00",
  "notification_id": "medication_265_100_20260615_0800_abcd",
  "items": [
    { "plan_id": 12, "dose_sequence": 1 },
    { "plan_id": 15, "dose_sequence": 1 }
  ]
}
```

约束：

1. `account_id` 必填，用于账号隔离。
2. `member_id` 必填，用于 Home 先切换成员。
3. `scheduled_at` 必填，用于用药执行中心切换日期。
4. `items` 必填，用于定位计划和剂次。
5. 通知 payload 不放诊断、病情、医院、医生等敏感信息。

### 5.3 通知 identifier

聚合通知建议：

```text
medication_{accountID}_{memberID}_{yyyyMMdd_HHmm}_{groupHash}
```

其中：

1. `accountID`：防止账号串通知。
2. `memberID`：便于按成员清理。
3. `yyyyMMdd_HHmm`：提醒时间。
4. `groupHash`：由 `planID + doseSequence` 排序后生成短 hash。

如果首版不做聚合，也可以使用：

```text
medication_{accountID}_{memberID}_{planID}_{yyyyMMdd_HHmm}_{doseSequence}
```

但推荐聚合，原因：

1. 减少 iOS pending notification 数量。
2. 避免同一分钟多条通知打扰。
3. 点击后自然打开同一时间组的记录 Sheet。

## 6. 调度算法设计

### 6.1 注册窗口

首版采用滚动窗口，不一次性注册长期用药全部通知。

| 项 | 建议 |
| --- | --- |
| 默认窗口 | 未来 7 天 |
| 最大窗口 | 不超过未来 14 天 |
| 单次注册上限 | 建议 48 条 |
| 超过上限策略 | 按 `scheduledAt` 从近到远保留，远期截断并记录 Debug 日志 |
| 重建触发 | 冷启动、前台恢复、计划保存、计划删除/停用、打卡、账号切换、时区变化、设置变更 |

### 6.2 编译输入

`MedicationReminderScheduleCompiler` 输入：

```swift
struct MedicationReminderCompileInput {
    let accountID: Int64
    let memberID: Int
    let plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let now: Date
    let windowDays: Int
    let calendar: Calendar
    let showsDrugNameInNotification: Bool
}
```

说明：

1. `plans` 来自当前成员首页数据。
2. `records` 至少要包含未来窗口内已存在的服药记录；如果当前只缓存今日记录，调度时可先按现有数据判断，不为已完成剂次重复注册。
3. `medicineBoxes` 用于后续文案或图片扩展，首版可不用。
4. `showsDrugNameInNotification` 来自通用设置医疗模块。

### 6.3 编译流程

```text
输入 plans / records / now
  -> 过滤无效计划
     - reminderEnabled = false
     - status != active
     - reminderTimes 为空
     - endDate 早于今天
  -> 对未来 7 天逐日展开
  -> 根据 frequencyType 判断当天是否应提醒
  -> 根据 reminderTimes 生成剂次
  -> 过滤 scheduledAt <= now 的过去剂次
  -> 过滤 records 中已 taken / skipped 的剂次
  -> 按 accountID + memberID + scheduledAt minute 聚合
  -> 生成 MedicationReminderEvent
  -> 按 scheduledAt 升序排序
  -> 截断到上限 48 条
```

### 6.4 频次规则

| 频次 | 规则 |
| --- | --- |
| `daily` | 从 `startDate` 到 `endDate`，每天按 `reminderTimes` 生成 |
| `every_n_days` | 以 `startDate` 为锚点，`daysBetween(startDate, day) % everyNDays == 0` 时生成 |
| `weekly` | 当天 weekday 命中 `weeklyWeekdays` 时生成；约定 1=周一...7=周日 |

注意：

1. `endDate` 按包含结束日处理。
2. 日期判断使用本地 `Calendar.current`，与用药执行中心保持一致。
3. `ReminderTime.time` 按 `HH:mm` 解析。
4. 同一天多个提醒时间按时间升序。
5. `doseSequence` 与 `MedicationExecutionPlanner.scheduledDoses` 保持一致，避免通知定位不到 Sheet 剂次。

### 6.5 已完成剂次过滤

判断某个剂次是否已完成：

```text
同 planID
AND 同 scheduledAt 所在分钟
AND 同 doseSequence
AND record.status in ["taken", "skipped"]
```

说明：

1. `taken` 和 `skipped` 都表示该剂次已处理。
2. 已处理剂次不再注册通知。
3. 保存记录成功后，需要移除当前剂次对应 pending / delivered 通知。

## 7. 本地通知注册设计

### 7.1 注册流程

```text
MedicationReminderSyncCoordinator.rebuild(...)
  -> NotificationPermissionCoordinator 检查系统通知权限
  -> 如果未授权：不注册，返回状态
  -> NotificationManager 查询当前 pending medication 通知
  -> 移除当前账号旧的 medication_reminder 通知
  -> Compiler 编译未来 7 天事件
  -> 为每个 event 构建 UNNotificationRequest
  -> center.add(request)
  -> 记录成功/失败日志
```

### 7.2 通知 trigger

使用：

```swift
UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
```

首版不使用 `repeats = true`，原因：

1. 每条通知必须携带 `plan_id / dose_sequence / scheduled_at`，重复通知不适合携带动态剂次。
2. 计划可能编辑、停用、删除。
3. 已打卡后需要取消当前剂次。
4. 滚动窗口更容易控制 iOS pending 上限。

### 7.3 通知内容

默认：

```text
title：用药提醒
body：妈妈有一项用药需要记录
```

本人：

```text
title：用药提醒
body：你有一项用药需要记录
```

同一分钟多项：

```text
title：用药提醒
body：妈妈有 3 项用药需要记录
```

如果通用设置开启“通知中显示药品名称”：

```text
title：用药提醒
body：妈妈该记录 阿莫西林 的用药了
```

多项药品且开启药名：

```text
title：用药提醒
body：妈妈有 3 项用药需要记录
```

多项场景不建议拼接全部药名，避免锁屏泄露过多信息。

### 7.4 不展示的内容

通知默认不展示：

1. 诊断名称。
2. 病情描述。
3. 医院名称。
4. 医生信息。
5. 详细剂量和用法。
6. 病例、处方、检查报告标题。

原因：

1. 通知可能出现在锁屏、通知中心、手表、车机。
2. 用药信息属于敏感健康数据。
3. 首版优先保护隐私，药名显示必须由用户主动开启。

## 8. 通知触发时机设计

### 8.1 创建/编辑/删除/停用计划

| 操作 | 通知处理 |
| --- | --- |
| 新增计划成功 | 重建当前账号未来 7 天用药通知 |
| 编辑计划成功 | 取消旧通知，按最新计划重建 |
| 删除计划成功 | 移除该计划相关 pending / delivered 通知，并重建窗口 |
| 停用计划成功 | 移除该计划相关通知，并重建窗口 |
| 开启 `reminderEnabled` | 重建窗口 |
| 关闭 `reminderEnabled` | 移除该计划通知，并重建窗口 |

建议直接重建当前账号未来窗口，而不是做过细的局部 patch。原因：

1. 用药计划数量通常可控。
2. 全量重建能降低遗漏旧通知的概率。
3. 统一路径便于调试。

### 8.2 用药打卡

保存 `taken` 或 `skipped` 成功后：

```text
服务端保存记录成功
  -> 更新 MedicationExecutionCenterPage 本地 recordsByDayID
  -> 通知 MedicationReminderSyncCoordinator
  -> 移除当前剂次 pending / delivered 通知
  -> 可选：轻量重建未来窗口
```

当前剂次通知定位：

```text
accountID + memberID + planID + scheduledAt + doseSequence
```

如果是聚合通知：

1. 当前剂次完成后，如果聚合通知内还有其他未完成剂次，可重建该时间点通知。
2. 如果该时间点所有剂次都已完成，则清理该聚合通知。

### 8.3 App 生命周期

| 时机 | 处理 |
| --- | --- |
| 冷启动已登录会话准备完成 | 重建当前账号未来 7 天通知 |
| App 进入前台 | 如果距离上次重建超过阈值，轻量重建 |
| 账号切换 | 清理旧账号通知，再为新账号重建 |
| 退出登录 | 清理当前账号所有用药通知 |
| 系统时区变化 | 清理并重建未来窗口 |
| “通知中显示药品名称”设置变更 | 重建未来窗口，让 pending 通知文案即时生效 |

建议防抖：

```text
同一账号 30 秒内多次触发 rebuild，只执行最后一次。
```

## 9. 通知点击路由详细设计

### 9.1 路由原则

点击通知后不直接从通知回调里操作 `MedicationExecutionCenterPage`。

必须走冷启动目标页面公共调度：

```text
SparkClient/需求文档/启动/冷启动目标页面公共调度需求文档.md
```

原因：

1. App 可能还没初始化完成。
2. 用户可能未登录或刚登录。
3. Home 可能还没有挂载。
4. 需要先切换成员并等待首页数据完成。
5. 目标 Sheet 只有在执行中心页面挂载后才能打开。

### 9.2 标准流程

```text
点击用药提醒通知
  -> App 启动或前台激活
  -> PushAdapter / UNUserNotificationCenterDelegate 收到 notification response
  -> 解析 userInfo 为 medication_reminder intent
  -> LaunchIntentCoordinator 入队
  -> 等待登录态、账号运行时、Home 宿主就绪
  -> HomeLaunchIntentConsumer 消费 intent
  -> Home 先切换到 member_id 对应成员
  -> 等待该成员首页数据加载完成
  -> 打开 Home / 用药执行中心
  -> MedicationExecutionCenterPage 切换到 scheduled_at 日期
  -> 加载目标日期记录窗口
  -> 定位 plan_id + dose_sequence 对应剂次
  -> 设置 logSheet，打开 MedicationExecutionLogSheet
```

### 9.3 LaunchIntent 建议

建议新增或扩展：

```swift
enum LaunchIntentTarget: Codable, Equatable, Sendable {
    case medicationReminder(MedicationReminderLaunchPayload)
}

struct MedicationReminderLaunchPayload: Codable, Equatable, Sendable {
    let accountID: Int64
    let memberID: Int
    let scheduledAt: Date
    let notificationID: String
    let items: [MedicationReminderLaunchItem]
}

struct MedicationReminderLaunchItem: Codable, Equatable, Sendable {
    let planID: Int
    let doseSequence: Int
}
```

要求：

1. `accountID` 与当前会话不一致时，不消费该 intent。
2. `memberID` 无权限时，回到 Home 并提示。
3. `items` 为空时，丢弃 intent 并记录日志。
4. 同一个 `notificationID` 要去重消费。

### 9.4 Home 消费逻辑

Home 消费 intent 的顺序必须是：

```text
switchMember(memberID)
  -> loadCompleteData(memberID)
  -> wait until completeData loaded
  -> openMedicationExecutionCenter(payload)
```

不能：

```text
openMedicationExecutionCenter()
  -> 再切成员
```

原因：

1. `MedicationExecutionCenterPage` 入参包括 `medicationPlans`、`medicineBoxes`、`initialRecords`。
2. 这些数据必须来自通知目标成员。
3. 如果先打开页面，会拿到当前 Home 已选成员旧数据，导致定位不到计划或打开错误成员的记录 Sheet。

### 9.5 执行中心定位逻辑

`MedicationExecutionCenterPage` 需要支持外部定位参数：

```swift
struct MedicationExecutionInitialFocus: Equatable, Sendable {
    let scheduledAt: Date
    let items: [MedicationReminderLaunchItem]
    let shouldOpenLogSheet: Bool
}
```

页面进入后：

```text
selectedDate = scheduledAt 对应日期
loadRecordWindow(centeredAt: selectedDate)
scheduledDoses = MedicationExecutionPlanner.scheduledDoses(...)
targetDoses = scheduledDoses.filter(planID + doseSequence 命中 items)
if targetDoses 未完成:
    logSheet = MedicationExecutionLogSheetContext(...)
else:
    展示已完成提示，不打开 Sheet
```

注意：

1. 需要等目标日期记录加载完成后再定位。
2. 定位只信任页面根据最新计划和记录计算出的 `scheduledDoses`，不直接信任通知 payload。
3. 如果目标剂次已经完成，不打开记录 Sheet。
4. 如果计划不存在或停用，展示“该用药提醒已失效”。

## 10. 设置与开关详细设计

### 10.1 系统通用设置医疗模块

在：

```text
SparkClient/SparkClient/Projects/Features/Settings/GeneralSettings/Presentation/GeneralSettingsView.swift
```

新增 `medicalSection`：

```text
List {
    versionSection
    homeNutritionEntrySection
    medicalSection
    MedicalExtractionRetrySettingsSection()
    cacheSection
}
```

首版设置项：

| 设置项 | 默认值 | 作用 |
| --- | --- | --- |
| 通知中显示药品名称 | 关闭 | 控制本地用药通知文案是否允许显示药品名称 |

建议文案：

```text
Section：医疗
Toggle：通知中显示药品名称
Footer：开启后，用药提醒可能会在锁屏、通知中心、手表或车机中显示药品名称。
```

### 10.2 偏好存储

建议新增：

```swift
@MainActor
final class MedicationReminderPreferencesStore: ObservableObject {
    @Published var showsDrugNameInNotification: Bool
    @Published var medicationNotificationsEnabled: Bool
}
```

存储原则：

1. 默认 `showsDrugNameInNotification = false`。
2. 默认 `medicationNotificationsEnabled = true`，但最终能否提醒还受系统通知权限控制。
3. 偏好建议按账号隔离，避免多人共用设备时串设置。
4. `showsDrugNameInNotification` 变更后触发通知窗口重建。

### 10.3 开关判断

最终是否注册通知：

```text
系统通知已授权
AND 用药通知总开关开启
AND plan.reminderEnabled = true
AND plan.status = active
AND 当前账号/成员仍可访问
AND 计划在未来窗口内存在待提醒剂次
```

如果系统通知未授权：

1. 用药计划仍可保存。
2. 页面提示“系统通知未开启，可能错过用药提醒”。
3. 不注册本地通知。
4. 用户开启系统权限后，前台恢复时重建通知。

## 11. 权限设计

### 11.1 请求时机

不在 App 启动时主动弹系统通知权限。

推荐时机：

1. 用户首次保存 `reminderEnabled = true` 的用药计划。
2. 用户在用药通知设置中主动开启提醒。
3. 用户点击“开启系统通知”引导。

### 11.2 权限状态

| 状态 | 行为 |
| --- | --- |
| `.notDetermined` | 先展示应用内说明，再请求系统权限 |
| `.authorized` / `.provisional` | 允许注册本地通知 |
| `.denied` | 不注册通知，引导去系统设置 |
| `.ephemeral` | 按可提醒处理，但记录 Debug 状态 |

### 11.3 应用内说明

建议文案：

```text
开启用药提醒
我们会在你设置的用药时间提醒你记录服药情况。
```

按钮：

```text
继续
暂不开启
```

用户点击“继续”后再调用系统权限请求。

## 12. 前台提醒设计

### 12.1 前台策略

本地通知在 App 前台到达时：

| 当前页面 | 行为 |
| --- | --- |
| 正在用药执行中心 | 不弹系统 banner，刷新页面并可轻提示 |
| 不在用药页面 | 展示应用内 banner |
| 后台/锁屏 | 走系统通知展示 |

### 12.2 前台应用内 banner

复用 `NotificationClient`：

```text
title = 用药提醒
message = 你/成员有一项用药需要记录
onTap = 提交 medicationReminder LaunchIntent
```

注意：

1. 前台不要同时展示系统 banner 和应用内 banner。
2. 同一个 `notificationID` 只展示一次。
3. 前台点击应用内 banner 也必须走同一套 LaunchIntent 消费流程。

## 13. 清理策略

### 13.1 按计划清理

删除、停用、关闭提醒时，清理：

```text
pending notification requests
delivered notifications
```

清理范围：

```text
accountID + memberID + planID
```

如果是聚合通知，不能只按单计划删除；应重建未来窗口，让聚合通知重新计算。

### 13.2 按账号清理

退出登录或账号切换：

```text
remove all medication_reminder notifications where account_id == currentAccountID
```

原因：

1. 本地通知是设备级资源。
2. 不清理会导致上一个账号的用药提醒遗留。
3. 点击遗留通知可能进入错误账号或泄露隐私。

### 13.3 打卡后清理

打卡成功后：

1. 移除当前剂次所在聚合通知。
2. 重新编译该时间点是否仍有未完成剂次。
3. 如果仍有未完成剂次，重新注册聚合通知。
4. 如果全部完成，不再注册。

## 14. 错误处理与降级

| 场景 | 处理 |
| --- | --- |
| 系统通知权限拒绝 | 计划保存成功，但不注册通知；页面提示去设置开启 |
| 编译无未来剂次 | 不注册通知，不报错 |
| pending 数量超过上限 | 保留最近 48 条，截断远期，记录 Debug 日志 |
| `UNUserNotificationCenter.add` 失败 | 记录失败原因；普通用户不弹技术错误 |
| 点击通知但账号不一致 | 不进入详情，可 Toast “该提醒属于其他账号” |
| 点击通知但成员无权限 | 回 Home，Toast “当前成员不可访问” |
| 点击通知但计划已删除/停用 | 回用药执行中心或 Home，Toast “该用药提醒已失效” |
| 点击通知时无网络 | 使用本地缓存；无缓存则提示稍后重试 |
| 已打卡后点击旧通知 | 不打开 Sheet，展示已完成状态 |

## 15. 影响文件

### 15.1 主要改动文件

```text
SparkClient/SparkClient/Projects/Core/Notification/Infrastructure/PushAdapter.swift
SparkClient/SparkClient/Projects/App/Sources/App/LaunchIntent.swift
SparkClient/SparkClient/Projects/App/Sources/App/LaunchIntentCoordinator.swift
SparkClient/SparkClient/Projects/App/Sources/App/HomeLaunchIntentConsumer.swift
SparkClient/SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift
SparkClient/SparkClient/Projects/Features/Settings/GeneralSettings/Presentation/GeneralSettingsView.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionCenterPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionModels.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionPlanner.swift
```

### 15.2 建议新增文件

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderModels.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderScheduleCompiler.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderNotificationManager.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderPermissionCoordinator.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderPreferencesStore.swift
```

### 15.3 服务端影响

```text
SparkService：无改动
```

本工单不新增服务端调度、不新增 APNs、不修改服务端模型。

## 16. 验收标准

### 16.1 通知注册验收

1. 保存开启提醒的用药计划后，本机能在指定时间收到通知。
2. 关闭提醒后，该计划未来通知全部取消。
3. 编辑提醒时间后，旧时间不再提醒，新时间正常提醒。
4. 删除或停用计划后，不再收到该计划通知。
5. App 无网时，本地通知仍能触发。
6. 用药通知只注册未来 7 天窗口，不一次性注册长期全部通知。
7. 超过本地上限时，按时间从近到远保留，不崩溃。

### 16.2 点击通知验收

1. 点击通知走冷启动目标页面公共调度组件。
2. 冷启动、后台、前台激活三种路径行为一致。
3. Home 先切换到通知 `member_id` 对应成员。
4. 目标成员首页数据加载完成后，才进入用药执行中心。
5. 用药执行中心定位到 `scheduled_at` 对应日期。
6. 定位到 `plan_id + dose_sequence` 对应剂次后直接打开 `MedicationExecutionLogSheet`。
7. 目标剂次已完成时，不打开 Sheet，展示已完成状态。
8. 计划已删除、停用或成员无权限时，展示不可用提示且不崩溃。

### 16.3 打卡后清理验收

1. 完成或跳过某次用药后，该剂次通知不再重复出现。
2. 同一时间聚合通知中仍有其他未完成剂次时，通知可被重新计算。
3. 全部剂次完成后，该时间点通知被清理。
4. 通知中心已展示的旧通知能被移除。

### 16.4 设置验收

1. `GeneralSettingsView` 增加“医疗”Section。
2. “通知中显示药品名称”默认关闭。
3. 默认关闭时，通知不显示药品名称。
4. 开启后，未来生成的单项用药通知可以显示药品名称。
5. 设置变更后，未来提醒窗口重建，pending 通知文案更新。

### 16.5 隔离与安全验收

1. 退出登录后，本账号用药通知被清理。
2. 切换账号后，不展示上一个账号的用药通知。
3. 点击其他账号遗留通知时，不进入当前账号医疗页面。
4. 通知 payload 不包含诊断、病情、医院、医生等敏感信息。

## 17. 测试建议

### 17.1 编译器单元测试

| 场景 | 预期 |
| --- | --- |
| 每日一次 | 未来 7 天生成 7 个提醒事件或聚合事件 |
| 每日多次 | 同一天多个时间点顺序正确 |
| 每几天 | 以 `startDate` 为锚点计算 |
| 每周指定日 | 只在指定 weekday 生成 |
| 有结束日期 | 结束日期之后不生成 |
| `reminderEnabled = false` | 不生成 |
| `status != active` | 不生成 |
| 已 taken / skipped | 对应剂次不生成 |
| 同一分钟多条计划 | 聚合为一条事件 |
| 超过 48 条 | 只保留最近 48 条 |

### 17.2 通知管理测试

1. 重建通知前会清理旧通知。
2. 同一输入多次重建不会产生重复 pending。
3. 删除计划后相关通知被清理。
4. 账号切换后旧账号通知被清理。
5. 权限拒绝时不注册通知。

### 17.3 路由手工测试

| 场景 | 预期 |
| --- | --- |
| App 未启动点击通知 | 进入 Home，切成员，加载数据，打开用药记录 Sheet |
| App 后台点击通知 | 同上 |
| App 前台点击应用内 banner | 同上 |
| 当前 Home 已是其他成员 | 先切到通知成员，再进入执行中心 |
| 目标成员无权限 | 提示不可访问 |
| 目标计划已删除 | 提示提醒已失效 |
| 目标剂次已打卡 | 不打开 Sheet，展示已完成 |

## 18. 实施拆分建议

### 第一步：模型与编译器

1. 新增 `MedicationReminderModels`。
2. 新增 `MedicationReminderScheduleCompiler`。
3. 复用或对齐 `MedicationExecutionPlanner` 的剂次计算规则。
4. 补充频次、聚合、已完成过滤单元测试。

### 第二步：通知注册与清理

1. 新增 `MedicationReminderNotificationManager`。
2. 支持按账号、成员、计划、notificationID 清理。
3. 支持注册未来 7 天聚合通知。
4. 支持 pending 上限截断。

### 第三步：计划/记录变更触发

1. 新增 `MedicationReminderSyncCoordinator`。
2. 在计划保存、编辑、删除、停用后触发重建。
3. 在服药记录保存成功后清理当前剂次并重建窗口。
4. 在账号切换、退出登录、前台恢复、时区变化时触发。

### 第四步：通知点击路由

1. 扩展 `LaunchIntent` 支持 `medicationReminder`。
2. `PushAdapter` / 通知回调识别本地 `medication_reminder`。
3. `HomeLaunchIntentConsumer` 先切成员并等待首页数据。
4. 打开 `MedicationExecutionCenterPage` 并传入 `MedicationExecutionInitialFocus`。
5. 执行中心定位剂次后打开 `logSheet`。

### 第五步：设置与权限

1. `GeneralSettingsView` 增加医疗 Section。
2. 新增“通知中显示药品名称”开关。
3. 新增权限说明弹窗和系统权限请求触发。
4. 设置变更后重建未来窗口。

### 第六步：回归验证

1. 验证首版本地通知验收标准。
2. 验证 000001 多日记录窗口与通知点击打开 Sheet 不冲突。
3. 验证无网络、无权限、账号切换、目标成员切换、计划失效等异常路径。

---

## 工单 `MEDICATION-EXECUTION-000003`：用药通知查看与管理页

### 工单状态

需求设计中。

### 需求依据

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift:278-279
/Users/hua/Downloads/Reference/包/Health/HealthClient/HealthClient/Presentation/Views/Notification/NotificationManagementView.swift
MEDICATION-EXECUTION-000002：用药本地通知闭环详细设计
```

## 1. 背景

`MEDICATION-EXECUTION-000002` 已经设计了本地用药通知闭环：

```text
用药计划 -> 编译未来 7 天提醒 -> 注册本地通知 -> 点击通知 -> 进入执行中心 -> 打开 logSheet -> 打卡后清理通知
```

但用户仍缺少一个可视化入口查看“当前本机到底注册了哪些用药提醒”。没有管理页会带来以下问题：

1. 用户不知道当前是否已经成功注册提醒。
2. 调试时无法判断通知是否漏注册、重复注册或已过期。
3. 用户无法手动补齐通知。
4. 用户无法取消某条不想要的本地提醒。
5. 用户无法清除全部本机用药提醒。
6. 000002 的通知调度逻辑缺少可观测入口。

因此需要在服药计划列表右上角增加“已有通知”入口，打开 SparkClient 自己的用药通知管理页。

## 2. 目标

### 2.1 核心目标

1. 在 `MedicationsListPage` 右上角 toolbar 增加“已有通知”入口。
2. 点击后进入用药通知管理页。
3. 页面展示本机当前账号的用药本地通知。
4. 支持统计：待发送、已送达。
5. 支持按成员、提醒时间、药品/计划聚合展示。
6. 支持手动补齐通知。
7. 支持取消单条待发送通知。
8. 支持清除当前账号全部用药通知。
9. 支持下拉或按钮刷新。
10. 与 000002 的 `MedicationReminderNotificationManager` / `MedicationReminderSyncCoordinator` 保持同一套数据来源和清理规则。

### 2.2 非目标

1. 不新增服务端接口。
2. 不展示服务端 APNs 记录。
3. 不展示其他类型通知，例如成员邀请、AI 试用审核、聊天消息。
4. 不做跨设备通知管理。
5. 不做已送达通知的“重新提醒”动作。
6. 不在通知管理页编辑用药计划本身。
7. 不改变 000002 的本地通知注册规则。

## 3. 入口设计

### 3.1 挂载位置

文件：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
```

当前 toolbar 位置已经预留：

```swift
.toolbar {
    // 增加 已有通知查看
}
```

建议新增：

```swift
ToolbarItem(placement: .navigationBarTrailing) {
    NavigationLink {
        MedicationReminderManagementPage(...)
    } label: {
        Label(
            L10n.text("medication_reminder.management.title", fallback: "已有通知"),
            systemImage: "bell.badge"
        )
    }
}
```

### 3.2 入口展示规则

| 场景 | 展示 |
| --- | --- |
| 已登录且有 memberID | 展示“已有通知”入口 |
| 无 memberID | 入口可展示但 disabled，或隐藏 |
| 系统通知未授权 | 入口仍展示，用于查看空态/权限提示 |
| 用药计划为空 | 入口仍展示，可展示空态和补齐按钮 |

建议首版：

```text
入口始终展示；
无当前成员/无账号时页面展示空态；
```

原因是通知管理页是账号级本地通知管理，不只服务当前成员。

## 4. 页面形态设计

### 4.1 页面名称

建议新增页面：

```text
MedicationReminderManagementPage.swift
```

建议路径：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderManagementPage.swift
```

### 4.2 页面结构

参考 HealthClient 的 `NotificationManagementView`，但视觉和依赖要符合 SparkClient 当前架构：

```text
NavigationStack / NavigationLink push
  -> 顶部统计区
  -> 权限/隐私提示区（按状态展示）
  -> 通知分组列表
  -> 空态 / 加载态 / 错误态
  -> 右上角操作：补齐通知、清除全部
```

### 4.3 顶部统计区

展示：

| 指标 | 含义 |
| --- | --- |
| 待发送 | `UNUserNotificationCenter.pendingNotificationRequests()` 中属于当前账号的用药通知数量 |
| 已送达 | `UNUserNotificationCenter.deliveredNotifications()` 中属于当前账号的用药通知数量 |
| 最近补齐 | 可选，展示最近一次重建时间；首版可不做 |

### 4.4 列表展示

建议按“成员 + 时间”聚合，而不是只按药品聚合。

原因：

1. 000002 推荐同一成员同一分钟聚合一条通知。
2. 一条通知可能包含多个药品。
3. 用户最关心“几点会提醒谁吃药”，其次才是药品明细。

建议卡片结构：

```text
08:00 今天
妈妈 · 3 项用药
待发送
阿莫西林、布洛芬、维生素D
```

如果通知 payload 中没有药品名，只展示：

```text
妈妈 · 3 项用药
```

展开后展示每个 item：

```text
阿莫西林 · doseSequence 1
布洛芬 · doseSequence 1
```

### 4.5 状态样式

| 状态 | 图标 | 颜色 | 操作 |
| --- | --- | --- | --- |
| 待发送 | `clock.fill` | blue | 可取消 |
| 已送达 | `checkmark.circle.fill` | green | 不支持取消，可清除 delivered |
| 已过期 | `exclamationmark.triangle.fill` | orange | 可清理 |
| 无法解析 | `questionmark.circle` | secondary | 可清理 |

说明：

1. Pending 通知使用 `trigger.nextTriggerDate()` 判断具体触发时间。
2. Delivered 通知使用系统 delivered notification 的 date 或 request 内容展示。
3. 无法解析的通知说明 payload 不完整或旧版本遗留。

## 5. 数据来源设计

### 5.1 查询范围

只读取本机通知中心：

```swift
UNUserNotificationCenter.current().pendingNotificationRequests()
UNUserNotificationCenter.current().deliveredNotifications()
```

过滤规则：

```text
identifier hasPrefix MedicationReminderNotification.identifierPrefix(accountID)
OR userInfo["type"] == "medication_reminder" AND userInfo["account_id"] == currentAccountID
```

首选 identifier 前缀，userInfo 作为兜底。

### 5.2 页面 ViewModel

建议新增：

```text
MedicationReminderManagementViewModel.swift
```

职责：

| 职责 | 说明 |
| --- | --- |
| 加载 pending 通知 | 读取待发送本地通知 |
| 加载 delivered 通知 | 读取已送达通知 |
| 解析 payload | 复用 `MedicationReminderPayloadParser` |
| 聚合分组 | 按成员、时间、notificationID 组成展示模型 |
| 取消单条 | 调用 `MedicationReminderNotificationManager.removeNotification(id:)` |
| 清除全部 | 调用 `removeAllMedicationNotifications(forAccountID:)` |
| 补齐通知 | 调用 `MedicationReminderSyncCoordinator.rebuildAfterPlanChanged(...)` 或等价方法 |
| 权限状态 | 读取 `MedicationReminderPermissionCoordinator.currentStatus()` |

### 5.3 展示模型

建议定义：

```swift
struct MedicationReminderDisplayGroup: Identifiable, Equatable {
    let id: String
    let notificationID: String
    let memberID: Int
    let memberName: String
    let scheduledAt: Date?
    let status: MedicationReminderDisplayStatus
    let items: [MedicationReminderDisplayItem]
    let rawBody: String
}

enum MedicationReminderDisplayStatus: Equatable {
    case pending
    case delivered
    case expired
    case invalid
}

struct MedicationReminderDisplayItem: Identifiable, Equatable {
    let id: String
    let planID: Int
    let doseSequence: Int
    let drugName: String?
}
```

注意：

1. Pending 通知和 delivered 通知可能同 ID 同时存在，展示时要去重或分状态展示。
2. 已送达通知如果已被打卡清理，可能已经不存在。
3. 如果 payload 无法解析，也要能展示“无法解析通知”，避免管理页崩溃。

## 6. 操作设计

### 6.1 补齐通知

按钮：

```text
补齐通知
```

行为：

```text
点击补齐通知
  -> 检查系统通知权限
  -> 如果未决定，走 000002 权限说明弹窗
  -> 如果拒绝，提示去设置开启
  -> 如果允许，调用 MedicationReminderSyncCoordinator 重建当前账号未来 7 天通知
  -> 重新加载管理页列表
  -> Toast：通知已补齐
```

说明：

1. 补齐通知不是“追加”，而是按 000002 规则清理旧通知后重建。
2. 不应生成超过 48 条。
3. 补齐后列表应立即刷新。

### 6.2 取消单条

待发送通知支持取消。

行为：

```text
点击取消
  -> removeNotification(id)
  -> 刷新列表
  -> Toast：已取消该提醒
```

注意：

1. 如果该通知是聚合通知，取消会取消这个时间点所有聚合剂次提醒。
2. 页面需要在确认文案中提示：“这会取消该时间点的用药提醒”。
3. 取消单条只是本地取消，不修改用药计划的 `reminderEnabled`。
4. 下次“补齐通知”或前台自动重建后，可能再次生成该提醒。

因此如果用户希望长期不提醒，应引导去编辑用药计划关闭提醒。

### 6.3 清除全部

按钮：

```text
清除全部
```

行为：

```text
点击清除全部
  -> 弹确认框
  -> removeAllMedicationNotifications(forAccountID)
  -> 刷新列表
  -> Toast：已清除全部用药提醒
```

确认文案：

```text
确定要清除本机已注册的全部用药提醒吗？
这不会关闭用药计划中的提醒开关；下次补齐通知或自动重建后，提醒可能再次出现。
```

## 7. 与 000002 的关系

本工单不重新实现通知调度，只做查看和管理。

必须复用：

```text
MedicationReminderNotificationManager
MedicationReminderSyncCoordinator
MedicationReminderPayloadParser
MedicationReminderNotification.identifierPrefix(accountID:)
MedicationReminderPermissionCoordinator
MedicationReminderPreferencesStore
```

不能新增第二套：

1. notification identifier 规则。
2. userInfo 解析规则。
3. pending/delivered 过滤规则。
4. 权限请求逻辑。
5. 补齐通知逻辑。

## 8. UI 细节

### 8.1 空态

无通知时展示：

```text
图标：bell.slash
标题：暂无用药提醒
说明：开启用药提醒后，将在这里显示本机未来提醒。
按钮：补齐通知
```

### 8.2 权限提示

如果系统通知权限未开启：

```text
系统通知未开启，可能错过用药提醒。
```

操作：

```text
去设置
```

### 8.3 隐私提示

如果“通知中显示药品名称”开启：

```text
当前通知可能在锁屏显示药品名称。
```

如果关闭：

```text
通知默认不显示药品名称。
```

该提示不必占用太大空间，可放在列表页顶部小提示里。

### 8.4 Toolbar

右上角建议：

```text
补齐通知
清除全部
```

如果空间紧张，使用 `Menu`：

```swift
Menu {
    Button("补齐通知") { ... }
    Button("清除全部", role: .destructive) { ... }
} label: {
    Image(systemName: "ellipsis.circle")
}
```

## 9. 影响文件

### 9.1 主要改动文件

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderNotificationManager.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderModels.swift
SparkClient/SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
SparkClient/SparkClient/Projects/App/Resources/en.lproj/Localizable.strings
```

### 9.2 建议新增文件

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderManagementPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderManagementViewModel.swift
```

## 10. 验收标准

1. `MedicationsListPage` 右上角展示“已有通知”入口。
2. 点击入口进入用药通知管理页。
3. 页面能展示当前账号 pending 用药通知。
4. 页面能展示当前账号 delivered 用药通知。
5. 非当前账号通知不展示。
6. 非用药通知不展示。
7. 待发送数量和已送达数量统计正确。
8. 同一分钟聚合通知能展示多项用药。
9. 点击“补齐通知”后，未来 7 天通知按 000002 规则重建。
10. 点击“取消”后，该条 pending 通知消失。
11. 点击“清除全部”后，当前账号用药通知全部清理。
12. 清除全部不修改用药计划 `reminderEnabled`。
13. 通知权限未开启时，页面展示权限提示。
14. 无通知时展示空态，不崩溃。
15. payload 无法解析的旧通知能展示为不可识别项或被安全忽略，不崩溃。

## 11. 测试建议

### 11.1 手工测试

| 场景 | 预期 |
| --- | --- |
| 有 3 条 pending 用药通知 | 页面显示待发送 3 |
| 有 delivered 通知 | 页面显示已送达数量 |
| 当前账号切换 | 只显示当前账号通知 |
| 点击补齐通知 | 刷新后 pending 列表更新 |
| 取消单条 pending | 该条从列表移除 |
| 清除全部 | 当前账号用药通知全部清空 |
| 通知权限关闭 | 展示权限提示 |
| 无用药通知 | 展示空态 |

### 11.2 回归测试

1. 管理页取消通知后，不影响用药计划本身。
2. 管理页清除全部后，重新进入 App 或点击补齐可按规则重建。
3. 点击通知仍能走 000002 的冷启动目标页面公共调度。
4. 打卡后当前剂次通知仍会被清理。
5. 设置“通知中显示药品名称”后，补齐通知生成的新文案符合设置。

---

## 工单 `MEDICATION-EXECUTION-000004`：共享成员用药通知协同详细设计

### 工单状态

需求设计中。

### 需求来源

来源讨论文档：

```text
/Users/hua/Downloads/Reference/SparkClient/需求文档/医疗档案/用药日常工单/用药通知需求讨论文档.md
工单：MEDICATION-NOTIFICATION-000002
```

已确认口径：

1. 本人用药计划开启提醒：继续走 `MEDICATION-EXECUTION-000002` 的本机本地通知闭环。
2. 非本人成员且没有其他用户绑定为本人：保存开启提醒计划后优先走成员分享流程；用户取消分享后，再询问是否在本机为该计划创建用药提醒。
3. 非本人成员且已有其他用户绑定为本人：不走分享流程；服务端通过公共通知能力给本人用户发送一次 APNs：“某某维护了你的用药计划”；客户端提示后结束。
4. “是否为他人创建本机提醒”改为存在服务端，且登记维度是“当前登录用户 + 服药计划 ID”，不是只关联成员。
5. 客户端不再新增、不再使用 `MedicationReminderConsentStore`；已经存在的本地 consent 相关代码需要清理，后续全部通过服务端接口判断。
6. 不考虑本地 consent 数据迁移，全新切换到服务端授权方案。
7. 服务端不做剂次定时调度，不生成未来每次用药提醒任务；本机提醒仍由客户端根据服务端返回的计划编译本地通知。

## 1. 目标

### 1.1 业务目标

1. 维护本人用药计划时，本机立即同步本地通知。
2. 维护非本人成员用药计划时，按成员是否已有“本人用户”分流：无本人用户先引导分享；有本人用户则通知本人用户。
3. 用户明确同意“为他人计划在本机提醒”后，把同意关系登记到服务端。
4. 补全本机通知时，一次性查询当前用户名下“本人成员”的已开启提醒用药计划，以及当前用户已同意“为他人本机提醒”的具体用药计划。
5. 客户端本地通知仍保持离线触发，不引入服务端定时调度。
6. 公共 APNs 只用于“有人维护了你的用药计划”这种资源变更告知，不用于到点吃药提醒。

### 1.2 非目标

1. 不做服务端按剂次定时推送。
2. 不做跨设备统一去重。
3. 不做家属代提醒完整权限体系。
4. 不做本地旧 consent 数据迁移。
5. 不把 owner/admin 直接当作“本人用户”通知。
6. 不在 APNs payload 中携带药品名、剂量、病情等敏感信息。

## 2. 关键业务规则

### 2.1 成员身份规则

| 场景 | 判断 | 行为 |
| --- | --- | --- |
| 本人成员 | 当前用户与成员绑定关系 `relationship = self` 且 active | 默认允许本机提醒，不需要额外授权登记 |
| 非本人成员，无其他本人用户 | 当前用户不是 self，且成员没有其他 active self 绑定用户 | 保存开启提醒计划后优先打开分享；取消分享后询问是否为该计划本机提醒 |
| 非本人成员，有其他本人用户 | 当前用户不是 self，且成员存在其他 active self 绑定用户 | 不打开分享；服务端通知本人用户；客户端不默认创建本机提醒 |
| 非本人计划，用户已在服务端同意 | 存在 `user_id + medication_plan_id + enabled=true` 登记 | 补全本地通知时纳入该计划 |
| 非本人计划，用户未同意 | 无登记或 `enabled=false` | 补全本地通知时跳过 |

注意：服务端登记是计划级，不是成员级。用户同意 A 成员的某个计划，不代表自动同意该成员未来所有计划。

### 2.2 为什么从成员级改为计划级

成员级授权的问题：

1. 授权范围过大。用户只是同意提醒“这次新建的降压药计划”，不等于同意该成员后续所有用药计划。
2. 删除或停用计划后难以解释。成员级同意还在，但具体哪些计划应该提醒需要额外过滤。
3. 审计不清晰。后台无法回答“用户为什么会收到这个服药计划的提醒”。
4. 多计划场景会误提醒。一个成员可能有临时用药、长期用药、按需用药，提醒意愿不同。

计划级授权收益：

1. 授权边界精确，和用户当次确认动作一致。
2. 查询补全简单，只返回明确授权过的计划。
3. 删除/停用/关闭提醒时可以自然失效。
4. 未来做后台审计、撤销授权、通知管理时都有明确对象。

## 3. 服务端数据模型设计

### 3.1 新增模型：MedicationReminderLocalAuthorization

建议新增在：

```text
SparkService/medical/models.py
```

模型语义：

```text
某个登录用户是否同意在自己的设备上，为某个非本人用药计划创建本地通知。
```

建议字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | BigAutoField | 主键 |
| `user` | FK(User) | 同意创建本机提醒的用户 |
| `member` | FK(Member) | 冗余记录计划所属成员，便于查询和审计 |
| `medication_plan` | FK(MedicationPlan) | 具体服药计划 ID，核心关联字段 |
| `enabled` | Boolean | 是否启用该计划的本机提醒授权 |
| `source` | CharField | 来源：`share_cancel_confirm`、`manual_manage`、`api` 等 |
| `created_at` | DateTime | 创建时间 |
| `updated_at` | DateTime | 更新时间 |

约束与索引：

| 约束/索引 | 说明 |
| --- | --- |
| unique(`user`, `medication_plan`) | 同一用户对同一计划只有一条授权记录 |
| index(`user`, `enabled`) | 补全本机通知时按用户查询 |
| index(`member`, `enabled`) | 后台排查成员授权 |
| index(`medication_plan`, `enabled`) | 计划删除/停用/查询授权用户 |

建议模型名不要叫 `Consent`：

1. `Consent` 容易被理解为医疗授权或隐私同意，语义过重。
2. 这里本质是“是否允许在本用户设备创建本地提醒”的功能授权。
3. 推荐 `MedicationReminderLocalAuthorization` 或 `MedicationPlanLocalReminderAuthorization`。

### 3.2 删除/停用时的处理

| 场景 | 处理 |
| --- | --- |
| 计划软删除 | 授权记录可保留但查询补全必须过滤；也可在删除事务后置 `enabled=false` |
| 计划关闭提醒 | 查询补全过滤；建议同步置 `enabled=false`，便于后台解释 |
| 计划暂停/过期 | 查询补全过滤，不一定需要改授权记录 |
| 成员解绑 | 用户不再可访问该成员时，查询不返回；旧授权不迁移、不删除也不能生效 |
| 成员删除 | 跟随现有成员/计划删除策略；授权记录需要避免孤儿数据 |

## 4. 服务端接口设计

### 4.1 查询开启提醒计划聚合接口

路径沿用现有规划：

```text
GET /api/v1/medical/medication-reminders/enabled-plans/
```

用途：客户端补全本机通知，只调用一次，不按成员循环请求。

请求参数：

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `window_start` | 否 | 本地通知编译窗口开始时间，ISO8601 |
| `window_end` | 否 | 本地通知编译窗口结束时间，ISO8601 |
| `include_records` | 否 | 是否返回窗口内用药记录，默认 true |

返回范围：

1. 当前用户可访问成员中，关系为 `self` 的成员，且计划 `reminder_enabled=true`、状态有效、时间覆盖窗口。
2. 当前用户在 `MedicationReminderLocalAuthorization` 中 `enabled=true` 的具体计划，且该计划仍可访问、仍开启提醒、状态有效、时间覆盖窗口。
3. 不返回未授权的非本人计划。
4. 不返回仅因 owner/admin 权限可见但未授权提醒的计划。

建议响应结构：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "window_start": "2026-06-16T00:00:00+08:00",
    "window_end": "2026-06-23T00:00:00+08:00",
    "groups": [
      {
        "member": {
          "id": 100,
          "name": "妈妈",
          "relationship": "mother",
          "is_self_member": false
        },
        "source": "authorized_plan",
        "plans": [],
        "records": []
      }
    ]
  }
}
```

`source` 建议取值：

| 值 | 说明 |
| --- | --- |
| `self_member` | 当前用户本人成员计划 |
| `authorized_plan` | 当前用户已同意为该具体计划本机提醒 |

### 4.2 成员通知归属接口

路径沿用现有规划：

```text
GET /api/v1/medical/members/{member_id}/notification-ownership/
```

用途：保存用药计划后，客户端判断下一步是本机通知、分享流程，还是提示已通知本人用户。

返回建议：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "member_id": 100,
    "is_current_user_self_member": false,
    "has_other_self_owner": true,
    "can_share": true,
    "can_write_medication_plan": true,
    "self_owners": [
      {
        "user_id": 265,
        "display_name": "Apple User",
        "has_apns": true,
        "notifications_enabled": true
      }
    ]
  }
}
```

权限规则：

1. 当前用户无成员访问权限：返回 403 或业务错误。
2. 当前用户无写入用药计划权限：`can_write_medication_plan=false`，保存计划入口不应继续。
3. `relationship=self` 与 `role=owner/admin` 必须分开判断。

### 4.3 计划级本机提醒授权接口

新增接口：

```text
PUT /api/v1/medical/medication-reminders/local-authorizations/{plan_id}/
DELETE /api/v1/medical/medication-reminders/local-authorizations/{plan_id}/
```

推荐首版用 `PUT by plan_id`，客户端简单、幂等。

PUT 请求：

```json
{
  "enabled": true,
  "source": "share_cancel_confirm"
}
```

PUT 处理：

1. 校验当前用户可访问该计划所属成员。
2. 校验该计划 `reminder_enabled=true` 且状态允许提醒。
3. 如果当前用户本来就是该成员本人，返回成功但不创建授权记录，避免数据冗余。
4. 对非本人计划执行 upsert：`user + medication_plan` 唯一。
5. 返回当前授权状态。

响应：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "id": 12,
    "user_id": 265,
    "member_id": 100,
    "medication_plan_id": 88,
    "enabled": true,
    "source": "share_cancel_confirm",
    "updated_at": "2026-06-16T10:00:00Z"
  }
}
```

DELETE 处理：

1. 用于通知管理页或未来计划详情页关闭“本机提醒这个他人计划”。
2. 将 `enabled=false` 或软删除授权记录，推荐 `enabled=false`，便于审计。
3. 客户端成功后触发本机通知重建。

### 4.4 公共健康资源变更 APNs

服务端在用药计划保存成功后，如果是“非本人 + 有其他本人用户”，通过公共通知能力只发 APNs：

```text
某某维护了你的用药计划
```

触发点：

1. `MedicationPlanViewSet` 创建/更新。
2. `MedicationPlanWorkflowSaveView` AI 工作流保存。
3. 其他未来会创建/更新用药计划的入口必须复用同一服务方法。

要求：

1. 使用 `transaction.on_commit` 后发送，避免保存失败但通知已发。
2. 只通知其他 `relationship=self` 用户，不通知当前操作者自己。
3. 不把 owner/admin 当作通知兜底目标。
4. APNs payload 不含药品名、剂量、病情。
5. APNs 失败不影响保存结果。

建议 payload：

```json
{
  "type": "health_resource_changed",
  "resource_type": "medication_plan",
  "resource_id": 88,
  "member_id": 100,
  "action": "updated",
  "actor_display_name": "赵道凯"
}
```

## 5. 客户端 API 与模型设计

### 5.1 API 文件

需要更新：

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/SparkMedicalQueryAPI.swift
```

建议新增方法：

```swift
func listMedicationReminderEnabledPlans(
    windowStartDate: Date?,
    windowEndDate: Date?,
    includeRecords: Bool
) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse

func fetchMemberNotificationOwnership(
    memberID: Int
) async throws -> SparkMedicalSyncAPI.RemoteMemberNotificationOwnership

func upsertMedicationReminderLocalAuthorization(
    planID: Int,
    enabled: Bool,
    source: String
) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization

func disableMedicationReminderLocalAuthorization(
    planID: Int
) async throws
```

DTO 命名建议：

| DTO | 说明 |
| --- | --- |
| `RemoteMedicationReminderEnabledPlansResponse` | 聚合响应 |
| `RemoteMedicationReminderMemberGroup` | 按成员分组的计划和记录 |
| `RemoteMedicationReminderMemberSummary` | 成员摘要 |
| `RemoteMemberNotificationOwnership` | 成员本人绑定和 APNs 能力 |
| `RemoteMedicationReminderLocalAuthorization` | 服务端计划级授权记录 |

编码规范：

1. 不手写无必要 `CodingKeys`。
2. 使用项目统一 `JSONEncoder.default` / `JSONDecoder.default`。
3. 字段命名保持 Swift 驼峰，依赖 convertToSnakeCase / ISO8601 日期策略。

### 5.2 清理本地 consent

需要清理或停用：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift
```

要求：

1. 不再新增本地 `MedicationReminderMemberConsent`。
2. 不再通过 UserDefaults 保存 `accountID + memberID` 同意关系。
3. `MedicationReminderSyncCoordinator` 不再依赖本地 consent 过滤。
4. 已有相关调用点全部改成服务端授权接口。
5. 不做旧 UserDefaults key 迁移；可以保留无害清理逻辑，但不能再参与业务判断。

## 6. 客户端流程设计

### 6.1 保存本人计划

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> fetchMemberNotificationOwnership(memberID)
  -> isCurrentUserSelfMember == true
  -> 走 000002 本机通知权限/重建流程
```

注意：本人成员不需要写 `MedicationReminderLocalAuthorization`。

### 6.2 保存非本人计划：无本人用户

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> isCurrentUserSelfMember == false
  -> hasOtherSelfOwner == false
  -> 打开 ShareSheet
```

分享结果：

```text
用户完成分享
  -> 结束
  -> 不立即创建本机通知

用户取消分享
  -> 弹二次确认：是否在本机提醒这个用药计划？
  -> 选择“在本机提醒”
      -> PUT local-authorizations/{plan_id}/ enabled=true
      -> 请求系统通知权限
      -> rebuild 本机通知
  -> 选择“暂不提醒”
      -> 不写服务端授权
      -> 不创建本机通知
```

文案要从“这个成员”调整成“这个用药计划”，避免用户误解为成员级永久授权。

### 6.3 保存非本人计划：有本人用户

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> hasOtherSelfOwner == true
  -> 服务端公共通知在保存后触发
  -> 客户端不打开 ShareSheet
  -> 客户端不询问是否本机提醒
  -> 提示后结束
```

提示：

```text
如果 selfOwners 中任一 hasApns == true：
  标题：已通知成员本人
  内容：该成员已绑定为其他用户本人，我们会通知对方查看用药计划。

如果 selfOwners 全部 hasApns == false：
  标题：成员本人暂未开启通知
  内容：该成员已绑定为其他用户本人，但对方可能无法收到系统通知。用药计划已保存。
```

### 6.4 补全本机通知

`MedicationReminderSyncCoordinator` 目标流程：

```text
rebuild(accountID)
  -> 检查系统通知权限
  -> GET enabled-plans(window_start, window_end, include_records=true)
  -> 服务端已经完成 self_member / authorized_plan 过滤
  -> 客户端只做计划有效性二次保护和本地编译
  -> MedicationReminderScheduleCompiler 生成未来窗口 events
  -> 截断到 maxPendingCount
  -> notificationManager.rebuild(events, accountID)
```

客户端不再做：

```text
for member in members 循环请求计划和记录
读取 MedicationReminderConsentStore
按 memberID 判断是否 consent
```

异常策略：

| 场景 | 处理 |
| --- | --- |
| `enabled-plans` 请求失败 | 不清空已有本地通知；记录 warning |
| 服务端返回空 | 清空当前账号用药通知 |
| 某个计划 DTO 异常 | 跳过该计划，不影响其他计划 |
| 系统通知权限关闭 | 不注册通知，保留计划数据 |
| 授权接口失败 | 保存计划不回滚；提示“用药计划已保存，提醒状态稍后同步” |

## 7. 页面挂载点

主要页面：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
```

需要接入：

1. 新建用药计划保存成功后。
2. 编辑用药计划保存成功后。
3. AI 工作流保存用药计划成功后。
4. 通知管理页未来取消某个他人计划提醒时。

建议新增：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderOwnershipCoordinator.swift
```

职责：

1. 保存后根据 `memberID + planID + reminderEnabled` 编排分流。
2. 查询 `notification-ownership`。
3. 本人成员转交 000002 本地通知同步。
4. 非本人无本人用户，通知页面打开 ShareSheet。
5. 分享取消后，通知页面展示计划级本机提醒确认。
6. 用户确认后调用服务端授权接口。
7. 非本人有本人用户，展示“已通知本人/暂未开启通知”。

建议 action：

```swift
enum MedicationReminderPostSaveAction: Equatable {
    case none
    case requestLocalNotificationForSelf(planID: Int)
    case openShare(memberID: Int, planID: Int)
    case showLocalReminderConfirm(memberID: Int, planID: Int, memberName: String)
    case showOwnerNotified(memberName: String, apnsAvailable: Bool)
}
```

## 8. 文件影响清单

### 8.1 客户端

| 文件 | 改动 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 新增远程 DTO：enabled plans、ownership、local authorization |
| `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/SparkMedicalQueryAPI.swift` | 新增聚合查询、归属查询、计划级授权 upsert/disable 方法 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift` | 使用 `enabled-plans` 聚合接口；删除本地 consent 过滤；服务端返回什么就编译什么 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift` | 删除或停用；不得再参与业务判断 |
| 新增 `MedicationReminderOwnershipCoordinator.swift` | 保存后协同流程编排 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift` | 保存成功后接入 ownership 流程；挂载 ShareSheet 和计划级二次确认 |
| `SparkClient/SparkClient/Projects/Features/Share/Presentation/ShareSheet.swift` | 建议增加完成/取消回调，避免只依赖 `onDisappear` |
| `SparkClient/SparkClient/Projects/Core/Notification/Application/HandleRemoteNotificationUseCase.swift` | 增加 `health_resource_changed` type 解析与路由 |
| `SparkClient/SparkClient/Projects/App/Sources/App/Architecture/LaunchIntent.swift` | 如需要，新增健康资源变更目标 |
| `SparkClient/SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | 新增中文文案 |
| `SparkClient/SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | 新增英文文案 |

### 8.2 服务端

| 文件 | 改动 |
| --- | --- |
| `SparkService/medical/models.py` | 新增 `MedicationReminderLocalAuthorization` 计划级授权模型 |
| `SparkService/medical/urls.py` | 注册 `enabled-plans`、`notification-ownership`、`local-authorizations/{plan_id}` |
| `SparkService/medical/views.py` | 新增/调整接口 View；用药计划保存后触发公共通知服务 |
| `SparkService/medical/serializers.py` | 新增响应 serializer 或 dict builder |
| `SparkService/medical/services/medication_reminder_service.py` | 聚合查询本人成员计划 + 已授权他人计划；授权 upsert/disable |
| `SparkService/medical/services/health_resource_change_notification_service.py` | 公共健康资源变更 APNs 通知服务 |
| `SparkService/accounts/services/notification_service.py` | 复用现有 APNs 通知能力；原则上只补公共封装 |
| `SparkService/medical/tests*.py` | 新增模型、接口、权限、过滤、通知触发测试 |
| 迁移文件 | 新增授权表迁移；不迁移客户端旧本地 consent |

## 9. 本地化文案

所有新增用户可见文案必须走 `L10n.text`。

建议 key：

| key | 中文文案 |
| --- | --- |
| `medication.reminder.share_first.hint` | 建议先把成员分享给本人或家人，共同接收和管理用药信息。 |
| `medication.reminder.non_self_plan.confirm.title` | 是否在本机提醒这个用药计划？ |
| `medication.reminder.non_self_plan.confirm.message` | 该成员还没有绑定为本人的用户。你可以临时在本机接收这个用药计划的提醒，后续也可以重新分享给本人或家人共同管理。 |
| `medication.reminder.non_self_plan.confirm.accept` | 在本机提醒 |
| `medication.reminder.non_self_plan.confirm.decline` | 暂不提醒 |
| `medication.reminder.owner_notified.title` | 已通知成员本人 |
| `medication.reminder.owner_notified.message` | 该成员已绑定为其他用户本人，我们会通知对方查看用药计划。 |
| `medication.reminder.owner_apns_unavailable.title` | 成员本人暂未开启通知 |
| `medication.reminder.owner_apns_unavailable.message` | 该成员已绑定为其他用户本人，但对方可能无法收到系统通知。用药计划已保存。 |
| `medication.reminder.authorization.saved.toast` | 已在本机开启这个用药计划的提醒。 |
| `medication.reminder.authorization.skipped.toast` | 用药计划已保存，未创建本机提醒。 |
| `medication.reminder.sync_degraded.toast` | 用药计划已保存，提醒状态稍后同步。 |
| `notification.health_resource_changed.medication_plan.title` | 用药计划已更新 |
| `notification.health_resource_changed.medication_plan.body` | 有人维护了你的用药计划，打开应用查看详情。 |
| `notification.health_resource_changed.route_missing.toast` | 用药计划可能已变更。 |

## 10. 日志设计

### 10.1 客户端日志

| 事件 | 时机 | 字段 |
| --- | --- | --- |
| `medication_reminder.ownership.start` | 保存开启提醒计划后开始查归属 | `accountID/memberID/planID/reminderEnabled` |
| `medication_reminder.ownership.success` | 归属查询成功 | `memberID/planID/isSelfMember/hasOtherSelfOwner/selfOwnerCount/canShare/canWrite` |
| `medication_reminder.ownership.failed` | 归属查询失败 | `memberID/planID/error/requestID` |
| `medication_reminder.post_save.self_member` | 本人成员走本机通知流程 | `memberID/planID` |
| `medication_reminder.post_save.open_share` | 非本人且无本人绑定，进入分享 | `memberID/planID` |
| `medication_reminder.post_save.owner_notified` | 非本人且有本人绑定，服务端应通知本人 | `memberID/planID/selfOwnerCount/apnsAvailable` |
| `medication_reminder.local_authorization.upsert.start` | 用户同意计划级本机提醒 | `memberID/planID/source` |
| `medication_reminder.local_authorization.upsert.success` | 服务端授权保存成功 | `memberID/planID/enabled` |
| `medication_reminder.local_authorization.upsert.failed` | 服务端授权保存失败 | `memberID/planID/error/requestID` |
| `medication_reminder.enabled_plans.start` | 补全通知开始请求聚合接口 | `accountID/windowStart/windowEnd/includeRecords` |
| `medication_reminder.enabled_plans.success` | 聚合接口成功 | `memberCount/planCount/recordCount/selfPlanCount/authorizedPlanCount` |
| `medication_reminder.enabled_plans.failed` | 聚合接口失败 | `error/requestID` |
| `medication_reminder.rebuild.compiled` | 补全通知编译完成 | `eventCount/truncatedCount` |

不要记录：药品名称、剂量、病情、完整 APNs payload。

### 10.2 服务端日志

| 事件 | 时机 | 字段 |
| --- | --- | --- |
| `medication_reminder.enabled_plans.request` | 进入聚合接口 | `request_id/user_id/window_start/window_end/include_records` |
| `medication_reminder.enabled_plans.response` | 聚合接口返回前 | `request_id/user_id/member_count/self_plan_count/authorized_plan_count/record_count` |
| `medication_reminder.local_authorization.upsert` | 计划级授权写入 | `request_id/user_id/member_id/plan_id/enabled/source` |
| `medication_reminder.local_authorization.denied` | 授权请求无权限或计划无效 | `request_id/user_id/plan_id/reason` |
| `member_notification_ownership.request` | 进入成员归属接口 | `request_id/user_id/member_id` |
| `member_notification_ownership.response` | 成员归属接口返回前 | `request_id/user_id/member_id/is_self_member/has_other_self_owner/self_owner_count/can_share/can_write` |
| `health_resource_change.notify.resolve_targets` | 公共通知计算目标 | `request_id/actor_user_id/member_id/resource_type/resource_id/action/self_owner_count/target_count` |
| `health_resource_change.notify.skip` | 没有目标或策略禁用 | `request_id/member_id/resource_type/resource_id/reason` |
| `health_resource_change.notify.dispatch` | 即将调用 APNs 通知 | `request_id/target_user_id/target_reason/resource_type/resource_id` |
| `health_resource_change.notify.done` | 单个目标通知完成 | `request_id/target_user_id/status/success_count/failure_count/error_message` |

## 11. 测试方案

### 11.1 服务端测试

| 场景 | 预期 |
| --- | --- |
| 当前用户有本人成员开启提醒计划 | `enabled-plans` 返回该计划，source=`self_member` |
| 当前用户可访问非本人成员但未授权计划 | `enabled-plans` 不返回该计划 |
| 当前用户已授权某个非本人计划 | `enabled-plans` 返回该计划，source=`authorized_plan` |
| 同一非本人成员有 3 个计划，只授权 1 个 | 只返回授权的 1 个计划 |
| 授权计划关闭提醒 | `enabled-plans` 不返回 |
| 授权计划暂停/过期/删除 | `enabled-plans` 不返回 |
| 用户失去成员访问权限 | `enabled-plans` 不返回该计划 |
| 对无权限计划 PUT 授权 | 返回 403 或业务错误，不创建记录 |
| 对本人成员计划 PUT 授权 | 返回成功但不创建冗余授权，或返回 already_self_member |
| 非本人有其他 self owner 保存计划 | 只通知其他 self owner，不通知 owner/admin |
| 当前操作者就是 self owner | 不给自己发资源变更 APNs |
| APNs 不可用 | 保存成功，通知记录 skipped |

### 11.2 客户端测试

| 场景 | 预期 |
| --- | --- |
| 本人开启提醒保存计划 | 正常弹通知权限/重建本机通知 |
| 非本人无 self owner 保存开启提醒计划 | 打开分享流程 |
| 非本人无 self owner，用户取消分享 | 弹“是否在本机提醒这个用药计划” |
| 用户选择在本机提醒 | 调用服务端授权接口，成功后补全通知包含该计划 |
| 用户选择暂不提醒 | 不调用授权接口，不创建本机通知 |
| 非本人有 self owner | 不打开分享，不弹本机提醒，提示已通知本人或对方未开启通知 |
| 补全通知 | 只请求一次 `enabled-plans` |
| 本地 `MedicationReminderConsentStore` 旧数据存在 | 不参与过滤，不影响补全结果 |
| 授权接口失败 | 保存计划不回滚，提示提醒状态稍后同步 |
| 账号切换 | 只使用当前账号服务端返回计划，不读取本地旧 consent |
| 点击资源变更 APNs 且资源不存在 | 使用本地化 Toast 提示并回退列表页 |

### 11.3 回归测试

1. 000002 的本地通知点击进入用药执行中心仍正常。
2. 000003 的已有通知管理页仍能补齐、取消、清除。
3. 本人用药计划保存不被分享流程打断。
4. 非本人关闭提醒保存不弹分享或本机提醒确认。
5. 用药记录打卡后当前剂次通知仍被清理。
6. 新增 UI 文案不出现 Swift 硬编码中文。
7. 客户端不再读取本地 consent 作为业务判断。
8. 服务端日志可通过 request_id 串联保存用药计划、计划级授权、目标计算、APNs 发送或跳过原因。

## 12. 验收标准

1. 服务端新增计划级授权模型，包含 `user_id`、`member_id`、`medication_plan_id`、`enabled`、`source`、时间字段。
2. 授权表具备 `user + medication_plan` 唯一约束。
3. 服务端提供 `GET /api/v1/medical/medication-reminders/enabled-plans/`。
4. `enabled-plans` 返回当前用户本人成员已开启提醒计划。
5. `enabled-plans` 返回当前用户已授权的非本人具体计划。
6. `enabled-plans` 不返回未授权非本人计划。
7. `enabled-plans` 不返回关闭提醒、暂停、过期、删除、无权限访问的计划。
8. 服务端提供 `GET /api/v1/medical/members/{member_id}/notification-ownership/`。
9. 服务端提供计划级授权 upsert/disable 接口。
10. 客户端用户同意“在本机提醒”后调用服务端授权接口，不写本地 UserDefaults consent。
11. 客户端 `MedicationReminderSyncCoordinator` 使用 `enabled-plans` 聚合接口，不再按成员循环请求计划和记录。
12. 客户端补全通知不再读取 `MedicationReminderConsentStore`。
13. `MedicationReminderConsentStore.swift` 删除或停用，相关业务调用清理干净。
14. 非本人成员且没有其他本人绑定时，保存开启提醒计划后优先打开分享流程。
15. 用户取消分享后，才询问是否在本机提醒这个用药计划。
16. 非本人成员且已有其他本人绑定时，客户端不走分享流程，不询问本机提醒。
17. 非本人成员且已有其他本人绑定时，服务端发送一次公共 APNs 告知本人用户。
18. APNs 文案和 payload 不包含药品名、剂量、病情。
19. 当前操作者就是本人用户时，不给自己发送资源变更 APNs。
20. 用药计划首版不把 owner/admin 作为公共 APNs 接收者。
21. APNs 发送失败不影响用药计划保存。
22. 客户端新增 UI 文案全部写入 `zh-Hans.lproj/Localizable.strings` 与 `en.lproj/Localizable.strings`。
23. 客户端关键流程具备日志：归属查询、分享打开/取消、计划级授权、`enabled-plans` 成功/失败、补全编译、资源变更 APNs 路由。
24. 服务端关键流程具备日志：`enabled-plans` 请求/响应、授权 upsert/disable、`notification-ownership` 请求/响应、公共通知目标计算、发送、跳过、失败。
25. 000002 本地通知闭环不回归。
26. 000003 通知管理页补齐通知使用新聚合接口后仍可正常刷新列表。

## 13. 实施顺序建议

1. 服务端新增 `MedicationReminderLocalAuthorization` 模型和迁移。
2. 服务端实现计划级授权 upsert/disable 接口和权限校验。
3. 服务端调整 `enabled-plans`：返回本人成员计划 + 已授权非本人计划。
4. 服务端实现或校正 `notification-ownership`。
5. 服务端实现公共健康资源变更 APNs，并挂到所有用药计划保存入口。
6. 客户端新增远程 DTO 和 API 方法。
7. 客户端停用/删除 `MedicationReminderConsentStore` 及其调用。
8. 客户端改造 `MedicationReminderSyncCoordinator` 使用 `enabled-plans`。
9. 客户端新增/调整 `MedicationReminderOwnershipCoordinator`，保存后按 planID 编排授权。
10. 接入 `ShareSheet` 结果回调和计划级二次确认。
11. 接入 `health_resource_changed` APNs 点击路由。
12. 补齐客户端本地化 key，移除新增硬编码中文。
13. 补齐客户端/服务端关键流程日志和关键注释。
14. 回归 000002 / 000003。

---

## 工单 `MEDICATION-EXECUTION-000005`：用药通知计划级服务端授权收敛改造

### 工单状态

需求设计中。

### 需求来源

本工单是对 `MEDICATION-EXECUTION-000004` 的进一步收敛。

本次确认口径：

1. “是否为他人创建通知”不再存在客户端本地，全部改为服务端存储。
2. 存储粒度不是 `user_id + member_id`，而是 `user_id + medication_plan_id`。
3. 本机本地通知仍由客户端调度，但客户端只消费服务端结果，不再保留本地 consent 判定。
4. 查询开启提醒计划时，需要同时覆盖两类计划：
   `当前用户名下本人成员的、已开启通知的服药计划`
   `当前用户已在服务端登记允许本机提醒的、非本人具体服药计划`
5. 现有本地 `MedicationReminderConsentStore.swift` 不做迁移，直接废弃业务作用。

### 1. 当前现状与问题

当前代码现状：

1. 服务端已有：
   `GET /api/v1/medical/medication-reminders/enabled-plans/`
   `GET /api/v1/medical/members/{member_id}/notification-ownership/`
2. 客户端 `MedicationReminderSyncCoordinator` 仍然会在 `enabled-plans` 返回后，再调用 `MedicationReminderConsentStore` 做一次本地过滤。
3. 客户端 `MedicationReminderOwnershipCoordinator` 在用户同意为非本人提醒时，仍写入本地 `UserDefaults`。
4. 服务端 `enabled-plans` 现状是“按当前用户可访问成员全量返回”，还没有基于“服务端已授权计划”做过滤。
5. 服务端目前没有计划级授权表，也没有把“当前用户是否已授权这个计划”挂到用药计划返回模型里。

对应代码位置：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderOwnershipCoordinator.swift
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalQueryAPI.swift
SparkService/medical/urls.py
SparkService/medical/services/medication_reminder_service.py
```

问题本质：

1. 判定源分裂：
   服务端返回一份计划，客户端本地再过滤一遍，最终“为什么提醒 / 为什么不提醒”无法单点解释。
2. 授权粒度不够精确：
   如果继续按成员维度存储，会把“我同意这一次的某个计划提醒”扩大成“我同意这个成员未来所有计划提醒”。
3. 多设备行为不一致：
   本地 `UserDefaults` 无法跨设备同步，换设备后通知补全结果会变。
4. 代码清理不彻底：
   即使接口已经往服务端靠，客户端仍然保留本地 consent，会让后续实现持续摇摆。

### 2. 设计目标

本工单只解决一件事：

```text
把“是否允许在当前账号设备上，为某个非本人服药计划创建本机提醒”收口到服务端，以服药计划 ID 为唯一业务对象。
```

目标拆解：

1. 服务端成为唯一授权源。
2. 客户端不再读取、不再写入本地 consent。
3. `enabled-plans` 与用药计划详情/列表，共同复用同一套计划级授权字段。
4. 授权对象是具体 `medication_plan_id`，不是成员级。
5. 不做旧本地数据迁移。
6. 不改成服务端到点推送；仍旧是客户端本地通知编译。

### 3. 服务端模型设计

#### 3.1 新增模型

建议新增模型：

```text
MedicationReminderLocalAuthorization
```

放置位置：

```text
SparkService/medical/models.py
```

字段建议：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | BigAutoField | 主键 |
| `user` | FK(User) | 当前登录用户，表示“谁要在自己设备上收这个提醒” |
| `member` | FK(Member) | 冗余成员，用于排查、过滤、列表分组 |
| `medication_plan` | FK(MedicationPlan) | 具体服药计划 ID，核心字段 |
| `enabled` | Boolean | 当前授权是否有效 |
| `source` | CharField | 来源，如 `share_cancel_confirm`、`notification_management`、`api` |
| `created_at` | DateTime | 创建时间 |
| `updated_at` | DateTime | 更新时间 |

约束与索引：

| 约束/索引 | 说明 |
| --- | --- |
| `unique(user, medication_plan)` | 同一用户对同一计划只有一条记录 |
| `index(user, enabled)` | 补全通知主查询入口 |
| `index(member, enabled)` | 成员排查与统计 |
| `index(medication_plan, enabled)` | 计划停用、删除、回收授权时快速定位 |

#### 3.2 为什么必须带 `medication_plan_id`

原因：

1. 用户确认动作本身就是针对“当前这个计划”。
2. 同一个成员可能同时有长期药、临时药、按需药，不应被一次确认全部放开。
3. 通知管理页未来做“取消这个计划提醒”时，计划级模型更自然。
4. 后台审计能够明确回答：
   “用户为什么收到这个计划的提醒”
   “是哪次流程登记了这条授权”

#### 3.3 存储层与返回层分离

本工单明确采用下面的分层：

```text
存储层：独立授权关系表
返回层：把当前用户视角的授权状态挂到 MedicationPlan DTO
```

原因：

1. 这个状态本质上不是 `MedicationPlan` 自身的公共字段，而是 `当前用户 + 当前计划` 的关系字段。
2. 如果把它直接做成 `MedicationPlan` 表里的布尔字段，会出现多用户共享时语义错误。
3. 但如果完全不回填到 DTO，客户端接入又会被迫额外查状态，链路变重。

因此最终方案是：

1. 数据库存储仍然独立。
2. 查询计划时，把授权状态按“当前请求用户”回填到计划模型。
3. 客户端只消费计划里的派生字段，不再维护本地判断。

### 4. 服务端接口设计

#### 4.1 保留并改造 `enabled-plans`

接口路径保持：

```text
GET /api/v1/medical/medication-reminders/enabled-plans/
```

职责改为：

1. 返回当前用户“本人成员”的开启提醒计划。
2. 返回当前用户已在服务端授权的“非本人具体计划”。
3. 不再返回未授权的非本人计划。
4. `plans` 内每个 `MedicationPlan` 节点都带出当前用户视角的授权字段。
5. 不依赖客户端再做 consent 过滤。

过滤规则：

1. 计划必须 `reminder_enabled = true`。
2. 计划必须状态有效，例如 `ACTIVE`。
3. 计划必须仍在通知窗口内有效。
4. 当前用户必须对该计划所属成员仍有访问权限。
5. 非本人计划必须存在 `MedicationReminderLocalAuthorization.enabled = true`。

计划返回模型建议补充字段：

```text
localReminderAuthorizationEnabled: Bool
localReminderAuthorizationSource: String?
localReminderAuthorizationUpdatedAt: String?
```

字段语义必须固定为：

```text
当前登录用户，对这个服药计划，是否已在服务端登记允许在本机创建提醒
```

不是计划本身的公共状态。

建议响应结构继续沿用当前 DTO，但补充来源字段：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "window_start_date": "2026-06-16",
    "window_end_date": "2026-06-23",
    "members": [
      {
        "member": {
          "id": 100,
          "name": "妈妈",
          "relationship": "mother",
          "is_self_member": false,
          "binding_role": "editor",
          "can_share": true,
          "can_write": true
        },
        "source": "authorized_plan",
        "self_owners": [],
        "plans": [],
        "records": []
      }
    ]
  }
}
```

`source` 建议取值：

| 值 | 说明 |
| --- | --- |
| `self_member` | 本人成员计划 |
| `authorized_plan` | 服务端已授权的非本人具体计划 |

#### 4.2 保留 `notification-ownership`

接口路径保持：

```text
GET /api/v1/medical/members/{member_id}/notification-ownership/
```

这个接口职责不变，仍用于保存计划后判断分流：

1. 当前用户是不是该成员本人。
2. 是否已有其他 `relationship=self` 的本人用户。
3. 是否应该走分享流程。
4. 是否应该只提示“已通知本人”。

注意：

1. 这个接口判断的是成员归属，不承担计划级授权查询。
2. 计划级授权状态不通过这个接口查询，而是通过用药计划 DTO 字段回传。

#### 4.3 不新增独立授权查询接口，写入并回现有用药计划链路

本次确认不新增单独的“授权查询接口”。

更进一步建议：

1. 不新增单独的“授权写入接口”。
2. 把“是否为当前用户登记这个非本人计划的本机提醒资格”并入现有用药计划保存链路。

推荐做法：

1. `MedicationPlanViewSet` 的 create / update。
2. `MedicationPlanWorkflowSaveView`。
3. 其他所有创建或修改 `MedicationPlan` 的工作流入口。

统一支持一个可选入参，例如：

```text
local_reminder_authorization_for_current_user
```

建议语义：

| 值 | 说明 |
| --- | --- |
| `nil` | 本次不改授权状态 |
| `true` | 为当前用户登记该计划的本机提醒资格 |
| `false` | 取消当前用户对该计划的本机提醒资格 |

服务端保存规则：

1. 如果当前用户是该成员本人：
   忽略该字段，不写冗余授权关系。
2. 如果当前用户是非本人且字段为 `true`：
   对 `user + medication_plan` 做 upsert，`enabled=true`。
3. 如果当前用户是非本人且字段为 `false`：
   将现有授权关系置为 `enabled=false`。
4. 如果字段未传：
   不改动现有授权关系。

这样做的结果：

1. 保存计划和维护本机提醒资格可以在一次提交内完成。
2. 不需要再额外走一条授权状态查询链路。
3. 计划保存成功后，客户端拿到返回的 `MedicationPlan`，即可知道当前用户视角授权状态。

#### 4.4 服务端 URL 注册

本次不为授权关系单独新增 URL。

仍然需要保留并复用：

```text
SparkService/medical/urls.py
```

重点是改造现有用药计划保存/查询接口的序列化与业务逻辑。

### 5. 服务端查询与业务实现

建议新增服务文件：

```text
SparkService/medical/services/medication_reminder_authorization_service.py
```

职责拆分：

1. `resolve_local_authorization(user, plan_id)`：
   查询当前用户对某个计划是否已授权。
2. `apply_local_authorization_change(user, plan, desired_value, source)`：
   在计划保存流程中写入或取消授权。
3. `serialize_local_authorization_for_user(user, plan)`：
   把当前用户视角授权状态回填到计划 DTO。
4. `list_enabled_reminder_plans_for_user(user, window, include_records)`：
   汇总本人成员计划 + 已授权非本人计划。

建议同时改造：

```text
SparkService/medical/services/medication_reminder_service.py
```

改造重点：

1. 现有 `build_enabled_plans_response(...)` 不能再按“当前用户可访问的所有成员”直接循环。
2. 需要先分两批算计划：
   `self member plans`
   `authorized non-self plans`
3. 每个 plan 在序列化时都补充当前用户视角的授权字段。
4. 再按成员聚合输出，避免同一成员重复分组。
5. `records` 查询仍按最终纳入的成员集合拉取。

建议流程：

```text
查询当前用户 active bindings
  -> 找到 relationship=self 的 member ids
  -> 查这些 member 的 enabled plans

查询当前用户 enabled=true 的 MedicationReminderLocalAuthorization
  -> 关联 medication_plan
  -> 过滤计划已删除 / 提醒关闭 / 不再可访问 / 状态失效
  -> 得到 authorized non-self plans

合并两批计划
  -> 为每个 plan 回填当前用户视角授权字段
  -> 按 member_id 分组
  -> 生成 members[group]
  -> 按最终 member ids 查询窗口内 records
  -> 输出响应
```

### 6. 客户端改造设计

#### 6.1 API 层新增与调整

客户端需要补充到：

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
```

调整现有 DTO：

1. `RemoteMedicationReminderMemberGroup` 增加 `source`。
2. `RemoteMedicationPlan` 增加当前用户视角授权字段：
   `localReminderAuthorizationEnabled`
   `localReminderAuthorizationSource`
   `localReminderAuthorizationUpdatedAt`
3. `RemoteMedicationReminderEnabledPlansResponse` 保持当前结构，避免大面积 UI 重构。

#### 6.2 删除客户端本地 consent 业务依赖

以下文件不再参与业务判断：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift
```

需要清理的点：

1. `MedicationReminderSyncCoordinator` 构造参数去掉 `consentStore`。
2. `MedicationReminderOwnershipCoordinator` 构造参数去掉 `consentStore`。
3. `AppContainer.swift` 与 `FeatureAssemblies.swift` 不再注入 `MedicationReminderConsentStore.shared`。
4. `loadSnapshots(accountID:)` 中去掉 `shouldScheduleLocalReminder(...)` 这层客户端二次过滤。
5. `enabled-plans` 返回什么，客户端就编译什么。

#### 6.3 保存成功后的流程改造

保存用药计划成功后：

```text
本人
  -> requestLocalNotificationForSelf(planID)
  -> 请求系统通知权限
  -> rebuild

非本人 + 无其他 self owner
  -> 先打开分享
  -> 用户取消分享
      -> 弹“是否在本机提醒这个用药计划”
      -> 确认
          -> 保存计划时带 `local_reminder_authorization_for_current_user = true`
          -> 请求通知权限
          -> rebuild
      -> 取消
          -> 如需要清理，则保存计划时带 `local_reminder_authorization_for_current_user = false`
          -> 结束

非本人 + 有其他 self owner
  -> 不分享
  -> 不本机确认
  -> 服务端走公共 APNs 告知对方
  -> 客户端提示后结束
```

这里必须把动作对象从“成员”改为“计划”。

所以 `MedicationReminderPostSaveAction` 建议扩展为带 `planID`：

```swift
enum MedicationReminderPostSaveAction: Equatable {
    case none
    case requestLocalNotificationForSelf(planID: Int)
    case openShare(memberID: Int, planID: Int)
    case showLocalReminderConfirm(memberID: Int, planID: Int, memberName: String)
    case showOwnerNotified(planID: Int, apnsAvailable: Bool)
}
```

#### 6.4 通知补全流程改造

`MedicationReminderSyncCoordinator` 的目标流程：

```text
rebuild(accountID)
  -> 检查通知权限
  -> 请求 enabled-plans
  -> 服务端已过滤掉未授权的非本人计划
  -> 客户端直接编译 events
  -> 注册本地通知
```

客户端不再做：

```text
读取 MedicationPlan.currentUserAuthorization 相关字段
按服务端返回结果直接编译
```

### 7. 影响文件清单

#### 7.1 客户端

| 文件 | 改动 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 为 `RemoteMedicationPlan` 增加当前用户视角授权字段，补充 group source |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift` | 删除本地 consent 过滤，仅消费服务端 `enabled-plans` |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderOwnershipCoordinator.swift` | 用户确认后改为在计划保存链路中提交授权变更字段 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift` | 删除或停用，不再参与任何业务判断 |
| `SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift` | 去掉 consentStore 注入 |
| `SparkClient/SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift` | 去掉 consentStore 注入 |

#### 7.2 服务端

| 文件 | 改动 |
| --- | --- |
| `SparkService/medical/models.py` | 新增 `MedicationReminderLocalAuthorization` |
| `SparkService/medical/views.py` | 改造现有用药计划保存响应与 `enabled-plans`，回填当前用户视角授权字段 |
| `SparkService/medical/services/medication_reminder_service.py` | 重写 `enabled-plans` 汇总逻辑 |
| `SparkService/medical/services/medication_reminder_authorization_service.py` | 新增授权查询、apply、serialize 服务 |
| `SparkService/medical/serializers.py` | 为 `MedicationPlan` 返回模型补充当前用户视角授权字段 |
| `SparkService/medical/tests*.py` | 新增授权模型、过滤与接口测试 |

### 8. 不做事项

本工单明确不做：

1. 不迁移旧的本地 `UserDefaults` consent 数据。
2. 不做服务端到点服药推送。
3. 不做多设备去重策略。
4. 不把成员级授权与计划级授权同时保留。
5. 不继续保留客户端本地 consent 作为兜底逻辑。

### 9. 验收标准

1. 服务端新增计划级授权模型，唯一键为 `user + medication_plan`。
2. 服务端新增计划级授权关系表，但不新增独立授权查询接口。
3. `RemoteMedicationPlan` 返回当前用户视角授权字段。
4. `enabled-plans` 只返回：
   本人成员的已开启提醒计划
   服务端已授权的非本人具体计划
5. `enabled-plans` 不再返回未授权非本人计划。
6. 客户端补全通知不再读取 `MedicationReminderConsentStore`。
7. 客户端用户确认“在本机提醒这个用药计划”后，通过现有计划保存链路提交授权字段。
8. `MedicationReminderConsentStore.swift` 及其注入、调用链全部清理干净或彻底停用。
9. 非本人计划授权状态以服务端为准，换设备后仍能补全同一计划提醒。
10. 关闭提醒、计划停用、计划删除、无权限访问后，`enabled-plans` 不再返回对应计划。
11. 不做旧本地授权迁移也不影响新逻辑运行。

### 10. 实施顺序建议

1. 服务端新增 `MedicationReminderLocalAuthorization` 模型与迁移。
2. 服务端改造用药计划保存链路，支持提交并维护当前用户视角授权状态。
3. 服务端改造 `MedicationPlan` 返回模型和 `enabled-plans` 聚合逻辑。
4. 客户端扩展 `RemoteMedicationPlan` 授权字段。
5. 客户端改造 `MedicationReminderOwnershipCoordinator`，确认后走计划保存链路。
6. 客户端改造 `MedicationReminderSyncCoordinator`，去掉本地 consent 二次过滤。
7. 客户端移除 `AppContainer`、`FeatureAssemblies` 中对 `MedicationReminderConsentStore` 的依赖。
8. 回归 `000002` 与 `000003`，确认通知编排与通知管理页不回退。

---

## 工单 `MEDICATION-EXECUTION-000006`：用药计划编辑页提醒开关与旧协同流程收敛讨论

### 工单状态

需求讨论中。

### 需求来源

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:584-610
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:698-709
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:810-819
SparkService/medical/views.py:1233-1329
```

本工单要讨论的是：在用药计划新增 / 编辑流程里，如何把“非本人提醒协同”从一段固定模块改造成一个更清晰的提醒开关，并把旧的分享 / 本机提醒后置处理流程拆掉，避免编辑页同时承担两套提醒逻辑。

### 1. 当前问题

当前 `MedicationPlanStepperView` 的确认页里，存在一块“非本人提醒协同”区域，里面同时包含：

1. 邀请他人通知用药。
2. 在本机开启通知。

这段逻辑的问题是：

1. 对新建计划、普通编辑、服务端编辑、本地草稿编辑来说，行为并不统一。
2. “是否开启提醒”与“是否触发协同 / 分享 / 授权”混在同一块 UI 里，用户感知不清晰。
3. 当前保存后又有一段额外的后置处理链路，容易和计划保存主流程重复。
4. 本地编辑场景不需要展示这块能力，但当前旧实现并没有清楚拆分。
5. 旧的保存后处理如果继续保留，后续很容易出现重复弹窗、重复同步、重复授权。

### 2. 讨论目标

1. 确认确认页中的协同区域保留“邀请他人通知”，同时把“在本机开启通知”改为“本机提醒开关”。
2. 确认新建 / 普通编辑时默认关闭。
3. 确认服务端编辑时，如果该计划此前已经开启过通知，则默认回填为开启。
4. 确认本地编辑不展示这块模块。
5. 确认保存成功后，再按计划 ID 异步调用授权接口，失败不阻塞主保存。
6. 确认没有开启提醒时，不调用授权接口。
7. 确认旧的协同分享与 post-save 流程可以清理，不再保留双路径。

### 3. 建议口径

#### 3.1 确认页 UI

建议保留原来的“非本人提醒协同”卡片结构，其中：

1. 保留“邀请他人通知”入口。
2. 将“在本机开启通知”文案改为“本机提醒开关”。

```text
邀请他人通知
本机提醒开关
```

展示规则：

| 场景 | 是否展示 | 默认值 |
| --- | --- | --- |
| 新增 | 展示 | 关闭 |
| 服务端编辑 | 展示 | 读取该计划当前是否已开启过通知，若已开启则默认开启 |
| 本地编辑 | 不展示 | 无 |

#### 3.2 保存后的授权同步

保存成功后，按“保存结果里的计划 ID”异步调用服务端授权操作：

1. 开关从关闭变开启：调用新增 / 授权接口。
2. 开关从开启变关闭：调用取消 / 删除接口。
3. 开关没有变化：不调用授权接口。
4. 保存失败：不调用授权接口。
5. 授权接口失败：只记录日志，不影响主保存结果，也不做额外 UI 干预。

#### 3.3 服务端编辑时的默认值回填

服务端编辑进入编辑页时，建议先按计划 ID 查询当前授权状态，再决定开关默认值。这样可以避免用户误以为开启状态丢失。

### 4. 需要清理的旧流程

本工单明确要求清理以下旧逻辑：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:698-709
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:810-819
```

讨论点：

1. 这两段是否属于同一条旧后置流程。
2. 是否可以完全删掉，不再保留兼容分支。
3. 删除后，计划保存主流程是否已经足够覆盖新增 / 编辑 / 授权同步。

### 5. 待确认问题

1. 这里的“是否开启过该用药通知”，是否严格按“当前计划 ID 的计划级授权”判断？
2. 服务端编辑时，若历史上有授权但当前计划已被停用或改成不提醒，默认值是否仍然按授权记录回填？
3. 本地编辑不展示模块后，如果用户希望补开通知，是不是应该等本地草稿转成正式计划后再统一处理？
4. 开关从关到开时，是否还需要触发一次通知重建，还是只在保存成功后让现有主流程完成即可？
5. 如果服务端授权接口成功但本次计划保存失败，是否需要回滚授权？当前倾向是不回滚，但这点需要确认。

### 6. 影响范围

#### 客户端

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanForm/MedicationPlanFormView.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/*
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
```

#### 服务端

```text
SparkService/medical/views.py
SparkService/medical/services/*
SparkService/medical/serializers.py
SparkService/medical/models.py
```

### 7. 建议验收口径

1. 新增 / 编辑页面的提醒开关行为一致。
2. 服务端编辑可回填历史授权开关。
3. 本地编辑不展示该模块。
4. 保存成功后，授权同步是异步的，不阻塞主流程。
5. 开关关闭时不调用授权操作。
6. 旧的分享 / 本机提醒后置流程已清理，不再进入双路径。
7. 相关日志能清楚区分“计划保存成功”和“授权同步成功 / 失败”。

---

## 工单 `MEDICATION-EXECUTION-000007`：用药计划编辑页提醒开关与授权同步详细设计

### 工单状态

需求详细设计中。

### 需求来源

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:584-610
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:599-607
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:698-709
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift:810-819
SparkService/medical/views.py:1233-1329
SparkService/medical/services/medication_reminder_authorization_service.py
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
```

### 1. 设计目标

本工单只解决一件事：

```text
在用药计划新增 / 编辑流程中，把“本机提醒”作为一个明确、可回填、可异步同步的计划级开关；同时保留“邀请他人通知”，并清理旧的 post-save 协同流程。
```

拆解为 5 个落地目标：

1. 确认页保留“邀请他人通知”，并把“在本机开启通知”改成“本机提醒开关”。
2. 新增 / 普通编辑默认关闭本机提醒开关。
3. 服务端编辑时，若该计划已有开启过的授权状态，则默认回填开启。
4. 本地编辑不展示该模块。
5. 保存成功后，按计划 ID 异步调用授权同步接口，失败不阻塞主保存。

### 2. 设计原则

1. 计划保存主流程优先，授权同步是附属动作。
2. 计划级授权必须以 `medication_plan_id` 为唯一粒度。
3. UI 只表达用户意图，不承担授权判定和保存编排。
4. 成功保存后再异步同步，不在编辑页内做多段后置处理。
5. 授权失败只记录日志，不回退主保存结果。

### 3. 页面交互设计

#### 3.1 确认页区域

文件：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift
```

确认页的“非本人提醒协同”卡片保持，内部两个动作并存：

```text
邀请他人通知
本机提醒开关
```

其中：

1. “邀请他人通知”保留原语义，沿用现有 ShareSheet 流程。
2. “在本机开启通知”统一改名为“本机提醒开关”。
3. 本地编辑模式不展示该卡片。

#### 3.2 默认值规则

| 场景 | 是否展示 | 默认值来源 |
| --- | --- | --- |
| 新增 | 展示 | 关闭 |
| 服务端编辑 | 展示 | 当前计划的计划级授权状态 |
| 本地编辑 | 不展示 | 无 |

服务端编辑的默认值回填规则：

1. 进入编辑页时先按计划 ID 查询授权状态。
2. 如果当前用户对该计划已有授权记录，则开关默认开启。
3. 如果没有授权记录，则默认关闭。
4. 回填失败时，按关闭处理，并记录日志。

### 4. 数据与状态设计

#### 4.1 客户端状态

建议在 `MedicationPlanStepperView` 中保留一个独立状态：

```swift
@State private var reminderEnabledOverride: Bool?
```

用于：

1. 服务端编辑进入时回填初始值。
2. 确保 `MedicationPlanFormView` 初始化时草稿值和当前授权状态一致。

#### 4.2 计划级授权状态

授权状态不是计划公共字段，而是当前用户对当前计划的关系字段。

建议在客户端只消费以下返回字段：

```text
localReminderAuthorizationEnabled
localReminderAuthorizationSource
localReminderAuthorizationUpdatedAt
```

语义：

1. `localReminderAuthorizationEnabled` 代表当前用户是否允许该计划在本机创建提醒。
2. `localReminderAuthorizationSource` 用于日志和排查。
3. `localReminderAuthorizationUpdatedAt` 用于展示和排障，不作为业务判断主依据。

### 5. 保存流程设计

#### 5.1 主保存流程

保存流程保持不变：

```text
填写计划
  -> 点击完成
  -> 校验草稿
  -> 保存到服务端
  -> 返回保存成功的 RemoteMedicationPlan
```

#### 5.2 授权同步流程

保存成功后，按保存返回的 `plan.id` 异步同步本机提醒授权。

推荐流程：

```text
保存成功
  -> 比较保存前后“本机提醒开关”是否变化
  -> 若无变化，结束
  -> 若变为开启，调用授权新增/启用接口
  -> 若变为关闭，调用授权取消/禁用接口
  -> 授权同步失败仅打日志
```

#### 5.3 异步要求

授权同步必须异步执行，原因：

1. 避免编辑保存完成后被授权流程拖慢。
2. 避免授权接口失败阻塞计划主保存。
3. 避免保存弹窗 / Sheet 关闭延迟。

### 6. 服务端接口设计

#### 6.1 现有保存接口

沿用现有用药计划保存接口，不新增独立“授权保存”页面。

保存接口需要支持携带：

```text
local_reminder_authorization_for_current_user
```

建议语义：

| 值 | 含义 |
| --- | --- |
| `nil` | 本次不改授权 |
| `true` | 为当前用户登记该计划的本机提醒资格 |
| `false` | 取消当前用户对该计划的本机提醒资格 |

#### 6.2 计划返回字段

用药计划 DTO 返回时，补充当前用户视角授权状态：

```text
localReminderAuthorizationEnabled
localReminderAuthorizationSource
localReminderAuthorizationUpdatedAt
```

客户端编辑页只读这些字段，不再自己推导 consent。

### 7. 旧流程清理范围

本工单要求清理两类旧逻辑：

1. 确认页中老的“本机开启通知”按钮式流程。
2. 保存后额外 post-save 处理链路里的重复协同逻辑。

需要重点排查并清理的区域：

```text
MedicationPlanStepperView.swift:698-709
MedicationPlanStepperView.swift:810-819
```

清理目标：

1. 不再由编辑页同时承担“保存 + 协同弹窗 + 授权同步 + 分享流”四件事。
2. 不再保留一套旧后置处理作为兼容分支。
3. 授权同步只保留一条异步路径。

### 8. 日志设计

建议至少记录以下日志点：

1. 打开服务端编辑页时，开始查询本机提醒授权状态。
2. 查询授权状态成功 / 失败。
3. 计划保存成功，记录保存后的 plan ID。
4. 授权同步开始 / 成功 / 失败。
5. 关闭开关但无需同步时，记录跳过原因。

日志字段建议包含：

```text
accountID
memberID
planID
reminderEnabled
authorizationEnabled
source
```

### 9. 文件影响范围

#### 客户端

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanForm/MedicationPlanFormView.swift
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderOwnershipCoordinator.swift
SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift
SparkClient/SparkClient/Projects/App/Sources/App/FeatureAssemblies.swift
```

#### 服务端

```text
SparkService/medical/views.py
SparkService/medical/models.py
SparkService/medical/serializers.py
SparkService/medical/services/medication_reminder_authorization_service.py
SparkService/medical/services/medication_reminder_service.py
```

### 10. 验收标准

1. 确认页保留“邀请他人通知”。
2. 确认页“在本机开启通知”文案改为“本机提醒开关”。
3. 新增 / 普通编辑默认关闭。
4. 服务端编辑能回填已开启授权。
5. 本地编辑不展示模块。
6. 计划保存成功后，授权同步异步执行。
7. 开关无变化时不调用授权接口。
8. 授权接口失败不影响主保存。
9. 旧的 post-save 处理链路可清理完毕。
10. 客户端不再依赖本地 consent 作为判定源。
