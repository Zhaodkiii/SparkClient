# IOS26-TABBAR-000002：正式版 iOS26TabBarView 与首页主模块需求工单

> 创建日期：2026-08-06  
> 关联模块：AppCoordinatorView、MainTabCoordinatorView、HomeView、DeepTutorChat、医疗列表、家庭药箱、家庭档案  
> 关联代码：`SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift`、`SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift`、`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`、`SparkClient/Projects/Features/Home/Presentation/HomeView.swift`、`SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift`  
> 状态：新需求/待实现  
> 优先级：P0，正式替换 iOS 26 demo 分支

## 1. 一句话目标

将当前 iOS 26 临时 demo TabView 替换为正式版 `IOS26TabBarView`：底部使用系统 Liquid Glass 悬浮 TabBar，首页首屏重设计为“家庭健康工作台”，提供制定体检计划、报告解读、用药、家庭药箱、家庭档案五个高频入口，并复用现有 typed route 与 DeepTutorChat 会话体系完成一步直达。

## 2. 背景与问题

### 2.1 当前问题

当前 `AppCoordinatorView` 的 iOS 26 分支仍是临时 demo：

```text
if #available(iOS 26.0, *) {
    TabView {
        Tab("Numbers", systemImage: "number") { ... }
        Tab("Alerts", systemImage: "bell") { ... }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
} else {
    MainTabCoordinatorView(...)
}
```

这个分支存在五个问题：

1. 它绕过正式 `MainTabCoordinatorView`，导致首页、聊天、DeepTutor、科普、设置等业务入口不可用。
2. 它没有复用 `AppRouteStore`，深链、推送、冷启动 intent 和首页医疗路由无法统一消费。
3. 它没有真实首页，只能验证 TabBar 外观，不能进入实际业务流程。
4. 它没有处理 `launchIntentCoordinator.updateReadiness`，可能导致冷启动目标页面队列卡住。
5. 它会让后续工程误以为 iOS 26 分支可以长期保留 demo 代码，增加上线风险。

### 2.2 本工单要解决什么

本工单要把 iOS 26 分支从“验证系统控件”升级为“正式主导航”：

```text
AppCoordinatorView
  -> iOS 26.0 及以上：IOS26TabBarView（正式版）
  -> iOS 25 及以下：MainTabCoordinatorView（现有兼容版）
```

`IOS26TabBarView` 不是 demo，不出现 `Numbers`、`Alerts` 这类临时 Tab。它必须承载正式业务 Tab、路由容器、首页工作台和系统 Liquid Glass 行为。

## 3. 产品目标

### 3.1 用户目标

用户打开 App 后，应在首页第一眼理解当前产品能帮自己做什么：

1. 管理家庭成员健康档案。
2. 快速进入体检计划制定。
3. 上传或选择报告进行 AI 解读。
4. 管理用药计划和服药记录。
5. 管理家庭药箱。

### 3.2 业务目标

1. 提升首页高价值功能的点击率。
2. 将 AI 能力前置，让体检计划和报告解读形成 DeepTutorChat 的核心入口。
3. 保留原有医疗数据、成员、用药、家庭药箱链路，减少重复开发。
4. 用 iOS 26 系统 TabBar 获得 Liquid Glass、滚动最小化、搜索 Tab 等系统能力。

### 3.3 成功指标

| 指标 | 目标 |
| --- | --- |
| 首页五个核心入口可见性 | 首屏或首屏下方一屏内完整可见 |
| 体检计划入口成功率 | 点击后 1 步创建 DeepTutorChat 新会话并进入会话页 |
| 报告解读入口成功率 | 点击后 1 步创建 DeepTutorChat 新会话并进入会话页 |
| 用药入口成功率 | 点击后进入 `MedicationExecutionCenterPage` |
| 家庭药箱入口成功率 | 点击后进入 `FamilyMedicineCabinetPage` |
| 家庭档案入口成功率 | 点击后进入现有 Home 容器承载的家庭/成员档案页面 |
| iOS 25 回归风险 | iOS 25 及以下仍走现有 `MainTabCoordinatorView`，行为不变 |

## 4. 非目标

1. 本期不完整实现“体检制定模式”的 AI 工作流，只预留模式参数和入口标题。
2. 本期不完整实现“报告解读模式”的 AI 工作流，只预留模式参数和入口标题。
3. 本期不重构 DeepTutorChat 底层消息协议。
4. 本期不新增服务端接口。
5. 本期不自定义 TabBar 背景、不隐藏系统选中胶囊、不复刻私有视觉参数。
6. 本期不删除 iOS 25 兼容主导航。

## 5. 正式版信息架构

### 5.1 iOS 26 主 Tab

正式版 `IOS26TabBarView` 底部只保留三项：`首页`、`DeepTutor`、`搜索`。使用 iOS 26 SwiftUI `Tab` API 实现，不再展示 `对话`、`科普`、`设置` 作为底部 Tab。

```text
IOS26TabBarView
├── 首页        Home
├── DeepTutor   DeepTutor
└── 搜索        Search
```

如果未来要恢复 `对话`、`科普`、`设置` 为底部 Tab，应作为另一个工单处理。本工单重点是取消 demo、落地正式首页，并将底部导航收束为更克制的三项。

### 5.2 首页五个主入口

```text
首页主模块
├── 制定体检计划
│   └── 创建 DeepTutorChat 新会话 -> 进入会话页 -> 设置为体检制定模式（后期实现）
├── 报告解读
│   └── 创建 DeepTutorChat 新会话 -> 进入会话页 -> 设置为报告解读模式（后期实现）
├── 用药模块
│   └── routeStore.route(to: .homeMedicalList(.medicationPlans, nil))
├── 家庭药箱
│   └── routeStore.route(to: .homeFamilyMedicineCabinet(memberID: selectedMemberID))
└── 家庭档案
    └── 进入 HomeView 所在 home route 容器，打开成员详情/家庭档案承载页
```

## 6. UI 设计方向

### 6.1 关键词

```text
简约
大气
高可信
家庭健康管理
AI 辅助但不喧宾夺主
iOS 26 Liquid Glass 原生感
```

### 6.2 视觉原则

1. 首页不是营销页，是家庭健康工作台。
2. 首屏要有清楚主行动，不要堆满小卡。
3. 医疗健康界面要稳重、可信、留白足够。
4. 重点入口用大尺寸模块，辅助入口用紧凑模块。
5. 使用系统字体、动态字体、系统材质，不使用过度渐变和装饰图案。
6. 卡片圆角控制在 iOS 原生舒适范围，避免所有元素都变成大圆角泡泡。
7. 内容滚动到 TabBar 下方时由系统 Liquid Glass 和 scroll edge effect 处理，不额外加硬阴影遮罩。

### 6.3 色彩与层级

| 层级 | 用法 | 建议 |
| --- | --- | --- |
| 页面背景 | 首页整体背景 | `Color(uiColor: .systemGroupedBackground)` 或系统背景 |
| 主模块 | 体检计划、报告解读 | `.regularMaterial` + 轻描边，保留玻璃层次 |
| 次模块 | 用药、家庭药箱、家庭档案 | 系统 secondary 背景，轻描边 |
| 强调色 | AI/计划/报告主行动 | 使用 `.tint` 或品牌蓝绿，但只用于操作状态 |
| 文字 | 医疗信息 | 主标题 `.primary`，解释 `.secondary` |

### 6.4 动效原则

1. 点击模块立即给出触觉反馈。
2. 新建 DeepTutor 会话期间模块显示局部 loading，不阻塞整个首页。
3. 页面跳转走系统 NavigationStack 动画。
4. 不在首页主模块添加夸张弹跳；默认使用系统过渡。
5. 遵守 Reduce Motion：关闭自定义位移动画，仅保留透明度和系统导航。

### 6.5 视觉层次与排版

1. 首页采用“三段式层次”：顶部信息区、主行动区、辅助行动区。
2. 标题层级固定为三档，不要再细分成 5-6 档。
3. 顶部主标题只出现一次，建议使用“家庭健康工作台”，不要把标题拆成多行口号。
4. 当前成员区域是次标题级，不应比主标题更抢眼。
5. 主行动卡片的标题字重应明显高于说明文字，形成“看标题就能决定点不点”的结构。
6. 辅助模块标题保持简洁，避免长句堆叠。
7. 说明文字控制在两行内，超过两行必须改写成更短的句子。
8. 不使用全大写标题，不使用过密的字距，不使用夸张的拉伸字体。
9. 主页内容采用左对齐，不使用居中堆叠作为默认主布局。
10. 卡片内文字遵循“标题、说明、行动”三行节奏，最多再加一行状态。

### 6.6 字号与行距

| 组件 | 建议字号 | 建议行距 | 用法 |
| --- | --- | --- | --- |
| 页面主标题 | `28-32pt` | `1.05-1.15` | “家庭健康工作台” |
| 区块标题 | `18-22pt` | `1.15-1.25` | “当前成员”“体检计划” |
| 模块标题 | `17-19pt` | `1.15-1.25` | 按钮卡主文案 |
| 模块说明 | `13-15pt` | `1.25-1.4` | 解释用途、状态、提醒 |
| 辅助标签 | `12-13pt` | `1.1-1.2` | 数量、更新时间、弱提示 |

1. 主标题使用粗体，但不要过粗。
2. 模块说明使用次级字重，保证医疗场景的克制感。
3. 数值和时间信息要小于模块标题，以免抢主次。
4. 大字号变化只允许在系统动态字体上扩大，不允许按视口宽度缩放。
5. 长中文词组必须优先换行，不要为了塞进卡片而缩小到不可读。

### 6.7 色彩与光影

1. 页面背景使用系统背景色，不要用单一纯白把层次抹平。
2. 主行动卡片使用轻薄 material，像浮在页面上，而不是像实体按钮。
3. 色彩强调只服务行动，不服务装饰。
4. 医疗信息区颜色要稳定、低噪音，避免高饱和红蓝同时大量出现。
5. 深色模式下仍要保留卡片边界，不能只靠阴影分层。
6. 光影只承担“层级提示”，不承担“装饰表演”。
7. 阴影尽量轻，半透明材质优先，边框优先于浓重投影。
8. 主卡可使用微弱冷色高光，辅助卡尽量中性化。
9. 错误、警告、成功状态只在局部区域着色，不要污染整屏。
10. 所有颜色都要能在小屏和大字体下保持足够对比度。

### 6.8 空间与留白

1. 卡片与卡片之间保持稳定间距，不能紧贴成一坨。
2. 首页顶部留白略多，给系统导航栏和状态区呼吸空间。
3. 主行动卡之间的间距应大于卡内段落间距，让用户自然分组。
4. 辅助入口网格间距收紧，但不要挤到误触。
5. 模块内部左右内边距要统一，避免左右边距不一致造成廉价感。
6. 底部 TabBar 上方预留足够安全距离，不让最后一块内容贴着胶囊悬停。
7. 页面纵向节奏以“空白分组”而不是“线条分组”为主。
8. 不要用重边框把所有模块切成表格感。
9. 当内容变少时，留白要跟着增加，不能强行压缩版式。
10. 当内容变多时，优先增加纵向滚动，不压缩字号与行距。

### 6.9 交互与状态反馈

1. 正常态：卡片稳定，只有轻微层次，不要像悬浮按钮一样过度抖动。
2. 按下态：立即出现轻微压暗或缩放，配合触觉反馈。
3. 聚焦态：只高亮当前可交互区域，不要让整屏一起变亮。
4. 选中成员：成员 chip 高亮，但主模块不跟着全屏变色。
5. 进行中：DeepTutor 建会话时，目标卡片显示局部 loading，其他模块保持可点。
6. 禁用态：入口置灰时仍保留结构位置，避免布局跳动。
7. 导航态：跳转后返回首页，原入口状态尽量保持，不要重置用户刚刚切过的成员。
8. 触发失败：在原地给出可理解反馈，不能静默无响应。
9. 长任务：用进度或状态文案，而不是无期限转圈。
10. 低优先级状态提示优先使用细文案，不要靠红色大片占位。

### 6.10 边界与异常状态

1. 无成员：首页主模块整体可见，但体检计划、报告解读、家庭药箱、家庭档案根据依赖关系做轻量禁用或引导。
2. 无报告：报告解读仍可进入会话，但应先展示“先选择/上传报告”的引导语。
3. 无药箱数据：用药和家庭药箱均应进入空状态页，不要留白后空荡返回。
4. 无网络：首页工作台仍可打开本地页面，远端刷新状态单独提示，不阻塞导航。
5. DeepTutor 创建失败：返回首页不跳崩，保留错误信息和重试动作。
6. 成员切换中：避免用户连续点击多个主入口导致重复建会话。
7. 视觉内容过长：用省略号和换行处理，不让按钮高度失控。
8. 大字体：卡片纵向变高，优先让页面滚动，不压扁内容。
9. 深色模式：维持层次感，避免所有模块都变成黑块。
10. 访问失败：给出“暂时无法加载，请稍后重试”的简短文案，并保留回退入口。

### 6.11 微交互与动效

1. 首页首次出现时，主标题和主模块按层级轻微依次显现，不要同一时刻全冒出来。
2. 成员切换只做非常短的过渡，不做大幅滑动。
3. 主入口按下时可以有 80-120ms 的轻微缩放，释放后立即恢复。
4. 进入 DeepTutor 时，Tab 切换和页面 push 之间不要再叠加额外中转动画。
5. 卡片内状态变化以透明度过渡为主，避免位移过多。
6. loading 结束后内容直接就位，不做多余弹跳。
7. scroll edge effect 要自然衔接底部 TabBar，不要再叠一个自定义模糊条。
8. 用户返回首页时，允许主标题和首屏模块做一次很轻的回弹感，但不能夸张。
9. 若系统开启 Reduce Motion，则所有位移动画切换为淡入淡出。
10. 若用户连续快速切换入口，动效要可中断，不应排队播放。

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
│  │  制定体检计划                 │  │
│  │  根据年龄、既往记录和家族风险  │  │
│  │  生成下一次体检建议            │  │
│  │                         开始  │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  报告解读                     │  │
│  │  进入 AI 会话，整理检查结论     │  │
│  │                         解读  │  │
│  └──────────────────────────────┘  │
│                                    │
│  ┌──────────────┐ ┌──────────────┐ │
│  │  用药         │ │  家庭药箱      │ │
│  │  计划与记录    │ │  库存与效期     │ │
│  └──────────────┘ └──────────────┘ │
│                                    │
│  ┌──────────────────────────────┐  │
│  │  家庭档案                     │  │
│  │  成员资料、病史、报告与模块维护  │  │
│  └──────────────────────────────┘  │
│                                    │
│        内容继续滚动到底部 TabBar 下方 │
├────────────────────────────────────┤
│      首页        DeepTutor        搜索 │
└────────────────────────────────────┘
```

### 7.2 首页信息层级

```text
一级：家庭健康工作台
二级：当前成员
一级行动：制定体检计划、报告解读
二级行动：用药、家庭药箱、家庭档案
三级信息：最近更新、数量、提醒状态、空状态提示
```

### 7.3 空状态

无成员时：

```text
┌────────────────────────────────────┐
│  家庭健康工作台                     │
│  先创建一个家庭成员，开始管理健康资料 │
│                                    │
│  [ 创建成员 ]                       │
│                                    │
│  制定体检计划 / 报告解读 / 用药等入口 │
│  置灰，并提示“创建成员后可用”         │
└────────────────────────────────────┘
```

无医疗数据时：

```text
┌────────────────────────────────────┐
│  报告解读                           │
│  还没有报告，也可以先进入 AI 会话了解  │
│  如何上传和整理报告                  │
│                              进入   │
└────────────────────────────────────┘
```

无药箱数据时：

```text
┌──────────────┐
│  家庭药箱      │
│  还没有药品     │
│  添加常备药     │
└──────────────┘
```

## 8. UI 模型

### 8.1 首页主模块模型

新增只服务 UI 的轻量模型，不直接绑定后端字段：

```swift
struct IOS26HomeActionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case checkupPlan
        case reportInterpretation
        case medication
        case familyMedicineCabinet
        case familyArchive
    }

    let id: Kind
    let title: String
    let subtitle: String
    let symbolName: String
    let prominence: Prominence
    let isEnabled: Bool
    let badgeText: String?

    enum Prominence {
        case primary
        case secondary
        case compact
    }
}
```

### 8.2 DeepTutor 快捷入口模式模型

本期先预留模式，不要求 AI 运行时真正改变行为：

```swift
enum DeepTutorQuickStartMode: String, Sendable {
    case checkupPlan = "checkup_plan"
    case reportInterpretation = "report_interpretation"

    var title: String {
        switch self {
        case .checkupPlan:
            return "制定体检计划"
        case .reportInterpretation:
            return "报告解读"
        }
    }

    var initialDraft: String {
        switch self {
        case .checkupPlan:
            return "我想为当前家庭成员制定下一次体检计划。请先根据已有健康档案询问必要信息。"
        case .reportInterpretation:
            return "我想解读一份检查报告。请引导我上传或选择报告，并帮我整理重点结论。"
        }
    }
}
```

说明：

1. 本期可以只创建标题为 `制定体检计划` 或 `报告解读` 的会话。
2. `initialDraft` 可先写入草稿，不自动发送。
3. 后期实现模式时，再让 `DeepTutorPromptBuilder`、`DeepTutorToolCompositionPolicy`、`DeepTutorRuntimeRequestBuilder` 读取该 mode。

## 9. 业务流程

### 9.1 App 进入正式 iOS 26 主导航

```text
AppCoordinatorView
  -> sessionContent.signedIn
  -> account prepared
  -> onboarding 不阻塞
  -> mainTab = facades.mainTab.makeDependencies(session.accountID)
  -> if #available(iOS 26.0, *)
       IOS26TabBarView(session:..., routeStore:..., dependencies:...)
     else
       MainTabCoordinatorView(...)
  -> onAppear 更新 launchIntent readiness
```

关键要求：

1. iOS 26 分支不得再出现 `Numbers`、`Alerts` demo。
2. iOS 26 分支必须和现有 `MainTabCoordinatorView` 一样更新 readiness：

```text
isSignedIn = true
accountID = session.accountID
isAccountPrepared = true
isOnboardingBlocking = false
mainTabReady = true
```

### 9.2 点击“制定体检计划”

```text
用户点击 制定体检计划
  -> 首页触发 haptic
  -> 调用 DeepTutorChatViewModel.createQuickStartConversation(mode: .checkupPlan)
  -> 创建本地 DeepTutorConversation
  -> 标题为“制定体检计划”
  -> 可选：写入 draftText 为体检计划引导语
  -> routeStore.route(to: .deepTutorThread(conversation.id), replaceStack: false)
  -> IOS26TabBarView 自动切到 DeepTutor Tab
  -> DeepTutorChatPage 打开该 conversation
```

本期效果：

1. 一步创建新会话。
2. 一步进入会话页面。
3. 页面标题显示“制定体检计划”。
4. 输入区可预填体检计划引导语，等待用户确认发送。

后期效果：

1. 进入“体检制定模式”。
2. AI 自动读取当前成员画像、年龄、既往体检、病史、家族史。
3. AI 通过 AskUser 卡片补齐缺失信息。
4. 输出体检计划草案。

### 9.3 点击“报告解读”

```text
用户点击 报告解读
  -> 首页触发 haptic
  -> 调用 DeepTutorChatViewModel.createQuickStartConversation(mode: .reportInterpretation)
  -> 创建本地 DeepTutorConversation
  -> 标题为“报告解读”
  -> 可选：写入 draftText 为报告解读引导语
  -> routeStore.route(to: .deepTutorThread(conversation.id))
  -> 进入 DeepTutorChatPage
```

本期效果：

1. 一步创建新会话。
2. 一步进入会话页面。
3. 页面标题显示“报告解读”。
4. 输入区可预填“请上传或选择报告”的引导语。

后期效果：

1. 进入“报告解读模式”。
2. 支持选择已有检查报告或上传新报告。
3. AI 输出报告重点、异常项、建议追问和就医提醒。

### 9.4 点击“用药模块”

```text
用户点击 用药
  -> viewModel.logMedicalListNavigation(kind: .medicationPlans)
  -> routeStore.route(to: .homeMedicalList(.medicationPlans, nil))
  -> 当前 Home Tab 的 CompatibleRouteNavigationContainer push
  -> MainTabCoordinatorView / IOS26TabBarView routeDestination
  -> HomeMedicalRouteSupport.medicalListView(route: .medicationPlans)
  -> MedicationExecutionCenterPage
```

复用现有代码：

```swift
dependencies.routeStore.route(to: .homeMedicalList(.medicationPlans, nil))
```

### 9.5 点击“家庭药箱”

```text
用户点击 家庭药箱
  -> guard selectedMemberID != nil
  -> routeStore.route(to: .homeFamilyMedicineCabinet(memberID: selectedMemberID))
  -> routeDestination
  -> HomeMedicalRouteSupport.familyMedicineCabinetView(...)
  -> FamilyMedicineCabinetPage
```

复用现有代码：

```swift
if let memberID = viewModel.selectedMemberID {
    dependencies.routeStore.route(to: .homeFamilyMedicineCabinet(memberID: memberID))
}
```

无选中成员时：

```text
展示 toast / notification：“请先选择或创建家庭成员”
```

### 9.6 点击“家庭档案”

家庭档案必须进入现有 Home 容器承载的成员/家庭档案页面，保持与当前 `HomeView` 成员选择、成员详情、模块维护一致。

目标容器：

```swift
CompatibleRouteNavigationContainer(path: routePath(.home)) {
    HomeView(
        dependencies: homeDependencies,
        viewModel: homeViewModel,
        medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
        externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
        launchIntentCoordinator: launchIntentCoordinator,
        session: session
    )
} destination: { route in
    routeDestination(route)
}
```

本期推荐落地方式：

1. 如果当前已有选中成员，打开 `HomeFullScreenCover.memberDetail(memberID:)`。
2. 如果没有成员，打开 `HomeSheet.addMember(.create())`。
3. 如需跨视图从 `IOS26HomeDashboardView` 控制 HomeView 内部 sheet/cover，优先新增 `HomeViewModel` 方法，不让外层直接操作私有 `@State`。

建议新增：

```swift
extension HomeViewModel {
    func openFamilyArchiveEntry() {
        if let memberID = selectedMemberID {
            pendingHomeAction = .openMemberDetail(memberID)
        } else {
            activeSheet = .addMember(.create())
        }
    }
}
```

如果当前架构不适合新增 `pendingHomeAction`，则本期可把家庭档案入口放在 `HomeView` 内部实现，直接设置 `activeFullScreenCover = .memberDetail(memberID:)`。

## 10. 关键技术方案

### 10.1 新增正式 iOS 26 主导航文件

新增文件：

```text
SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift
```

职责：

1. 使用 iOS 26 SwiftUI `Tab` API。
2. 复用现有 `CompatibleRouteNavigationContainer`。
3. 复用 `AppRouteStore`。
4. 复用 `routeDestination(_:)` 逻辑，避免和 `MainTabCoordinatorView` 分叉。
5. 设置 `.tabBarMinimizeBehavior(.onScrollDown)`。
6. 更新 `launchIntentCoordinator.mainTabReady`。

### 10.2 拆出公共 route destination

当前 `MainTabCoordinatorView.routeDestination(_:)` 是私有方法。为了避免 iOS 26 和 iOS 25 两套主导航复制同一批 route destination，建议拆出公共 builder：

```text
SparkClient/Projects/App/Sources/App/MainTabRouteDestinationBuilder.swift
```

示例：

```swift
@MainActor
struct MainTabRouteDestinationBuilder {
    let session: UserSession
    let homeDependencies: HomeFeatureDependencies
    let popularScienceDependencies: PopularScienceFeatureDependencies
    let homeViewModel: HomeViewModel
    let medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let chatStateStore: ChatStateStore
    let chatListViewModel: ChatListViewModel
    let chatDetailViewModel: ChatDetailViewModel
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let accountManagementViewModel: AccountManagementViewModel
    let aiSettingsViewModel: AISettingsViewModel

    @ViewBuilder
    func destination(_ route: AppRoute) -> some View {
        switch route {
        case .chatThread(let threadID):
            ChatView(...)
        case .deepTutorThread(let conversationID):
            DeepTutorChatPage(conversationID: conversationID, viewModel: deepTutorChatViewModel)
        case .aiSettings:
            AISettingsView(viewModel: aiSettingsViewModel)
        case .accountManagement:
            AccountManagementView(viewModel: accountManagementViewModel, session: session)
        case .homeMedicalList(let listRoute, let medicationFocus):
            HomeMedicalRouteSupport.medicalListView(...)
        case .homeFamilyMedicineCabinet(let memberID):
            HomeMedicalRouteSupport.familyMedicineCabinetView(...)
        case .popularScienceArticle(let articleID):
            PopularScienceArticleDetailView(...)
        case .home, .knowledge, .chatList, .popularScience, .settings, .deepTutorList:
            EmptyView()
        }
    }
}
```

迁移要求：

1. `MainTabCoordinatorView` 改为调用 `destinationBuilder.destination(route)`。
2. `IOS26TabBarView` 也调用同一个 builder。
3. 不复制粘贴 route switch。

### 10.3 新增正式首页工作台

新增文件：

```text
SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift
```

职责：

1. 承载 iOS 26 首页重设计。
2. 复用 `HomeViewModel`、`HomeFeatureDependencies`、`UserSession`。
3. 保留 `HomeView` 的生命周期消费能力，或在 `HomeView` 内根据 iOS 26 切换新的内容 body。

推荐方式：

```text
HomeView
  -> 保留 sheet/fullScreenCover/launchIntent/lifecycle
  -> homeScrollBody 内根据系统版本选择内容
       iOS 26: IOS26HomeDashboardView(...)
       旧系统: 现有 medicalInfoSection + nutritionInfoSection
```

不要绕过 `HomeView`，因为 `HomeView` 现在承担：

1. Launch Intent 消费。
2. 外部 PDF 导入。
3. 上传成功刷新。
4. 成员邀请和分享票消费。
5. Sheet / fullScreenCover 管理。

### 10.4 DeepTutor 快捷建会话

当前 `DeepTutorChatViewModel` 已有：

```swift
func createAndOpenConversation(source: String = "toolbar") async
```

但该方法只更新 `selectedConversationID`，主要服务 `DeepTutorConversationListPage.navigationDestination(item:)`。首页快捷入口需要拿到 conversation id 并切换 Tab，因此建议新增：

```swift
@discardableResult
func createQuickStartConversation(
    mode: DeepTutorQuickStartMode,
    source: String
) async -> UUID? {
    isCreatingConversation = true
    conversationCreationError = nil
    defer { isCreatingConversation = false }

    do {
        let created = try await createConversation(title: mode.title, refreshList: false)
        optimisticallyInsertConversation(created)
        selectedConversationID = created.id

        var next = state
        next.draftText = mode.initialDraft
        next.activeCapability = .chat
        state = next

        await refreshConversations(source: source, expectedCreatedID: created.id)
        await openConversation(created.id)
        return created.id
    } catch {
        conversationCreationError = error.localizedDescription
        return nil
    }
}
```

注意：

1. 这段示例说明设计，不要求逐字照抄。
2. 如果 `openConversation` 会从 `DeepTutorDraftStore` 覆盖 `state.draftText`，则应新增 `DeepTutorDraftStore.saveDraft(mode.initialDraft, for: created.id)`，再 `openConversation`。
3. 不要让首页直接调用 `DeepTutorLocalChatRepository`。
4. 不要在首页直接写 Core Data。

### 10.5 首页点击动作协调器

为了避免 `IOS26HomeDashboardView` 里塞满路由和异步细节，建议新增轻量 coordinator：

```text
SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardActionHandler.swift
```

示例：

```swift
@MainActor
struct IOS26HomeDashboardActionHandler {
    let routeStore: AppRouteStore
    let homeViewModel: HomeViewModel
    let deepTutorChatViewModel: DeepTutorChatViewModel
    let notificationClient: any NotificationClient

    func handle(_ action: IOS26HomeActionItem.Kind) {
        switch action {
        case .checkupPlan:
            Task { await openDeepTutor(mode: .checkupPlan) }
        case .reportInterpretation:
            Task { await openDeepTutor(mode: .reportInterpretation) }
        case .medication:
            homeViewModel.logMedicalListNavigation(kind: .medicationPlans)
            routeStore.route(to: .homeMedicalList(.medicationPlans, nil))
        case .familyMedicineCabinet:
            guard let memberID = homeViewModel.selectedMemberID else {
                notificationClient.show("请先选择或创建家庭成员", title: "家庭药箱", source: "ios26_home")
                return
            }
            routeStore.route(to: .homeFamilyMedicineCabinet(memberID: memberID))
        case .familyArchive:
            homeViewModel.openFamilyArchiveEntry()
        }
    }

    private func openDeepTutor(mode: DeepTutorQuickStartMode) async {
        guard let conversationID = await deepTutorChatViewModel.createQuickStartConversation(
            mode: mode,
            source: "ios26_home_\(mode.rawValue)"
        ) else { return }
        routeStore.route(to: .deepTutorThread(conversationID))
    }
}
```

## 11. 关键代码示例

### 11.1 AppCoordinatorView 替换 demo 分支

```swift
if #available(iOS 26.0, *) {
    IOS26TabBarView(
        session: session,
        routeStore: mainTab.routeStore,
        homeDependencies: mainTab.homeDependencies,
        knowledgeDependencies: mainTab.knowledgeDependencies,
        popularScienceDependencies: mainTab.popularScienceDependencies,
        taskManager: mainTab.taskManager,
        homeViewModel: mainTab.homeViewModel,
        medicalDocumentUploadViewModel: mainTab.medicalDocumentUploadViewModel,
        knowledgeViewModel: mainTab.knowledgeViewModel,
        popularScienceViewModel: mainTab.popularScienceViewModel,
        chatStateStore: mainTab.chatStateStore,
        chatListViewModel: mainTab.chatListViewModel,
        chatDetailViewModel: mainTab.chatDetailViewModel,
        deepTutorChatViewModel: mainTab.deepTutorChatViewModel,
        settingsViewModel: mainTab.settingsViewModel,
        accountManagementViewModel: mainTab.accountManagementViewModel,
        aiSettingsViewModel: mainTab.aiSettingsViewModel,
        versionUpdateCoordinator: mainTab.versionUpdateCoordinator,
        upgradeLoginViewModel: mainTab.upgradeLoginViewModel,
        pushAdapter: mainTab.pushAdapter,
        externalMedicalDocumentImportCoordinator: mainTab.externalMedicalDocumentImportCoordinator,
        launchIntentCoordinator: mainTab.launchIntentCoordinator
    )
    .environmentObject(mainTab.memberContextStore)
    .id(session.accountID)
    .onAppear {
        mainTab.launchIntentCoordinator.updateReadiness {
            $0.isSignedIn = true
            $0.accountID = session.accountID
            $0.isAccountPrepared = true
            $0.isOnboardingBlocking = false
        }
    }
} else {
    MainTabCoordinatorView(...)
}
```

### 11.2 IOS26TabBarView 核心结构

```swift
@available(iOS 26.0, *)
struct IOS26TabBarView: View {
    let session: UserSession
    @ObservedObject var routeStore: AppRouteStore
    let homeDependencies: HomeFeatureDependencies
    let knowledgeDependencies: KnowledgeFeatureDependencies
    let popularScienceDependencies: PopularScienceFeatureDependencies
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var popularScienceViewModel: PopularScienceHomeViewModel
    @ObservedObject var chatStateStore: ChatStateStore
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var chatDetailViewModel: ChatDetailViewModel
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject var upgradeLoginViewModel: LoginViewModel
    let pushAdapter: PushAdapter
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {
            Tab(L10n.text("tab.home"), systemImage: "house.fill", value: AppRouteStore.RootTab.home) {
                homeContainer
            }

            Tab(L10n.text("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill", value: AppRouteStore.RootTab.chat) {
                chatContainer
            }

            Tab(L10n.text("tab.deep_tutor"), systemImage: "graduationcap.fill", value: AppRouteStore.RootTab.deepTutor) {
                deepTutorContainer
            }

            Tab(L10n.text("tab.popular_science"), systemImage: "book.pages.fill", value: AppRouteStore.RootTab.popularScience) {
                popularScienceContainer
            }

            Tab(L10n.text("tab.settings"), systemImage: "gearshape.fill", value: AppRouteStore.RootTab.settings) {
                settingsContainer
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = true }
        }
        .onDisappear {
            launchIntentCoordinator.updateReadiness { $0.mainTabReady = false }
        }
    }
}
```

注意：

1. `Tab(..., value:)` 语法以本机 Xcode 26 SDK 为准。
2. 如果实际 SDK 仍要求 `.tag(...)`，则沿用 `.tag(AppRouteStore.RootTab.home)`。
3. 必须避免写 `UITabBar.appearance().backgroundColor` 等破坏 Liquid Glass 的代码。

### 11.3 首页容器复用

```swift
@available(iOS 26.0, *)
private extension IOS26TabBarView {
    var homeContainer: some View {
        CompatibleRouteNavigationContainer(path: routePath(.home)) {
            HomeView(
                dependencies: homeDependencies,
                viewModel: homeViewModel,
                medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
                externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
                launchIntentCoordinator: launchIntentCoordinator,
                session: session
            )
        } destination: { route in
            destinationBuilder.destination(route)
        }
    }
}
```

### 11.4 首页工作台 View 草图

```swift
@available(iOS 26.0, *)
struct IOS26HomeDashboardView: View {
    @ObservedObject var viewModel: HomeViewModel
    let session: UserSession
    let actionHandler: IOS26HomeDashboardActionHandler

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                memberStrip
                primaryActions
                secondaryActions
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
```

### 11.5 首页模块按钮草图

```swift
@available(iOS 26.0, *)
private struct IOS26HomeActionCard: View {
    let item: IOS26HomeActionItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: item.symbolName)
                    .font(.title2.weight(.semibold))
                Text(item.title)
                    .font(.headline)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.isEnabled == false)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
    }
}
```

## 12. 落地细节

### 12.1 文件清单

| 文件 | 动作 | 说明 |
| --- | --- | --- |
| `AppCoordinatorView.swift` | 修改 | iOS 26 分支改为 `IOS26TabBarView` |
| `IOS26TabBarView.swift` | 新增 | 正式 iOS 26 主 Tab |
| `MainTabRouteDestinationBuilder.swift` | 新增 | 复用 route destination |
| `MainTabCoordinatorView.swift` | 修改 | 调用公共 destination builder，减少重复 |
| `IOS26HomeDashboardView.swift` | 新增 | iOS 26 首页主模块 UI |
| `IOS26HomeDashboardActionHandler.swift` | 新增 | 首页动作路由协调 |
| `DeepTutorQuickStartMode.swift` | 新增 | 体检计划、报告解读模式预留 |
| `DeepTutorChatViewModel.swift` | 修改 | 新增快捷建会话方法 |
| `HomeView.swift` | 修改 | iOS 26 下使用新首页内容，保留生命周期/sheet/cover |
| `HomeViewModel.swift` | 可选修改 | 家庭档案入口统一方法 |

### 12.2 不允许的实现方式

1. 不允许把正式首页写在 `AppCoordinatorView.swift`。
2. 不允许继续保留 `Numbers`、`Alerts` demo。
3. 不允许 iOS 26 分支绕过 `HomeView` 的生命周期和启动意图消费。
4. 不允许首页直接访问 DeepTutor repository。
5. 不允许直接 push UIKit controller 绕过 `AppRouteStore`。
6. 不允许用自定义底栏替代系统 TabBar。
7. 不允许复制两份 route destination switch。

### 12.3 数据加载

1. 首页数据仍由 `HomeViewModel.loadInitialIfNeeded(syncRemote: true)` 负责。
2. iOS 26 首页只消费 `HomeViewModel.dashboard`、`selectedMemberID`、`pendingInviteCount` 等现有状态。
3. 用药和家庭药箱页面继续从 `completeData` 读取首屏数据。
4. DeepTutor 快捷入口创建的是本地会话，不依赖远端接口。

### 12.4 错误处理

| 场景 | 处理 |
| --- | --- |
| DeepTutor 创建失败 | 保持首页，展示 `conversationCreationError` 或 toast |
| 未选择成员点击家庭药箱 | 提示“请先选择或创建家庭成员” |
| 无成员点击家庭档案 | 打开创建成员流程 |
| 用药数据为空 | 仍进入用药页面，由页面展示空状态 |
| iOS 26 API 编译失败 | 以本机 Xcode 26 SDK 调整 `Tab` 初始化签名 |

## 13. 验收标准

### 13.1 iOS 26 主导航

1. iOS 26 登录后进入正式 `IOS26TabBarView`。
2. 底部没有 `Numbers`、`Alerts` demo。
3. Tab 只有 `首页`、`DeepTutor`、`搜索`。
4. 滚动首页时，iPhone 上 TabBar 可按系统行为最小化。
5. iOS 25 及以下仍进入 `MainTabCoordinatorView`。

### 13.2 首页主模块

1. 首页展示“家庭健康工作台”。
2. 首页展示当前成员选择区域。
3. 首页展示制定体检计划、报告解读、用药、家庭药箱、家庭档案五个入口。
4. UI 使用系统字体、系统材质、动态字体。
5. 深色模式可读。
6. Dynamic Type 放大后文字不重叠。

### 13.3 体检计划入口

1. 点击“制定体检计划”后创建新的 DeepTutor 会话。
2. 自动切换到 DeepTutor Tab。
3. 自动进入新会话页面。
4. 会话标题为“制定体检计划”或等价本地化文案。
5. 本期不要求 AI 自动生成体检计划，但要预留 mode。

### 13.4 报告解读入口

1. 点击“报告解读”后创建新的 DeepTutor 会话。
2. 自动切换到 DeepTutor Tab。
3. 自动进入新会话页面。
4. 会话标题为“报告解读”或等价本地化文案。
5. 本期不要求 AI 自动解读报告，但要预留 mode。

### 13.5 用药入口

1. 点击“用药”进入 `MedicationExecutionCenterPage`。
2. 路由使用 `.homeMedicalList(.medicationPlans, nil)`。
3. 页面返回后仍停留在首页 Tab。

### 13.6 家庭药箱入口

1. 有选中成员时点击进入 `FamilyMedicineCabinetPage`。
2. 路由使用 `.homeFamilyMedicineCabinet(memberID:)`。
3. 无选中成员时展示明确提示，不崩溃。

### 13.7 家庭档案入口

1. 有选中成员时点击进入成员详情/家庭档案承载页。
2. 无成员时点击进入创建成员流程。
3. 必须复用 `HomeView` 当前成员与档案链路。

## 14. 测试建议

### 14.1 单元测试

1. `DeepTutorQuickStartMode.title` 和 `initialDraft` 正确。
2. `createQuickStartConversation(mode:)` 创建会话后返回 id。
3. 创建失败时设置 `conversationCreationError`。
4. `IOS26HomeDashboardActionHandler` 对每个 action 调用正确 route。

### 14.2 手工验收

1. iOS 26 模拟器登录。
2. 首页滚动，观察 TabBar 悬浮和最小化。
3. 点击制定体检计划，确认进入 DeepTutor 新会话。
4. 返回首页，点击报告解读，确认进入另一个新会话。
5. 点击用药，确认进入用药执行中心。
6. 点击家庭药箱，确认进入家庭药箱。
7. 点击家庭档案，确认进入成员详情或创建成员流程。
8. 切换深色模式。
9. 打开大字体。
10. iOS 25 模拟器确认旧主导航不变。

## 15. 分阶段实施计划

### Phase 1：导航替换

1. 新增 `IOS26TabBarView.swift`。
2. 从 `AppCoordinatorView` 移除 demo。
3. 复用 existing dependencies。
4. 补齐 `launchIntentCoordinator.mainTabReady`。

### Phase 2：Route Destination 收口

1. 新增 `MainTabRouteDestinationBuilder.swift`。
2. `MainTabCoordinatorView` 迁移到 builder。
3. `IOS26TabBarView` 使用 builder。

### Phase 3：首页主模块

1. 新增 `IOS26HomeDashboardView.swift`。
2. 在 `HomeView` 的内容层切换 iOS 26 首页。
3. 完成 plain text UI 对齐。
4. 完成无成员、无数据、loading 状态。

### Phase 4：快捷入口

1. 新增 `DeepTutorQuickStartMode`。
2. `DeepTutorChatViewModel` 新增快捷建会话方法。
3. 首页接入制定体检计划和报告解读。
4. 首页接入用药、家庭药箱、家庭档案。

### Phase 5：验收与回归

1. iOS 26 编译与手工验收。
2. iOS 25 编译与回归。
3. DeepTutor 创建会话失败场景验证。
4. 首页大字体、深色模式验证。

## 16. 风险与规避

| 风险 | 影响 | 规避 |
| --- | --- | --- |
| iOS 26 `Tab` API 签名变化 | 编译失败 | 以本机 Xcode 26 SDK 为准，保留 `.tag` fallback |
| iOS 26 分支绕过 HomeView 生命周期 | 启动 intent 丢失 | `IOS26TabBarView` 必须继续承载 `HomeView` |
| DeepTutor 快捷入口只设置 selectedConversationID | 不会跨 Tab 导航 | 返回 conversation id 后调用 `routeStore.route(to: .deepTutorThread(id))` |
| route destination 复制 | 后续维护分叉 | 抽 `MainTabRouteDestinationBuilder` |
| 家庭档案入口无法从外层控制 cover | 无法进入成员详情 | 将入口实现放在 `HomeView` 内部或新增 `HomeViewModel` pending action |
| 自定义 TabBar 外观破坏 Liquid Glass | 系统材质失效 | 禁止 appearance background/backgroundImage |
| 底部 Tab 收窄为三项 | 原有对话/科普/设置入口不再直达 | 保留首页内部入口和搜索承接，必要时后续单独恢复次级入口 |

## 17. 后期扩展

1. 体检制定模式接入 `DeepTutorPromptBuilder`。
2. 报告解读模式接入报告选择/上传工具。
3. 搜索作为 iOS 26 专用 Tab。
4. 首页展示最近一次体检、今日用药、快过期药品。
5. 根据成员年龄和模块开通状态动态排序首页入口。

## 18. 官方规范约束

1. 使用系统 `TabView` / `Tab`，不自绘底部 TabBar。
2. 使用 `.tabBarMinimizeBehavior(.onScrollDown)` 验证 iPhone 滚动最小化。
3. 不设置 `UITabBar.appearance().backgroundColor`。
4. 不设置 `UITabBar.appearance().backgroundImage`。
5. 不隐藏系统选中胶囊。
6. 不硬编码 WWDC 视频里的视觉尺寸。
7. 保留系统安全区和 Liquid Glass 滚动边缘效果。
