# DEEPTUTORCHAT-000053 完全移除 DeepTutorChat 模块改造范围工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000053 |
| 工单类型 | P0 模块下线 / 编译依赖清理范围梳理 |
| 状态 | 待实施；本文仅定义改造范围，不包含任何代码实现 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标 | 完全移除 iOS 客户端中的 `DeepTutorChat` 运行时模块、入口、设置、持久化访问、测试和面向用户的文案，使工程不再编译或暴露该能力 |
| 模块根目录 | `SparkClient/Projects/Features/DeepTutorChat/` |
| 历史工单目录 | `需求文档/对话/DeepTutorChat/` |
| 创建日期 | 2026-08-26 |
| 当前盘点 | 模块本体 159 个 Swift 文件；专属测试 7 个 Swift 文件；历史工单 Markdown 53 个 |
| 当前工作区注意事项 | `SparkClient/Projects/App/Sources/App/MainTabRouteDestinationBuilder.swift` 已有未提交修改；实施时不得覆盖、回退或混入该修改，需在其当前内容基础上处理 DeepTutor 引用 |

## 1. 下线定义与边界

本工单中的“完全移除”以**应用运行时与可编译源码**为边界，完成后必须同时满足：

```text
1. `SparkClient/Projects/Features/DeepTutorChat/` 不再存在。
2. 任何 App 路由、Tab、首页快捷入口、依赖装配或会话切换流程均不能创建、持有或导航至 `DeepTutorChatViewModel`。
3. UI 不再出现 DeepTutor / DeepTutorChat 入口、设置项、工具分区或对应本地化文本。
4. 普通 Chat、首页“制定体检计划/报告解读”、AI 设置、ToolHub 和登录切换仍可编译、可运行。
5. 不保留对 DeepTutor 类型、UserDefaults key、日志 module、兼容工具名或本地数据的死引用。
6. 专属测试删除；受影响的首页、普通 Chat、AI 设置和 AI Runtime 测试改为验证移除后的行为。
```

不在本工单直接删除的内容：

```text
1. `需求文档/对话/DeepTutorChat/` 下的 53 个历史工单：它们是历史记录，应保留；可在后续文档治理工单中统一增加“已下线”标记，不能在代码下线时直接删除历史。
2. 与 DeepTutor 只有文案提及、但不再有运行时含义的历史提交、Git 历史和外部参考项目。
3. 普通 `Chat` 模块本体及其既有能力；本次的替代承接端为普通 Chat，而非重建一个新 DeepTutor 模块。
```

## 2. 当前实现事实与下线策略

当前 DeepTutorChat 是一个 Feature Slice：`Presentation` 提供会话列表、会话页、输入区、消息卡片与工具 Sheet；`Application` 负责流式编排、工具循环、恢复、消息与标题；`Domain` 定义会话/工具模型；`Infrastructure` 提供本地会话存储、编解码、日志与工具数据源。

它被 App 作为单例 `DeepTutorChatViewModel` 装配，并从三个可见入口使用：DeepTutor Tab、DeepTutor 路由页面、首页快捷动作。普通 Chat 还复用了两个本应属于通用层的 DeepTutor 类型/格式化器，因此不能先物理删除目录再修编译；必须按下列顺序先断开外部依赖，再删除模块。

```text
入口与状态清理
  → 首页快捷入口固定转普通 Chat
  → AI 设置与 ToolHub 去除 DeepTutor 专属项
  → 将普通 Chat 必须保留的通用逻辑迁移/重写到 Chat 或 Core
  → 删除 Feature、专属测试、本地化与遗留数据
  → 全局残留搜索、构建和回归验证
```

## 3. 必须删除的模块本体（159 个文件）

实施时删除整个目录，而不是逐个挑选文件，以免遗留未被入口引用的工具、模型或本地存储代码：

```text
SparkClient/Projects/Features/DeepTutorChat/
├── Application/                              70 个文件
│   ├── Tools/                                 21 个文件（含 Builtins/）
│   ├── DeepTutorChatViewModel.swift
│   ├── SendDeepTutorAIMessageUseCase.swift
│   ├── DeepTutorTurnCoordinator.swift
│   ├── DeepTutorAIRuntimeAdapter.swift
│   └── 其余会话、提示词、附件、Quiz、恢复与工具编排文件
├── Domain/                                    33 个文件
│   ├── Tools/                                 13 个文件
│   ├── DeepTutorConversationState.swift
│   ├── DeepTutorMessage.swift
│   ├── DeepTutorQuickStartMode.swift
│   └── 其余能力、消息块、会话标题与工具模型文件
├── Infrastructure/                            12 个文件
│   ├── Tools/                                  5 个文件
│   ├── DeepTutorLocalChatStore.swift
│   ├── DeepTutorLocalChatRepository.swift
│   ├── DeepTutorMessageCodec.swift
│   └── DeepTutorChatLogging.swift 等
└── Presentation/                              44 个文件
    ├── Bubbles/                                2 个文件
    ├── Cards/                                 17 个文件
    ├── Rendering/                              3 个文件
    ├── ToolInteraction/                        8 个文件
    ├── DeepTutorConversationListPage.swift
    ├── DeepTutorChatPage.swift
    ├── DeepTutorComposerView.swift
    └── 其余列表、输入区、消息行、样式与附件展示文件
```

注意：以上按目录统计的 159 个文件为删除基线。实施前应以 `find SparkClient/Projects/Features/DeepTutorChat -type f` 复核；若中途新增文件，仍应随模块一并处理。

## 4. 模块外直接依赖：必须改造的生产代码

下表是当前不在模块目录内、但直接引用 DeepTutor 类型、路由、工具或设置的数据源文件。实施不可遗漏。

| 改造面 | 文件 | 当前关联代码/语义 | 下线要求 |
| --- | --- | --- | --- |
| 路由模型 | `SparkClient/Projects/App/Sources/App/AppRouteStore.swift` | `deepTutorList`、`deepTutorThread(UUID)`、`.deepTutor` RootTab | 删除两类 destination 与 RootTab 值；清理 root 判定和所有 switch 分支，确保旧 route 不再落入未知状态。 |
| 路由页面 | `SparkClient/Projects/App/Sources/App/MainTabRouteDestinationBuilder.swift` | 注入 `DeepTutorChatViewModel`，构建 `DeepTutorChatPage` | 删除注入字段、构造参数和 `.deepTutorThread` 分支；保留用户已有未提交修改。 |
| App 容器 | `SparkClient/Projects/App/Sources/App/AppContainer.swift` | 创建并持有 `DeepTutorChatViewModel`、`DeepTutorLocalChatStore` | 删除属性、初始化、依赖传递与 Preview 注入；同时删除仅供它使用的 repository/store 构造。 |
| Feature 装配 | `SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift` | 装配结构持有 `deepTutorChatViewModel` | 删除字段、构造参数和调用方参数。 |
| 账号生命周期 | `SparkClient/Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift` | 登录/切换/退出时调用 `resetForSessionSwitch()` | 删除字段、构造参数和两处 reset；不得用空实现替代。 |
| 主 Tab 协调 | `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` | 透传 DeepTutor VM | 删除观察属性、初始化参数和下游传递。 |
| 登录后主容器 | `SparkClient/Projects/App/Sources/App/SignedInMainTabHostView.swift` | 透传 DeepTutor VM 至 Tab/Home | 删除三处透传与对应构造参数。 |
| iOS 26 Tab | `SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift` | DeepTutor VM、`deepTutorContainer`、`DeepTutorConversationListPage`；Tab 声明目前有注释残留 | 删除全部 DeepTutor 容器/参数/残留注释；不可只因 Tab 被注释而保留编译依赖。 |
| 首页视图 | `SparkClient/Projects/Features/Home/Presentation/HealthHomeView.swift` | 持有并透传 DeepTutor VM，加载态合并其创建状态 | 删除 VM 参数、属性、Preview 参数和合并加载态。 |
| iOS 26 首页 | `SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift` | 将 DeepTutor VM 传给 dashboard | 删除传递及构造参数。 |
| 首页 dashboard | `SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift` | 监听 `isCreatingConversation` 并合并 loading | 改为只观察普通 Chat 创建状态。 |
| 首页动作 | `SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardActionHandler.swift` | `openQuickStart` 可转 DeepTutor；`openDeepTutor` 创建会话并导航 | 删除 DeepTutor VM 和 `openDeepTutor`；两个快捷动作统一走现有普通 Chat / 小任务链路。 |
| 首页偏好 | `SparkClient/Projects/Features/Home/Domain/HomeQuickStartConversationTarget.swift` | `chat` 与 `deepTutorChat` 二选一 | 删除 `deepTutorChat` case、标题 key 和已持久化值的兼容策略；旧值必须安全回退为 `chat`。 |
| AI 设置快照 | `SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift` | 持久化 `deepTutorConversationAppearance` | 删除字段、初始化参数、Codable decode/encode key、snapshot copy/merge；旧存档含该 key 时应由兼容解码忽略，不得造成升级失败。 |
| AI 设置模型 | `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` | `DeepTutorConversationCardStyle`、`DeepTutorToolTraceDisplayMode`、`DeepTutorConversationAppearancePreferences` | 删除三种 DeepTutor 专属类型及默认值。 |
| AI 设置首页 | `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` | 展示 DeepTutor 卡片样式与工具 trace 设置 | 删除两个设置区和绑定。 |
| AI 工具设置 | `SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIToolSettingsView.swift` | `deepTutorTools()`、专属工具分区、兼容工具合并 | 删除 DeepTutor 分区、catalog、计数、工具查找合并和仅为其服务的本地化 key；保留 Chat 工具页面。 |
| AI Runtime 调试 | `SparkClient/Projects/Core/AIRuntime/AIRuntimeDebugFlags.swift` | 复用 `deeptutor.debug.*` UserDefaults key | 删除或改名为 Runtime/Chat 语义；若 Chat 仍依赖，迁移后必须同步其读取方和迁移策略。 |
| ToolHub 外部工具 | `SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubExternalConnector.swift` | DeepTutor 天气日志名与 `.deepTutorChat` LogModule | 去除 DeepTutor 命名、日志 module 依赖及仅由其触发的执行路径；保留普通 Chat 确实使用的天气能力。 |
| ToolHub 成员资料 | `SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubQueryMemberProfile.swift` | 直接调用 `DeepTutorQueryMemberProfileFormatter` | 该格式化器被模块删除阻断；将通用格式化逻辑移动/重写为 ToolHub 或 Chat/Core 所有的类型，再替换调用。 |
| 日志枚举 | `SparkClient/Projects/Foundation/Utilities/LogModule.swift` | `.deepTutorChat = "DEEP_TUTOR_CHAT"` | 删除枚举 case，并先完成所有调用点改名/删除。 |
| Chat 快捷模式 | `SparkClient/Projects/Features/Chat/Domain/ChatQuickStartMode.swift` | `init(deepTutorMode:)` 依赖 `DeepTutorQuickStartMode` | 移除跨 Feature 初始化器；Chat 自行定义/调用自己的 mode，不能依赖待删模块的 Domain 类型。 |
| Chat 引导格式化 | `SparkClient/Projects/Features/Chat/Application/ChatGuideMemberProfilePromptFormatter.swift` | 调用 `DeepTutorQueryMemberProfileFormatter` | 与 ToolHub 同步收口为非 DeepTutor 的共享实现，或在 Chat 内重写。 |
| Chat 引导页面 | `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/Guide/ChatGuideHomeDestinationView.swift` | 构造和传递 DeepTutor VM | 删除 VM 参数、属性与下游传递；确认被注释的旧调用也一并清除。 |

## 5. 本地化、持久化、日志与数据清理

### 5.1 本地化

两个文件均有 DeepTutor 运行时文案，必须同步删除或改为 Chat 文案，不能只删其中一个语言包：

```text
SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
SparkClient/Projects/App/Resources/en.lproj/Localizable.strings
```

当前确认的键包括：

```text
tab.deep_tutor
settings.general.home_quick_start_target.deep_tutor_chat
settings.general.home_quick_start_target.footer（需改为仅描述 Chat）
ai_settings.row.ai_tools.subtitle（需改为仅描述 Chat）
ai_settings.ai_tools.intro（需改为仅描述 Chat）
ai_settings.ai_tools.section.deeptutor
ai_settings.ai_tools.section.deeptutor.subtitle
ai_settings.ai_tools.summary.deeptutor.*
ai_settings.ai_tools.summary.deeptutor_web_search
ai_settings.ai_tools.summary.deeptutor_paper_search
ai_settings.ai_tools.summary.planned_deeptutor
```

### 5.2 用户默认值与本地会话数据

模块目前包含 `DeepTutorLocalChatStore`、`DeepTutorLocalChatRepository`、`DeepTutorMessageCodec`、`DeepTutorUserToolSettingsStore` 与 `DeepTutorDebugFlags`。实施前必须通过其代码确认真实存储介质、key、数据库/文件名和账号隔离方式，再执行以下策略：

```text
1. 删除代码前导出“待清理 key / 表 / 文件”清单，不能凭类型名猜测。
2. 首次升级启动时仅清理属于 DeepTutor 的本地数据；不得删除 Chat、AI 设置或成员医疗数据。
3. 旧的 `HomeQuickStartConversationTarget.deepTutorChat` 值回退为 `chat`。
4. 旧 `AISettingsSnapshot` 内的 `deepTutorConversationAppearance` 必须可被忽略/迁移，不能使 Codable 解码失败。
5. 清理完成后移除一次性迁移代码与日志，避免长期保留 DeepTutor 标识。
```

### 5.3 日志与可观测性

需清除 `DEEP_TUTOR_CHAT` module、`deeptutor.debug.*` 以及 `deeptutor.weather.*` 日志命名。若 ToolHub/天气仍服务普通 Chat，应改用该能力真实所属的日志 module，并保持现有脱敏要求；不得只改字符串而保留无入口的 DeepTutor 分支。

### 5.4 AI 设置：配置模型、持久化与界面必须一体去除

DeepTutorChat 的设置不是单一页面开关，而是三层配置链：`AISettingsSnapshot` 负责账号级快照序列化，`AISettingsDomainModels` 定义外观枚举/结构体，`AISettingsView` 与 `AIToolSettingsView` 展示和消费这些配置。实施必须整条链路删除，不能只隐藏 UI。

| 层级 | 当前文件与配置 | 必须改造内容 | 升级兼容要求 |
| --- | --- | --- | --- |
| 配置域模型 | `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift`：`DeepTutorConversationCardStyle`、`DeepTutorToolTraceDisplayMode`、`DeepTutorConversationAppearancePreferences` | 删除三个类型、默认值及所有仅服务 DeepTutor 卡片样式、工具 trace 展开方式、流式期间折叠的选项。 | 不将这些枚举改名后继续留在 AI Settings；它们属于被下线模块。 |
| 快照内存模型 | `SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift`：`deepTutorConversationAppearance` | 删除顶层字段、构造函数参数、默认快照、`Preferences` 中的同名字段以及 snapshot/preferences 双向映射。 | 新版本内存模型不再暴露该属性。 |
| 快照编码 | 同一 `AISettingsSnapshot.swift` 的自定义 `Codable` | 删除写入 `deepTutorConversationAppearance` 的 `encode`；删除新模型对该字段的读取/传递。 | 历史 JSON 中含 `deepTutorConversationAppearance` 时必须能被解码器忽略；不允许因未知字段使读取失败。首次成功保存新快照后，该字段自然不再写回。 |
| DEBUG 设置页面 | `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` | 删除 `#if DEBUG` 内的 `Section("DeepTutorChat 对话外观")` 和 `DeepTutorConversationAppearanceSettingsSection`。 | Chat 的 `ChatConversationUIArchitectureSettingsSection`、`ChatConversationAppearanceSettingsSection`、`ChatComposerStartupSettingsSection` 不在删除范围，必须保持。 |
| AI 工具总览文案 | `AISettingsView.swift` 与两套 `Localizable.strings` | 将“DeepTutorChat 与 Chat 可调用工具”收口为“Chat 可调用工具”；删除 DeepTutor 工具介绍和标题。 | 中英文必须同步，禁止一个语言包留下不可达 key。 |
| 工具列表入口 | `SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIToolSettingsView.swift` | 删除 `NavigationLink` 中的 DeepTutorChat 列表、`graduationcap.fill` 行、数量计算及其 DeepTutor 专属 subtitle。 | 页面只保留 Chat ToolHub 工具列表与当前状态，不改变 Chat 工具可用性。 |
| 工具 catalog | 同一 `AIToolSettingsView.swift` 的 `AIToolCatalog` | 删除 `deepTutorTools()`、`nativeDeepTutorTools()`、`deepTutorCompatibilityTools()`、`deepTutorNative(...)`、`deepTutorCompatibility(...)`，以及 `tool(named:)` 中 `chatTools() + deepTutorTools()` 的合并。 | `tool(named:)` 仅解析 Chat catalog；不保留 `deeptutor.<name>` item ID 作为隐藏兼容项。 |
| 工具来源与命名 | 同一文件中 `AIToolSettingsItem` 的 `.deepTutorChat` source、`deeptutor.<name>` ID 及 DeepTutor-main compatible 标记 | 删除只为该 source 存在的枚举 case、显示 badge、筛选/统计分支和兼容名配置；如果 source 枚举被其他文件使用，逐调用点清理后再删。 | 不得把 DeepTutor-main 兼容名伪装成普通 Chat 工具；确有 Chat 所需的工具应以 Chat 的真实 schema/名称重新登记。 |

必须特别复核 `AIToolCatalog.tool(named:)`：它目前会从 `chatTools() + deepTutorTools()` 中按标准化名称查找工具。下线后工具查找、工具标题展示、工具详情页和任何调用此函数的页面都要只使用 Chat catalog，避免页面虽然没有 DeepTutor 分区、但仍可解析残留工具名。

### 5.5 启动、依赖装配、Tab 容器与账号生命周期必须移除

DeepTutorChat 在应用冷启动时即被构造，并非进入 Tab 后才延迟创建。`AppContainer` 构造 `DeepTutorChatViewModel` 时注入 `DeepTutorLocalChatStore`、Core Data、会话快照、`ChatOrchestrator`、AI Runtime、AI 设置中心、记忆读写、成员上下文、医疗查询 API、文件传输和 Logger。因此必须从组合根开始删除，不能只删视图入口。

| 启动/生命周期阶段 | 当前调用链 | 文件 | 实施要求 |
| --- | --- | --- | --- |
| 应用容器初始化 | `AppContainer.init` → `DeepTutorLocalChatStore(coreDataStack, snapshotStore, logger)` → `DeepTutorChatViewModel(...)` | `SparkClient/Projects/App/Sources/App/AppContainer.swift` | 删除 `deepTutorChatViewModel` 属性和完整构造块；同时删掉仅为这个构造传入的 repository、AI Runtime、记忆、成员、医疗 API、文件传输参数传递。不得删掉仍被 Chat/其他 Feature 使用的共享服务实例。 |
| 运行时注册 | `AppContainer.accountSessionRuntime` 构造时注入 VM | `AppContainer.swift`、`Architecture/AccountSessionRuntime.swift` | 删除 `AccountSessionRuntime` 的私有 VM 字段、初始化参数、赋值，以及 `activateUser`/`activateGuest` 两处 `resetForSessionSwitch()`。 |
| 主 Tab 依赖包 | `AppContainer.makeMainTabDependencies` → `MainTabDependencies` | `AppContainer.swift`、`Architecture/FeatureAssemblies.swift` | 从依赖结构体、缓存创建逻辑、所有 call site 中删除该字段；确保构造参数顺序/标签同步更新。 |
| 主界面组合 | `SignedInMainTabHostView` → `MainTabCoordinatorView` → `IOS26TabBarView` | `SignedInMainTabHostView.swift`、`MainTabCoordinatorView.swift`、`IOS26TabBarView.swift` | 删除 `@ObservedObject`、init 参数、属性赋值和所有向 Home/Chat 页面透传。Preview 与 live 容器均须可构造。 |
| Tab 与导航容器 | `IOS26TabBarView.deepTutorContainer` → `CompatibleRouteNavigationContainer(path: routePath(.deepTutor))` → `DeepTutorConversationListPage` | `IOS26TabBarView.swift` | 删除整个 `deepTutorContainer`；删除已注释 Tab、注释说明和 `routePath(.deepTutor)` 残留。注释代码同属源码残留，不得保留。 |
| 路由图 | `AppRouteStore.RouteDestination` 与 `RootTab` → `MainTabRouteDestinationBuilder.destination` | `AppRouteStore.swift`、`MainTabRouteDestinationBuilder.swift` | 删除 list/thread 路由、RootTab `.deepTutor`、selectedTab switch、root destination switch 和目标页面分支。对升级前恢复的 DeepTutor route 制定安全降级：回到 `.chatList` 或 `.home`，不得 force unwrap/崩溃。 |
| 首页启动后的依赖传递 | `IOS26TabBarView`/`HealthHomeView`/`IOS26HomeView`/`IOS26HomeDashboardView`/`IOS26HomeDashboardActionHandler` | `Projects/Features/Home/Presentation/*.swift` | 从所有构造器、属性、Preview、加载状态合并与 `.onChange(of: isCreatingConversation)` 中删除 VM；首页加载态仅以普通 Chat 创建状态为准。 |
| 首页快捷入口配置 | `HomeQuickStartConversationPreferenceStore` → `HomeQuickStartConversationTarget.deepTutorChat` → `openDeepTutor(mode:)` | `Projects/Features/Home/Domain/HomeQuickStartConversationTarget.swift`、`IOS26HomeDashboardActionHandler.swift` | 删除 target case 和 DeepTutor 分支/方法；读取旧 raw value `deepTutorChat` 必须映射为 `.chat`，使制定计划和报告解读自动进入普通 Chat 的既有流程。 |

启动阶段验收必须覆盖三种容器：生产 `AppContainer.live()`、SwiftUI `AppContainer.preview`、账号登录后的 `MainTabDependencies` 缓存创建。任何一个仍要求传入 `DeepTutorChatViewModel` 都说明依赖图未清理完毕。

### 5.6 调试开关、用户默认值与 Core Data 场景数据

除 AI Settings 快照外，当前还存在以下配置/数据入口，均需在实际删除前逐项记录并在升级路径处理：

| 存储/配置项 | 当前来源 | 处理要求 |
| --- | --- | --- |
| 可选工具配置 | `DeepTutorUserToolSettingsStore`：`deeptutor.enabled_optional_tools`、`deeptutor.enabled_optional_tools_uses_default` | 在移除模块后的首次启动清除两个 key；删除 store 与所有 capability allow-list 调用。 |
| 模块 DEBUG 开关 | `DeepTutorDebugFlags`：`deeptutor.debug.useLocalSimulator`、`verboseChatRefreshLogs`、`verboseChatRenderLogs`、`verboseChatStreamLogs`、`verboseCapabilityLogs`、`verboseCapabilitySnapshots`、`verboseQuizParseLogs`、`verboseConversationListRefreshLogs` | 删除读取代码，并在首次启动清理所有列出的 key。不能保留“用于未来模块”的 DeepTutor 前缀。 |
| AI Runtime DEBUG 开关 | `AIRuntimeDebugFlags`：`deeptutor.debug.verboseAIRuntimeRequestLogs`、`deeptutor.debug.verboseAIRuntimeStreamLogs` | 先确认普通 Chat 是否仍使用这两个开关：若使用，迁移到中性/Chat key 并提供一次性值迁移；若不用，清除 key 和读取逻辑。 |
| Core Data 会话数据 | `DeepTutorLocalChatStore` 使用共享 `ChatThreadEntity`、`ChatMessageEntity`、`ChatMessageBlockEntity`，通过 `scenario == "deepTutor"` 和 `ownerAccountID` 区分 | 不删除共享 Entity/schema；只按每个账号的 `scenario == "deepTutor"` 清除对应 Thread、关联 Message 与 MessageBlock，清理顺序需遵循 Core Data 关系和级联规则。严禁按实体名全表删除。 |
| Block 类型与消息编码 | `DeepTutorMessageCodec` 的 `deepTutorEnvelope`、`deepTutorText`、`deepTutorThinking`、`deepTutorTrace`、`deepTutorAskUser`、`deepTutorCaptureCard`、`deepTutorMemberSelection`、`deepTutorMemberProfile`、`deepTutorGeneratedFile`、`deepTutorResearchOutline`、`deepTutorQuiz`、`deepTutorQuizParseError`、`deepTutorVisualization`、`deepTutorError` | 它们随 DeepTutor 私有 message block 一并停止读取与写入；数据清理前不得让通用 Chat codec 尝试解释这些类型。 |
| 通知与观察者 | `DeepTutorChatNotifications` / `.deepTutorChatDatabaseDidChange` | 删除通知名、发布点、订阅点与 Combine cancellable；检查没有残留 NotificationCenter observer。 |

一次性迁移/清理应设计为可重入：即便用户在清理后杀死 App，再启动也不会误删 Chat 数据或重复抛错。清理日志不可输出消息正文、附件、医疗资料、完整 UUID 或账号敏感信息。

## 6. 测试改造范围

### 6.1 删除专属测试（7 个）

```text
Tests/DeepTutorChat/DeepTutorChatTests.swift
Tests/DeepTutorChat/DeepTutorHealthToolExtensionTests.swift
Tests/DeepTutorChat/DeepTutorModelContextResolverTests.swift
Tests/DeepTutorChat/DeepTutorToolCompositionPolicyTests.swift
Tests/DeepTutorChat/DeepTutorToolPolicyResolverTests.swift
Tests/DeepTutorChat/DeepTutorTurnCoordinatorTests.swift
Tests/DeepTutorChat/DeepTutorWeatherToolExtensionTests.swift
```

### 6.2 必须更新/新增的回归验证

| 测试面 | 相关文件 | 验收重点 |
| --- | --- | --- |
| 首页快捷模式 | `Tests/Home/IOS26HomeDashboardTests.swift` | 当前 `DeepTutorQuickStartModeTests` 依赖待删类型；改为验证两个首页快捷动作创建普通 Chat / 小任务，且旧 preference 值回退为 Chat。 |
| 路由与 Tab | App 路由相关现有测试；若无则新增目标测试 | 不存在 `deepTutorList`、`deepTutorThread`、`.deepTutor`；Deep link/恢复旧 route 不崩溃。 |
| AI 设置存档 | AISettings 既有测试目录 | 移除 DeepTutor appearance/tool 配置后，新旧 snapshot 均能解码；AI 工具页仅展示 Chat 能力。 |
| ToolHub / Chat | ToolHub 与 Chat 既有测试目录 | 成员资料格式化和天气执行在 Chat 需要时仍可用，且不导入 DeepTutor 类型。 |
| 登录切换 | App/AccountSessionRuntime 既有测试目录 | 登录、切换账号、退出不再调用已删除 VM，且普通 Chat 状态不回归。 |

## 7. 历史文档、构建配置与搜索收口

### 7.1 历史文档

`需求文档/对话/DeepTutorChat/` 当前有 53 个 Markdown 文件，其中包括历史工单与变更说明。它们不属于应用编译输入，默认保留以维护审计链路。本次只新增本文；不得批量删除或改写历史工单。

工程的其他文档中当前至少有 62 个 Markdown 文件提到 `DeepTutorChat`/`DeepTutor Chat`。代码下线完成后，应另开文档治理任务按以下规则处理：

```text
仍描述当前产品能力的文档：改为 Chat 或删除该能力说明。
历史工单/变更记录：保留并标注“模块已于 <版本> 下线”。
无法判断文档性质的内容：人工确认后再编辑。
```

### 7.2 构建配置

本次只读扫描未发现 `Project.swift`、`Tuist.swift`、`Package.swift` 或 `.pbxproj` 中以 `DeepTutorChat` 命名的显式条目。实施前仍需确认项目是否通过目录 glob 自动纳入 `SparkClient/Projects/**` 源码；若为自动收集，删除目录后应重新生成/刷新工程并检查 Build Phases 是否存在孤儿文件引用。

## 8. 推荐实施顺序与提交拆分

```text
提交 1：路由、Tab、AppContainer、FeatureAssemblies、账号生命周期
提交 2：首页快捷入口与 preference 默认值/旧值回退
提交 3：AI Settings、工具目录、本地化、日志命名和共享格式化逻辑收口
提交 4：删除 DeepTutorChat Feature 目录与专属测试
提交 5：本地数据迁移/清理、全局残留搜索、构建与回归测试
```

每个提交必须独立编译；删除目录的提交不得携带对无关功能的重构。若共享格式化器经确认具有 Chat/ToolHub 价值，应在提交 3 迁移为中性命名和归属，之后再在提交 4 删除原实现。

## 9. 风险与实施前决策

| 风险 | 影响 | 必须决策/动作 |
| --- | --- | --- |
| 首页快捷入口原本可选 DeepTutor | 用户已保存偏好会指向不存在目标 | 明确回退普通 Chat，并验证升级后的首次动作。 |
| Chat/ToolHub 复用 DeepTutor 格式化器 | 直接删目录会编译失败 | 在删除前将真正共享的成员资料格式化逻辑迁移/重写到合适模块。 |
| AI 设置 Codable 快照含专属字段 | 升级后可能解码失败或保留死数据 | 制定兼容 decode 与一次性清理策略。 |
| 本地会话数据可能含用户健康上下文 | 粗放清理可能误删其它数据或留下敏感残留 | 先从 store 实现取得精确 key/表/文件清单，限定清理范围。 |
| 当前工作区已有未提交改动 | 误覆盖会丢失用户工作 | 实施前再次检查 diff；只在必要的 DeepTutor 行附近做最小合并。 |
| 旧路由/恢复状态 | 更新后可能因枚举值缺失崩溃 | 定义安全降级目标为 Chat 列表/首页，并增加测试。 |

## 10. 完成验收标准

```text
[ ] `SparkClient/Projects/Features/DeepTutorChat/` 与 `Tests/DeepTutorChat/` 均不存在。
[ ] 应用源码、测试源码、资源和构建配置的全局搜索不再命中 `DeepTutorChat`、`DeepTutorChatViewModel`、`DeepTutorQuickStartMode`、`deepTutorList`、`deepTutorThread`、`.deepTutor`、`DEEP_TUTOR_CHAT` 或 `deeptutor.`（历史文档目录除外）。
[ ] DeepTutor Tab、路由、会话页、首页快捷入口分流、AI 设置外观项、AI 工具分区和对应本地化文案均不可见。
[ ] 首页两个快捷动作、普通 Chat、AI 设置、ToolHub、登录/切换账号/退出流程均通过编译和回归测试。
[ ] 已安装用户升级后，旧首页偏好安全回退至 Chat；旧 AI 设置快照可读；仅 DeepTutor 私有本地数据被清理。
[ ] Xcode/工程生成后的 Build Phases 不含删除目录的孤儿文件引用。
[ ] `git diff` 只包含本工单批准范围；既有 `MainTabRouteDestinationBuilder.swift` 用户修改已保留。
[ ] 本工单以外的历史 DeepTutorChat 工单未被删除或静默改写。
```

## 11. 本工单交付限制

本文是改造范围与验收基线，不授权执行删除、迁移、配置修改、数据清理或测试改写。实际实施必须单独开始，并在实施前复核文件数量、持久化位置与当前工作区 diff。
