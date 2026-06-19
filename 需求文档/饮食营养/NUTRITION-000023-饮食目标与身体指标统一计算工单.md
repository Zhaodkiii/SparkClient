# NUTRITION-000023 饮食目标与身体指标统一计算工单

> 文档性质：独立工单需求与详设稿。本文整理今天对话新增内容，参考 YAZIO 的 BMI、理想体重、每日卡路里摄入、卡路里消耗四类计算器，抽象为项目内“统一人体能量模型 + 体重模型 + 多输出切面”。本文覆盖客户端业务流程、UI 设计、服务端接口、数据存储、算法流程、日志、本地化和验收标准。

## 一、工单背景

参考页面：

1. [身体质量指数 BMI 计算器](https://www.yazio.com/en/bmi-calculator)
2. [理想体重计算器](https://www.yazio.com/en/ideal-weight-calculator)
3. [每日卡路里摄入量计算器](https://www.yazio.com/en/calorie-intake-calculator)
4. [卡路里消耗计算器](https://www.yazio.com/en/calories-burned-calculator)

YAZIO 这类计算器的优秀点不是做了四个独立公式页面，而是把同一套人体模型拆成不同的用户问题入口：

```text
我现在身体状态如何？ -> BMI
我的目标体重是否合理？ -> 理想体重范围
我每天应该吃多少？ -> 卡路里摄入目标
我每天大概消耗多少？ -> BMR / TDEE / 活动消耗解释
```

项目内不建议第一期直接照搬四个独立计算器页面，而是融入饮食营养目标设置、总结详情、AI 对话上下文。

## 二、目标

本工单目标：

1. 建立统一身体指标与目标计算流程。
2. 支持从成员档案和目标草稿计算 BMI、理想体重范围、BMR、TDEE、建议卡路里目标、消耗估算解释。
3. 在客户端 `我的目标` 页面提供“重新计算卡路里目标”的完整闭环。
4. 在计算结果页用 plain text UI 方式展示计算依据和建议结果。
5. 服务端提供统一计算接口，避免客户端硬编码公式。
6. `NutritionGoal` 保存最终目标和最近一次计算快照。
7. 看板与 AI 对话可读取计算结果作为解释上下文。

## 三、非目标

第一期不做：

1. 不做独立 `BMI 计算器` 页面。
2. 不做独立 `理想体重计算器` 页面。
3. 不做独立 `每日卡路里摄入量计算器` 页面。
4. 不做独立 `卡路里消耗计算器` 页面。
5. 不把 BMI、理想体重、BMR、TDEE 建成独立事实表。
6. 不用 TDEE 替代 Apple 健康或手动记录的真实消耗。
7. 不做儿童、孕期、哺乳期、慢病专用公式，只做风险提示和后续预留。

## 四、总体设计

### 4.1 统一模型

```text
成员档案 / 目标草稿
  -> 性别、年龄、身高、当前体重
  -> 活跃水平
  -> 目标模式、每周目标
  -> 身体指标计算
      -> BMI
      -> 理想体重范围
      -> BMR
      -> TDEE
      -> 建议卡路里目标
      -> 消耗估算解释
```

### 4.2 四个输出切面

| 输出 | 作用 | 是否事实数据 |
| --- | --- | --- |
| BMI | 展示当前体重状态标签 | 否，公式估算 |
| 理想体重范围 | 判断目标体重是否合理 | 否，公式估算 |
| 建议摄入 | 生成每日卡路里目标 | 否，系统建议 |
| 消耗估算 | 解释 BMR/TDEE 与活动消耗 | 否，估算解释 |

事实数据仍来自：

1. 饮食记录：`NutritionMealRecord` / `NutritionIntake`
2. Apple 健康能量消耗：`NutritionEnergyBurnRecord.apple_health_id`
3. 家庭成员手动消耗：`NutritionEnergyBurnRecord`

## 五、客户端业务流程

### 5.1 入口

入口一：饮食营养首页更多菜单。

```text
饮食营养首页
-> 更多
-> 我的目标
```

入口二：总结详细页。

```text
总结模块
-> 详细信息
-> 目标区域
-> 我的目标
```

入口三：首次进入饮食营养且无目标。

```text
首次进入饮食营养
-> 服务端返回默认目标
-> 页面提示“可设置你的目标”
-> 进入我的目标
```

入口四：新建成员流程中的饮食健康模块。

```text
新建成员
-> 姓名生日页
-> 关系性别页
-> 创建成员并获得 memberID
-> 选择维护模块
-> 开启饮食健康
-> 去完善
-> MemberNutritionSetupSheet
-> 分步维护身体信息、目标设置、营养目标
-> 保存 NutritionGoal
-> 更新 MemberModuleSetting(module_code=nutrition)
```

关联文档：

```text
需求文档/成员管理/成员建档与模块维护需求讨论文档.md
```

说明：

1. 进入饮食健康模块前，成员必须已经创建成功并获得 `memberID`。
2. 饮食健康模块不等待成员建档最后统一提交。
3. 饮食健康 sheet 点击完成后立即保存 `NutritionGoal`。
4. 保存成功后更新 `MemberModuleSetting(module_code=nutrition)`。
5. 最后完成成员建档流程时，只刷新首页和成员模块配置，不再重复提交饮食目标。

### 5.2 完整流程

```text
进入我的目标
-> 拉取当前成员 NutritionGoal
-> 生成 NutritionGoalDraft
-> 用户点击卡路里目标
-> 用户点击重新计算卡路里目标
-> 客户端提交 NutritionEnergyCalculationRequest 或统一身体指标计算请求
-> 服务端返回 NutritionBodyMetricsCalculationResponse
-> 客户端展示计算结果页
-> 用户点击使用建议目标
-> 回写 NutritionGoalDraft
-> 用户返回我的目标并点击保存
-> 客户端提交 NutritionGoalUpdateRequest
-> 服务端保存新的 NutritionGoal active 版本
-> 客户端刷新 dashboard
-> 总结、营养、餐次目标、AI 上下文使用新目标
```

### 5.2.1 新建成员内的饮食健康分步流程

新建成员中的饮食健康不是一页大表单，而是参考 `MedicationPlanStepperView` 的分步 sheet。

```text
MemberNutritionSetupSheet
├─ Step 1 身体信息
├─ Step 2 目标设置
└─ Step 3 营养目标
```

步骤说明：

| 步骤 | 页面 | 内容 | 是否可跳过 | 保存 |
| --- | --- | --- | --- | --- |
| Step 1 | `MemberNutritionBodyInfoStepView` | 身高、当前体重、目标体重、活跃水平 | 可跳过 | 写入目标草稿 |
| Step 2 | `MemberNutritionGoalStepView` | 减重、保持体重、增重、打造肌肉、自定义 | 可跳过 | 写入目标草稿 |
| Step 3 | `MemberNutritionMacroGoalStepView` | 卡路里目标、营养目标、餐次分布 | 可跳过 | 点击完成时保存 `NutritionGoal` |

交互规则：

1. 每一步只维护一组信息。
2. 非必填步骤支持 `跳过`。
3. 跳过后模块状态可以保持 `enabled_pending`。
4. 只要用户保存了有效目标，模块状态更新为 `enabled_completed`。
5. 如果用户关闭 sheet 且有未保存草稿，需要二次确认。
6. 如果保存失败，只提示饮食健康模块保存失败，不重复创建成员。

### 5.3 缺失资料流程

```text
点击重新计算
-> 服务端返回 missing_fields
-> 客户端展示缺失资料页
-> 用户补充身高 / 当前体重 / 生理性别 / 年龄
-> 再次提交计算
```

第一期需要支持缺失字段：

| 字段 | 缺失处理 |
| --- | --- |
| 当前体重 | 在目标页补充 |
| 身高 | 在目标补充页填写，不一定回写成员档案 |
| 年龄 | 优先由成员生日推导；缺失时提示补充生日或年龄 |
| 生理性别 | 优先成员档案；缺失时提示补充 |

## 六、客户端 UI 设计

### 6.1 我的目标页面

```text
┌────────────────────────────┐
│ ←          我的目标         │
├────────────────────────────┤
│ 目标                  减重 >│
├────────────────────────────┤
│ 起始体重          65.0 千克 >│
├────────────────────────────┤
│ 当前体重          65.0 千克 >│
├────────────────────────────┤
│ 目标体重          60.0 千克 >│
├────────────────────────────┤
│ 活跃水平                低 >│
├────────────────────────────┤
│ 每周目标        -0.50 千克 >│
├────────────────────────────┤
│ 卡路里目标      1,584 千卡 >│
├────────────────────────────┤
│ 步数目标             10,000 >│
├────────────────────────────┤
│ 营养目标              默认 >│
├────────────────────────────┤
│                            │
│         保存               │
└────────────────────────────┘
```

按钮与行为：

| 区域 | 行为 |
| --- | --- |
| 返回 | 有草稿变更时提示是否放弃 |
| 目标 | 打开目标模式选择 |
| 当前体重 | 打开数字输入页 |
| 活跃水平 | 打开低/中/高选择页 |
| 每周目标 | 打开范围选择页 |
| 卡路里目标 | 进入卡路里目标页 |
| 营养目标 | 进入营养目标页 |
| 保存 | 提交 `NutritionGoalUpdateRequest` |

### 6.2 卡路里目标页

```text
┌────────────────────────────┐
│ ←        卡路里目标         │
├────────────────────────────┤
│ 提示：禁食倒计时可能影响目标 │
├────────────────────────────┤
│ 卡路里目标（千卡）     1584 │
├────────────────────────────┤
│ 重新计算卡路里目标          │
├────────────────────────────┤
│ 周末热量目标              > │
├────────────────────────────┤
│ 卡路里分布                > │
├────────────────────────────┤
│                            │
│          保存              │
└────────────────────────────┘
```

点击 `重新计算卡路里目标`：

```text
当前 NutritionGoalDraft
-> NutritionEnergyCalculationRequest
-> 服务端计算
-> 计算结果页
```

### 6.3 计算结果页

```text
┌────────────────────────────┐
│ ←        计算结果           │
├────────────────────────────┤
│ 建议卡路里目标              │
│                            │
│        1,584 千卡/天        │
│                            │
├────────────────────────────┤
│ 当前状态                    │
│ BMI：23.9  正常             │
│ 理想体重：56.3 - 73.0 千克  │
│ 当前目标体重：60.0 千克     │
│ 状态：位于建议范围内         │
├────────────────────────────┤
│ 计算依据                    │
│ 当前体重：65.0 千克          │
│ 身高：165 厘米              │
│ 年龄：30 岁                 │
│ 活跃水平：低                │
│ BMR：1,420 千卡             │
│ 维持热量：2,134 千卡         │
│ 每日热量差：-550 千卡        │
├────────────────────────────┤
│ 消耗解释                    │
│ 基础代谢：1,420 千卡         │
│ 日常活动估算：714 千卡       │
│ 今日 Apple 健康消耗：411 千卡 │
├────────────────────────────┤
│ 提示：结果为估算值，会受到    │
│ 记录准确性、疾病、用药等影响  │
├────────────────────────────┤
│        使用建议目标          │
│        保留当前目标          │
└────────────────────────────┘
```

按钮行为：

| 按钮 | 行为 |
| --- | --- |
| 使用建议目标 | 回写 `dailyEnergyTargetKcal`，`isEnergyTargetCustom=false`，保存 BMR/TDEE 快照到草稿 |
| 保留当前目标 | 不修改草稿，返回卡路里目标页 |
| 返回 | 返回卡路里目标页 |

### 6.4 缺失资料页

```text
┌────────────────────────────┐
│ ←        补充资料           │
├────────────────────────────┤
│ 为了重新计算卡路里目标，     │
│ 需要补充以下信息。           │
├────────────────────────────┤
│ 身高                 165 cm │
├────────────────────────────┤
│ 当前体重             65.0 kg│
├────────────────────────────┤
│ 生理性别                女 >│
├────────────────────────────┤
│ 年龄                  30 岁 │
├────────────────────────────┤
│        继续计算             │
└────────────────────────────┘
```

说明：

1. 补充资料写入目标草稿。
2. 第一阶段不强制回写成员档案。
3. 后续可增加“同步保存到成员档案”开关。

### 6.5 卡路里分布页

```text
┌────────────────────────────┐
│ ←        卡路里分布      ↻  │
├────────────────────────────┤
│ 早餐      475 千卡     30% >│
├────────────────────────────┤
│ 午餐      634 千卡     40% >│
├────────────────────────────┤
│ 晚餐      396 千卡     25% >│
├────────────────────────────┤
│ 小吃       79 千卡      5% >│
├────────────────────────────┤
│ 合计                  100% │
├────────────────────────────┤
│          保存              │
└────────────────────────────┘
```

### 6.6 营养目标页

```text
┌────────────────────────────┐
│ ←        营养目标        ↻  │
├────────────────────────────┤
│ 营养              低碳水化合物 >│
├────────────────────────────┤
│ 碳水化合物  174g / 713千卡 45% >│
├────────────────────────────┤
│ 蛋白质       97g / 396千卡 25% >│
├────────────────────────────┤
│ 脂肪         51g / 475千卡 30% >│
├────────────────────────────┤
│ 合计                  100% │
└────────────────────────────┘
```

## 七、算法流程

### 7.1 输入

| 字段 | 单位 | 来源 |
| --- | --- | --- |
| `biologicalSex` | `male/female/unknown` | 成员档案或补充资料 |
| `ageYears` | 年 | 成员生日推导或补充资料 |
| `heightCm` | cm | 成员档案或补充资料 |
| `currentWeightKg` | kg | 我的目标页面 |
| `activityLevel` | 枚举 | 我的目标页面 |
| `goalType` | 枚举 | 我的目标页面 |
| `weeklyWeightDeltaKg` | kg/周 | 我的目标页面 |

### 7.2 BMR

```text
男性：
BMR = 10 * 体重kg + 6.25 * 身高cm - 5 * 年龄 + 5

女性：
BMR = 10 * 体重kg + 6.25 * 身高cm - 5 * 年龄 - 161
```

### 7.3 TDEE

```text
TDEE = BMR * 活跃系数
```

| 活跃水平 | 数据值 | 系数 |
| --- | --- | --- |
| 低 | `low` | `1.2` |
| 中 | `medium` | `1.375` |
| 高 | `high` | `1.55` |
| 很高 | `very_high` | `1.725` |

### 7.4 每周目标换算

```text
每周热量差 = 每周目标kg * 7700
每日热量差 = 每周热量差 / 7
```

示例：

```text
每周目标 = -0.50 kg
每日热量差 = -0.50 * 7700 / 7 = -550 kcal
```

### 7.5 建议卡路里目标

```text
suggestedEnergyKcal = TDEE + 每日热量差
```

### 7.6 BMI

```text
BMI = 当前体重kg / (身高m * 身高m)
```

### 7.7 理想体重范围

```text
理想体重下限 = 18.5 * 身高m * 身高m
理想体重上限 = 24.0 * 身高m * 身高m
Broca 参考体重 = 身高cm - 100
```

### 7.8 消耗估算

```text
estimatedDailyActivityKcal = max(TDEE - BMR, 0)
```

说明：

1. `estimatedDailyActivityKcal` 是估算。
2. 今日看板 `已消耗` 不直接用它。
3. 本人今日消耗优先用 Apple 健康事实数据。
4. 家庭成员用手动 `NutritionEnergyBurnRecord`。

## 八、服务端数据存储

### 8.1 本工单涉及的服务端表

本工单第一期不建议为了 BMI、理想体重、BMR、TDEE 分别新建事实表，但需要明确服务端表变更：

| 表/模型 | 类型 | 第一阶段是否需要 | 作用 |
| --- | --- | --- | --- |
| `NutritionGoal` | 扩展现有表 | 是 | 保存成员当前目标、卡路里目标、营养目标、餐次分布和最近一次计算快照 |
| `NutritionGoalCalculationLog` | 新增表 | 可选，建议预留 | 保存每次目标计算请求和结果，用于审计、排障、AI 解释回溯 |
| `NutritionBMIRecord` | 新增表 | 否 | 不需要，BMI 是计算结果，不是业务事实 |
| `NutritionIdealWeightRecord` | 新增表 | 否 | 不需要，理想体重是计算结果，不是业务事实 |
| `NutritionTDEERecord` | 新增表 | 否 | 不需要，TDEE 是计算结果，不是业务事实 |
| `NutritionCalculatorHistory` | 新增表 | 否 | 不建议做泛化历史表，语义不清晰 |

结论：

1. 第一阶段必须扩展 `NutritionGoal`。
2. 如果产品/运营需要审计“用户每次重新计算目标”的历史，则新增 `NutritionGoalCalculationLog`。
3. 如果第一阶段只需要展示最近一次计算依据，可以不建 `NutritionGoalCalculationLog`，只在 `NutritionGoal` 保存最近一次计算快照。

### 8.2 NutritionGoal 扩展字段

`NutritionGoal` 保存最终目标和最近一次计算快照。

新增或确认字段：

```text
height_cm
biological_sex
age_years
bmr_kcal
tdee_kcal
energy_delta_kcal
calculation_formula
calculation_version
calculation_inputs
daily_energy_target_kcal
is_energy_target_custom
weekend_energy_target_kcal
is_weekend_energy_enabled
meal_distribution
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `height_cm` | 身高快照，单位 cm；来自成员档案或目标补充页 |
| `biological_sex` | 生理性别快照，例如 `male/female/unknown` |
| `age_years` | 年龄快照，由生日推导或用户补充 |
| `bmr_kcal` | 最近一次计算得到的基础代谢 |
| `tdee_kcal` | 最近一次计算得到的维持热量 |
| `energy_delta_kcal` | 根据每周目标换算的每日热量差 |
| `calculation_formula` | 公式名称，例如 `mifflin_st_jeor` |
| `calculation_version` | 公式版本，例如 `v1` |
| `calculation_inputs` | JSON，保存活动系数、风险标记、缺失字段、默认值使用情况等 |
| `daily_energy_target_kcal` | 用户最终确认的每日卡路里目标 |
| `is_energy_target_custom` | 是否用户手动覆盖卡路里目标 |
| `weekend_energy_target_kcal` | 周末热量目标，第一期可预留 |
| `is_weekend_energy_enabled` | 是否启用周末热量目标 |
| `meal_distribution` | 早餐、午餐、晚餐、小吃目标比例 |

保存规则：

| 用户行为 | 保存规则 |
| --- | --- |
| 使用建议目标 | `daily_energy_target_kcal=suggestedEnergyKcal`，`is_energy_target_custom=false` |
| 手动修改卡路里 | 保存用户输入值，`is_energy_target_custom=true` |
| 重新计算但不使用 | 不保存到正式 `NutritionGoal`，只保留页面草稿 |

### 8.3 NutritionGoalCalculationLog：目标计算审计表

### Q：是否需要新建 `NutritionGoalCalculationLog`？

A：如果第一期只做“计算并使用建议目标”，可以不建；如果希望排查用户反馈、保留每次计算历史、分析公式效果，建议新建。

建议模型：

```python
class NutritionGoalCalculationLog(models.Model):
    class Source(models.TextChoices):
        GOAL_RECALCULATE = "goal_recalculate", "goal_recalculate"
        BODY_METRICS = "body_metrics", "body_metrics"
        AI_SUGGESTION = "ai_suggestion", "ai_suggestion"

    user = models.ForeignKey(User, related_name="nutrition_goal_calculation_logs", on_delete=models.CASCADE, db_index=True, db_comment="当前登录账号 ID；用于权限边界和审计查询")
    member = models.ForeignKey("medical.Member", related_name="nutrition_goal_calculation_logs", on_delete=models.CASCADE, db_index=True, db_comment="目标计算归属成员 ID；目标是成员维度")
    goal = models.ForeignKey("nutrition.NutritionGoal", related_name="calculation_logs", on_delete=models.SET_NULL, null=True, blank=True, db_index=True, db_comment="本次计算最终关联的目标 ID；用户未保存建议时可为空")
    source = models.CharField(max_length=32, choices=Source.choices, default=Source.GOAL_RECALCULATE, db_index=True, db_comment="计算来源：重新计算卡路里目标、统一身体指标计算、AI 建议等")

    input_snapshot = models.JSONField(default=dict, blank=True, db_comment="计算输入快照；保存性别、年龄、身高、体重、活跃水平、目标模式、每周目标等")
    result_snapshot = models.JSONField(default=dict, blank=True, db_comment="计算结果快照；保存 BMI、理想体重范围、BMR、TDEE、建议摄入、消耗估算等")
    calculation_formula = models.CharField(max_length=32, blank=True, default="", db_comment="公式名称，例如 mifflin_st_jeor")
    calculation_version = models.CharField(max_length=32, blank=True, default="", db_comment="公式版本，例如 v1")
    risk_flags = models.JSONField(default=list, blank=True, db_comment="风险标记列表，例如 below_safe_energy_floor、missing_height")
    missing_fields = models.JSONField(default=list, blank=True, db_comment="缺失字段列表，例如 height_cm、biological_sex")
    used_default_values = models.BooleanField(default=False, db_index=True, db_comment="本次计算是否使用了默认值")
    accepted = models.BooleanField(default=False, db_index=True, db_comment="用户是否采用本次计算结果保存为目标")
    accepted_at = models.DateTimeField(null=True, blank=True, db_comment="用户采用本次计算结果的时间；未采用为空")

    created_at = models.DateTimeField(auto_now_add=True, db_index=True, db_comment="计算发生时间")
```

索引建议：

```python
indexes = [
    models.Index(fields=["user", "member", "created_at"]),
    models.Index(fields=["member", "source", "created_at"]),
    models.Index(fields=["goal", "accepted"]),
]
```

设计要点：

1. `input_snapshot` 和 `result_snapshot` 是审计快照，不参与看板主查询。
2. `accepted=false` 表示用户只是试算，没有采用结果。
3. 用户点击“使用建议目标”并保存成功后，可回写 `goal_id`、`accepted=true`、`accepted_at`。
4. 第一阶段如果不建此表，必须保证 `NutritionGoal` 至少保存最近一次计算快照。
5. 不要把此表作为目标事实源；目标事实源仍然是 `NutritionGoal`。

### 8.4 不新增事实表

不新增以下表：

1. `NutritionBMIRecord`
2. `NutritionIdealWeightRecord`
3. `NutritionTDEERecord`
4. `NutritionCalculatorHistory`

原因：

1. BMI、理想体重、BMR、TDEE 是计算结果，不是业务事实。
2. 第一阶段没有必要保存每次试算历史。
3. `NutritionGoal` 的最近一次计算快照足够支撑展示和 AI 解释。

如果本工单决定启用 `NutritionGoalCalculationLog`，它也只是审计日志表，不是 BMI/TDEE 的事实表。

## 九、服务端接口

### 9.1 获取当前目标

```http
GET /api/v1/nutrition/goals/current/?member_id=100
```

返回：

```text
RemoteNutritionGoal
```

### 9.2 保存目标

```http
PUT /api/v1/nutrition/goals/current/
```

请求：

```text
NutritionGoalUpdateRequest
```

服务端行为：

```text
校验成员权限
-> 校验目标字段
-> 当前 active 目标置为 false
-> 新建 active NutritionGoal
-> 返回 RemoteNutritionGoal
```

### 9.3 重新计算卡路里目标

```http
POST /api/v1/nutrition/goals/calculate-energy/
```

请求：

```swift
struct NutritionEnergyCalculationRequest: Codable, Sendable, Equatable {
    var memberId: Int
    var goalType: String
    var activityLevel: String
    var currentWeightKg: Double?
    var heightCm: Double?
    var biologicalSex: String?
    var ageYears: Int?
    var weeklyWeightDeltaKg: Double?
}
```

响应：

```swift
struct NutritionEnergyCalculationResponse: Codable, Sendable, Equatable {
    var suggestedEnergyKcal: Double
    var bmrKcal: Double?
    var tdeeKcal: Double?
    var energyDeltaKcal: Double?
    var calculationFormula: String
    var calculationVersion: String
    var calculationInputs: NutritionCalculationInputs?
    var reason: String
}
```

### 9.4 统一身体指标和目标计算

```http
POST /api/v1/nutrition/goals/calculate-body-metrics/
```

用途：一次返回 BMI、理想体重、摄入目标、消耗估算。

响应：

```swift
struct NutritionBodyMetricsCalculationResponse: Codable, Sendable, Equatable {
    var bmi: NutritionBMIResult?
    var idealWeight: NutritionIdealWeightResult?
    var calorieIntake: NutritionEnergyCalculationResponse?
    var caloriesBurned: NutritionBurnEstimateResult?
    var missingFields: [String]
    var warnings: [String]
}
```

### 9.5 DTO

```swift
struct NutritionCalculationInputs: Codable, Sendable, Equatable {
    var activityFactor: Double?
    var weeklyWeightEnergyKcalPerKg: Double?
    var minSafeEnergyKcal: Double?
    var riskFlags: [String]
    var missingFields: [String]
    var usedDefaultValues: Bool
    var source: String?
}

struct NutritionBMIResult: Codable, Sendable, Equatable {
    var value: Double
    var category: String
    var categoryText: String
}

struct NutritionIdealWeightResult: Codable, Sendable, Equatable {
    var minKg: Double?
    var maxKg: Double?
    var referenceKg: Double?
    var method: String
    var targetWeightStatus: String
}

struct NutritionBurnEstimateResult: Codable, Sendable, Equatable {
    var bmrKcal: Double?
    var tdeeKcal: Double?
    var estimatedDailyActivityKcal: Double?
    var appleHealthActiveEnergyKcal: Double?
    var manualBurnedEnergyKcal: Double?
    var source: String
}
```

编码解码约定：

1. 客户端 DTO 使用 camelCase。
2. 服务端 JSON 使用 snake_case。
3. 客户端继续使用统一 `JSONEncoder.default` / `JSONDecoder.default`。
4. 不手写 `CodingKeys`。

## 十、客户端实现范围

### 10.1 新增或扩展页面

| 页面 | 类型 | 说明 |
| --- | --- | --- |
| `NutritionGoalView` | 扩展 | 我的目标主页面 |
| `NutritionCalorieGoalView` | 扩展 | 卡路里目标页面 |
| `NutritionGoalCalculationResultView` | 新增 | 计算结果页 |
| `NutritionGoalMissingProfileView` | 新增 | 缺失资料补充页 |
| `NutritionMealDistributionView` | 扩展 | 卡路里分布页 |
| `NutritionMacroGoalView` | 扩展 | 营养目标页 |

### 10.2 ViewModel 状态

```swift
enum NutritionGoalCalculationState: Equatable {
    case idle
    case loading
    case missingFields([String])
    case result(NutritionBodyMetricsCalculationResponse)
    case failed(messageKey: String)
}
```

### 10.3 客户端日志

关键日志：

```text
饮食目标计算：开始 memberID=100 goalType=lose_weight activityLevel=low
饮食目标计算：缺少资料 memberID=100 missingFields=[height_cm]
饮食目标计算：成功 memberID=100 suggestedEnergy=1584 bmr=1420 tdee=2134 riskFlags=[]
饮食目标保存：开始 memberID=100 isCustom=false dailyEnergy=1584
饮食目标保存：成功 memberID=100 goalID=12
```

### 10.4 本地化

必须本地化：

1. 我的目标。
2. 卡路里目标。
3. 重新计算卡路里目标。
4. 使用建议目标。
5. 保留当前目标。
6. BMI 分类文案。
7. 理想体重范围。
8. 维持热量。
9. 基础代谢。
10. 缺失资料提示。
11. 风险提示。

## 十一、服务端实现范围

### 11.1 服务层

建议新增服务：

```text
nutrition/services/goal_calculation_service.py
```

职责：

1. 标准化输入。
2. 从成员档案补齐性别、生日、身高。
3. 计算 BMI。
4. 计算理想体重范围。
5. 计算 BMR/TDEE。
6. 计算建议卡路里目标。
7. 生成风险提示和解释文案。
8. 返回统一 DTO。
9. 如果启用 `NutritionGoalCalculationLog`，记录每次计算的输入快照和结果快照。

### 11.2 数据迁移

必须迁移：

1. 扩展 `NutritionGoal` 计算快照字段。
2. 增加必要索引。

可选迁移：

1. 新增 `NutritionGoalCalculationLog`。
2. 如果第一期不启用计算审计表，需要在工单实现说明中明确“仅保存最近一次计算快照”。

### 11.3 权限

所有接口必须校验：

1. 当前用户对 `member_id` 有查看权限。
2. 保存目标时必须有编辑/管理权限。
3. 家庭成员目标计算不读取当前设备 Apple 健康。
4. 本人成员可以在结果中带 Apple 健康消耗事实数据。

### 11.4 错误码建议

| code | msg | 场景 |
| --- | --- | --- |
| `40001` | `missing_required_profile_fields` | 缺少身高、年龄、性别、体重 |
| `40002` | `invalid_goal_parameters` | 每周目标、比例、热量范围非法 |
| `40301` | `member_permission_denied` | 无成员权限 |
| `42201` | `unsafe_energy_goal` | 建议目标过低或过激 |

如果只是缺少资料，建议返回业务成功响应并在 `missing_fields` 中表达，而不是抛异常，方便客户端进入补充资料页。

## 十二、数据一致性

### 12.1 事实和估算分离

| 数据 | 类型 | 来源 |
| --- | --- | --- |
| 饮食摄入 | 事实 | 服务端饮食记录 |
| Apple 健康活动消耗 | 事实 | HealthKit 同步 |
| 手动能量消耗 | 事实 | 服务端记录 |
| BMI | 估算/分类 | 公式计算 |
| 理想体重范围 | 估算/建议 | 公式计算 |
| BMR | 估算 | 公式计算 |
| TDEE | 估算 | BMR * 活跃系数 |
| 建议摄入 | 建议 | TDEE + 目标修正 |

### 12.2 目标变更

目标变更规则：

1. 饮食记录不变。
2. 今日和未来看板使用最新目标。
3. 旧目标置为 `is_active=false`。
4. 新目标保存计算快照。
5. 历史目标复盘后续可按 `effective_from` 查询。

## 十三、验收标准

### 13.1 客户端验收

1. 从 `我的目标` 可以进入卡路里目标页。
2. 点击 `重新计算卡路里目标` 可以发起计算请求。
3. 缺少资料时进入补充资料页。
4. 资料完整时展示计算结果页。
5. 计算结果页展示建议卡路里、BMI、理想体重范围、BMR、TDEE、每日热量差、消耗解释。
6. 点击 `使用建议目标` 后回写目标草稿。
7. 保存目标后刷新饮食营养首页。
8. 用户手动修改卡路里后 `isEnergyTargetCustom=true`。
9. 所有文案本地化。
10. 关键链路有日志。

### 13.2 服务端验收

1. `calculate-energy` 能返回 BMR、TDEE、每日热量差、建议目标。
2. `calculate-body-metrics` 能返回 BMI、理想体重、摄入建议、消耗估算。
3. 缺少字段时返回 `missing_fields`，不导致客户端崩溃。
4. 目标保存后 `NutritionGoal` 写入计算快照。
5. 如果启用 `NutritionGoalCalculationLog`，每次计算都会写入计算日志；用户采用建议目标后日志可关联正式 `goal_id`。
6. 目标保存不改写饮食记录。
7. 成员权限校验和医疗档案成员权限一致。
8. DTO 字段 snake_case 输出，客户端 camelCase 解码。

### 13.3 联调验收

1. 同一输入多次计算结果一致。
2. `goal_type=maintain` 时每日热量差为 0。
3. `goal_type=lose_weight` 时每日热量差为负数。
4. `goal_type=gain_muscle` 时每日热量差为正数。
5. 低于安全阈值时返回 `riskFlags`。
6. Apple 健康事实消耗和 TDEE 估算在 UI 中不混淆。

## 十四、分阶段实施

### 阶段一：目标计算基础能力

目标：先让饮食目标计算本身可用。

实现内容：

1. 扩展 `NutritionGoal`，保存目标、BMI、BMR、TDEE、计算快照。
2. 服务端提供目标计算接口。
3. 客户端 `我的目标` 支持重新计算卡路里目标。
4. 客户端支持缺失资料补充页。
5. 保存目标后刷新饮食营养首页和看板。

验收：

1. 用户可以从 `我的目标` 完成重新计算和保存。
2. 服务端返回 BMI、理想体重范围、BMR、TDEE、建议卡路里。
3. `NutritionGoal` 保存最近一次计算快照。

### 阶段二：新建成员饮食健康联动

目标：把本工单接入成员建档流程。

关联文档：

```text
需求文档/成员管理/成员建档与模块维护需求讨论文档.md
```

实现内容：

1. 新建成员先完成姓名生日页、关系性别页。
2. 关系性别页下一步立即创建成员，并获得 `memberID`。
3. 进入模块选择页时已经持有 `memberID`。
4. 模块选择页展示医疗模块和饮食健康。
5. 用户点击饮食健康 `去完善`，sheet 打开 `MemberNutritionSetupSheet`。
6. `MemberNutritionSetupSheet` 分身体信息、目标设置、营养目标三个步骤。
7. 饮食健康 sheet 点击完成时立即保存 `NutritionGoal`。
8. 保存成功后更新 `MemberModuleSetting(module_code=nutrition)`。
9. 成员建档最后完成时不再重复提交饮食健康表单，只刷新首页配置。

验收：

1. 进入饮食健康 sheet 前已经有 `memberID`。
2. 饮食健康模块保存失败不重复创建成员。
3. 饮食健康保存成功后，成员首页可展示 `nutritionInfoSection`。
4. `MemberModuleSetting(module_code=nutrition)` 状态正确。

### 阶段三：医疗模块联动作为成员建档前置依赖

目标：虽然本工单主线是饮食目标，但成员建档流程里医疗模块和饮食健康并列展示，因此需要明确前置依赖。

关联数据：

```text
MemberModuleSetting
MemberMedicalProfile
```

实现内容：

1. 服务端在 `medical` app 内新增 `MemberModuleSetting`。
2. 服务端在 `medical` app 内新增 `MemberMedicalProfile`。
3. 医疗模块 sheet 完成时独立保存 `MemberMedicalProfile`。
4. 医疗保存成功后更新 `MemberModuleSetting(module_code=medical)`。
5. 饮食健康保存成功后更新 `MemberModuleSetting(module_code=nutrition)`。
6. 首页模块排序由 `MemberModuleSetting.display_order` 控制。

说明：

1. 医疗模块正式业务数据仍走现有病历、用药计划、体检报告、症状、随访等表。
2. `MemberMedicalProfile` 只保存成员建档阶段的医疗概览和关注项。
3. 用药计划通过 `MedicationPlanStepperView` 创建，不保存在 `MemberMedicalProfile` 里。

### 阶段四：后续增强

后续可继续增强：

1. 手动录入体检指标迁移为结构化指标记录表。
2. `NutritionGoalCalculationLog` 启用完整计算审计。
3. 根据成员模块配置优化首页模块排序和摘要卡片。
4. 日常健康模块是否从代码预留变成可见模块。
5. 成长发育、照护安全是否独立成模块。

## 十五、与既有工单关系

1. 基于 `NUTRITION-000004` 的默认目标能力扩展。
2. 基于 `NUTRITION-000005` 看板目标值展示。
3. 基于 `NUTRITION-000008` 能量消耗和 Apple 健康同步事实数据。
4. 基于 `NUTRITION-000009` 客户端 DTO/API/Repository/UseCase。
5. 不替代 `NUTRITION-000010` 首页看板，只为其提供目标和解释数据。
6. 后续 AI 对话扩展可由 `NUTRITION-000018` 读取本工单计算结果。
7. 成员建档联动依赖《成员建档与模块维护需求讨论文档》中的 `MemberModuleSetting` 与 `MemberMedicalProfile` 设计。

## 十六、开放问题

1. BMI 分类阈值是否使用中国成人标准还是 WHO 标准？
2. 最低安全热量阈值是否按性别区分？
3. 身高、性别、年龄补充后是否回写成员档案？
4. `very_high` 是否第一期仅数据层保留，不在 UI 展示？
5. `calculate-energy` 和 `calculate-body-metrics` 是否都保留，还是第一期只做统一接口？
6. 目标计算公式是否固定 `Mifflin-St Jeor v1`，后续再扩展版本？
