# iOS 用药模块日常工单需求文档

> 文档性质：需求文档 + 详细设计文档。本文仅记录 `Medications/MedicationExecutionCenter` 用药执行中心的日常工单需求、现状缺口、详细设计、交互要求和验收标准，不直接修改代码。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICATION-EXECUTION-000001` | 用药执行中心多日进度圆环与记录窗口优化 | 需求设计中 | 参考 iOS 健康“用药”效果，检查并补齐 `MedicationExecutionCenter` 未完整实现部分；重点优化顶部日期进度圆环 View，使其展示选中日前后多天用药进度，并按“当前选中日前后 4 天”加载记录数据 |
| `MEDICATION-EXECUTION-000002` | 用药本地通知闭环详细设计 | 需求设计中 | 基于 `用药通知需求讨论文档.md` 已确认结论，首版只做客户端本地通知：计划变更同步通知、离线提醒、点击通知走冷启动目标页面公共调度、切换成员并打开用药记录 Sheet、打卡后清理当前剂次通知、通用设置医疗隐私开关 |
| `MEDICATION-EXECUTION-000003` | 用药通知查看与管理页 | 需求设计中 | 在服药计划列表右上角增加“已有通知”入口，查看本机已注册/已送达用药本地通知，支持补齐通知、取消单条、清除全部；参考 HealthClient 通知管理页，但落地需符合 SparkClient 的本地通知、LaunchIntent、L10n 与 Home 依赖架构 |

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
