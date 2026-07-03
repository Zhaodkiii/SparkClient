# MEDICAL-SHARE-000002 医疗详情对象 Web 分享详设工单

> 状态：新需求 / 待实现  
> 创建日期：2026-07-03  
> 前置依赖：`MEDICAL-SHARE-000001 病例 Web 分享详设工单` 已建立分享记录、分享码、公开访问、Web 分享页、客户端公共分享组件基础能力。  
> 范围：体检报告详情页、医疗检查报告详情页、处方详情页、服药计划详情页、药品详情页右上角分享入口；服务端扩展对应业务类型公开分享 payload；Web 分享页按业务类型渲染独立详情页面。

## 1. 背景与目标

`MEDICAL-SHARE-000001` 首期只支持病例详情页分享。当前医疗档案中还有多个独立详情页也需要支持外部分享：用户在 App 内查看某一份体检报告、检查报告、处方、服药计划或药品详情时，可以从右上角菜单直接生成 10 天有效的公开 Web 分享链接，让外部用户看到与手机客户端详情页一致的核心内容。

本工单目标：

1. 五类详情页右上角菜单增加“分享”入口。
2. 复用 `000001` 的客户端公共分享组件、分享域名、分享码、有效期、微信/小红书/复制链接能力。
3. 服务端 `MedicalShareRecord.BusinessType` 扩展五类业务类型。
4. 服务端公开接口根据 `business_type + business_id` 加载对应详情 payload。
5. Web 分享页在 `/s/{share_code}` 内按业务类型渲染对应详情页面。
6. 公开分享页只展示只读内容，不展示编辑、删除、管理附件、绑定病例、新增记录等 App 内管理操作。

本工单不做代码实现，只作为后续执行工单的详细设计。

## 2. 业务范围

本期新增 5 个分享业务对象：

| 业务对象 | 业务类型码 | iOS 详情页 | 服务端主表 | Web 页面定位 |
| --- | --- | --- | --- | --- |
| 体检报告 | `health_exam_report` | `HealthExamRecognitionResultView` detail 模式 | `HealthExamReport` | 体检报告详情页 |
| 医疗检查报告 | `examination_report` | `ExaminationReportDetailPage` server 模式 | `ExaminationReport` | 检查/检验报告详情页 |
| 处方 | `prescription` | `MedicationPrescriptionDetailPage` server 模式 | `Prescription` | 处方详情页，含关联服药计划 |
| 服药计划 | `medication_plan` | `MedicationPlanDetailPage` server 模式 | `MedicationPlan` | 服药计划详情页，含药品与服药记录摘要 |
| 药品 | `medicine_box` | `MedicineBoxDetailPage` server 模式 | `MedicineBox` | 药品详情页，含库存、效期、关联计划摘要 |

说明：

1. 本期只支持服务端已保存详情对象分享。识别结果草稿、本地草稿、未保存对象不生成公开分享。
2. Web 分享页不要求完整复刻 App 的所有交互，只要求内容层级、卡片布局、关键字段、附件展示与手机客户端详情页一致。
3. 仍使用同一分享入口：`https://share.dreamwhale.top/s/{share_code}`。
4. 分享有效期继续固定 10 天。
5. 下载 App 链接继续使用 `https://apps.apple.com/cn/app/id6751417431`。

## 3. 实现阶段建议使用的 Skill

本工单横跨 iOS、服务端、Web、隐私安全、部署和验收。实现时建议按阶段灵活使用已安装 skill，不要求每次全部启用；遇到某一类问题时再调用对应 skill，避免上下文过重。

| 阶段 | 推荐 Skill | 如何使用 | 产出重点 |
| --- | --- | --- | --- |
| 范围复核与拆任务 | `产品经理` | 开工前快速复核本工单范围、非目标、验收标准，确认 5 类业务对象是否仍是本期范围 | 防止范围扩散；明确本期不做草稿分享、不做编辑能力、不做新渠道 |
| 服务端设计与实现 | `后端接口架构师` | 扩展 `MedicalShareRecord.BusinessType`、公开 payload 分发、对象权限校验、关联数据聚合时使用 | 稳定的业务类型模型、统一接口契约、可扩展 payload builder |
| 数据与查询优化 | `数据库优化工程师` | 设计多业务对象查询、处方关联服药计划、药品关联计划、最近服药记录查询时使用 | 避免 N+1；确认索引够用；明确查询边界和排序 |
| iOS 接入 | `移动端应用工程师` | 给 5 个 SwiftUI 详情页右上角菜单接入分享入口、处理草稿模式禁用、复用公共分享 Sheet 时使用 | 接入一致、不重复造组件、失败态清晰 |
| Web 页面实现 | `前端页面工程师` | `share-web` 增加五类详情组件、payload 类型解析、附件展示、下载 CTA 时使用 | 可维护的 Vue 组件结构、响应式详情页、构建通过 |
| Web 布局与体验 | `体验架构师` | 校准手机、Pad、桌面比例；定义详情页信息层级、卡片密度、子卡片样式时使用 | 与 000001 视觉一致；手机端接近 SwiftUI；桌面不后台化 |
| 安全与隐私 | `应用安全工程师` | 评审分享码、公开接口、附件签名 URL、`raw_ocr` / `extra` 脱敏、日志内容时使用 | 避免公开敏感字段；确保过期/撤销不可访问 |
| API 测试 | `接口测试工程师` | 为创建分享、公开访问、过期、删除、无权限、各业务 payload 写测试时使用 | 覆盖 5 类业务对象和关键异常路径 |
| 代码评审 | `代码审查员` | 实现完成后做一次变更审查，重点看权限、重复逻辑、payload 兼容、测试缺口 | 找出回归风险和维护风险 |
| 真实验收 | `真实验收检查员` | 联调完成后，用真实链接、截图、构建结果、接口返回作为证据验收 | 防止“只看代码觉得完成”；确认页面和数据真的可访问 |
| 部署联调 | `部署运维工程师` | `share-web` 打包、nginx、域名、反代、缓存和线上配置检查时使用 | 确保 `share.dreamwhale.top` 和 App Store 下载链接在线可用 |
| 文档收尾 | `技术文档编写员` | 实现后更新工单状态、接口说明、部署说明、已知限制时使用 | 形成可交接记录，方便后续 `000003` 或更多业务扩展 |

推荐使用顺序：

1. 开工拆解：`产品经理` + `后端接口架构师` + `移动端应用工程师`。
2. 服务端实现：`后端接口架构师` + `数据库优化工程师` + `应用安全工程师`。
3. Web 实现：`前端页面工程师` + `体验架构师`。
4. 验证收口：`接口测试工程师` + `代码审查员` + `真实验收检查员`。
5. 上线准备：`部署运维工程师` + `技术文档编写员`。

实际执行时的推荐提示语示例：

```text
使用 后端接口架构师，按 MEDICAL-SHARE-000002 实现服务端业务类型扩展和公开 payload builder。
使用 移动端应用工程师，给 MEDICAL-SHARE-000002 中的 5 个 SwiftUI 详情页接入公共分享入口。
使用 前端页面工程师 和 体验架构师，实现 MEDICAL-SHARE-000002 的 share-web 多业务详情页面，并对齐 000001 的视觉密度。
使用 应用安全工程师，审查 MEDICAL-SHARE-000002 的公开 payload 是否泄露 raw_ocr、extra、成员绑定和私有附件地址。
使用 真实验收检查员，基于真实分享链接、移动端截图、接口响应和构建结果验收 MEDICAL-SHARE-000002。
```

## 4. 现状代码参考

### iOS 关键代码

| 页面 | 文件 | 当前右上角菜单情况 | 本工单改造点 |
| --- | --- | --- | --- |
| 体检报告详情 | `SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/ResultPages/HealthExamRecognitionResultView.swift` | detail 模式已有导出、分享、编辑、删除占位，其中分享按钮为空实现 | 接入公共分享组件，传 `business_type=health_exam_report`、`business_id=detailReportID` |
| 医疗检查报告详情 | `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/ExaminationReports/ExaminationReportDetailPage.swift` | 右上角菜单只有编辑、删除 | 增加分享按钮，server 模式启用，localDraft 禁用或隐藏 |
| 处方详情 | `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPrescriptionDetailPage.swift` | 右上角菜单只有编辑、删除 | 增加分享按钮，分享处方及关联用药计划 |
| 服药计划详情 | `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanDetailPage.swift` | 右上角菜单只有编辑、删除 | 增加分享按钮，分享用药计划、关联药品、服药记录摘要 |
| 药品详情 | `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/MedicineBoxDetailPage.swift` | 右上角菜单只有编辑、删除 | 增加分享按钮，分享药品库存、效期、附件与关联计划摘要 |

### 服务端关键代码

| 模块 | 文件 | 当前情况 | 本工单改造点 |
| --- | --- | --- | --- |
| 分享记录模型 | `SparkService/medical/models.py` | `MedicalShareRecord.BusinessType` 仅支持 `medical_case` | 扩展 5 个业务类型码 |
| 分享创建 serializer | `SparkService/medical/serializers.py` | `MedicalShareCreateSerializer.business_type` 使用模型 choices | choices 扩展后自动支持；需补业务对象校验 |
| 分享服务 | `SparkService/medical/services/medical_share_service.py` | `_supported_business_types()` 和 `build_public_share_payload()` 只支持病例 | 增加业务分发、对象权限校验、公开 payload 聚合 |
| 分享视图 | `SparkService/medical/views.py` | 创建分享、公开分享详情已存在 | 复用接口；根据扩展后的 service 返回不同 payload |
| 附件 | `file_manager` 业务绑定 | 已支持 `health_exam_report`、`examination_report`、`prescription_batch`、`medication_plan`、`medicine_box` | 公开分享继续使用短时签名 URL，不暴露私有 object key |

### Web 关键代码

| 模块 | 当前情况 | 本工单改造点 |
| --- | --- | --- |
| `SparkService/share-web/src/views/ShareCaseView.vue` | 当前以病例和病例时间轴为主 | 改造成业务类型分发容器，或新增 detail components |
| `SparkService/share-web/src/api.ts` | 已有 `ShareCasePayload` 类型 | 增加通用 `SharePayload` union 类型与五类 detail payload 类型 |
| `SparkService/share-web/src/style.css` | 已有白底卡片、时间轴、详情 sheet、附件胶囊样式 | 增加详情页通用信息卡、指标列表、用药计划卡、药品库存卡样式 |

## 5. 推荐目录结构

### iOS

继续复用 `000001` 的公共分享能力，不为每个详情页复制一套分享逻辑。

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Share/
  ShareAPI.swift
  ShareDTO.swift

SparkClient/SparkClient/Projects/Features/Common/Share/
  ShareSheetView.swift
  ShareChannel.swift
  ShareActionHandler.swift
  ShareableMedicalResource.swift          # 可选：统一业务类型和标题摘要生成

SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/ResultPages/
  HealthExamRecognitionResultView.swift   # detail 模式接入分享

SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/ExaminationReports/
  ExaminationReportDetailPage.swift       # server 模式接入分享

SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/
  MedicationPrescriptionDetailPage.swift  # 接入分享
  MedicationPlanDetailPage.swift          # 接入分享

SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/
  MedicineBoxDetailPage.swift             # 接入分享
```

### 服务端

```text
SparkService/medical/
  models.py
  serializers.py
  views.py
  urls.py
  services/
    medical_share_service.py              # 业务类型分发与公开 payload 聚合
    medical_share_payload_builders.py      # 可选：拆出各业务 payload builder，避免 service 过长
  tests.py                                # 增加多业务分享测试
```

如后续实现时 `medical_share_service.py` 继续膨胀，建议拆分为：

```text
SparkService/medical/services/share_payload/
  __init__.py
  common.py
  medical_case.py
  health_exam_report.py
  examination_report.py
  prescription.py
  medication_plan.py
  medicine_box.py
```

### Web

```text
SparkService/share-web/src/
  api.ts
  views/
    ShareCaseView.vue                     # 可继续作为 /s/:shareCode 容器
  components/
    ShareExpiredState.vue
    ShareDownloadPanel.vue
    ShareAttachmentList.vue
    DetailInfoGrid.vue
    DetailSection.vue
    HealthExamShareDetail.vue
    ExaminationReportShareDetail.vue
    PrescriptionShareDetail.vue
    MedicationPlanShareDetail.vue
    MedicineBoxShareDetail.vue
```

## 6. 业务类型与分享记录模型

扩展 `MedicalShareRecord.BusinessType`：

```python
class BusinessType(models.TextChoices):
    MEDICAL_CASE = "medical_case", "medical_case"
    HEALTH_EXAM_REPORT = "health_exam_report", "health_exam_report"
    EXAMINATION_REPORT = "examination_report", "examination_report"
    PRESCRIPTION = "prescription", "prescription"
    MEDICATION_PLAN = "medication_plan", "medication_plan"
    MEDICINE_BOX = "medicine_box", "medicine_box"
```

复用现有字段：

```text
business_type
business_id
share_code
member
user
expires_at
status
access_count
last_accessed_at
extra
```

索引沿用 `000001`，无需为新增类型创建单独表。

分享复用规则：

1. 同一用户、同一成员、同一 `business_type + business_id` 存在未过期 active 分享记录时继续复用。
2. 分享标题 `title` 按业务对象当前标题刷新。
3. 每个对象独立生成分享码；病例分享和处方分享即使有关联，也不是同一条分享记录。

## 7. 服务端接口设计

### 7.1 创建分享记录

沿用既有接口：

```http
POST /api/v1/medical/shares/
Authorization: Bearer <token>
Content-Type: application/json
```

请求示例：

```json
{
  "business_type": "prescription",
  "business_id": 123
}
```

响应沿用既有结构：

```json
{
  "code": 0,
  "msg": "created",
  "data": {
    "share_code": "AbC123xYz789",
    "share_url": "https://share.dreamwhale.top/s/AbC123xYz789",
    "business_type": "prescription",
    "business_id": 123,
    "expires_at": "2026-07-13T08:00:00+08:00",
    "status": "active",
    "created": true
  }
}
```

### 7.2 获取公开分享详情

沿用既有接口：

```http
GET /api/v1/medical/shares/public/<share_code>/
```

响应增加 `payload_type`，Web 按类型分发渲染：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "share": {
      "share_code": "AbC123xYz789",
      "business_type": "prescription",
      "business_id": 123,
      "status": "active",
      "expires_at": "2026-07-13T08:00:00+08:00",
      "title": "东部战区总医院",
      "share_url": "https://share.dreamwhale.top/s/AbC123xYz789"
    },
    "member": {
      "id": 9,
      "display_name": "张**",
      "gender": "female",
      "age_text": "40岁"
    },
    "payload_type": "prescription",
    "payload": {},
    "download_app": {
      "title": "下载 App 查看和管理完整健康档案",
      "description": "当前链接已经进入公开分享页。你可以下载 Spark App 继续查看完整内容。",
      "button_text": "下载 App",
      "url": "https://apps.apple.com/cn/app/id6751417431"
    }
  }
}
```

兼容策略：

1. 病例分享现有 `case + timeline` payload 可以继续保留。
2. 新增业务建议统一放入 `payload_type + payload`，避免未来继续扩展时顶层字段无限增加。
3. Web 需要同时兼容病例旧结构和新结构。

## 8. 服务端权限与对象解析

创建分享时必须校验登录用户对对象所属成员有编辑权限；公开访问时只校验分享码和有效期，不要求登录。

对象解析规则：

| 业务类型 | 查询条件 | 所属成员 | 创建分享权限 |
| --- | --- | --- | --- |
| `health_exam_report` | `HealthExamReport.id = business_id AND is_deleted = false` | `report.member` | 当前用户可编辑该成员 |
| `examination_report` | `ExaminationReport.id = business_id AND is_deleted = false` | `report.member` | 当前用户可编辑该成员 |
| `prescription` | `Prescription.id = business_id AND is_deleted = false` | `prescription.member` | 当前用户可编辑该成员 |
| `medication_plan` | `MedicationPlan.id = business_id AND is_deleted = false` | `plan.member` | 当前用户可编辑该成员 |
| `medicine_box` | `MedicineBox.id = business_id AND is_deleted = false` | `box.member` 或家庭公共药品所属 user | 当前用户可编辑绑定成员；家庭公共药品需是创建者或家庭可管理成员 |

药品 `medicine_box.member` 可能为空，代表家庭公共药品。实现阶段需要明确家庭公共药品分享权限：

1. 若 `member` 为空但 `entryMemberID` 来源不保存，服务端只能按 `box.user == request.user` 或家庭管理员权限校验。
2. 公开 payload 不返回家庭成员列表，只返回药品本身和必要关联计划摘要。

## 9. 各业务公开 payload 详细设计

### 9.1 体检报告 `health_exam_report`

数据来源：

1. `HealthExamReport`
2. `MedExamDetail.business_type = health_exam_report AND business_id = report.id`
3. 附件：`business_type = health_exam_report`

payload：

```json
{
  "id": 123,
  "title": "仁和医院体检中心",
  "institution_name": "仁和医院体检中心",
  "report_no": "HE-2026-001",
  "exam_date": "2026-04-12",
  "exam_type": 1,
  "summary": "血脂略高，建议控制饮食并复查。",
  "status": 2,
  "attachments": [],
  "items": [
    {
      "id": 1,
      "category": "血常规",
      "sub_category": "",
      "item_name": "白细胞计数",
      "result_value": "11.2",
      "unit": "10^9/L",
      "reference_range": "3.5-9.5",
      "flag": "high",
      "diagnosis": "",
      "sort_order": 1
    }
  ]
}
```

Web 展示：

1. 顶部标题：机构名优先，无则“体检报告”。
2. 摘要卡：体检日期、体检类型、报告编号、状态。
3. 总结卡：`summary`。
4. 指标列表：按 `category` 分组，异常指标优先或高亮；空值不展示。
5. 附件区：附件 1、附件 2。

隐私过滤：

1. 不返回 `raw_ocr`。
2. 不返回 `extra` 中 AI trace、OCR 坐标、置信度细节。

### 9.2 医疗检查报告 `examination_report`

数据来源：

1. `ExaminationReport`
2. `MedExamDetail.business_type = examination_report AND business_id = report.id`
3. 关联病例摘要：`report.medical_record` 可选，只返回病例 ID、标题、诊断摘要、状态。
4. 附件：`business_type = examination_report`

payload：

```json
{
  "id": 456,
  "title": "超声诊断报告单",
  "category": "imaging",
  "sub_category": "超声",
  "item_name": "超声诊断报告单",
  "performed_at": "2025-10-26T08:00:00+08:00",
  "reported_at": "2025-10-26T09:00:00+08:00",
  "organization_name": "苏州大学附属第四医院",
  "department_name": "影像科",
  "doctor_name": "王医生",
  "findings": "双侧乳腺回声不均",
  "impression": "BI-RADS 3类",
  "status": 2,
  "linked_case": {
    "id": 12,
    "title": "发现乳腺结节 1天",
    "diagnosis_summary": "乳房结节 N63.x01"
  },
  "attachments": [],
  "details": []
}
```

Web 展示：

1. 顶部标题：`item_name` 优先。
2. 信息卡：分类、子类、检查时间、报告时间、机构、科室、医生。
3. 结论卡：`impression`。
4. 所见卡：`findings`。
5. 明细列表：存在 `MedExamDetail` 时展示。
6. 关联病例卡：只读摘要，不跳转 App 内编辑。

隐私过滤：

1. 不返回 `raw_ocr`。
2. 不展示内部 source、AI 识别 trace。

### 9.3 处方 `prescription`

数据来源：

1. `Prescription`
2. `MedicationPlan.prescription_id = prescription.id`
3. 每个计划关联 `MedicineBox` 摘要
4. 关联病例摘要：`prescription.medical_case` 可选
5. 附件：`business_type = prescription_batch`

payload：

```json
{
  "id": 789,
  "title": "东部战区总医院",
  "institution_name": "东部战区总医院",
  "prescriber_name": "王医生",
  "prescription_no": "RX-001",
  "prescribed_at": "2025-06-27T09:00:00+08:00",
  "diagnosis": "高血压、高脂血症、腔隙性脑梗死、失眠",
  "status": "active",
  "linked_case": {
    "id": 12,
    "title": "就诊记录",
    "diagnosis_summary": "高血压"
  },
  "medication_plans": [
    {
      "id": 1,
      "drug_name": "阿托伐他汀钙片",
      "dose_per_time": "20mg（1片）",
      "frequency_text": "每晚一次",
      "start_date": "2025-06-27",
      "end_date": null,
      "instructions": "",
      "status": "active",
      "medicine_box": {
        "id": 33,
        "medicine_name": "阿托伐他汀钙片",
        "strength": "20mg",
        "dosage_form": "片剂"
      }
    }
  ],
  "attachments": []
}
```

Web 展示：

1. 顶部标题：机构名优先，无则“处方”。
2. 处方基础卡：开方机构、医生、处方号、开方日期、状态。
3. 诊断卡：展示 `diagnosis`。
4. 关联用药计划卡：浅灰白背景，展示药名、剂量、频次；与 `000001` 已调整的处方下用药计划样式保持一致。
5. 关联病例摘要卡：如有则展示。
6. 附件区。

特殊聚合：

1. 即使服药计划没有关联病例，只要 `prescription_id = prescription.id`，也必须展示在处方下。
2. 处方分享页不展示“解绑/同步病例”“删除处方”“删除关联用药计划”等管理能力。

### 9.4 服药计划 `medication_plan`

数据来源：

1. `MedicationPlan`
2. 关联 `MedicineBox`
3. 关联 `Prescription`
4. 关联病例摘要：`plan.medical_case` 可选
5. 服药记录：`MedicationRecord.plan_id = plan.id`，仅返回最近记录摘要
6. 附件：`business_type = medication_plan`

payload：

```json
{
  "id": 1,
  "drug_name": "替美",
  "dose_per_time": "0.20g",
  "frequency_type": "daily",
  "frequency_text": "每日2次",
  "reminder_times": [{"time": "08:00", "dose": 1}],
  "start_date": "2026-06-15",
  "end_date": null,
  "instructions": "饭后服用",
  "status": "active",
  "medicine_box": {
    "id": 3,
    "medicine_name": "替美",
    "medicine_type": "慢病用药",
    "brand_name": "",
    "dosage_form": "片剂",
    "strength": "0.20g",
    "total_quantity": "20",
    "expire_date": "2027-01-01"
  },
  "prescription": {
    "id": 9,
    "institution_name": "东部战区总医院",
    "prescribed_at": "2025-06-27T09:00:00+08:00",
    "diagnosis": "高血压"
  },
  "linked_case": {},
  "recent_records": [
    {
      "id": 100,
      "scheduled_at": "2026-07-03T08:00:00+08:00",
      "status": "taken",
      "planned_dose": "1",
      "actual_dose": "1",
      "taken_at": "2026-07-03T08:02:00+08:00"
    }
  ],
  "attachments": []
}
```

Web 展示：

1. 顶部标题：药品名。
2. 计划卡：剂量、频次、提醒时间、开始/结束日期、状态、说明。
3. 关联药品卡：药箱药品名称、规格、剂型、库存、效期。
4. 关联处方卡：机构、开方日期、诊断。
5. 最近服药记录：展示最近 7 条或最近 30 天内记录，避免公开 payload 过大。
6. 附件区。

隐私与范围：

1. 不展示所有历史服药记录，只展示摘要。
2. 不展示本地通知授权、提醒设备状态等内部字段。

### 9.5 药品 `medicine_box`

数据来源：

1. `MedicineBox`
2. 关联服药计划：`MedicationPlan.medicine_box_id = box.id`
3. 附件：`business_type = medicine_box`

payload：

```json
{
  "id": 3,
  "medicine_name": "阿托伐他汀钙片",
  "medicine_type": "慢病用药",
  "brand_name": "",
  "dosage_form": "片剂",
  "strength": "20mg",
  "dose_unit": "片",
  "total_quantity": "20",
  "expire_date": "2027-01-01",
  "notes": "",
  "linked_plans": [
    {
      "id": 1,
      "drug_name": "阿托伐他汀钙片",
      "dose_per_time": "20mg（1片）",
      "frequency_text": "每晚一次",
      "status": "active",
      "start_date": "2025-06-27"
    }
  ],
  "attachments": []
}
```

Web 展示：

1. 顶部标题：药品名称。
2. 基本信息卡：药品类型、品牌、剂型、规格。
3. 库存卡：总数量、剂量单位、有效期。
4. 备注卡：有内容才展示。
5. 关联服药计划卡：浅灰白卡片列表，展示药名、剂量、频次、状态。
6. 附件区。

隐私与范围：

1. 家庭公共药品不展示家庭成员列表。
2. 不展示创建用户、家庭关系、共享权限等信息。

## 10. Web 设计要求

整体视觉继续沿用 `000001` 当前 Web 分享页风格：

1. 页面背景白色。
2. 内容卡白底、浅边框、轻阴影。
3. 子卡片使用极浅灰白 `#f8fafc`，例如处方下用药计划卡。
4. 附件统一展示为 `附件1`、`附件2`，不展示原始文件名。
5. 移动端、Pad、桌面端都使用单列详情主体，桌面只增加最大宽度和留白。
6. 详情页不要出现编辑、删除、管理、绑定、解绑、新增等操作。
7. 右上角不展示时间轴箭头类跳转符号。

建议页面骨架：

```text
分享页容器
  ├─ 顶部栏：App 标识 / 标题 / 下载 App
  ├─ 主详情卡：按业务类型展示标题、日期、状态
  ├─ 详情区块：
  │    ├─ 基础信息
  │    ├─ 诊断/总结/结论
  │    ├─ 指标/计划/药品/记录列表
  │    └─ 附件
  └─ 下载 App 引导
```

业务类型与组件映射：

```text
payload_type=health_exam_report     -> HealthExamShareDetail
payload_type=examination_report     -> ExaminationReportShareDetail
payload_type=prescription           -> PrescriptionShareDetail
payload_type=medication_plan        -> MedicationPlanShareDetail
payload_type=medicine_box           -> MedicineBoxShareDetail
legacy case/timeline payload        -> MedicalCaseShareDetail
```

## 11. iOS 接入设计

五个页面都调用同一个分享准备方法，不在页面里硬编码 URL。

统一输入建议：

```swift
struct ShareableMedicalResource {
    let businessType: String
    let businessID: Int
    let title: String
    let summary: String?
}
```

页面接入规则：

1. `HealthExamRecognitionResultView`
   - 仅 `mode == .detail` 且 `detailReportID != nil` 时展示分享。
   - 当前分享按钮已有占位，应改为调用公共分享流程。

2. `ExaminationReportDetailPage`
   - 仅 `mode == .server` 时展示分享。
   - `mode == .localDraft` 隐藏分享或禁用并提示“保存后可分享”。

3. `MedicationPrescriptionDetailPage`
   - 仅 `mode == .server` 且 `currentPrescription != nil` 时展示分享。
   - 分享标题使用机构名、医生名、处方号兜底。

4. `MedicationPlanDetailPage`
   - 仅 `mode == .server` 时展示分享。
   - 分享标题使用 `currentPlan.drugName`。

5. `MedicineBoxDetailPage`
   - 仅 `mode == .server` 时展示分享。
   - 分享标题使用 `currentBox.medicineName`。

右上角菜单顺序建议：

```text
分享
编辑
删除
```

如果页面已有“导出”，建议：

```text
导出
分享
编辑
删除
```

分享失败：

1. 网络失败：toast 或 alert 展示错误。
2. 服务端返回无权限：提示“当前内容无法分享”。
3. 本地草稿：提示“保存后可分享”。

## 12. 完整业务流程

```text
用户进入体检报告/检查报告/处方/服药计划/药品详情页
  -> 点击右上角更多
  -> 点击分享
  -> iOS 调用 POST /api/v1/medical/shares/
      business_type = 当前详情类型
      business_id = 当前详情 ID
  -> 服务端校验登录态、对象存在、成员权限
  -> 服务端创建或复用 MedicalShareRecord
      share_code = 随机码
      expires_at = now + 10天
  -> iOS 拿到 share_url
  -> 弹出公共 ShareSheet
  -> 用户选择微信好友 / 小红书 / 复制链接
  -> 外部用户打开 https://share.dreamwhale.top/s/{share_code}
  -> share-web 调用 GET /api/v1/medical/shares/public/{share_code}/
  -> 服务端校验分享码状态和有效期
  -> 服务端按 business_type 聚合公开详情 payload
  -> Web 按 payload_type 渲染对应详情页面
  -> 分享过期或撤销时渲染下载 App 引导页
```

## 13. 安全与隐私要求

1. 分享码仍必须不可枚举，不能包含业务 ID、用户 ID、成员 ID。
2. 公开接口必须继续校验分享记录状态和 `expires_at`。
3. 公开 payload 不返回手机号、账号、家庭关系、成员绑定、用户权限、内部调试字段。
4. 所有报告类对象不得返回 `raw_ocr`。
5. `extra` 默认不返回；如必须返回，需要按白名单筛选字段。
6. 附件必须走短时签名 URL 或受控代理，不允许暴露私有存储 object key。
7. 服药记录只返回摘要，避免公开过长的健康行为历史。
8. 日志不要记录完整医疗详情；只记录 request_id、share_code hash、业务类型、状态、耗时。

## 14. 验收标准

### iOS

1. 五个详情页右上角均可看到“分享”入口。
2. 本地草稿/未保存详情不能生成分享，且有明确提示或隐藏入口。
3. 点击分享先调用服务端创建/复用分享记录，成功后才弹出分享 Sheet。
4. 分享 Sheet 复用 `000001` 公共组件，微信好友、小红书、复制链接行为一致。
5. 复制链接内容包含标题和 `https://share.dreamwhale.top/s/{share_code}`。
6. 分享失败时不会弹出空 Sheet，不会导致详情页状态丢失。

### 服务端

1. `MedicalShareRecord.BusinessType` 支持 5 个新增业务类型。
2. 登录用户可为有权限的体检报告、检查报告、处方、服药计划、药品生成分享码。
3. 无权限、已删除、未知业务类型返回明确错误。
4. 同一用户同一业务对象未过期分享记录复用。
5. 公开接口无需登录即可访问有效分享码。
6. 公开 payload 按业务类型返回正确详情数据。
7. 报告类 payload 不包含 `raw_ocr`。
8. 处方 payload 包含处方下所有服药计划，包括仅关联处方、不关联病例的计划。
9. 服药计划 payload 包含关联药品、关联处方和最近服药记录摘要。
10. 药品 payload 包含关联服药计划摘要。

### Web

1. `/s/{share_code}` 能按业务类型渲染对应详情页。
2. 五类详情页在手机比例下为单列白底卡片布局，内容不溢出。
3. Pad 和电脑比例下只增加阅读宽度和留白，不改成后台表格布局。
4. 附件展示为 `附件1`、`附件2`，不展示原始文件名。
5. 处方下用药计划、药品下关联计划使用浅灰白子卡片。
6. 分享过期、撤销、业务删除时展示下载 App 引导页。
7. 页面 CTA 打开 `https://apps.apple.com/cn/app/id6751417431`。

## 15. 测试建议

服务端新增测试：

1. `test_create_health_exam_report_share_success`
2. `test_create_examination_report_share_success`
3. `test_create_prescription_share_success`
4. `test_create_medication_plan_share_success`
5. `test_create_medicine_box_share_success`
6. `test_share_denied_without_member_edit_permission_for_each_business_type`
7. `test_public_health_exam_share_returns_items_without_raw_ocr`
8. `test_public_examination_share_returns_details_without_raw_ocr`
9. `test_public_prescription_share_returns_linked_medication_plans`
10. `test_public_medication_plan_share_returns_medicine_box_and_recent_records`
11. `test_public_medicine_box_share_returns_linked_plans`
12. `test_public_share_business_deleted_for_each_business_type`

iOS 建议：

1. 每个详情页 Preview 或轻量 UI 测试验证菜单包含分享。
2. 本地草稿模式不触发分享 API。
3. `ShareableMedicalResource` 标题、摘要生成单测。
4. 分享 API 请求 business_type / business_id 正确。

Web 建议：

1. API 类型解析单测，覆盖 5 个 `payload_type`。
2. 组件渲染测试或 Playwright 截图，覆盖手机、Pad、桌面比例。
3. 过期页和下载 CTA 跳转测试。

## 16. 待确认问题

1. 药品 `medicine_box.member = null` 的家庭公共药品，创建分享权限按“药品创建者”还是“当前家庭管理员”判断？建议首期按 `box.user == request.user`，后续再接家庭权限模型。
2. 服药计划分享中的服药记录公开范围建议首期只返回最近 7 条或最近 30 天内记录，二选一即可。建议选择最近 7 条，payload 更稳定。
3. 体检报告和检查报告的指标明细是否需要异常项置顶？建议 Web 展示时异常项优先，服务端仍按 `sort_order` 返回，由前端决定视觉排序。
