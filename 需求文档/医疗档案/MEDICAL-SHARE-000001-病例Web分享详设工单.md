# MEDICAL-SHARE-000001 病例 Web 分享详设工单

> 状态：新需求 / 待实现  
> 创建日期：2026-07-02  
> 范围：iOS 客户端公共分享组件、服务端医疗模块分享记录与公开访问接口、Web 分享页、部署域名与 nginx 规划。  
> 首期业务：病例详情页 `MedicalCaseDetailPage` 分享，后续扩展到检查报告、体检报告、用药计划、营养记录等业务对象。

## 1. 背景与目标

当前病例详情页只能在手机客户端内查看。需要支持用户在病例详情页右上角点击分享，生成一个有效期 10 天的分享链接，外部用户通过 Web 页面看到与手机客户端病例详情页一致的关键内容。

首期支持：

1. `MedicalCaseDetailPage` 右上角菜单增加“分享”入口。
2. 点击分享时客户端向服务端上送业务类型和业务 ID，服务端创建或复用有效分享记录并返回分享码。
3. 客户端拿到分享码后弹出底部分享 Sheet。
4. 分享 Sheet 首期展示：微信好友、小红书、复制链接。
5. 分享链接由 Web 二级域名和分享码组成，外部用户无需登录即可访问分享页。
6. 分享码有效期 10 天；过期、撤销、业务不存在时进入失效页，引导下载 App。
7. Web 分享页首期接入医疗病例模块，视觉对齐 iOS 病例详情页的头部摘要卡、时间轴、附件胶囊与报告卡片。

## 2. 现状代码参考

### iOS 关键代码

| 目标 | 当前文件 | 后续用途 |
| --- | --- | --- |
| 病例详情页入口 | `SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/MedicalCases/MedicalCaseDetail/MedicalCaseDetailPage.swift` | 右上角菜单增加分享入口；当前菜单已有导出、删除 |
| 顶部病例摘要卡 | 同上 `MedicalCasePatientHeaderCard` | Web 头部主诉、诊断、状态、日期卡片视觉源 |
| 时间轴行 | `.../MedicalCaseDetail/MedicalCaseTimelineRow.swift` | Web 时间轴布局、卡片层级、检查报告/就诊/症状等内容源 |
| 时间轴事件构造 | `.../MedicalCaseDetail/MedicalCaseTimelineTypes.swift` | Web 服务端聚合字段需对齐该构造逻辑 |
| 时间轴色彩/图标 | `.../MedicalCaseDetail/MedicalCaseCardPalette.swift` | Web 颜色与图标语义对齐 |
| 附件胶囊 | `.../MedicalCaseDetail/AttachmentPill.swift` | Web 附件展示样式参考；外部访问需用公开附件 URL 或受控临时 URL |
| 网络 DTO | `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift` | 新增分享接口 DTO |
| 医疗查询 API | `SparkClient/SparkClient/Projects/Core/Networking/API/Medical/MedicalQueryAPI.swift` | 可新增 `MedicalShareAPI`，不要塞入普通查询 API |

### 服务端关键代码

| 目标 | 当前文件 | 后续用途 |
| --- | --- | --- |
| 医疗模型 | `SparkService/medical/models.py` | 新增分享记录模型 |
| 医疗序列化 | `SparkService/medical/serializers.py` | 新增分享创建、详情 payload serializer |
| 医疗路由 | `SparkService/medical/urls.py` | 新增 `/shares/` 和公开 `/share/<code>/` 接口 |
| 医疗视图 | `SparkService/medical/views.py` | 可新增轻量 view，复杂聚合逻辑下沉到 service |
| 成员权限 | `SparkService/medical/services/member_permission_gate.py` | 创建分享时校验当前用户对病例成员有访问权 |
| 附件关系 | `file_manager.business_relations.files_for_business` | 聚合病例、检查报告等附件 |
| 成员完整数据 | `MemberCompleteDataAPI` | 可复用其病例聚合思路，但分享接口应只返回单个病例相关数据 |

## 3. 推荐目录结构

### iOS

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Share/
  ShareAPI.swift
  ShareDTO.swift

SparkClient/SparkClient/Projects/Core/Networking/
  NetworkConfiguration.swift      # 或现有等价配置入口，新增 shareWebBaseURL

SparkClient/SparkClient/Projects/Features/Common/Share/
  ShareSheetView.swift
  ShareChannel.swift
  ShareActionHandler.swift

SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/MedicalCases/MedicalCaseDetail/
  MedicalCaseDetailPage.swift  # 接入分享入口
```

说明：分享组件做成公共能力，不放在 `MedicalCases` 子目录。病例详情页只负责传入业务类型、业务 ID、标题和分享摘要。客户端网络配置需要新增分享域名配置项，避免在业务页面硬编码 Web 域名。

### 服务端

```text
SparkService/medical/
  models.py                       # 新增 MedicalShareRecord
  serializers.py                  # 新增 MedicalShareCreateSerializer / MedicalShareRecordSerializer
  urls.py                         # 新增分享路由
  views.py                        # 新增 MedicalShareCreateAPI / MedicalSharePublicDetailAPI
  services/
    share_code_service.py         # 生成分享码、创建/复用分享记录
    share_payload_service.py      # 按业务类型聚合公开分享 payload
  tests_share.py                  # 分享创建、过期、权限、公开 payload 测试
```

### Web 分享页

建议新增独立前端项目，不复用 `backoffice-web`：

```text
SparkService/share-web/
  package.json
  vite.config.ts
  index.html
  src/
    main.ts
    App.vue
    api/share.ts
    router/index.ts
    views/MedicalCaseSharePage.vue
    views/ShareExpiredPage.vue
    components/
      CaseHeaderCard.vue
      MedicalTimeline.vue
      TimelineCard.vue
      AttachmentPill.vue
    styles/medical-share.css
```

原因：`backoffice-web` 是后台管理系统，含登录态、管理路由和 Ant Design 业务组件；分享页面向外部用户，应该是独立构建、独立域名、无登录态的轻量 C 端页面。

## 4. 域名与 nginx 建议

分享二级域名确定使用：

```text
share.dreamwhale.top
```

选择 `share.dreamwhale.top` 的原因：

1. 语义通用，后续病例、报告、营养、任务等都能复用。
2. 不绑定医疗模块，避免未来扩展时域名不合适。
3. 分享链接短，适合复制和外部 App 分享。

客户端配置要求：

```text
shareWebBaseURL = https://share.dreamwhale.top
```

要求：

1. `ShareAPI` 返回 `share_url` 时优先使用服务端返回值。
2. 如果服务端只返回 `share_code`，客户端使用 `shareWebBaseURL + "/s/" + share_code` 拼接。
3. `shareWebBaseURL` 必须走现有环境配置体系，区分 Debug、测试、生产环境；业务页面禁止硬编码域名。
4. 复制链接、微信、小红书三种渠道共用同一个最终 URL。

当前本地 nginx 样例 `2026/docker/nginx/backoffice.conf` 和 `39_110_2026/docker/nginx/backoffice.conf` 都是 SPA 配置：

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

后续部署分享页可沿用同类配置，新增独立 server：

```nginx
server {
    listen 80;
    server_name share.dreamwhale.top;

    root /usr/share/nginx/share-web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
```

待执行阶段需要你完成 DNS 解析：`share.dreamwhale.top -> 139.196.215.51`。

## 5. 分享码与数据模型

新增模型建议：

```python
class MedicalShareRecord(models.Model):
    class BusinessType(models.TextChoices):
        MEDICAL_CASE = "medical_case", "medical_case"

    class Status(models.TextChoices):
        ACTIVE = "active", "active"
        REVOKED = "revoked", "revoked"

    user = models.ForeignKey(User, related_name="medical_share_records", on_delete=models.CASCADE, db_index=True)
    member = models.ForeignKey(Member, related_name="share_records", on_delete=models.CASCADE, db_index=True)
    business_type = models.CharField(max_length=64, choices=BusinessType.choices, db_index=True)
    business_id = models.PositiveBigIntegerField(db_index=True)
    share_code = models.CharField(max_length=32, unique=True, db_index=True)
    title = models.CharField(max_length=255, blank=True, default="")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    expires_at = models.DateTimeField(db_index=True)
    last_accessed_at = models.DateTimeField(null=True, blank=True)
    access_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    extra = models.JSONField(default=dict, blank=True)
```

索引建议：

```text
unique(share_code)
index(user, business_type, business_id, status, expires_at)
index(member, business_type, business_id)
index(expires_at, status)
```

分享码规则：

1. 使用 URL-safe 随机码，建议 12 到 16 位，例如 `secrets.token_urlsafe(12)` 后过滤长度。
2. 不使用连续自增 ID，不暴露用户 ID、成员 ID、病例 ID。
3. 创建分享时若同一用户、同一业务对象存在未过期 active 分享记录，默认复用并刷新 `updated_at`，不频繁生成多个链接。
4. 有效期固定 10 天，`expires_at = now + 10 days`。
5. 后续如需要“重新生成链接”，再增加 `force_new=true` 或撤销接口。

业务类型码值首期：

```text
medical_case
```

后续扩展建议：

```text
examination_report
health_exam_report
medication_plan
prescription
nutrition_record
```

## 6. 服务端接口设计

### 6.1 创建分享记录

```http
POST /api/v1/medical/shares/
Authorization: Bearer <token>
Content-Type: application/json
```

请求：

```json
{
  "business_type": "medical_case",
  "business_id": 123
}
```

响应：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "share_code": "AbC123xYz789",
    "share_url": "https://share.dreamwhale.top/s/AbC123xYz789",
    "business_type": "medical_case",
    "business_id": 123,
    "expires_at": "2026-07-12T08:00:00+08:00"
  }
}
```

权限：

1. 登录用户必须能编辑该病例所属成员，服务端按 `MemberPermissionGate.require_edit` 校验。
2. 只有可编辑成员资料的用户能创建分享；仅查看权限不能创建外链分享。
3. 业务对象必须未软删除。

### 6.2 获取公开分享详情

```http
GET /api/v1/medical/shares/public/<share_code>/
```

无需登录。响应包含页面所需全部数据：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "share": {
      "share_code": "AbC123xYz789",
      "business_type": "medical_case",
      "business_id": 123,
      "expires_at": "2026-07-12T08:00:00+08:00",
      "status": "active"
    },
    "member": {
      "display_name": "张**",
      "gender": "female",
      "age_text": "38岁"
    },
    "case": {
      "id": 123,
      "title": "发现乳腺结节 1天",
      "record_type": "custom",
      "status": 2,
      "diagnosis_summary": "乳房结节 N63.x01",
      "hospital_name": "",
      "created_at": "...",
      "updated_at": "...",
      "attachments": []
    },
    "timeline": [
      {
        "id": "examination-456",
        "kind": "examination",
        "category": "imaging",
        "title": "彩超检查报告单",
        "detail": "双侧乳腺回声...",
        "date": "2025-10-26",
        "status_badge_text": null,
        "attachments": []
      }
    ],
    "download_app": {
      "title": "下载 App 查看和管理完整健康档案",
      "ios_url": "",
      "android_url": ""
    }
  }
}
```

失效响应建议仍返回 `code != 0`，Web 根据错误码进入失效页：

```json
{
  "code": 41001,
  "msg": "share_expired",
  "data": {
    "download_app": {
      "title": "分享已过期，下载 App 查看和管理自己的健康档案"
    }
  }
}
```

错误码建议：

| code | msg | 场景 |
| --- | --- | --- |
| `40401` | `share_not_found` | 分享码不存在 |
| `41001` | `share_expired` | 已超过 10 天有效期 |
| `41002` | `share_revoked` | 分享被撤销 |
| `41003` | `business_unavailable` | 病例已删除或不可访问 |
| `40001` | `unsupported_business_type` | 未支持的业务类型 |

### 6.3 可选：撤销分享

首期可不做 UI，但服务端建议预留：

```http
POST /api/v1/medical/shares/<share_code>/revoke/
```

仅分享创建者或成员 owner/admin 可撤销。

## 7. 病例分享聚合逻辑

首期 `share_payload_service.py` 只支持 `medical_case`。

聚合范围：

1. 病例主表：`MedicalCase`。
2. 病例附件：`files_for_business(user, "medical_case", case.id)`。
3. 症状：`Symptom.medical_case_id = case.id`。
4. 就诊：`Visit.medical_case_id = case.id`。
5. 手术：`Surgery.medical_case_id = case.id`。
6. 随访：`FollowUp.medical_case_id = case.id`。
7. 检查报告：`ExaminationReport.medical_record_id = case.id`，含附件。
8. 处方：`Prescription.medical_case_id = case.id`。
9. 用药计划：`MedicationPlan.medical_case_id = case.id` 或处方下关联计划。
10. 药箱：只返回时间轴中用药计划需要展示的药品名称、剂型、规格等必要字段。

排序逻辑对齐 iOS `MedicalCaseTimelineEventBuilder.makeEvents`：

1. 处方按 `prescribed_at / updated_at`。
2. 用药计划按 `start_date`。
3. 检查报告按 `reported_at / performed_at / updated_at / created_at`。
4. 症状按 `started_at / updated_at`。
5. 就诊按 `visited_at / updated_at`。
6. 手术按 `performed_at / updated_at`。
7. 随访按 `completed_at / planned_at / updated_at`。
8. 最终按事件日期倒序；同日按类型优先级稳定排序。

隐私脱敏：

1. 成员姓名默认脱敏，例如 `张三` -> `张*`，`Alice` -> `A***`。
2. 不返回用户手机号、账号、成员绑定关系、共享用户列表。
3. 不返回 `raw_ocr`、内部 `extra` 中的调试字段、AI trace、source system id。
4. 附件首期只展示文件名、类型和可预览 URL；如无法生成公开 URL，则只展示附件胶囊并提示“请下载 App 查看原件”。
5. 图片/PDF 原件是否可外部打开，需要服务端通过短时签名 URL 控制，不能直接暴露私有 OSS object key。

## 8. Web 页面设计

路由：

```text
/s/:shareCode
```

页面结构对齐照片 2 和 iOS 病例详情：

```text
页面顶部
  ├─ 返回/关闭按钮：Web 内可隐藏或返回上一页
  ├─ 标题：病例 title，例如“发现乳腺结节 1天”
  └─ 更多按钮：首期可放“下载 App”

病例摘要卡
  ├─ 主诉：case.title
  ├─ 诊断：case.diagnosis_summary
  ├─ 状态 badge：复诊/治疗中/已归档等
  └─ 日期：case.updated_at 或 created_at

时间线
  ├─ 左侧彩色圆形图标
  ├─ 垂直连接线
  ├─ 日期
  └─ 右侧内容卡片
       ├─ 检查报告：类型、机构、结论、附件胶囊
       ├─ 就诊信息：类型、科室、医生、备注
       ├─ 症状：名称、严重程度、部位、持续时间
       ├─ 处方：诊断、处方号、状态、用药计划摘要
       ├─ 用药计划：药名、剂量、频次、状态
       ├─ 手术：名称、部位、医生、麻醉方式
       └─ 随访：状态、方式、结果、下一步

底部下载引导
  ├─ 固定底栏或页面底部 CTA
  └─ “下载 App 管理完整健康档案”
```

视觉要求：

1. 背景使用浅灰 `#F5F5F8`，卡片白底。
2. 摘要卡左侧使用橙色强调条，圆角 16px，边框浅橙色。
3. 时间轴图标颜色对齐 iOS：影像/检查紫蓝、就诊青绿、症状橙色、手术红色、随访绿色、用药靛蓝、处方紫色。
4. 手机比例下必须和 SwiftUI 实现效果完全一致：单列布局、顶部标题、摘要卡、时间轴左侧图标和竖线、右侧卡片间距、圆角、阴影、附件胶囊都按 iOS 视觉还原。
5. Pad 比例下保持单列主内容，但适当增加内容宽度和左右留白，建议主容器 `max-width: 720px`，时间轴与卡片比例不变。
6. 电脑比例下居中展示主内容，建议主容器 `max-width: 920px`；可增加右侧轻量下载 App 引导栏，但病例主体仍保持 iOS 时间轴视觉，不改成后台表格或多列卡片。
7. 响应式断点建议：手机 `< 600px`、Pad `600px - 1024px`、电脑 `>= 1024px`。
8. Web 不展示编辑、删除、新增记录入口。
9. 过期页只展示失效说明和下载 App 引导，不展示任何病例数据。

## 9. iOS 分享组件设计

### 9.1 接入点

`MedicalCaseDetailPage.swift` 右上角 `Menu` 增加：

```swift
Button {
    Task { await prepareShare() }
} label: {
    Label("分享", systemImage: "square.and.arrow.up")
}
```

不要复用当前导出 PDF 的 `MedicalCaseActivityView`，因为本需求需要自定义渠道、先创建分享码，再弹 Sheet。

### 9.2 公共组件

公共组件输入：

```swift
struct ShareSheetInput: Equatable {
    let title: String
    let summary: String?
    let shareURL: URL
    let businessType: String
    let businessID: Int
    let expiresAt: Date
}
```

渠道：

```swift
enum ShareChannel: String, CaseIterable {
    case wechatFriend
    case xiaohongshu
    case copyLink
}
```

展示样式参考照片 1：

1. 底部 Sheet，圆角顶部。
2. 标题“分享到”。
3. 右上角关闭按钮。
4. 图标宫格：微信好友、小红书、复制链接。
5. 图标下方展示渠道名称。

### 9.3 微信好友

建议采用主流做法：

1. 如果项目已集成微信 OpenSDK，则使用 SDK 分享网页链接，带标题、摘要、缩略图、URL。
2. 如果未集成，首期降级为系统分享 `UIActivityViewController` 或复制链接后尝试打开微信。
3. 分享前检查微信是否安装；未安装时提示“未安装微信，已复制链接”。

### 9.4 小红书

小红书对外链分享能力受平台限制，建议首期采用降级策略：

1. 复制分享链接到剪贴板。
2. 尝试通过 URL Scheme 打开小红书 App。
3. 提示用户在小红书粘贴链接发布或发送。

如果后续申请到小红书开放平台能力，再替换为官方 SDK 分享。

### 9.5 复制链接

复制内容：

```text
我分享了一个健康病例：{title}
{share_url}
```

复制成功后 toast：`链接已复制，10天内可访问`。

## 10. 完整业务流程

```text
用户进入病例详情页
  -> 点击右上角更多
  -> 点击分享
  -> iOS 调用 POST /api/v1/medical/shares/
      business_type=medical_case
      business_id=case.id
  -> 服务端校验登录态、病例存在、成员权限
  -> 服务端创建或复用 MedicalShareRecord
      share_code=随机码
      expires_at=now+10天
  -> iOS 拿到 share_url
  -> 弹出公共 ShareSheet
  -> 用户选择微信好友 / 小红书 / 复制链接
  -> 外部用户打开 https://share.dreamwhale.top/s/{share_code}
  -> share-web 调用 GET /api/v1/medical/shares/public/{share_code}/
  -> 服务端校验分享码状态和有效期
  -> 服务端按病例 ID 聚合时间轴和附件
  -> Web 渲染病例摘要卡、时间轴、附件
  -> 分享过期或撤销则渲染下载 App 引导页
```

## 11. 安全与合规要求

1. 分享链接属于敏感健康数据外部访问入口，分享码必须不可枚举。
2. 公开接口必须限流，建议按 IP + share_code 做基础频控。
3. 公开接口不允许返回登录用户、成员绑定、手机号、内部 ID 以外的无关个人信息。
4. 分享过期后不能通过接口拿到历史 payload。
5. 服务端访问日志不要记录完整医疗详情，只记录 share_code hash、业务类型、业务 ID、状态、耗时。
6. 附件打开必须走短时签名 URL 或代理鉴权，不允许暴露 OSS 私有 object key。
7. 后续如支持撤销分享，撤销后立即失效。

## 12. 验收标准

### iOS

1. 病例详情页右上角可以点击“分享”。
2. 分享前会调用服务端生成分享码，失败时不弹空 Sheet。
3. Sheet 样式与照片 1 的底部宫格体验一致，首期只有微信好友、小红书、复制链接。
4. 复制链接成功后剪贴板内容包含标题和 Web 链接。
5. 未安装微信/小红书时有降级提示，不闪退。
6. 分享组件能被其他业务复用，不依赖病例详情页内部状态。

### 服务端

1. 登录用户可为有权限访问的病例生成分享码。
2. 无权限病例、已删除病例、未知业务类型不能生成分享码。
3. 分享记录有效期为 10 天。
4. 未过期同一用户同一业务对象默认复用 active 分享记录。
5. 公开接口无需登录即可访问有效分享码。
6. 分享过期、撤销、业务删除时返回明确错误码。
7. 公开 payload 包含病例摘要、时间轴、必要附件元数据，不包含敏感内部字段。

### Web

1. 打开 `/s/{share_code}` 能渲染病例详情。
2. 页面视觉接近照片 2：浅灰背景、顶部标题、摘要卡、时间轴、彩色图标、右侧卡片。
3. 检查报告卡片能展示标题、类别、结论和附件胶囊。
4. 过期链接展示下载 App 引导页。
5. 移动端 375px 宽度下内容不溢出；桌面端居中展示。
6. 手机比例下页面视觉与 SwiftUI 病例详情页一致；Pad 和电脑比例下只扩大阅读宽度与留白，不改变病例详情主体结构。

## 13. 测试建议

服务端新增测试：

1. `test_create_medical_case_share_success`
2. `test_create_share_denied_without_member_edit_permission`
3. `test_create_share_reuses_active_record`
4. `test_public_share_returns_medical_case_timeline`
5. `test_public_share_expired`
6. `test_public_share_business_deleted`
7. `test_public_share_payload_masks_member_name`
8. `test_public_share_does_not_include_raw_ocr`

iOS 建议：

1. Share API DTO 编解码单测。
2. Share Sheet 渠道渲染快照或 Preview。
3. `MedicalCaseDetailPage` 点击分享后 loading、成功、失败状态覆盖。

Web 建议：

1. share API mock 成功、过期、404。
2. 病例摘要卡和时间轴组件渲染测试。
3. Playwright 覆盖手机 375px、Pad 768px、电脑 1440px 截图检查。

## 14. 风险与补充建议

1. 健康数据外链分享风险较高，建议后续增加“谁可以看”的说明、撤销分享、访问次数展示。
2. 小红书首期大概率不能直接像微信 SDK 一样分享网页卡片，需要先按“复制链接 + 打开 App”落地。
3. 附件公开访问是最大安全点，首期按已定方案使用 10 分钟短时签名 URL，不能直接暴露私有 OSS object key。
4. Web 页面不要展示编辑入口，避免用户误以为可以在 Web 管理病例。
5. 分享链接建议带 Open Graph 信息，微信/浏览器预览更友好；后续可由 Web SSR 或后端模板增强。

## 15. 已定方案

### 15.1 分享创建权限

确定选择：`require_edit`。

只有可编辑成员资料的用户能创建病例分享。该方案比所有可查看用户都能分享更稳妥，也比 owner/admin only 更适合家庭协作。

### 15.2 附件外部访问

确定选择：服务端生成 10 分钟短时签名 URL，允许 Web 打开图片/PDF。

要求：

1. 签名 URL 只在分享码有效、分享记录 active、业务对象未删除时返回。
2. 签名 URL 有效期 10 分钟，不继承分享码 10 天有效期。
3. 日志只记录附件 ID、分享码 hash、状态和耗时，不记录 OSS 私有 object key。

### 15.3 Web 技术路线

确定选择：新增独立 Vue/Vite `share-web`。

与现有后台技术栈一致，落地快；同时和 `backoffice-web` 分离，避免后台登录态、管理路由和 C 端分享页面混在一起。

## 16. 推荐使用的 Codex Skills

本工单同时涉及 iOS、服务端、Web、安全、测试和部署。执行时建议按阶段使用下列已安装 skill，避免单一视角遗漏健康数据外链分享的安全与体验细节。

### 16.1 必用 skill

| Skill | 使用阶段 | 如何使用 |
| --- | --- | --- |
| `后端接口架构师` | 服务端模型、接口、聚合逻辑实现 | 设计并实现 `MedicalShareRecord`、分享码创建/复用逻辑、`POST /api/v1/medical/shares/`、`GET /api/v1/medical/shares/public/<share_code>/`、病例公开 payload 聚合服务、附件短时签名 URL 生成入口。 |
| `应用安全工程师` | 服务端接口设计完成后、公开接口上线前 | 审查分享码不可枚举性、`require_edit` 权限校验、公开接口限流、成员信息脱敏、内部字段过滤、附件 OSS object key 不泄漏、日志脱敏和过期/撤销后的数据不可访问。 |
| `前端页面工程师` | `share-web` 独立项目实现 | 新建 Vue/Vite 分享页，完成 `/s/:shareCode` 路由、病例摘要卡、时间轴、附件胶囊、过期页、下载 App 引导和手机/Pad/桌面响应式适配。 |
| `移动端应用工程师` | iOS 分享入口和公共分享组件实现 | 在 `MedicalCaseDetailPage` 增加分享入口，新增 `ShareAPI`/DTO、公共 `ShareSheetView`、`ShareChannel`、复制链接、微信好友和小红书降级处理，确保分享组件可被其他业务复用。 |
| `接口测试工程师` | 服务端和 Web 接口验收 | 补齐分享创建、无权限、复用 active 记录、过期、撤销、业务删除、公开 payload 脱敏、`raw_ocr` 不返回、Web mock 成功/失效态等测试。 |

### 16.2 建议配合使用的 skill

| Skill | 使用阶段 | 如何使用 |
| --- | --- | --- |
| `界面设计师` | Web 分享页和 iOS Sheet 视觉验收 | 对齐 iOS 病例详情页的浅灰背景、摘要卡、时间轴、彩色图标、卡片阴影、附件胶囊和底部分享 Sheet 宫格体验。 |
| `体验架构师` | 多端交互与信息架构确认 | 确认 Web 页面不出现编辑/删除入口，过期页路径清晰，下载 App 引导不过度遮挡病例主体，手机和桌面阅读节奏一致。 |
| `部署运维工程师` | 域名、nginx、构建和发布 | 配置 `share.dreamwhale.top`、独立 `share-web` 构建产物、nginx SPA fallback、`/api/` 反代、`/health` 检查和发布脚本。 |
| `技术文档编写员` | 实现完成后的交付文档 | 补充分享接口说明、部署说明、环境变量、错误码、验收记录和后续扩展指引。 |
| `真实验收检查员` | 提测前最终验收 | 基于服务端测试结果、Web 截图、iOS 交互录屏或手测记录进行证据化验收，避免只按代码合并判断完成。 |

### 16.3 推荐执行顺序

1. 使用 `后端接口架构师` 完成服务端模型、接口和病例分享 payload。
2. 使用 `应用安全工程师` 对服务端公开访问面做安全复核，先修复高风险问题。
3. 使用 `前端页面工程师` 完成 `share-web` 页面，并接入公开接口。
4. 使用 `移动端应用工程师` 完成 iOS 分享入口、分享 Sheet 和渠道降级。
5. 使用 `接口测试工程师` 补齐接口、失效态、脱敏和 Web mock 测试。
6. 使用 `部署运维工程师` 完成域名、nginx、构建产物和健康检查。
7. 使用 `真实验收检查员` 做最终证据化验收。

说明：`replicate-ios-to-android` 暂不适用于本工单首期，因为首期范围是 iOS、服务端和 Web 分享页，不包含 Android 对齐实现。
