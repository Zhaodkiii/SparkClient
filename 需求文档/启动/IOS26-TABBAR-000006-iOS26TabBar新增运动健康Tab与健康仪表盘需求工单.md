# IOS26-TABBAR-000006：iOS26TabBar 新增运动健康 Tab 与健康仪表盘需求工单

> 创建日期：2026-08-20  
> 关联模块：IOS26TabBarView、AppRouteStore、MainTabCoordinatorView、HealthKit、体重/血氧/心率/睡眠/步数等健康指标、用户健康档案  
> 关联代码：`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift`、`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`、`SparkClient/Projects/Features/Nutrition/Presentation/EnergyBurn/NutritionEnergyBurnViews.swift`（热量消耗现有能力）、`SparkClient/Projects/Core/Health/`（苹果健康能力）  
> 状态：新需求/待实现  
> 优先级：P1，Tab 级新增模块

---

## 1. 一句话目标

在 iOS26 主 Tab 栏新增「运动健康」独立 Tab，采用新的独立目录结构承载健康仪表盘；在绑定/未绑定苹果健康（HealthKit）设备的两种状态下，分别展示全量/精简的健康数据卡片，把体重、睡眠、饮食、步数、运动记录、热量消耗、站立小时、运动锻炼时长、血氧饱和度、心率等数据集中在一个视图里。

---

## 2. 背景与问题

当前健康相关数据分散在多个入口：

1. 体重、BMI、体脂率等身材管理数据在「用户健康数据档案」中已有，未集中到首页。
2. 睡眠、步数、热量消耗、运动时长、心率、血氧等苹果健康可读取数据目前未聚合展示。
3. 血糖、血压等需要外部设备或手动录入的数据暂未接入，需要为后期保留扩展位。
4. 饮食数据已独立为 `Nutrition` Tab，运动/体征类数据还没有聚合入口。
5. 当前主 Tab 栏仅包含健康、饮食、AI 对话、科普、DeepTutor、设置，缺乏面向「每天健康数据打卡」的专用入口。

结果是：

1. 用户无法在一个页面上快速浏览当天整体健康状况。
2. 未绑定 HealthKit 的用户看到一片空白，体验差。
3. 未来接入血糖、血压等设备数据时没有统一承载位置。
4. 运动健康的“每天看一眼”心智尚未建立。

本工单要解决的是：**新增「运动健康」Tab，作为健康数据（体征 + 运动 + 体征趋势）的唯一聚合入口，首版覆盖苹果健康与档案内的数据，并预留血糖/血压扩展位。**

---

## 3. 目标

### 3.1 用户目标

1. 打开 App 后，通过新的 Tab 能一眼看到当天核心健康数据。
2. 已绑定苹果健康（授权数据读取）的用户看到全量健康仪表盘：体重/BMI、睡眠、饮食、步数、运动记录、热量消耗、站立小时、运动锻炼时长、血氧饱和度、心率。
3. 未绑定（或未授权）苹果健康的用户只看到基础数据（档案内已有数据，如体重/BMI），其余卡片展示「暂无数据」占位，并引导去绑定/授权。
4. 血糖、血压作为预留卡片，始终占位，展示「暂无数据」状态，待后续设备接入。
5. 每张卡片都能点击进入对应详情页（详情页不在本期范围）。

### 3.2 产品目标

1. 建立独立的「运动健康」功能模块（Feature），而不是把逻辑塞进 Home/Nutrition。
2. 与 Nutrition 模块并列，形成「健康首页 / 饮食 / 运动健康 / AI 对话」的一级导航心智。
3. 为后续接入血糖仪、血压计、智能手表等外部设备预留统一的数据接入点。
4. 降低首次进入空窗期：未绑定用户看到「少量数据」而非纯空白。

### 3.3 成功指标

| 指标 | 目标 |
| --- | --- |
| Tab 曝光率 | 新 Tab 在主 Tab 栏可见，默认顺序由产品定义 |
| 授权完成率 | 未授权用户点击卡片后能顺利跳转到健康授权引导 |
| 首屏卡片数（已授权） | ≥ 9 张卡片首屏可见（身材管理 + 睡眠 + 饮食 + 步数 + 运动 + 热量 + 站立 + 锻炼时长 + 血氧 + 心率） |
| 首屏卡片数（未授权） | ≥ 1 张档案数据卡片（身材管理）+ 预留占位 |
| 可扩展性 | 血糖/血压卡片结构就绪，接入时只需接数据，不改页面骨架 |

---

## 4. 非目标

1. 本期**不做**血糖、血压的真实数据接入，仅预留 UI 占位。
2. 本期**不做**健康数据的历史趋势图（折线图/周/月视图），卡片只展示当日最新值。
3. 本期**不做**数据手动录入，所有数据来源限定为苹果健康 + 用户档案。
4. 本期**不做**独立外部设备绑定流程（与手表/手环/血压计配对等），仅保留 HealthKit 授权。
5. 本期**不做**健康数据 AI 解读，所有卡片只做数值 + 单位 + 时间戳展示。
6. 本期**不改动** Nutrition、Home 等现有 Tab 内的逻辑，新增内容只落在新 Feature 目录下。
7. 本期**不提供**经典 `MainTabCoordinatorView`（iOS < 26）下的新 Tab（沿用 iOS26 主 Tab 栏），是否同步到经典 Tab 栏后续再评估。

---

## 5. 模块定义

### 5.1 新 Tab 与路由

1. 在 `AppRouteStore.RootTab` 新增 `case fitness = 9`（raw value 沿用“新值避免影响历史选中态”约定，具体编号以合并时为准）。
2. 在 `AppRoute` 新增 `case fitnessHome`（根路由），以及未来详情路由占位：
   - `case fitnessWeightDetail`
   - `case fitnessSleepDetail`
   - `case fitnessStepsDetail`
   - `case fitnessWorkoutDetail`
   - `case fitnessCaloriesDetail`
   - `case fitnessStandHourDetail`
   - `case fitnessExerciseTimeDetail`
   - `case fitnessBloodOxygenDetail`
   - `case fitnessHeartRateDetail`
   - `case fitnessBloodGlucoseDetail`（预留）
   - `case fitnessBloodPressureDetail`（预留）
3. `rootTab` 与 `isRootDestination` 映射同步补齐。
4. 在 `IOS26TabBarView` 中新增 Tab 项（图标、文案、顺序见 §7）。
5. 本地化新增 `tab.fitness`：中文「运动健康」，英文「Fitness」。

### 5.2 新 Feature 目录结构

新增模块：`SparkClient/Projects/Features/Fitness/`，建议结构参考 Nutrition / Home 模块：

```
Features/Fitness/
├── Application/
│   ├── FitnessDashboardUseCase.swift         // 聚合各数据源(档案/HealthKit/饮食)
│   ├── FitnessHealthKitSyncUseCase.swift     // HealthKit 授权检查、数据拉取
│   └── FitnessAuthorizationStateUseCase.swift // 是否已授权/已绑定 HealthKit
├── Domain/
│   ├── FitnessDashboardModels.swift          // 仪表盘卡片模型(枚举 + 数据)
│   ├── FitnessMetricType.swift               // 指标类型枚举(体重/睡眠/步数...)
│   ├── FitnessMetricValue.swift              // 指标值(数值/单位/时间戳/状态)
│   └── FitnessRepository.swift               // 仓库协议
├── Infrastructure/
│   ├── DefaultFitnessRepository.swift        // 默认实现(聚合多数据源)
│   ├── FitnessHealthKitStore.swift           // HealthKit 读取封装
│   ├── FitnessProfileStoreAdapter.swift      // 从用户健康档案读体重/BMI
│   └── FitnessNutritionAdapter.swift         // 复用 Nutrition 模块的当日热量数据
└── Presentation/
    ├── Root/
    │   ├── FitnessHomeView.swift             // 运动健康 Tab 根视图(仪表盘)
    │   ├── FitnessHomeViewModel.swift        // 仪表盘 VM
    │   └── FitnessHomeState.swift            // 仪表盘状态(idle/loading/content/error)
    ├── Components/
    │   ├── FitnessMetricCard.swift           // 通用指标卡片组件(双列/单列)
    │   ├── FitnessSectionHeader.swift        // "健康仪表盘" 标题
    │   └── FitnessMetricStatusBadge.swift    // "偏低/正常/偏高" 状态徽标
    ├── Cards/
    │   ├── FitnessWeightCard.swift           // 身材管理(体重/BMI/体脂)
    │   ├── FitnessSleepCard.swift            // 睡眠
    │   ├── FitnessNutritionCard.swift        // 饮食(复用 Nutrition 热量数据)
    │   ├── FitnessStepsCard.swift            // 步数
    │   ├── FitnessWorkoutCard.swift          // 运动记录(最近一条)
    │   ├── FitnessCaloriesCard.swift         // 热量消耗(运动消耗)
    │   ├── FitnessStandHourCard.swift        // 站立小时
    │   ├── FitnessExerciseTimeCard.swift     // 总锻炼时长
    │   ├── FitnessBloodOxygenCard.swift      // 血氧饱和度
    │   ├── FitnessHeartRateCard.swift        // 心率
    │   ├── FitnessBloodGlucoseCard.swift     // 血糖(占位:暂无数据)
    │   └── FitnessBloodPressureCard.swift    // 血压(占位:暂无数据)
    ├── Authorization/
    │   ├── FitnessHealthKitAuthPromptView.swift   // 未授权时的引导卡片
    │   └── FitnessHealthKitAuthViewModel.swift
    └── Navigation/
        └── FitnessRoute.swift                // Feature 内部路由
```

> 目录命名、UseCase 划分、VM 命名与 Nutrition、Home 模块保持一致风格（Application/Domain/Infrastructure/Presentation 四层），具体文件名可在实现时微调。

### 5.3 数据源说明

| 指标 | 数据源 | 未授权/无数据表现 |
| --- | --- | --- |
| 体重 / BMI / 体脂率 | 用户健康档案（已有） | 档案无数据时「暂无数据」，不依赖 HealthKit |
| 睡眠时长 | HealthKit（`HKCategoryTypeIdentifierSleepAnalysis`） | 未授权/无数据：「暂无数据」 |
| 饮食记录（当日摄入/目标） | 复用 `Nutrition` 模块当日数据 | 无数据：「-- kcal/--kcal」 |
| 步数 | HealthKit（`HKQuantityTypeIdentifierStepCount`） | 未授权/无数据：「--/10000」（默认日目标 10000） |
| 运动记录（最近一条运动） | HealthKit（`HKWorkoutTypeIdentifier`） | 未授权/无数据：「暂无数据」 |
| 热量消耗（运动消耗） | HealthKit（`HKQuantityTypeIdentifierActiveEnergyBurned`） | 未授权/无数据：「-- kcal 运动消耗」 |
| 站立小时 | HealthKit（`HKCategoryTypeIdentifierAppleStandHour`） | 未授权/无数据：「-- 小时」 |
| 总锻炼时长 | HealthKit（`HKQuantityTypeIdentifierAppleExerciseTime`） | 未授权/无数据：「-- 分钟」 |
| 血氧饱和度 | HealthKit（`HKQuantityTypeIdentifierOxygenSaturation`），异常态显示「偏低」徽标 | 未授权/无数据：「-- %」 |
| 心率 | HealthKit（`HKQuantityTypeIdentifierHeartRate`） | 未授权/无数据：「-- 次/分钟」 |
| 血糖 | **预留**（不接数据） | 始终「暂无数据 / -- mmol/L」 |
| 血压 | **预留**（不接数据） | 始终「暂无数据 / -- mmHg」 |

---

## 6. 交互与视觉规范

### 6.1 页面结构（从上到下）

1. 顶部大标题：**健康仪表盘**（navigationTitle，大标题样式）。
2. 成员切换（沿用 `MemberContextStore`，与 Nutrition/Home 保持一致）。
3. 未授权状态：在顶部显示「绑定苹果健康」引导卡（一次关闭后本期不再强打扰，是否持久化由实现定）。
4. 卡片区：
   - 第 1 行 **身材管理**（全宽卡片）：体重（KG） / BMI（标签） / 体脂率。
   - 第 2 行起双列布局：睡眠 / 饮食记录。
   - 第 3 行：步数 / 运动记录。
   - 第 4 行：热量消耗 / 站立小时数。
   - 第 5 行：总锻炼时长 / 血氧饱和度（异常时右上角「偏低」徽标）。
   - 第 6 行：血糖 / 血压（暂占位，显示「暂无数据」）。
   - 第 7 行：心率（单列，全宽卡片）。
5. 底部隐私提示：**「档案内容仅供您本人使用，我们将严格保护您的隐私安全」**（未绑定状态显示，已绑定可隐藏或弱化）。

> 布局参考设计图：两张状态——「已绑定展示全量」「未绑定展示少量数据+占位」。

### 6.2 卡片视觉统一规范

1. 背景：`RoundedRectangle` 圆角 20~24pt，浅色渐变/毛玻璃底（沿用 Nutrition 卡片风格），卡片左上角淡色「HEALTHY」大字水印（参考设计图）。
2. 顶部：图标 + 标题 + 可选状态徽标（如血氧「偏低」）。
3. 中部：时间戳（最近一次数据时间，格式 `MM-dd HH:mm`，无数据显示「暂无数据」）。
4. 下部：数值 + 单位，主数字使用大字号加粗（32~36pt），副单位/标签小号字。
5. 空态：主数字显示 `--`，单位保留，时间戳「暂无数据」为次级灰色。
6. 异常态：数值用主色；状态徽标用橙色边框胶囊标签（如「偏低」）。

### 6.3 两种状态差异

**已绑定/已授权 HealthKit**：
- 体重从档案读取，其余从 HealthKit/Nutrition 读取最新值。
- 所有卡片显示时间戳和具体数值（若某单指标授权被拒，则该卡片按空态处理，不影响其他卡片）。
- 不显示底部隐私提示（或弱化显示）。

**未绑定/未授权**：
- 体重/BMI/体脂仍从档案读取（即使未授权也应能看到这部分，若档案也无则显示空态）。
- 睡眠、步数、运动、热量、站立、锻炼时长、血氧、心率统一显示「暂无数据」+ `--`。
- 饮食记录根据 Nutrition 模块是否有数据决定（与 HealthKit 授权无关）。
- 血糖/血压始终占位「暂无数据」。
- 顶部显示引导授权卡片，底部显示隐私提示文案。

### 6.4 点击行为

1. 本期所有有数据的卡片点击后进入对应详情页占位（可先路由到一个统一的「敬请期待」占位页，或空实现，详情页在后续工单中完成）。
2. 未授权状态下点击 HealthKit 相关卡片，弹出系统健康授权请求（或跳到系统设置）。
3. 血糖/血压卡片点击后弹 Toast「该功能即将上线」或无响应，不做跳转。
4. 引导授权卡片：主按钮「去授权」，关闭按钮「稍后再说」。

### 6.5 UI 线框图（纯文本示意）

以下 ASCII 线框图仅描述布局与信息层级，最终像素级视觉以 UI 设计稿为准。所有卡片统一圆角矩形 + 浅色毛玻璃/渐变底 + 左上角淡色「HEALTHY」水印，图标 + 标题行在上，时间戳居中，大数值在下。

#### 6.5.1 状态 A：已绑定 / 已授权 HealthKit（全量数据）

```
┌─────────────────────────────────────────────────────────┐
│  健康仪表盘                               [成员切换 ▾]   │  ← 大标题 navigationTitle
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ╭─────────────────────────────────────────────────╮    │
│  │ ▣ 身材管理                         08-20 10:16  │    │  ← 全宽卡片
│  │                                                 │    │
│  │   66.25           22.9              --          │    │
│  │   体重/KG        BMI·标准         体脂率·暂无    │    │
│  ╰─────────────────────────────────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ ☾ 睡眠                │ │ 🍽 饮食记录           │    │
│  │       08-20 08:16     │ │       暂无数据        │    │
│  │                       │ │                       │    │
│  │   4h47m               │ │   -- kcal/--kcal      │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ 👟 步数               │ │ 📋 运动记录           │    │
│  │       08-20 10:39     │ │       08-17 13:36     │    │
│  │                       │ │                       │    │
│  │   768 / 10000         │ │   160分钟(羽毛球)     │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ 🔥 热量消耗           │ │ 🕒 站立小时数         │    │
│  │       08-20 10:40     │ │       08-20 10:40     │    │
│  │                       │ │                       │    │
│  │   61 kcal 运动消耗    │ │   3 小时              │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ ⏱ 总锻炼时长          │ │ 🫧 血氧饱和度 [偏低]   │    │  ← 异常态右上角徽标
│  │       08-20 10:40     │ │       08-20 08:55     │    │
│  │                       │ │                       │    │
│  │   3 分钟              │ │   93 %                │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ 💧 血糖               │ │ 🩺 血压               │    │  ← 预留位(暂无数据)
│  │       暂无数据        │ │       暂无数据        │    │
│  │                       │ │                       │    │
│  │   -- mmol/L           │ │   -- mmHg             │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭─────────────────────────────────────────────────╮    │
│  │ ♡ 心率                           08-20 10:34    │    │  ← 单列全宽
│  │                                                 │    │
│  │   99 次/分钟                                    │    │
│  ╰─────────────────────────────────────────────────╯    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 6.5.2 状态 B：未绑定 / 未授权 HealthKit（精简数据 + 占位）

```
┌─────────────────────────────────────────────────────────┐
│  健康仪表盘                               [成员切换 ▾]   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ╭─────────────────────────────────────────────────╮    │
│  │ 🔗 绑定苹果健康，解锁完整健康数据               │    │  ← 授权引导卡
│  │  授权后可查看步数/睡眠/心率/血氧等完整数据      │    │
│  │                                                 │    │
│  │              [ 去授权 ]      稍后再说           │    │
│  ╰─────────────────────────────────────────────────╯    │
│                                                         │
│  ╭─────────────────────────────────────────────────╮    │
│  │ ▣ 身材管理                         暂无数据     │    │  ← 档案也无数据时
│  │                                                 │    │
│  │    --              --                --         │    │
│  │   体重/KG       BMI·暂无         体脂率·暂无    │    │
│  ╰─────────────────────────────────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮ ╭───────────────────────╮    │
│  │ ☾ 睡眠                │ │ 💧 血糖               │    │
│  │       暂无数据        │ │       暂无数据        │    │
│  │                       │ │                       │    │
│  │   --                  │ │   -- mmol/L           │    │
│  ╰───────────────────────╯ ╰───────────────────────╯    │
│                                                         │
│  ╭───────────────────────╮                             │
│  │ 🩺 血压               │                             │
│  │       暂无数据        │                             │
│  │                       │                             │
│  │   -- mmHg             │                             │
│  ╰───────────────────────╯                             │
│                                                         │
│                                                         │
│            ⨁ 档案内容仅供您本人使用，                    │
│              我们将严格保护您的隐私安全                  │  ← 底部灰字提示
│                                                         │
└─────────────────────────────────────────────────────────┘
```

> 说明：
> - 状态 B 下仅身材管理从档案读取（档案也无数据时卡片仍占位显示「暂无数据」）；其余 HealthKit 指标统一 `--` 占位；
> - 血糖 / 血压无论授权与否都始终显示占位卡片（为后期设备接入预留）；
> - 授权引导卡可被关闭一次，关闭后本期内不再强制弹出（持久化策略由实现决定）；
> - 心率卡片在未授权状态下可以选择隐藏或保留在底部单列占位，由 UI 最终决定，本工单不强绑。

#### 6.5.3 卡片内部结构（通用模板）

```
╭─────────────────────────────────────╮
│ [ICON] 卡片标题          [状态徽标]  │  ← 标题行（图标 + 标题，右上角可选徽标如「偏低」）
│              MM-dd HH:mm            │  ← 时间戳（次级灰字，无数据时显示「暂无数据」）
│                                     │
│      数值       单位 / 标签         │  ← 大号主数字 + 小号单位，无数据显示 --
╰─────────────────────────────────────╯
```

单卡片样式对齐要素：
- 圆角：20~24pt
- 内边距：16pt
- 标题：headline 字重 semibold
- 时间戳：footnote，次级前景色
- 主数值：title/title2 字重 bold
- 异常徽标：橙色描边胶囊，如「偏低」「偏高」

---

## 7. Tab 栏集成

1. 在 `IOS26TabBarView` 的 `TabView` 中新增：

   ```swift
   Tab(L10n.text("tab.fitness"), systemImage: "figure.run", value: AppRouteStore.RootTab.fitness) {
       fitnessContainer
   }
   ```

2. 建议 Tab 顺序（与产品最终确认为准）：**健康 / 饮食 / 运动健康 / AI 对话 / 设置**。图标推荐：`figure.run`（或 `heart.text.square.fill` / `waveform.path.ecg`，以最终设计为准）。
3. 新增 `fitnessContainer`：用 `CompatibleRouteNavigationContainer(path: routePath(.fitnessHome))` 包裹 `FitnessHomeView`。
4. `fitnessContainer` 所需依赖（`FitnessFeatureDependencies`）在 `AppContainer` / `SignedInMainTabHostView` 中统一组装，并注入到 `IOS26TabBarView`（与 `homeDependencies` / `nutritionDependencies` 类似）。
5. `MainTabRouteDestinationBuilder` 中增加对应 case 的占位返回（`EmptyView()`），确保 switch 完备。

---

## 8. 依赖与复用

1. **体重数据**：复用 `HomeFeatureDependencies` 中已有的用户健康档案/成员健康档案读取能力，不新写接口。
2. **热量消耗/饮食**：直接复用 `NutritionFeatureDependencies.dashboardUseCase` 或 `healthKitSyncUseCase`，避免重复实现。
3. **HealthKit**：项目已有 `SparkHealthTool`（`Projects/Core/Health/`）以及 Nutrition 模块中的 `NutritionHealthKitSyncUseCase`/`NutritionHealthKitStore`，**优先复用 / 抽象通用能力**，不要在 Fitness 模块直接硬写一套新的 HealthKit 调用；建议提取一个跨模块的 HealthKit 查询工具层（或在 Fitness 模块内做适配）。
4. **成员上下文**：复用 `MemberContextStore` 作为当前选中成员来源。
5. **Logger**：统一使用项目 `Logger`，module 标签为 `.fitness`（新增 case 时同步扩展 Logger 枚举）。
6. **路由容器**：统一使用 `CompatibleRouteNavigationContainer` + `MainNavigationLink`。

---

## 9. 数据边界与权限

1. HealthKit 读取权限只请求本工单涉及的类型：睡眠、步数、运动（workout）、活动能量、站立小时、锻炼时长、血氧、心率。**不写入** HealthKit 任何数据。
2. 体重从用户档案读取，不走 HealthKit（体重写入/读取以现有档案链路为准）。
3. 家庭成员维度：健康数据以「当前选中成员」为粒度读取，切换成员时仪表盘整体刷新。
4. 未选中成员时，所有卡片按空态显示，不请求 HealthKit。
5. 数据只在本地读取展示，本期不上传健康原始数据。

---

## 10. 验收标准

### 10.1 功能验收

1. 新 Tab「运动健康」出现在 iOS26 主 Tab 栏，点击进入健康仪表盘页面。
2. 未授权 HealthKit 时：
   - 顶部出现引导授权卡片；
   - 身材管理显示档案内体重/BMI（无则占位）；
   - 其余 HealthKit 相关卡片显示「暂无数据 / --」；
   - 血糖/血压显示「暂无数据」占位；
   - 底部隐私提示可见。
3. 已授权 HealthKit 后：
   - 引导卡片消失；
   - 9+ 项数据卡片能展示最近一次读数与时间戳；
   - 血氧异常值右上角出现「偏低」等徽标；
   - 步数默认目标 10000，显示为 `X / 10000` 格式；
   - 运动记录卡片显示最近一次运动的时长与类型（如「160 分钟(羽毛球)」）。
4. 切换成员时仪表盘刷新为该成员的数据。
5. 下拉刷新：重新拉取 HealthKit / 档案最新数据。
6. 进入页面时自动拉取数据（`.task`），前后台切换回前台自动刷新。

### 10.2 工程验收

1. 新代码全部落在 `Features/Fitness/` 下，不污染 Home / Nutrition 模块。
2. `AppRouteStore`、`AppContainer`、`IOS26TabBarView`、`MainTabRouteDestinationBuilder` 等 App 层文件改动最小化，仅做必要的注册与注入。
3. Feature 四层（Application/Domain/Infrastructure/Presentation）结构与现有 Nutrition 模块对齐。
4. HealthKit 能力复用现有封装，禁止在 Fitness 模块里重复造 HKHealthStore 单例。
5. 所有文本走本地化（`L10n.text(...)`），中文 zh-Hans 与英文 en 两份都补。
6. 无强制解包、无废弃 API 使用、`onChange` 使用新 API（两参数闭包），编译无警告。
7. 提供 Preview 覆盖：已授权全量态、未授权空态、深色模式。

### 10.3 不在本期（Follow-up）

1. 每个指标的详情页（趋势图/周月视图）。
2. 血糖、血压的真实数据接入（设备/手动录入）。
3. 健康异常 AI 解读与主动提醒。
4. 健康数据写入 HealthKit（如手动录入体重）。
5. 健康目标设置（步数目标、睡眠目标）与目标达成提醒。
6. iPad / macOS 适配。
7. 经典 Tab 栏（`MainTabCoordinatorView`，iOS < 26）下的新 Tab。

---

## 11. 风险与依赖

1. **HealthKit 授权粒度**：用户可以选择性拒绝部分指标授权，需要做到单项指标独立容错，不因一个类型失败影响整个页面。
2. **血氧可用设备**：血氧仅在支持的设备（Apple Watch Series 6 及以上）上有数据，需要兜底空态。
3. **跨模块依赖**：复用 Nutrition 能力时注意不要形成循环依赖；如发现循环依赖，把 HealthKit 通用层抽到 Core/Health 或独立的 Fitness 基础设施模块。
4. **性能**：HealthKit 数据查询应统一用并发（`async/await`）查询，避免主线程阻塞；建议一次并发查询所有指标，合并结果后一次性更新 ViewModel。
5. **隐私合规**：Info.plist 中 HealthKit 用途说明字段（`NSHealthShareUsageDescription` 等）需确认已配置，未配置则在合入前补齐。

---

## 12. 实现建议顺序

1. 骨架：新建 `Features/Fitness/` 目录与 `FitnessFeatureDependencies`、`FitnessHomeView`、`FitnessHomeViewModel`、`FitnessRoute`。
2. 路由注册：`AppRouteStore` / `AppRoute` / `MainTabRouteDestinationBuilder` 注册 `fitness` 根路由。
3. App 组装：在 `AppContainer`/`SignedInMainTabHostView` 中组装 Fitness 依赖，注入 `IOS26TabBarView`，新增 `fitnessContainer`。
4. 卡片组件：先实现通用 `FitnessMetricCard` 和空态/已绑定两种布局骨架（先用假数据）。
5. 数据源接入：先接档案体重 → 再接 Nutrition 饮食 → 再批量接 HealthKit 8 项指标。
6. 异常态/占位态：补血氧「偏低」徽标、血糖/血压占位、未授权引导卡。
7. 下拉刷新/前后台刷新/成员切换刷新。
8. 预览与埋点（埋点方案后续补）。
9. 自测 + 诊断检查。

---

## 13. 参考设计

- 已绑定全量数据态设计图：身材管理（体重/BMI/体脂）+ 睡眠 + 饮食 + 步数 + 运动 + 热量 + 站立 + 锻炼时长 + 血氧（偏低徽标）+ 心率，共 9+ 张卡片。
- 未绑定精简态设计图：仅身材管理有数据（或空态），其余卡片「暂无数据」占位，含隐私提示文案。
- 图标遵循 SF Symbols：
  - 身材管理：`person.text.rectangle` / `figure.arms.open`
  - 睡眠：`moon.zzz.fill`
  - 饮食：`fork.knife`（与 Nutrition 保持一致）
  - 步数：`shoe.fill` / `figure.walk`
  - 运动记录：`list.bullet.clipboard.fill`
  - 热量消耗：`flame.fill`
  - 站立小时：`clock.fill`
  - 总锻炼时长：`stopwatch.fill`
  - 血氧：`drop.fill` / `lungs.fill`
  - 心率：`heart.fill` / `waveform.path.ecg`
  - 血糖：`drop.halffull`
  - 血压：`cross.case.fill` / `bolt.heart.fill`

（最终以 UI 设计稿为准，本工单不锁定具体 SF Symbol 名称。）

---

## 14. 落地细节

### 14.1 现有代码事实盘点（合入前必须对齐）

以下是当前仓库中可直接复用或必须扩展的真实代码位置，实现时以这些为准：

| 关注点 | 真实位置 | 现状 / 动作 |
| --- | --- | --- |
| `HomeFeatureDependencies` | `Projects/App/Sources/App/Architecture/FeatureAssemblies.swift:34` | 已含 `nutritionDependencies: NutritionFeatureDependencies`；本次需新增 `fitnessDependencies: FitnessFeatureDependencies` 字段并在 `makeHomeDependencies`（约 :163）与 `preview`（约 :108）两处填充 |
| `NutritionFeatureDependencies` | `Projects/Features/Nutrition/Presentation/Root/NutritionHomeViewModel.swift:16` | 四层组装参考范本（UseCase + store + memberContextStore + logger） |
| Nutrition 工厂方法 | `FeatureAssemblies.swift:70` `makeNutritionDependencies(backend:memberContextStore:aiRuntimeService:configCenter:notificationStore:logger:)` | Fitness 工厂方法应仿此签名，但**不需要** `aiRuntimeService` / `configCenter` / `notificationStore`（本期不涉及 AI 与通知） |
| `LogModule` | `Projects/Foundation/Utilities/LogModule.swift:4` | 需新增 `case fitness = "FITNESS"` |
| HealthKit 统一工具 | `Projects/Core/Health/SparkHealthTool.swift:20` `final class SparkHealthTool` | 已有 `stepCount` / `activeEnergyBurned` / `basalEnergyBurned` / `sleepAnalysis` / `workoutType` / `heartRate` / `respiratoryRate` / `flightsClimbed` / `distanceCycling` / `appleSleepingWristTemperature` 等读取与 `requestAuthorization()`；**缺**血氧、站立小时、锻炼时长三类，见 §14.3 |
| 授权方法 | `SparkHealthTool.swift:763` `private func requestAuthorization()` | 现为 `private`；若 Fitness 复用，需评估改为 `internal` 或在 Fitness 内做薄封装；本期建议**复用其商店与查询私有方法路径**，而不是复制 HKHealthStore 单例 |
| 成员上下文 | `MemberContextStore`（`Projects/Features/MemberContext/Presentation/MemberContextStore.swift`） | 用 `context.selectedMemberID`（`Int?`）与 `context.members` 解析成员 |
| Logger 协议 | `Projects/Foundation/Utilities/Logger.swift:113` | `warning` / `info` / `error` 方法论中使用 `module: .fitness` |

### 14.2 HealthKit 指标 → 类型 / 单位 / 聚合方式精确映射

实现 `FitnessHealthKitStore` 时按下表逐项查询，避免类型/单位写错：

| 指标 | `HKQuantityTypeIdentifier` | 读取单位 `HKUnit` | 聚合方式 | 展示格式 |
| --- | --- | --- | --- | --- |
| 步数 | `.stepCount` | `.count()` | 当日 `cumulativeSum` | `768 / 10000` |
| 热量消耗（运动） | `.activeEnergyBurned` | `.kilocalorie()` | 当日 `cumulativeSum` | `61 kcal 运动消耗` |
| 总锻炼时长 | `.appleExerciseTime`（**无，需新增授权+读取**） | `.minute()` | 当日 `cumulativeSum` | `3 分钟` |
| 站立小时 | `.appleStandHour`（`HKCategoryType`，**需新增**） | `.count()` | 当日满足站立的小时数 | `3 小时` |
| 睡眠 | `HKCategoryType.sleepAnalysis` | — | 夜间各阶段时长求和（睡眠日 18:00 切分，复用 `SparkHealthTool.fetchSleepDetails` 规则） | `4h47m` |
| 运动记录 | `HKWorkoutType`（`workoutType()`） | — | 取当日/最近一条 `HKWorkout`，`duration` + `workoutActivityType` 名称 | `160分钟(羽毛球)` |
| 血氧饱和度 | `.oxygenSaturation`（**需新增**） | `.percent()` | 当日最新一条离散样本（非累积） | `93 %` |
| 心率 | `.heartRate` | `.count().unitDivided(by: .minute())` | 当日最新一条离散样本 | `99 次/分钟` |
| 体重 | 档案（非 HealthKit） | `kg`（档案内单位） | 档案最新一条 | `66.25 KG` |
| BMI | 档案派生（体重/身高²） | — | 档案计算或服务端给出 | `22.9 · 标准` |
| 体脂率 | 档案（可选） | `%` | 档案最新一条 | `--`（无则占位） |

> 睡眠的「睡眠日」规则本项目已在 `SparkHealthTool.fetchSleepDetails` 固化：以前一天 18:00 作为睡眠日起点，18:00 后入睡算当天。Fitness 睡眠卡片应复用同一时间归组口径，保证与 AI 工具侧数据一致。

### 14.3 HealthKit 授权缺口（本次必须补齐）

`SparkHealthTool.requestAuthorization()` 现有 `readTypes` 已覆盖：步数、步行距离、活动/基础能量、饮食四要素、睡眠、workout、运动路线、心率、呼吸率、爬楼层数、骑行距离、跑速、睡眠腕温。

**本期运动健康新增三类必须加入授权读取集合，否则查询会因未授权返回空：**

```swift
// 需新增到 Fitness 的授权/读取类型集合（或扩展 SparkHealthTool.readTypes）
HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!     // 血氧
HKObjectType.categoryType(forIdentifier: .appleStandHour)!       // 站立小时（category，非 quantity）
HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!    // 锻炼时长
```

注意 `appleStandHour` 是 `HKCategoryType`，不能用 `statisticsCollection` 的 `cumulativeSum` 路径，需按 `HKCategorySample` 计数满足站立的样本数（或统计 `appleStandHour`=1 的小时数），作为落地时的独立分支实现。

血氧 `.oxygenSaturation` 与心率 `.heartRate` 是「离散快照」型指标，取当日**最新一条**样本，而不是求和/日均，需用 `HKSampleQuery`（`optionalQuantitySamples(for:start:end:)` 现有私有方法正是此语义，可复用/仿照）。

### 14.4 数据模型定义（建议字段级落地）

```swift
// Domain/FitnessMetricType.swift
enum FitnessMetricType: String, CaseIterable, Sendable {
    case weight, sleep, nutrition, steps, workout
    case calories, standHour, exerciseTime
    case bloodOxygen, heartRate, bloodGlucose, bloodPressure
}

// Domain/FitnessMetricValue.swift
struct FitnessMetricValue: Equatable, Sendable {
    let type: FitnessMetricType
    /// 主数值（无数据为 nil）
    var value: Double?
    /// 展示单位（如 "KG"、"次/分钟"、"%"）
    let unit: String
    /// 最近一次数据时间（无数据为 nil）
    var timestamp: Date?
    /// 状态：正常 / 偏低 / 偏高 / 无数据（预留血氧「偏低」等徽标）
    var status: FitnessMetricStatus
    /// 附加标签（如步数 "768 / 10000"、运动 "羽毛球"、BMI "标准"）
    var label: String?
}

enum FitnessMetricStatus: Sendable {
    case normal, low, high, noData
}

// Domain/FitnessDashboardModels.swift
struct FitnessDashboard: Sendable {
    var isHealthKitAuthorized: Bool
    var metrics: [FitnessMetricValue]
}
```

`FitnessHomeViewModel` 持有 `state`（复用 Nutrition 的 `NutritionHomeState` 命名模式，本节定义 `FitnessHomeState`）：

```swift
// Presentation/Root/FitnessHomeState.swift
@MainActor
struct FitnessHomeState {
    var loadState: FitnessHomeLoadState = .idle
    var selectedMemberID: Int?
    var dashboard: FitnessDashboard?
}

enum FitnessHomeLoadState {
    case idle, loading, content(FitnessDashboard), error(String)
}
```

### 14.5 UseCase / ViewModel 方法签名（建议）

```swift
// Application/FitnessAuthorizationStateUseCase.swift
struct FitnessAuthorizationStateUseCase {
    let healthKitStore: FitnessHealthKitStore
    let logger: Logger
    /// 是否已经为当前成员授权读取（HealthKit 授权是设备级，非成员级；成员维度仅影响“是否显示”与刷新时机）
    func currentState() -> FitnessAuthorizationState { ... }
}

// Application/FitnessHealthKitSyncUseCase.swift
struct FitnessHealthKitSyncUseCase {
    let healthKitStore: FitnessHealthKitStore
    let logger: Logger
    /// 并发拉取 8 项 HealthKit 指标（步数/睡眠/运动/热量/站立/锻炼时长/血氧/心率），合并为 [FitnessMetricValue]
    func loadToday(now: Date) async throws -> [FitnessMetricValue]
}

// Application/FitnessDashboardUseCase.swift
struct FitnessDashboardUseCase {
    let profileStoreAdapter: FitnessProfileStoreAdapter      // 身材管理（档案）
    let healthKitSyncUseCase: FitnessHealthKitSyncUseCase
    let nutritionAdapter: FitnessNutritionAdapter            // 饮食热量（复用 Nutrition）
    let logger: Logger
    func loadDashboard(memberID: Int?, date: Date) async throws -> FitnessDashboard
}

// Presentation/Root/FitnessHomeViewModel.swift
@MainActor
final class FitnessHomeViewModel: ObservableObject {
    @Published private(set) var state = FitnessHomeState()
    private var loadTask: Task<Void, Never>?
    func loadIfNeeded() async { ... }   // 首次进入
    func reload() async { ... }         // 下拉/切换成员/回前台
    func setSelectedMember(_ id: Int?) { ... }
}
```

### 14.6 AppContainer / 装配改动点（真实注入路径）

1. 在 `FeatureAssemblies.swift` 新增 `FitnessFeatureDependencies`（含 `dashboardUseCase`、`healthKitSyncUseCase`、`authorizationStateUseCase`、`memberContextStore`、`logger`）及工厂 `makeFitnessDependencies(backend:memberContextStore:logger:)`。
2. `HomeFeatureDependencies` 增加 `fitnessDependencies: FitnessFeatureDependencies`，并在 `AppContainer.swift` 的 `homeDependencies` 组装处、以及 `FeatureAssemblies.swift` 的 `preview` 与正式组装处补上。
3. 在 `IOS26TabBarView`（`Projects/App/Sources/App/IOS26TabBarView.swift`）新增 `fitnessContainer` 与 `fitness` Tab，注入 `fitnessDependencies`（从 `homeDependencies` 或独立注入）。
4. `MainTabRouteDestinationBuilder` 根目标分支补 `.fitnessHome` → `EmptyView()`，或返回 `FitnessHomeView`（若详情也在 App 层路由）。
5. `AppRouteStore` 新增 `RootTab.fitness`（rawValue 9）、`AppRoute.fitnessHome` 及映射；`resetRouteGraph` / `defaultRootTab` 无需改（默认仍 `healthHome`）。

### 14.7 血氧异常阈值与「偏低/偏高」徽标规则（首版）

| 指标 | 正常 | 偏低 | 偏高 | 徽标 |
| --- | --- | --- | --- | --- |
| 血氧饱和度 | 95%–100% | < 95% | — | `偏低` |
| 安静心率 | 60–100 次/分 | < 60 | > 100 | 可先不显徽标，仅数值 |
| BMI | 18.5–23.9 | < 18.5 | ≥ 24 | 文案用「偏瘦」「正常」「超重」（档案侧已有则复用） |

首版仅血氧硬性要求「偏低」徽标（见 §6.2），心率/BMI 阈值规则此表作为实现参考，不强制上徽标。

### 14.8 本地化 key 清单（新增，需 en + zh-Hans 两份）

| key | 中文 | 英文 |
| --- | --- | --- |
| `tab.fitness` | 运动健康 | Fitness |
| `fitness.home.title` | 健康仪表盘 | Health Dashboard |
| `fitness.card.weight` | 身材管理 | Body Composition |
| `fitness.card.sleep` | 睡眠 | Sleep |
| `fitness.card.nutrition` | 饮食记录 | Nutrition |
| `fitness.card.steps` | 步数 | Steps |
| `fitness.card.workout` | 运动记录 | Workout |
| `fitness.card.calories` | 热量消耗 | Energy Burned |
| `fitness.card.stand_hour` | 站立小时数 | Stand Hours |
| `fitness.card.exercise_time` | 总锻炼时长 | Exercise Time |
| `fitness.card.blood_oxygen` | 血氧饱和度 | Blood Oxygen |
| `fitness.card.heart_rate` | 心率 | Heart Rate |
| `fitness.card.blood_glucose` | 血糖 | Blood Glucose |
| `fitness.card.blood_pressure` | 血压 | Blood Pressure |
| `fitness.data.no_data` | 暂无数据 | No Data |
| `fitness.auth.title` | 绑定苹果健康，解锁完整健康数据 | Connect Apple Health to unlock complete data |
| `fitness.auth.subtitle` | 授权后可查看步数/睡眠/心率/血氧等完整数据 | Authorize to view steps, sleep, heart rate, blood oxygen and more |
| `fitness.auth.action` | 去授权 | Authorize |
| `fitness.auth.later` | 稍后再说 | Later |
| `fitness.auth.coming_soon` | 该功能即将上线 | Coming soon |
| `fitness.privacy.hint` | 档案内容仅供您本人使用，我们将严格保护您的隐私安全 | Your data is for personal use only. We strictly protect your privacy. |
| `fitness.status.low` | 偏低 | Low |
| `fitness.status.high` | 偏高 | High |

### 14.9 Fitness 模块内路由（首版尽量精简）

`FitnessRoute` / `FitnessNavigationDestination` 首版仅需一个根：

```swift
enum FitnessRoute: Hashable, Sendable { case home }
```

各指标详情页留待后续工单，本期内点击卡片统一走「敬请期待」Toast（血糖/血压）或空实现，不预定义一堆详情 route，避免过度设计。

### 14.10 容错与性能落地要点

1. **单项失败不阻塞整体**：`FitnessHealthKitSyncUseCase.loadToday` 内部对 8 项指标各用独立 `async let`（`withTaskGroup`）并发查询，单项失败捕获后置为 `noData`，其余正常返回，最终仍返回 `FitnessDashboard(authorized:metrics:)`。
2. **授权态判定**：设备是否支持用 `HKHealthStore.isHealthDataAvailable()`；是否已授权用 `healthStore.authorizationStatus(for: type)` 对所有类型取 `notDetermined` 判定（任一核心类型未授权 → 走「未绑定」态）。
3. **不阻塞主线程**：所有 HealthKit 查询走 `async`；`@MainActor` 只在 ViewModel 更新 `@Published` 时切换。
4. **成员切换竞态**：`reload()` 先 `loadTask?.cancel()`（沿用 `NutritionHomeViewModel` 的防竞态模式），避免旧成员数据覆盖新成员。
5. **回前台刷新**：`.onReceive(UIApplication.didBecomeActiveNotification)` 或 SwiftUI `.scenePhase` 变化时 `reload()`。
6. **权限弹窗次数**：HealthKit 系统授权弹窗只在用户主动点击「去授权」或首次进入引导卡时触发，不做加载时自动弹授权窗（避免打断）。
7. **日志**：统一 `logger.info/warning/error(message, module: .fitness)`，查询失败打 `warning` 不报 `error`（授权未决、无数据属可预期）。

### 14.11 Preview 覆盖清单

1. **已授权全量态**：`FitnessDashboard(authorized:true, metrics: 12项含数值)`，浅色 + 深色。
2. **未授权空态**：`FitnessDashboard(authorized:false, metrics: 身材管理有/无数据两种 + 其余 noData)`，含引导卡与隐私提示。
3. **血氧偏低态**：其中血氧 `status = .low`，验证「偏低」徽标渲染。
4. Preview 依赖用 `AppContainer.preview` 或专门构造 `FitnessFeatureDependencies.preview`，不直连真实 HealthKit。
