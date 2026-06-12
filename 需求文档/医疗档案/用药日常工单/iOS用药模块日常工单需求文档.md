# iOS 用药模块日常工单需求文档

> 文档性质：需求文档 + 详细设计文档。本文仅记录 `Medications/MedicationExecutionCenter` 用药执行中心的日常工单需求、现状缺口、详细设计、交互要求和验收标准，不直接修改代码。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICATION-EXECUTION-000001` | 用药执行中心多日进度圆环与记录窗口优化 | 需求设计中 | 参考 iOS 健康“用药”效果，检查并补齐 `MedicationExecutionCenter` 未完整实现部分；重点优化顶部日期进度圆环 View，使其展示选中日前后多天用药进度，并按“当前选中日前后 4 天”加载记录数据 |

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

