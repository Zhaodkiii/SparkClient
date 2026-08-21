# IOS26-TABBAR-000008 AppRouteStore 默认 Tab 持久化失效排查与独立 PreferenceStore 工单

> 创建日期：2026-08-22  
> 关联模块：AppRouteStore、MainTabCoordinatorView、IOS26TabBarView、RouteCoordinator、启动路由  
> 关联代码：`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`、`SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift`、`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift`、`SparkClient/Projects/App/Sources/App/Architecture/RouteCoordinator.swift`、`SparkClient/Projects/Features/Home/Presentation/HomeSectionPreferenceStore.swift`  
> 状态：问题排查/待实现  
> 优先级：P0，启动默认页面体验问题

---

## 1. 一句话目标

修复 `AppRouteStore.selectedTab` 持久化失效问题：用户从对话 tab 切换到首页后，退出 App 再次打开，默认仍进入对话。需要排查是 selectedTab 未正确写入、启动未正确读取，还是启动后被 `resetRouteGraph`、显式路由或 Tab 可见性兜底重新改回 `.chat`。

本工单要求将 selectedTab 的 `UserDefaults` 存储从 `AppRouteStore` 中拆出为单独文件，参考 `HomeSectionPreferenceStore` 的模式实现。

---

## 2. 当前问题

复现路径：

```text
打开 App
  ↓
默认进入对话 tab
  ↓
用户切换到首页 tab
  ↓
退出应用
  ↓
再次打开 App
  ↓
实际：仍默认进入对话 tab
期望：默认进入首页 tab
```

用户提供的当前实现：

```swift
/// selectedTab 持久化 key（IOS26-TABBAR-000007）：设备级偏好，只存根 tab raw value。
private static let selectedTabStorageKey = "app.route.selectedRootTab"

private let storage: UserDefaults

@Published var selectedTab: RootTab {
    didSet {
        guard selectedTab != oldValue else { return }
        storage.set(selectedTab.rawValue, forKey: Self.selectedTabStorageKey)
    }
}

static var defaultRootTab: RootTab {
    .chat
}

init(storage: UserDefaults = .standard) {
    self.storage = storage
    selectedTab = Self.restoreSelectedTab(from: storage)
}

static func restoreSelectedTab(from storage: UserDefaults) -> RootTab {
    guard let raw = storage.object(forKey: selectedTabStorageKey) as? Int,
          let tab = RootTab(rawValue: raw) else {
        return defaultRootTab
    }
    return tab
}
```

从代码看，单纯的 `didSet + UserDefaults` 方案理论上能写入；如果仍恢复 `.chat`，优先怀疑后续启动链路覆盖了恢复值。

---

## 3. 当前实现事实

### 3.1 AppRouteStore 当前状态

文件：`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`

当前 `RootTab` raw value：

```swift
enum RootTab: Int, Hashable {
    case healthHome = 0
    case knowledge = 2
    case chat = 3
    case settings = 4
    case popularScience = 5
    case deepTutor = 6
    case search = 7
    case nutrition = 8
    case fitness = 9
}
```

当前默认 tab：

```swift
static var defaultRootTab: RootTab {
    .chat
}
```

当前已经把持久化逻辑直接写入 `AppRouteStore.selectedTab.didSet`。

### 3.2 TabView 绑定

文件：

```text
SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift
SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift
```

两套 Tab 容器均使用：

```swift
TabView(selection: $routeStore.selectedTab)
```

因此用户点击 tab 理论上会修改 `routeStore.selectedTab`。

`MainTabCoordinatorView` 还存在：

```swift
.onChange(of: routeStore.selectedTab) { _ in
    ensureSelectedTabIsVisible()
}
.onAppear {
    ensureSelectedTabIsVisible()
    launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
}
```

`IOS26TabBarView` 还存在：

```swift
.onAppear {
    routeStore.ensureSelectedTabIsVisible(visibleTabs: visibleTabs)
    launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
}
.onChange(of: homeStylePreferenceStore.style) { _, _ in
    routeStore.ensureSelectedTabIsVisible(visibleTabs: visibleTabs)
}
```

### 3.3 可能覆盖 selectedTab 的路径

文件：`SparkClient/Projects/App/Sources/App/Architecture/RouteCoordinator.swift`

当前账号运行时重置会调用：

```swift
func resetRouteGraphForAccountRuntime(reason: String) {
    logger.info("路由流程：重置账号级 route graph reason=\(reason)", module: .general)
    routeStore.resetRouteGraph()
}
```

而 `AppRouteStore.resetRouteGraph()` 当前会：

```swift
selectedTab = Self.defaultRootTab
routeStacks.removeAll()
```

如果 App 冷启动恢复了 `.healthHome`，随后 session 状态变化触发 `resetRouteGraphForAccountRuntime`，就会把 selectedTab 改回 `.chat`，并通过 didSet 写回 UserDefaults。这样下次启动也继续是 `.chat`。

### 3.4 参考实现

文件：`SparkClient/Projects/Features/Home/Presentation/HomeSectionPreferenceStore.swift`

现有首页分页持久化采用独立 store：

```swift
@MainActor
final class HomeSectionPreferenceStore: ObservableObject {
    static let shared = HomeSectionPreferenceStore()

    @Published var section: IOS26HomeView.HomeSection {
        didSet {
            guard section != oldValue else { return }
            userDefaults.set(section.rawValue, forKey: storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "spark.home.last_section"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: storageKey),
           let section = IOS26HomeView.HomeSection(rawValue: raw) {
            self.section = section
        } else {
            self.section = .dashboard
        }
    }
}
```

本工单要求 selectedTab 持久化也采用同类独立文件，不把 UserDefaults 细节继续放在 `AppRouteStore` 内部。

---

## 4. 根因假设

### 4.1 H1：启动后 `resetRouteGraph()` 覆盖持久化值

优先级最高。

现象链路：

```text
AppRouteStore.init 恢复 selectedTab = .healthHome
  ↓
session / account runtime 初始化
  ↓
RouteCoordinator.resetRouteGraphForAccountRuntime(...)
  ↓
routeStore.resetRouteGraph()
  ↓
selectedTab = .chat
  ↓
didSet 写回 UserDefaults = 3
  ↓
用户看到仍是 Chat
```

需要确认：

1. 冷启动时是否有 `resetRouteGraphForAccountRuntime` 日志。
2. `AppRouteStore.init` 恢复出的 tab 是什么。
3. `resetRouteGraph()` 后是否把 `.chat` 写回了 storage。

### 4.2 H2：Tab 切换没有写入真实共享的 routeStore

可能原因：

1. App 中存在多个 `AppRouteStore()` 实例。
2. 用户操作的 TabView 绑定了一个实例，启动恢复读取的是另一个实例。
3. Preview 或 Feature assembly 中创建了额外实例，但正式链路应确认只用 NotificationAssembly 中的 `routeStore`。

当前搜索发现：

```text
AssemblyProducts.swift -> let routeStore = AppRouteStore()
FeatureAssemblies.swift preview -> let routeStore = AppRouteStore()
```

正式链路大概率只有一个，但仍需日志确认实例 identity。

### 4.3 H3：`ensureSelectedTabIsVisible` 回退到 `.chat`

如果用户切到的 tab 在当前布局不可见，`ensureSelectedTabIsVisible` 会回退 `.chat` 并写回。

但用户从对话切到首页，`.healthHome` 在 `MainTabCoordinatorView.visibleTabs` 和 `IOS26TabBarView.visibleTabs` 中通常都是可见的，因此该假设优先级低于 H1。

需要确认：

1. 启动时 `visibleTabs` 是否包含 `.healthHome`。
2. `ensureSelectedTabIsVisible` 是否被调用并执行 fallback。

### 4.4 H4：存储 key 或 UserDefaults suite 不一致

当前 `AppRouteStore` 使用 `.standard`，参考的 `HomeSectionPreferenceStore` 也使用 `.standard`。如果后续注入了测试 UserDefaults 或不同 suite，可能造成读写不一致。

需要确认：

1. 写入和读取的 key 是否同一个。
2. 写入是否发生。
3. 读取时 rawValue 是否存在。

---

## 5. 需求范围

### 5.1 新增独立 RootTabPreferenceStore

#### 需求说明

参考 `HomeSectionPreferenceStore`，创建独立文件管理根 tab 持久化。

建议路径：

```text
SparkClient/Projects/App/Sources/App/RootTabPreferenceStore.swift
```

或如果希望跟路由更集中：

```text
SparkClient/Projects/App/Sources/App/Architecture/RootTabPreferenceStore.swift
```

推荐实现：

```swift
import Combine
import Foundation

/// 根 Tab 停留位置（UserDefaults 持久化）。
/// 默认仍为 AppRouteStore.defaultRootTab；只存根 tab，不存二级导航栈。
@MainActor
final class RootTabPreferenceStore: ObservableObject {
    static let shared = RootTabPreferenceStore()

    @Published var tab: AppRouteStore.RootTab {
        didSet {
            guard tab != oldValue else { return }
            userDefaults.set(tab.rawValue, forKey: storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "app.route.selectedRootTab"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.object(forKey: storageKey) as? Int,
           let tab = AppRouteStore.RootTab(rawValue: raw) {
            self.tab = tab
        } else {
            self.tab = AppRouteStore.defaultRootTab
        }
    }

    func resetToDefault() {
        tab = AppRouteStore.defaultRootTab
    }

    func removePersistedValue() {
        userDefaults.removeObject(forKey: storageKey)
        tab = AppRouteStore.defaultRootTab
    }
}
```

#### 基础要求

1. `AppRouteStore` 不直接持有 `UserDefaults`。
2. `AppRouteStore` 初始化时从 `RootTabPreferenceStore.tab` 读取。
3. `selectedTab` 改变时同步写入 `RootTabPreferenceStore.tab`。
4. 测试可注入自定义 `RootTabPreferenceStore` 或 `UserDefaults`。
5. key 沿用 `app.route.selectedRootTab`，兼容已写入数据。

#### 验收标准

1. 切换首页后，`RootTabPreferenceStore.tab == .healthHome`。
2. 冷启动新建 `AppRouteStore` 时，初始 selectedTab 为 `.healthHome`。
3. 不再由 `AppRouteStore` 直接调用 `UserDefaults.set`。

### 5.2 AppRouteStore 接入 PreferenceStore

#### 需求说明

`AppRouteStore` 继续作为路由状态源，但持久化细节委托给 `RootTabPreferenceStore`。

建议结构：

```swift
@MainActor
final class AppRouteStore: ObservableObject {
    private let rootTabPreferenceStore: RootTabPreferenceStore

    @Published var selectedTab: RootTab {
        didSet {
            guard selectedTab != oldValue else { return }
            rootTabPreferenceStore.tab = selectedTab
        }
    }

    init(rootTabPreferenceStore: RootTabPreferenceStore = .shared) {
        self.rootTabPreferenceStore = rootTabPreferenceStore
        self.selectedTab = rootTabPreferenceStore.tab
    }
}
```

#### 关键规则

1. `route(to:)`、`replaceStack(_:for:)`、用户点击 TabView 都可以持久化。
2. `ensureSelectedTabIsVisible` 的兜底也可以持久化，因为这是当前布局下的有效 tab。
3. `resetRouteGraph()` 是否持久化 `.chat` 需要单独决策，不能默认覆盖用户最后 tab。

#### 验收标准

1. 用户点击首页，杀进程重启后进入首页。
2. 用户点击设置，杀进程重启后进入设置。
3. 程序化 route 到 chat thread 后，下一次启动进入 Chat。

### 5.3 resetRouteGraph 不应误覆盖用户最后 tab

#### 需求说明

需要区分两类 reset：

1. 用户显式退出账号、清空运行时路由：可以回到 `.chat`。
2. 冷启动 session 恢复、账号运行时重建：不应覆盖已经恢复的持久化 tab。

当前 `resetRouteGraphForAccountRuntime(reason:)` 统一调用 `routeStore.resetRouteGraph()`，而 `resetRouteGraph()` 会把 selectedTab 设为 `.chat`。这可能是“切到首页后重启仍回对话”的直接原因。

#### 推荐方案

将 reset 拆成两个语义：

```swift
func resetRouteStacksPreservingSelectedTab() {
    routeStacks.removeAll()
}

func resetRouteGraphToDefaultTab(persistDefault: Bool) {
    selectedTab = Self.defaultRootTab
    routeStacks.removeAll()
    if persistDefault {
        rootTabPreferenceStore.tab = Self.defaultRootTab
    }
}
```

`RouteCoordinator.resetRouteGraphForAccountRuntime(reason:)` 根据 reason 选择：

```text
冷启动/会话恢复/账号运行时重建
  -> resetRouteStacksPreservingSelectedTab

明确登出/账号切换需要回首页或回 Chat
  -> resetRouteGraphToDefaultTab(persistDefault: true)
```

如果无法短期区分 reason，至少增加日志并先不要在冷启动恢复阶段持久化 `.chat`。

#### 验收标准

1. 冷启动恢复 session 时，不把 `.healthHome` 覆盖成 `.chat`。
2. 明确调用 reset 到默认 tab 时，才写回 `.chat`。
3. 日志能看出 reset 是否保留 selectedTab。

### 5.4 增加临时排查日志

#### 需求说明

如果无法一次确定问题，应先加临时日志，让用户复现“切到首页后重启仍回对话”。

日志只记录 tab、rawValue、原因、实例标识，不记录用户隐私数据。

建议日志点：

```text
app.route.tab.preference.init raw=<raw?> restored=<tab> default=<tab>
```

```text
app.route.tab.preference.write old=<tab> new=<tab> raw=<raw> source=selectedTab.didSet
```

```text
app.route.store.init selected=<tab> instance=<ObjectIdentifier>
```

```text
app.route.tab.changed old=<tab> new=<tab> source=tabView|route|replaceStack|visibilityFallback|reset
```

```text
app.route.tab.visibility_check selected=<tab> visible=<tabs> fallback=<tab?> didFallback=<true|false>
```

```text
app.route.reset reason=<reason> mode=preserveSelectedTab|toDefaultTab selectedBefore=<tab> selectedAfter=<tab>
```

复现后判断：

| 日志现象 | 结论 |
| --- | --- |
| 切首页没有 write `.healthHome` | TabView 绑定或 selectedTab didSet 未触发 |
| 有 write `.healthHome`，下次 init restored `.healthHome`，随后 reset 到 `.chat` | resetRouteGraph 覆盖 |
| 有 write `.healthHome`，下次 init raw 仍为 3 | 某处又写回 `.chat` |
| init restored `.healthHome`，visibility fallback 到 `.chat` | visibleTabs 计算或布局模式导致首页不可见 |
| 出现多个不同 routeStore instance | AppRouteStore 多实例问题 |

#### 验收标准

1. 复现日志能定位最后一次把 selectedTab 改为 `.chat` 的调用来源。
2. 临时日志不输出账号、token、业务数据。
3. 修复完成后可降级为 debug 日志或移除临时日志。

---

## 6. 整体业务流程

### 6.1 用户切换到首页

```text
用户点击首页 tab
  ↓
TabView(selection:) 写入 routeStore.selectedTab = .healthHome
  ↓
AppRouteStore.didSet
  ↓
RootTabPreferenceStore.tab = .healthHome
  ↓
UserDefaults["app.route.selectedRootTab"] = 0
```

### 6.2 冷启动恢复

```text
App 启动
  ↓
RootTabPreferenceStore.shared init
  ↓
读取 UserDefaults raw=0
  ↓
tab = .healthHome
  ↓
AppRouteStore init selectedTab = .healthHome
  ↓
MainTabCoordinatorView / IOS26TabBarView onAppear
  ↓
ensureSelectedTabIsVisible
  ↓
如果 healthHome 可见 -> 保持 healthHome
```

### 6.3 reset 不覆盖用户 tab

```text
session 恢复 / runtime 重建
  ↓
RouteCoordinator.resetRouteGraphForAccountRuntime
  ↓
只清 routeStacks
  ↓
selectedTab 保持 .healthHome
```

---

## 7. 数据与持久化

| 数据 | 存储 | key | 默认 |
| --- | --- | --- | --- |
| 根 tab rawValue | UserDefaults | `app.route.selectedRootTab` | `.chat` |
| routeStacks | 内存 | 无 | 空 |
| 首页分页 section | UserDefaults | `spark.home.last_section` | `.dashboard` |

注意：

1. selectedTab 是设备级 UI 偏好。
2. 不存二级导航栈。
3. 不因普通 session 恢复清理 selectedTab。

---

## 8. 错误模型

| 场景 | 处理 |
| --- | --- |
| UserDefaults 无值 | `.chat` |
| rawValue 不合法 | `.chat` |
| selectedTab 当前不可见 | 兜底到 `.chat` 或第一个可见 tab |
| resetRouteGraph 冷启动调用 | 保留 selectedTab，只清 stack |
| 显式退出登录需要回默认 | 回 `.chat` 并持久化 |
| 深链/通知显式路由 | 显式路由优先并更新 selectedTab |

---

## 9. 关键代码对应关系

| 能力 | 代码位置 |
| --- | --- |
| selectedTab 与 RootTab | `SparkClient/Projects/App/Sources/App/AppRouteStore.swift` |
| 新增独立持久化 store | `SparkClient/Projects/App/Sources/App/RootTabPreferenceStore.swift`（建议新增） |
| 参考持久化 store | `SparkClient/Projects/Features/Home/Presentation/HomeSectionPreferenceStore.swift` |
| 经典 Tab 容器 | `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` |
| iOS26 Tab 容器 | `SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift` |
| 路由重置 | `SparkClient/Projects/App/Sources/App/Architecture/RouteCoordinator.swift` |
| AppRouteStore 装配 | `SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift`、`SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift` |

---

## 10. 测试策略

建议新增：

| 测试 | 覆盖点 |
| --- | --- |
| `RootTabPreferenceStoreTests` | rawValue 保存、恢复、非法值回退 |
| `AppRouteStoreInitialSelectedTabTests` | 初始化读取 preference store |
| `AppRouteStoreSelectedTabWriteTests` | selectedTab 变化写入 preference store |
| `AppRouteStoreResetPreserveTabTests` | runtime reset 只清 stack 不覆盖 tab |
| `AppRouteStoreResetDefaultTabTests` | 显式 reset 回 `.chat` 并持久化 |
| `AppRouteStoreVisibilityFallbackTests` | 不可见 tab 兜底并写回 |

手动验收：

1. 清空 App 数据，首次启动进入对话。
2. 切换到首页，杀进程重启，进入首页。
3. 切换到设置，杀进程重启，进入设置。
4. 冷启动日志中没有 session reset 把首页覆盖为对话。
5. 深链打开聊天线程时仍进入 Chat。

---

## 11. 当前实现、缺口与演进

当前实现：

1. `AppRouteStore` 已有 `selectedTab`。
2. `defaultRootTab` 仍为 `.chat`。
3. `selectedTab` 已尝试直接写入 UserDefaults。
4. 两套 Tab 容器都绑定 `routeStore.selectedTab`。
5. `HomeSectionPreferenceStore` 已提供可参考的独立 UserDefaults store 模式。

当前缺口：

1. selectedTab 持久化与路由状态耦合在 `AppRouteStore` 内。
2. 缺少独立 `RootTabPreferenceStore`。
3. `resetRouteGraph()` 可能在冷启动阶段覆盖恢复值。
4. 缺少日志判断 selectedTab 是未写入、未读取，还是被后续覆盖。
5. 缺少持久化失效的回归测试。

建议演进：

1. 统一 App 级 UI 偏好存储目录，避免偏好散落在不同 feature。
2. route stack 持久化另开工单，不和本次 root tab 混做。
3. 修复稳定后移除临时排查日志，仅保留关键 debug。

---

## 12. 整体验收标准

1. 从对话切换到首页，退出 App 后再次打开默认进入首页。
2. 从首页切换到设置，退出 App 后再次打开默认进入设置。
3. 首次安装或无存储值时仍默认进入对话。
4. `resetRouteGraphForAccountRuntime` 不会在冷启动恢复时把 tab 写回 `.chat`。
5. 显式路由、深链、通知仍可覆盖持久化 tab。
6. selectedTab 持久化逻辑位于独立 `RootTabPreferenceStore` 文件。
7. 日志能定位 selectedTab 每次恢复、写入、兜底和 reset 的来源。

