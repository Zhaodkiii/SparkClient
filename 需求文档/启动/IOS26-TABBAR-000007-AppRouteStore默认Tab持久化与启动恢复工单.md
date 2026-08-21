# IOS26-TABBAR-000007 AppRouteStore 默认 Tab 持久化与启动恢复工单

> 创建日期：2026-08-22  
> 关联模块：AppRouteStore、MainTabCoordinatorView、IOS26TabBarView、应用启动路由  
> 关联代码：`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`、`SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift`、`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift`  
> 状态：新需求/待实现  
> 优先级：P1，主导航体验优化

---

## 1. 一句话目标

`AppRouteStore` 的默认初始 tab 仍保持 `.chat`，但需要把用户最后一次主动切换的根 tab 持久化；下次启动 App 时优先恢复上次 tab，让用户回到最近使用的主页面。

当前代码：

```swift
@Published var selectedTab: RootTab = AppRouteStore.defaultRootTab
@Published private(set) var routeStacks: [RootTab: [AppRoute]] = [:]

static var defaultRootTab: RootTab {
    .chat
}
```

目标行为：

```text
首次安装 / 无历史记录
  -> 默认打开 .chat

用户切换到 healthHome / nutrition / fitness / settings
  -> 持久化 selectedTab

下次冷启动
  -> 恢复上次 selectedTab

如果历史 selectedTab 当前不可见
  -> 回退到 .chat 或当前可见默认 tab
```

---

## 2. 背景与问题

当前 `AppRouteStore.selectedTab` 使用静态默认值 `.chat` 初始化。每次 App 冷启动或 route store 重建时，都会回到 Chat tab。

这会导致：

1. 用户上次停留在首页、饮食、运动健康、设置等页面，下次打开仍回到 Chat。
2. 新增 Nutrition / Fitness / iOS26 Tab 后，用户的主导航偏好无法保留。
3. `MainTabCoordinatorView` 和 `IOS26TabBarView` 都绑定 `routeStore.selectedTab`，但持久化职责目前没有统一收口。
4. 当前 `RootTab` raw value 已有历史兼容约定，适合用 raw value 做轻量持久化，但需要处理不可见 tab 和历史值失效。

本工单解决的是：**主 tab 选中态的本地持久化和启动恢复**。

---

## 3. 当前实现事实

### 3.1 AppRouteStore

文件：`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`

当前 `RootTab`：

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

当前默认值：

```swift
@Published var selectedTab: RootTab = AppRouteStore.defaultRootTab

static var defaultRootTab: RootTab {
    .chat
}
```

当前切换入口：

```swift
func route(to route: AppRoute, replaceStack: Bool = false) {
    let tab = route.rootTab
    selectedTab = tab
    ...
}

func replaceStack(_ routes: [AppRoute], for tab: RootTab) {
    routeStacks[tab] = routes
    selectedTab = tab
}

func resetRouteGraph() {
    selectedTab = Self.defaultRootTab
    routeStacks.removeAll()
}
```

### 3.2 Tab 容器

文件：

```text
SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift
SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift
```

两处都通过：

```swift
TabView(selection: $routeStore.selectedTab)
```

绑定当前 tab。

`MainTabCoordinatorView` 当前可见 tab：

```swift
private var visibleTabs: Set<AppRouteStore.RootTab> {
    if usesDashboardHomeStyle {
        return [.healthHome, .chat, .settings]
    }
    return [.healthHome, .chat, .nutrition, .fitness, .settings]
}
```

`IOS26TabBarView` 在 dashboard/classic 样式下展示的 tab 集合不同，需要考虑历史持久化 tab 当前不可见的情况。

---

## 4. 需求范围

### 4.1 selectedTab 持久化

#### 需求说明

用户主动切换根 tab 后，保存当前 `selectedTab`。下次 App 启动创建 `AppRouteStore` 时，读取持久化值作为初始 tab。

#### 基础要求

1. 首次启动或没有持久化值时，仍使用 `.chat`。
2. 持久化内容建议保存 `RootTab.rawValue`。
3. 只持久化根 tab，不持久化 `routeStacks`。
4. `route(to:)` 和 `replaceStack(_:for:)` 引起的 tab 切换也应更新持久化值。
5. `resetRouteGraph()` 应回到 `.chat`，并清理或重置持久化 tab。

#### 技术方案

在 `AppRouteStore` 内增加轻量 storage：

```swift
private static let selectedTabStorageKey = "app.route.selectedRootTab"

@Published var selectedTab: RootTab {
    didSet {
        persistSelectedTabIfNeeded(selectedTab)
    }
}
```

初始化时：

```swift
init(storage: UserDefaults = .standard) {
    self.storage = storage
    self.selectedTab = Self.restoreSelectedTab(from: storage)
}
```

恢复逻辑：

```swift
static func restoreSelectedTab(from storage: UserDefaults) -> RootTab {
    let raw = storage.integer(forKey: selectedTabStorageKey)
    return RootTab(rawValue: raw) ?? defaultRootTab
}
```

注意：`UserDefaults.integer(forKey:)` 无法区分“未设置”和 rawValue=0，建议使用 `object(forKey:) as? Int`。

推荐实现：

```swift
static func restoreSelectedTab(from storage: UserDefaults) -> RootTab {
    guard let raw = storage.object(forKey: selectedTabStorageKey) as? Int,
          let tab = RootTab(rawValue: raw) else {
        return defaultRootTab
    }
    return tab
}
```

#### 验收标准

1. 首次启动默认进入 `.chat`。
2. 用户切换到 `.healthHome` 后杀进程重启，默认进入 `.healthHome`。
3. 用户切换到 `.settings` 后杀进程重启，默认进入 `.settings`。
4. `route(to: .chatThread(...))` 后，持久化 tab 为 `.chat`。
5. `resetRouteGraph()` 后，下次启动回到 `.chat`。

### 4.2 不可见 tab 兜底

#### 需求说明

由于 iOS26 / classic / dashboard 样式下可见 tab 不完全一致，历史持久化 tab 可能在当前 UI 中不可见。启动和样式变化时必须兜底到可见 tab。

#### 基础要求

1. 如果持久化值对应的 `RootTab` 已不存在，回退 `.chat`。
2. 如果持久化 tab 当前不可见，回退到 `.chat`。
3. 如果 `.chat` 在某种未来布局中也不可见，回退到第一个可见 tab。
4. 回退后的 tab 应同步写回持久化值，避免下次继续恢复非法 tab。

#### 技术方案

`AppRouteStore` 不直接知道不同 Tab 容器的 `visibleTabs`，因此可由容器调用：

```swift
func ensureSelectedTabIsVisible(visibleTabs: Set<RootTab>) {
    guard visibleTabs.contains(selectedTab) == false else { return }
    let fallback = visibleTabs.contains(Self.defaultRootTab)
        ? Self.defaultRootTab
        : (visibleTabs.first ?? Self.defaultRootTab)
    selectedTab = fallback
}
```

`MainTabCoordinatorView.ensureSelectedTabIsVisible()` 和 `IOS26TabBarView` 中同类逻辑应改为调用 store 方法，避免两处兜底规则不一致。

#### 验收标准

1. 持久化 `.nutrition`，切换到 dashboard 样式后，启动回退到 `.chat` 或当前可见默认 tab。
2. 持久化未知 rawValue，不崩溃，回退 `.chat`。
3. 样式切换导致当前 tab 不可见时，立即切到可见 tab 并更新持久化值。

### 4.3 账号与登出边界

#### 需求说明

需要明确 selectedTab 持久化是设备级还是账号级。

本工单建议：**设备级偏好**。理由：

1. selectedTab 是本机 UI 使用习惯，不含敏感数据。
2. 与登录账号强绑定收益低。
3. 游客账号和正式账号切换时保持最近使用入口，更符合本地导航体验。

#### 基础要求

1. 登录/登出不强制清理 selectedTab。
2. `resetRouteGraph()` 应清 route stack，但 selectedTab 仍按产品选择回 `.chat` 并持久化。
3. 如果后续产品要求账号级，可把 key 扩展为 `app.route.selectedRootTab.<accountID>`。

#### 验收标准

1. 用户登出再登录，不因 selectedTab 持久化导致崩溃。
2. 游客账号升级后，selectedTab 仍能正常恢复。
3. `resetRouteGraph()` 后不恢复到旧 tab。

### 4.4 深链和显式路由优先级

#### 需求说明

启动恢复 tab 不能覆盖深链、通知、任务跳转等显式路由。

优先级：

```text
显式 AppRoute / DeepLink / Notification
  > 冷启动持久化 selectedTab
  > AppRouteStore.defaultRootTab(.chat)
```

#### 基础要求

1. 如果启动时有 `launchIntentCoordinator` 待处理路由，应先使用 route intent。
2. `route(to:)` 设置的 tab 会覆盖持久化恢复值，并写入新的 selectedTab。
3. 冷启动没有显式路由时，才使用持久化 tab。

#### 验收标准

1. 持久化 `.settings`，通过通知打开聊天线程，应进入 `.chat`。
2. 持久化 `.chat`，通过首页任务深链打开，应进入 `.healthHome`。
3. 深链处理完成后，新的 tab 成为后续持久化值。

---

## 5. 整体业务流程

### 5.1 冷启动恢复

```text
AppContainer / Composition Root 创建 AppRouteStore
  ↓
AppRouteStore.init 读取 UserDefaults
  ↓
rawValue 可解码？
  ├─ 否 -> selectedTab = .chat
  └─ 是 -> selectedTab = persistedTab
  ↓
Tab 容器 onAppear
  ↓
ensureSelectedTabIsVisible(visibleTabs)
  ↓
显示最终 selectedTab
```

### 5.2 用户切换 Tab

```text
用户点击 TabView tab
  ↓
TabView binding 写入 routeStore.selectedTab
  ↓
AppRouteStore didSet
  ↓
UserDefaults 保存 rawValue
```

### 5.3 程序化路由

```text
routeStore.route(to: route)
  ↓
selectedTab = route.rootTab
  ↓
持久化 rootTab
  ↓
更新 routeStacks
```

### 5.4 重置路由图

```text
resetRouteGraph()
  ↓
selectedTab = .chat
  ↓
routeStacks.removeAll()
  ↓
持久化 .chat 或清理 key
```

---

## 6. 数据与持久化

| 数据 | 存储 | 生命周期 | 说明 |
| --- | --- | --- | --- |
| `selectedTab.rawValue` | `UserDefaults` | 设备级持久化 | 只存 root tab |
| `routeStacks` | 内存 | AppRouteStore 生命周期 | 不持久化 |
| deep link route | 启动协调器内存状态 | 单次消费 | 优先级高于 selectedTab |

建议 key：

```text
app.route.selectedRootTab
```

如果需要版本化：

```text
app.route.selectedRootTab.v1
```

---

## 7. 错误模型

| 场景 | 处理 |
| --- | --- |
| UserDefaults 无值 | `.chat` |
| rawValue 无法解析 | `.chat` |
| tab 当前不可见 | `.chat` 或第一个可见 tab |
| UserDefaults 写入失败 | 不影响当前会话 UI |
| 深链指定 tab | 深链优先 |
| resetRouteGraph | 回 `.chat` 并同步持久化 |

---

## 8. 与其他模块的接口边界

本模块负责：

1. 保存和恢复 App 根 tab。
2. 在 tab 不可见时兜底。
3. 保证程序化路由同步更新 selectedTab。

本模块不负责：

1. 持久化二级页面导航栈。
2. 恢复 Chat 具体线程、文章详情或设置子页。
3. 改变默认 tab 的业务定义，默认仍是 `.chat`。
4. 改变 Tab 样式、顺序或图标。

上游调用方：

```text
MainTabCoordinatorView
IOS26TabBarView
LaunchIntentCoordinator
其他 routeStore.route(to:) 调用方
```

下游依赖：

```text
UserDefaults
AppRouteStore.RootTab rawValue
```

---

## 9. 关键代码对应关系

| 能力 | 代码位置 |
| --- | --- |
| RootTab 定义与 selectedTab | `SparkClient/Projects/App/Sources/App/AppRouteStore.swift` |
| 经典主 Tab 容器 | `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` |
| iOS26 Tab 容器 | `SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift` |
| 深链/启动意图就绪 | `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift`、`LaunchIntentCoordinator` 相关代码 |

---

## 10. 测试策略

建议新增或调整测试：

| 测试 | 覆盖点 |
| --- | --- |
| `AppRouteStoreSelectedTabPersistenceTests` | 保存/恢复 selectedTab |
| `AppRouteStoreDefaultTabTests` | 无持久化值默认 `.chat` |
| `AppRouteStoreInvalidRawValueTests` | 非法 rawValue 回退 `.chat` |
| `AppRouteStoreVisibleTabFallbackTests` | 不可见 tab 回退并持久化 |
| `AppRouteStoreRoutePersistenceTests` | `route(to:)` / `replaceStack` 更新持久化 |
| `AppRouteStoreResetTests` | reset 后回 `.chat` |

手动验收：

1. 首次安装打开 App，默认进入 Chat。
2. 切到首页，杀进程重启，进入首页。
3. 切到设置，杀进程重启，进入设置。
4. 切到饮食，切换 dashboard 样式后重启，回退到可见 tab。
5. 通过通知/深链进入聊天线程，优先进入 Chat，而不是持久化 tab。

---

## 11. 当前实现、缺口与演进

当前实现：

1. `AppRouteStore.defaultRootTab` 已固定为 `.chat`。
2. `selectedTab` 当前只在内存中维护。
3. `TabView(selection:)` 已绑定 `routeStore.selectedTab`。
4. `MainTabCoordinatorView` 已有可见 tab 兜底逻辑。
5. `IOS26TabBarView` 也存在样式变化下的 tab 可见性处理。

当前缺口：

1. `selectedTab` 没有持久化。
2. `AppRouteStore` 没有初始化恢复逻辑。
3. 可见 tab 兜底逻辑分散在不同 Tab 容器中。
4. 深链优先级和持久化 tab 的关系未在文档中明确。
5. 缺少 selectedTab 持久化测试。

建议演进：

1. 把 tab 持久化封装为 `AppRoutePersistenceStore`，便于后续持久化更多根级 UI 偏好。
2. 如果后续需要恢复二级页面，再单独设计 route stack 持久化，不纳入本期。
3. 如果产品希望账号级 tab 偏好，再把 storage key 加上 accountID。

---

## 12. 整体验收标准

1. 无历史记录时默认 tab 仍为 `.chat`。
2. 用户切换 tab 后，下次冷启动恢复最后 tab。
3. 程序化路由切换 tab 后，也会更新持久化值。
4. 当前不可见 tab 不会导致 TabView 空白或异常。
5. `resetRouteGraph()` 后回到 `.chat`。
6. 深链/通知等显式路由优先于持久化 tab。
7. 不持久化二级导航栈，避免打开 App 直接进入旧详情页。

