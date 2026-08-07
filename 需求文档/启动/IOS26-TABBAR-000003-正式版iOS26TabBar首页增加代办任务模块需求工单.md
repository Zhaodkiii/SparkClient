# IOS26-TABBAR-000003：正式版 iOS26TabBar 首页增加代办任务模块需求工单

> 创建日期：2026-08-07  
> 关联模块：iOS26TabBarView、IOS26HomeDashboardView、HomeView、TaskManager、TaskCenterViewController、TaskCardCell  
> 关联代码：`SparkClient/Projects/Features/Home/Presentation/HomeView.swift`、`SparkClient/Projects/Features/Task/Application/TaskManager.swift`、`SparkClient/Projects/Features/Task/Presentation/TaskCenterViewController.swift`、`SparkClient/Projects/Features/Task/Presentation/TaskCardCell.swift`  
> 状态：新需求/待实现  
> 优先级：P1，首页工作台增强

## 1. 一句话目标

在正式版 `IOS26TabBarView` 的首页中增加一个“代办任务模块”，把现有 `TaskManager` 中的待办、医疗、运动、饮食任务前置到首页，让用户打开 App 后先看到今天要做什么，再进入任务中心进行管理。

## 2. 背景与问题

当前任务能力已经存在，但首页没有形成统一入口：

1. `TaskManager` 已经维护了 `HealthTask` 任务集合、增量同步、创建、完成、取消和通知对齐。
2. `TaskCenterViewController` 已经提供了任务中心列表、筛选、创建与编辑能力。
3. `HomeView` 也已经持有 `taskManager` 依赖，但首页主体还主要围绕成员、医疗、报告和模块维护展开。

结果是：

1. 用户要先进入别的模块，才知道自己有什么任务。
2. 首页缺少“今天要做什么”的直观感受。
3. 任务中心虽然功能完整，但入口层级偏深。
4. 代办任务对家庭健康管理的“日常节奏感”没有被建立起来。

本工单要解决的是：**把任务中心能力的一部分摘要前置到首页，但不把首页变成另一个任务列表页。**

## 3. 目标

### 3.1 用户目标

1. 用户打开首页后，能立刻看到待办任务总数、任务类型和优先级概览。
2. 用户能在首页直接判断今天是否有需要处理的医疗、运动或饮食任务。
3. 用户能从首页一键进入任务中心继续管理。

### 3.2 产品目标

1. 提高任务的曝光率和完成率。
2. 降低“我有任务但没看到”的漏执行风险。
3. 让首页工作台从“数据展示”升级为“行动驱动”。
4. 与任务中心形成清晰分工：首页看概览，任务中心做管理。

### 3.3 成功指标

| 指标 | 目标 |
| --- | --- |
| 首页任务模块曝光率 | 首页首屏可见 |
| 任务中心进入率 | 点击模块后进入任务中心 |
| 待办任务完成率 | 任务中心待完成任务的完成率提升 |
| 首页任务感知 | 用户能在 3 秒内识别当前待办数量 |
| 低干扰 | 首页任务模块不破坏主行动入口层级 |

## 4. 非目标

1. 本期不重做任务中心。
2. 本期不新增任务后端接口。
3. 本期不改造 `TaskManager` 的同步协议。
4. 本期不把任务编辑、完成、取消按钮全部搬到首页。
5. 本期不把首页做成长列表，不替代任务中心。
6. 本期不改变任务的来源模型或状态机。

## 5. 模块定义

### 5.1 首页代办任务模块是什么

首页代办任务模块是一个面向家庭健康工作台的摘要型模块，默认展示：

1. 待办任务总数。
2. 当前最紧急的 1-3 条任务预览。
3. 任务类型分布或标签。
4. 进入任务中心的主按钮。

它不是任务管理页，也不是任务编辑器。

### 5.2 展示内容建议

优先展示以下信息：

1. 待完成数量。
2. 逾期数量。
3. 今天到期数量。
4. 最高优先级任务。
5. 最近更新时间。

任务内容来自现有 `HealthTask`：

```swift
struct HealthTask: Identifiable, Codable, Equatable, Sendable {
    var title: String
    var description: String
    var type: TaskType
    var status: TaskStatus
    var startTime: Date?
    var dueTime: Date?
    var priority: Priority
    var createdAt: Date
    var updatedAt: Date
}
```

### 5.3 任务来源范围

首页模块展示的是全部可见任务的摘要，不区分业务线写死展示：

1. 医疗任务。
2. 运动任务。
3. 饮食任务。

如果后续 `TaskService` 或业务端给任务补充更多类型，也应通过通用摘要策略自动适配。

## 6. UI 设计方向

### 6.1 关键词

```text
简约
克制
今天要做什么
任务驱动
健康日程感
与首页主行动并列但不抢戏
```

### 6.2 视觉原则

1. 代办任务模块要看起来像“工作台”，不是提醒横幅。
2. 主标题、数字、任务条目三层关系必须清晰。
3. 预览任务数量控制在 3 条以内，避免首页变长。
4. 高优先级信息要用更强的视觉重量，但不要用大面积红色。
5. 任务模块可以有轻微的完成感，但不要做成游戏化进度条。
6. 卡片边界要清楚，避免和首页其他模块糊成一体。
7. 任务模块应和首页的“制定体检计划”“报告解读”形成并列行动感。

### 6.3 色彩与光影

| 状态 | 建议 |
| --- | --- |
| 待完成 | 使用偏暖但不过饱和的提醒色，例如系统橙 |
| 逾期 | 只在数量徽标或状态标签上使用红色 |
| 已完成 | 低饱和绿色或中性完成态 |
| 已取消 | 灰色弱化 |
| 正常概览 | 系统材质 + 轻描边，避免高噪音配色 |

1. 任务模块背景优先使用系统材质或轻量卡面，不要叠加重阴影。
2. 进度或数量强调应集中在数字上，不要整块变色。
3. 任务状态颜色只用于标签和关键数字，不用于整卡铺色。
4. 深色模式下，仍需保留边界与层级，而不是变成一团黑。

### 6.4 空间与留白

1. 模块内部要有足够的上方留白，让数字区和任务列表区分层。
2. 任务条目之间留白略小于首页主模块之间留白，以便形成“列表感”。
3. 模块底部留白要比按钮区域略大，避免 CTA 挤边。
4. 列表最多三条，第四条开始改为“查看更多”。
5. 空状态时宁可留白，也不要硬塞假数据。

### 6.5 交互与状态反馈

1. 模块按下立即出现轻微压暗或缩放。
2. 点击“查看全部任务”进入任务中心。
3. 点击具体任务预览项也应进入任务中心，帮助用户继续处理。
4. 若任务为空，不显示空白列表，直接给出引导行动。
5. 任务同步中只显示局部 loading，不阻塞首页其他模块。

### 6.6 异常状态处理

1. 无任务：显示“今天没有待办”并引导到任务中心创建或同步。
2. 同步失败：展示轻量失败状态，不影响其他首页内容。
3. 任务数量很大：只展示前 3 条，其余收进“查看全部任务”。
4. 任务字段缺失：标题、状态、时间信息都必须有回退文案。
5. 低网速或离线：继续展示上次缓存任务摘要，并标记为“上次同步于…”

### 6.7 微交互与动效

1. 首页初次出现时，代办任务模块可与主模块保持同一套轻微入场节奏。
2. 数字从 0 到当前值可以做一次很短的计数过渡，但不要炫技。
3. 列表更新时优先做内容替换，不做大幅布局跳动。
4. 进入任务中心时使用系统导航动画，不额外叠加复杂转场。
5. Reduce Motion 开启时保留淡入淡出和颜色变化，去掉位移动效。

## 7. 首页 plain text UI 线框

### 7.1 iPhone 首屏

```text
┌────────────────────────────────────┐
│  早上好，华                         │
│  家庭健康工作台                     │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  当前成员                     │  │
│  │  [爸爸] [妈妈] [我]       [+] │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  代办任务                     │  │
│  │  待完成  3   逾期 1   今日 2   │  │
│  │  ① 服药提醒 · 20:00          > │  │
│  │  ② 体检资料补全 · 医疗        > │  │
│  │  ③ 报告待解读 · 今日          > │  │
│  │                      查看全部  │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  制定体检计划                 │  │
│  │  根据年龄、既往记录和家族风险  │  │
│  │  生成下一次体检建议            │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  报告解读                     │  │
│  │  进入 AI 会话，整理检查结论     │  │
│  └──────────────────────────────┘  │
├────────────────────────────────────┤
│      首页        DeepTutor        搜索 │
└────────────────────────────────────┘
```

### 7.2 模块节奏

```text
一级：家庭健康工作台
二级：当前成员
二级：代办任务摘要
一级行动：制定体检计划、报告解读
三级行动：查看全部任务
```

### 7.3 空状态

```text
┌────────────────────────────────────┐
│  代办任务                           │
│  今天没有待办                       │
│  你可以进入任务中心创建一个任务，或等 │
│  待系统同步最新任务                 │
│                         查看全部任务 │
└────────────────────────────────────┘
```

### 7.4 失败状态

```text
┌────────────────────────────────────┐
│  代办任务                           │
│  任务暂时无法加载                   │
│  先继续使用首页其他功能，稍后会自动重试 │
│                      重新加载任务    │
└────────────────────────────────────┘
```

## 8. UI 模型

### 8.1 首页代办任务摘要模型

```swift
struct IOS26HomeTaskSummary: Equatable, Sendable {
    let pendingCount: Int
    let overdueCount: Int
    let todayCount: Int
    let lastSyncTime: Date?
    let items: [IOS26HomeTaskSummaryItem]
    let isLoading: Bool
    let errorMessage: String?
}

struct IOS26HomeTaskSummaryItem: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let subtitle: String
    let timeText: String
    let badgeText: String?
    let priority: HealthTask.Priority
    let status: HealthTask.TaskStatus
    let taskType: HealthTask.TaskType
}
```

### 8.2 任务聚合规则

建议按以下规则生成首页摘要：

1. 只展示 `pending` 任务。
2. 按 `priority` 和 `dueTime` 排序。
3. `dueTime` 优先，其次 `startTime`，最后 `updatedAt`。
4. 最多展示 3 条。
5. 若有逾期任务，优先出现在第一位。
6. `todayCount` 统计今天到期或今天开始的 pending 任务。
7. `overdueCount` 统计当前时间早于 `dueTime` 且仍未完成的 pending 任务。

### 8.3 摘要映射

```swift
func makeHomeTaskSummary(tasks: [HealthTask]) -> IOS26HomeTaskSummary
```

输出要点：

1. 数字摘要要稳定、可解释。
2. 预览条目要短，尽量一行读完。
3. 时间显示要用本地化短格式。
4. 任务类型可以只用图标或简短标签，不要占掉太多空间。

## 9. 业务流程

### 9.1 首页加载任务摘要

```text
HomeView 出现
  -> 读取 taskManager.tasks
  -> 生成首页代办任务摘要
  -> 若 taskManager 还在同步，则显示 loading
  -> 同步完成后刷新摘要
```

### 9.2 点击代办任务模块

```text
用户点击“代办任务”模块
  -> 轻触反馈
  -> 打开任务中心
  -> 进入 TaskCenterViewController
  -> 先看到筛选和完整任务列表
```

### 9.3 点击任务预览项

```text
用户点击某条任务预览
  -> 进入任务中心
  -> 默认停留在待完成任务视图
  -> 用户继续完成、编辑、取消或筛选
```

### 9.4 任务同步后的首页更新

```text
TaskManager.syncIncremental
  -> 更新 tasks
  -> HomeView 观察 tasks 变化
  -> 重新生成摘要
  -> 首页任务模块自动刷新
```

## 10. 关键技术方案

### 10.1 直接复用 TaskManager

首页任务模块不单独维护一份任务仓库，直接复用现有 `TaskManager`：

```swift
@ObservedObject var taskManager: TaskManager
```

优点：

1. 与任务中心数据同源。
2. 与通知注册/取消同源。
3. 与创建、完成、取消操作同源。

### 10.2 直接复用 TaskCenterViewController

首页任务模块只负责“摘要和入口”，不负责完整 CRUD。

任务中心仍由现有页面承担：

```swift
TaskCenterViewController(memberID: viewModel.selectedMemberID, taskManager: dependencies.taskManager)
```

### 10.3 首页模块位置

建议放在首页主模块的中上部，优先级高于普通信息卡，低于主标题和成员区：

```text
主标题
成员区
代办任务模块
制定体检计划
报告解读
用药 / 家庭药箱 / 家庭档案
```

这样任务模块既能前置日常行为，也不会吞掉首页主行动。

### 10.4 推荐代码结构

```text
SparkClient/Projects/Features/Home/Presentation/IOS26HomeTaskSummaryView.swift
SparkClient/Projects/Features/Home/Presentation/IOS26HomeTaskSummaryViewModel.swift
```

如果希望先少改文件，也可以先让 `IOS26HomeDashboardView` 内部承载任务摘要子视图，但不建议把摘要计算直接写在 View body 里。

## 11. 关键代码示例

### 11.1 首页任务摘要视图

```swift
@available(iOS 26.0, *)
struct IOS26HomeTaskSummaryView: View {
    let summary: IOS26HomeTaskSummary
    let onOpenTaskCenter: () -> Void
    let onOpenTaskItem: (IOS26HomeTaskSummaryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("代办任务")
                        .font(.headline.weight(.semibold))
                    Text(summaryHeaderSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("查看全部") {
                    onOpenTaskCenter()
                }
                .font(.footnote.weight(.semibold))
            }

            HStack(spacing: 12) {
                metricPill(title: "待完成", value: "\(summary.pendingCount)")
                metricPill(title: "逾期", value: "\(summary.overdueCount)")
                metricPill(title: "今日", value: "\(summary.todayCount)")
            }

            if summary.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = summary.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重新加载任务") {
                    onOpenTaskCenter()
                }
                .buttonStyle(.bordered)
            } else if summary.items.isEmpty {
                Text("今天没有待办")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.items.prefix(3)) { item in
                        Button {
                            onOpenTaskItem(item)
                        } label: {
                            taskPreviewRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
```

### 11.2 任务摘要计算

```swift
func makeHomeTaskSummary(tasks: [HealthTask]) -> IOS26HomeTaskSummary {
    let now = Date()
    let pending = tasks.filter { $0.status == .pending }

    let overdueCount = pending.filter { task in
        guard let due = task.dueTime else { return false }
        return due < now
    }.count

    let todayCount = pending.filter { task in
        let calendar = Calendar.current
        if let due = task.dueTime {
            return calendar.isDateInToday(due)
        }
        if let start = task.startTime {
            return calendar.isDateInToday(start)
        }
        return false
    }.count

    let items = pending.sorted { lhs, rhs in
        let leftDate = lhs.dueTime ?? lhs.startTime ?? lhs.updatedAt
        let rightDate = rhs.dueTime ?? rhs.startTime ?? rhs.updatedAt
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue < rhs.priority.rawValue
        }
        return leftDate < rightDate
    }
    .prefix(3)
    .map { task in
        IOS26HomeTaskSummaryItem(
            id: task.id,
            title: task.title,
            subtitle: task.description.isEmpty ? task.type.displayName : task.description,
            timeText: task.dueTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
                ?? task.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
                ?? NSLocalizedString("task.time.unspecified", comment: "未设置时间"),
            badgeText: task.priority == .high ? "高优先级" : nil,
            priority: task.priority,
            status: task.status,
            taskType: task.type
        )
    }

    return IOS26HomeTaskSummary(
        pendingCount: pending.count,
        overdueCount: overdueCount,
        todayCount: todayCount,
        lastSyncTime: nil,
        items: Array(items),
        isLoading: false,
        errorMessage: nil
    )
}
```

### 11.3 首页接入

```swift
IOS26HomeTaskSummaryView(
    summary: makeHomeTaskSummary(tasks: taskManager.tasks),
    onOpenTaskCenter: {
        viewModel.activeSheet = .taskCenter
    },
    onOpenTaskItem: { _ in
        viewModel.activeSheet = .taskCenter
    }
)
```

说明：

1. 首页第一版只要求跳任务中心，不要求精确定位某条任务。
2. 如果后续要支持“点一条就定位”，再单独补充任务中心的初始筛选/锚点参数。

## 12. 落地细节

### 12.1 推荐改动文件

| 文件 | 动作 | 说明 |
| --- | --- | --- |
| `HomeView.swift` | 修改 | 在 iOS 26 首页工作台中插入代办任务模块 |
| `IOS26HomeDashboardView.swift` | 修改/新增 | 首页工作台承载任务摘要 |
| `TaskManager.swift` | 不改或少改 | 直接复用现有 tasks 数据 |
| `TaskCenterViewController.swift` | 不改 | 继续承担完整任务管理 |
| `HomePresentationSupport.swift` | 可选修改 | 若需要新增首页 sheet/route 承接点，再补充 |

### 12.2 不允许的实现

1. 不要单独创建一个新的任务仓库。
2. 不要把任务列表完整复制到首页。
3. 不要让首页承担任务 CRUD。
4. 不要绕过 `TaskManager` 直接读接口。
5. 不要把任务状态颜色做得太强，避免首页失去健康场景的克制感。

### 12.3 与现有任务中心的关系

首页任务模块与任务中心的关系是：

```text
首页代办任务模块 = 摘要 + 导航入口
TaskCenterViewController = 全量管理 + 创建 / 编辑 / 完成 / 取消
TaskManager = 单一事实源
```

这个分工要保持清楚，不能混成两个入口做同一件事。

### 12.4 同步时机

1. 首页首次加载时，直接读 `taskManager.tasks`。
2. 首页下拉刷新时，触发 `taskManager.syncIncremental(memberID:)`。
3. 任务变更后由 `TaskManager` 自身驱动界面刷新。
4. 若任务服务尚未配置，首页显示降级状态，不要报错崩溃。

## 13. 验收标准

1. iOS 26 首页出现代办任务模块。
2. 模块可见待办数量、逾期数量、今日数量。
3. 模块最多展示 3 条任务预览。
4. 点击模块进入任务中心。
5. 点击任务预览项也进入任务中心。
6. 无任务时显示空状态，不显示假数据。
7. 同步失败时显示轻量失败状态，不影响首页其他内容。
8. 大字体、深色模式下模块仍可读。
9. 首页不出现明显布局跳动。
10. iOS 25 及以下系统行为不受影响。

## 14. 测试建议

### 14.1 单元测试

1. `makeHomeTaskSummary(tasks:)` 能正确统计 pending、overdue、today。
2. 任务排序按优先级和时间正确。
3. 空任务时 summary.items 为空。
4. 失败状态文案能正确落地。

### 14.2 手工验收

1. 首页有 pending 任务时，模块显示任务摘要。
2. 任务为 0 时，模块显示空状态。
3. 任务同步后摘要数字实时更新。
4. 点击模块后进入任务中心。
5. 深色模式下检查卡片边界和状态色。
6. 大字体下检查三条任务预览是否仍可读。

## 15. 风险与规避

| 风险 | 影响 | 规避 |
| --- | --- | --- |
| 任务太多 | 首页信息过载 | 只展示 3 条，剩余进入任务中心 |
| 任务状态噪音太强 | 破坏首页克制感 | 状态颜色只用于标签和数字 |
| 同步失败 | 用户看不到任务 | 保留缓存摘要和重试入口 |
| 首页卡片变长 | 首屏被挤压 | 控制摘要字段和行数 |
| 与任务中心重复 | 体验冗余 | 首页只做摘要，不做编辑 |

## 16. 后期扩展

1. 支持按成员过滤任务摘要。
2. 支持把任务类型标签映射到“医疗 / 运动 / 饮食”。
3. 支持首页直接创建任务的快捷入口。
4. 支持任务逾期红点和成员关联提醒。
5. 支持任务完成率周视图。

