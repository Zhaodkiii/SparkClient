# MEDICAL-000003 过往体检档案 AI 体检计划闭环重构工单

关联文档：

- `成员管理/医疗模块引导流程重构需求讨论文档.md`
- `成员管理/医疗模块引导流程重构详细设计文档.md`
- `成员管理/医疗模块引导数据存储模型详细设计文档.md`
- `成员管理/MEMBER-000001-成员模块汇总页与分组维护流程工单.md`
- `成员管理/MEMBER-000002-成员医疗模块汇总页数据加载去重与完整成员缓存工单.md`

关联项目：

- `/Users/hua/Downloads/Reference/SparkClient`
- `/Users/hua/Downloads/Reference/SparkService`

涉及现有能力：

- 客户端体检报告上传与识别：`MedicalDocumentUploadHostView`
- 客户端体检报告引导页：`MemberMedicalExamArchiveStepView`
- 客户端医疗引导主流程：`MemberMedicalSetupSheet`
- AI 场景：`health_exam_extraction`、`report_interpretation`、`medical_structured_extraction`
- 服务端任务系统：`task_system.models.Task`、`TaskMedical`、`TaskNotification`
- 服务端医疗画像投影：`MemberMedicalProfile.exam_plan_summary` / `guidance_sections`
- 服务端关键指标：`MemberMedicalKeyIndicatorRecord`

---

## 一、背景

当前「过往体检档案」流程主要完成：

```text
是否有历史报告
-> 上传/查看体检报告
-> 填写最近一次体检时间
-> 手动维护关键指标
-> 展示下一次体检计划摘要
```

问题是：用户感知仍然偏“档案录入”，没有把体检报告、症状、病史、生活习惯、关键指标真正串成“下一步行动”。

医疗模块的核心价值不应只是存储体检报告，而是：

```text
报告/画像输入
-> AI 识别和解释
-> 生成异常项
-> 生成随访任务
-> 生成下一次体检计划
-> 回写医疗画像和任务系统
-> 首页/模块汇总可持续追踪
```

本工单重构「过往体检档案」页面流程，使其成为 AI Health Agent 的关键闭环。

---

## 二、目标

### 2.1 产品目标

1. 用户有历史报告时，系统通过上传/识别/确认/随访/体检计划形成闭环。
2. 用户没有历史报告时，系统不展示空状态，而是基于已填写的基础档案、病史、症状和生活习惯生成首次体检清单。
3. 让 AI 的推导过程透明化，用户能看到 AI 使用了哪些依据。
4. 生成的随访项目需要进入任务系统，成为可提醒、可完成、可追踪的待办。
5. 生成的体检计划需要回写 `MemberMedicalProfile`，成为医疗模块汇总页的体检档案摘要。

### 2.2 工程目标

1. 复用现有体检报告上传识别流程，不新建平行上传链路。
2. 复用现有 AI 场景配置，不把 prompt 写死在页面里。
3. 复用任务系统 `Task` / `TaskMedical` / `TaskNotification`，不单独创建提醒表。
4. 服务端新增体检档案 AI 计划生成接口，负责聚合输入、调用 AI、保存计划、创建任务。
5. 客户端新增分流 UI、解析确认页、随访生成页、体检计划结果页。

---

## 三、核心流程总览

```text
用户进入「过往体检档案」
   │
   ├─ 有历史报告
   │    │
   │    ├─ 上传/选择已有报告
   │    ├─ AI 解析报告
   │    ├─ 用户确认异常项
   │    ├─ 生成近期随访计划
   │    ├─ 用户确认添加到任务
   │    ├─ 生成下一次体检计划
   │    └─ 回写医疗画像 + completeData 缓存
   │
   └─ 暂无历史报告
        │
        ├─ 展示“无报告也可以生成基线体检单”
        ├─ 汇总基础档案/病史/症状/生活习惯
        ├─ 用户确认让 AI 生成
        ├─ 生成首次体检/排查清单
        └─ 回写医疗画像 + 可选创建任务
```

---

## 四、用户路径设计

### 4.1 Path A：有历史报告

适用场景：

```text
用户手头有 PDF / 图片 / 拍照报告
用户已经在系统中有体检报告记录
用户希望 AI 根据历史异常生成下一步计划
```

完整路径：

```text
过往体检档案引导
-> 选择「有历史报告」
-> 上传/选择报告
-> AI 解析结果确认
-> 随访项目确认
-> 专属体检方案生成中
-> AI 定制体检单结果
-> 过往体检档案汇总
```

### 4.2 Path B：暂无历史报告

适用场景：

```text
用户没有做过体检
用户暂时找不到报告
用户只完成了基础档案/病史/生活习惯/症状
```

完整路径：

```text
过往体检档案引导
-> 选择「暂无历史报告」
-> 无报告价值转换说明
-> 画像依据确认
-> AI 生成首次体检单
-> AI 定制体检单结果
-> 过往体检档案汇总
```

---

## 五、客户端 UI 设计

### 5.1 入口页：过往体检档案

```text
┌────────────────────────────┐
│ ←        过往体检档案       │
├────────────────────────────┤
│                            │
│            📄              │
│         [ 🏥 🔍 ]          │
│            📈              │
│                            │
│  整合并追踪你的体检报告，   │
│  AI 会根据历史异常、病史和  │
│  生活习惯生成下一步计划。   │
├────────────────────────────┤
│  请选择当前情况             │
│                            │
│ ┌────────────────────────┐ │
│ │ 📑 我有历史体检报告     │ │
│ │ 上传或选择已有报告，AI  │ │
│ │ 会提取异常项并生成计划  │ │
│ └────────────────────────┘ │
│                            │
│ ┌────────────────────────┐ │
│ │ ✨ 暂无历史报告         │ │
│ │ 根据已填写健康画像，生成│ │
│ │ 首次体检/排查清单       │ │
│ └────────────────────────┘ │
├────────────────────────────┤
│              跳过           │
└────────────────────────────┘
```

按钮行为：

| 按钮 | 行为 | 打开方式 |
|---|---|---|
| 我有历史体检报告 | 进入报告选择/上传页 | Navigation push |
| 暂无历史报告 | 进入基线生成说明页 | Navigation push |
| 跳过 | 回到过往体检档案汇总；不创建计划 | 当前流程内跳转 |

### 5.2 Path A：报告选择/上传页

```text
┌────────────────────────────┐
│ ←        选择体检报告       │
├────────────────────────────┤
│ 已有报告                    │
│ ┌────────────────────────┐ │
│ │ 2025年度体检报告       │ │
│ │ 某体检中心 · 2025-08   │ │
│ │ 轻度脂肪肝、血脂异常    │ │
│ └────────────────────────┘ │
│                            │
│ ┌────────────────────────┐ │
│ │ 2024年度体检报告       │ │
│ │ 某医院 · 2024-07       │ │
│ └────────────────────────┘ │
├────────────────────────────┤
│                            │
│       拍照 / 上传新报告     │
│                            │
└────────────────────────────┘
```

按钮行为：

| 区域 | 行为 |
|---|---|
| 已有报告卡片 | 选择该报告进入 AI 解析确认 |
| 拍照 / 上传新报告 | 复用 `MedicalAttachmentUploadListSheet` + `MedicalDocumentUploadHostView` |

复用现有代码：

```swift
MedicalAttachmentUploadListSheet(documentType: .healthExamReport, onConfirm: startHealthExamRecognition)

MedicalDocumentUploadHostView(
    viewModel: medicalDocumentUploadViewModel,
    aiSettingsViewModel: aiSettingsViewModel
)
```

### 5.3 Path A：AI 解析结果确认页

```text
┌────────────────────────────┐
│ ←        报告解析完成       │
├────────────────────────────┤
│ AI 已为你提取 2025 年体检  │
│ 报告核心数据。              │
├────────────────────────────┤
│ 发现 3 项主要异常           │
│                            │
│ ☑ 甲状腺结节 TI-RADS 3类   │
│   建议定期复查甲状腺彩超    │
│                            │
│ ☑ LDL-C 偏高 3.8 mmol/L    │
│   需要关注心血管风险        │
│                            │
│ ☑ 轻度脂肪肝               │
│   建议复查肝功能和腹部彩超  │
├────────────────────────────┤
│       编辑异常项            │
│       确认并继续            │
└────────────────────────────┘
```

说明：

1. 默认全选 AI 识别出的异常项。
2. 用户可以取消明显识别错误的异常。
3. 用户可以点击“编辑异常项”调整名称、数值、单位、建议。
4. 确认后进入随访项目生成页。

### 5.4 Path A：随访项目生成页

```text
┌────────────────────────────┐
│ ←        近期随访建议       │
├────────────────────────────┤
│ 针对报告中的异常项，AI 已为 │
│ 你生成近期复查提醒。        │
├────────────────────────────┤
│ ☑ 3个月内复查甲状腺彩超     │
│   来源：甲状腺结节          │
│   优先级：中                │
│                            │
│ ☑ 3个月内复查血脂四项       │
│   来源：LDL-C 偏高          │
│   优先级：中                │
│                            │
│ ☑ 6个月内复查肝功能         │
│   来源：轻度脂肪肝          │
│   优先级：低                │
├────────────────────────────┤
│       稍后再说              │
│       添加至我的随访日程     │
└────────────────────────────┘
```

按钮行为：

| 按钮 | 行为 |
|---|---|
| 稍后再说 | 不创建任务，继续生成下一次体检计划 |
| 添加至我的随访日程 | 创建 `Task(type=medical, source=ai/report)` + `TaskMedical` + 可选 `TaskNotification` |

### 5.5 Path A：专属体检方案生成中

```text
┌────────────────────────────┐
│ ←      正在生成体检方案     │
├────────────────────────────┤
│                            │
│          🎯                │
│                            │
│ 系统正在交叉分析：          │
│                            │
│ ✓ 历史异常指标              │
│ ✓ 生活习惯                  │
│ ✓ 既往病史和家族史          │
│ ✓ 当前症状和用药            │
│                            │
│ 正在为你强化心血管与内分泌  │
│ 筛查，并剔除冗余项目。      │
└────────────────────────────┘
```

### 5.6 Path B：暂无历史报告价值转换页

```text
┌────────────────────────────┐
│ ←        暂无历史报告       │
├────────────────────────────┤
│ 💡 暂无历史数据也没关系     │
│                            │
│ 系统已经掌握你的：          │
│ ✓ 生活习惯                  │
│ ✓ 症状表现                  │
│ ✓ 既往病史                  │
│ ✓ 家族病史                  │
│                            │
│ 即使没有历史报告，AI 也可以 │
│ 生成一份首次体检/排查清单。 │
├────────────────────────────┤
│    让 AI 为我生成定制体检单 │
│    暂不生成                 │
└────────────────────────────┘
```

### 5.7 Path B：画像依据确认页

```text
┌────────────────────────────┐
│ ←        生成依据确认       │
├────────────────────────────┤
│ AI 将基于以下信息生成体检单 │
├────────────────────────────┤
│ 基础档案                    │
│ 女 · 58岁 · 160cm · 60kg   │
│                            │
│ 健康病史                    │
│ 高血压 · 长期用药           │
│                            │
│ 症状观察                    │
│ 近期皮疹/瘙痒               │
│                            │
│ 生活习惯                    │
│ 久坐超过8小时 · 偶尔饮酒    │
├────────────────────────────┤
│       修改资料              │
│       确认生成              │
└────────────────────────────┘
```

### 5.8 AI 定制体检单结果页

```text
┌────────────────────────────┐
│ ←        AI 定制体检单      │
├────────────────────────────┤
│ 生成依据                    │
│ 历史报告 / 病史 / 生活习惯  │
│ / 症状 / 家族史             │
├────────────────────────────┤
│ 必做项目                    │
│ ✓ 血常规                    │
│ ✓ 尿常规                    │
│ ✓ 肝功能                    │
│ ✓ 肾功能                    │
│ ✓ 血脂四项                  │
│ ✓ 空腹血糖                  │
├────────────────────────────┤
│ 建议增加                    │
│ ✓ 甲状腺彩超                │
│ ✓ 腹部彩超                  │
│ ✓ 低剂量胸部 CT             │
├────────────────────────────┤
│ 近期随访                    │
│ ✓ 3个月内复查血脂四项        │
│ ✓ 3个月内复查甲状腺彩超      │
├────────────────────────────┤
│ 医疗说明                    │
│ 本建议仅用于健康管理和体检   │
│ 规划，不替代医生诊断。       │
├────────────────────────────┤
│       保存计划              │
│       添加提醒              │
└────────────────────────────┘
```

### 5.9 过往体检档案汇总页

```text
┌────────────────────────────┐
│ ←        过往体检档案       │
├────────────────────────────┤
│ 已填写内容                  │
│ 2025年度体检报告 · 3项异常  │
│ 已生成 2 项随访 · 已生成体检│
│ 计划                        │
├────────────────────────────┤
│ 体检报告               已完成│
│ 最近一次体检  2025-08      │
│ 异常项          3项          │
│ 随访任务        2项          │
│ 下一次体检计划  已生成       │
├────────────────────────────┤
│       完成                  │
└────────────────────────────┘
```

---

## 六、客户端详细设计

### 6.1 新增/调整页面

体检档案相关页面代码需要单独收敛到独立目录，不再继续堆在 `MemberMedicalSetupSheet.swift` 内。

建议目录：

```text
SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/Medical/ExamArchive/
├─ README.md
├─ MemberMedicalExamArchiveFlowView.swift
├─ MemberMedicalExamArchiveFlowViewModel.swift
├─ MemberMedicalExamArchiveRoute.swift
├─ Models/
│  ├─ MemberMedicalExamArchivePath.swift
│  ├─ MemberMedicalExamAbnormalItemDraft.swift
│  ├─ MemberMedicalExamFollowUpTaskDraft.swift
│  ├─ MemberMedicalExamPlanDraft.swift
│  └─ MemberMedicalExamPlanEvidence.swift
├─ Steps/
│  ├─ MemberMedicalExamArchiveEntryStepView.swift
│  ├─ MemberMedicalExamReportPickerStepView.swift
│  ├─ MemberMedicalExamAIExtractConfirmStepView.swift
│  ├─ MemberMedicalExamFollowUpPlanStepView.swift
│  ├─ MemberMedicalExamPlanGeneratingStepView.swift
│  ├─ MemberMedicalExamPlanResultStepView.swift
│  ├─ MemberMedicalExamBaselineIntroStepView.swift
│  ├─ MemberMedicalExamEvidenceConfirmStepView.swift
│  └─ MemberMedicalExamArchiveSummaryStepView.swift
└─ Components/
   ├─ MemberMedicalExamAbnormalItemCard.swift
   ├─ MemberMedicalExamFollowUpTaskCard.swift
   ├─ MemberMedicalExamPlanSectionCard.swift
   ├─ MemberMedicalExamEvidenceCard.swift
   ├─ MemberMedicalExamReportChoiceCard.swift
   └─ MemberMedicalExamPathChoiceCard.swift
```

`MemberMedicalSetupSheet` 中的 `examArchiveStep` 不再直接承载所有逻辑，只作为入口：

```text
examArchiveIntro
-> MemberMedicalExamArchiveFlowView
-> 完成后回写 viewModel.examPlanLines / examPlanSummary / memberHealthExamReports
-> 返回 examArchiveSummary
```

### 6.1.1 旧体检档案引导流程下线

当前旧流程中的以下提示和页面逻辑不再用于成员建档「过往体检档案」：

```text
是否有历史体检报告
历史体检信息补全
电子体检报告导入（推荐）
最近一次体检时间
体检机构
体检报告摘要
体检指标手动表单作为主流程
系统生成的下一次体检计划静态列表
```

这些内容不再作为主流程页面展示，原因：

```text
旧流程仍然是“录入档案 -> 手动补充 -> 静态计划”的表单思路；
新流程需要改为“报告/画像输入 -> AI 推导 -> 随访任务 -> 体检计划”的行动闭环。
```

处理规则：

```text
MemberMedicalSetupSheet.examArchiveIntro:
    保留入口介绍，但点击开始后直接进入 MemberMedicalExamArchiveFlowView。

MemberMedicalSetupSheet.examArchiveStep:
    不再展示旧的 MemberMedicalExamArchiveStepView 表单。
    改为包一层新 flow 或直接 push 到 ExamArchive/MemberMedicalExamArchiveFlowView。

MemberMedicalSetupSheet.examPlanStep:
    不再展示旧的静态计划页。
    由新 flow 的 MemberMedicalExamPlanResultStepView 替代。

MemberMedicalSetupSheet.keyIndicatorStep:
    不作为过往体检档案主流程必经页。
    异常项优先来自 AI 解析和用户确认。
    后续如需要手动补充指标，可作为“编辑异常项/补充指标”的辅助入口。
```

需要保留但不作为建档主流程的页面：

```text
HealthExamReportsListPage:
    保留。它是正式医疗档案列表页，不属于成员建档引导主流程。

MedicalDocumentUploadHostView:
    保留。新流程继续复用它做体检报告上传和识别。

MedicalAttachmentUploadListSheet:
    保留。新流程继续复用它选择拍照、文件、图片。

MemberMedicalExamIndicatorStepView:
    第一阶段不删除。
    从主流程中降级为异常项编辑/补充指标的可选辅助页。
```

旧文案移除范围：

```text
成员建档过往体检档案流程内，不再出现：
- “暂无已导入报告，可通过下方拍照或上传电子版快速录入。”
- “历史体检信息补全”
- “系统将启动 AI 智能 OCR 识别，自动提取您的异常指标与结论。”
- “系统生成的下一次体检计划”
```

新文案统一围绕：

```text
有报告：AI 看懂报告 -> 确认异常 -> 生成随访 -> 生成体检计划
无报告：没有报告也能基于健康画像生成首次体检单
```

### 6.2 路由设计

```swift
enum MemberMedicalExamArchiveRoute: Hashable {
    case entry
    case reportPicker
    case aiExtractConfirm(reportID: Int)
    case followUpPlan
    case planGenerating
    case planResult
    case baselineIntro
    case evidenceConfirm
    case summary
}
```

### 6.3 ViewModel 状态

```swift
@MainActor
final class MemberMedicalExamArchiveFlowViewModel: ObservableObject {
    @Published var selectedPath: ExamArchivePath?
    @Published var selectedReport: RemoteHealthExamReportWithAttachments?
    @Published var abnormalItems: [RemoteExamAbnormalItemDraft] = []
    @Published var selectedAbnormalItemIDs: Set<String> = []
    @Published var followUpTasks: [RemoteMedicalFollowUpTaskDraft] = []
    @Published var selectedFollowUpTaskIDs: Set<String> = []
    @Published var generatedPlan: RemoteMedicalExamPlanDraft?
    @Published var evidenceSnapshot: RemoteMedicalExamPlanEvidence?
    @Published var loadState: LoadState = .idle
}
```

### 6.4 与现有上传识别链路衔接

上传仍复用：

```swift
MedicalAttachmentUploadListSheet(documentType: .healthExamReport, onConfirm: startHealthExamRecognition)
MedicalDocumentUploadHostView(viewModel: medicalDocumentUploadViewModel, aiSettingsViewModel: aiSettingsViewModel)
```

上传保存成功后：

```text
MedicalDocumentUploadViewModel.saveSucceededRevision
-> 重新拉取/patch completeData.healthExamReports
-> 自动进入 aiExtractConfirm(reportID)
```

### 6.5 本地化

新增文案必须进入：

```text
SparkClient/Projects/App/Resources/en.lproj/Localizable.strings
SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
```

Prompt 进入：

```text
SparkClient/Projects/App/Resources/en.lproj/Prompts.strings
SparkClient/Projects/App/Resources/zh-Hans.lproj/Prompts.strings
```

不要在 Swift 页面中硬编码长文案和 prompt。

---

## 七、服务端接口设计

### 7.1 生成体检档案 AI 计划

```text
POST /api/v1/medical/members/{member_id}/exam-archive/ai-plan/
```

请求：

```json
{
  "mode": "report_based",
  "health_exam_report_id": 100,
  "selected_abnormal_items": [
    {
      "code": "ldl_c_high",
      "name": "低密度脂蛋白偏高",
      "value": "3.8",
      "unit": "mmol/L",
      "severity": "medium"
    }
  ],
  "create_follow_up_tasks": true,
  "selected_follow_up_task_keys": [
    "thyroid_ultrasound_3m",
    "blood_lipid_3m"
  ]
}
```

无报告模式：

```json
{
  "mode": "baseline",
  "health_exam_report_id": null,
  "create_follow_up_tasks": false
}
```

响应：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "mode": "report_based",
    "member_id": 597,
    "source_report_id": 100,
    "abnormal_items": [],
    "follow_up_tasks": [],
    "created_tasks": [],
    "exam_plan": {
      "title": "2026 年度 AI 定制体检单",
      "must_items": [],
      "recommended_items": [],
      "follow_up_items": [],
      "rationale": [],
      "risk_notice": "本建议仅用于健康管理和体检规划，不替代医生诊断。"
    },
    "member_medical_profile": {},
    "guidance_sections": []
  }
}
```

### 7.2 仅预览报告异常项

```text
POST /api/v1/medical/members/{member_id}/exam-archive/preview-abnormal-items/
```

用途：

```text
用户选择已有报告后，先从报告明细和 AI 解读中提取异常项；
不创建任务，不写入体检计划。
```

### 7.3 保存用户确认后的异常项

```text
POST /api/v1/medical/members/{member_id}/exam-archive/confirmed-abnormal-items/
```

用途：

```text
记录用户确认后的异常项；
用于后续体检计划和风险评估；
可以落到 MemberMedicalKeyIndicatorRecord。
```

### 7.4 任务创建

可由 `ai-plan` 接口内部创建，也可拆成：

```text
POST /api/v1/tasks/medical/bulk-create/
```

第一期建议由 `ai-plan` 内部创建，避免客户端串多个接口导致状态不一致。

---

## 八、服务端数据存储设计

### 8.1 体检计划草稿/结果

建议新增模型：

```python
class MemberMedicalExamPlan(models.Model):
    class Source(models.TextChoices):
        AI_REPORT = "ai_report", "ai_report"
        AI_BASELINE = "ai_baseline", "ai_baseline"
        MANUAL = "manual", "manual"

    class Status(models.TextChoices):
        DRAFT = "draft", "draft"
        CONFIRMED = "confirmed", "confirmed"
        ARCHIVED = "archived", "archived"

    user = models.ForeignKey(User, related_name="medical_exam_plans", on_delete=models.CASCADE, db_index=True, db_comment="创建账号")
    member = models.ForeignKey(Member, related_name="medical_exam_plans", on_delete=models.CASCADE, db_index=True, db_comment="所属成员")
    source = models.CharField(max_length=32, choices=Source.choices, db_index=True, db_comment="来源：报告AI、基线AI、手动")
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.CONFIRMED, db_index=True, db_comment="计划状态")
    source_report = models.ForeignKey(HealthExamReport, related_name="generated_exam_plans", on_delete=models.SET_NULL, null=True, blank=True, db_comment="来源体检报告")
    title = models.CharField(max_length=128, db_comment="计划标题")
    must_items = models.JSONField(default=list, blank=True, db_comment="必做体检项目")
    recommended_items = models.JSONField(default=list, blank=True, db_comment="建议增加项目")
    follow_up_items = models.JSONField(default=list, blank=True, db_comment="近期随访复查项目")
    rationale = models.JSONField(default=list, blank=True, db_comment="生成依据说明")
    risk_notice = models.TextField(blank=True, default="", db_comment="医疗风险提示")
    ai_trace_id = models.CharField(max_length=64, blank=True, default="", db_index=True, db_comment="AI 调用链路 ID")
    prompt_version = models.CharField(max_length=32, blank=True, default="", db_comment="Prompt 版本")
    model_name = models.CharField(max_length=128, blank=True, default="", db_comment="实际使用模型")
    extra = models.JSONField(default=dict, blank=True, db_comment="扩展信息")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)
```

### 8.2 异常项确认记录

建议复用 `MemberMedicalKeyIndicatorRecord`：

```text
source = report_extraction
scenario = exam_plan
title = 体检报告异常项确认
summary = 甲状腺结节 · LDL-C 偏高 · 轻度脂肪肝
extra = {
  "source_report_id": 100,
  "confirmed_abnormal_items": [...]
}
```

如果后续异常项需要独立检索和趋势分析，再新增：

```text
MemberMedicalAbnormalFinding
```

第一期不建议新增，避免表过多。

### 8.3 随访任务存储

复用任务系统：

```text
Task
    type = medical
    source = ai 或 report
    business_type = medical_exam_follow_up
    business_id = MemberMedicalExamPlan.id 或 HealthExamReport.id

TaskMedical
    medical_task_type = thyroid_ultrasound_follow_up / blood_lipid_follow_up / liver_function_follow_up
    reminder_time = 建议复查时间
    source = ai_report

TaskNotification
    channel = local / apns
    reminder_time = 同 TaskMedical.reminder_time
```

### 8.4 MemberMedicalProfile 投影

生成体检计划后更新：

```text
MemberMedicalProfile.exam_plan_summary
MemberMedicalProfile.guidance_sections[exam_archive].summary
MemberMedicalProfile.guidance_sections[exam_archive].status
MemberMedicalProfile.guidance_updated_at
```

注意：

```text
MemberMedicalProfile 只保存摘要投影；
MemberMedicalExamPlan 是计划事实源；
Task/TaskMedical 是随访任务事实源。
```

---

## 九、AI 设计

### 9.1 AI 场景

复用现有：

```text
health_exam_extraction：体检报告结构化抽取
report_interpretation：报告解读和异常解释
medical_structured_extraction：医疗结构化补充抽取
```

新增建议：

```text
medical_exam_plan_generation
```

如果不想新增场景，第一期可使用：

```text
report_interpretation
```

但建议新增独立场景，原因：

```text
体检计划生成不是单纯解释报告；
它需要输出固定 JSON：必做项目、建议项目、随访项目、依据、风险提示；
模型温度、最大 token、工具权限都应独立配置。
```

客户端需要同步：

```swift
case medicalExamPlanGeneration = "medical_exam_plan_generation"
```

服务端需要同步：

```python
MEDICAL_EXAM_PLAN_GENERATION = "medical_exam_plan_generation"
```

### 9.2 Prompt 输入

输入必须包含：

```text
成员基础档案：性别、年龄、身高、体重、BMI
既往病史：慢病、手术、过敏
家族病史
生活习惯：吸烟、饮酒、运动、睡眠、久坐
症状记录
用药计划
手术记录
历史体检报告摘要
异常指标
用户确认后的异常项
```

### 9.3 AI 输出 JSON

```json
{
  "abnormal_items": [
    {
      "key": "ldl_c_high",
      "name": "低密度脂蛋白偏高",
      "value": "3.8",
      "unit": "mmol/L",
      "severity": "medium",
      "reason": "与心血管风险相关"
    }
  ],
  "follow_up_tasks": [
    {
      "key": "blood_lipid_3m",
      "title": "3个月内复查血脂四项",
      "medical_task_type": "blood_lipid_follow_up",
      "due_in_days": 90,
      "priority": "medium",
      "source_abnormal_key": "ldl_c_high"
    }
  ],
  "exam_plan": {
    "title": "AI 定制体检单",
    "must_items": [],
    "recommended_items": [],
    "follow_up_items": [],
    "rationale": [],
    "risk_notice": "..."
  }
}
```

### 9.4 AI 安全边界

必须在结果页展示：

```text
本建议仅用于健康管理和体检规划，不替代医生诊断。
如有明显不适、症状加重或急症风险，请及时就医。
```

AI 不得输出：

```text
确诊结论
治疗方案替代医生
停药/换药建议
保证性判断
```

---

## 十、接口与缓存联动

### 10.1 生成成功后客户端缓存 patch

成功响应后：

```text
completeData.healthExamReports upsert source report
completeData.memberMedicalProfile = response.memberMedicalProfile
completeData.memberMedicalProfile.examPlanSummary = response.examPlan.summary
completeData.memberMedicalProfile.guidanceSections = response.guidanceSections
```

如果创建任务：

```text
任务列表缓存如果存在，追加 createdTasks
否则不强制拉任务列表
```

### 10.2 completeData ETag

服务端 ETag 需要纳入：

```text
MemberMedicalExamPlan.updated_at
Task/TaskMedical updated_at where business_type=medical_exam_follow_up
MemberMedicalProfile.updated_at
HealthExamReport.updated_at
MemberMedicalKeyIndicatorRecord.updated_at where scenario=exam_plan
```

否则生成计划后回到医疗模块汇总页可能仍命中旧 304。

---

## 十一、日志要求

客户端：

```text
体检档案流程：进入 memberID=597 mode=entry
体检档案流程：选择有历史报告 memberID=597
体检档案流程：上传报告完成 reportID=100
体检档案流程：AI 异常项预览成功 reportID=100 count=3
体检档案流程：用户确认异常项 count=3
体检档案流程：生成随访任务 count=2 createTasks=1
体检档案流程：AI 体检计划生成成功 planID=10 must=6 recommended=3 followUp=2
体检档案流程：缓存已更新 memberID=597 hasProfile=1
```

服务端：

```text
exam-plan 开始 member_id=597 mode=report_based report_id=100
exam-plan 聚合上下文完成 member_id=597 symptoms=2 medications=1 surgeries=1 reports=1
exam-plan AI 调用开始 scenario=medical_exam_plan_generation trace_id=...
exam-plan AI 调用成功 abnormal=3 followUp=2 must=6 recommended=3
exam-plan 创建随访任务 count=2 member_id=597
exam-plan 更新 MemberMedicalProfile member_id=597 plan_id=10
```

---

## 十二、验收标准

### 12.1 Path A：有历史报告

1. 用户可选择已有报告或上传新报告。
2. 上传新报告复用现有 `MedicalDocumentUploadHostView`。
3. AI 提取异常项后进入确认页。
4. 用户可取消错误异常项。
5. 确认后生成随访建议。
6. 用户选择添加随访后，服务端创建 `Task` / `TaskMedical`。
7. 生成体检计划后，结果页展示必做、建议增加、近期随访和依据。
8. 完成后回到过往体检档案汇总页，显示已生成计划。
9. 医疗模块汇总页 `过往体检档案` 卡片显示最新计划摘要。

### 12.2 Path B：暂无历史报告

1. 用户选择暂无历史报告后，不展示空状态。
2. 页面展示已掌握的基础档案、病史、症状、生活习惯。
3. 用户确认后可生成首次体检/排查清单。
4. 生成结果保存到 `MemberMedicalExamPlan`。
5. `MemberMedicalProfile.examPlanSummary` 更新。

### 12.3 服务端

1. 生成计划接口有权限校验，参考医疗档案成员权限。
2. AI 输出 JSON 校验失败时返回可理解错误，不写入脏数据。
3. 创建任务和保存计划要么事务成功，要么整体回滚。
4. 不因 AI 失败影响用户已有体检报告保存。
5. ETag 能随计划、任务、profile 更新而变化。

### 12.4 客户端

1. 所有长文案本地化。
2. 生成中页面有 loading 和取消返回保护。
3. 失败可重试。
4. 不重复上传报告。
5. 保存成功后 patch `MemberModuleSetupCacheContext.completeData`。

---

## 十三、分阶段实现

### 阶段一：客户端 UI 重构

1. 新建 `ExamArchive` 子目录。
2. 拆出入口、报告选择、无报告说明、依据确认、结果页。
3. 保持现有上传识别链路可用。

### 阶段二：服务端 AI 计划接口

1. 新增 `MemberMedicalExamPlan`。
2. 新增 `exam-archive/ai-plan/`。
3. AI 输出校验。
4. 回写 `MemberMedicalProfile`。

### 阶段三：随访任务闭环

1. AI 生成随访任务草稿。
2. 用户确认后创建 `Task` / `TaskMedical` / `TaskNotification`。
3. 任务与报告/计划建立 business_type/business_id 关联。

### 阶段四：缓存与汇总页联动

1. 生成成功后 patch completeData。
2. 医疗模块汇总页显示最新体检计划摘要。
3. completeData ETag 纳入计划和任务更新时间。

### 阶段五：AI 场景独立化

1. 新增 `medical_exam_plan_generation` 场景。
2. 服务端 ai_config 增加枚举。
3. 客户端 AIScenario 增加枚举。
4. Prompts.strings 增加体检计划生成 prompt。

---

## 十四、本工单不做的事

```text
不做完整诊断系统
不替代医生给治疗方案
不做线下体检机构预约
不做医保/支付流程
不做癌症筛查指南全量规则引擎
不删除现有 HealthExamReportsListPage
不重写已有 MedicalDocumentUploadHostView，只复用其上传识别能力
不保留成员建档中过往体检档案旧表单式引导作为主流程
```

---

## 十五、最终结论

本工单将「过往体检档案」从“报告录入页”升级为“AI 体检计划闭环”：

```text
有报告：
    上传/选择报告
    -> AI 解析异常
    -> 用户确认
    -> 生成随访任务
    -> 生成下一次体检计划

无报告：
    汇总已有健康画像
    -> AI 生成首次体检/排查清单

最终：
    写入 MemberMedicalExamPlan
    创建 Task/TaskMedical
    更新 MemberMedicalProfile
    刷新医疗模块汇总页
```

核心原则：

```text
报告是输入；
异常项是解释；
随访任务是行动；
体检计划是结果；
MemberMedicalProfile 只保存摘要投影；
MemberMedicalExamPlan 和 Task 才是事实源。
```
