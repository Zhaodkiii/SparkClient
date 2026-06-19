# NUTRITION-000024 成员建档饮食健康去完善与首页模块展示工单

> 文档性质：独立工单需求与详设稿。本文参考 `NUTRITION-000023 饮食目标与身体指标统一计算`，聚焦“新建成员流程内的饮食健康去完善”。本工单不重新定义统一计算公式，而是明确成员建档场景如何使用计算结果预填摄入目标、消耗目标、营养目标，并控制用户修改值在正常范围内，同时明确首页医疗/饮食模块按成员启用状态展示。

## 一、工单背景

`NUTRITION-000023` 已经定义了统一人体能量模型：

```text
成员资料 / 目标草稿
-> 性别、年龄、身高、当前体重
-> 活跃水平、目标模式、每周目标
-> BMI、理想体重范围、BMR、TDEE、建议摄入、消耗解释
```

但在新建成员流程里，用户进入 `饮食健康 -> 去完善` 时，需要的是更贴近建档的体验：

1. 用户刚刚填写了姓名、生日/年龄、关系、性别。
2. 进入模块选择页时成员已经创建完成，客户端已经拿到 `memberID`。
3. 用户点击饮食健康 `去完善`。
4. 系统根据用户输入的基础信息自动预填：
   - 当前体重相关输入。
   - 活跃水平默认值。
   - 目标模式默认值。
   - 每日摄入目标。
   - 每日消耗估算。
   - 碳水/蛋白质/脂肪目标。
5. 用户最后可以修改这些目标，但不能改出明显不合理的极端值。
6. 保存后首页只展示该成员开启的模块，例如只开启饮食健康就展示饮食健康，不展示医疗模块。

本工单解决的是“建档场景的使用方式和防护边界”，不是“公式本身”。

## 二、目标

1. 新建成员内 `饮食健康 -> 去完善` 使用分步页面维护，不使用单页大表单。
2. 进入饮食健康去完善时，基于成员基础信息和默认策略自动生成目标草稿。
3. 自动生成的关键数据包括：
   - 摄入目标：每日卡路里、碳水、蛋白质、脂肪。
   - 消耗估算：BMR、TDEE、日常活动消耗。
   - 体重目标：目标模式、每周体重变化。
   - 餐次分布：早餐、午餐、晚餐、小吃占比。
4. 用户可以手动修改目标值。
5. 用户修改值需要被限制在正常常规范围内，避免出现百万级热量、1000kg 每周目标等异常值。
6. 保存时立即写入 `NutritionGoal`，并更新 `MemberModuleSetting(module_code=nutrition)`。
7. 首页根据成员模块启用状态展示 `medicalInfoSection`、`nutritionInfoSection`。
8. 首页模块排序后续由服务端 `display_order` 控制，第一期客户端可先按医疗、饮食固定顺序展示。

## 三、非目标

第一期不做：

1. 不新增一套独立饮食目标公式。
2. 不把建档页里的草稿保存为本地长期数据。
3. 不做儿童、孕期、哺乳期、慢病特殊公式。
4. 不做模块级 AI 权限。
5. 不做“关闭模块后删除历史数据”。
6. 不做首页模块的服务端动态布局渲染系统。
7. 不做日常健康模块展示，日常健康仍仅保留代码预留。

## 四、与 NUTRITION-000023 的关系

| 项目 | NUTRITION-000023 | NUTRITION-000024 |
| --- | --- | --- |
| 关注点 | 统一计算模型和目标页能力 | 新建成员饮食健康去完善落地 |
| 入口 | 我的目标、总结详情、饮食首页 | 新建成员 -> 选择维护模块 -> 饮食健康去完善 |
| 核心能力 | BMI、BMR、TDEE、摄入目标、消耗解释 | 基于建档信息预填目标草稿、限制用户输入、保存模块状态 |
| 数据保存 | `NutritionGoal` | `NutritionGoal` + `MemberModuleSetting` |
| 首页影响 | 看板使用目标值 | 首页按模块启用状态展示饮食/医疗模块 |

本工单应复用 `NUTRITION-000023` 的计算接口和安全边界，不重复实现公式。

## 五、客户端业务流程

### 5.1 主流程

```text
新建成员 Step 1
-> 填写姓名、出生日期/年龄
-> 下一步

新建成员 Step 2
-> 填写关系、性别
-> 下一步
-> 客户端调用创建成员接口
-> 服务端返回 memberID

新建成员 Step 3
-> 选择维护模块
-> 开启饮食健康
-> 点击 去完善
-> 打开 MemberNutritionSetupSheet
-> 根据成员基础信息生成饮食目标草稿
-> 用户分步确认/修改
-> 点击保存
-> 保存 NutritionGoal
-> 更新 MemberModuleSetting(module_code=nutrition)
-> 返回模块选择页
-> 饮食健康显示 已完成
-> 完成建档
-> 首页刷新成员模块配置
-> 首页只展示已开启模块
```

### 5.2 去完善打开方式

| 位置 | 操作 | 打开方式 |
| --- | --- | --- |
| `MemberModuleSetupView` | 点击饮食健康 `去完善` | sheet |
| `MemberNutritionSetupSheet` 内部 | 下一步 / 跳过 / 返回 | 对齐 `MedicationPlanStepperView` |
| 最终保存 | 点击保存 | 立即调用接口并关闭 sheet |

参考文件：

```text
SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift
SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Nutrition/MemberNutritionSetupSheet.swift
SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Nutrition/MemberNutritionSetupViewModel.swift
```

## 六、饮食健康去完善页面设计

### 6.1 页面结构

饮食健康去完善不做一页大表单，使用分步页面：

```text
MemberNutritionSetupSheet
├─ Step 1 基础信息
├─ Step 2 目标模式
├─ Step 3 摄入与消耗
├─ Step 4 营养目标
└─ Step 5 完成总结
```

说明：

1. `Step 1` 和成员基础信息不同，饮食健康里的基础信息只保存营养计算所需字段。
2. 身高不进入 `Member` 基础字段，只属于饮食目标计算输入。
3. 当前体重、目标体重、活跃水平用于计算，不作为医疗成员基础资料。
4. 摄入目标和消耗估算由系统根据输入自动生成。
5. 用户可以手动修改最终目标。

### 6.2 Step 1 基础信息

```text
┌────────────────────────────┐
│ ←        饮食健康       跳过 │
├────────────────────────────┤
│ 步骤 1 / 5                  │
│ 完善身体信息，用于计算目标   │
├────────────────────────────┤
│ 身高                  160 cm │
├────────────────────────────┤
│ 当前体重              60.0 kg│
├────────────────────────────┤
│ 目标体重              58.0 kg│
├────────────────────────────┤
│ 活跃水平                  中 >│
├────────────────────────────┤
│                            │
│          下一步             │
└────────────────────────────┘
```

字段说明：

| 字段 | 来源 | 默认值策略 | 可修改 | 正常范围 |
| --- | --- | --- | --- | --- |
| 身高 | 饮食健康草稿 | 无历史值时默认 160cm | 是 | 80cm - 230cm |
| 当前体重 | 饮食健康草稿 | 无历史值时默认 60kg | 是 | 20kg - 300kg |
| 目标体重 | 饮食健康草稿 | 默认等于当前体重 | 是 | 20kg - 300kg |
| 活跃水平 | 草稿 | 默认中 | 是 | 低/中/高/很高 |

### 6.3 Step 2 目标模式

```text
┌────────────────────────────┐
│ ←        目标模式       跳过 │
├────────────────────────────┤
│ 步骤 2 / 5                  │
│ 选择你希望达成的饮食目标     │
├────────────────────────────┤
│ ☑ 保持体重                  │
│ ☐ 减重                      │
│ ☐ 增重                      │
│ ☐ 打造肌肉                  │
│ ☐ 控糖                      │
│ ☐ 控盐                      │
│ ☐ 控脂                      │
│ ☐ 自定义                    │
├────────────────────────────┤
│ 每周目标              0.00 kg│
├────────────────────────────┤
│                            │
│          下一步             │
└────────────────────────────┘
```

目标模式建议：

| 目标模式 | weeklyWeightDelta 默认 | 输入限制 |
| --- | --- | --- |
| 保持体重 | 0 | 固定 0 |
| 减重 | -0.50kg/周 | -1.00 到 0 |
| 增重 | +0.25kg/周 | 0 到 +1.00 |
| 打造肌肉 | +0.25kg/周 | 0 到 +1.00 |
| 控糖 | 0 | 固定 0 |
| 控盐 | 0 | 固定 0 |
| 控脂 | 0 | 固定 0 |
| 自定义 | 0 | -1.00 到 +1.00 |

### 6.4 Step 3 摄入与消耗

```text
┌────────────────────────────┐
│ ←        摄入与消耗     跳过 │
├────────────────────────────┤
│ 步骤 3 / 5                  │
│ 已根据身体信息生成建议值     │
├────────────────────────────┤
│ 每日摄入目标          1995 kcal│
├────────────────────────────┤
│ 基础代谢              1350 kcal│
├────────────────────────────┤
│ 维持消耗              1995 kcal│
├────────────────────────────┤
│ 日常活动消耗           645 kcal│
├────────────────────────────┤
│ 重新计算目标              ↻  │
├────────────────────────────┤
│                            │
│          下一步             │
└────────────────────────────┘
```

关键说明：

1. `每日摄入目标` 是用户最终要吃多少，来自 `TDEE + 目标热量差`。
2. `基础代谢` 是 BMR。
3. `维持消耗` 是 TDEE。
4. `日常活动消耗` 是 `TDEE - BMR` 的估算解释。
5. 这些值由用户输入的基本信息计算得来。
6. 用户可以修改每日摄入目标，但不能超出正常范围。

范围控制：

| 字段 | 正常范围 | 超出处理 |
| --- | --- | --- |
| 每日摄入目标 | 0 - 10000 kcal | 保存前 clamp；服务端超过返回 400 |
| 基础代谢 | 只读 | 不允许手动编辑 |
| 维持消耗 | 只读 | 不允许手动编辑 |
| 日常活动消耗 | 只读 | 不允许手动编辑 |

### 6.5 Step 4 营养目标

```text
┌────────────────────────────┐
│ ←        营养目标       跳过 │
├────────────────────────────┤
│ 步骤 4 / 5                  │
│ 可调整每日三大营养素比例     │
├────────────────────────────┤
│ 碳水化合物              50%  │
│ 约 249 g                    │
├────────────────────────────┤
│ 蛋白质                  20%  │
│ 约 100 g                    │
├────────────────────────────┤
│ 脂肪                    30%  │
│ 约 67 g                     │
├────────────────────────────┤
│ 合计                    100% │
├────────────────────────────┤
│                            │
│          下一步             │
└────────────────────────────┘
```

比例控制：

| 字段 | 正常范围 |
| --- | --- |
| 碳水化合物比例 | 5% - 80% |
| 蛋白质比例 | 5% - 50% |
| 脂肪比例 | 5% - 60% |
| 三项合计 | 必须为 100% |

克数换算：

```text
碳水克数 = 每日摄入目标 * 碳水比例 / 100 / 4
蛋白质克数 = 每日摄入目标 * 蛋白比例 / 100 / 4
脂肪克数 = 每日摄入目标 * 脂肪比例 / 100 / 9
```

服务端兜底：

| 字段 | 服务端上限 |
| --- | --- |
| carbohydrate_target_g | 2000g |
| protein_target_g | 2000g |
| fat_target_g | 2000g |

### 6.6 Step 5 完成总结

```text
┌────────────────────────────┐
│ ←        饮食健康           │
├────────────────────────────┤
│ 步骤 5 / 5                  │
│ 请确认以下目标              │
├────────────────────────────┤
│ 已填写内容                  │
│ 160cm · 60.0kg · 中         │
│ 保持体重 · 1995 kcal        │
│ 碳水 50% · 蛋白质 20% · 脂肪 30%│
├────────────────────────────┤
│ 基础信息              已完成 │
│ 160cm · 60.0kg · 中         │
├────────────────────────────┤
│ 目标模式              已完成 │
│ 保持体重 · 1995 kcal        │
├────────────────────────────┤
│ 营养目标              已完成 │
│ 碳水 50% · 蛋白质 20% · 脂肪 30%│
├────────────────────────────┤
│ 跳过                 保存   │
└────────────────────────────┘
```

点击保存：

```text
校验目标草稿
-> clamp 可自动修正字段
-> 不可修正字段提示用户
-> 调用 NutritionGoal 保存接口
-> 调用 MemberModuleSetting 保存接口
-> 返回模块选择页
```

## 七、计算与预填规则

### 7.1 输入来源

| 输入 | 来源 |
| --- | --- |
| memberID | 新建成员成功后返回 |
| 性别 | 成员关系性别页 |
| 年龄 | 出生日期推导 |
| 身高 | 饮食健康 Step 1 |
| 当前体重 | 饮食健康 Step 1 |
| 目标体重 | 饮食健康 Step 1 |
| 活跃水平 | 饮食健康 Step 1 |
| 目标模式 | 饮食健康 Step 2 |
| 每周目标 | 饮食健康 Step 2 |

### 7.2 计算输出

| 输出 | 说明 | 用途 |
| --- | --- | --- |
| BMR | 基础代谢 | Step 3 只读展示 |
| TDEE | 维持消耗 | Step 3 只读展示 |
| estimatedActivity | TDEE - BMR | Step 3 只读展示 |
| dailyEnergyTarget | 建议每日摄入 | Step 3 可修改 |
| carbohydrateTargetG | 碳水目标克数 | Step 4 / 看板 |
| proteinTargetG | 蛋白质目标克数 | Step 4 / 看板 |
| fatTargetG | 脂肪目标克数 | Step 4 / 看板 |
| mealDistribution | 餐次分布 | 看板餐次目标 |

### 7.3 正常范围控制

客户端和服务端都要做限制。

客户端：

1. 输入时尽量限制键盘和步进范围。
2. 进入下一步前做一次 normalize。
3. 点击保存前再做一次 normalize。
4. 读取旧缓存或旧服务端数据时也要 normalize，避免脏值回填 UI。

服务端：

1. 接收 `POST /api/v1/nutrition/goals/` 时校验。
2. 接收计算接口时校验 `weekly_weight_delta_kg`。
3. 对 dashboard/defaults 读取结果做安全夹取，避免旧脏数据继续扩散。
4. 目标相关 ETag 需要包含规则版本，避免客户端继续 304 命中旧响应体。

异常案例：

| 异常输入 | 处理 |
| --- | --- |
| weeklyWeightDeltaKg = 1000 | 客户端 clamp；服务端 400 |
| dailyEnergyTargetKcal = 1103745 | 客户端 clamp；服务端 400 |
| carbohydrateTargetG = 134441 | 客户端 clamp；服务端 400 |
| 控盐目标 weeklyWeightDeltaKg = 1 | 客户端改为 0；服务端 400 |
| 减重目标 weeklyWeightDeltaKg = +0.5 | 客户端改为 0；服务端 400 |

## 八、服务端接口

### 8.1 读取目标状态

```text
GET /api/v1/nutrition/goals/?member_id={memberID}
```

用途：

1. 进入饮食健康去完善时读取已有目标。
2. 有目标则回填。
3. 没有目标则读取 defaults。

### 8.2 计算身体指标和目标

```text
POST /api/v1/nutrition/goals/calculate-body-metrics/
```

请求核心字段：

```json
{
  "member_id": 100,
  "goal_type": "maintain",
  "activity_level": "medium",
  "current_weight_kg": 60,
  "target_weight_kg": 60,
  "height_cm": 160,
  "biological_sex": "female",
  "age_years": 58,
  "weekly_weight_delta_kg": 0
}
```

返回核心字段：

```json
{
  "bmi": {},
  "ideal_weight": {},
  "calorie_intake": {
    "suggested_energy_kcal": 1995,
    "bmr_kcal": 1350,
    "tdee_kcal": 1995,
    "energy_delta_kcal": 0
  },
  "calories_burned": {
    "bmr_kcal": 1350,
    "tdee_kcal": 1995,
    "estimated_daily_activity_kcal": 645
  },
  "missing_fields": [],
  "warnings": [],
  "calculation_inputs": {}
}
```

### 8.3 保存目标

```text
POST /api/v1/nutrition/goals/
```

保存内容：

1. 目标模式。
2. 身高、当前体重、目标体重。
3. 活跃水平、每周目标。
4. BMR、TDEE、energyDelta。
5. 每日摄入目标。
6. 三大营养素目标。
7. 餐次分布。
8. 计算快照。

### 8.4 保存模块状态

```text
POST /api/v1/medical/members/{memberID}/modules/
```

或项目内已有模块设置接口。

保存内容：

```json
{
  "module_code": "nutrition",
  "is_enabled": true,
  "is_completed": true,
  "display_order": 20,
  "summary_text": "保持体重 · 1995千卡",
  "detail_data": {
    "height_cm": "160.0",
    "weight_kg": "60.0",
    "activity_level": "medium",
    "goal_mode": "maintain",
    "weekly_target_kg": "0.00",
    "target_calories": "1995.0",
    "carbohydrate_percent": "50.0",
    "protein_percent": "20.0",
    "fat_percent": "30.0"
  }
}
```

## 九、数据模型影响

### 9.1 NutritionGoal

继续使用 `NUTRITION-000023` 的 `NutritionGoal`。

需要重点使用字段：

| 字段 | 用途 |
| --- | --- |
| member | 成员维度目标 |
| goal_type | 目标模式 |
| height_cm | 饮食健康身高快照 |
| current_weight_kg | 当前体重快照 |
| target_weight_kg | 目标体重 |
| biological_sex | 性别快照 |
| age_years | 年龄快照 |
| activity_level | 活跃水平 |
| weekly_weight_delta_kg | 每周目标 |
| bmr_kcal | 基础代谢 |
| tdee_kcal | 维持消耗 |
| energy_delta_kcal | 每日热量差 |
| calculation_inputs | 计算输入和风险快照 |
| daily_energy_target_kcal | 每日摄入目标 |
| carbohydrate_target_g | 碳水目标 |
| protein_target_g | 蛋白质目标 |
| fat_target_g | 脂肪目标 |
| meal_distribution | 餐次分布 |

### 9.2 MemberModuleSetting

用于控制首页模块是否展示。

建议字段：

| 字段 | 用途 |
| --- | --- |
| member | 成员 |
| module_code | `medical` / `nutrition` |
| is_enabled | 是否开启 |
| is_completed | 是否完成维护 |
| display_order | 首页排序 |
| summary_text | 模块摘要 |
| detail_data | 模块轻量摘要数据 |
| completed_at | 完成时间 |

饮食健康保存成功后：

```text
module_code = nutrition
is_enabled = true
is_completed = true
summary_text = 目标模式 + 热量目标
```

## 十、首页模块展示

当前首页代码位置：

```text
SparkClient/Projects/Features/Home/Presentation/HomeView.swift
```

现状片段：

```swift
medicalInfoSection          // 医疗
nutritionInfoSection        // 营养
```

目标：

```text
首页根据当前选中成员的模块配置展示模块。
```

建议逻辑：

```swift
if viewModel.isModuleEnabled(.medical) {
    medicalInfoSection
}

if viewModel.isModuleEnabled(.nutrition) {
    nutritionInfoSection
}
```

展示规则：

| 模块状态 | 首页展示 |
| --- | --- |
| is_enabled = true, is_completed = true | 展示模块 |
| is_enabled = true, is_completed = false | 可展示模块，但显示待完善入口 |
| is_enabled = false | 不展示模块 |
| 无模块配置 | 不展示，或只对本人/默认成员按推荐展示待开启入口，第一期建议不展示 |

第一期建议：

1. 首页只展示已开启模块。
2. `is_enabled=true` 但未完成时，可以展示轻量卡片和 `去完善`。
3. 医疗模块和饮食健康模块都开启时，按 `display_order` 排序；若客户端暂未接排序，先固定医疗在前、饮食在后。
4. 切换成员后重新判断模块配置。

## 十一、客户端涉及文件

| 文件 | 改动 |
| --- | --- |
| `HomeView.swift` | `medicalInfoSection`、`nutritionInfoSection` 按模块启用状态展示 |
| `HomeViewModel.swift` | 持有当前成员模块配置，提供 `isModuleEnabled` |
| `MemberModuleSetupView.swift` | 饮食健康 `去完善` 打开 `MemberNutritionSetupSheet` |
| `MemberNutritionSetupSheet.swift` | 分步 sheet，步骤数扩展为基础信息、目标模式、摄入消耗、营养目标、完成总结 |
| `MemberNutritionSetupViewModel.swift` | 目标草稿、计算调用、输入范围限制、保存 `NutritionGoal` 和模块状态 |
| `MemberNutritionBodyInfoStepView.swift` | 身高、体重、活跃水平输入 |
| `MemberNutritionGoalStepView.swift` | 目标模式、每周目标输入 |
| 新增 `MemberNutritionEnergyStepView.swift` | 摄入目标、BMR、TDEE、日常活动消耗展示和重新计算 |
| `MemberNutritionMacroGoalStepView.swift` | 碳水/蛋白/脂肪比例与克数 |
| 新增 `MemberNutritionSetupSummaryView.swift` | 完成总结页 |
| `NutritionGoalUseCase.swift` | 复用目标计算、保存和安全 normalize |

## 十二、服务端涉及文件

| 文件 | 改动 |
| --- | --- |
| `nutrition/serializers.py` | `NutritionGoalUpsertSerializer`、`NutritionGoalCalculationSerializer` 校验目标范围 |
| `nutrition/services/goal_calculation_service.py` | 继续提供统一计算 |
| `nutrition/services/goal_service.py` | 读取目标时安全夹取旧异常值 |
| `nutrition/http_cache.py` | 目标相关 ETag 包含规则版本 |
| `nutrition/views.py` | 目标读取/保存/计算接口 |
| `medical/models.py` | `MemberModuleSetting` 模块状态 |
| `medical/views.py` | 模块状态保存接口 |

## 十三、日志

客户端日志建议：

```text
成员建档饮食健康：打开去完善 memberID=100
成员建档饮食健康：目标草稿初始化 source=member_profile height=160 weight=60 goal=maintain
成员建档饮食健康：重新计算开始 memberID=100 goal=maintain activity=medium
成员建档饮食健康：重新计算成功 energy=1995 bmr=1350 tdee=1995
成员建档饮食健康：输入值已规范化 field=weeklyTarget old=1000 new=0
成员建档饮食健康：保存目标开始 memberID=100
成员建档饮食健康：保存目标成功 memberID=100 goalID=1
成员建档饮食健康：模块状态更新成功 memberID=100 module=nutrition completed=true
首页模块：根据模块配置展示 memberID=100 modules=medical,nutrition
```

服务端日志建议：

```text
nutrition.goal_calculate_body_metrics user_id=1 member_id=100 goal_type=maintain
nutrition.goal_upsert user_id=1 member_id=100 goal_id=1 goal_type=maintain
medical.member_module_upsert user_id=1 member_id=100 module=nutrition enabled=true completed=true
```

## 十四、本地化

新增 key 建议：

| key | 默认中文 |
| --- | --- |
| `member.setup.nutrition.title` | 饮食健康 |
| `member.setup.nutrition.body_info.title` | 基础信息 |
| `member.setup.nutrition.goal.title` | 目标模式 |
| `member.setup.nutrition.energy.title` | 摄入与消耗 |
| `member.setup.nutrition.macro.title` | 营养目标 |
| `member.setup.nutrition.summary.title` | 完成总结 |
| `member.setup.nutrition.recalculate` | 重新计算目标 |
| `member.setup.nutrition.daily_intake` | 每日摄入目标 |
| `member.setup.nutrition.bmr` | 基础代谢 |
| `member.setup.nutrition.tdee` | 维持消耗 |
| `member.setup.nutrition.activity_burn` | 日常活动消耗 |
| `member.setup.nutrition.value_clamped` | 已调整到合理范围 |
| `home.module.medical` | 医疗 |
| `home.module.nutrition` | 饮食健康 |

## 十五、验收标准

### 15.1 新建成员饮食健康

1. 创建成员后进入模块选择页，已经持有 `memberID`。
2. 点击饮食健康 `去完善` 使用 sheet 打开分步页面。
3. 分步页面不是一页大表单。
4. 基础信息、目标模式、摄入与消耗、营养目标、完成总结可以按步骤前进。
5. 每一步支持跳过。
6. 摄入目标和消耗估算能根据用户输入的基础信息生成。
7. 用户可以修改每日摄入目标和营养比例。
8. 极端输入会被客户端限制或保存前修正。
9. 保存时写入 `NutritionGoal`。
10. 保存成功后写入 `MemberModuleSetting(module_code=nutrition)`。
11. 保存失败时不重复创建成员。

### 15.2 数值边界

1. `weeklyWeightDeltaKg=1000` 不会进入服务端保存。
2. `dailyEnergyTargetKcal=1103745` 不会进入服务端保存。
3. 控糖、控盐、控脂、保持体重的每周目标保存为 `0`。
4. 减重目标不能保存正每周目标。
5. 增重/打造肌肉不能保存负每周目标。
6. 宏量营养克数不会出现十万级异常值。

### 15.3 首页展示

1. 当前成员未开启医疗模块时，首页不展示医疗模块。
2. 当前成员未开启饮食健康模块时，首页不展示饮食健康模块。
3. 当前成员开启饮食健康后，首页展示饮食健康模块。
4. 切换成员后首页模块随成员配置变化。
5. 模块排序优先使用 `display_order`；未接入排序时医疗在前、饮食在后。

## 十六、实施阶段

### 阶段一：饮食健康去完善分步补齐

1. 拆分 `MemberNutritionSetupSheet` 页面。
2. 新增摄入与消耗步骤。
3. 新增完成总结步骤。
4. 下一步、跳过、返回交互对齐 `MedicationPlanStepperView`。

### 阶段二：目标草稿计算与范围控制

1. 进入 sheet 初始化目标草稿。
2. 调用 `calculate-body-metrics`。
3. 展示 BMR、TDEE、日常活动消耗。
4. 保存前 normalize 目标值。
5. 服务端兜底校验异常值。

### 阶段三：保存闭环

1. 保存 `NutritionGoal`。
2. 保存 `MemberModuleSetting(module_code=nutrition)`。
3. 返回模块选择页，显示饮食健康已完成。
4. 最后完成成员建档时不重复提交饮食健康。

### 阶段四：首页模块展示

1. `HomeViewModel` 拉取/持有成员模块配置。
2. `HomeView` 根据模块配置展示医疗和饮食健康。
3. 切换成员刷新模块展示。
4. 后续支持 `display_order` 排序。

## 十七、风险与注意点

1. 不要把身高放入成员基础资料，身高仅属于饮食目标计算输入。
2. 不要让 `NutritionGoal` 异常值污染首页 dashboard。
3. 不要把 BMR/TDEE 当成事实消耗，它们只是估算解释。
4. Apple 健康和手动消耗仍然是事实消耗数据。
5. 首页不要固定展示所有模块，否则和成员模块配置目标冲突。
6. `is_enabled=true` 但 `is_completed=false` 的展示策略需要产品确认；第一期可展示待完善入口。
7. 模块保存失败时不能回滚成员创建，但需要允许用户重试完善模块。

## 十八、关联工单

1. `NUTRITION-000023`：饮食目标与身体指标统一计算。
2. `NUTRITION-000010`：饮食营养首页与看板展示。
3. `NUTRITION-000008`：能量消耗与 Apple 健康同步接口。
4. `NUTRITION-000017`：本地化、日志、错误态与测试验收。
5. `成员建档与模块维护需求讨论文档`：成员创建、模块选择、模块状态保存。
