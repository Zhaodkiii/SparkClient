# MEDICAL-000001 用药明细事实源与成员医疗画像投影工单

创建日期：2026-06-21

关联文档：

- `成员管理/医疗模块引导流程重构需求讨论文档.md`
- `成员管理/医疗模块引导流程重构详细设计文档.md`
- `成员管理/医疗模块引导数据存储模型详细设计文档.md`

参考代码：

- 服务端：`SparkService/medical/models.py:76-99`
- 服务端：`SparkService/medical/models.py:687-777`
- 客户端：`SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Medical/`
- 客户端：`SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanStepper/MedicationPlanStepperView.swift`

说明：本文档为详细设计工单，只描述目标方案与实现边界，不要求立即修改代码。

---

## 一、背景

成员医疗模块中，用药信息当前同时存在两个层级：

```text
MemberMedicalProfile.long_term_medications
MemberMedicalProfile.medication_notes
MedicationPlan
```

其中 `MedicationPlan` 已经是完整的用药计划明细模型，包含：

```text
member
medical_case
medicine_box
prescription
drug_name
dose_per_time
dose_value
dose_unit
frequency_type
frequency_text
reminder_times
start_date
end_date
instructions
reminder_enabled
status
extra
```

而 `MemberMedicalProfile.long_term_medications` 与 `MemberMedicalProfile.medication_notes` 也在描述成员长期用药。这会导致一个成员的用药事实存在多处来源。

当前症状模块已经完成类似改造：

```text
Symptom
    = 症状明细事实源

MemberMedicalProfile.symptom_follow_up_focus
    = 从有效 Symptom 聚合出的成员医疗画像投影
```

用药模块也需要采用同一套边界。

---

## 二、核心问题

### 2.1 重复事实源

`MedicationPlan` 是明细事实源，`MemberMedicalProfile.long_term_medications` 和 `medication_notes` 又保存长期用药摘要。

当用户修改、暂停、删除某个用药计划时，如果没有同步更新 profile，会出现：

```text
用药计划已删除
但成员医疗画像仍显示该药
```

或者：

```text
用药计划剂量已修改
但 medication_notes 仍显示旧剂量
```

### 2.2 字段职责不清

`long_term_medications` 是列表，`medication_notes` 是文本，二者都在描述用药摘要。

问题：

1. 药名在 list。
2. 剂量、频次、说明可能在 notes。
3. AI 读取时需要同时理解两个字段。
4. 删除或暂停时需要同步两处。
5. 客户端展示时不知道哪个字段优先。

### 2.3 成员医疗引导入口不应直接写 profile 用药字段

成员医疗引导里的“用药”应该展示和创建真实 `MedicationPlan`，不应该直接维护 `MemberMedicalProfile.long_term_medications`。

否则用药提醒、药箱、处方、历史记录都会和引导页数据割裂。

---

## 三、目标设计

### 3.1 最终边界

```text
MedicationPlan
= 用药明细事实源
= 药名、剂量、频次、提醒、开始结束日期、状态、来源处方/药箱

MemberMedicalProfile.medication_focus
= 从有效 MedicationPlan 聚合出的成员长期用药摘要投影
= 只服务首页、医疗引导、AI 输入、体检计划上下文
```

### 3.2 一句话原则

```text
MedicationPlan 做唯一事实源；
MemberMedicalProfile 只保存 medication_focus 摘要投影；
所有创建、编辑、删除、暂停后由服务端重算 profile；
客户端只消费 mutation 响应并刷新列表与摘要。
```

### 3.3 和症状模块保持一致

```text
Symptom CRUD
    -> 服务端重算 symptom_follow_up_focus
    -> mutation 响应返回 member_profile + summary
    -> 客户端刷新列表 + 摘要

MedicationPlan CRUD
    -> 服务端重算 medication_focus
    -> mutation 响应返回 member_profile + summary
    -> 客户端刷新列表 + 摘要
```

---

## 四、服务端数据模型设计

### 4.1 MemberMedicalProfile 字段调整

当前字段：

```python
long_term_medications = models.JSONField(...)
medication_notes = models.TextField(...)
```

建议目标字段：

```python
medication_focus = models.JSONField(default=list, blank=True)
```

语义：

```text
成员长期用药摘要投影。
由服务端根据有效 MedicationPlan 重算。
不作为用药事实源。
```

建议结构：

```json
[
  {
    "drug_name": "二甲双胍",
    "summary": "每日2次 · 0.5g",
    "status": "active",
    "reminder_enabled": true,
    "source_plan_id": 12
  },
  {
    "drug_name": "氨氯地平",
    "summary": "每日1次",
    "status": "active",
    "reminder_enabled": true,
    "source_plan_id": 18
  }
]
```

### 4.2 关于 source_plan_id

`source_plan_id` 可以保留，用于客户端从 profile 摘要跳转到用药计划详情。

但它不是强一致关系，真正事实仍以 `MedicationPlan` 为准。

也就是说：

```text
profile.medication_focus.source_plan_id
    = 用于展示和跳转的投影引用

MedicationPlan.id
    = 事实源主键
```

### 4.3 long_term_medications 与 medication_notes 如何处理

建议方案：

```text
新增 medication_focus
后续不再由新流程写入 long_term_medications / medication_notes
旧字段进入兼容读取期
新接口优先返回 medication_focus
```

如果当前项目不需要兼容旧版本，可更激进：

```text
废弃 medication_notes
将 long_term_medications 改名或迁移为 medication_focus
```

推荐优先级：

1. 新增 `medication_focus`。
2. 服务端 mutation 响应只返回 `medication_focus`。
3. 客户端新流程只消费 `medication_focus`。
4. `long_term_medications` 与 `medication_notes` 只作为历史兼容字段。

---

## 五、服务端聚合规则

### 5.1 有效 MedicationPlan 范围

用于生成 `medication_focus` 的计划：

```text
member = 当前成员
is_deleted = false
status in [active, paused]
```

建议展示排序：

```text
active 优先
reminder_enabled=true 优先
start_date 倒序
updated_at 倒序
id 倒序
```

### 5.2 摘要生成规则

每个 `MedicationPlan` 生成一条投影：

```text
drug_name
summary
status
reminder_enabled
source_plan_id
```

`summary` 拼接建议：

```text
dose_per_time / dose_value + dose_unit
frequency_text
reminder_times
```

示例：

```text
二甲双胍 · 0.5g · 每日2次
氨氯地平 · 每日1次 · 08:00提醒
阿司匹林 · 每日1次 · 已暂停
```

### 5.3 顶层 summary

mutation 响应中的 `summary` 用于客户端快速展示：

```text
二甲双胍 · 每日2次 / 氨氯地平 · 每日1次
```

无有效用药：

```text
暂无长期用药
```

---

## 六、服务端接口设计

### 6.1 用药计划列表

```text
GET /api/v1/medical/medication-plans/?member_id=xxx
```

用途：

```text
成员医疗引导用药页
成员详情页用药摘要
用药计划列表
```

返回：

```json
{
  "code": 0,
  "msg": "success",
  "data": [
    {
      "id": 12,
      "member_id": 100,
      "drug_name": "二甲双胍",
      "dose_per_time": "0.5g",
      "frequency_text": "每日2次",
      "reminder_times": [{"time": "08:00", "dose": 1}],
      "start_date": "2026-06-21",
      "end_date": null,
      "reminder_enabled": true,
      "status": "active"
    }
  ]
}
```

### 6.2 用药计划详情

```text
GET /api/v1/medical/medication-plans/{id}/
```

用途：

```text
MedicationPlanDetailView
```

### 6.3 创建用药计划

```text
POST /api/v1/medical/medication-plans/
```

成功后：

```text
创建 MedicationPlan
重算 MemberMedicalProfile.medication_focus
返回 mutation 响应
```

### 6.4 编辑用药计划

```text
PATCH /api/v1/medical/medication-plans/{id}/
```

成功后：

```text
更新 MedicationPlan
重算 MemberMedicalProfile.medication_focus
返回 mutation 响应
```

### 6.5 暂停 / 恢复

可以使用 PATCH：

```json
{
  "status": "paused"
}
```

或：

```json
{
  "status": "active"
}
```

成功后同样重算 `medication_focus`。

### 6.6 删除用药计划

```text
DELETE /api/v1/medical/medication-plans/{id}/
```

建议软删除：

```text
is_deleted = true
```

成功后：

```text
重算 MemberMedicalProfile.medication_focus
返回 mutation 响应
```

---

## 七、Mutation 响应设计

### 7.1 创建 / 编辑 / 暂停 / 恢复成功

```json
{
  "deleted": false,
  "medication_plan": {
    "id": 12,
    "member_id": 100,
    "drug_name": "二甲双胍",
    "dose_per_time": "0.5g",
    "frequency_text": "每日2次",
    "reminder_times": [{"time": "08:00", "dose": 1}],
    "start_date": "2026-06-21",
    "end_date": null,
    "reminder_enabled": true,
    "status": "active"
  },
  "member_profile": {
    "medication_focus": [
      {
        "drug_name": "二甲双胍",
        "summary": "0.5g · 每日2次",
        "status": "active",
        "reminder_enabled": true,
        "source_plan_id": 12
      }
    ]
  },
  "summary": "二甲双胍 · 0.5g · 每日2次"
}
```

### 7.2 删除成功

```json
{
  "deleted": true,
  "medication_plan": null,
  "member_profile": {
    "medication_focus": []
  },
  "summary": "暂无长期用药"
}
```

### 7.3 响应设计原则

1. `medication_plan` 表示本次 mutation 的对象。
2. `member_profile.medication_focus` 表示服务端重算后的画像投影。
3. `summary` 用于客户端快速刷新引导页摘要。
4. 客户端不自行拼接 profile 用药摘要，以服务端返回为准。

---

## 八、客户端设计

### 8.1 成员医疗引导用药页

当前成员医疗引导里的“用药”页面不应直接维护 `MemberMedicalProfile.long_term_medications`。

目标：

```text
MemberMedicalMedicationStepView
    -> 拉取 member medication plans
    -> 展示用药计划卡片列表
    -> 添加用药计划
    -> 点击卡片进入用药计划详情
```

页面结构：

```text
用药

是否存在长期用药？
[无长期用药] [有长期用药]

已有用药计划
┌────────────────────────────┐
│ 二甲双胍                    │
│ 0.5g · 每日2次              │
│ 提醒 08:00 / 20:00       > │
└────────────────────────────┘

添加用药计划
```

### 8.2 添加用药计划

入口：

```text
添加用药计划 -> MedicationPlanStepperView
```

保存成功：

```text
POST /api/v1/medical/medication-plans/
-> mutation response
-> viewModel.applyMedicationMutation()
```

### 8.3 用药计划详情页

新增或复用：

```text
MedicationPlanDetailView
```

详情页参考药箱详情页设计。

页面结构：

```text
用药计划详情

二甲双胍

单次剂量        0.5g
服用频次        每日2次
提醒时间        08:00 / 20:00
开始日期        2026-06-21
结束日期        未设置
提醒状态        已开启
关联药箱        二甲双胍片
来源处方        未关联
状态            执行中

编辑
暂停 / 恢复
删除
```

### 8.4 删除用药计划

删除需要二次确认：

```text
删除后，该用药计划将不再用于成员医疗画像、AI体检建议和用药提醒。
```

确认后：

```text
DELETE /api/v1/medical/medication-plans/{id}/
-> mutation response
-> viewModel.applyMedicationMutation()
```

### 8.5 暂停 / 恢复

暂停：

```text
PATCH status=paused
```

恢复：

```text
PATCH status=active
```

暂停后的计划仍可进入 `medication_focus`，但 summary 应体现“已暂停”。

---

## 九、客户端 ViewModel 数据流

### 9.1 建议新增状态

```swift
@Published var memberMedicationPlans: [RemoteMedicationPlan] = []
@Published var medicationFocus: [RemoteMedicationFocusItem] = []
```

### 9.2 建议新增方法

```swift
func refreshMemberMedicationPlansIfNeeded(force: Bool = false) async
func applyMedicationMutation(_ response: MedicationPlanMutationResponse)
func ingestProfileMedicationFocus(_ focus: [RemoteMedicationFocusItem])
```

### 9.3 applyMedicationMutation 行为

```text
if response.deleted:
    从 memberMedicationPlans 移除对应计划
else:
    插入或更新 response.medication_plan

ingestProfileMedicationFocus(response.member_profile.medication_focus)
刷新 medication summary
```

### 9.4 摘要优先级

客户端显示用药摘要时：

```text
优先使用服务端 member_profile.medication_focus
其次使用 memberMedicationPlans 本地列表临时拼接
不再读取 long_term_medications + medication_notes
```

---

## 十、数据一致性策略

### 10.1 服务端负责最终一致性

客户端不能自己维护 `MemberMedicalProfile.medication_focus`。

所有变更必须走：

```text
MedicationPlan mutation
    -> 服务端重算 profile
    -> 返回 mutation response
    -> 客户端更新展示
```

### 10.2 为什么不由客户端同步 profile

原因：

1. 多端并发时客户端无法保证最终一致。
2. 后端 AI 抽取、处方生成、药箱同步也可能创建用药计划。
3. 用药计划有状态过滤规则，应该由服务端统一维护。
4. profile 是投影，不是前端表单事实。

---

## 十一、迁移与兼容策略

### 11.1 不考虑旧版本的理想方案

如果当前项目允许不兼容旧版本：

```text
新增 medication_focus
停止写入 long_term_medications
停止写入 medication_notes
新接口只返回 medication_focus
```

### 11.2 迁移建议

首次迁移时可以：

```text
读取已有 long_term_medications + medication_notes
尝试生成 medication_focus 初始摘要
后续以 MedicationPlan 重算结果覆盖
```

如果没有对应 MedicationPlan：

```text
可以只生成摘要项，不设置 source_plan_id
```

后续用户编辑时，引导用户创建正式 `MedicationPlan`。

---

## 十二、验收标准

### 12.1 服务端

1. 创建 `MedicationPlan` 后，`MemberMedicalProfile.medication_focus` 自动更新。
2. 编辑剂量、频次、提醒时间后，`medication_focus` 自动更新。
3. 暂停计划后，`medication_focus` 展示已暂停状态。
4. 删除计划后，`medication_focus` 移除对应药品。
5. mutation 响应统一返回 `medication_plan`、`member_profile`、`summary`。
6. 新流程不再写入 `medication_notes`。

### 12.2 客户端

1. 成员医疗引导用药页展示 `MedicationPlan` 列表。
2. 点击用药卡片进入用药计划详情页。
3. 添加、编辑、暂停、删除后页面即时刷新。
4. 用药摘要以服务端 `member_profile.medication_focus` 为准。
5. 删除用药计划有二次确认。
6. 首页、成员医疗模块摘要、AI 上下文读取到最新用药摘要。

---

## 十三、风险点

### 13.1 profile 投影和明细短暂不一致

如果 mutation 成功但重算 profile 失败，会出现列表已变更但摘要未更新。

处理建议：

```text
MedicationPlan mutation 和 profile 重算放在同一个事务内。
```

### 13.2 没有用药计划但 profile 有历史文本

如果旧数据只有 `long_term_medications` / `medication_notes`，客户端可能展示旧摘要。

处理建议：

```text
新页面提示用户补全正式用药计划。
```

### 13.3 处方、药箱、用药计划三者关系

`MedicationPlan` 可以关联药箱和处方，但不能要求所有用药都必须有关联。

处理建议：

```text
手动创建的长期用药允许 medicine_box=null、prescription=null。
后续用户可以再补充关联。
```

---

## 十四、阶段拆分

### 阶段一：服务端投影能力

1. 新增或确定 `MemberMedicalProfile.medication_focus`。
2. 新增 `recompute_medication_focus(member)`。
3. 新增 `build_medication_plan_mutation_payload()`。
4. `MedicationPlan` create / update / destroy / status change 后重算 profile。

### 阶段二：客户端 API 与 ViewModel

1. 新增 `MedicationPlanMutationResponse`。
2. `createMedicationPlan / updateMedicationPlan / deleteMedicationPlan` 解码 mutation 响应。
3. `MemberMedicalSetupViewModel` 增加用药列表与 profile 投影同步方法。

### 阶段三：成员医疗引导页

1. 用药页展示 `MedicationPlan` 列表。
2. 添加入口使用 `MedicationPlanStepperView`。
3. 点击卡片进入用药计划详情页。
4. 删除、暂停、恢复后刷新列表和摘要。

### 阶段四：首页与 AI 上下文

1. 首页成员医疗摘要读取 `medication_focus`。
2. AI 体检计划上下文读取 `medication_focus`。
3. 停止读取 `long_term_medications + medication_notes` 作为新流程主要数据源。

---

## 十五、最终结论

用药模块应采用和症状模块一致的架构：

```text
MedicationPlan
    = 用药明细事实源

MemberMedicalProfile.medication_focus
    = 服务端从有效 MedicationPlan 聚合出的画像投影

客户端
    = 展示明细列表 + 消费 mutation 响应 + 同步 profile 摘要
```

这样可以避免重复模型、减少状态散落，并且能让用药提醒、药箱、处方、医疗引导、首页摘要和 AI 体检计划共享同一套可靠数据。
