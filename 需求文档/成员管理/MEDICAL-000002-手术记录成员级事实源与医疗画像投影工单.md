# MEDICAL-000002 手术记录成员级事实源与医疗画像投影工单

创建日期：2026-06-21

关联文档：

- `成员管理/医疗模块引导流程重构需求讨论文档.md`
- `成员管理/医疗模块引导流程重构详细设计文档.md`
- `成员管理/医疗模块引导数据存储模型详细设计文档.md`
- `成员管理/MEDICAL-000001-用药明细事实源与成员医疗画像投影工单.md`

参考代码：

- 服务端：`SparkService/medical/models.py:403-424`
- 服务端：`SparkService/medical/models.py:76-99`
- 客户端：`SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Medical/MemberMedicalSetupSheet.swift:887-995`
- 客户端：`SparkClient/Projects/Features/MedicalRecord/Presentation/NewRecord/Forms/SurgeryFormView.swift:1-165`
- 客户端参考：`SparkClient/Projects/Features/MedicalRecord/Presentation/NewRecord/Forms/SymptomFormView.swift:2-9`
- 客户端参考：`SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Medical/MemberMedicalSymptomFollowUpStepView.swift`
- 客户端参考：`SparkClient/Projects/Features/MedicalRecord/Presentation/NewRecord/Forms/SymptomFormView.swift`

说明：本文档为详细设计工单，只描述目标方案与实现边界，不修改代码。

---

## 一、背景

成员医疗引导中的“手术史”当前主要在引导页内以表单字段维护：

```text
surgeryHistory
surgeryTime
surgeryRecoveryStatus
surgeryHospital
surgeryNotes
```

但服务端已有完整手术明细模型：

```text
Surgery
```

当前 `Surgery` 具备：

```text
member
medical_case
procedure_name
procedure_code
site
performed_at
surgeon
anesthesia_type
incision_level
asa_class
source_system_id
notes
extra
```

问题在于：

1. `Surgery.medical_case` 当前必填，限制了“成员独立手术记录”。
2. 成员建档/医疗引导里的手术史不一定属于某个病例。
3. 手动添加和病历识别/病例详情添加可能落点不一致。
4. 如果 profile 内继续保存手术史文本，会和 `Surgery` 形成重复事实源。

症状模块已经完成同类改造：

```text
Symptom.medical_case 可选
成员引导可创建成员级症状
症状 CRUD 后服务端重算 MemberMedicalProfile.symptom_follow_up_focus
客户端通过 mutation 响应同步列表与画像摘要
```

手术记录也需要采用一致设计。

---

## 二、核心目标

### 2.1 最终边界

```text
Surgery
= 手术记录明细事实源
= 手术名称、部位、时间、医院、医生、麻醉方式、切口等级、备注、来源

MemberMedicalProfile.surgery_focus
= 从有效 Surgery 聚合出的成员手术史摘要投影
= 只服务首页、医疗引导、AI 输入、体检计划上下文
```

### 2.2 一句话原则

```text
Surgery 做唯一事实源；
MemberMedicalProfile 只保存 surgery_focus 摘要投影；
成员引导、病例详情、AI识别都写入同一张 Surgery 表；
所有创建、编辑、删除后由服务端重算 profile；
客户端只消费 mutation 响应并刷新列表与摘要。
```

### 2.3 和症状保持一致

```text
Symptom CRUD
    -> 服务端重算 symptom_follow_up_focus
    -> mutation 响应返回 member_profile + summary
    -> 客户端刷新列表 + 摘要

Surgery CRUD
    -> 服务端重算 surgery_focus
    -> mutation 响应返回 member_profile + summary
    -> 客户端刷新列表 + 摘要
```

---

## 三、当前问题

### 3.1 medical_case 必填限制成员级手术

当前服务端：

```python
medical_case = models.ForeignKey(MedicalCase, related_name="surgeries", on_delete=models.CASCADE, db_index=True)
```

这意味着每条手术必须绑定病例。

但成员引导中的手术史经常是：

```text
用户只记得做过阑尾炎手术
用户只记得剖宫产
用户只记得某年做过胆囊手术
不一定有完整病例记录
```

如果为了保存这类手术强行创建占位病例，会污染病例列表，也会让数据关系变得不自然。

### 3.2 手术史表单和 Surgery 明细重复

如果 `MemberMedicalProfile.extra` 或引导页字段保存一份手术史，同时 `Surgery` 又保存一份明细，会出现：

```text
Surgery 已删除
但 profile 仍显示曾有手术
```

或者：

```text
手术时间在 Surgery 中更新了
但 profile 摘要仍是旧时间
```

### 3.3 手动添加和识别添加体验不一致

成员引导里的手术史目前是直接表单维护。

病例识别或新建病例中的 `SurgeryFormView` 是另一套表单。

目标应是：

```text
手动添加
拍摄/上传识别
病例详情添加
成员引导添加
```

最终都进入同一套 `SurgeryFormView` 与同一套服务端 mutation 流程。

---

## 四、服务端模型设计

### 4.1 Surgery.medical_case 改为可选

目标：

```python
medical_case = models.ForeignKey(
    MedicalCase,
    related_name="surgeries",
    on_delete=models.CASCADE,
    db_index=True,
    null=True,
    blank=True,
)
```

含义：

```text
medical_case = null
    = 成员级独立手术记录

medical_case != null
    = 病例内手术记录
```

### 4.2 迁移

建议新增迁移：

```text
medical/migrations/00xx_surgery_optional_medical_case.py
```

迁移内容：

```text
Surgery.medical_case null=True, blank=True
```

### 4.3 MemberMedicalProfile 增加 surgery_focus

建议新增：

```python
surgery_focus = models.JSONField(
    default=list,
    blank=True,
    db_comment="成员手术史摘要投影；由有效 Surgery 聚合生成，不作为手术事实源",
)
```

建议结构：

```json
[
  {
    "procedure_name": "阑尾切除术",
    "summary": "2018年5月 · 已恢复",
    "performed_at": "2018-05-01T00:00:00Z",
    "site": "腹部",
    "source_surgery_id": 23
  }
]
```

说明：

```text
source_surgery_id 用于客户端跳转详情。
它是投影引用，不是 profile 的事实依赖。
真实事实以 Surgery 为准。
```

### 4.4 不建议 profile 保存手术自由文本

不要再把手术史作为纯文本塞进 `MemberMedicalProfile.extra` 或单独 notes。

原因：

1. 不利于时间线排序。
2. 不利于编辑/删除。
3. 不利于 AI 结构化读取。
4. 不利于和病例、体检计划、风险评估关联。

---

## 五、服务端聚合规则

### 5.1 有效 Surgery 范围

```text
member = 当前成员
is_deleted = false
```

包含：

```text
成员级手术：medical_case is null
病例内手术：medical_case is not null
```

排序建议：

```text
performed_at 倒序
updated_at 倒序
id 倒序
```

### 5.2 摘要生成规则

每个 `Surgery` 生成一条投影：

```text
procedure_name
summary
performed_at
site
source_surgery_id
```

`summary` 拼接建议：

```text
performed_at
site
hospital_name / extra.hospital_name
recovery_status / extra.recovery_status
```

示例：

```text
阑尾切除术 · 2018年5月 · 已恢复
剖宫产 · 2020年3月 · 术后恢复良好
胆囊切除术 · 时间未填
```

### 5.3 mutation 顶层 summary

用于客户端快速刷新：

```text
阑尾切除术 · 2018年5月 / 剖宫产 · 2020年3月
```

无手术记录：

```text
无手术史
```

---

## 六、服务端接口设计

### 6.1 手术列表

```text
GET /api/v1/medical/surgeries/?member_id=xxx
```

返回成员名下所有有效手术：

```text
成员级手术
病例内手术
```

用途：

```text
成员医疗引导手术页
成员详情页手术史
手术详情页入口
AI 上下文组装
```

### 6.2 手术详情

```text
GET /api/v1/medical/surgeries/{id}/
```

用途：

```text
SurgeryDetailView
```

### 6.3 创建手术

```text
POST /api/v1/medical/surgeries/
```

创建模式：

```text
medical_case_id = null
    -> 成员级独立手术

medical_case_id = xxx
    -> 病例内手术
```

成功后：

```text
创建 Surgery
写入 extra.source = manual / photo_ai / case_document_ai
重算 MemberMedicalProfile.surgery_focus
返回 SurgeryMutationResponse
```

### 6.4 编辑手术

```text
PATCH /api/v1/medical/surgeries/{id}/
```

成功后：

```text
更新 Surgery
重算 MemberMedicalProfile.surgery_focus
返回 SurgeryMutationResponse
```

### 6.5 删除手术

```text
DELETE /api/v1/medical/surgeries/{id}/
```

建议软删除：

```text
is_deleted = true
```

成功后：

```text
重算 MemberMedicalProfile.surgery_focus
返回 SurgeryMutationResponse
```

---

## 七、Mutation 响应设计

### 7.1 创建 / 编辑成功

```json
{
  "deleted": false,
  "surgery": {
    "id": 23,
    "member_id": 100,
    "medical_case": null,
    "procedure_name": "阑尾切除术",
    "procedure_code": "",
    "site": "腹部",
    "performed_at": "2018-05-01T00:00:00Z",
    "surgeon": "",
    "anesthesia_type": "",
    "incision_level": "",
    "asa_class": "",
    "notes": "术后恢复良好",
    "extra": {
      "source": "manual",
      "recovery_status": "已恢复",
      "hospital_name": "某医院"
    }
  },
  "member_profile": {
    "surgery_focus": [
      {
        "procedure_name": "阑尾切除术",
        "summary": "2018年5月 · 已恢复",
        "performed_at": "2018-05-01T00:00:00Z",
        "site": "腹部",
        "source_surgery_id": 23
      }
    ]
  },
  "summary": "阑尾切除术 · 2018年5月 · 已恢复"
}
```

### 7.2 删除成功

```json
{
  "deleted": true,
  "surgery": null,
  "member_profile": {
    "surgery_focus": []
  },
  "summary": "无手术史"
}
```

### 7.3 响应原则

1. `surgery` 表示本次 mutation 的对象。
2. `member_profile.surgery_focus` 表示服务端重算后的画像投影。
3. `summary` 用于客户端快速刷新引导页摘要。
4. 客户端不自行维护 profile 手术摘要，以服务端返回为准。

---

## 八、客户端 API 设计

### 8.1 RemoteSurgery

目标：

```swift
struct RemoteSurgery: Codable, Sendable, Equatable {
    let id: Int
    let memberId: Int
    let medicalCase: Int?
    let procedureName: String
    let procedureCode: String?
    let site: String?
    let performedAt: Date?
    let surgeon: String?
    let anesthesiaType: String?
    let incisionLevel: String?
    let asaClass: String?
    let notes: String?
    let extra: [String: JSONValue]?
}
```

重点：

```text
medicalCase 改为 Int?
```

### 8.2 SurgeryMutationResponse

```swift
struct SurgeryMutationResponse: Codable, Sendable, Equatable {
    let deleted: Bool
    let surgery: RemoteSurgery?
    let memberProfile: RemoteMemberMedicalProfileProjection?
    let summary: String?
}
```

### 8.3 API 方法

```swift
func listSurgeries(memberID: Int) async throws -> [RemoteSurgery]
func createSurgery(_ request: SurgeryCreateRequest) async throws -> SurgeryMutationResponse
func updateSurgery(id: Int, request: SurgeryUpdateRequest) async throws -> SurgeryMutationResponse
func deleteSurgery(id: Int) async throws -> SurgeryMutationResponse
```

### 8.4 编码解码要求

使用项目统一编码解码策略：

```text
JSONEncoder.default
JSONDecoder.default
convertToSnakeCase
ISO8601 日期
```

不要手写 `CodingKeys`，除非字段名确实无法通过统一策略覆盖。

---

## 九、SurgeryFormView 重构

### 9.1 当前问题

当前 `SurgeryFormView` 是基础表单：

```text
procedureName
procedureCode
site
performedAt
surgeon
anesthesiaType
incisionLevel
asaClass
notes
```

成员医疗引导里另有一套手术搜索、手术名称、时间、恢复状态、医院、备注表单。

这会导致 UI 和数据流不一致。

### 9.2 目标

参考症状改造：

```text
SymptomFormView
    -> 统一症状分类、搜索、持续时间、严重程度、备注

SurgeryFormView
    -> 统一手术分类、搜索、手术时间、部位、医院、恢复状态、备注
```

关键要求：

```text
成员医疗引导中的「添加手术」必须使用 Sheet 打开 SurgeryFormView。
SurgeryFormView 的页面 UI 复用/迁移 MemberMedicalSetupSheet.surgeryDetailEditor 的设计。
成员医疗引导页本身不再内嵌完整手术编辑表单。
```

也就是说，`MemberMedicalSetupSheet.swift:887-995` 内已经形成的 `surgeryDetailEditor` 交互能力应沉淀到 `SurgeryFormView`：

```text
搜索手术名称
常见手术分类 chips
手术名称
手术时间
恢复状态
主治医院
补充备注
```

这样成员引导、病例详情、AI 识别后的编辑都能使用同一套手术录入页面。

### 9.3 建议新增 SurgeryFormSupport.swift

集中管理：

```text
手术分类
拼音搜索
常见手术 chips
恢复状态选项
麻醉方式选项
summaryLine 摘要拼接
```

示例：

```swift
enum SurgeryFormSupport {
    static let categoryGroups: [SurgeryCategoryGroup]
    static let recoveryOptions: [String]
    static func summaryLine(for surgery: RemoteSurgery) -> String
}
```

### 9.4 SurgeryFormView Mode

目标：参考 `SymptomFormView` 的 `case create(CreateContext)` 设计，不要只在 `Mode.create` 里放零散参数。

```swift
struct SurgeryFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: RemoteSurgery)
        case localEdit(existing: SurgeryRecognitionDraft, onSubmit: (SurgeryRecognitionDraft) -> Void)
    }

    struct CreateContext {
        let memberID: Int
        let medicalCaseID: Int?
        let submissionService: MedicalRecordFormSubmissionService
        let onCreateSubmit: MainActorThrowingAction<SurgeryRecognitionDraft>?
        let onSaved: (([RemoteSurgery], String) -> Void)?
        let onMutation: ((SurgeryMutationResponse) -> Void)?
    }
}
```

Create 模式：

```text
medicalCaseID = nil
    -> 成员级独立手术

medicalCaseID != nil
    -> 病例内手术
```

保存：

```text
直接请求服务器
返回 SurgeryMutationResponse
回调给上层
```

CreateContext 字段职责：

| 字段 | 说明 |
|---|---|
| `memberID` | 手术所属成员 |
| `medicalCaseID` | 可选；为空表示成员级独立手术，有值表示病例内手术 |
| `submissionService` | 复用医疗记录表单提交服务 |
| `onCreateSubmit` | 兼容本地/旧表单提交逻辑 |
| `onSaved` | 保存成功后回调手术列表与摘要 |
| `onMutation` | 保存成功后回调服务端 mutation 响应，推荐成员引导使用 |

### 9.5 Create 回调

新增：

```swift
onSaved: (SurgeryMutationResponse) -> Void
```

或者：

```swift
onSaved: ([RemoteSurgery], String) -> Void
```

推荐使用 mutation response，和症状、用药保持一致。

### 9.6 SurgeryFormView 页面 UI

`SurgeryFormView` 不应继续停留在基础文本表单，应使用成员医疗引导页中已有的 `surgeryDetailEditor` 体验作为统一手术录入 UI。

目标页面结构：

```text
手术记录

搜索手术名称（支持拼音/首字母）

常见手术
┌────────────────────────────┐
│ 普外 / 妇产 / 骨科 / 心血管 │
│ [阑尾切除术] [胆囊切除术]   │
│ [剖宫产] [骨折内固定]       │
└────────────────────────────┘

手术名称        请输入或从上方选择
手术时间        例如 2018年5月
当前恢复状态    已恢复 / 恢复中 / 有后遗症 / 不清楚
主治医院        选填
补充备注        选填

保存
```

UI 来源：

```text
MemberMedicalSetupSheet.surgeryDetailEditor
    -> 迁移/复用到 SurgeryFormView
```

成员医疗引导页只保留：

```text
已有手术卡片列表
添加手术记录按钮
```

不再维护一份独立的内嵌编辑 UI。

---

## 十、成员医疗引导页设计

### 10.1 当前手术页改造目标

位置：

```text
MemberMedicalSetupSheet.swift:887-995
```

当前：

```text
搜索手术名称
选择常见手术
填写手术名称、时间、恢复状态、医院、备注
```

目标：

```text
进入页面时拉取成员已有手术
展示手术卡片列表
手动添加 -> Sheet 打开 SurgeryFormView(mode: .create(CreateContext))
点击卡片 -> Sheet 打开 SurgeryDetailView
新建/编辑/删除后 applySurgeryMutation
```

### 10.2 页面结构

```text
手术史

是否做过手术？
[无手术史] [有手术史]

已有手术记录
┌────────────────────────────┐
│ 阑尾切除术                  │
│ 2018年5月 · 已恢复          │
│ 腹部                       >│
└────────────────────────────┘

添加手术记录
```

### 10.3 添加手术

```text
点击「添加手术记录」
-> Sheet 打开 SurgeryFormView(mode: .create(CreateContext(memberID: memberID, medicalCaseID: nil, ...)))
-> 保存后服务端创建成员级 Surgery
-> 返回 mutation response
-> viewModel.applySurgeryMutation(response)
```

Sheet 打开方式要求：

```text
MemberMedicalSetupSheet
    @State private var isSurgeryFormPresented = false

点击添加手术记录
    isSurgeryFormPresented = true

.sheet(isPresented: $isSurgeryFormPresented) {
    CompatibleNavigationContainer {
        SurgeryFormView(
            mode: .create(
                .init(
                    memberID: memberID,
                    medicalCaseID: nil,
                    submissionService: dependencies.medicalRecordFormSubmissionService,
                    onMutation: { response in
                        viewModel.applySurgeryMutation(response)
                    }
                )
            )
        )
    }
}
```

说明：

```text
成员医疗引导中的添加手术必须走 SurgeryFormView。
不要在 MemberMedicalSetupSheet 内直接保存 surgeryHistory / surgeryTime / surgeryNotes。
```

### 10.4 点击卡片查看详情

```text
点击手术卡片
-> Sheet 打开 SurgeryDetailView
```

`SurgeryDetailView` 是本工单必须新增的独立详情页，不能只使用通用只读兜底页。

参考：

```text
SymptomDetailView
    -> mutation 回调、编辑 Sheet、删除二次确认

MedicationPlanDetailPage
    -> List 分组详情、关联资源展示、底部/工具栏操作
```

详情页展示：

```text
手术详情

阑尾切除术

手术时间        2018年5月
手术部位        腹部
主治医生        未填写
麻醉方式        未填写
切口等级        未填写
ASA分级         未填写
恢复状态        已恢复
关联病例        未关联
来源            手动添加

备注
术后恢复良好

编辑
删除
```

删除需要二次确认：

```text
删除后，该手术记录将不再用于成员医疗画像、AI体检建议和风险评估。
```

### 10.5 SurgeryDetailView 设计

建议新增：

```text
SparkClient/Projects/Features/MedicalRecord/Presentation/NewRecord/Forms/SurgeryDetailView.swift
```

页面职责：

```text
展示单条 RemoteSurgery 的只读详情
支持编辑
支持删除
通过 SurgeryMutationResponse 回调上层刷新列表和 profile 摘要
```

建议初始化参数：

```swift
struct SurgeryDetailView: View {
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onUpdated: (SurgeryMutationResponse) -> Void
    let onDeleted: (Int, SurgeryMutationResponse) -> Void

    init(
        surgery: RemoteSurgery,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        onUpdated: @escaping (SurgeryMutationResponse) -> Void,
        onDeleted: @escaping (Int, SurgeryMutationResponse) -> Void
    )
}
```

内部状态参考 `SymptomDetailView`：

```swift
@State private var currentSurgery: RemoteSurgery
@State private var showingEditSheet = false
@State private var showingDeleteConfirm = false
@State private var alertMessage: String?
@State private var isDeleting = false
```

页面结构使用 `List` 分组，和症状详情页保持一致，同时信息组织参考用药详情页：

```text
Section
  手术名称

Section("手术信息")
  手术时间
  手术部位
  主治医生
  麻醉方式
  切口等级
  ASA分级
  恢复状态
  来源
  关联病例

Section("备注")
  notes

Section
  删除手术
```

字段映射：

| 页面字段 | 数据来源 |
|---|---|
| 手术名称 | `procedureName` |
| 手术时间 | `performedAt` |
| 手术部位 | `site` |
| 主治医生 | `surgeon` |
| 麻醉方式 | `anesthesiaType` |
| 切口等级 | `incisionLevel` |
| ASA分级 | `asaClass` |
| 恢复状态 | `extra.recovery_status` |
| 来源 | `extra.source` |
| 关联病例 | `medicalCase == nil ? "未关联" : "已关联"` |
| 备注 | `notes` |

未填写字段统一展示：

```text
未填写
```

### 10.6 SurgeryDetailView 编辑

右上角提供：

```text
编辑
```

点击后：

```text
Sheet 打开 SurgeryFormView(mode: .serverEdit(existing: currentSurgery))
```

保存成功：

```text
SurgeryFormView
    -> updateSurgery
    -> SurgeryMutationResponse
    -> SurgeryDetailView 更新 currentSurgery
    -> onUpdated(response)
```

伪代码：

```swift
.sheet(isPresented: $showingEditSheet) {
    CompatibleNavigationContainer {
        SurgeryFormView(
            mode: .serverEdit(existing: currentSurgery),
            onServerSubmit: MainActorThrowingAction { draft in
                let response = try await MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
                    .submitSurgeryUpdate(memberID: memberID, existing: currentSurgery, draft: draft)
                if let updated = response.surgery {
                    currentSurgery = updated
                }
                onUpdated(response)
            }
        )
    }
}
```

### 10.7 SurgeryDetailView 删除

点击删除后弹出二次确认：

```text
确认删除手术记录？

删除后，该手术记录将不再用于成员医疗画像、AI体检建议和风险评估。

取消 / 删除
```

确认后：

```text
DELETE /api/v1/medical/surgeries/{id}/
-> SurgeryMutationResponse
-> onDeleted(currentSurgery.id, response)
-> dismiss()
```

失败时：

```text
展示 alertMessage
保持当前详情页
```

### 10.8 成员医疗引导中打开详情

`MemberMedicalSetupSheet` 或拆分后的手术步骤页中：

```text
@State private var selectedSurgery: RemoteSurgery?

点击手术卡片：
    selectedSurgery = surgery

.sheet(item: $selectedSurgery) { surgery in
    CompatibleNavigationContainer {
        SurgeryDetailView(
            surgery: surgery,
            memberID: memberID,
            workflowAPI: workflowAPI,
            onUpdated: { response in
                viewModel.applySurgeryMutation(response)
            },
            onDeleted: { _, response in
                viewModel.applySurgeryMutation(response)
            }
        )
    }
}
```

打开方式要求：

```text
成员医疗引导内使用 Sheet 打开。
病例详情页内可根据现有导航体系选择 push 或 sheet。
```

---

## 十一、客户端 ViewModel 数据流

### 11.1 建议新增状态

```swift
@Published var memberSurgeries: [RemoteSurgery] = []
@Published var surgeryFocus: [RemoteSurgeryFocusItem] = []
```

### 11.2 建议新增方法

```swift
func refreshMemberSurgeriesIfNeeded(force: Bool = false) async
func applySurgeryMutation(_ response: SurgeryMutationResponse)
func ingestProfileSurgeryFocus(_ focus: [RemoteSurgeryFocusItem])
```

### 11.3 applySurgeryMutation 行为

```text
if response.deleted:
    从 memberSurgeries 移除对应手术
else:
    插入或更新 response.surgery

ingestProfileSurgeryFocus(response.member_profile.surgery_focus)
刷新 surgerySummary
```

### 11.4 surgerySummary 优先级

```text
优先使用服务端 member_profile.surgery_focus
其次使用 memberSurgeries 本地列表临时拼接
不再使用引导页内独立 surgeryHistory 文本作为事实源
```

---

## 十二、后端 Workflow 设计

### 12.1 SurgeryWorkflowCreateView

如果当前存在类似 `SymptomWorkflowCreateView` 的手术创建入口，需对齐症状：

```text
medical_case_id 为空时，不自动创建占位病例
直接保存成员级 Surgery
```

创建后：

```text
写入 extra.source = manual / photo_ai / case_document_ai
返回 SurgeryMutationResponse
```

### 12.2 病例详情页内添加手术

病例详情页仍传：

```text
medicalCaseID != nil
```

这样生成病例内手术：

```text
Surgery(member=xxx, medical_case=case)
```

### 12.3 医疗引导内添加手术

成员医疗引导传：

```text
medicalCaseID = nil
```

这样生成成员级手术：

```text
Surgery(member=xxx, medical_case=null)
```

---

## 十三、数据一致性策略

### 13.1 服务端负责 profile 投影

客户端不直接维护 `MemberMedicalProfile.surgery_focus`。

所有变更必须走：

```text
Surgery mutation
    -> 服务端重算 surgery_focus
    -> mutation response 返回 profile
    -> 客户端刷新列表和摘要
```

### 13.2 不自动创建占位病例

成员级手术不是病例，不应该为了满足外键而创建占位病例。

否则会造成：

```text
病例列表出现无意义草稿病例
手术记录归属不清
用户以为自己创建了一个病例
```

### 13.3 手术记录可以后续关联病例

后续可支持：

```text
成员级 Surgery
    -> 用户选择关联病例
    -> PATCH medical_case_id
```

但第一期不必强制做。

---

## 十四、验收标准

### 14.1 服务端

1. `Surgery.medical_case` 支持为空。
2. 成员级手术创建时不自动创建占位病例。
3. 病例详情页添加手术仍可关联 `medical_case`。
4. 创建、编辑、删除手术后重算 `MemberMedicalProfile.surgery_focus`。
5. mutation 响应统一返回 `surgery`、`member_profile`、`summary`。
6. 删除手术后 `surgery_focus` 自动移除对应摘要。

### 14.2 客户端

1. 成员医疗引导手术页进入时拉取成员已有手术。
2. 手术记录以卡片列表展示。
3. 手动添加手术使用 `SurgeryFormView` Sheet。
4. 新建模式 `medicalCaseID=nil` 时保存为成员级手术。
5. 点击卡片打开 `SurgeryDetailView`。
6. 详情页支持编辑和删除。
7. 新建、编辑、删除后调用 `applySurgeryMutation` 更新列表和 profile 摘要。
8. `surgerySummary` 优先以服务端 `surgery_focus` 为准。

---

## 十五、阶段拆分

### 阶段一：服务端成员级手术

1. `Surgery.medical_case` 改为可选。
2. 新增迁移。
3. 手术创建入口支持 `medical_case_id = null`。
4. 不再自动创建占位病例。

### 阶段二：服务端 profile 投影

1. 新增 `MemberMedicalProfile.surgery_focus`。
2. 新增 `recompute_surgery_focus(member)`。
3. 新增 `build_surgery_mutation_payload()`。
4. `Surgery` create / update / destroy 后重算 profile。

### 阶段三：客户端 API

1. `RemoteSurgery.medicalCase` 改为 `Int?`。
2. 新增 `SurgeryMutationResponse`。
3. `createSurgery / updateSurgery / deleteSurgery` 返回 mutation response。
4. `listSurgeries(memberID:)` 查询成员级和病例级手术。

### 阶段四：SurgeryFormView 重构

1. 新增 `SurgeryFormSupport.swift`。
2. 将成员引导里的手术分类、搜索、恢复状态迁入统一表单。
3. `SurgeryFormView.create` 支持 `memberID` 和可选 `medicalCaseID`。
4. 保存后直接请求服务端并回调 mutation response。

### 阶段五：成员医疗引导页

1. 手术页展示成员已有手术卡片。
2. 添加按钮 Sheet 打开 `SurgeryFormView`。
3. 卡片点击 Sheet 打开 `SurgeryDetailView`。
4. 编辑、删除后同步 ViewModel 和 profile 投影。

---

## 十六、最终结论

手术记录应采用和症状、用药一致的架构：

```text
Surgery
    = 手术明细事实源

MemberMedicalProfile.surgery_focus
    = 服务端从有效 Surgery 聚合出的画像投影

客户端
    = 展示明细列表 + 使用统一 SurgeryFormView + 消费 mutation 响应 + 同步 profile 摘要
```

这样可以避免 profile 表单字段和手术明细重复，也能让成员级手术、病例内手术、AI识别手术、首页摘要和 AI 体检计划共享同一套可靠数据。
