# iOS 用药模块日常工单需求文档

> 文档性质：需求文档 + 详细设计文档。本文仅记录 `Medications/MedicationExecutionCenter` 用药执行中心的日常工单需求、现状缺口、详细设计、交互要求和验收标准，不直接修改代码。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICATION-EXECUTION-000001` | 用药执行中心多日进度圆环与记录窗口优化 | 需求设计中 | 参考 iOS 健康“用药”效果，检查并补齐 `MedicationExecutionCenter` 未完整实现部分；重点优化顶部日期进度圆环 View，使其展示选中日前后多天用药进度，并按“当前选中日前后 4 天”加载记录数据 |
| `MEDICATION-EXECUTION-000002` | 用药本地通知闭环详细设计 | 需求设计中 | 基于 `用药通知需求讨论文档.md` 已确认结论，首版只做客户端本地通知：计划变更同步通知、离线提醒、点击通知走冷启动目标页面公共调度、切换成员并打开用药记录 Sheet、打卡后清理当前剂次通知、通用设置医疗隐私开关 |
| `MEDICATION-EXECUTION-000003` | 用药通知查看与管理页 | 需求设计中 | 在服药计划列表右上角增加“已有通知”入口，查看本机已注册/已送达用药本地通知，支持补齐通知、取消单条、清除全部；参考 HealthClient 通知管理页，但落地需符合 SparkClient 的本地通知、LaunchIntent、L10n 与 Home 依赖架构 |
| `MEDICATION-EXECUTION-000004` | 共享成员用药通知协同详细设计 | 需求设计中 | 基于 `MEDICATION-NOTIFICATION-000002`，落地非本人成员用药提醒归属判断、成员分享优先流程、服务端开启提醒计划汇总接口、成员通知归属接口、公共健康资源变更 APNs 告知、本地他人提醒授权存储与补全通知过滤 |

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
2. 非本人成员且没有其他用户绑定为本人：保存开启提醒计划后优先走成员分享流程；用户取消分享后，再询问是否在本机为该成员创建用药提醒。
3. 非本人成员且已有其他用户绑定为本人：不走分享流程；服务端通过公共通知能力给本人用户发送一次 APNs：“某某维护了你的用药计划”；客户端提示后结束。
4. “是否为非本人成员在本机提醒”是设备级偏好，首版存在客户端本地，不新增服务端授权表。
5. 补全本机通知时，本人默认补全；非本人只有本地已同意才补全。
6. 服务端不做剂次定时调度，不生成未来每次用药提醒任务。

## 1. 目标

### 1.1 业务目标

1. 解决共享成员场景下“谁应该收到用药提醒”的归属问题。
2. 避免维护他人成员用药计划后，维护者设备默认长期响铃。
3. 对没有本人绑定的成员，引导用户优先分享成员，让本人或家人共同管理。
4. 对已有本人绑定的成员，由服务端通知本人用户有人维护了用药计划。
5. 用一个服务端聚合接口替代客户端按成员循环拉取计划和记录，减少补全通知请求数量。
6. 保持 iOS 本地通知作为准时提醒主路径。

### 1.2 技术目标

1. `MedicationReminderSyncCoordinator` 从 N+1 拉取改为一次性拉取开启提醒计划汇总。
2. 新增本地 `MedicationReminderConsentStore`，集中管理非本人成员本机提醒授权。
3. 新增服务端成员通知归属接口，客户端不再靠 `relationship` 字符串猜成员是否属于其他本人用户。
4. 新增服务端公共健康资源变更通知服务，当前接入用药计划，后续可复用到病例、体检、检查报告等资源。
5. APNs 只用于“资源被维护”的协同告知，不用于用药剂次定时提醒。
6. 接口与 DTO 遵循现有 `JSONDecoder.default` / `JSONEncoder.default` 的驼峰转下划线策略，客户端不手写 `CodingKeys`。

### 1.3 非目标

1. 不做服务端用药剂次调度。
2. 不新增服务端 `MedicationReminderConsent` 表。
3. 不做跨设备本地通知去重。
4. 不做家属代提醒权限体系。
5. 不改变现有 `MedicationPlan.reminder_enabled` 含义。
6. 不改变用药计划保存接口的主业务返回结构。
7. 不在 APNs payload 或锁屏文案中暴露药品名、剂量、病情。

## 2. 总体架构

### 2.1 模块关系

```text
MedicationsListPage / 用药计划表单
  -> 保存 MedicationPlan
  -> MedicationReminderOwnershipCoordinator
      -> 调用成员通知归属接口
      -> 根据归属决定：本人本地通知 / 分享流程 / 服务端已通知本人 / 本机代提醒二次确认

MedicationReminderSyncCoordinator
  -> 调用开启提醒计划汇总接口
  -> 结合 MedicationReminderConsentStore 过滤可在本机提醒的成员
  -> MedicationReminderScheduleCompiler 编译未来窗口
  -> MedicationReminderNotificationManager 注册本地通知

SparkService medical
  -> MedicationReminderEnabledPlansAPI：返回当前用户可访问成员的开启提醒计划与窗口记录
  -> MemberNotificationOwnershipAPI：返回成员本人绑定与 APNs 能力
  -> HealthResourceChangeNotificationService：保存用药计划后通知本人用户

SparkService accounts
  -> NotificationService.send_to_user_sync(APNS)
  -> TrustedDevice / AccountDeviceSession 判断 APNs 可用设备
```

### 2.2 关键边界

| 边界 | 说明 |
| --- | --- |
| 客户端本地通知 | 负责真正的用药到点提醒 |
| 服务端 APNs | 只负责“某某维护了你的用药计划”的一次性告知 |
| 客户端 consent | 只表示“这台设备是否愿意提醒某个非本人成员” |
| 服务端成员归属 | 只判断是否存在其他用户以 `relationship=self` 绑定该成员 |
| 分享流程 | 复用 `ShareSheet`，不在用药模块复制分享实现 |

## 3. 服务端详细设计

### 3.1 新增接口：开启提醒用药计划汇总

#### 3.1.1 URL

文件：

```text
SparkService/medical/urls.py
```

新增：

```python
path(
    "medication-reminders/enabled-plans/",
    MedicationReminderEnabledPlansAPI.as_view(),
    name="medical-medication-reminder-enabled-plans",
)
```

请求：

```text
GET /api/v1/medical/medication-reminders/enabled-plans/
```

#### 3.1.2 请求参数

| 参数 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `window_start_date` | `YYYY-MM-DD` | 否 | 服务端当前日期 | 通知滚动窗口开始日期 |
| `window_end_date` | `YYYY-MM-DD` | 否 | `window_start_date + 7 days` | 通知滚动窗口结束日期，包含日期语义 |
| `include_records` | Bool | 否 | `true` | 是否返回窗口内用药记录 |

约束：

1. `window_end_date` 不能早于 `window_start_date`。
2. 窗口最大建议限制为 14 天，最多不超过 30 天。
3. 超过最大窗口时，服务端按最大窗口截断或返回参数错误；建议首版截断并在响应中返回实际窗口。

#### 3.1.3 服务端过滤规则

必须过滤：

```text
MedicationPlan.reminder_enabled = true
MedicationPlan.status = "active"
MedicationPlan.is_deleted = false
MedicationPlan.member_id in 当前用户可访问成员
MedicationPlan.start_date <= window_end_date
MedicationPlan.end_date is null OR MedicationPlan.end_date >= window_start_date
```

不支持的筛选：

```text
不开放 keyword；
不开放药品类型；
不开放单成员筛选；
不开放任意 status；
不返回历史已结束计划；
不返回未开启提醒计划。
```

原因：

1. 该接口服务于本地通知补全，不是用药计划列表页。
2. 状态和值域固定可以减少客户端误用。
3. 服务端只做粗筛，不展开每个剂次，避免变成服务端调度。

#### 3.1.4 响应结构

建议响应：

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
        "self_owners": [
          {
            "user_id": 300,
            "display_name": "赵*",
            "has_apns": true,
            "notifications_enabled": true
          }
        ],
        "plans": [],
        "records": []
      }
    ]
  }
}
```

说明：

| 字段 | 说明 |
| --- | --- |
| `window_start_date` | 服务端实际采用的窗口开始日期 |
| `window_end_date` | 服务端实际采用的窗口结束日期 |
| `members` | 当前用户全部可访问成员的提醒数据；成员没有符合条件的计划时 `plans=[]`、`records=[]` |
| `member.relationship` | 当前登录用户与该成员的关系 |
| `member.is_self_member` | `relationship == "self"` 的服务端计算结果 |
| `member.can_share` | 当前用户是否可分享该成员 |
| `member.can_write` | 当前用户是否可维护该成员用药计划 |
| `self_owners` | 其他以 `relationship=self` 绑定该成员的用户，排除当前用户 |
| `plans` | 已开启提醒且有效的用药计划 |
| `records` | 窗口内用药记录，用于客户端排除已打卡剂次 |

#### 3.1.5 self_owners 规则

查询：

```text
UserMemberBinding
  member_id = 当前成员
  status = active
  relationship = "self"
  user_id != request.user.id
```

返回：

1. 允许返回数组 `self_owners`，避免未来出现多个本人绑定时接口不够用。
2. 只返回脱敏展示名和 APNs 能力。
3. 不返回邮箱、手机号、push token、完整设备信息。
4. 如果当前用户自己就是 `relationship=self`，`self_owners` 可以为空。

#### 3.1.6 records 查询窗口

如果 `include_records=true`：

```text
MedicationRecord.member_id in 当前成员集合
MedicationRecord.scheduled_at >= window_start_date 00:00:00
MedicationRecord.scheduled_at < window_end_date + 1 day 00:00:00
```

注意：

1. `window_end_date` 是日期语义，记录查询要转为右开区间。
2. 时区以服务端存储和现有 `MedicationRecordScheduledRange` 规则对齐。
3. 只返回当前用户可访问成员的记录。

### 3.2 新增接口：成员通知归属

#### 3.2.1 URL

文件：

```text
SparkService/medical/urls.py
```

新增：

```python
path(
    "members/<int:member_id>/notification-ownership/",
    MemberNotificationOwnershipAPI.as_view(),
    name="medical-member-notification-ownership",
)
```

请求：

```text
GET /api/v1/medical/members/{member_id}/notification-ownership/
```

#### 3.2.2 权限

必须：

```text
MemberPermissionGate.require_access(user=request.user, member_id=member_id)
```

说明：

1. 当前用户没有成员访问权限时返回 404 或权限错误，不暴露成员是否存在。
2. 当前用户有访问权限时，才返回当前用户关系、可分享能力、本人绑定情况。
3. `self_owners` 必须脱敏。

#### 3.2.3 响应结构

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "member_id": 100,
    "member_name": "妈妈",
    "current_user_relationship": "mother",
    "is_current_user_self_member": false,
    "can_share": true,
    "can_write": true,
    "has_other_self_owner": true,
    "self_owners": [
      {
        "user_id": 300,
        "display_name": "赵*",
        "has_apns": true,
        "notifications_enabled": true
      }
    ]
  }
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `is_current_user_self_member` | 当前登录用户是否把该成员绑定为本人 |
| `has_other_self_owner` | 是否存在其他用户把该成员绑定为本人 |
| `self_owners` | 其他本人用户的脱敏通知能力 |
| `can_share` | 当前用户是否可打开分享流程 |
| `can_write` | 当前用户是否可维护用药计划 |

### 3.3 服务端公共通知服务

#### 3.3.1 不新增客户端通知接口

本工单不建议新增：

```text
POST /api/v1/medical/health-resource-change-notifications/
```

原因：

1. 客户端手动调用容易重复发送 APNs。
2. 通知应与服务端保存成功的事务边界绑定。
3. 资源变更通知应由服务端根据真实保存结果触发，而不是相信客户端上报。

因此采用服务端内部公共方法。

#### 3.3.2 新增服务方法

建议新增文件：

```text
SparkService/medical/services/health_resource_change_notification_service.py
```

服务方法：

```python
class HealthResourceChangeNotificationService:
    @staticmethod
    def notify_owner_resource_changed(
        *,
        actor_user,
        member_id: int,
        resource_type: str,
        resource_id: int,
        action: str,
        request_id: str = "",
    ) -> dict:
        ...
```

参数：

| 参数 | 说明 |
| --- | --- |
| `actor_user` | 执行保存/更新的人 |
| `member_id` | 资源所属成员 |
| `resource_type` | 当前为 `medication_plan`，后续可扩展 |
| `resource_id` | 资源 ID |
| `action` | `created` / `updated` |
| `request_id` | 方便串联日志 |

返回建议：

```json
{
  "target_count": 1,
  "sent_count": 1,
  "skipped_count": 0,
  "skipped_reasons": []
}
```

该返回不一定暴露给客户端，主要用于日志和测试。

#### 3.3.3 通知目标选择

公共健康资源变更通知必须先区分三个概念：

| 概念 | 判断方式 | 语义 |
| --- | --- | --- |
| 本人 | `UserMemberBinding.relationship == "self"` | 健康资料实际归属人，最优先通知对象 |
| 所有者 | `UserMemberBinding.role == "owner"` | 成员档案所有者，拥有最高管理权 |
| 管理员 | `UserMemberBinding.role == "admin"` | 成员档案管理员，可管理绑定与重要资料 |

注意：

```text
本人不是 role；
owner/admin 不是健康资料本人；
同一个用户可能同时是本人 + owner；
通知时必须按 user_id 去重。
```

##### 3.3.3.1 默认通知原则

| 原则 | 说明 |
| --- | --- |
| 不通知操作者自己 | `target_user_id == actor_user.id` 必须排除 |
| 优先通知本人 | 健康资料变更首先通知其他 `relationship=self` 的绑定用户 |
| owner/admin 只做管理兜底 | 不应该在有本人接收者时再默认通知 owner/admin，避免一条健康资料变更打扰所有管理者 |
| viewer/editor 默认不接收 | `viewer/editor` 不是管理兜底角色，默认不发公共 APNs |
| APNs 可用才发送 | 目标用户没有 active APNs 设备时记录 skipped |
| 资源策略可配置 | 不同资源可以决定是否启用 owner/admin 兜底，避免公共方法一刀切 |

##### 3.3.3.2 用药计划 `medication_plan` 首版策略

用药计划属于高频、强个人隐私、且可能触发后续本地提醒的资源，首版通知规则建议：

| 场景 | 通知对象 | 是否通知 owner/admin | 说明 |
| --- | --- | --- | --- |
| 操作者是本人 | 不发公共 APNs | 否 | 本人自己维护自己的用药计划，不需要“被他人维护”通知 |
| 操作者不是本人，存在其他本人绑定 | 通知其他本人绑定用户 | 否 | 符合“某某维护了你的用药计划”语义 |
| 操作者不是本人，不存在其他本人绑定 | 不发公共 APNs | 否 | 客户端走分享优先流程；用户取消分享后再决定是否本机代提醒 |
| 操作者是 owner/admin，但不是本人 | 如果存在其他本人，通知本人；否则不通知 | 否 | 管理者维护资料时，目标仍是本人 |
| 操作者是 editor/viewer 且有写入能力 | 如果存在其他本人，通知本人；否则不通知 | 否 | viewer 理论上无写入；如未来有特殊写入能力，也按本人优先 |
| 多个其他本人绑定 | 通知全部其他本人绑定用户 | 否 | 按 user_id 去重 |

结论：

```text
medication_plan 首版不启用 owner/admin 兜底通知。
```

原因：

1. 没有本人绑定时，客户端已经要求优先分享成员。
2. owner/admin 可能只是照护者或资料管理员，不一定希望收到每次用药计划变更。
3. 用药计划变更 APNs 是“给本人看的协同告知”，不是管理审计消息。
4. 后续如果要做“管理员订阅成员资料变化”，应单独做通知偏好，不混入本工单。

##### 3.3.3.3 通用资源未来扩展策略

公共方法需要支持策略参数，但首版用药计划只启用本人通知。

建议内部策略：

```python
class HealthResourceNotificationPolicy:
    notify_self_owners: bool = True
    notify_managers_when_no_self_owner: bool = False
    notify_managers_when_self_owner_exists: bool = False
    manager_roles: tuple[str, ...] = ("owner", "admin")
```

不同资源建议：

| 资源类型 | 本人通知 | 无本人时 owner/admin 兜底 | 有本人时 owner/admin 同时通知 | 说明 |
| --- | --- | --- | --- | --- |
| `medication_plan` | 是 | 否 | 否 | 首版只通知本人 |
| `medical_case` | 是 | 可选 | 否 | 病例是重要资料，无本人时可通知管理者 |
| `health_exam_report` | 是 | 可选 | 否 | 体检报告无本人时可通知 owner/admin |
| `examination_report` | 是 | 可选 | 否 | 检查报告同上 |
| `medicine_box` | 否或可选 | 可选 | 否 | 药箱偏管理库存，后续可由产品决定 |

owner/admin 兜底只适用于：

```text
没有其他 relationship=self 接收者；
资源策略允许 notify_managers_when_no_self_owner；
目标用户 role in owner/admin；
目标用户不是 actor；
目标用户有 APNs 可用设备。
```

有本人接收者时，不建议同时通知 owner/admin，除非未来做“管理员订阅重要变更”开关。

##### 3.3.3.4 目标计算伪代码

```python
def resolve_targets(actor_user, member_id, resource_type):
    bindings = active_bindings(member_id).select_related("user")
    policy = policy_for(resource_type)

    targets = []

    if policy.notify_self_owners:
        self_targets = [
            b.user
            for b in bindings
            if b.relationship == "self" and b.user_id != actor_user.id
        ]
        targets.extend(self_targets)

    has_self_targets = len(targets) > 0

    if not has_self_targets and policy.notify_managers_when_no_self_owner:
        manager_targets = [
            b.user
            for b in bindings
            if b.role in ("owner", "admin") and b.user_id != actor_user.id
        ]
        targets.extend(manager_targets)

    if has_self_targets and policy.notify_managers_when_self_owner_exists:
        manager_targets = [
            b.user
            for b in bindings
            if b.role in ("owner", "admin") and b.user_id != actor_user.id
        ]
        targets.extend(manager_targets)

    return unique_by_user_id(targets)
```

##### 3.3.3.5 通知结果记录

返回建议扩展：

```json
{
  "target_count": 1,
  "sent_count": 1,
  "skipped_count": 0,
  "targets": [
    {
      "user_id": 300,
      "target_reason": "self_owner",
      "channel": "apns",
      "status": "sent"
    }
  ],
  "skipped_reasons": []
}
```

`target_reason` 可选值：

| 值 | 说明 |
| --- | --- |
| `self_owner` | 其他本人绑定用户 |
| `manager_owner` | owner 兜底 |
| `manager_admin` | admin 兜底 |
| `actor_self` | 操作者自己，跳过 |
| `no_apns_device` | 没有可用 APNs 设备 |
| `policy_disabled` | 资源策略未启用该类目标 |

##### 3.3.3.6 用药计划首版目标查询

用药计划当前实际查询可简化为：

```text
UserMemberBinding
  member_id = member_id
  status = active
  relationship = "self"
  user_id != actor_user.id
```

规则：

1. 当前操作者如果就是本人用户，不发“被他人维护”的通知。
2. 没有其他本人绑定，不发 APNs。
3. 有多个其他本人绑定时，逐个发送，按 `user_id` 去重。
4. owner/admin 首版不作为用药计划公共 APNs 接收者。
5. 目标用户没有 APNs 可用设备时，记录 skipped，不影响保存。

#### 3.3.4 APNs 内容

标题：

```text
用药计划已更新
```

内容：

```text
{actor_display_name} 维护了你的用药计划，打开应用查看详情
```

如果没有可靠脱敏名：

```text
有人维护了你的用药计划，打开应用查看详情
```

payload：

```json
{
  "type": "health_resource_changed",
  "resource_type": "medication_plan",
  "resource_id": "123",
  "member_id": "100",
  "action": "updated",
  "actor_user_id": "265"
}
```

隐私要求：

1. 不带药品名。
2. 不带剂量。
3. 不带频次。
4. 不带病情。
5. 不带成员完整身份证明信息。

#### 3.3.5 复用 accounts 通知能力

使用：

```text
SparkService/accounts/services/notification_service.py
NotificationService.send_to_user_sync(
    campaign_id=None,
    user_id=target_user_id,
    channels=[NotificationMessage.Channel.APNS],
    title=...,
    body=...,
    payload=...,
    created_by_id=actor_user.id,
    request_id=request_id,
)
```

不新增第二套 APNs Provider。

### 3.4 服务端保存流程挂载

需要挂载的服务端入口：

```text
SparkService/medical/views.py
MedicationPlanViewSet
MedicationPlanWorkflowSaveView
PrescriptionBatchWorkflowSaveView（如果会同步创建 MedicationPlan）
```

触发条件：

```text
MedicationPlan 保存成功
plan.reminder_enabled = true
plan.member_id 有效
actor_user 与其他 self owner 不同
```

建议动作：

1. 在事务提交后触发，避免保存失败却发送通知。
2. 如果已有异步任务基础，使用 Celery 异步发送。
3. 如果首版同步发送，必须捕获异常，不影响保存接口成功。

伪流程：

```python
plan = serializer.save(user=request.user)
transaction.on_commit(
    lambda: HealthResourceChangeNotificationService.notify_owner_resource_changed(
        actor_user=request.user,
        member_id=plan.member_id,
        resource_type="medication_plan",
        resource_id=plan.id,
        action="created" if created else "updated",
        request_id=request_id,
    )
)
```

### 3.5 服务端新增/复用数据模型

#### 3.5.1 不新增数据库模型

本工单服务端不新增数据库表。

复用：

```text
medical.Member
medical.UserMemberBinding
medical.MedicationPlan
medical.MedicationRecord
accounts.TrustedDevice
accounts.AccountDeviceSession
accounts.NotificationMessage
accounts.NotificationCampaign（如走 campaign）
```

#### 3.5.2 新增服务端 DTO / Serializer

建议新增轻量 serializer 或纯 dict builder：

```text
MedicationReminderEnabledPlansResponseSerializer
MedicationReminderMemberGroupSerializer
MedicationReminderMemberSummarySerializer
MedicationReminderSelfOwnerSerializer
MemberNotificationOwnershipSerializer
```

注意：

1. 计划和记录可以复用现有 `MedicationPlanSerializer` / `MedicationRecordSerializer`，避免重复模型。
2. 如果现有 serializer 太重，再新增轻量 serializer，但字段必须和客户端 `RemoteMedicationPlan` / `RemoteMedicationRecord` 对齐。
3. 不要返回完整 `User` 或完整 `TrustedDevice`。

## 4. 客户端详细设计

### 4.1 新增远程 DTO

文件：

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
```

建议新增：

```swift
struct RemoteMedicationReminderEnabledPlansResponse: Codable, Sendable, Equatable {
    var windowStartDate: Date
    var windowEndDate: Date
    var members: [RemoteMedicationReminderMemberGroup]
}

struct RemoteMedicationReminderMemberGroup: Codable, Sendable, Equatable {
    var member: RemoteMedicationReminderMemberSummary
    var selfOwners: [RemoteMedicationReminderSelfOwner]
    var plans: [RemoteMedicationPlan]
    var records: [RemoteMedicationRecord]
}

struct RemoteMedicationReminderMemberSummary: Codable, Sendable, Equatable {
    var id: Int
    var name: String
    var relationship: String
    var isSelfMember: Bool
    var bindingRole: String?
    var canShare: Bool
    var canWrite: Bool
}

struct RemoteMedicationReminderSelfOwner: Codable, Sendable, Equatable {
    var userId: Int64
    var displayName: String
    var hasApns: Bool
    var notificationsEnabled: Bool
}

struct RemoteMemberNotificationOwnership: Codable, Sendable, Equatable {
    var memberId: Int
    var memberName: String
    var currentUserRelationship: String
    var isCurrentUserSelfMember: Bool
    var canShare: Bool
    var canWrite: Bool
    var hasOtherSelfOwner: Bool
    var selfOwners: [RemoteMedicationReminderSelfOwner]
}
```

编码要求：

1. 使用项目统一 `JSONDecoder.default` 的 snake_case 解码策略。
2. 不手写 `CodingKeys`。
3. 日期字段沿用现有医疗日期解码策略；如果 `windowStartDate/windowEndDate` 是纯日期，需要确认当前 `MedicalDateCoding` 是否覆盖，否则在 API 层转为 `Date`。

### 4.2 新增客户端 API 方法

文件：

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
SparkClient/SparkClient/Projects/Core/Networking/API/Medical/SparkMedicalQueryAPI.swift
```

建议方法：

```swift
func listMedicationReminderEnabledPlans(
    windowStartDate: Date?,
    windowEndDate: Date?,
    includeRecords: Bool
) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse

func fetchMemberNotificationOwnership(
    memberID: Int
) async throws -> SparkMedicalSyncAPI.RemoteMemberNotificationOwnership
```

请求路径：

```text
GET /api/v1/medical/medication-reminders/enabled-plans/
GET /api/v1/medical/members/{member_id}/notification-ownership/
```

注意：

1. `enabled-plans` 不传成员 ID。
2. 客户端传窗口日期即可。
3. 补全通知失败时不能影响页面主流程，记录日志并保持已有通知。

### 4.3 新增本地 consent 存储

文件：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderConsentStore.swift
```

模型：

```swift
struct MedicationReminderMemberConsent: Codable, Equatable, Sendable {
    let accountID: Int64
    let memberID: Int
    var allowsLocalReminder: Bool
    var decidedAt: Date
    var source: String
}
```

Store：

```swift
final class MedicationReminderConsentStore: Sendable {
    static let shared = MedicationReminderConsentStore()

    func allowsLocalReminder(accountID: Int64, memberID: Int) -> Bool
    func setAllowsLocalReminder(_ value: Bool, accountID: Int64, memberID: Int, source: String)
    func removeConsent(accountID: Int64, memberID: Int)
    func removeAllForAccount(_ accountID: Int64)
}
```

存储方式：

```text
UserDefaults
key = medication_reminder_member_consent_v1_{accountID}_{memberID}
```

为什么不放服务端：

1. 本机通知是设备级行为。
2. 当前不做跨设备统一提醒。
3. 放服务端会制造“用户级同意但多设备重复提醒”的假一致。
4. 后续做家属代提醒或主设备策略时，再升级服务端模型。

### 4.4 改造 MedicationReminderSyncCoordinator

现状：

```swift
private func loadSnapshots(accountID: Int64, members: [Member]) async -> [MedicationReminderMemberSnapshot] {
    for member in members {
        let plans = try await medicalQueryAPI.listMedicationPlans(memberID: member.id)
        let records = try await medicalQueryAPI.listMedicationRecords(memberID: member.id, ...)
        snapshots.append(...)
    }
}
```

目标：

```text
一次请求 enabled-plans
  -> 服务端返回所有可访问成员提醒数据
  -> 客户端按 consent 过滤
  -> 编译本地通知
```

建议新增依赖：

```swift
private let consentStore: MedicationReminderConsentStore
```

过滤规则：

```swift
private func shouldScheduleLocalReminder(
    accountID: Int64,
    group: SparkMedicalSyncAPI.RemoteMedicationReminderMemberGroup
) -> Bool {
    if group.member.isSelfMember {
        return true
    }
    return consentStore.allowsLocalReminder(
        accountID: accountID,
        memberID: group.member.id
    )
}
```

转换为编译输入：

```swift
let input = MedicationReminderCompileInput(
    accountID: accountID,
    memberID: group.member.id,
    memberDisplayName: group.member.name,
    isSelfMember: group.member.isSelfMember,
    plans: group.plans,
    records: group.records,
    now: now,
    windowDays: MedicationReminderNotification.defaultWindowDays,
    calendar: calendar,
    showsDrugNameInNotification: preferencesStore.showsDrugNameInNotification
)
```

异常策略：

1. `enabled-plans` 请求失败：记录日志，不清空已有本地通知。
2. 单个成员数据异常：跳过该成员，不影响其他成员。
3. 过滤后事件为空：调用 `notificationManager.rebuild(events: [], accountID:)` 清理当前账号用药通知。
4. 系统通知未授权：保持现有 000002 行为，跳过注册。

### 4.5 新增保存后协同流程 Coordinator

建议新增文件：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderOwnershipCoordinator.swift
```

职责：

1. 保存用药计划成功后，根据成员和计划提醒状态判断是否需要后续引导。
2. 调用 `fetchMemberNotificationOwnership(memberID:)`。
3. 本人成员：触发 000002 本机通知权限/重建流程。
4. 非本人且没有其他本人绑定：请求页面打开分享流程。
5. 非本人且有其他本人绑定：提示“已通知成员本人”或“成员本人暂未开启通知”，然后结束。
6. 用户取消分享后：请求页面展示“是否在本机提醒”二次确认。
7. 用户同意本机提醒：写入 `MedicationReminderConsentStore`，请求系统通知权限并重建。

建议状态：

```swift
enum MedicationReminderPostSaveAction: Equatable {
    case none
    case requestLocalNotificationForSelf
    case openShare(memberID: Int)
    case showLocalReminderConfirm(memberID: Int, memberName: String)
    case showOwnerNotified(memberName: String, apnsAvailable: Bool)
}
```

建议方法：

```swift
@MainActor
final class MedicationReminderOwnershipCoordinator {
    func resolvePostSaveAction(
        accountID: Int64,
        memberID: Int,
        reminderEnabled: Bool
    ) async -> MedicationReminderPostSaveAction

    func acceptLocalReminderForNonSelfMember(
        accountID: Int64,
        memberID: Int,
        members: [Member]
    ) async
}
```

### 4.6 保存用药计划后的业务流程

#### 4.6.1 本人计划

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> fetchMemberNotificationOwnership
  -> isCurrentUserSelfMember == true
  -> 走 000002：权限说明/系统权限/本机通知重建
```

页面行为：

```text
如果系统通知未决定：展示用药通知说明弹窗；
用户继续后请求系统权限；
权限允许后重建本地通知；
权限拒绝则保存成功但提示提醒不可用。
```

#### 4.6.2 非本人，没有其他本人绑定

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> fetchMemberNotificationOwnership
  -> isCurrentUserSelfMember == false
  -> hasOtherSelfOwner == false
  -> 打开 ShareSheet
```

ShareSheet 结果：

```text
用户完成分享：
  -> 结束
  -> 不立即创建本机通知

用户取消分享：
  -> 弹二次确认：是否在本机提醒这个成员的用药？
  -> 选择“在本机提醒”：写入 consent，重建本机通知
  -> 选择“暂不提醒”：结束，不创建本机通知
```

注意：

1. 分享流程优先，不在第一层直接给“在本机提醒”。
2. 本机代提醒只是当前设备偏好，不改变服务端计划。
3. 二次确认后才请求系统通知权限，避免用户还没同意本机代提醒就弹系统权限。

#### 4.6.3 非本人，有其他本人绑定

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == true
  -> 服务端公共通知已在保存后触发
  -> fetchMemberNotificationOwnership
  -> hasOtherSelfOwner == true
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

#### 4.6.4 关闭提醒或暂停/取消计划

```text
保存 MedicationPlan 成功
  -> plan.reminderEnabled == false 或 status != active
  -> 不走分享/归属提示
  -> 触发本机通知重建，清理不应存在的通知
```

### 4.7 页面挂载点

主要页面：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
```

需要接入的位置：

1. 新建用药计划保存成功后。
2. 编辑用药计划保存成功后。
3. 从 AI 工作流保存用药计划后，如果回到该页面，也应触发同一协同逻辑。

建议页面状态：

```swift
@State private var pendingShareMember: Member?
@State private var pendingNonSelfReminderPrompt: NonSelfReminderPrompt?
@State private var ownerNotificationToast: OwnerNotificationToast?
```

`ShareSheet`：

```swift
.sheet(item: $pendingShareMember) { member in
    ShareSheet(
        member: member,
        shareUseCase: homeDependencies.shareMemberUseCase,
        inviteUseCase: homeDependencies.memberInviteUseCase
    )
    .onDisappear {
        if shareDidNotComplete {
            pendingNonSelfReminderPrompt = ...
        }
    }
}
```

注意：

1. 现有 `ShareSheet` 未必有“完成/取消”回调，如果没有，需要补一个轻量结果回调或由 ViewModel 暴露完成状态。
2. 不建议通过 `onDisappear` 单独判断分享结果，容易误判扫码/附近分享中的中间状态；更好是 `ShareSheet` 增加 `onCompletion` / `onCancel`。
3. 如果短期无法改 `ShareSheet`，可以先在关闭分享 sheet 后弹二次确认，但文案要允许用户选择“不需要”。

## 5. 数据模型详细说明

### 5.1 服务端不新增 DB 模型

不新增：

```text
MedicationReminderConsent
MedicationReminderSchedule
MedicationReminderNotificationTask
```

原因：

1. 当前不做服务端剂次调度。
2. 当前不做跨设备统一去重。
3. 当前不做家属代提醒授权体系。

### 5.2 客户端新增本地模型

新增：

```text
MedicationReminderMemberConsent
```

语义：

```text
当前账号在当前设备上，是否允许为某个非本人成员创建本地用药提醒。
```

生命周期：

| 场景 | 行为 |
| --- | --- |
| 用户选择“在本机提醒” | 写入 `allowsLocalReminder = true` |
| 用户选择“暂不提醒” | 可写入 `false` 或不写；建议写入 false，便于以后减少重复询问 |
| 成员解绑/失去访问权限 | 下次补全过滤并清理旧通知；可顺带删除 consent |
| 账号退出 | 保留或清理均可；建议按账号维度保留，避免同设备重新登录重复询问 |
| 账号删除/注销 | 清理该账号 consent |

### 5.3 DTO 命名建议

客户端 DTO 放在 `SparkMedicalSyncAPI` 命名空间内：

```text
RemoteMedicationReminderEnabledPlansResponse
RemoteMedicationReminderMemberGroup
RemoteMedicationReminderMemberSummary
RemoteMedicationReminderSelfOwner
RemoteMemberNotificationOwnership
```

不要放到 `MedicationReminderModels.swift`：

1. `MedicationReminderModels.swift` 是本地通知编译/展示模型。
2. 远程 DTO 应集中在医疗 API namespace。
3. 避免远程模型和本地编译模型混在一起。

## 6. 本地通知补全算法

### 6.1 输入

```text
accountID
windowStartDate = today
windowEndDate = today + defaultWindowDays
includeRecords = true
```

### 6.2 处理步骤

```text
rebuild(accountID)
  -> 检查系统通知权限
  -> listMedicationReminderEnabledPlans(window)
  -> for group in response.members:
        if group.member.isSelfMember:
            include
        else if consentStore.allowsLocalReminder(accountID, group.member.id):
            include
        else:
            skip
  -> 对 include 的 group 调用 MedicationReminderScheduleCompiler
  -> 聚合所有 events
  -> 按 scheduledAt 排序
  -> 截断到 MedicationReminderNotification.maxPendingCount
  -> notificationManager.rebuild(events, accountID)
```

### 6.3 特别规则

| 场景 | 规则 |
| --- | --- |
| 本人成员 | 默认参与补全 |
| 非本人，已 consent | 参与补全 |
| 非本人，未 consent | 不参与补全 |
| 非本人，有其他本人绑定 | 未 consent 时不参与补全；保存流程只做服务端 APNs 告知 |
| 接口失败 | 不清空已有通知 |
| 接口成功但无事件 | 清空当前账号用药通知 |
| 成员失去访问权限 | 服务端不返回该成员；本机 rebuild 后清理旧通知 |

## 7. APNs 点击行为

`health_resource_changed` APNs 与 `medication_reminder` 本地通知不同。

### 7.1 Payload type

```text
medication_reminder
  -> 用药到点提醒
  -> 点击进入用药执行中心并打开记录 Sheet

health_resource_changed
  -> 健康资源被他人维护
  -> 当前只用于“用药计划已更新”
  -> 点击进入对应资源详情或用药计划列表/详情
```

### 7.2 首版点击目标

建议首版：

```text
点击“用药计划已更新”APNs
  -> 冷启动目标页面公共调度
  -> Home
  -> 切换到 member_id 对应成员
  -> 进入用药模块
  -> 如果能定位 medication_plan resource_id，则打开计划详情/编辑页只读详情
  -> 如果无法定位，进入用药计划列表并 Toast：用药计划可能已变更
```

如果当前没有稳定用药计划详情路由，首版可以先进入用药模块列表页。

## 8. 文件影响清单

### 8.1 客户端

| 文件 | 改动 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 新增远程 DTO |
| `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/SparkMedicalQueryAPI.swift` | 新增两个查询方法 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderSyncCoordinator.swift` | 用 `enabled-plans` 聚合接口替代按成员循环；按 consent 过滤 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationNotification/MedicationReminderModels.swift` | 如需要，补充本地 consent 相关非远程模型；远程 DTO 不放这里 |
| 新增 `MedicationReminderConsentStore.swift` | 本地存储非本人成员本机提醒授权 |
| 新增 `MedicationReminderOwnershipCoordinator.swift` | 保存后协同流程编排 |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift` | 保存成功后接入 ownership 流程；挂载 ShareSheet 和二次确认 |
| `SparkClient/SparkClient/Projects/Features/Share/Presentation/ShareSheet.swift` | 建议增加完成/取消回调，避免 `onDisappear` 误判 |
| `SparkClient/SparkClient/Projects/Core/Notification/Application/HandleRemoteNotificationUseCase.swift` | 增加 `health_resource_changed` type 解析与路由 |
| `SparkClient/SparkClient/Projects/App/Sources/App/Architecture/LaunchIntent.swift` | 如需要，新增健康资源变更目标 |
| `SparkClient/SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | 新增中文文案；所有新增 UI 文案必须走 `L10n.text` |
| `SparkClient/SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | 新增英文文案；key 与中文保持一致 |

### 8.2 服务端

| 文件 | 改动 |
| --- | --- |
| `SparkService/medical/urls.py` | 注册 `enabled-plans` 和 `notification-ownership` |
| `SparkService/medical/views.py` | 新增 `MedicationReminderEnabledPlansAPI`、`MemberNotificationOwnershipAPI`；用药计划保存后触发公共通知服务 |
| `SparkService/medical/serializers.py` | 新增轻量响应 serializer 或 dict builder |
| `SparkService/medical/services/medication_reminder_service.py` | 聚合查询开启提醒计划、窗口记录、成员本人绑定 |
| `SparkService/medical/services/health_resource_change_notification_service.py` | 公共健康资源变更 APNs 通知服务 |
| `SparkService/accounts/services/notification_service.py` | 复用现有 `send_to_user_sync`，原则上不改或只补公共封装 |
| `SparkService/medical/tests*.py` | 新增接口、权限、过滤和通知触发测试 |

## 8.3 关键代码注释要求

本工单涉及“本人/所有者/管理员/非本人 consent/服务端 APNs 告知/本地通知补全”多条容易混淆的规则。关键代码必须补充短注释，说明“为什么这样做”，不要只解释“代码做了什么”。

### 8.3.1 客户端必须注释的位置

| 文件/位置 | 注释要求 |
| --- | --- |
| `MedicationReminderConsentStore.swift` | 在类型注释中说明：该 consent 是“当前账号在当前设备上是否为非本人成员创建本地提醒”，不是服务端家庭权限，也不会跨设备同步 |
| `MedicationReminderSyncCoordinator.loadSnapshots/rebuild` | 注释说明：补全通知使用服务端聚合接口，避免按成员 N+1；非本人成员必须通过本地 consent 才参与本机通知 |
| `shouldScheduleLocalReminder` 或同等过滤函数 | 注释说明：本人默认补全；非本人只看本地 consent；是否存在其他本人绑定不直接决定补全，保存流程负责 APNs 告知 |
| `MedicationReminderOwnershipCoordinator.resolvePostSaveAction` | 注释说明：保存成功后的引导流程按“本人 / 非本人无本人绑定 / 非本人有本人绑定”三段分流 |
| `ShareSheet` 完成/取消回调 | 注释说明：不能只依赖 `onDisappear` 判断用户取消，因为扫码、附近分享、远程邀请都可能导致中间关闭或状态变化 |
| `HandleRemoteNotificationUseCase` 的 `health_resource_changed` 分支 | 注释说明：这是资源变更告知，不是到点用药提醒，不应打开用药记录 Sheet |
| `LaunchIntent` 新增目标 | 注释说明：资源变更通知优先定位资源详情；定位失败回退用药列表 |

示例：

```swift
/// 设备级同意：仅表示当前账号愿意在这台设备上为非本人成员创建本地用药提醒。
/// 这不是家庭成员权限，也不会同步到服务端；跨设备提醒策略后续单独设计。
struct MedicationReminderMemberConsent: Codable, Equatable, Sendable { ... }
```

### 8.3.2 服务端必须注释的位置

| 文件/位置 | 注释要求 |
| --- | --- |
| `MedicationReminderEnabledPlansAPI` | 注释说明：该接口只服务本地通知补全，固定返回开启提醒且有效的计划，不是用药计划通用列表接口 |
| `medication_reminder_service.py` 的有效期过滤 | 注释说明：服务端只做窗口粗筛，不展开剂次，剂次编译仍由客户端完成 |
| `MemberNotificationOwnershipAPI` | 注释说明：`relationship=self` 表示健康资料本人；`role=owner/admin` 表示管理权限，二者不能混用 |
| `HealthResourceChangeNotificationService.resolve_targets` | 注释说明：用药计划首版只通知其他本人绑定用户，不启用 owner/admin 兜底 |
| `transaction.on_commit` 触发通知处 | 注释说明：必须等保存事务提交后再发送 APNs，避免保存失败但通知已发 |
| APNs payload 构造处 | 注释说明：payload 不携带药名、剂量、病情，避免锁屏与通知链路泄露隐私 |

示例：

```python
# 用药计划变更通知只面向“其他本人绑定用户”。
# owner/admin 是管理角色，不等同于健康资料本人；首版不作为用药计划 APNs 兜底接收者。
targets = resolve_self_owner_targets(...)
```

## 8.4 客户端本地化要求

所有新增用户可见文案必须写入：

```text
SparkClient/SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
SparkClient/SparkClient/Projects/App/Resources/en.lproj/Localizable.strings
```

Swift 代码中必须使用：

```swift
L10n.text("key", fallback: "中文兜底")
```

不允许：

```text
SwiftUI Text / Button / alert 中硬编码中文；
Toast 中硬编码中文；
APNs 点击路由失败提示中硬编码中文；
```

### 8.4.1 建议本地化 key

| key | 中文文案 |
| --- | --- |
| `medication.reminder.share_first.hint` | 建议先把成员分享给本人或家人，共同接收和管理用药信息。 |
| `medication.reminder.non_self.confirm.title` | 是否在本机提醒这个成员的用药？ |
| `medication.reminder.non_self.confirm.message` | 该成员还没有绑定为本人的用户。你可以临时在本机接收提醒，后续也可以重新分享给本人或家人共同管理。 |
| `medication.reminder.non_self.confirm.accept` | 在本机提醒 |
| `medication.reminder.non_self.confirm.decline` | 暂不提醒 |
| `medication.reminder.owner_notified.title` | 已通知成员本人 |
| `medication.reminder.owner_notified.message` | 该成员已绑定为其他用户本人，我们会通知对方查看用药计划。 |
| `medication.reminder.owner_apns_unavailable.title` | 成员本人暂未开启通知 |
| `medication.reminder.owner_apns_unavailable.message` | 该成员已绑定为其他用户本人，但对方可能无法收到系统通知。用药计划已保存。 |
| `medication.reminder.sync_degraded.toast` | 用药计划已保存，提醒状态稍后同步。 |
| `medication.reminder.local_consent.saved.toast` | 已在本机开启该成员的用药提醒。 |
| `medication.reminder.local_consent.skipped.toast` | 用药计划已保存，未创建本机提醒。 |
| `notification.health_resource_changed.medication_plan.title` | 用药计划已更新 |
| `notification.health_resource_changed.medication_plan.body` | 有人维护了你的用药计划，打开应用查看详情。 |
| `notification.health_resource_changed.route_missing.toast` | 用药计划可能已变更。 |

英文文案需要语义对齐，不要求逐字直译。

## 9. UI / 交互文案

### 9.1 没有其他本人绑定，优先分享

触发：

```text
非本人成员 + 开启提醒 + hasOtherSelfOwner = false
```

行为：

```text
打开 ShareSheet
```

如果需要先解释，可用轻提示：

```text
建议先把成员分享给本人或家人，共同接收和管理用药信息。
```

### 9.2 用户取消分享后的二次确认

标题：

```text
是否在本机提醒这个成员的用药？
```

内容：

```text
该成员还没有绑定为本人的用户。你可以临时在本机接收提醒，后续也可以重新分享给本人或家人共同管理。
```

按钮：

```text
在本机提醒
暂不提醒
```

### 9.3 已通知成员本人

标题：

```text
已通知成员本人
```

内容：

```text
该成员已绑定为其他用户本人，我们会通知对方查看用药计划。
```

按钮：

```text
好的
```

### 9.4 成员本人暂未开启通知

标题：

```text
成员本人暂未开启通知
```

内容：

```text
该成员已绑定为其他用户本人，但对方可能无法收到系统通知。用药计划已保存。
```

按钮：

```text
好的
```

## 10. 异常处理

| 场景 | 处理 |
| --- | --- |
| `notification-ownership` 请求失败 | 计划保存不回滚；提示“用药计划已保存，提醒状态稍后同步”；不打开分享，不创建非本人本机通知 |
| `enabled-plans` 请求失败 | 不清空已有通知；记录日志 |
| 服务端 APNs 发送失败 | 不影响用药计划保存；服务端记录 `NotificationMessage` failed/skipped |
| 用户拒绝系统通知权限 | 保存成功；本地不创建通知；提示系统通知未开启 |
| 用户取消分享 | 再询问是否本机提醒 |
| 用户取消二次确认 | 不写 true consent，不创建通知 |
| 成员解绑 | 下次补全不返回该成员，清理旧本地通知 |
| 账号切换 | `MedicationReminderSyncCoordinator.activate/deactivate` 按账号隔离；consent key 带 accountID |

## 11. 日志设计

### 11.1 客户端日志

客户端日志目标：

1. 能解释为什么某个成员参与或没有参与本机补全通知。
2. 能解释保存计划后为什么打开分享、为什么提示已通知本人、为什么没有创建本机通知。
3. 能定位服务端接口失败、权限未开启、APNs 路由失败等降级路径。
4. 不记录药名、剂量、病情、完整 payload。

建议事件：

| 事件 | 时机 | 字段 |
| --- | --- | --- |
| `medication_reminder.ownership.start` | 保存开启提醒计划后开始查归属 | `accountID/memberID/planID/reminderEnabled` |
| `medication_reminder.ownership.success` | 归属查询成功 | `memberID/isSelfMember/hasOtherSelfOwner/selfOwnerCount/canShare/canWrite` |
| `medication_reminder.ownership.failed` | 归属查询失败 | `memberID/error/requestID` |
| `medication_reminder.post_save.self_member` | 本人成员走本机通知流程 | `memberID/planID` |
| `medication_reminder.post_save.open_share` | 非本人且无本人绑定，进入分享 | `memberID/planID` |
| `medication_reminder.post_save.owner_notified` | 非本人且有本人绑定，服务端应通知本人 | `memberID/planID/selfOwnerCount/apnsAvailable` |
| `medication_reminder.share.completed` | 分享完成 | `memberID/channel` |
| `medication_reminder.share.cancelled` | 用户取消分享 | `memberID` |
| `medication_reminder.non_self_consent.accepted` | 用户同意本机代提醒 | `memberID/source` |
| `medication_reminder.non_self_consent.declined` | 用户拒绝本机代提醒 | `memberID/source` |
| `medication_reminder.enabled_plans.start` | 补全通知开始请求聚合接口 | `accountID/windowStart/windowEnd/includeRecords` |
| `medication_reminder.enabled_plans.success` | 聚合接口成功 | `memberCount/planCount/recordCount/windowStart/windowEnd` |
| `medication_reminder.enabled_plans.failed` | 聚合接口失败 | `error/requestID` |
| `medication_reminder.rebuild.filtered` | 补全通知过滤完成 | `includedMemberCount/skippedMemberCount/selfMemberCount/nonSelfConsentCount/eventCount` |
| `medication_reminder.health_resource_route.start` | 点击资源变更 APNs 开始路由 | `resourceType/resourceID/memberID/action` |
| `medication_reminder.health_resource_route.fallback` | 资源无法定位，回退列表页 | `resourceType/resourceID/memberID/reason` |

原有简要日志：

```text
用药提醒归属查询开始/成功/失败 memberID
非本人无 self owner：进入分享流程 memberID
用户取消分享：进入本机提醒二次确认 memberID
用户同意非本人本机提醒 memberID
用户拒绝非本人本机提醒 memberID
enabled-plans 拉取成功 members/plans/records 数量
补全过滤结果 includedMembers/skippedMembers/events
```

不要记录：

```text
药品名称
剂量
病情
完整 APNs payload
```

推荐日志级别：

| 级别 | 使用场景 |
| --- | --- |
| `debug` | 分支选择、过滤原因、点击路由中间态 |
| `info` | 归属查询成功、补全成功、用户同意/拒绝本机代提醒 |
| `warning` | 接口失败但业务降级、APNs 路由无法定位、系统通知未授权 |
| `error` | 理论上不应出现的数据损坏、DTO 解码失败且无法降级 |

### 11.2 服务端日志

服务端日志目标：

1. 能审计接口返回了多少成员、计划、记录。
2. 能解释某次资源变更通知为什么发送、跳过或失败。
3. 能验证 owner/admin 没有被用药计划首版误通知。
4. 方便通过 `request_id` 串联保存请求、通知目标计算和 APNs 发送记录。

建议事件：

| 事件 | 时机 | 字段 |
| --- | --- | --- |
| `medication_reminder.enabled_plans.request` | 进入聚合接口 | `request_id/user_id/window_start/window_end/include_records` |
| `medication_reminder.enabled_plans.response` | 聚合接口返回前 | `request_id/user_id/member_count/plan_count/record_count` |
| `medication_reminder.enabled_plans.invalid_window` | 窗口参数非法或被截断 | `request_id/user_id/window_start/window_end/reason` |
| `member_notification_ownership.request` | 进入成员归属接口 | `request_id/user_id/member_id` |
| `member_notification_ownership.response` | 成员归属接口返回前 | `request_id/user_id/member_id/is_self_member/has_other_self_owner/self_owner_count/can_share/can_write` |
| `health_resource_change.notify.resolve_targets` | 公共通知计算目标 | `request_id/actor_user_id/member_id/resource_type/resource_id/action/self_owner_count/manager_count/target_count` |
| `health_resource_change.notify.skip` | 没有目标或策略禁用 | `request_id/member_id/resource_type/resource_id/reason` |
| `health_resource_change.notify.dispatch` | 即将调用 APNs 通知 | `request_id/target_user_id/target_reason/resource_type/resource_id` |
| `health_resource_change.notify.done` | 单个目标通知完成 | `request_id/target_user_id/status/success_count/failure_count/error_message` |

原有简要日志：

```text
enabled-plans request user_id window_start window_end member_count plan_count record_count
notification-ownership request user_id member_id has_other_self_owner self_owner_count
health resource changed notify actor_user_id member_id resource_type resource_id target_count sent skipped
```

服务端隐私限制：

```text
不记录药品名称；
不记录剂量；
不记录用药说明；
不记录完整 APNs token；
不记录完整 APNs payload；
APNs token 如必须排查，只记录 token_last4。
```

服务端推荐日志级别：

| 级别 | 使用场景 |
| --- | --- |
| `info` | 接口成功摘要、通知目标解析、发送结果 |
| `warning` | 参数窗口被截断、目标无 APNs、通知 skipped |
| `error` | 通知服务异常、APNs Provider 异常、接口无法降级 |

## 12. 测试方案

### 12.1 服务端测试

| 场景 | 预期 |
| --- | --- |
| 当前用户有 3 个可访问成员 | `enabled-plans` 返回 3 个成员分组；没有开启提醒计划的成员 `plans=[]`、`records=[]` |
| 成员计划 `reminder_enabled=false` | 不返回 |
| 成员计划 `status=paused` | 不返回 |
| 计划已过期 | 不返回 |
| 计划未来才开始且不在窗口内 | 不返回 |
| 计划覆盖窗口 | 返回 |
| 无权限访问 member_id | `notification-ownership` 不返回成员信息 |
| 成员有其他 self owner | `has_other_self_owner=true` |
| 成员没有其他 self owner | `has_other_self_owner=false` |
| 保存用药计划且其他 self owner 有 APNs | 创建 APNs NotificationMessage |
| 保存用药计划但 actor 就是 self owner | 不发“他人维护”通知 |
| 保存用药计划且只有 owner/admin、没有其他 self owner | 不发公共 APNs；客户端分享流程处理 |
| 保存用药计划且同时存在 self owner 和 owner/admin | 只通知其他 self owner，不通知 owner/admin |
| 保存用药计划且 actor 是 owner/admin、另有 self owner | 通知 self owner |
| 保存用药计划且 actor 是 owner/admin、没有 self owner | 不发公共 APNs |
| APNs 不可用 | 保存成功，通知记录 skipped |

### 12.2 客户端测试

| 场景 | 预期 |
| --- | --- |
| 本人开启提醒保存计划 | 正常弹通知权限/重建本机通知 |
| 非本人无 self owner 保存开启提醒计划 | 打开分享流程 |
| 非本人无 self owner，用户取消分享 | 弹“是否本机提醒” |
| 用户选择在本机提醒 | 写入 consent，补全通知包含该成员 |
| 用户选择暂不提醒 | 不写 true consent，不创建通知 |
| 非本人有 self owner | 不打开分享，不弹本机提醒，提示已通知本人或对方未开启通知 |
| 补全通知 | 只请求一次 `enabled-plans` |
| 非本人未 consent | 补全时跳过 |
| 非本人已 consent | 补全时包含 |
| 接口失败 | 不清空已有通知 |
| 账号切换 | 不读取其他账号 consent |
| 中文系统语言 | 所有弹窗、Toast、按钮使用中文本地化文案 |
| 英文系统语言 | 所有弹窗、Toast、按钮使用英文本地化文案 |
| 点击资源变更 APNs 且资源不存在 | 使用本地化 Toast 提示并回退列表页 |

### 12.3 回归测试

1. 000002 的本地通知点击进入用药执行中心仍正常。
2. 000003 的已有通知管理页仍能补齐、取消、清除。
3. 本人用药计划保存不被分享流程打断。
4. 非本人关闭提醒保存不弹分享或本机提醒确认。
5. 用药记录打卡后当前剂次通知仍被清理。
6. 新增 UI 文案不出现 Swift 硬编码中文。
7. 客户端关键流程日志可在 Debug 日志中串联保存后归属判断、分享流程、本机 consent、补全通知过滤。
8. 服务端日志可通过 request_id 串联保存用药计划、目标计算、APNs 发送或跳过原因。

## 13. 验收标准

1. 服务端提供 `GET /api/v1/medical/medication-reminders/enabled-plans/`。
2. `enabled-plans` 只返回当前用户可访问成员的数据。
3. `enabled-plans` 只返回开启提醒、状态 active、有效期覆盖窗口的计划。
4. `enabled-plans` 可返回窗口内用药记录。
5. 客户端补全通知不再按成员循环请求 `listMedicationPlans` 和 `listMedicationRecords`。
6. 服务端提供 `GET /api/v1/medical/members/{member_id}/notification-ownership/`。
7. `notification-ownership` 能返回当前用户是否本人、是否存在其他本人用户、本人用户 APNs 能力。
8. 非本人成员且没有其他本人绑定时，保存开启提醒计划后优先打开分享流程。
9. 用户取消分享后，才询问是否在本机提醒该成员用药。
10. 用户同意本机提醒后，本地写入 consent 并补全通知。
11. 用户暂不提醒后，不请求系统通知权限，不创建本机通知。
12. 非本人成员且已有其他本人绑定时，客户端不走分享流程，不询问本机提醒。
13. 非本人成员且已有其他本人绑定时，服务端发送一次公共 APNs 告知本人用户。
14. APNs 文案和 payload 不包含药品名、剂量、病情。
15. 当前操作者就是本人用户时，不给自己发送资源变更 APNs。
16. 用药计划首版不把 owner/admin 作为公共 APNs 接收者；owner/admin 只有未来资源策略明确开启兜底时才通知。
17. 同一用户同时是本人和 owner/admin 时，只发送一条通知。
18. APNs 发送失败不影响用药计划保存。
19. 本地 consent 按 `accountID + memberID` 隔离。
20. 成员解绑或失去访问权限后，补全通知不再包含该成员。
21. 客户端新增 UI 文案全部写入 `zh-Hans.lproj/Localizable.strings` 与 `en.lproj/Localizable.strings`，Swift 代码通过 `L10n.text` 读取。
22. 客户端关键流程具备日志：归属查询、分享打开/取消、本机 consent、`enabled-plans` 成功/失败、补全过滤、资源变更 APNs 路由。
23. 服务端关键流程具备日志：`enabled-plans` 请求/响应、`notification-ownership` 请求/响应、公共通知目标计算、发送、跳过、失败。
24. 关键代码具备必要注释：本人/owner/admin 区分、非本人 consent 设备级语义、用药计划不启用 owner/admin 兜底、事务提交后发送 APNs、隐私字段不进入 payload。
25. 日志不得记录药品名、剂量、病情、完整 APNs token、完整 APNs payload。
26. 000002 本地通知闭环不回归。
27. 000003 通知管理页补齐通知使用新聚合接口后仍可正常刷新列表。

## 14. 实施顺序建议

1. 服务端先实现 `notification-ownership`，用于客户端保存后流程判断。
2. 服务端实现 `enabled-plans`，先不接客户端，使用测试确认过滤规则。
3. 服务端实现 `HealthResourceChangeNotificationService`，并挂到用药计划保存入口。
4. 客户端新增远程 DTO 和 API 方法。
5. 客户端新增 `MedicationReminderConsentStore`。
6. 改造 `MedicationReminderSyncCoordinator` 使用聚合接口和 consent 过滤。
7. 新增 `MedicationReminderOwnershipCoordinator`，接入用药计划保存后流程。
8. 接入 `ShareSheet` 结果回调和二次确认。
9. 接入 `health_resource_changed` APNs 点击路由。
10. 补齐客户端本地化 key，移除新增硬编码中文。
11. 补齐客户端/服务端关键流程日志。
12. 补齐关键代码注释。
13. 回归 000002 / 000003。
