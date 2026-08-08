# DEEPTUTORCHAT-000047 DeepTutorChat 独立 query_member_profile 成员医疗资料工具工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000047 |
| 工单类型 | P0 工具能力 / 医疗资料上下文 / DeepTutorChat 独立工具 |
| 当前范围 | 创建需求工单与设计方案，不直接修改 Swift / Django 业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `SparkClient/Projects/Features/DeepTutorChat` |
| 服务端工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkService` |
| 关联历史工单 | `DEEPTUTORCHAT-000043` 独立工具架构、`DEEPTUTORCHAT-000045` 会话绑定成员、`DEEPTUTORCHAT-000037` 体检报告制定计划智能体 |
| 创建日期 | 2026-08-08 |
| 核心目标 | DeepTutorChat 新增独立 `query_member_profile` 工具，读取 SparkService 成员医疗档案，整理为 AI 可用的成员基础资料，并在消息内插入“已获取成员医疗资料”卡片 |

## 1. 结论先行

本工单要求在 DeepTutorChat 独立工具架构内新增原生工具：

```text
query_member_profile
```

该工具必须独立于 Chat 的 `ToolHubQueryMemberProfile`。Chat 现有工具当前主要返回各类记录数量汇总，不满足 DeepTutorChat 对“体检计划智能体前置个人化资料”的需求。

服务端核验结论：

```text
已有接口可直接复用：
GET /api/v1/medical/members/{member_id}/complete-data/

客户端已有网络方法可直接复用：
SparkMedicalQueryAPI.fetchMemberCompleteData(memberID:)

本期不需要新增 SparkService 接口。
```

仅当后续发现 `complete-data` payload 过大、AI 工具调用频率过高、或需要服务端统一脱敏摘要时，再新增 AI 专用瘦身接口：

```text
GET /api/v1/medical/members/{member_id}/profile-summary/
```

## 2. 背景与问题

DeepTutorChat 已完成第一阶段独立工具架构：

```text
ask_user
get_current_member_binding
request_member_selection
read_memory
write_memory
```

但体检计划智能体、健康风险问答、个性化建议等场景还缺少一个关键前置工具：

```text
读取当前成员已维护的医疗档案，并整理成稳定、可解释、可插入上下文的文本。
```

当前问题：

1. DeepTutorChat 不能直接复用 Chat `ToolHubQueryMemberProfile`，否则会破坏 `DEEPTUTORCHAT-000043` 的独立工具架构边界。
2. Chat 现有 `query_member_profile` 输出偏“计数汇总”，不包含基础档案、病史、生活习惯、体检档案、风险评估五类结构化摘要。
3. DeepTutorChat 消息流中缺少“工具已经获取到成员医疗资料”的可视化卡片，用户不知道 AI 是否真的读取了资料。
4. 生成个性化体检计划前，AI 需要明确调用该工具，而不是凭空询问或泛泛建议。
5. 医疗资料属于敏感数据，必须有明确的最小化、脱敏、日志、记忆写入边界。

## 3. 服务端接口核验

### 3.1 已有接口

SparkService 已有成员医疗聚合接口：

```text
GET /api/v1/medical/members/{member_id}/complete-data/
```

服务端代码位置：

```text
SparkService/medical/urls.py
  path("members/<int:member_id>/complete-data/", MemberCompleteDataAPI.as_view(), ...)

SparkService/medical/views.py
  MemberCompleteDataAPI.get(...)
```

该接口已做权限校验：

```text
MemberPermissionGate.require_access(user=request.user, member_id=int(member_id))
```

返回聚合内容包含：

```text
member
medical_profile
module_setting / member_module_settings
medical_cases
health_exam_reports
examination_reports
medication_plans
symptoms
visits
surgeries
follow_ups
```

其中 `medical_profile` 已通过服务端实时聚合增强：

```text
build_member_medical_guidance_projection(...)
enrich_member_medical_profile_payload(...)
```

包含本工单需要的五类摘要：

```text
guidance_sections:
  basic_profile
  health_history
  lifestyle
  exam_archive
  risk_assessment

risk_assessment_summary
exam_plan_summary
guidance_updated_at
```

### 3.2 客户端已有可复用方法

SparkClient 已有网络模型与 API：

```text
SparkClient/Projects/Core/Networking/API/Medical/MedicalQueryAPI.swift
  fetchMemberCompleteData(memberID:)

SparkClient/Projects/Core/Networking/API/Medical/MedicalSyncAPI.swift
  RemoteMemberCompleteData
  RemoteMemberMedicalProfile
  RemoteMemberMedicalProfileSectionSummary
```

本期 DeepTutorChat 不新建底层 HTTP client，只在 DeepTutorChat Infrastructure 下创建工具专用 datasource，内部复用 `SparkMedicalQueryAPI`。

### 3.3 是否需要新增服务端接口

本期结论：不新增。

原因：

1. `complete-data` 已包含需要的成员基础信息、医疗画像、体检档案和风险投影。
2. 权限、归档过滤、模块聚合均已在服务端完成。
3. iOS 已有模型与请求方法，接入成本低。
4. 工具侧可以在客户端做 AI 上下文裁剪，不必让服务端为首期需求再开一条接口。

后续新增接口的触发条件：

| 条件 | 说明 |
| --- | --- |
| payload 过大 | `complete-data` 包含报告附件、病例、用药等大量列表，导致工具调用慢或 token 压力明显 |
| 多端复用 | Web / Android / HarmonyOS 都需要同一份 AI 专用摘要 |
| 服务端脱敏 | 需要统一控制 AI 可见字段，避免客户端各端整理口径漂移 |
| 缓存策略 | 需要按 `member_profile.updated_at` 单独缓存摘要，而不是缓存完整成员数据 |

可选后续接口草案：

```http
GET /api/v1/medical/members/{member_id}/profile-summary/
```

返回：

```json
{
  "member_id": 10,
  "member_name": "凯",
  "updated_at": "2026-08-08T...",
  "sections": [
    {"code": "basic_profile", "title": "基础档案", "summary": "...", "status": "completed"}
  ],
  "ai_context": "..."
}
```

## 4. 产品目标

### 4.1 用户侧目标

用户在 DeepTutorChat 中提出以下问题时，系统应自动读取当前成员医疗资料：

```text
给我制定体检计划
结合我的档案看看该查什么
根据家族史推荐体检项目
我妈妈适合做哪些筛查
根据过往体检报告给出复查计划
```

用户应能在消息流中看到一张卡片：

```text
已获取成员医疗资料
成员：凯
包含：基础档案、健康病史、生活习惯、过往体检档案、风险评估
更新时间：2026-08-08
```

### 4.2 AI 侧目标

AI 在生成个性化体检计划前必须具备：

1. 当前会话绑定成员或通过 `request_member_selection` 获得成员。
2. 已调用 `query_member_profile` 获取成员医疗资料。
3. 根据工具返回的结构化文本制定计划。
4. 明确说明哪些建议来自已维护档案，哪些仍需用户补充确认。

### 4.3 工程侧目标

1. `query_member_profile` 完全放在 DeepTutorChat 独立工具目录内。
2. 不复用 `Projects/Core/AIRuntime/ToolHub/Executors/ToolHubQueryMemberProfile.swift`。
3. 不引入 Chat `ToolInteractionCoordinator`。
4. 工具结果进入 DeepTutorChat 自己的 stream event / message block / card。
5. 工具输出可测试、可脱敏、可稳定复现。

## 5. 工具定义

### 5.1 工具名称

```text
query_member_profile
```

### 5.2 工具定位

| 字段 | 内容 |
| --- | --- |
| 是否必须 | 必须 |
| 使用时机 | 生成任何个性化体检计划、健康筛查建议、成员风险摘要前 |
| 前置依赖 | 当前会话有 `boundMemberID`；若无，先调用 `get_current_member_binding`，再调用 `request_member_selection` |
| 数据来源 | SparkService `GET /api/v1/medical/members/{member_id}/complete-data/` |
| 输出给 AI | 成员医疗资料文本 + 结构化 metadata |
| 输出给用户 | 消息内插入“已获取成员医疗资料”卡片 |
| 隐私等级 | sensitive，不写入 memory，不在日志输出全文 |

### 5.3 Function Calling Schema

```json
{
  "name": "query_member_profile",
  "description": "Query the selected family member's maintained medical profile and summarize basic profile, health history, lifestyle, exam archive and risk assessment for personalized health planning.",
  "parameters": {
    "type": "object",
    "properties": {
      "member_id": {
        "type": "integer",
        "description": "Optional member id. If omitted, use current DeepTutorChat bound member."
      },
      "purpose": {
        "type": "string",
        "description": "Why the profile is needed, e.g. health_exam_plan, risk_summary, screening_recommendation.",
        "enum": ["health_exam_plan", "risk_summary", "screening_recommendation", "general_health_context"]
      },
      "include_sections": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["basic_profile", "health_history", "lifestyle", "exam_archive", "risk_assessment"]
        },
        "description": "Sections to include. Default includes all five sections."
      }
    },
    "required": ["purpose"]
  }
}
```

### 5.4 工具调用规则

Prompt Manifest 必须加入：

```text
- 如果用户要求制定体检计划、筛查建议、复查计划、健康风险总结，必须先确保有成员上下文。
- 有成员上下文后，必须调用 query_member_profile。
- query_member_profile 返回后，再生成个性化建议。
- 不要把工具返回的 JSON 原样展示给用户；应结合用户问题整理为自然语言。
- 如果资料缺失，要明确标注“档案未维护/待补充”，不要假设。
- 医疗资料不得写入 write_memory。
```

## 6. 数据整理口径

### 6.1 输入数据来源映射

| 输出分区 | 主要来源 | 备用来源 |
| --- | --- | --- |
| 基础档案 | `complete.member` + `memberMedicalProfile.extra` | `guidance_sections.basic_profile.summary` |
| 健康病史与症状记录 | `chronicConditions`、`allergies`、`familyHistory`、`medicationFocus`、`surgeryFocus`、`symptomFollowUpFocus` | `symptoms`、`surgeries`、`medicationPlans` |
| 生活习惯 | `smokingProfile`、`drinkingProfile`、`exerciseProfile`、`sleepHours`、`extra.sleep_quality` | `guidance_sections.lifestyle.summary` |
| 过往体检档案 | `healthExamReports`、`examinationReports`、`examPlanSummary`、`extra.exam_report_summary` | `guidance_sections.exam_archive.summary` |
| 风险评估 | `riskAssessmentSummary`、`notes` | `guidance_sections.risk_assessment.summary` |

### 6.2 输出给 AI 的文本标准

工具返回的 `content` 必须是稳定 Markdown 文本：

```markdown
# 成员医疗资料摘要

成员：凯（self / male / 27岁）
资料更新时间：2026-08-08
资料完整度：基础档案 completed；健康病史 completed；生活习惯 completed；过往体检档案 completed；风险评估 completed

## 基础档案
- 性别：男
- 年龄：27岁
- 身高体重：171cm / 66kg
- 职业与久坐：程序员 / 中久坐

## 健康病史与症状记录
- 慢病：未记录
- 过敏：荨麻疹
- 家族史：高血压 / 糖尿病等，按实际数据输出
- 用药关注：替硝唑片等，按实际数据输出
- 手术/操作：拔牙
- 症状随访：牙痛

## 生活习惯
- 吸烟：历史吸烟，已戒烟
- 饮酒：按档案输出
- 运动：按档案输出
- 睡眠：6.5小时，睡眠质量 fair

## 过往体检档案
- 是否有体检史：有
- 最近体检：2025-05 美年大健康
- 体检异常摘要：按 extra.exam_report_summary / HealthExamReport 摘要提炼
- 已有体检计划摘要：按 exam_plan_summary 输出

## 风险评估
- 按 riskAssessmentSummary / notes 输出

## AI 使用提示
- 上述内容来自用户维护的成员医疗档案。
- 未记录字段不得推断为没有疾病或没有风险。
- 生成体检计划时需区分“基础必查”和“因风险加项”。
```

缺失字段输出规则：

| 情况 | 输出 |
| --- | --- |
| 字段为空 | `未记录` |
| 分区不存在 | `该分区尚未维护` |
| 体检报告只有数量无摘要 | 输出数量，不编造异常 |
| 风险评估为空 | `尚未生成风险评估` |
| 成员无权限或不存在 | 工具失败，不返回医疗内容 |

### 6.3 输出 metadata

```json
{
  "member_id": "10",
  "member_name": "凯",
  "sections": "basic_profile,health_history,lifestyle,exam_archive,risk_assessment",
  "completed_sections": "4",
  "has_profile": "true",
  "has_exam_history": "true",
  "health_exam_report_count": "1",
  "examination_report_count": "0",
  "symptom_count": "1",
  "medication_plan_count": "1",
  "updated_at": "2026-08-08T..."
}
```

## 7. 消息卡片设计

### 7.1 新增卡片

建议新增：

```text
DeepTutorMemberProfileCardView
```

建议新增 block payload：

```swift
case memberProfile(DeepTutorMemberProfileBlockPayload)
```

Payload 字段：

```swift
struct DeepTutorMemberProfileBlockPayload: Codable, Equatable, Sendable {
    var toolCallID: String
    var memberID: Int
    var memberName: String
    var relationship: String?
    var gender: String?
    var ageText: String?
    var sections: [Section]
    var source: String              // "complete-data"
    var fetchedAt: Date
    var status: Status              // loaded / partial / failed

    struct Section: Codable, Equatable, Sendable, Identifiable {
        var id: String              // basic_profile
        var title: String
        var summary: String
        var status: String          // completed / partial / empty
    }
}
```

卡片首屏展示：

```text
已获取成员医疗资料
凯 · 本人 · 男 · 27岁

✓ 基础档案：男 · 27岁 · 171cm · 66kg · 中久坐
✓ 健康病史：牙痛 · 荨麻疹 · 拔牙
✓ 生活习惯：历史吸烟 · 6.5小时睡眠
✓ 过往体检档案：2025年体检 · 有体检史
✓ 风险评估：已生成 / 待生成

来源：成员医疗档案 complete-data
```

交互要求：

1. 默认折叠为摘要卡片，避免占满聊天窗口。
2. 点击卡片可展开五个分区摘要。
3. 不展示完整体检报告原文，不展示附件 URL。
4. 如果某分区缺失，显示“待补充”，不显示空白。
5. 卡片只表示“资料已获取”，最终医学解释仍由 AI 回复承担。

### 7.2 Stream Event

建议新增事件：

```swift
case memberProfileLoaded(payload: DeepTutorMemberProfileBlockPayload)
```

事件来源：

```text
DeepTutorAgenticRuntime
  -> tool call query_member_profile
  -> DeepTutorQueryMemberProfileTool.execute
  -> result.metadata includes profile_card_payload
  -> DeepTutorAIRuntimeEventMapper maps toolResult to memberProfileLoaded
  -> DeepTutorMessageReducer inserts memberProfile block
```

如果不想扩大 enum，也可以首期通过 `toolResult(kind=query_member_profile)` 在 `DeepTutorContentRouter` 中识别并生成 `.memberProfile(...)` segment。但长期建议新增专用事件，减少字符串解析。

## 8. 推荐代码落点

### 8.1 Domain

```text
SparkClient/Projects/Features/DeepTutorChat/Domain/Tools/DeepTutorToolName.swift
  + case queryMemberProfile = "query_member_profile"

SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift
  + case memberProfile
  + DeepTutorMemberProfileBlockPayload

SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorStreamEvent.swift
  + case memberProfileLoaded(...)
```

### 8.2 Application

```text
Application/Tools/Builtins/DeepTutorQueryMemberProfileTool.swift
  - definition()
  - execute(arguments:context:)
  - memberID 解析
  - complete-data 拉取
  - AI context Markdown 生成
  - card payload metadata 生成

Application/Tools/DeepTutorToolRegistryFactory.swift
  - 注册 DeepTutorQueryMemberProfileTool

Application/Tools/DeepTutorToolRegistry.swift
  - compose 默认挂载 query_member_profile
  - promptManifest 增加健康资料工具规则

Application/DeepTutorAIRuntimeEventMapper.swift
  - 映射 query_member_profile toolResult -> memberProfileLoaded

Application/DeepTutorMessageReducer.swift
  - 插入 memberProfile block
```

### 8.3 Infrastructure

```text
Infrastructure/Tools/DeepTutorMemberProfileDataSource.swift
  - fetch(memberID:) async throws -> RemoteMemberCompleteData
  - 内部复用 SparkMedicalQueryAPI.fetchMemberCompleteData(memberID:)

Infrastructure/Tools/DeepTutorMemberProfileFormatter.swift
  - makeAIContext(...)
  - makeCardPayload(...)
  - section fallback / missing field policy
```

`DeepTutorMemberToolDataSource.swift` 可以继续负责成员列表/选择；本工具建议新建 `DeepTutorMemberProfileDataSource.swift`，避免“成员选择数据源”和“成员医疗档案数据源”混在一起。

### 8.4 Presentation

```text
Presentation/Cards/DeepTutorMemberProfileCardView.swift
```

在 `DeepTutorAssistantResponseView` / message block 渲染入口中增加 `.memberProfile` 分支。

## 9. Agent Loop 流程

### 9.1 有会话绑定成员

```text
用户：给我制定一份体检计划
AI -> get_current_member_binding
Tool -> {"bound":true,"member_id":10}
AI -> query_member_profile({purpose:"health_exam_plan"})
Tool -> 拉取 complete-data，返回 Markdown + card metadata
UI -> 插入“已获取成员医疗资料”卡片
AI -> 根据资料生成体检计划
```

### 9.2 无会话绑定成员

```text
用户：给我妈妈制定体检计划
AI -> get_current_member_binding
Tool -> {"bound":false}
AI -> request_member_selection({reason:"需要确认要为哪位成员制定体检计划"})
UI -> 成员选择卡片
用户选择“妈妈”
系统 -> 绑定 conversation.memberID
同 turn 恢复
AI -> query_member_profile({member_id: selectedMemberID, purpose:"health_exam_plan"})
Tool -> 返回资料摘要 + 卡片
AI -> 继续生成体检计划
```

### 9.3 资料缺失

```text
AI -> query_member_profile
Tool -> 返回 has_profile=false 或 sections empty
UI -> 插入“资料较少/待补充”卡片
AI -> 基于年龄性别给基础计划，同时询问必要补充信息
```

## 10. 体检计划智能体强制规则

`DEEPTUTORCHAT-000037` 体检报告制定计划智能体需要补充：

| 工具 | 是否必须 | 用途 | 调用时机 |
| --- | --- | --- | --- |
| `get_current_member_binding` | 必须 | 检查当前会话绑定成员 | 任何个性化体检计划前 |
| `request_member_selection` | 条件必须 | 无绑定成员时请求选择 | 需要成员资料但没有 member_id |
| `query_member_profile` | 必须 | 读取年龄、性别、身高体重、慢病、过敏、用药、家族史、生活方式、过往体检、风险评估 | 生成任何个性化体检计划前 |
| `ask_user` | 条件必须 | 档案缺关键字段时补问 | `query_member_profile` 返回缺失字段后 |

AI 最终回答标准：

1. 开头说明“已参考成员医疗档案中的哪些信息”。
2. 输出“基础必查项目 + 风险加项 + 可选项”。
3. 每个风险加项必须说明依据来自哪类档案字段。
4. 对缺失字段给出补充建议，不把未记录等同于没有风险。
5. 对高风险发现仅建议就医/专科咨询，不给诊断结论。

## 11. 隐私与安全

1. `query_member_profile` 返回内容标记为 sensitive。
2. 日志只记录：

```text
memberID
sections count
hasProfile
record counts
durationMs
success/failure
```

禁止记录：

```text
过敏详情全文
家族史全文
体检异常全文
病例摘要全文
用药详情全文
风险评估全文
```

3. `write_memory` 不得保存 `query_member_profile` 的输出。
4. 卡片不展示附件 URL、报告全文、身份证明类字段。
5. 权限失败时，工具只返回“无法读取成员医疗资料”，不透露成员是否存在。

## 12. 错误处理

| 场景 | 工具行为 | UI 行为 | AI 行为 |
| --- | --- | --- | --- |
| 未绑定成员 | 返回失败并提示先选成员，或由 AI 先调用 `request_member_selection` | 不插资料卡 | 请求选择成员 |
| 权限失败 | success=false，content 为权限失败泛化文案 | 插入失败状态卡或不插卡 | 说明无法读取资料 |
| 网络失败 | success=false，metadata 包含 error_type=network | 可插“获取失败”卡 | 询问是否稍后重试，或基于用户输入给通用建议 |
| profile 为空 | success=true，has_profile=false | 插“资料较少”卡 | 给基础建议并提示补充档案 |
| complete-data 解码失败 | success=false，error_type=decode | 不展示敏感内容 | 说明资料读取异常 |

## 13. 验收标准

### 13.1 服务端验收

- [ ] 确认复用 `GET /api/v1/medical/members/{member_id}/complete-data/`。
- [ ] 不新增接口也能覆盖五个分区：基础档案、健康病史、生活习惯、过往体检档案、风险评估。
- [ ] 权限失败时不会返回任何成员医疗详情。

### 13.2 工具验收

- [ ] DeepTutorChat registry 中可见 `query_member_profile`。
- [ ] DeepTutorChat 运行时出站 schema 包含 `query_member_profile`，且不依赖 Chat `ToolHub`。
- [ ] 有绑定成员时，工具可直接读取 `boundMemberID`。
- [ ] 无绑定成员时，AI 会先触发 `request_member_selection`。
- [ ] 工具返回 Markdown 文本包含五个标准分区。
- [ ] 工具 metadata 可生成成员资料卡片。
- [ ] 工具失败不会导致整个 agent loop 崩溃。

### 13.3 消息卡片验收

- [ ] 工具成功后消息流插入“已获取成员医疗资料”卡片。
- [ ] 卡片展示成员、分区、摘要、更新时间。
- [ ] 缺失分区显示“待补充”。
- [ ] 卡片不会展示完整报告正文或附件 URL。
- [ ] 历史消息重载后卡片仍能解码展示。

### 13.4 AI 回答验收

- [ ] 生成体检计划前必先调用 `query_member_profile`。
- [ ] 回答能区分基础项目、风险加项、可选项目。
- [ ] 回答能引用档案依据，例如“因家族史/过往体检/生活习惯，建议加做...”。
- [ ] 档案缺失时不编造。
- [ ] 医疗表达不下诊断，只给筛查、复查、就诊建议。

### 13.5 回归验收

- [ ] Chat 模块原 `query_member_profile` 不受影响。
- [ ] DeepTutorChat `ask_user`、`request_member_selection`、`read_memory/write_memory` 不受影响。
- [ ] `DEEPTUTORCHAT-000043` 独立工具架构边界不被破坏。
- [ ] `xcodebuild -project SparkClient.xcodeproj -scheme SparkClient -destination 'generic/platform=iOS Simulator' build` 通过。

## 14. 实施拆分建议

### Phase 1：工具与数据整理

1. 新增 `DeepTutorToolName.queryMemberProfile`。
2. 新增 `DeepTutorMemberProfileDataSource`。
3. 新增 `DeepTutorMemberProfileFormatter`。
4. 新增 `DeepTutorQueryMemberProfileTool`。
5. Registry 注册并更新 prompt manifest。

### Phase 2：消息事件与卡片

1. 新增 memberProfile payload / block / event。
2. EventMapper 映射 toolResult。
3. MessageReducer 插入 block。
4. 新增 `DeepTutorMemberProfileCardView`。
5. 历史消息 codec 兼容。

### Phase 3：体检计划智能体接入

1. 更新体检计划智能体 system prompt。
2. 明确 `query_member_profile` 必调规则。
3. 增加缺失资料时 `ask_user` 补问策略。
4. 增加体检计划输出模板与验收样例。

### Phase 4：测试与日志

1. 单测 formatter。
2. 单测 datasource mock。
3. 单测 registry schema。
4. 单测 message block codec。
5. 增加敏感日志脱敏检查。

## 15. 非目标

本工单不做：

1. 不新增体检报告全文解析工具。
2. 不读取 PDF 原文。
3. 不实现 `list_member_health_sources` / `get_health_resource_context`。
4. 不复用 Chat ToolHub 的 query_member_profile 执行器。
5. 不把医疗档案写入长期记忆。
6. 不在服务端新增接口，除非后续性能或脱敏要求明确触发。

## 16. 开放问题

| 问题 | 建议 |
| --- | --- |
| `complete-data` 是否太大 | 首期客户端裁剪；上线后用日志观察耗时和 payload size |
| 卡片是否展示风险评估全文 | 不展示全文，只展示一行摘要；展开也只展示服务端 projection summary |
| 是否允许用户点击卡片进入医疗模块 | 首期不做；后续可加“查看档案”入口 |
| 是否支持多个成员对比 | 不做；本工具一次只读取一个 member |
| 是否缓存工具结果 | 可按 conversationID + memberID + profile.updatedAt 做内存级缓存，首期不是必须 |

## 17. 推荐最终效果

用户输入：

```text
给我制定一份体检计划
```

消息流：

```text
DeepTutor 推理中...
卡片：已获取成员医疗资料
AI：我已参考凯的基础档案、健康病史、生活习惯和过往体检档案。下面按“基础必查 / 风险加项 / 可选项 / 体检前注意事项”给你制定计划...
```

这才是本工单的完成标准：用户能看见资料已被真实读取，AI 能基于资料给出个性化计划，工程上仍保持 DeepTutorChat 独立工具架构。
