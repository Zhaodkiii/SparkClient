# DEEPTUTORCHAT-000037 体检报告制定计划智能体需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000037 |
| 工单类型 | P1 健康体检计划智能体 / DeepTutorChat 工具编排 / 医疗画像闭环 |
| 当前范围 | 只创建需求/技术方案工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 需求文档目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/DeepTutorChat` |
| 创建日期 | 2026-08-08 |
| 触发需求 | 用户希望 DeepTutorChat 能基于个人与家族健康背景、既往体检报告、生活方式和风险因素，高效制定体检计划，并给出标准化问答方案 |
| 关联工单 | `DEEPTUTORCHAT-000024`、`DEEPTUTORCHAT-000030`、`MEDICAL-000003`、`总领文档/对话、AI Runtime 与工具调用/工具调用与审计需求.md`、`总领文档/首页、成员与医疗画像/体检报告.md` |
| 核心约束 | 医疗建议必须分级、可追问、可解释、可落任务；不能替代医生诊断；不能把高风险异常轻描淡写为生活方式建议 |

## 1. 背景与问题

当前 DeepTutorChat 已具备对话、成员选择、健康资料读取、问报告、任务生成、知识库和联网搜索等基础能力，但“体检计划”仍容易停留在通用建议：

```text
建议做基础体检
建议加做肿瘤筛查
注意清淡饮食、空腹
异常项请复查
```

这类回答看似完整，但有三个产品问题：

1. 没有先整理个人画像和家族风险，容易推荐过多或过少项目。
2. 没有把“体检前准备、项目选择、当天执行、报告解读、复查任务”串成闭环。
3. 没有稳定的工具链与问答标准，模型每轮回答形态不一致，难以沉淀为用户长期健康档案。

本工单目标是新增一个“体检报告制定计划智能体”能力：当用户提出“帮我做体检计划”“看我的报告下次该查什么”“父母体检套餐怎么选”“体检前要准备什么”等问题时，DeepTutorChat 应主动进入体检计划流程，使用成员健康画像、历史报告、家族史、生活方式、权威知识和任务系统，生成可执行、可解释、可追踪的体检计划。

## 2. 产品目标

### 2.1 用户目标

1. 用户能在 3 到 5 轮内完成关键信息补齐，得到一份个性化体检计划。
2. 用户能清楚知道哪些项目是基础必做，哪些是基于风险加项，哪些暂不建议。
3. 用户能得到体检前 2 到 3 天、体检当天、体检后复查的执行清单。
4. 用户能把体检日期、空腹提醒、复查项目、专科就诊建议保存为任务。
5. 用户能看到 AI 使用了哪些依据：年龄、性别、症状、病史、家族史、生活方式、既往报告异常、指南/科普知识。

### 2.2 工程目标

1. 复用 DeepTutorChat 现有工具调用链路，不新建平行聊天架构。
2. 复用成员选择、健康资料上下文、报告引用、任务生成、知识库检索和风险提示卡。
3. 新增体检计划智能体能力只作为能力策略与工具组合，不把完整医疗逻辑硬编码在页面。
4. 形成稳定结构化输出，便于后续落卡片、保存计划、生成任务和做回归测试。

## 3. 非目标

1. 不替代临床医生，不输出“确诊”“排除疾病”“无需就医”等绝对判断。
2. 第一期不直接购买体检套餐、不接入体检机构下单。
3. 第一期不自动读取未授权的 Apple 健康、医院病历或家庭成员隐私资料。
4. 第一期不做复杂保险核保、职业病诊断、孕产专项方案。
5. 第一期不根据单一肿瘤标志物给出癌症判断。

## 4. 目标用户与触发场景

| 场景 | 用户问题示例 | 智能体目标 |
| --- | --- | --- |
| 首次体检 | “我 32 岁，第一次体检该选什么？” | 建立基础画像，给出基础项目与少量风险加项 |
| 年度体检 | “今年体检套餐怎么选？” | 结合年龄、性别、生活方式和去年异常优化套餐 |
| 报告后计划 | “我的体检报告有脂肪肝和尿酸高，下次该查什么？” | 读取报告异常，生成复查与专项项目 |
| 家庭成员体检 | “给我爸妈做体检计划” | 先选成员，区分本人/父母画像与授权边界 |
| 高风险筛查 | “家里有人得过肠癌，我要查什么？” | 识别家族史风险，建议专科筛查路径 |
| 体检执行 | “体检当天怎么安排最省时间？” | 输出空腹、憋尿、抽血、彩超、用餐后的顺序 |

## 5. 智能体能力定义

能力名称建议：

```text
health_exam_plan_agent
```

能力定位：

```text
基于成员健康画像、历史体检报告、症状、病史、家族史、生活方式和医学知识，为用户生成体检项目组合、体检前准备、当日执行顺序、报告解读与后续复查任务的智能体。
```

能力入口建议：

1. DeepTutorChat 用户自然语言触发。
2. 成员医疗画像页的“生成体检计划”入口。
3. 体检报告详情页的“生成下次体检计划”入口。
4. 任务系统中的“年度体检提醒”二次进入。

## 6. 工具清单与职责

### 6.1 第一期优先复用现有工具

| 工具 | 是否必须 | 用途 | 触发条件 |
| --- | --- | --- | --- |
| `request_member_selection` | 必须 | 选择本人/父母/孩子等目标成员 | 用户未明确成员，或问题涉及家人 |
| `get_current_member` | 必须 | 获取当前会话默认成员 | 用户说“我/我的体检”且已有默认成员 |
| `query_member_profile` | 必须 | 查询并整理用户已维护的医疗档案基础数据，包括基础档案、健康病史与症状记录、生活习惯、过往体检档案、风险评估，并输出可供体检计划智能体使用的画像摘要 | 生成任何个性化体检计划前 |
| `list_member_health_sources` | 必须 | 列出可引用的体检报告、检查报告、病历、用药等资料 | 用户提到“结合报告/历史异常/上次体检” |
| `get_health_resource_reference` | 必须 | 选择具体报告并拿到引用信息 | 用户指定某份报告或需要引用报告结论 |
| `get_health_resource_context` | 必须 | 获取报告结构化异常、关键指标和医生建议 | 报告后计划、异常追踪、复查建议 |
| `ask_user_question` | 必须 | 补齐缺失画像：症状、家族史、吸烟饮酒、职业、女性专项等 | 关键信息不足以分层时 |
| `search_knowledge_bag` | 必须 | 检索本地健康科普、筛查原则、体检前注意事项 | 需要医学依据或统一口径时 |
| `search_online` / `read_web_page` | 可选 | 检索最新指南、机构说明、体检项目解释 | 用户要求最新资料，或本地知识不足 |
| `show_medical_risk_notice` | 必须 | 展示风险提示与就医边界 | 有红旗症状、高危结节、占位、胸痛等场景 |
| `generate_structured_health_card` | 必须 | 生成体检计划卡、复查卡、风险分层卡 | 输出最终方案时 |
| `generate_task` | 必须 | 创建体检预约、体检前准备、复查、专科就诊任务 | 用户确认保存或高风险必须追踪 |
| `save_memory` / `update_memory` | 可选 | 保存长期偏好和稳定风险因素 | 用户确认保存家族史、吸烟史、常用体检机构等 |
| `generate_chat_title` | 可选 | 自动生成会话标题 | 完成首轮方案后 |

### 6.2 建议新增的领域工具

第一期可以先通过 prompt + 现有工具完成；若要稳定落卡片和服务端闭环，建议新增以下工具：

| 新工具 | 类型 | 职责 | 输入 | 输出 |
| --- | --- | --- | --- | --- |
| `generate_health_exam_plan` | 领域生成工具 | 汇总画像和报告，生成结构化体检计划 | member_id、profile_snapshot、risk_factors、report_refs、goal、budget_preference、city_optional | exam_plan_json |
| `save_health_exam_plan` | 持久化工具 | 保存本次体检计划到成员医疗画像 | member_id、exam_plan_json、source_conversation_id | plan_id |
| `compare_health_exam_reports` | 分析工具 | 对比历年体检指标趋势 | member_id、report_ids、indicator_keys | trend_summary_json |
| `create_exam_followup_tasks` | 任务工具 | 批量创建体检前/当天/复查任务 | member_id、plan_id、task_items | task_ids |

新增工具不得绕开 ToolHub，需要声明 `ToolDataCategory`、`ToolDataSensitivity`、`ToolEgressPolicy`，并进入 AI Settings 工具开关和审计。

### 6.3 `query_member_profile` 医疗档案查询优化

本工单要求优化 `query_member_profile` 的数据查询与整理能力。该工具不能只返回年龄、性别、慢病、过敏、家族史、生活方式等零散摘要，而必须支持读取并整理用户在医疗模块中维护过的基础数据，形成体检计划智能体的前置画像输入。

#### 6.3.1 数据来源要求

医疗模块数据不是单表存储，工具实现需要按统一医疗资源和聚合接口理解数据边界：

| 数据域 | 主要来源 | 智能体使用方式 |
| --- | --- | --- |
| 基础档案 | `Member` + `MemberMedicalProfile.extra` | 年龄、性别、身高、体重、职业、久坐程度等，用于基础体检项目和人群分层 |
| 健康病史与症状记录 | `MemberMedicalProfile` 结构化 JSON + `Symptom`、`Surgery`、`MedicationPlan` 等事实表投影 | 慢病、过敏、手术史、症状随访、长期用药，用于专项加项和风险提示 |
| 生活习惯 | `smoking_profile`、`drinking_profile`、`exercise_profile`、`sleep_hours`、`extra.sleep_quality` | 吸烟、饮酒、运动、睡眠、熬夜久坐等，用于心血管、代谢、肺部等风险分层 |
| 过往体检档案 | `MemberMedicalProfile.extra` + `HealthExamReport` | 是否有体检史、最近体检时间、机构、报告摘要、异常项、已生成体检计划 |
| 风险评估 | `MemberMedicalProfile.notes` + `complete-data.guidance_sections` + 报告异常投影 | 读取服务端聚合出的分区摘要和风险提示，作为最终计划依据之一 |
| 模块完成状态 | `MemberModuleSetting` + `extra.section_progress` | 判断哪些画像分区已完成，哪些需要通过 `ask_user_question` 追问 |

推荐查询链路：

```text
query_member_profile(member_id)
  -> 读取 Member 基础属性
  -> 读取 MemberMedicalProfile 主档案
  -> 读取 MemberModuleSetting 的 medical 模块完成态
  -> 优先读取 /members/{member_id}/complete-data/ 聚合投影
  -> 整理 guidance_sections：basic_profile / health_history / lifestyle / exam_archive / risk_assessment
  -> 补充 HealthExamReport、Symptom、Surgery、MedicationPlan 等事实表摘要
  -> 返回 profile_snapshot + missing_fields + evidence_refs
```

#### 6.3.2 输出结构要求

`query_member_profile` 返回给模型的结果必须按体检计划场景整理，而不是把数据库字段原样抛给模型。

建议输出结构：

```json
{
  "member_id": "10",
  "basic_profile": {
    "name": "凯",
    "gender": "male",
    "age": 27,
    "height_cm": 171,
    "weight_kg": 66,
    "occupation": "程序员 / 开发 / 产品 / 设计",
    "sedentary_level": "medium"
  },
  "health_history": {
    "chronic_conditions": [],
    "allergies": ["荨麻疹"],
    "family_history": [],
    "symptom_follow_up_focus": ["牙痛"],
    "surgery_focus": ["拔牙"],
    "medication_focus": ["替硝唑片"]
  },
  "lifestyle": {
    "smoking_profile": {"status": "quit", "duration": "1-3 years", "quit_time": "2-5 years"},
    "drinking_profile": {},
    "exercise_profile": {},
    "sleep_hours": 6.5,
    "sleep_quality": "fair"
  },
  "exam_archive": {
    "has_exam_history": true,
    "last_exam_year": "2025-05",
    "exam_institution": "美年大健康",
    "exam_report_summary": "结构化异常摘要",
    "latest_exam_plan_id": "optional"
  },
  "risk_assessment": {
    "notes_summary": "职业、久坐、吸烟史、症状、报告异常等拼接后的可读摘要",
    "guidance_sections": [
      {"section_code": "basic_profile", "status": "completed"},
      {"section_code": "health_history", "status": "completed"},
      {"section_code": "lifestyle", "status": "completed"},
      {"section_code": "exam_archive", "status": "completed"},
      {"section_code": "risk_assessment", "status": "completed"}
    ]
  },
  "missing_fields": ["family_history_detail"],
  "evidence_refs": ["member", "member_medical_profile", "complete_data", "health_exam_report"]
}
```

字段要求：

1. `basic_profile`、`health_history`、`lifestyle`、`exam_archive`、`risk_assessment` 五个域必须稳定存在；没有数据时返回空对象或空数组，并在 `missing_fields` 标注。
2. `guidance_sections` 必须保留 `section_code` 和完成状态，供智能体判断是否需要追问。
3. `exam_report_summary` 可返回摘要和异常项，不返回整份 OCR 原文。
4. `medication_focus`、`surgery_focus`、`symptom_follow_up_focus` 是服务端投影字段，客户端不能把它们当作可直接 PATCH 的事实源。
5. `extra` 中的问卷状态位需要规范化为布尔/枚举语义，避免模型理解 `"have"`、`"none"`、`"true"` 等字符串时出错。

#### 6.3.3 智能体使用规则

1. 生成体检计划前必须先调用 `query_member_profile`。
2. 如果五个画像域中任一关键域缺失，优先用 `ask_user_question` 追问，而不是臆测。
3. 如果 `exam_archive.has_exam_history=true` 且存在报告摘要，应把既往异常纳入加项和复查计划。
4. 如果 `risk_assessment.notes_summary` 中已有风险评估，不得覆盖为通用模板；应引用并解释其与本次体检计划的关系。
5. 如果用户只问体检前准备，也可以不读取完整报告，但仍应读取基础档案和特殊风险，例如糖尿病、孕期、长期用药。

## 7. 智能体完整流程

### 7.1 总流程

```text
用户提出体检计划需求
  -> 意图识别：是否为 health_exam_plan_agent
  -> 成员确认：本人 / 家庭成员 / 未指定
  -> 资料读取：基础档案 + 健康病史与症状记录 + 生活习惯 + 过往体检档案 + 风险评估 + 历史报告 + 任务 + 记忆
  -> 缺口判断：是否缺年龄、性别、症状、家族史、生活习惯、预算/目标
  -> 追问补齐：最多 3 轮，每轮只问必要问题
  -> 风险分层：基础风险 / 专项风险 / 红旗风险
  -> 项目组合：基础项目 + 针对性加项 + 暂不建议项目
  -> 执行计划：体检前 2-3 天、前一晚、当天顺序、体检后
  -> 报告闭环：异常项追踪、复查周期、专科建议、任务创建
  -> 输出标准问答 + 结构化卡片
  -> 用户确认保存计划 / 创建任务 / 更新记忆
```

### 7.2 前置准备：整理个人与家族健康背景

智能体必须先整理以下信息，不能直接套通用套餐：

| 信息 | 必问条件 | 说明 |
| --- | --- | --- |
| 年龄、性别 | 始终必需 | 决定筛查年龄阈值和性别专项 |
| 近期症状 | 始终必需 | 头晕、胃痛、胸闷、便血、体重下降等影响优先级 |
| 慢性病史 | 始终必需 | 高血压、糖尿病、高脂血症、肾病、肝病等 |
| 正在用药 | 有慢病或报告异常时必问 | 影响肝肾功能、凝血、血糖、血脂解释 |
| 家族史 | 始终必需 | 直系亲属高血压、糖尿病、心血管疾病、癌症 |
| 生活习惯 | 始终必需 | 久坐、熬夜、高压、吸烟、饮酒、运动、饮食 |
| 女性专项 | 女性用户必问 | 月经、妊娠/备孕、妇科病史、乳腺相关风险 |
| 既往报告 | 有历史资料时读取 | 提取异常项和趋势 |
| 预算/体检目的 | 计划落地前询问 | 入职、年度、备孕、父母筛查、高风险复查 |

追问规则：

1. 已能从成员画像或报告读取的信息，不重复问。
2. 单轮最多问 4 个问题，优先使用选择题。
3. 如果用户不愿提供隐私信息，输出“基础保守方案”，并标注不确定性。
4. 出现红旗症状时，不继续套餐推荐优先，先建议及时就医。

### 7.3 项目组合策略

输出必须采用：

```text
基础必做项目 + 针对性加项 + 可选项目 + 暂不建议项目
```

基础必做项目：

| 类别 | 项目 |
| --- | --- |
| 一般检查/物理检查 | 身高、体重、BMI、血压、内科、外科、眼科、耳鼻喉科 |
| 实验室检查 | 血常规、尿常规、肝功能、肾功能、空腹血糖、血脂四项 |
| 辅助检查 | 12 导联心电图、腹部彩超（肝胆胰脾肾） |

针对性加项建议：

| 风险场景 | 建议加项 | 说明 |
| --- | --- | --- |
| 40 岁以上或肺癌高危因素 | 胸部低剂量螺旋 CT | 用于肺部风险筛查，不能用普通胸片替代同等筛查价值 |
| 消化道肿瘤家族史、便血、长期胃肠症状 | 胃肠镜或消化专科评估 | 有症状时优先就医，不只做体检套餐 |
| 高血压、高血脂、久坐熬夜 | 颈动脉彩超、心脏彩超、同型半胱氨酸（Hcy） | 用于心血管风险进一步评估 |
| 甲状腺结节史或家族史 | 甲状腺彩超 | 结合既往分级决定复查周期 |
| 女性成年用户 | 乳腺彩超、妇科检查 | 年龄、症状和既往史决定是否升级钼靶等 |
| 45 岁以上、绝经后、长期少晒太阳 | 骨密度、25-羟基维生素 D | 用于骨量和维生素 D 状态评估 |
| 肥胖、脂肪肝、血糖异常 | 糖化血红蛋白、胰岛素抵抗相关评估可选 | 结合医生建议，不作为确诊依据 |
| 尿酸高或痛风史 | 尿酸复查、肾功能、泌尿系彩超 | 关注肾结石和肾功能 |

暂不建议项目规则：

1. 不建议无差别堆叠全套肿瘤标志物。
2. 不建议把 PET-CT 作为普通年度体检筛查。
3. 不建议低风险年轻用户过度做高辐射或侵入性检查。
4. 不建议忽略症状，仅靠套餐替代专科门诊。

### 7.4 体检前与体检当日执行

智能体必须输出可执行清单：

```text
体检前 2-3 天
  - 清淡饮食
  - 避免剧烈运动、饮酒、熬夜
  - 如长期服药，按医生建议处理，不自行停药

体检前一晚
  - 晚 8 点后避免进食
  - 晚 12 点后按机构要求禁水或少量饮水
  - 准备身份证、医保卡、既往报告、药物清单

体检当天
  - 保持空腹
  - 穿无金属饰物、易脱穿衣物
  - 先完成抽血、腹部彩超等空腹项目
  - 需要憋尿的泌尿/妇科彩超按现场叫号安排
  - 完成空腹项目后再用餐，再做心电图、内外科、眼耳鼻喉等
```

当用户有糖尿病、孕期、肾病、长期抗凝/降压/降糖药等情况时，必须提示按医生或体检机构要求处理，不做统一停药建议。

### 7.5 报告解读与健康闭环

报告出来后，智能体必须推动闭环：

| 异常等级 | 示例 | 输出要求 |
| --- | --- | --- |
| 轻度异常 | 轻度脂肪肝、尿酸偏高、轻度血脂异常 | 生活方式建议 + 3-6 个月复查任务 |
| 需复查异常 | 肝肾功能异常、血糖异常、甲状腺结节、肺结节 | 标注复查项目、复查周期、建议专科 |
| 高风险异常 | 占位、可疑恶性、严重胸痛/便血/黑便/明显消瘦 | 优先建议尽快专科就医或急诊，不延迟到下次体检 |

闭环动作：

1. 生成“异常项追踪清单”。
2. 生成“下一次复查/体检任务”。
3. 回写成员医疗画像中的体检计划摘要。
4. 保存可复用风险因素到记忆，但必须让用户确认。
5. 下次问答自动引用历年指标趋势。

## 8. 最终问答标准

### 8.1 回答结构标准

最终答案必须稳定包含以下模块，除非用户明确只问单点问题：

```text
1. 先给结论
2. 我依据了什么
3. 你的风险分层
4. 推荐体检项目
   - 基础必做
   - 针对性加项
   - 可选/暂不建议
5. 体检前和当天怎么做
6. 报告出来后怎么追踪
7. 需要你确认/补充的信息
8. 医疗边界提示
```

### 8.2 标准回答示例

```markdown
我建议你这次选“基础体检 + 心血管/代谢加项”的组合，不建议一上来堆全套肿瘤标志物。

我依据的信息：
- 你今年 38 岁，长期久坐、熬夜，近期偶尔胸闷。
- 家族里有高血压和糖尿病史。
- 你没有提供既往体检报告，所以这版是基线方案。

你的风险重点：
- 代谢风险：血糖、血脂、尿酸、脂肪肝。
- 心血管风险：血压、心电图、颈动脉和心脏结构评估。
- 消化道和肺部暂按普通风险处理，除非你有吸烟、便血、长期胃痛或肿瘤家族史。

推荐项目：
- 基础必做：身高体重、血压、内外科、眼耳鼻喉、血常规、尿常规、肝功能、肾功能、空腹血糖、血脂四项、12 导联心电图、腹部彩超。
- 针对性加项：糖化血红蛋白、尿酸、颈动脉彩超、心脏彩超、同型半胱氨酸。
- 可选项目：甲状腺彩超。
- 暂不建议：普通低风险情况下不建议 PET-CT 或全套肿瘤标志物作为年度体检主项目。

体检执行：
- 体检前 2-3 天清淡饮食，避免饮酒、剧烈运动和熬夜。
- 前一晚 8 点后不再进食，按体检机构要求禁水。
- 当天先做抽血和腹部彩超，再处理需要憋尿的彩超，之后吃早餐，再做心电图和常规检查。

报告出来后：
- 如果只是轻度脂肪肝、尿酸或血脂偏高，建议生活方式干预后 3-6 个月复查。
- 如果出现肺部实性结节、占位、便血相关异常或医生提示高危，请尽快去专科门诊，不要等下一年体检。

我可以帮你把“体检前准备”和“3 个月复查血脂/尿酸”保存成提醒任务。
```

### 8.3 追问标准

信息不足时不要一次问太多，应按优先级追问：

第一轮：

```text
为了避免给你推荐过多项目，我先确认 4 个关键点：
1. 这次是给你本人还是家人做计划？
2. 年龄和性别是？
3. 最近有没有明显不舒服，比如胸闷、胃痛、头晕、便血、体重明显下降？
4. 直系亲属有没有高血压、糖尿病、心血管疾病或癌症？
```

第二轮：

```text
再补两个会影响加项的问题：
1. 是否吸烟、经常饮酒、长期熬夜或久坐？
2. 是否有既往体检异常，例如脂肪肝、血脂高、尿酸高、结节、血糖异常？
```

第三轮：

```text
最后确认落地偏好：
1. 你希望偏基础经济，还是尽量全面？
2. 有没有已预约的体检机构或体检日期？
```

### 8.4 医疗安全标准

必须遵守：

1. 对高危症状先建议就医，再谈体检。
2. 对报告异常要区分“轻度异常、需复查、高风险异常”。
3. 不给出药物停用、药量调整、确诊或排除诊断。
4. 涉及辐射、侵入性检查、孕产、儿童、老人、多病共存时要提示医生评估。
5. 回答中必须说明“体检计划是健康管理建议，不替代医生诊疗”。

## 9. DeepTutorChat 能力分流规则

### 9.1 命中意图

用户输入包含以下语义时，应进入 `health_exam_plan_agent`：

```text
体检计划
体检套餐怎么选
体检项目
年度体检
父母体检
报告出来后下一步
根据报告制定计划
复查计划
下次体检查什么
体检前准备
体检当天流程
```

### 9.2 不应命中或需转诊的意图

| 用户意图 | 处理方式 |
| --- | --- |
| “我现在胸痛怎么办” | 不进入体检计划，优先紧急就医提示 |
| “这个结节是不是癌” | 进入报告解读/风险提示，不做确诊 |
| “帮我选最便宜套餐” | 可以辅助筛选，但不能只按价格牺牲必要项目 |
| “我不想告诉年龄性别，直接推荐” | 输出保守基础方案，并声明不确定性 |

## 10. 结构化输出 Schema 建议

为了后续卡片化和保存计划，模型最终应能产出如下 JSON 语义：

```json
{
  "agent": "health_exam_plan_agent",
  "member_id": "member_123",
  "confidence": "medium",
  "basis": {
    "profile_fields": ["age", "sex", "chronic_conditions", "family_history", "lifestyle"],
    "report_refs": ["exam_report_2025"],
    "missing_fields": ["budget_preference"]
  },
  "risk_summary": [
    {
      "category": "cardiovascular",
      "level": "moderate",
      "reason": "hypertension family history and sedentary lifestyle"
    }
  ],
  "exam_items": {
    "basic": ["blood_pressure", "cbc", "urinalysis", "liver_function", "kidney_function", "fasting_glucose", "lipids", "ecg_12_lead", "abdominal_ultrasound"],
    "targeted": ["carotid_ultrasound", "echocardiography", "homocysteine"],
    "optional": ["thyroid_ultrasound"],
    "not_recommended": ["pet_ct_for_routine_screening"]
  },
  "execution_plan": {
    "before_2_3_days": ["light_diet", "avoid_alcohol", "avoid_strenuous_exercise", "sleep_regularly"],
    "night_before": ["fast_after_20_00", "follow_institution_water_rule", "prepare_previous_reports"],
    "exam_day_order": ["blood_draw", "abdominal_ultrasound", "urinary_or_gynecologic_ultrasound_if_needed", "breakfast", "ecg", "physical_exam"]
  },
  "follow_up": [
    {
      "item": "lipids",
      "timing": "3-6 months",
      "action": "recheck_after_lifestyle_intervention"
    }
  ],
  "safety_notice": "This plan is health management guidance and does not replace medical diagnosis or treatment."
}
```

## 11. UI 与消息卡片建议

### 11.1 计划结果卡

卡片标题：

```text
体检计划
```

卡片分区：

1. 风险重点：最多 3 条。
2. 基础必做：折叠列表。
3. 针对性加项：展示“为什么建议”。
4. 体检执行：按时间轴展示。
5. 复查任务：展示可一键保存按钮。

### 11.2 追问卡

复用 `DeepTutorAskUserCardView`，问题类型优先用选择项：

1. 成员选择。
2. 年龄/性别确认。
3. 症状多选。
4. 家族史多选。
5. 生活习惯多选。
6. 预算偏好单选。

### 11.3 风险提示卡

出现以下情况必须展示 `show_medical_risk_notice`：

1. 胸痛、明显胸闷、呼吸困难。
2. 便血、黑便、进行性消瘦。
3. 报告出现占位、可疑恶性、高危结节。
4. 严重肝肾功能异常。
5. 用户要求用体检替代治疗或复诊。

## 12. 数据与隐私

1. 家族史、疾病史、报告异常、用药属于敏感健康信息，必须进入工具审计。
2. 使用联网搜索时，不得把可识别个人身份的报告内容原文外传。
3. 保存长期记忆前必须征得用户确认，例如“是否把父亲有糖尿病史保存到健康画像？”
4. 家庭成员资料必须遵守成员绑定和权限体系，共享用户无权限时不能读取。
5. 输出给模型的报告上下文应优先使用结构化摘要，不直接传整份原始 PDF/OCR 文本。
6. `query_member_profile` 返回的医疗档案数据必须做最小必要化：体检计划只需要摘要、风险因素、缺失字段和证据引用，不应输出完整原始 `extra`、完整 OCR 文本或无关历史明细。

## 13. 实施拆解

### 13.1 P1 必做

1. 在 DeepTutorChat 能力分流中增加 `health_exam_plan_agent` 意图。
2. 为该意图配置工具组合白名单：成员、画像、健康资源、追问、知识、风险提示、任务、结构化卡片。
3. 增加体检计划系统提示词模板，固定问答结构与安全边界。
4. 使用 `DeepTutorAskUserCardView` 承接画像缺口追问。
5. 使用 `generate_structured_health_card` 输出体检计划卡。
6. 用户确认后用 `generate_task` 创建体检前准备和复查任务。
7. 优化 `query_member_profile`，支持查询并整理基础档案、健康病史与症状记录、生活习惯、过往体检档案、风险评估五类医疗档案基础数据。
8. 增加单元测试覆盖能力分流、工具白名单、画像聚合和问答结构解析。

### 13.2 P2 增强

1. 新增 `generate_health_exam_plan` 结构化领域工具。
2. 新增 `save_health_exam_plan` 保存计划到成员医疗画像。
3. 新增历年体检报告趋势对比。
4. 体检计划卡支持“一键导出 PDF/分享给家人”。
5. 结合城市和体检机构套餐做项目覆盖度比对。

## 14. 验收标准

### 14.1 功能验收

1. 用户输入“帮我制定今年体检计划”，如果成员不明确，必须先触发成员选择或画像追问。
2. 用户输入“结合我去年的体检报告制定计划”，必须调用健康资源列表和报告上下文工具。
3. 输出必须包含基础必做、针对性加项、可选/暂不建议、体检前准备、当天顺序、报告后追踪。
4. 高危症状或报告高危异常时，必须先给就医提示，不能只推荐体检套餐。
5. 用户确认保存后，必须生成至少一个任务，例如体检预约、体检前准备、3-6 个月复查。

### 14.2 工具验收

1. `health_exam_plan_agent` 本轮工具列表不得包含无关天气、地图、绘图工具。
2. 关闭健康资料读取开关后，智能体只能追问用户，不得声称已读取报告。
3. 无成员权限时，工具返回权限错误，最终回答必须提示需要授权。
4. 所有健康资料读取和联网搜索外传必须进入审计日志。
5. `query_member_profile` 必须返回 `basic_profile`、`health_history`、`lifestyle`、`exam_archive`、`risk_assessment` 五个稳定域。
6. `query_member_profile` 必须能识别医疗模块各分区完成态，并把未完成或缺失的字段写入 `missing_fields`。
7. 当用户已维护过体检报告摘要、症状、手术、用药或风险评估时，体检计划回答必须能引用这些数据作为依据，不能继续输出“未提供既往资料”的通用话术。

### 14.3 回答质量验收

1. 不出现“所有人都建议做全套肿瘤标志物”。
2. 不出现“检查正常就一定没问题”。
3. 不出现“可以自行停药后体检”。
4. 不出现没有依据的具体诊断。
5. 每个加项至少说明一个触发理由。
6. 暂不建议项目必须说明原因，避免用户误解为漏项。

## 15. 测试建议

| 测试文件建议 | 覆盖点 |
| --- | --- |
| `Tests/DeepTutorChat/DeepTutorHealthExamPlanIntentTests.swift` | 体检计划意图识别 |
| `Tests/DeepTutorChat/DeepTutorHealthExamPlanToolPolicyTests.swift` | 工具白名单与敏感工具过滤 |
| `Tests/DeepTutorChat/DeepTutorMemberProfileAggregationTests.swift` | `query_member_profile` 医疗档案五域聚合与缺失字段判断 |
| `Tests/DeepTutorChat/DeepTutorHealthExamPlanPromptTests.swift` | 系统提示词包含问答结构和医疗安全边界 |
| `Tests/DeepTutorChat/DeepTutorHealthExamPlanCardParserTests.swift` | 结构化计划卡解析 |
| `Tests/DeepTutorChat/DeepTutorHealthExamPlanSafetyTests.swift` | 红旗症状优先就医 |

核心测试用例：

1. 32 岁无报告首次体检，生成基础方案并追问家族史。
2. 45 岁男性吸烟，建议肺部低剂量 CT 并说明原因。
3. 女性用户，建议乳腺和妇科专项，并根据年龄/症状分层。
4. 去年报告有脂肪肝、尿酸高，生成 3-6 个月复查任务。
5. 用户说“现在胸痛”，不进入常规体检套餐推荐。

## 16. 风险与取舍

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 模型过度推荐项目 | 用户成本增加，医疗焦虑 | 强制“暂不建议项目”和加项理由 |
| 模型遗漏高危异常 | 医疗安全风险 | 红旗症状和高危报告异常走风险提示卡 |
| 画像缺失导致方案不准 | 个性化不足 | 最多 3 轮追问，缺失时标注不确定性 |
| 联网搜索外传隐私 | 合规风险 | 搜索只传泛化问题，不传身份和完整报告 |
| 任务过多打扰用户 | 体验下降 | 只有用户确认后创建任务，高风险除外也需说明 |

## 17. 结论

本工单建议把“体检报告制定计划”作为 DeepTutorChat 的一个独立健康智能体能力，而不是普通 prompt。第一期重点是：

```text
成员与报告上下文读取
-> 必要追问
-> 风险分层
-> 基础项目 + 针对性加项
-> 体检执行清单
-> 报告后复查任务
```

这样能把用户给出的体检建议材料转成可执行产品流程，并和 SparkClient 现有 DeepTutorChat、医疗画像、报告上传、任务系统形成闭环。
