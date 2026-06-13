# AI 识别报告详设文档

> 范围说明：本文详细设计 SparkClient 医疗档案内 AI 文档识别、OCR、类型识别、结构化抽取、失败重试与结果修正流程。本文为详设文档，用于指导后续客户端实现；重点设计“结构化抽取失败后，继续识别时携带上次失败原因”的公共能力。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICAL-AI-OCR-000001` | 结构化抽取失败后继续识别需携带上次失败原因 | 已实现 | AI 识别报告、解码失败反馈、公共 Prompt 追加、本地化、继续识别流程 |
| `MEDICAL-AI-OCR-000002` | 解码失败自动重试与本地配置开关 | 已实现 | 仅解码失败带入失败原因、自动重试、通用设置、重试次数本地配置 |
| `MEDICAL-AI-OCR-000003` | 提交前本地预校验与字段高亮纠错 | 已实现 | 客户端按服务端规则预校验、对应模块提示、字段高亮、用户修复后重新提交 |
| `MEDICAL-AI-OCR-000004` | 折叠模块内预校验错误自动展开并定位 | 已实现 | 提交失败后展开错误所在折叠模块、再滚动到对应卡片或字段 |
| `MEDICAL-AI-OCR-000005` | 缺少识别场景模型时引导配置模型密钥 | 已实现 | missingModelForScenario 弹窗提示、取消/前往设置、Sheet 打开模型密钥页面 |
| `MEDICAL-AI-OCR-000006` | 处方数组识别与用药资料草稿详情预览 | 新需求/待实现 | 处方数组抽取、结果页成员切换、处方/用药计划/药箱详情页本地草稿预览模式、编辑删除回调 |
| `MEDICAL-AI-OCR-000007` | 处方提交前 dose_value 数值预校验修复 | 修复需求/待实现 | combined-create 前拦截 dose_value 非数字、字段高亮、定位到对应处方药品 |
| `MEDICAL-AI-OCR-000008` | 草稿模式删除关联药箱未清理用药计划草稿 | 修复需求/待实现 | 用药计划详情进入药箱详情后删除药箱，清理本页草稿、父级草稿与最终保存 payload |
| `MEDICAL-AI-OCR-000009` | 处方识别药箱候选确认与批量保存 | 已实现 | 识别概览、加载家庭药箱、药品候选匹配、确认后由处方批量保存绑定已有药品或新建药箱、未确认剥离 medicineBox |
| `MEDICAL-AI-OCR-000010` | 处方识别保存前检查点补全 | 修复需求/待实现 | 补全处方/用药计划枚举、日期、频次、剂量、提醒时间、药箱表达等保存前检查点；处方状态只保留服务端合法值 |

## 工单 `MEDICAL-AI-OCR-000001`：结构化抽取失败后继续识别需携带上次失败原因

### 工单状态

已实现。

## 1. 设计背景

### 业务背景

医疗档案上传识别需要把图片、PDF 或文档中的 OCR 文本转成结构化医疗资料。当前支持的目标类型包括：

```swift
case caseDocument     // 病例文档（出院小结、门诊病历等）
case healthExamReport // 体检报告（包含大量数值指标）
case medicalReport    // 医疗报告（如 B超、CT、放射科报告）
case prescription     // 处方单（用药清单与剂量）
case medicationPlan   // 用药计划（抽取药箱 + 服药计划组合）
case medicineBox      // 药品/药盒包装（用于加入药箱）
```

识别流程大体为：

```text
upload -> ocr -> type_recognition -> extract -> attachment_binding -> save
```

当前问题出现在 `extract` 阶段：AI 已经返回 JSON，但某些字段类型不符合客户端 schema，导致 Swift 解码失败。用户点击“继续识别”后，如果仍使用同一份原始 Prompt，AI 可能再次输出同样的错误结构。

### 典型失败样例

药盒识别中，客户端模型要求：

```swift
extra: [String: String]
```

AI 实际返回：

```json
[
  {
    "medicineName": "Fufang Huangbaiye Tuji",
    "medicineType": "",
    "brandName": "舜圣堂",
    "dosageForm": "Topical solution",
    "strength": "100ml",
    "doseUnit": "ml",
    "totalQuantity": "1",
    "expireDate": "",
    "notes": "",
    "extra": "",
    "sortOrder": 0
  }
]
```

解码失败：

```text
typeMismatch(Dictionary<String, Any>, codingPath: [Index 0, extra])
Expected to decode Dictionary<String, Any> but found a string instead.
```

需要在下一次继续识别时明确告诉 AI：

```text
字段 [0].extra 类型错误；extra 必须是 JSON object，未知时使用 {}，不要输出 ""。
```

## 2. 设计目标

### 核心设计目标

新增一个公共“结构化抽取失败反馈”机制。当 `extract` 阶段失败后，系统记录归一化失败原因；用户点击“继续识别”时，复用已完成的上传、OCR 和类型识别结果，并把失败原因作为本地化的纠错块追加到原有抽取 Prompt 末尾，再次请求 AI。

### 第一期目标

1. 支持记录最近一次 `extract` 阶段失败原因。
2. 支持从 `DecodingError` / `ExtractionError` 中归一化字段路径、期望类型、实际类型和修正建议。
3. 支持继续识别时把失败原因追加到原 Prompt。
4. 支持中文和英文 Prompt 纠错块本地化。
5. 覆盖全部医疗文档类型，不只针对药盒。
6. 继续识别时复用 upload / OCR / type recognition checkpoint。
7. 抽取成功后清空失败反馈。
8. 切换文件、切换成员、重新开始流程时清空旧失败反馈。

### 第一期边界

1. 不做自动无限重试。
2. 不把完整日志、完整请求报文或完整 stack trace 塞入 Prompt。
3. 不在 ViewModel 或 Extractor 中硬编码长中文提示词。
4. 不改变现有 OCR、类型识别、保存结果页设计。
5. 不在本工单内大规模放宽所有 JSON 解码规则。

## 3. 总体架构设计

### 模块划分

```text
MedicalDocumentUploadViewModel
  ├─ 维护识别流程状态
  ├─ 捕获 extract 失败
  ├─ 保存 lastExtractionRetryFeedback
  └─ 用户点击继续识别时传入 feedback

ExtractTypedMedicalDocumentUseCase
  └─ 透传 retryFeedback 到 extractor

DefaultTypedMedicalDocumentExtractor
  ├─ 生成基础 extraction prompt
  ├─ 调用 MedicalPromptFactory 追加 retry correction
  ├─ 执行 AI 结构化抽取
  └─ 失败时抛出带上下文的错误

MedicalPromptFactory
  ├─ 根据文档类型生成基础 prompt
  └─ 拼接 retry correction block

PromptLocalizer / Prompts.strings
  └─ 提供 retry correction 本地化模板

MedicalExtractionErrorNormalizer
  └─ 把 DecodingError / ExtractionError 归一化为 MedicalExtractionRetryFeedback

StructuredJSONStreamDecoder
  └─ 暴露 AI 输出 preview 与解码失败上下文
```

### 关键原则

1. UI 只负责触发继续识别，不负责拼 Prompt。
2. Prompt 拼接集中在 `MedicalPromptFactory`。
3. 错误归一化集中在 `MedicalExtractionErrorNormalizer`。
4. 本地化集中在 `PromptLocalizer / Prompts.strings`。
5. Extractor 只消费最终 Prompt，不关心 UI 文案。

## 4. 数据结构设计

### `MedicalExtractionRetryFeedback`

新增公共模型：

```swift
struct MedicalExtractionRetryFeedback: Sendable, Codable, Equatable {
    let kind: MedicalDocumentKind
    let step: MedicalDocumentUploadStep
    let errorCode: MedicalExtractionRetryErrorCode
    let fieldPath: String?
    let expectedType: String?
    let actualType: String?
    let rawMessage: String
    let aiOutputPreview: String?
    let suggestion: String?
    let createdAt: Date
}
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `kind` | 当前文档类型，例如 `medicineBox` |
| `step` | 失败步骤，第一期主要是 `.extract` |
| `errorCode` | 归一化错误码 |
| `fieldPath` | 出错字段路径，例如 `[0].extra` |
| `expectedType` | 期望类型，例如 `object/dictionary` |
| `actualType` | 实际类型，例如 `string` |
| `rawMessage` | 简短原始错误描述，限制长度 |
| `aiOutputPreview` | AI 上次输出片段，限制长度 |
| `suggestion` | 面向 AI 的短修正建议 |
| `createdAt` | 反馈创建时间 |

### `MedicalExtractionRetryErrorCode`

新增错误码枚举：

```swift
enum MedicalExtractionRetryErrorCode: String, Codable, Sendable {
    case jsonTypeMismatch
    case jsonKeyNotFound
    case jsonValueNotFound
    case jsonDataCorrupted
    case invalidJSONShape
    case markdownWrappedJSON
    case unknown
}
```

### `MedicalPromptInput` 扩展

当前：

```swift
struct MedicalPromptInput: Sendable {
    let kind: MedicalDocumentKind
    let mergedOCRText: String
}
```

建议扩展：

```swift
struct MedicalPromptInput: Sendable {
    let kind: MedicalDocumentKind
    let mergedOCRText: String
    let retryFeedback: MedicalExtractionRetryFeedback?

    init(
        kind: MedicalDocumentKind,
        mergedOCRText: String,
        retryFeedback: MedicalExtractionRetryFeedback? = nil
    ) {
        self.kind = kind
        self.mergedOCRText = mergedOCRText
        self.retryFeedback = retryFeedback
    }
}
```

这样旧调用不需要全部改动，新增能力保持兼容。

## 5. 流程详设

### 首次识别流程

```text
MedicalDocumentUploadViewModel.prepareAndStart
  -> upload
  -> ocr
  -> type_recognition
  -> extractStructured(retryFeedback: nil)
  -> success:
       clear lastExtractionRetryFeedback
       continue attachment_binding
  -> failure:
       normalize error
       save lastExtractionRetryFeedback
       show extract failed state
```

### 继续识别流程

```text
用户点击继续识别
  -> ViewModel 确认 selectedFiles / mergedOCRText / typeResolution 仍有效
  -> 复用 upload checkpoint
  -> 复用 OCR checkpoint
  -> 复用 type recognition checkpoint
  -> extractStructured(retryFeedback: lastExtractionRetryFeedback)
  -> MedicalPromptFactory 生成基础 prompt
  -> MedicalPromptFactory 追加本地化 retry correction block
  -> AI 抽取
  -> success:
       clear lastExtractionRetryFeedback
       continue attachment_binding
  -> failure:
       用新错误覆盖 lastExtractionRetryFeedback
```

### 状态机设计

新增 ViewModel 状态：

```swift
@Published private(set) var lastExtractionRetryFeedback: MedicalExtractionRetryFeedback?
@Published private(set) var isRetryingExtraction = false
```

状态清理规则：

| 场景 | 处理 |
| --- | --- |
| 抽取失败 | 保存 feedback |
| 继续识别成功 | 清空 feedback |
| 继续识别再次失败 | 用新 feedback 覆盖旧 feedback |
| 用户重新选择文件 | 清空 feedback |
| 用户切换成员 | 清空 feedback |
| 用户切换识别类型 | 清空 feedback |
| 用户取消流程 | 清空 feedback |

## 6. Prompt 拼接详设

### Prompt 拼接位置

`MedicalPromptFactory` 负责统一拼接：

```swift
func extractionPrompt(for input: MedicalPromptInput) -> String {
    let base = baseExtractionPrompt(for: input.kind, ocrText: input.mergedOCRText)
    guard let feedback = input.retryFeedback else { return base }
    let correction = localizer.medicalExtractionRetryCorrectionPrompt(
        kind: input.kind,
        feedback: feedback
    )
    return [base, correction]
        .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        .joined(separator: "\n\n---\n\n")
}
```

### Correction block 模板

中文模板：

```text
【重试修正要求】
上一次结构化抽取失败，失败原因如下：
- 文档类型：{kind}
- 错误字段：{fieldPath}
- 期望类型：{expectedType}
- 上次实际类型：{actualType}
- 失败说明：{rawMessage}
- 修正建议：{suggestion}

请在不改变原始 OCR 事实的前提下，重新输出符合原 schema 的纯 JSON。
不要输出 Markdown，不要输出解释文字。
如果字段未知，请使用该 schema 允许的空值；例如 extra 未知时使用 {}，数组未知时使用 []。
```

英文模板：

```text
[Retry correction]
The previous structured extraction failed:
- Document type: {kind}
- Invalid field: {fieldPath}
- Expected type: {expectedType}
- Previous actual type: {actualType}
- Error: {rawMessage}
- Fix suggestion: {suggestion}

Please return pure JSON that follows the original schema, without changing OCR facts.
Do not return Markdown or explanatory text.
Use schema-compatible empty values when unknown; for example, use {} for unknown extra and [] for unknown arrays.
```

### 长度限制

| 字段 | 最大长度 |
| --- | --- |
| `rawMessage` | 500 字符 |
| `suggestion` | 500 字符 |
| `aiOutputPreview` | 1200 字符 |
| correction block 总长度 | 建议不超过 2500 字符 |

第一期 Prompt 不默认附带 `aiOutputPreview`，除非错误归一化需要展示上次实际输出片段。避免把旧错误答案再次强化给模型。

## 7. 错误归一化详设

### `MedicalExtractionErrorNormalizer`

新增：

```swift
enum MedicalExtractionErrorNormalizer {
    static func makeFeedback(
        kind: MedicalDocumentKind,
        step: MedicalDocumentUploadStep,
        error: Error,
        aiOutputPreview: String?
    ) -> MedicalExtractionRetryFeedback
}
```

### `DecodingError` 处理

重点处理：

```swift
case .typeMismatch(let type, let context)
case .keyNotFound(let key, let context)
case .valueNotFound(let type, let context)
case .dataCorrupted(let context)
```

字段路径生成：

```swift
private static func fieldPath(from codingPath: [CodingKey]) -> String {
    codingPath.map { key in
        if let intValue = key.intValue { return "[\(intValue)]" }
        return ".\(key.stringValue)"
    }
    .joined()
    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
}
```

样例：

```text
[_CodingKey(Index 0), CodingKeys(extra)] -> [0].extra
```

### 常见字段修正建议

| 字段路径命中 | 建议 |
| --- | --- |
| `extra` | `extra` must be a JSON object. Use `{}` when unknown. Do not use `""`. |
| `items` | `items` must be an array. Use `[]` when no item is available. |
| `medicines` | `medicines` must be an array of medicine objects. |
| `indicators` | `indicators` must be an array of exam indicator objects. |
| `date` / `examDate` / `expireDate` | Use `yyyy-MM-dd` when visible; otherwise use the schema-compatible empty value. |
| `sortOrder` | Use integer number, not string. |

中文本地化建议由 `PromptLocalizer` 根据 `fieldPath` 和 `errorCode` 输出。

## 8. 接口与调用链改造

### `ExtractTypedMedicalDocumentUseCase`

建议签名：

```swift
func extractStructured(
    memberID: Int,
    files: [MedicalUploadLocalFile],
    mergedOCRText: String,
    resolution: MedicalDocumentTypeResolution,
    preferredModelName: String? = nil,
    retryFeedback: MedicalExtractionRetryFeedback? = nil,
    cancellationToken: AIRuntimeCancellationToken? = nil
) async throws -> MedicalDocumentTypedExtractionOutput
```

### `DefaultTypedMedicalDocumentExtractor`

建议签名：

```swift
func extractStructured(
    memberID: Int,
    files: [MedicalUploadLocalFile],
    mergedOCRText: String,
    resolution: MedicalDocumentTypeResolution,
    preferredModelName: String? = nil,
    retryFeedback: MedicalExtractionRetryFeedback? = nil,
    cancellationToken: AIRuntimeCancellationToken? = nil
) async throws -> MedicalDocumentTypedExtractionOutput
```

Prompt 生成：

```swift
let prompt = promptFactory.extractionPrompt(
    for: MedicalPromptInput(
        kind: kind,
        mergedOCRText: mergedOCRText,
        retryFeedback: retryFeedback
    )
)
```

### `StructuredJSONStreamDecoder`

为了生成可用反馈，需要暴露：

```swift
struct StructuredJSONDecodingFailureContext: Sendable {
    let error: Error
    let outputPreview: String
    let kindLabel: String
}
```

可选实现方式：

1. 在 `StructuredJSONStreamDecoder.collect` 抛出包装错误，包含 preview。
2. 在 `DefaultTypedMedicalDocumentExtractor.extractStructured` 捕获失败时读取 final text preview。
3. 如果当前 collect 失败前无法返回 preview，则先只用 `DecodingError` 生成反馈，后续再增强。

第一期优先目标是拿到字段路径和类型错误，preview 可选。

## 9. UI 交互详设

### 失败状态展示

`extract` 失败后，现有失败 UI 保持。增加轻量说明：

```text
上次识别结果格式不符合要求，继续识别时将携带失败原因让 AI 修正。
```

### 继续识别按钮

点击继续识别时：

1. 不重新上传文件。
2. 不重新 OCR。
3. 不重新类型识别，除非用户主动切换类型。
4. 直接从 `extract` 步骤重新执行。
5. 步骤摘要可显示：

```text
重新抽取 · 已携带上次失败原因
```

### 调试信息

Debug 环境可展示更具体字段：

```text
失败字段：[0].extra
期望类型：object
实际类型：string
```

生产环境只展示用户可理解的说明，不暴露 Swift 类型细节。

## 10. 文档类型覆盖设计

| 类型 | 场景 | 失败反馈使用方式 |
| --- | --- | --- |
| `caseDocument` | 病例、出院小结、门诊病历 | 修正病历草稿 JSON 字段 |
| `healthExamReport` | 体检报告 | 修正指标数组、数值/单位/日期字段 |
| `medicalReport` | B 超、CT、影像、病理等 | 修正报告数组或报告对象字段 |
| `prescription` | 处方单 | 修正药品列表、剂量、频次字段 |
| `medicationPlan` | 用药计划 | 修正药箱 + 服药计划组合结构 |
| `medicineBox` | 药盒包装 | 修正 `extra`、规格、数量、有效期字段 |

公共流程不关心具体类型，只使用 `kind` 选择基础 Prompt 和场景；失败纠错块按错误上下文追加。

## 11. 涉及文件与改动内容

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentUploadViewModel.swift` | 增加 `lastExtractionRetryFeedback`、`isRetryingExtraction`；失败时保存反馈，继续识别时传入反馈，成功/切换上下文时清空 | 流程状态管理 |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Application/ExtractTypedMedicalDocumentUseCase.swift` | `extractStructured` 增加 `retryFeedback` 可选参数并透传 | 用例接口扩展 |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultTypedMedicalDocumentExtractor.swift` | 使用带 retry feedback 的 `MedicalPromptInput`；捕获/透传解码失败上下文 | 抽取核心 |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/MedicalPromptFactory.swift` | 支持基础 Prompt + retry correction block 拼接 | Prompt 公共入口 |
| `PromptLocalizer` / `Prompts.strings` | 增加 retry correction 文案模板和字段建议本地化 | 本地化 |
| 新增 `MedicalExtractionRetryFeedback.swift` | 定义失败反馈模型和错误码 | 公共模型 |
| 新增 `MedicalExtractionErrorNormalizer.swift` | 归一化 `DecodingError` / `ExtractionError` | 公共错误处理 |
| `StructuredJSONStreamDecoder` | 可选：暴露失败时 AI 输出 preview | 诊断能力 |
| `MedicalDocumentUploadHostView` / 失败结果 UI | 增加继续识别说明 | 用户反馈 |

## 12. 验收标准

### 流程验收

1. 首次结构化抽取失败后，ViewModel 能记录最近一次失败反馈。
2. 用户点击继续识别后，不重复上传、不重复 OCR、不重复类型识别。
3. 再次执行 extract 时，Prompt 末尾包含本地化 retry correction block。
4. 抽取成功后清空失败反馈。
5. 切换文件、成员、识别类型或取消流程后，不复用旧反馈。

### 纠错验收

1. `extra` 返回字符串导致失败时，继续识别 Prompt 明确要求 `extra` 使用 object，未知时用 `{}`。
2. 数组字段返回对象导致失败时，继续识别 Prompt 明确要求使用 array。
3. 日期格式错误时，继续识别 Prompt 明确要求指定日期格式。
4. AI 修正输出后，页面能进入结果确认页。

### 本地化验收

1. 中文环境 correction block 使用中文。
2. 英文环境 correction block 使用英文。
3. 文档类型名称、字段错误说明、修正建议均支持本地化。
4. ViewModel / Extractor 中没有硬编码长中文 Prompt。

### 架构验收

1. 不只针对 `medicineBox` 做特判。
2. Prompt 拼接集中在 `MedicalPromptFactory` / `PromptLocalizer`。
3. 错误归一化集中在 `MedicalExtractionErrorNormalizer`。
4. 不把完整日志、完整请求报文塞进 Prompt。
5. 不自动无限重试。

## 13. 风险与后续扩展

### 主要风险

1. 失败原因过长会稀释原始抽取任务。
2. 把旧 AI 输出完整塞回 Prompt，可能强化错误答案。
3. 只做 Prompt 修正不能覆盖所有模型不稳定情况。
4. 如果错误归一化太粗糙，AI 得不到有效纠错信号。

### 后续扩展

1. JSON normalizer 对安全字段自动修复，例如 `extra: "" -> extra: {}`。
2. 为每种文档类型补充 schema 示例，提升模型稳定性。
3. 支持一次失败后自动低成本重试一次，仍失败再让用户手动继续。
4. 保存失败样本到 Debug 日志，便于优化 Prompt。
5. 为不同模型维护结构化抽取兼容策略。

## 工单 `MEDICAL-AI-OCR-000002`：解码失败自动重试与本地配置开关

### 工单状态

已实现。

## 1. 设计背景

### 背景说明

`MEDICAL-AI-OCR-000001` 已实现“结构化抽取失败后，继续识别时携带上次失败原因”。该方案解决了手动继续识别时 AI 反复犯同类 JSON schema 错误的问题。

本工单进一步优化两个点：

1. **只有解码失败才允许把失败原因带入 Prompt。**
2. **解码失败可以在流程内部自动重试，不需要用户手动点击继续识别。**

这里需要严格区分失败类型。不是所有失败都适合带入 Prompt 让 AI 修正。

### 失败类型区分

| 失败类型 | 是否带入 Prompt | 是否自动重试 | 原因 |
| --- | --- | --- | --- |
| JSON 解码失败 / schema 类型错误 | 是 | 可配置 | AI 已返回内容，但结构不符合客户端 schema，可以通过 Prompt 修正 |
| AI 网关调用失败 | 否 | 否 | 网络、服务端、鉴权、限流等问题，Prompt 无法修复 |
| 模型不可用 / API Key 缺失 | 否 | 否 | 配置问题，应该提示用户处理模型配置 |
| 用户取消 / 任务取消 | 否 | 否 | 用户主动行为，不应自动重试 |
| OCR 失败 | 否 | 否 | 不是结构化抽取输出问题 |
| 上传失败 | 否 | 否 | 文件/网络问题 |
| 保存失败 | 否 | 否 | 后端或业务数据保存问题 |
| 类型识别失败 | 否 | 否 | 不属于结构化抽取 schema 解码失败 |

核心原则：

```text
只有 extract 阶段的“AI 输出 JSON 解码失败”才生成 retry feedback 并允许自动重试。
其他错误不生成 retry feedback，不追加失败原因到 Prompt。
```

## 2. 设计目标

### 核心设计目标

在医疗报告 AI 结构化抽取流程中，增加可配置的“解码失败自动重试”能力。开启后，当 `extract` 阶段因为 AI 输出 JSON 无法解码或字段类型不匹配失败时，系统自动生成失败反馈、追加到 Prompt，并在流程内自动重新抽取。用户无需手动点击“继续识别”。

### 第一期目标

1. 仅 `DecodingError` / `StructuredJSONDecodingFailure` / `ExtractionError.decodingFailed(context:)` 触发 retry feedback。
2. AI 调用失败、网络失败、取消、上传/OCR/保存失败不进入 retry feedback。
3. 自动重试开关默认关闭。
4. 设置位置：通用设置内新增“医疗报告抽取”模块。
5. 支持配置自动重试次数。
6. 最大自动重试次数为 5 次。
7. 配置仅保存在本地，不要求服务端同步。
8. 开启后，流程内自动重试；重试仍失败且达到次数上限后，才进入失败状态。
9. 每次自动重试都携带上一次解码失败原因。
10. 成功后清空重试状态和失败反馈。

### 第一期边界

1. 不对非解码失败自动重试。
2. 不做指数退避，第一期同一流程内顺序重试即可。
3. 不做服务端配置同步。
4. 不做按文档类型分别配置次数。
5. 不做不同模型的差异化重试策略。

## 3. 设置设计

### 设置入口

在 App 通用设置内新增模块：

```text
通用设置
  -> 医疗报告抽取
       -> 抽取失败自动重试
       -> 自动重试次数
```

模块名称建议：

```text
医疗报告抽取
```

### 配置项

| 配置项 | 类型 | 默认值 | 范围 | 说明 |
| --- | --- | --- | --- | --- |
| `autoRetryOnDecodingFailureEnabled` | Bool | `false` | 开/关 | 是否在结构化抽取解码失败后自动重试 |
| `maxDecodingFailureAutoRetryCount` | Int | `1` | `1...5` | 开启后最多自动重试次数 |

注意：

```text
默认不开启自动重试。
即使默认次数是 1，只有开关打开才生效。
```

### 本地存储

配置只存本地，建议使用 `UserDefaults` 或现有本地设置仓储。

建议 key：

```swift
medicalExtraction.autoRetryOnDecodingFailure.enabled
medicalExtraction.autoRetryOnDecodingFailure.maxCount
```

建议模型：

```swift
struct MedicalExtractionRetrySettings: Equatable, Codable, Sendable {
    var autoRetryOnDecodingFailureEnabled: Bool
    var maxDecodingFailureAutoRetryCount: Int

    static let `default` = MedicalExtractionRetrySettings(
        autoRetryOnDecodingFailureEnabled: false,
        maxDecodingFailureAutoRetryCount: 1
    )
}
```

保存时需要 clamp：

```swift
maxDecodingFailureAutoRetryCount = min(max(value, 1), 5)
```

## 4. 自动重试流程详设

### 流程概览

```text
extract 第 1 次调用
  -> 成功：继续 attachment_binding
  -> 非解码失败：直接失败，不自动重试，不带入 Prompt
  -> 解码失败：
       if 设置关闭：进入失败状态，允许手动继续识别
       if 设置开启：生成 retry feedback，自动重试

自动重试第 N 次
  -> 使用上一次 decoding failure 生成 retry correction prompt
  -> 成功：继续 attachment_binding，清空 retry 状态
  -> 解码失败且 N < maxCount：更新 feedback，继续自动重试
  -> 解码失败且 N >= maxCount：进入失败状态，保留最后一次 feedback
  -> 非解码失败：直接失败，不继续自动重试
```

### 伪代码

```swift
private func runExtractWithOptionalAutoRetry(...) async throws -> MedicalDocumentTypedExtractionOutput {
    var attempt = 0
    var retryFeedback: MedicalExtractionRetryFeedback? = nil
    let settings = medicalExtractionRetrySettingsStore.load()
    let maxRetry = settings.autoRetryOnDecodingFailureEnabled
        ? settings.maxDecodingFailureAutoRetryCount
        : 0

    while true {
        do {
            let output = try await extractUseCase.extractStructured(
                ...,
                retryFeedback: retryFeedback,
                cancellationToken: cancellationToken
            )
            clearExtractionRetryFeedback()
            return output
        } catch {
            guard isDecodingFailure(error) else {
                clearExtractionRetryFeedback()
                throw error
            }

            let feedback = MedicalExtractionErrorNormalizer.makeFeedback(...)
            lastExtractionRetryFeedback = feedback

            guard attempt < maxRetry else {
                throw error
            }

            attempt += 1
            retryFeedback = feedback
            continue
        }
    }
}
```

### 重试次数定义

`maxDecodingFailureAutoRetryCount` 表示“失败后额外自动重试次数”，不是总调用次数。

示例：

```text
配置 = 1
最多调用：首次 + 1 次自动重试

配置 = 5
最多调用：首次 + 5 次自动重试
```

## 5. 解码失败判定

### 判定函数

新增公共判断：

```swift
enum MedicalExtractionFailureClassifier {
    static func isDecodingFailure(_ error: Error) -> Bool
}
```

判定为 true：

```swift
DecodingError
StructuredJSONDecodingFailure
ExtractionError.decodingFailed(context:)
```

判定为 false：

```swift
CancellationError
AIRuntimeError / network error
missing model / missing API key
upload failed
ocr failed
save failed
unknown non-decoding error
```

### 为什么要严格限制？

如果 AI 网关调用失败也把错误原因拼进 Prompt，会出现两个问题：

1. 下一次仍然可能因为网络/鉴权失败，不是 AI 能修复的问题。
2. Prompt 中混入“调用失败、限流、API key 缺失”等系统信息，没有业务价值，还可能污染模型输出。

所以：

```text
retry feedback 只服务于“AI 输出格式纠错”。
```

## 6. UI 交互详设

### 设置页

通用设置新增：

```text
医疗报告抽取

[开关] 抽取失败自动重试
说明：开启后，仅当 AI 输出格式不符合要求时，系统会自动携带失败原因重新抽取。

自动重试次数
[Stepper / Picker] 1...5
说明：达到次数后仍失败，将停留在失败页，可手动继续识别。
```

当开关关闭时：

```text
自动重试次数控件置灰或隐藏。
```

### 识别进度页

自动重试发生时，`extract` 步骤摘要可以显示：

```text
重新抽取 · 第 1/3 次 · 已携带上次失败原因
```

如果最终失败：

```text
识别结果格式仍不符合要求，已达到自动重试次数。你可以手动继续识别或从头重来。
```

### 手动继续识别保留

即使自动重试开启，也保留“继续识别”按钮。原因：

1. 自动重试次数用尽后，用户仍可手动再试。
2. 设置关闭时，仍然需要手动继续识别能力。
3. 用户可能调整识别类型或模型后继续。

手动继续识别仍沿用 `MEDICAL-AI-OCR-000001` 的 retry feedback 机制。

## 7. 状态设计

### ViewModel 状态

建议新增：

```swift
@Published private(set) var autoRetryAttempt = 0
@Published private(set) var maxAutoRetryAttempts = 0
@Published private(set) var isAutoRetryingExtraction = false
```

或封装：

```swift
struct MedicalExtractionAutoRetryState: Equatable, Sendable {
    var isEnabled: Bool
    var currentAttempt: Int
    var maxAttempts: Int
    var isRunning: Bool
}
```

清理规则：

| 场景 | 处理 |
| --- | --- |
| 新流程开始 | 重置自动重试计数 |
| 解码失败并自动重试 | `currentAttempt += 1` |
| 抽取成功 | 清空计数与 feedback |
| 非解码失败 | 停止自动重试，清空自动重试状态 |
| 用户取消 | 清空自动重试状态 |
| 切换文件/成员/类型 | 清空自动重试状态和 feedback |

## 8. 涉及文件与改动内容

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentUploadViewModel.swift` | 在 extract 阶段包一层自动重试循环；仅解码失败生成 feedback；增加自动重试状态 | 流程控制 |
| `SparkClient/Projects/Features/MedicalDocumentUpload/Domain/MedicalExtractionErrorNormalizer.swift` | 只接受解码失败类错误生成 feedback；非解码失败不生成或返回 nil | 错误边界 |
| 新增 `MedicalExtractionFailureClassifier.swift` | 判断错误是否属于解码失败 | 公共错误分类 |
| 新增 `MedicalExtractionRetrySettings.swift` | 本地配置模型，包含开关和次数 | 设置模型 |
| 新增 `MedicalExtractionRetrySettingsStore.swift` | UserDefaults 读写本地配置 | 本地持久化 |
| 通用设置页面 | 新增“医疗报告抽取”模块，包含开关和重试次数 | 用户配置入口 |
| `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | 新增设置项、说明、自动重试进度文案 | 本地化 |
| `SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | 新增英文文案 | 本地化 |

## 9. 与 `MEDICAL-AI-OCR-000001` 的关系

### 继承部分

`MEDICAL-AI-OCR-000002` 复用 000001 的能力：

1. `MedicalExtractionRetryFeedback`
2. `MedicalExtractionErrorNormalizer`
3. `MedicalPromptFactory` retry correction 拼接
4. `PromptLocalizer` 本地化模板
5. 手动继续识别能力

### 修正部分

000002 对 000001 增加更严格边界：

```text
000001：extract 失败后记录失败原因，手动继续时带入 Prompt
000002：只有解码失败才记录失败原因；开启配置后可自动带入失败原因重试
```

也就是说，000002 实现后，应避免以下行为：

1. AI 调用失败也记录 retry feedback。
2. 网络错误也带入 Prompt。
3. 用户取消也提示“将携带失败原因让 AI 修正”。
4. 所有 extract 错误都自动重试。

## 10. 验收标准

### 解码失败边界验收

1. `extra` 类型错误导致 `DecodingError.typeMismatch` 时，生成 retry feedback。
2. JSON 结构不是目标 array/object 时，生成 retry feedback。
3. AI 网关调用失败时，不生成 retry feedback。
4. API Key 缺失或模型不可用时，不生成 retry feedback。
5. 用户取消任务时，不生成 retry feedback。
6. OCR / 上传 / 保存失败时，不生成 retry feedback。

### 自动重试验收

1. 默认设置下，不自动重试，仍停留失败页并允许手动继续识别。
2. 开启自动重试且次数为 1 时，首次解码失败后自动重试 1 次。
3. 开启自动重试且次数为 5 时，最多额外自动重试 5 次。
4. 每次自动重试的 Prompt 都包含上一次解码失败原因。
5. 自动重试成功后，进入结果确认页。
6. 自动重试达到上限后仍失败，进入失败页并保留手动继续识别按钮。
7. 自动重试过程中不重复 upload / OCR / type recognition。
8. 非解码失败不会触发自动重试。

### 设置验收

1. 通用设置内出现“医疗报告抽取”模块。
2. “抽取失败自动重试”默认关闭。
3. 开启后可配置次数。
4. 次数范围为 1...5。
5. 配置保存到本地，重启 App 后保持。
6. 不依赖服务端配置。

### UI 验收

1. 自动重试时 extract 步骤展示当前重试进度。
2. 自动重试失败达到上限后，用户能看到原因提示。
3. 手动继续识别按钮仍然存在。
4. 设置关闭时不展示自动重试进度。

## 11. 风险与注意事项

### 主要风险

1. 自动重试会增加模型调用成本，默认必须关闭。
2. 次数上限必须硬限制为 5，避免异常循环。
3. 只有解码失败才能重试，不能扩大到调用失败。
4. 自动重试期间要尊重用户取消。
5. 每次重试只带入最近一次失败原因，不累计拼接多次错误，避免 Prompt 膨胀。

### 后续扩展

1. 按文档类型配置不同重试次数。
2. 对部分安全字段做本地 normalizer 自动修复，减少重试调用。
3. 对不同模型统计解码失败率，用于模型选择策略。
4. 自动重试失败后建议切换更强模型。

## 工单 `MEDICAL-AI-OCR-000003`：提交前本地预校验与字段高亮纠错

### 工单状态

已实现。

## 1. 背景与问题

AI 识别结果进入结果确认页后，用户点击“提交”时，当前流程会直接调用保存接口。由于 AI 抽取结果可能存在字段缺失、日期格式不完整、枚举值不合法等问题，后端可能返回 400。

典型问题：

```text
symptom.started_at = "2025-06"
服务端要求完整日期或 DateTime，导致保存失败。
```

```text
examination_reports[1].item_name = ""
服务端要求报告名称必填，导致保存失败。
```

本工单不改服务端接口、不新增服务端字段错误协议、不依赖服务端返回字段定位。目标是在点击提交按钮后、真正上送服务器前，客户端参考服务端存储规则做一次本地预校验：

1. 如果本地预校验通过，继续走现有提交接口流程。
2. 如果本地预校验失败，不发起网络请求。
3. 结果页保留当前识别和编辑状态。
4. 将不符合要求的字段在对应模块和字段位置高亮展示。
5. 顶部提示用户修复错误后再提交。

## 2. 设计目标

### 核心目标

在 `saveResult()` 触发保存前增加本地预校验层，按服务端约束检查当前识别草稿。校验失败时生成客户端本地 `MedicalPreSubmitValidationIssue`，写入 ViewModel 状态，结果页按 issue 高亮对应模块和字段；校验成功时再执行原有保存逻辑。

### 第一期目标

1. 点击提交后先执行本地预校验。
2. 本地预校验失败时不调用服务端保存接口。
3. 本地预校验错误展示在结果页顶部摘要。
4. 对应模块卡片展示错误角标或红色提示。
5. 对应字段行展示错误原因。
6. 用户可自行点击卡片或编辑按钮进入对应编辑页修改。
7. 用户修改字段后，本地错误可即时清除或下次提交重新计算。
8. 预校验通过后，保存接口流程保持不变。
9. 保存成功后清空本地预校验错误。

### 非目标

1. 不新增服务端字段错误协议。
2. 不解析服务端 400 字段错误来驱动 UI 高亮。
3. 不改变现有保存接口、请求 payload、响应结构。
4. 不让 AI 自动修复保存字段错误。
5. 不在本工单内覆盖所有后端复杂业务规则，只覆盖客户端可稳定判断的规则。

## 3. 总体流程

现有流程：

```text
用户点击提交
  -> viewModel.updateTypedResult(...)
  -> viewModel.saveResult()
  -> saveUseCase.execute(output:)
  -> 请求服务端保存接口
```

调整后：

```text
用户点击提交
  -> viewModel.updateTypedResult(...)
  -> viewModel.saveResult()
      -> MedicalPreSubmitValidator.validate(output:)
          -> 有错误：写入 preSubmitValidationIssues，fail(.save)，不请求服务端
          -> 无错误：清空 preSubmitValidationIssues，继续 saveUseCase.execute(output:)
  -> 请求服务端保存接口
```

关键点：

1. 预校验只拦截客户端能明确判断的问题。
2. 预校验不代替服务端校验，服务端仍是最终数据边界。
3. 预校验失败不清空 `typedOutput`、不重置页面、不丢失用户编辑内容。
4. 预校验通过后的保存接口流程不变。

## 4. 客户端错误模型

新增本地预校验错误模型：

```swift
struct MedicalPreSubmitValidationIssue: Identifiable, Equatable, Sendable {
    let id: UUID
    let resourceType: MedicalPreSubmitValidationResourceType
    let fieldPath: String
    let fieldKey: String
    let fieldLabel: String
    let message: String
    let severity: MedicalPreSubmitValidationSeverity
    let sectionTitle: String
    let cardIndex: Int?
}
```

资源类型：

```swift
enum MedicalPreSubmitValidationResourceType: String, Sendable {
    case caseDocument
    case symptom
    case visit
    case surgery
    case followUp
    case healthExamReport
    case examinationReport
    case prescription
    case medicationPlan
    case medicineBox
}
```

错误级别：

```swift
enum MedicalPreSubmitValidationSeverity: Sendable {
    case blocking
    case warning
}
```

第一期只使用 `blocking`。只有阻断错误会阻止提交。`warning` 可留给后续非必填但可疑字段提醒。

ViewModel 增加状态：

```swift
@Published private(set) var preSubmitValidationIssues: [MedicalPreSubmitValidationIssue] = []
```

## 5. 预校验器设计

新增：

```text
MedicalPreSubmitValidator
```

职责：

1. 接收当前 `MedicalDocumentTypedExtractionOutput`。
2. 根据 `typedResult` 分发到不同类型校验。
3. 生成本地字段错误列表。
4. 不做网络请求，不依赖服务端响应。
5. 不修改原始草稿数据，只返回错误。

建议协议：

```swift
protocol MedicalPreSubmitValidating: Sendable {
    func validate(output: MedicalDocumentTypedExtractionOutput) -> [MedicalPreSubmitValidationIssue]
}
```

分类型内部方法：

```swift
validateCaseDocument(_ draft: CaseRecognitionDraft) -> [MedicalPreSubmitValidationIssue]
validateHealthExamReports(_ drafts: [HealthExamRecognitionDraft]) -> [MedicalPreSubmitValidationIssue]
validateMedicalReports(_ drafts: [MedicalReportRecognitionDraft]) -> [MedicalPreSubmitValidationIssue]
validateMedication(_ drafts: [MedicationRecognitionDraft]) -> [MedicalPreSubmitValidationIssue]
validateMedicineBoxes(_ drafts: [MedicineBoxRecognitionDraft]) -> [MedicalPreSubmitValidationIssue]
```

## 6. 第一期校验规则

规则来源：参考服务端存储要求和当前保存接口常见失败，不追求一次性覆盖所有规则。

### 通用规则

| 规则 | 说明 | 错误提示 |
| --- | --- | --- |
| 必填字符串不能为空 | 去除空格和换行后为空视为错误 | 请填写{字段名} |
| 日期必须完整 | 不接受 `2025-06`、`2025` 等不完整日期 | 请选择完整日期 |
| 数组内必填项逐条检查 | 多个报告、多个药品、多个指标分别生成错误 | 第 n 项的{字段名}不能为空 |
| 枚举值必须在客户端可选范围内 | 如报告分类、用药状态、频次类型 | 请选择有效的{字段名} |
| 数值字段不能写入明显非法文本 | 年龄、数量等字段不能为负数或非数字 | 请填写有效数字 |

### 病例文档

文件：

```text
CaseRecognitionResultContentView.swift
```

校验对象：

```text
CaseRecognitionDraft
```

规则：

| 字段路径 | 模块 | 规则 |
| --- | --- | --- |
| `medical_case.title` | 病史与诊断 | 不能为空 |
| `medical_case.occurred_at` | 病史与诊断 | 如果有值，必须是完整日期 |
| `medical_case.age_at_visit` | 病史与诊断 | 如果有值，必须大于等于 0 |
| `symptom.name` | 症状 | 症状存在时不能为空 |
| `symptom.started_at` | 症状 | 如果有值，必须是完整日期 |
| `visit.visited_at` | 就诊 | 如果有值，必须是完整日期 |
| `visit.department` | 就诊 | 就诊记录存在时建议不能为空，第一期可先不阻断 |
| `examination_reports[n].item_name` | 检查报告 | 每份报告名称不能为空 |
| `examination_reports[n].performed_at` | 检查报告 | 如果有值，必须是完整日期 |
| `prescriptions[n].medication_plans[m].drug_name` | 用药 | 药品名称不能为空 |
| `prescriptions[n].medication_plans[m].start_date` | 用药 | 如果有值，必须是完整日期 |

### 体检报告

文件：

```text
HealthExamRecognitionResultContentView.swift
```

规则：

| 字段路径 | 模块 | 规则 |
| --- | --- | --- |
| `health_exam_reports[n].title` | 体检报告 | 报告标题不能为空 |
| `health_exam_reports[n].exam_date` | 体检报告 | 如果有值，必须是完整日期 |
| `health_exam_reports[n].items[m].item_name` | 体检指标 | 指标名称不能为空 |
| `health_exam_reports[n].items[m].result_value` | 体检指标 | 指标结果不能为空 |

### 医疗报告

文件：

```text
MedicalReportRecognitionResultContentView.swift
```

规则：

| 字段路径 | 模块 | 规则 |
| --- | --- | --- |
| `examination_reports[n].item_name` | 检查报告 | 报告名称不能为空 |
| `examination_reports[n].performed_at` | 检查报告 | 如果有值，必须是完整日期 |
| `examination_reports[n].category` | 检查报告 | 如果有值，必须在可选分类内 |
| `examination_reports[n].details[m].item_name` | 报告明细 | 如果明细存在，项目名不能为空 |
| `examination_reports[n].details[m].result_value` | 报告明细 | 如果明细存在，结果值不能为空 |

### 处方 / 用药计划

文件：

```text
MedicationRecognitionResultContentView.swift
```

规则：

| 字段路径 | 模块 | 规则 |
| --- | --- | --- |
| `prescriptions[n].prescribed_at` | 处方 | 如果有值，必须是完整日期 |
| `prescriptions[n].medication_plans[m].drug_name` | 药品 | 药品名称不能为空 |
| `prescriptions[n].medication_plans[m].start_date` | 药品 | 如果有值，必须是完整日期 |
| `prescriptions[n].medication_plans[m].dose_per_time` | 药品 | 如果填写了单位，剂量建议不能为空，第一期可阻断 |
| `prescriptions[n].medication_plans[m].frequency_type` | 药品 | 必须是客户端支持的频次类型 |

### 药箱

文件：

```text
MedicineBoxRecognitionResultView.swift
```

规则：

| 字段路径 | 模块 | 规则 |
| --- | --- | --- |
| `medicine_boxes[n].medicine_name` | 药箱 | 药品名称不能为空 |
| `medicine_boxes[n].expire_date` | 药箱 | 如果有值，必须是完整日期 |
| `medicine_boxes[n].total_quantity` | 药箱 | 如果有值，不能为负数 |

## 7. 日期与格式规则

### 日期完整性

客户端应统一使用本地工具判断“完整日期”，不要在各页面写正则。

建议新增：

```text
MedicalPreSubmitValidationRules
```

规则：

1. `yyyy-MM-dd` 视为完整日期。
2. ISO8601 DateTime 视为完整日期。
3. `yyyy-MM`、`yyyy`、空字符串不视为完整日期。
4. 空值是否允许由字段规则决定。

示例：

| 输入 | 结果 |
| --- | --- |
| `2025-06-21` | 通过 |
| `2025-06-21T00:00:00Z` | 通过 |
| `2025-06` | 不通过 |
| `2025` | 不通过 |
| `` | 由字段必填规则决定 |

## 8. 结果页 UI 设计

### 顶部错误摘要

在所有识别结果页顶部增加统一错误摘要组件：

```text
MedicalPreSubmitValidationSummaryBanner
```

展示内容：

```text
有 2 处内容需要修改后再提交
请检查下方红色标记的字段。修改完成后再次提交。

1. 症状开始时间：请选择完整日期
2. 第 2 份检查报告 - 报告名称：请填写报告名称
```

交互：

1. 点击某条错误，滚动到对应卡片或模块。
2. 不自动打开编辑页。
3. 用户通过结果页已有卡片点击、编辑按钮或编辑入口自行进入对应编辑页。

### 卡片高亮

对应卡片增加错误态：

1. 卡片边框使用 `Color.red.opacity(0.45)`。
2. 卡片标题右侧显示“需修改”角标。
3. 字段行下方展示具体错误文案。
4. 编辑按钮文案保持原有。

示例：

```text
检查报告 #2                         需修改
报告名称：未填写
  请填写报告名称
检查日期：2026-02-10
机构：苏州大学附属第四医院
```

### 字段行高亮

建议抽象公共字段错误渲染：

```text
MedicalValidationIssueInlineView
MedicalValidationIssueBadge
```

字段行渲染规则：

1. 当前字段有错误：字段下方展示红色错误说明。
2. 当前字段缺失：值展示“未填写”。
3. 当前字段格式错误：保留原始值，并提示正确格式。

### 编辑页内错误提示

用户自行打开对应编辑页后，编辑表单也接收本地预校验错误：

```swift
validationIssues: [MedicalPreSubmitValidationIssue]
```

编辑页表现：

1. 对应输入框边框高亮。
2. 输入框下方展示错误说明。
3. 用户修改该字段后，本地可清除该字段错误。
4. 再次提交时重新执行全量本地预校验。

## 9. 各结果页接入方案

### 路由层

`MedicalDocumentResultRouterView.swift`

职责不变，仍按类型路由：

```text
caseDocument -> CaseRecognitionResultView
healthExamReport -> HealthExamRecognitionResultView
medicalReport -> MedicalReportRecognitionResultView
prescription -> PrescriptionRecognitionResultView
medicationPlan -> MedicationRecognitionResultView
medicineBoxes -> MedicineBoxRecognitionResultView
```

各结果页统一从 `viewModel.preSubmitValidationIssues` 读取错误状态。

### 病例结果页

文件：

```text
CaseRecognitionResultContentView.swift
```

接入点：

1. 顶部展示 `MedicalPreSubmitValidationSummaryBanner`。
2. `CaseHistoryDiagnosisSectionView` 支持接收病例、症状、就诊、手术相关 issues。
3. `MedicalReportCardsSectionView` 支持接收 `examination_reports[n]` issues。
4. `CaseTreatmentPlanSectionView` 支持接收处方、药品、随访相关 issues。
5. 用户编辑后刷新草稿，并清理已修改字段相关 issue 或等待下次提交重新计算。

### 体检结果页

文件：

```text
HealthExamRecognitionResultContentView.swift
```

接入点：

1. 顶部展示本地预校验错误摘要。
2. 报告卡片高亮报告标题、体检日期等错误。
3. 指标列表高亮指标名称、结果值等错误。

### 医疗报告结果页

文件：

```text
MedicalReportRecognitionResultContentView.swift
```

接入点：

1. 顶部展示本地预校验错误摘要。
2. `MedicalReportCardsSectionView` 支持报告级和明细级错误。
3. 多份报告时按 `cardIndex` 高亮对应报告。

### 用药结果页

文件：

```text
MedicationRecognitionResultContentView.swift
```

接入点：

1. 顶部展示本地预校验错误摘要。
2. 处方卡片高亮开方日期等错误。
3. 药品卡片高亮药品名称、开始日期、剂量、频次等错误。

### 药箱结果页

文件：

```text
MedicineBoxRecognitionResultView.swift
```

接入点：

1. 顶部展示本地预校验错误摘要。
2. 药箱卡片高亮药品名称、有效期、数量等错误。

## 10. ViewModel 接入

`MedicalDocumentUploadViewModel.saveResult()` 调整：

```text
saveResult()
  -> guard typedOutput != nil
  -> let issues = preSubmitValidator.validate(output)
  -> if issues contains blocking:
         preSubmitValidationIssues = issues
         fail(.save)
         errorMessage = "有内容需要修改后再提交"
         return false
  -> preSubmitValidationIssues = []
  -> continue saveUseCase.execute(output:)
```

注意：

1. `viewModel.updateTypedResult(...)` 必须在预校验前执行，确保校验的是用户最新编辑后的草稿。
2. 预校验失败不进入 `DefaultTypedMedicalDocumentSaver`。
3. 预校验失败不影响 upload / ocr / extract 的完成状态。
4. 预校验失败后保存按钮仍可再次点击。

## 11. 涉及文件

| 文件 | 改动 |
| --- | --- |
| `MedicalDocumentUploadViewModel.swift` | 增加 `preSubmitValidationIssues`，保存前执行本地预校验 |
| `MedicalDocumentResultRouterView.swift` | 路由不变，结果页通过 ViewModel 读取本地预校验错误 |
| `CaseRecognitionResultContentView.swift` | 顶部错误摘要、病历/症状/就诊/报告/用药模块字段高亮 |
| `HealthExamRecognitionResultContentView.swift` | 顶部错误摘要、体检报告和指标行高亮 |
| `MedicalReportRecognitionResultContentView.swift` | 顶部错误摘要、报告卡片和明细高亮 |
| `MedicationRecognitionResultContentView.swift` | 顶部错误摘要、处方/药品卡片高亮 |
| `MedicineBoxRecognitionResultView.swift` | 顶部错误摘要、药箱卡片高亮 |
| 新增 `MedicalPreSubmitValidationIssue.swift` | 本地预校验错误模型 |
| 新增 `MedicalPreSubmitValidator.swift` | 提交前本地预校验器 |
| 新增 `MedicalPreSubmitValidationRules.swift` | 必填、日期、数值、枚举等公共规则 |
| 新增 `MedicalPreSubmitValidationSummaryBanner.swift` | 顶部错误摘要组件 |
| 新增 `MedicalValidationIssueInlineView.swift` | 字段行错误展示组件 |
| `Localizable.strings` | 字段名、模块名、错误提示本地化 |

## 12. 验收标准

### 流程验收

1. 点击提交后先执行本地预校验。
2. 本地预校验失败时，不发起保存接口请求。
3. 本地预校验通过时，继续走原有保存接口流程。
4. 保存接口请求 payload 和接口路径不因本工单变化。
5. 预校验失败后不离开结果页、不清空草稿。
6. 保存成功后清空本地预校验错误。

### UI 验收

1. 顶部展示“有内容需要修改后再提交”摘要。
2. 对应卡片高亮展示。
3. 对应字段展示错误文案。
4. 点击错误项只定位到对应模块或卡片，不直接打开编辑页。
5. 用户修改字段后可重新提交。

### 典型错误验收

1. `symptom.started_at = "2025-06"` 时，提交前拦截，症状模块高亮。
2. `examination_reports[1].item_name` 为空时，提交前拦截，第 2 张检查报告高亮。
3. 药品名称为空时，提交前拦截，对应药品卡片高亮。
4. 药箱药品名称为空时，提交前拦截，对应药箱卡片高亮。
5. 所有阻断错误修复后，再次提交会发起服务端保存请求。

## 13. 风险与注意事项

1. 客户端预校验不能替代服务端校验，服务端仍需保持最终校验。
2. 不要把所有后端规则都搬到客户端，第一期只做稳定、明确、可本地判断的规则。
3. 不要在每个 View 内散落规则，规则必须集中在 `MedicalPreSubmitValidator` / `MedicalPreSubmitValidationRules`。
4. 不要把技术字段直接展示给用户，字段名和错误文案必须本地化。
5. 不要预校验失败后重置 `typedOutput`，否则用户会丢失已编辑内容。
6. 日期规则要和保存 payload 的实际格式保持一致，避免客户端误拦截。

## 14. 后续扩展

1. 对日期格式错误提供“一键补全为当天”或日期选择器快捷入口。
2. 将服务端仍然返回的 400 统计为规则缺口，后续补充本地预校验。
3. 增加 warning 级别，对可疑但不阻断的字段做黄色提醒。
4. 将校验规则与表单组件进一步绑定，做到编辑中实时提示。

## 工单 `MEDICAL-AI-OCR-000004`：折叠模块内预校验错误自动展开并定位

### 工单状态

已实现。

## 1. 背景与问题

`MEDICAL-AI-OCR-000003` 已要求点击提交前执行本地预校验，并在错误字段所在模块和字段位置高亮。但识别结果页存在大量折叠模块，例如：

1. 病例结果页的病史/症状/就诊/检查报告/用药方案折叠区。
2. 体检结果页按分类折叠的指标列表。
3. 处方/用药结果页的处方批次、药品列表。
4. 药箱结果页的药品列表或分组。

如果错误字段位于折叠区块内，用户点击“提交”后只看到顶部错误摘要，但对应卡片仍被折叠隐藏，会造成两个问题：

1. 页面无法滚动到被折叠隐藏的字段。
2. 用户不知道需要先展开哪个模块才能看到红色错误。

因此需要在预校验失败后，客户端根据错误字段所在位置，自动展开对应折叠模块，再滚动到对应卡片或字段。

## 2. 设计目标

### 核心目标

当用户点击提交且本地预校验失败时，如果错误字段位于折叠模块内部，结果页应先展开包含该错误的模块，再滚动定位到对应卡片或字段，并展示高亮错误。

### 第一期目标

1. 提交失败后，自动处理第一条阻断错误的定位。
2. 如果第一条错误位于折叠模块内，先展开对应模块。
3. 展开完成后再滚动到对应卡片或字段。
4. 顶部错误摘要内点击任意错误，也执行同样的“展开 -> 滚动”流程。
5. 不直接打开编辑页，仍由用户自行点击卡片或编辑按钮进入编辑。
6. 不改变 `MEDICAL-AI-OCR-000003` 的保存前本地预校验逻辑。

### 非目标

1. 不改变保存接口流程。
2. 不解析服务端字段错误。
3. 不要求一次性展开所有错误模块，第一期优先定位用户当前点击或第一条错误。
4. 不自动进入编辑页。

## 3. 交互流程

### 点击提交后预校验失败

```text
用户点击提交
  -> updateTypedResult(...)
  -> saveResult()
  -> MedicalPreSubmitValidator.validate(output)
  -> 返回 blocking issues
  -> ViewModel 写入 preSubmitValidationIssues
  -> 结果页收到 issues
  -> 取第一条 blocking issue
  -> 根据 issue.resourceType / fieldPath / cardIndex 找到折叠模块
  -> 展开该模块
  -> 等待布局刷新
  -> 滚动到 issue.scrollTargetID
  -> 展示字段高亮
```

### 点击错误摘要

```text
用户点击顶部错误摘要中的某一条
  -> 根据该 issue 找到折叠模块
  -> 展开对应模块
  -> 滚动到对应卡片或字段
  -> 用户自行点击编辑入口修改
```

## 4. 数据设计

`MedicalPreSubmitValidationIssue` 需要支持定位折叠区块：

```swift
struct MedicalPreSubmitValidationIssue {
    let resourceType: MedicalPreSubmitValidationResourceType
    let fieldPath: String
    let fieldKey: String
    let cardIndex: Int?

    var scrollTargetID: String { ... }
    var collapseSectionID: String? { ... }
}
```

### `collapseSectionID`

用于描述错误字段所在的可折叠模块：

```swift
enum MedicalPreSubmitValidationSectionID {
    static let caseHistory = "preSubmitValidation.section.caseHistory"
    static let examinationReports = "preSubmitValidation.section.examinationReports"
    static let treatmentPlan = "preSubmitValidation.section.treatmentPlan"
    static let medicationList = "preSubmitValidation.section.medicationList"
    static let medicineBoxList = "preSubmitValidation.section.medicineBoxList"
    static let healthExamGroups = "preSubmitValidation.section.healthExamGroups"
}
```

映射示例：

| 错误字段 | 需要展开的模块 |
| --- | --- |
| `symptom.started_at` | `caseHistory` |
| `visit.visited_at` | `caseHistory` |
| `examination_reports[n].item_name` | `examinationReports` |
| `prescriptions[n].medication_plans[m].drug_name` | `treatmentPlan` |
| `medication_plans[n].drug_name` | `medicationList` |
| `medicine_boxes[n].medicine_name` | `medicineBoxList` |
| `health_exam.items[n].item_name` | `healthExamGroups` |

## 5. 页面状态设计

各结果页维护本地展开状态：

```swift
@State private var expandedValidationSections: Set<String> = []
```

体检结果页还需要维护指标分类展开状态：

```swift
@State private var expandedCategories: Set<String> = []
```

当需要定位 issue 时：

1. 先将 `issue.collapseSectionID` 插入 `expandedValidationSections`。
2. 如果是体检指标错误，根据指标 index 找到分类名称，并插入 `expandedCategories`。
3. 等待下一轮布局刷新后执行 `scrollProxy.scrollTo(issue.scrollTargetID, anchor: .top)`。

## 6. 公共定位工具

建议新增公共工具：

```text
MedicalPreSubmitValidationNavigation.swift
```

职责：

1. 根据 issue 计算需要展开的折叠模块。
2. 根据体检指标 index 计算需要展开的分类。
3. 统一执行“展开 -> 延迟 -> 滚动”。

示例：

```swift
@MainActor
static func reveal(
    issue: MedicalPreSubmitValidationIssue,
    expandedSectionIDs: inout Set<String>,
    expandedHealthExamCategories: inout Set<String>,
    healthExamCategoryForItemIndex: ((Int) -> String?)?,
    scrollProxy: ScrollViewProxy
)
```

## 7. 各结果页接入要求

### 病例结果页

文件：

```text
CaseRecognitionResultContentView.swift
CaseHistoryDiagnosisSectionView.swift
CaseTreatmentPlanSectionView.swift
MedicalReportResultSections.swift
```

要求：

1. 病史/症状/就诊折叠时，症状或就诊错误应先展开病史模块。
2. 检查报告列表折叠时，报告名称、日期、明细错误应先展开检查报告模块。
3. 用药方案折叠时，药品名称、开始日期、剂量、频次错误应先展开治疗方案模块。
4. 滚动 ID 必须能唯一定位到具体卡片，不能只定位到整个列表。

### 体检结果页

文件：

```text
HealthExamRecognitionResultContentView.swift
HealthExamResultSections.swift
```

要求：

1. 基础信息错误定位到基础信息卡。
2. 指标错误必须先展开对应指标分类。
3. 分类展开后再滚动到对应指标行。
4. `cardIndex` 或定位 ID 需要区分“基础信息卡”和“第 1 个指标”，避免二者都使用同一个定位。

### 医疗报告结果页

文件：

```text
MedicalReportRecognitionResultContentView.swift
MedicalReportResultSections.swift
```

要求：

1. 报告列表折叠时，先展开报告列表。
2. 多份报告时滚动到对应报告卡片。
3. 报告明细错误可以先定位到报告卡片，第一期不要求滚到明细行。

### 处方 / 用药结果页

文件：

```text
PrescriptionRecognitionResultContentView.swift
MedicationRecognitionResultContentView.swift
PrescriptionResultSections.swift
MedicationResultSections.swift
```

要求：

1. 多处方、多药品时，定位 ID 必须包含处方 index 和药品 index。
2. 不允许多个处方下的第 1 个药品共用同一个滚动 ID。
3. 批次折叠时先展开批次，再定位到药品卡。

### 药箱结果页

文件：

```text
MedicineBoxRecognitionResultView.swift
```

要求：

1. 药品列表折叠时先展开药品列表。
2. 多个药品时滚动到对应药品卡。
3. 不自动打开药品编辑页。

## 8. 自动定位触发时机

### 提交失败后自动定位

预校验失败后，应自动定位第一条阻断错误：

```text
preSubmitValidationIssues 从空变为非空
  -> 取 blockingIssues.first
  -> reveal(issue)
```

注意：

1. 避免每次 View 刷新都重复滚动。
2. 可记录最近一次自动定位的 issue id 或 validation revision。
3. 用户手动点击错误摘要时，不受自动定位去重限制。

### 点击摘要定位

顶部摘要点击某条错误时，始终执行定位流程：

```text
点击 issue
  -> reveal(issue)
```

## 9. 验收标准

### 通用验收

1. 错误字段在折叠模块内时，提交失败后模块会自动展开。
2. 模块展开后页面滚动到对应卡片或字段。
3. 顶部错误摘要点击任意错误，也能展开并定位。
4. 不自动打开编辑页。
5. 用户修复后重新提交，错误消失。

### 典型场景

1. 病例页症状模块折叠，`symptom.started_at = "2025-06"`，点击提交后展开病史/症状模块并滚动到症状卡。
2. 病例页检查报告列表折叠，第 2 份报告名称为空，点击提交后展开检查报告列表并滚动到第 2 份报告。
3. 体检页指标分类折叠，第 3 个指标名称为空，点击提交后展开对应分类并滚动到该指标。
4. 多处方场景下，第 2 张处方第 1 个药品名称为空，点击提交后滚动到第 2 张处方下的第 1 个药品，而不是第 1 张处方下的第 1 个药品。
5. 药箱列表折叠，第 2 个药品名称为空，点击提交后展开药箱列表并滚动到第 2 个药品。

## 10. 风险与注意事项

1. 展开和滚动之间必须有布局刷新间隔，否则 `scrollTo` 可能找不到目标。
2. 滚动 ID 必须全局唯一，尤其是多处方、多药品、多报告场景。
3. 不要把展开状态写入持久化，只作为结果页本地 UI 状态。
4. 不要为定位逻辑引入服务端字段协议，本工单仍然完全基于本地预校验 issue。
5. 如果无法定位具体字段，至少展开对应模块并滚动到模块顶部。

## 工单 `MEDICAL-AI-OCR-000005`：缺少识别场景模型时引导配置模型密钥

### 工单状态

已实现。

## 1. 背景与问题

AI 识别报告流程依赖不同 `AIScenario` 的可用模型，例如 OCR 后的类型识别、药盒抽取、病例抽取、体检报告抽取、医疗报告抽取等。当对应场景没有可用模型时，底层会抛出：

```swift
case .missingModelForScenario(let scenario):
    return "场景「\(scenario.rawValue)」暂无可用的 AI 模型"
```

如果只展示这类技术错误，用户不知道下一步应该做什么。医疗识别场景下应像对话列表/会话页一样，引导用户去配置模型、Base URL 和 API Key。

参考现有对话模块：

```text
ChatConversationListPage.swift:77-84
ChatConversationListPage.swift:85-97
ChatView.swift:402-408
```

## 2. 设计目标

### 核心目标

当医疗 AI 识别流程遇到 `AIConfigError.missingModelForScenario` 时，不只展示错误文案，而是弹窗询问用户是否前往设置。用户选择“前往设置”后，通过 sheet 打开模型密钥页面 `APIKeysSettingsView`。

### 第一期目标

1. 捕获 `AIConfigError.missingModelForScenario`。
2. 弹窗提示用户需要配置模型。
3. 弹窗提供“取消”和“前往设置”两个操作。
4. 点击“前往设置”后，以 sheet 形式打开 `APIKeysSettingsView`。
5. sheet 内使用 `NavigationView` 包装，并提供“完成”按钮关闭。
6. 不自动重试识别，用户配置完成后自行重新开始或继续当前流程。

### 非目标

1. 不在本工单内实现临时配置页。
2. 不改变 AI 模型选择策略。
3. 不自动创建模型配置。
4. 不绕过 `AIConfigCenter` / `AISettingsViewModel` 现有配置链路。

## 3. 弹窗文案

### 标题

```text
暂无可用的 AI 模型
```

### 内容

```text
请前往设置配置 Base URL、模型和 API Key，以开始识别。
```

说明：

1. 文案需要贴合医疗识别场景，使用“开始识别”。
2. 当前复用 `APIKeysSettingsView`，配置行为与系统 AI 设置保持一致。

### 按钮

| 按钮 | 行为 |
| --- | --- |
| 取消 | 关闭弹窗，停留当前页面 |
| 前往设置 | 关闭弹窗并打开模型密钥 sheet |

## 4. 页面状态设计

医疗文档上传 Host 或 ViewModel 对应页面增加状态：

```swift
@State private var showMissingModelAlert = false
@State private var showAPIKeysSettingsSheet = false
@State private var missingModelScenario: AIScenario?
```

如果状态放在 ViewModel：

```swift
@Published var missingModelScenarioForAlert: AIScenario?
```

推荐：

1. 错误识别和场景记录放在 `MedicalDocumentUploadViewModel`。
2. alert / sheet 展示状态放在 SwiftUI View。
3. View 观察 ViewModel 的缺模型事件后触发 alert。

## 5. 错误识别流程

### 捕获位置

候选位置：

```text
MedicalDocumentUploadViewModel.swift
localizedRecognitionErrorMessage(for:failedStep:)
runTypedRecognition / extract / type_recognition 错误 catch 分支
```

处理原则：

1. 只对 `AIConfigError.missingModelForScenario` 触发配置引导。
2. 其他错误继续走现有 `errorMessage` 展示。
3. 不把所有 AI 错误都引导去设置。
4. 如果错误被包装，需要递归或归一化识别 root error。

伪流程：

```text
catch error
  -> if error is missingModelForScenario:
       missingModelScenarioForAlert = scenario
       errorMessage = nil 或短提示
       fail(currentStep)
     else:
       errorMessage = localizedRecognitionErrorMessage(...)
```

## 6. Sheet 打开方式

参考 `ChatConversationListPage`：

```swift
.alert(title, isPresented: $showMissingModelAlert) {
    Button("前往设置") {
        showAPIKeysSettingsSheet = true
    }
    Button("取消", role: .cancel) {}
} message: {
    Text("请前往设置配置 Base URL、模型和 API Key，以开始识别。")
}
.sheet(isPresented: $showAPIKeysSettingsSheet) {
    NavigationView {
        APIKeysSettingsView(viewModel: aiSettingsViewModel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        showAPIKeysSettingsSheet = false
                    }
                }
            }
    }
}
```

注意：

1. 使用项目已有 `APIKeysSettingsView`。
2. 使用当前页面可获得的 `AISettingsViewModel`。
3. 不新增独立配置页。
4. 不在医疗识别模块重复实现密钥表单。

## 7. 涉及文件

| 文件 | 改动 |
| --- | --- |
| `MedicalDocumentUploadViewModel.swift` | 捕获/归一化 `missingModelForScenario`，暴露缺模型提示状态 |
| `MedicalDocumentUploadHostView.swift` | 挂载 alert 和 APIKeysSettingsView sheet |
| `MedicalDocumentUploadView.swift` 或入口页面 | 如 Host 无法拿到 `AISettingsViewModel`，在入口层注入 |
| `AIConfigModels.swift` | 不改错误定义，只复用 `AIConfigError.missingModelForScenario` |
| `APIKeysSettingsView.swift` | 不改页面，只复用 |
| `Localizable.strings` | 增加医疗识别缺模型标题、内容、按钮文案 |

## 8. 验收标准

1. 医疗 AI 识别任一步骤遇到 `missingModelForScenario` 时，弹出缺模型配置提示。
2. 弹窗展示文案：“请前往设置配置 Base URL、模型和 API Key，以开始识别。”
3. 点击“取消”后停留当前页面，不打开设置。
4. 点击“前往设置”后 sheet 打开 `APIKeysSettingsView`。
5. sheet 点击“完成”后关闭。
6. 其他错误不触发缺模型配置弹窗。
7. 配置完成后不自动重试识别，用户可自行重新触发识别。

## 9. 风险与注意事项

1. 不要把所有识别失败都归类为缺模型。
2. 如果错误被 use case 或 extractor 包装，需要保证仍能识别内部 `missingModelForScenario`。
3. 医疗上传页面需要能拿到与 AI 设置一致的 `AISettingsViewModel`，避免打开一个空配置上下文。
4. 避免 alert 和现有 `errorMessage` alert 同时弹出。
5. 文案需要与 `APIKeysSettingsView` 的持久化配置行为保持一致，避免提示成临时内存配置。

## 工单 `MEDICAL-AI-OCR-000006`：处方数组识别与用药资料草稿详情预览

### 工单状态

新需求/待实现。

## 1. 背景与问题

### 1.1 业务背景

处方识别不是天然“一张图片只对应一张处方”。真实场景中可能出现：

1. 一次上传多张处方图片。
2. 一张图片内包含多张处方或多组医嘱。
3. 处方和用药计划混排，例如上方是处方抬头，下方是多条药品及服用说明。
4. 用户需要在保存前进入处方、用药计划、药箱详情页预览和编辑识别结果。

当前处方抽取链路仍按单个 `PrescriptionRecognitionDraft` 处理：

```swift
case .prescription:
    let final = try await extractStructured(
        prompt: prompt,
        scenario: .prescriptionExtraction,
        kindLabel: "prescription",
        as: PrescriptionRecognitionDraft.self,
        preferredModelName: preferredModelName,
        cancellationToken: cancellationToken
    )
```

结果页也以单个 `batch` 管理：

```swift
@State private var batch: PrescriptionRecognitionDraft
```

这会带来几个问题：

1. AI 识别到多张处方时，只能落到一个处方对象，信息容易被合并或丢失。
2. 结果页无法天然表达“第 1 张处方 / 第 2 张处方 / 第 N 张处方”。
3. 进入处方详情页时，目前用负数 ID 临时构造远端模型，并传入空保存/删除回调，只能展示，不能形成完整草稿编辑闭环。
4. 用药计划详情页、药箱详情页进入后仍默认走服务端编辑/删除流程，不适合识别结果保存前的本地草稿。
5. 识别结果页缺少处方场景下的成员切换能力，和体检报告结果页体验不一致。

### 1.2 当前相关代码位置

| 文件 | 当前情况 | 主要问题 |
| --- | --- | --- |
| `DefaultTypedMedicalDocumentExtractor.swift:344-359` | 处方按 `PrescriptionRecognitionDraft.self` 解码 | 不支持多处方数组 |
| `Prompts.strings:333-437` | 处方 Prompt 要求输出恰好一个 JSON 对象 | 需要改为 JSON array |
| `PrescriptionRecognitionResultContentView.swift` | `@State private var batch` 单处方状态 | 页面状态无法承载多处方 |
| `PrescriptionResultSections.swift:350-386` | 用负数 ID 构造详情页预览数据 | 缺少正式草稿 Mode 与回调更新 |
| `MedicationPrescriptionDetailPage.swift` | 默认服务端详情/编辑/删除 | 需要支持本地草稿预览模式 |
| `MedicationPlanDetailPage.swift` | 默认服务端详情/编辑/删除 | 需要支持本地草稿预览模式 |
| `MedicineBoxDetailPage.swift` | 默认服务端详情/编辑/删除 | 需要支持本地草稿预览模式 |

## 2. 设计目标

### 2.1 核心目标

将处方识别从“单个处方草稿”升级为“处方草稿数组”，并让识别结果页中的处方、用药计划、药箱详情页都支持本地草稿预览模式。用户在保存到服务端前，可以像查看正式详情一样查看、编辑、删除识别出来的数据；所有修改只作用于识别结果页本地草稿，最终点击保存时再统一提交服务端。

### 2.2 第一期目标

1. 处方抽取结果改为 `[PrescriptionRecognitionDraft]`。
2. 处方 Prompt 明确要求输出 JSON array。
3. 识别全流程、类型结果、结果页展示、预校验、保存入参都适配处方数组。
4. 处方结果页支持切换成员，交互参考体检报告结果页。
5. 处方详情页支持 `Mode`，默认正常服务端模式；识别结果页进入时使用本地草稿预览模式。
6. 用药计划详情页支持 `Mode`，默认正常服务端模式；识别结果页进入时使用本地草稿预览模式。
7. 药箱详情页支持 `Mode`，默认正常服务端模式；识别结果页进入时使用本地草稿预览模式。
8. 草稿模式下编辑、删除都不调用服务端，只通过回调更新识别结果页的 `[PrescriptionRecognitionDraft]`。
9. 草稿模式下进入关联用药计划、关联药箱详情页时，继续沿用草稿模式。
10. 结果页内所有本地编辑后，保存提交使用最新草稿值。

### 2.3 非目标

1. 不改变正式详情页已保存数据的服务端编辑能力。
2. 不在详情页中直接提交识别结果。
3. 不为草稿数据新增本地数据库持久化。
4. 不要求服务端保存接口支持“局部草稿更新”。
5. 不在本工单重做全部用药模块 UI。

## 3. 数据模型详设

### 3.1 `MedicalDocumentTypedExtractionResult` 改造

当前处方分支如果是：

```swift
case prescription(PrescriptionRecognitionDraft)
```

需要改为：

```swift
case prescription([PrescriptionRecognitionDraft])
```

如果为了降低外部调用迁移成本，也可以新增语义更清晰的 case：

```swift
case prescriptions([PrescriptionRecognitionDraft])
```

推荐使用第一种：保持业务类型名不变，只改变承载值。原因是上传文档类型仍然是 `.prescription`，只是识别结果从单个改为多个。

### 3.2 处方数组归一化

处方抽取成功后需要统一归一化：

```swift
private static func normalizedPrescriptionDrafts(
    _ drafts: [PrescriptionRecognitionDraft]
) -> [PrescriptionRecognitionDraft]
```

归一化规则：

1. 空数组允许返回，但结果页展示空态并提示用户可手动补充。
2. 每个处方内 `medicationPlans` 为 `nil` 时归一化为 `[]`。
3. 每个处方保持独立的 `medicalCase`、`prescriberName`、`institutionName`、`prescribedAt`、`diagnosis`。
4. 每个处方内药品 `sortOrder` 如果缺失，按处方内顺序补齐。
5. 不跨处方合并药品，避免把不同处方的用药计划混到一起。

### 3.3 本地草稿详情 Mode

三个详情页都需要引入明确 Mode，区分“已保存远端数据”和“识别结果本地草稿”。

推荐定义：

```swift
enum MedicalResourceDetailMode: Equatable, Sendable {
    case server
    case localDraft
}
```

也可以为每个页面定义更强类型的 Mode：

```swift
enum MedicationPrescriptionDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum MedicationPlanDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum MedicineBoxDetailMode: Equatable, Sendable {
    case server
    case localDraft
}
```

推荐第一期使用各页面独立 Mode，避免一开始抽象过大。后续如果详情页草稿模式扩展到更多医疗资源，再归纳为公共 `MedicalResourceDetailMode`。

### 3.4 草稿回调模型

识别结果页需要知道更新的是哪一张处方、哪一个药品计划、哪一个药箱。建议以索引路径回传，不依赖临时负数 ID 作为唯一业务依据。

```swift
struct PrescriptionDraftIndexPath: Equatable, Sendable {
    let prescriptionIndex: Int
}

struct MedicationDraftIndexPath: Equatable, Sendable {
    let prescriptionIndex: Int
    let medicationIndex: Int
}
```

回调建议：

```swift
onPrescriptionDraftUpdated: (Int, PrescriptionRecognitionDraft) -> Void
onPrescriptionDraftDeleted: (Int) -> Void
onMedicationPlanDraftUpdated: (Int, Int, MedicationPlanRecognitionDraft) -> Void
onMedicationPlanDraftDeleted: (Int, Int) -> Void
onMedicineBoxDraftUpdated: (Int, Int, MedicineBoxRecognitionDraft) -> Void
onMedicineBoxDraftDeleted: (Int, Int) -> Void
```

说明：

1. 第一位 `Int` 是处方索引。
2. 第二位 `Int` 是处方内药品/计划索引。
3. 负数 ID 仍可用于 SwiftUI `NavigationLink` 和远端模型展示适配，但不能作为草稿状态更新的唯一依据。

## 4. 处方数组识别流程详设

### 4.1 Extractor 解码改造

`DefaultTypedMedicalDocumentExtractor.swift:344-359` 处方分支改为：

```swift
case .prescription:
    let final = try await extractStructured(
        prompt: prompt,
        scenario: .prescriptionExtraction,
        kindLabel: "prescription",
        as: [PrescriptionRecognitionDraft].self,
        preferredModelName: preferredModelName,
        cancellationToken: cancellationToken
    )
    guard let drafts = final.decoded else {
        throw Self.decodingFailedError(from: final, kindLabel: "prescription")
    }
    let normalized = Self.normalizedPrescriptionDrafts(drafts)
    return (
        .prescription(normalized),
        Self.normalizedExtractedJSON(for: .prescription(normalized), fallback: final.normalizedJSON)
    )
```

兼容策略：

1. 如果担心部分模型仍输出单对象，可在第一期引入兼容解码：先尝试 `[PrescriptionRecognitionDraft]`，失败且 JSON 是 object 时再尝试单对象并包装成数组。
2. 兼容解码只能作为过渡，Prompt 仍必须明确要求输出 array。
3. 解码失败自动重试时，需要提示“处方结果必须是 JSON array，即使只有一张处方也输出 `[{}]`”。

### 4.2 Prompt 改造

`Prompts.strings:333-437` 中处方抽取 Prompt 当前写法：

```text
严格按照我指定的 JSON 结构输出恰好一个 JSON 对象
```

需要改为：

```text
严格按照我指定的 JSON 结构输出一个 JSON 数组。数组中每个元素是一张处方对象。即使只识别到一张处方，也必须输出包含一个对象的数组。
```

输出结构从：

```json
{
  "prescriberName": "",
  "medicationPlans": []
}
```

改为：

```json
[
  {
    "prescriberName": "",
    "institutionName": "",
    "prescribedAt": "",
    "diagnosis": "",
    "prescriptionNo": "",
    "status": "",
    "extra": {},
    "medicationPlans": []
  }
]
```

Prompt 需要补充多处方规则：

1. 多张处方不要合并为一个对象。
2. 每张处方独立保留医生、机构、日期、诊断、处方号。
3. 无法判断某药品属于哪张处方时，放到最接近的处方对象内，并在 `extra` 中记录低置信度原因。
4. 只有一张处方也必须输出数组。
5. 没有识别到处方时输出 `[]`。

### 4.3 `normalizedExtractedJSON` 改造

处方保存前可能依赖 `extractedJSON` 或 `typedResult`。改造后需要保证：

1. `typedResult` 中是 `[PrescriptionRecognitionDraft]`。
2. `normalizedExtractedJSON` 中保存的也是数组 JSON。
3. 调试日志输出 preview 时避免过长，只展示前若干字符。

## 5. 结果页状态与 UI 详设

### 5.1 `PrescriptionRecognitionResultContentView` 状态改造

当前：

```swift
@State private var batch: PrescriptionRecognitionDraft
```

改为：

```swift
@State private var batches: [PrescriptionRecognitionDraft]
@State private var selectedMemberID: Int
```

初始化规则：

1. 如果 `output.typedResult` 是 `.prescription(let drafts)`，使用 `drafts`。
2. 如果数组为空，展示空处方结果态。
3. `selectedMemberID` 初始值来自 `output.envelope.memberID`。
4. 切换成员后，更新结果页本地成员 ID，并保证后续详情页草稿模型转换使用新成员 ID。

### 5.2 成员切换

处方结果页支持切换成员，交互参考体检报告结果页。

需求：

1. 成员确认区域展示当前成员头像/名称/关系。
2. 点击切换成员后打开成员选择 UI。
3. 切换成功后更新当前识别结果归属成员。
4. 切换成员后，处方详情、用药计划详情、药箱详情中的本地草稿远端适配模型都使用新 `memberID`。
5. 切换成员不清空处方识别结果。
6. 切换成员后重新执行提交前预校验，因为部分规则可能依赖成员归属或资源关联。

建议状态同步：

```text
用户切换成员
  -> PrescriptionRecognitionResultContentView.selectedMemberID 更新
  -> output envelope 的提交上下文使用 selectedMemberID
  -> detailNavigationContext.memberID 使用 selectedMemberID
  -> save 时把 selectedMemberID 作为最终 memberID
```

如果当前 `MedicalDocumentTypedExtractionOutput.envelope.memberID` 是不可变值，结果页不要直接修改 envelope；由保存方法显式接收 `memberIDOverride` 或由 ViewModel 提供 `updateSelectedMemberID`。

### 5.3 处方列表展示

`PrescriptionBatchListSectionView` 不再传 `[batch]`，直接传 `batches`。

UI 需要展示：

1. 处方序号：`处方 1 / N`。
2. 医院/机构名称。
3. 开方医生。
4. 开方日期。
5. 诊断。
6. 药品数量。
7. 附件关联状态。
8. 校验错误角标。

当 `batches.count > 1` 时，页面必须让用户清晰知道正在编辑第几张处方，避免把第二张处方误改到第一张。

### 5.4 空态

AI 返回 `[]` 时：

1. 展示“未识别到处方信息”。
2. 保留源文件附件区域。
3. 提供“手动新增处方草稿”入口。
4. 保存按钮置灰或提示必须至少有一张处方。

手动新增可以第一期延后，但文档要求预留状态，不要让空数组页面崩溃。

## 6. 处方详情页草稿预览模式

### 6.1 页面入口

识别结果页点击处方卡片进入：

```swift
MedicationPrescriptionDetailPage(
    mode: .localDraft,
    prescription: draft.remotePrescription(memberID: selectedMemberID, id: temporaryPrescriptionID),
    plans: draft.medicationPlans.remoteMedicationPlans(...),
    medicineBoxes: draft.medicationPlans.remoteMedicineBoxes(...),
    recordsByPlanID: [:],
    memberID: selectedMemberID,
    ...
    onLocalDraftPrescriptionSaved: { updatedDraft in ... },
    onLocalDraftPrescriptionDeleted: { ... },
    onLocalDraftMedicationPlanSaved: { medicationIndex, updatedDraft in ... },
    onLocalDraftMedicationPlanDeleted: { medicationIndex in ... }
)
```

默认正式场景仍然：

```swift
mode: .server
```

为了兼容现有调用，`mode` 参数默认值为 `.server`。

### 6.2 草稿模式行为

| 操作 | 服务端模式 | 草稿模式 |
| --- | --- | --- |
| 展示 | 展示远端数据 | 展示草稿适配数据 |
| 编辑处方 | 打开服务端编辑页，保存调用接口 | 打开本地编辑页，保存回调更新草稿 |
| 删除处方 | 调用服务端删除接口 | 本地删除当前处方草稿并返回结果页 |
| 解绑用药计划 | 调用服务端更新 | 本地从处方草稿中移除关联 |
| 进入用药计划详情 | 服务端模式 | 草稿模式 |
| 进入药箱详情 | 服务端模式 | 草稿模式 |

### 6.3 编辑处方

处方详情页草稿模式点击“编辑”：

1. 不使用 `MedicationPrescriptionEditPage` 的服务端保存流程，除非它已经支持 `localEdit`。
2. 推荐为编辑页增加 `Mode.localEdit`：

```swift
MedicationPrescriptionEditPage(
    mode: .localEdit,
    prescription: currentPrescription,
    plans: currentPlans,
    ...
    onLocalSaved: { updatedPrescription, updatedPlans in
        currentPrescription = updatedPrescription
        currentPlans = updatedPlans
        onPrescriptionDraftUpdated(updatedDraft)
    }
)
```

3. 如果短期成本较高，可以先在结果页继续使用现有本地编辑器，详情页编辑按钮回调给结果页打开本地编辑器。但最终体验建议在详情页内完成编辑闭环。

### 6.4 删除处方

草稿模式删除处方：

```text
点击删除
  -> 弹出确认
  -> 从结果页 batches 删除对应 index
  -> dismiss 当前详情页
  -> 结果页列表刷新
```

注意：

1. 不调用 `workflowAPI.delete`。
2. 删除后如果数组为空，结果页展示空态。
3. 删除后预校验错误列表需要重新计算。

## 7. 用药计划详情页草稿预览模式

### 7.1 页面入口

处方结果页或处方详情页进入某条用药计划时：

```swift
MedicationPlanDetailPage(
    mode: .localDraft,
    plan: draft.remoteMedicationPlan(...),
    medicineBoxes: [draft.remoteMedicineBox(...)],
    records: [],
    memberID: selectedMemberID,
    ...
    onLocalDraftSaved: { updatedPlanDraft in ... },
    onLocalDraftDeleted: { ... },
    onLocalDraftMedicineBoxSaved: { updatedBoxDraft in ... },
    onLocalDraftMedicineBoxDeleted: { ... }
)
```

默认正式入口仍是 `.server`。

### 7.2 草稿模式行为

| 操作 | 服务端模式 | 草稿模式 |
| --- | --- | --- |
| 编辑计划 | 调用服务端编辑保存 | 本地编辑 `MedicationPlanRecognitionDraft` |
| 删除计划 | 调用服务端删除 | 从对应处方的 `medicationPlans` 删除 |
| 关联药箱点击 | 进入服务端药箱详情 | 进入草稿药箱详情 |
| 病历绑定模块 | 可服务端绑定/解绑 | 第一期开只读或隐藏，避免误调用服务端 |
| 服药记录 | 展示真实记录 | 草稿模式无记录，展示空态或隐藏 |

### 7.3 嵌套进入时的草稿回传编排

草稿模式可能有两种入口：

1. 结果页直接点击某个药品，进入 `MedicationPlanDetailPage`。
2. 结果页先进入 `MedicationPrescriptionDetailPage`，再从处方详情页点击某个关联用药计划，进入 `MedicationPlanDetailPage`。

第二种是本工单重点场景。数据回传不能只停留在 `MedicationPlanDetailPage` 内部，也不能只更新 `MedicationPrescriptionDetailPage.currentPlans`，必须最终回写到结果页的：

```swift
batches[prescriptionIndex].medicationPlans?[medicationIndex]
```

推荐回调链路：

```text
MedicationPlanDetailPage(localDraft)
  -> onLocalDraftSaved(updatedMedicationDraft)
  -> MedicationPrescriptionDetailPage 更新 currentPlans / medicineBoxesByID
  -> MedicationPrescriptionDetailPage 调用 onLocalDraftMedicationPlanSaved(medicationIndex, updatedMedicationDraft)
  -> PrescriptionResultSections 回调 onUpdateMedication(prescriptionIndex, medicationIndex, updatedMedicationDraft)
  -> PrescriptionRecognitionResultContentView 更新 batches[prescriptionIndex].medicationPlans[medicationIndex]
  -> 结果页卡片、预校验、保存 payload 使用最新值
```

删除回调链路：

```text
MedicationPlanDetailPage(localDraft)
  -> onLocalDraftDeleted()
  -> MedicationPrescriptionDetailPage 从 currentPlans 删除对应 plan，并同步 medicineBoxesByID
  -> MedicationPrescriptionDetailPage 调用 onLocalDraftMedicationPlanDeleted(medicationIndex)
  -> PrescriptionResultSections 回调 onDeleteMedication(prescriptionIndex, medicationIndex)
  -> PrescriptionRecognitionResultContentView 删除 batches[prescriptionIndex].medicationPlans[medicationIndex]
  -> 结果页刷新药品数量、错误列表和保存 payload
```

关键要求：

1. `MedicationPrescriptionDetailPage` 进入用药计划详情时必须携带 `prescriptionIndex` 和 `medicationIndex`，不能只靠负数 `plan.id` 反查。
2. `MedicationPlanDetailPage` 草稿模式保存后，先更新自身 `currentPlan`，再触发外部回调。
3. `MedicationPrescriptionDetailPage` 收到保存回调后，要同步更新本页局部状态，避免用户返回处方详情时仍看到旧数据。
4. `PrescriptionRecognitionResultContentView` 收到最终回调后，要更新 `batches`，这是最终提交数据源。
5. 删除计划后，需要同时清理对应药箱草稿；如果该药箱只属于这条计划，应从 `medicineBoxesByID` 移除。
6. 删除计划后不要自动删除处方草稿；处方可以保留为空处方，由预校验提示用户补充或删除。
7. 回调过程中任何 index 越界都应安全忽略并记录 Debug 日志，不要崩溃。

建议 `MedicationPrescriptionDetailPage` 新增草稿回调参数：

```swift
let onLocalDraftMedicationPlanSaved: ((Int, MedicationPlanRecognitionDraft) -> Void)?
let onLocalDraftMedicationPlanDeleted: ((Int) -> Void)?
let onLocalDraftMedicineBoxSaved: ((Int, MedicineBoxRecognitionDraft) -> Void)?
let onLocalDraftMedicineBoxDeleted: ((Int) -> Void)?
```

其中 `Int` 是当前处方内的 `medicationIndex`。

建议 `MedicationPlanDetailPage` 新增草稿回调参数：

```swift
let onLocalDraftSaved: ((MedicationPlanRecognitionDraft) -> Void)?
let onLocalDraftDeleted: (() -> Void)?
let onLocalDraftMedicineBoxSaved: ((MedicineBoxRecognitionDraft) -> Void)?
let onLocalDraftMedicineBoxDeleted: (() -> Void)?
```

`MedicationPlanDetailPage` 不需要知道自己属于第几张处方，index path 由上层 `MedicationPrescriptionDetailPage` 捕获并闭包绑定。

### 7.4 编辑计划

用药计划详情页草稿模式点击编辑：

1. 使用本地编辑模式，不调用 `workflowAPI`。
2. 编辑保存后把 `RemoteMedicationPlan` 适配回 `MedicationPlanRecognitionDraft`，或直接让编辑页操作 draft 模型。
3. 更新路径是 `batches[prescriptionIndex].medicationPlans[medicationIndex]`。
4. 同步更新关联的 `medicineBox` 草稿字段，避免详情页看到的药品信息和药箱信息不一致。
5. 如果入口来自处方详情页，需要同时更新 `MedicationPrescriptionDetailPage.currentPlans`，否则用户从用药计划详情返回处方详情时会看到旧计划。
6. 保存回调最终必须回到 `PrescriptionRecognitionResultContentView.batches`，否则点击结果页保存时仍会提交旧数据。

编辑保存伪代码：

```swift
private func handleLocalDraftPlanSaved(
    medicationIndex: Int,
    updatedDraft: MedicationPlanRecognitionDraft
) {
    guard currentPlans.indices.contains(medicationIndex) else { return }

    let updatedPlan = updatedDraft.remoteMedicationPlan(
        memberID: memberID,
        id: currentPlans[medicationIndex].id,
        prescriptionID: currentPrescription?.id,
        medicineBoxID: currentPlans[medicationIndex].medicineBox,
        medicalCaseID: currentPrescription?.medicalCase
    )

    currentPlans[medicationIndex] = updatedPlan

    if let updatedBox = updatedDraft.medicineBox?.remoteMedicineBox(...) {
        medicineBoxesByID[updatedBox.id] = updatedBox
    }

    onLocalDraftMedicationPlanSaved?(medicationIndex, updatedDraft)
}
```

### 7.5 删除计划

草稿模式删除计划：

```text
点击删除
  -> 确认
  -> MedicationPlanDetailPage 调用 onLocalDraftDeleted
  -> MedicationPrescriptionDetailPage 删除 currentPlans[medicationIndex]
  -> MedicationPrescriptionDetailPage 调用 onLocalDraftMedicationPlanDeleted(medicationIndex)
  -> 删除 batches[prescriptionIndex].medicationPlans[medicationIndex]
  -> dismiss
  -> 结果页刷新处方药品数量
```

删除后该处方没有药品时，处方仍可保留，但提交前预校验应提示处方至少需要一条有效药品，除非服务端允许空处方。

删除处理伪代码：

```swift
private func handleLocalDraftPlanDeleted(medicationIndex: Int) {
    guard currentPlans.indices.contains(medicationIndex) else { return }

    let removedPlan = currentPlans.remove(at: medicationIndex)
    if let boxID = removedPlan.medicineBox {
        medicineBoxesByID.removeValue(forKey: boxID)
    }

    onLocalDraftMedicationPlanDeleted?(medicationIndex)
}
```

结果页最终处理：

```swift
private func deleteMedicationDraft(
    prescriptionIndex: Int,
    medicationIndex: Int
) {
    guard batches.indices.contains(prescriptionIndex) else { return }
    guard var plans = batches[prescriptionIndex].medicationPlans,
          plans.indices.contains(medicationIndex)
    else { return }

    plans.remove(at: medicationIndex)
    batches[prescriptionIndex].medicationPlans = plans
    refreshPreSubmitValidation()
}
```

注意：

1. 删除后 SwiftUI `NavigationLink` 返回时，列表 index 会变化，后续点击必须使用最新 index。
2. 删除后如果存在校验错误指向被删除的 `prescriptions[n].medicationPlans[m]`，需要清理或重算。
3. 如果当前处方详情页还停留在旧的 plan 列表，需要删除后立即刷新 `currentPlans`，不要等结果页刷新。
4. 如果删除的是最后一个计划，处方详情页药品区展示空态，不自动关闭处方详情页。

## 8. 药箱详情页草稿预览模式

### 8.1 页面入口

用药计划详情页草稿模式下点击关联药箱，必须继续草稿模式：

```swift
MedicineBoxDetailPage(
    mode: .localDraft,
    box: draft.remoteMedicineBox(...),
    entryMemberID: selectedMemberID,
    ...
    onLocalDraftSaved: { updatedBoxDraft in ... },
    onLocalDraftDeleted: { ... }
)
```

默认正式入口仍是 `.server`。

### 8.2 草稿模式行为

| 操作 | 服务端模式 | 草稿模式 |
| --- | --- | --- |
| 编辑药箱 | `MedicineBoxFormView(mode: .serverEdit)` | `MedicineBoxFormView(mode: .localEdit)` |
| 删除药箱 | 调用服务端删除 | 本地清空或删除对应药品的药箱字段 |
| 归属成员 | 服务端字段 | 使用结果页当前成员 |
| 附件 | 服务端附件 | 使用识别源文件或本地附件快照 |

### 8.3 编辑药箱

药箱详情页草稿模式点击编辑：

1. `MedicineBoxFormView` 增加 `localEdit` 模式。
2. 本地编辑保存后回调更新 `MedicationPlanRecognitionDraft.medicineBox`。
3. 如果药箱字段和用药计划字段有重叠，例如 `medicineName`、`brandName`、`dosageForm`、`strength`，需要明确同步策略。

推荐同步策略：

1. 药箱是药品基础信息主来源。
2. 编辑药箱基础字段后，同步更新用药计划中的药品展示字段。
3. 用药计划中的剂量、频次、提醒时间不受药箱编辑影响。

### 8.4 删除药箱

草稿模式删除药箱有两种设计：

方案 A：删除整个药品计划。

方案 B：只清空药箱信息，保留用药计划。

推荐第一期使用方案 B：

1. 删除药箱只清空 `MedicationPlanRecognitionDraft.medicineBox`。
2. 保留 `medicineName`、`dosePerTime`、`frequencyText` 等计划字段。
3. 提交前预校验根据服务端要求判断是否必须补齐药箱信息。

这样用户不会因为误删药箱而丢掉完整用药计划。

## 9. 草稿与远端模型转换

### 9.1 转换方向

现有结果页已有类似转换：

```swift
draft.remotePrescription(memberID:id:)
draft.remoteMedicationPlan(memberID:id:prescriptionID:medicineBoxID:medicalCaseID:)
draft.remoteMedicineBox(memberID:id:)
```

000006 需要补齐反向转换：

```swift
PrescriptionRecognitionDraft.updated(from remote: RemotePrescription, plans: [RemoteMedicationPlan], boxes: [RemoteMedicineBox])
MedicationPlanRecognitionDraft.updated(from plan: RemoteMedicationPlan, box: RemoteMedicineBox?)
MedicineBoxRecognitionDraft.updated(from box: RemoteMedicineBox)
```

也可以使用专门 Mapper：

```swift
enum PrescriptionRecognitionDraftMapper {
    static func makeRemotePrescription(...)
    static func makeRemoteMedicationPlan(...)
    static func makeRemoteMedicineBox(...)
    static func updateDraft(...)
}
```

推荐使用 Mapper，避免把大量转换逻辑散落在 SwiftUI View 内。

### 9.2 临时 ID 规则

草稿模式可以继续使用负数 ID 适配现有详情页：

```text
prescriptionID = -20_000 - prescriptionIndex
medicineBoxID = -30_000 - prescriptionIndex * 100 - medicationIndex
planID        = -40_000 - prescriptionIndex * 100 - medicationIndex
```

规则要求：

1. ID 只用于页面展示、NavigationLink identity、远端模型适配。
2. 草稿更新必须优先使用 index path。
3. 保存到服务端前不能把负数 ID 当真实 ID 上送。
4. 保存成功后服务端返回真实 ID，由保存回执展示。

## 10. 提交保存流程

### 10.1 保存入参

处方保存时使用最新：

```swift
batches: [PrescriptionRecognitionDraft]
memberID: selectedMemberID
sourceFiles: output.envelope.sourceFiles
```

服务端已支持多处方一次性提交，客户端不要按处方一条一条循环调用保存接口。

后端目标接口：

```text
POST /api/v1/medical/combined-create/
```

后端当前契约要点：

1. 请求体使用 `prescriptions: []` 承载多张处方。
2. 每个处方对象内使用 `medication_plans: []` 承载该处方下的用药计划。
3. 服务端在同一个 `transaction.atomic` 中处理成员、病例、处方、药箱、用药计划与附件绑定。
4. 返回值包含 `prescription_ids`、`medicine_box_ids`、`medication_plan_ids`。
5. 客户端提交前必须一次性组装完整 payload，不要对 `batches` 做逐条网络提交。

保存流程：

```text
点击保存
  -> 本地预校验 [PrescriptionRecognitionDraft]
  -> 如果有错误：高亮、展开、滚动
  -> 如果通过：组装 combined-create payload
  -> 一次请求提交 prescriptions 数组
  -> 服务端事务内批量创建处方、药箱、用药计划与附件绑定
  -> 返回保存回执
```

请求结构示意：

```json
{
  "member": {
    "id": 335
  },
  "medical_case": {
    "title": "处方识别",
    "diagnosis_summary": "..."
  },
  "prescriptions": [
    {
      "institution_name": "医院名称",
      "prescriber_name": "医生姓名",
      "prescribed_at": "2026-06-13",
      "diagnosis": "诊断",
      "prescription_no": "处方号",
      "source_file_ids": [1, 2],
      "medication_plans": [
        {
          "drug_name": "药品名称",
          "dose_per_time": "1片",
          "dose_value": "1",
          "dose_unit": "片",
          "frequency_type": "daily",
          "frequency_text": "每日三次",
          "reminder_times": [
            {
              "time": "08:00",
              "dose": 1
            }
          ],
          "start_date": "2026-06-13",
          "instructions": "餐后口服",
          "medicine_box": {
            "medicine_name": "药品名称",
            "dosage_form": "片剂",
            "dose_unit": "片"
          }
        }
      ]
    }
  ]
}
```

客户端适配要求：

1. `DefaultTypedMedicalDocumentSaver` 或对应保存用例需要新增/调整“处方数组保存”分支，直接调用 combined-create。
2. `batches` 中每张处方转换为 `prescriptions[]` 的一个元素。
3. 处方级附件写入对应处方元素的 `source_file_ids`。
4. 药品级附件按服务端当前契约映射到对应 `medication_plans[]` 或保持当前已支持字段，不能丢失。
5. 返回的 `prescription_ids` 顺序默认按请求 `prescriptions[]` 创建顺序对应；如服务端未来返回更细的映射，客户端优先使用显式映射。
6. 任意一张处方校验失败时，服务端事务整体失败；客户端应保留草稿并展示错误，不要尝试自动拆分重提。

### 10.2 预校验适配

`MEDICAL-AI-OCR-000003` 和 `000004` 的预校验与滚动定位需要支持处方数组。

issue path 示例：

```text
prescriptions[0].institutionName
prescriptions[0].medicationPlans[1].medicineName
prescriptions[1].medicationPlans[0].dosePerTime
```

滚动目标 ID 示例：

```swift
"prescription.0"
"prescription.0.medication.1"
"prescription.1.medication.0.field.medicineName"
```

要求：

1. 多处方下不能定位到错误处方。
2. 折叠状态下先展开对应处方，再滚动到字段。
3. 编辑/删除草稿后，需要清理已不存在 index 的错误。

### 10.3 保存后回执

保存成功后回执需要展示多处方结果：

1. 保存成功处方数量。
2. 保存成功用药计划数量。
3. 保存成功药箱数量。
4. 每张处方的真实 ID。
5. 本次保存使用服务端事务批量提交，失败时按整体失败处理，保留草稿供用户修复后重新一次性提交。

第一期不设计“部分成功/部分失败”的客户端分支；如果服务端返回字段级错误，映射到 000003/000004 的本地错误展示与定位能力。

## 11. 导航与页面挂载

### 11.1 处方结果页到处方详情

`PrescriptionResultSections.swift:350-386` 当前构造详情页的位置，需要增加：

1. `mode: .localDraft`
2. `prescriptionIndex`
3. 本地保存/删除回调
4. 选中成员 ID

伪代码：

```swift
private func prescriptionDetailDestination(
    index: Int,
    batch: PrescriptionRecognitionDraft,
    context: MedicalDocumentResultDetailNavigationContext
) -> some View {
    MedicationPrescriptionDetailPage(
        mode: .localDraft,
        prescription: mapper.remotePrescription(...),
        plans: mapper.remotePlans(...),
        medicineBoxes: mapper.remoteBoxes(...),
        ...
        onLocalDraftPrescriptionSaved: { updated in
            onUpdateBatch?(index, updated)
        },
        onLocalDraftPrescriptionDeleted: {
            onDeleteBatch?(index)
        },
        onLocalDraftMedicationPlanSaved: { medicationIndex, updated in
            onUpdateMedication?(index, medicationIndex, updated)
        },
        onLocalDraftMedicationPlanDeleted: { medicationIndex in
            onDeleteMedication?(index, medicationIndex)
        }
    )
}
```

### 11.2 处方结果页到单条药品详情

`medicationDetailDestination` 也需要传草稿模式：

```swift
MedicationPlanDetailPage(
    mode: .localDraft,
    ...
)
```

并且编辑/删除回调最终落回：

```swift
batches[batchIndex].medicationPlans?[itemIndex] = updatedDraft
```

### 11.3 用药计划详情到药箱详情

`MedicationPlanDetailPage` 内部点击关联药箱时：

```swift
MedicineBoxDetailPage(
    mode: mode == .localDraft ? .localDraft : .server,
    ...
)
```

不要在草稿模式下进入服务端药箱详情，否则用户编辑会误触发接口。

## 12. 页面 UI 细节

### 12.1 结果页处方数组

处方卡片建议：

```text
处方 1/3                  校验异常 2
上海市xx医院 · 张医生
2026-06-13 · 感冒/咳嗽
药品 4 项

[查看详情] [编辑] [管理附件]
```

多处方列表要求：

1. 每张卡片标题带序号。
2. 药品列表也带局部序号。
3. 错误态在对应处方卡片上展示角标。
4. 点击处方卡片进入处方详情草稿预览。
5. 点击单个药品进入用药计划详情草稿预览。

### 12.2 草稿详情页提示

详情页草稿模式需要有轻量提示，避免用户误以为已经保存：

```text
识别结果预览，修改仅保存到当前草稿，点击结果页保存后才会写入医疗档案。
```

位置建议：

1. 详情页顶部 Section。
2. 使用系统浅色提示样式，不做强干扰。
3. 正式服务端模式不展示。

### 12.3 草稿模式禁用项

草稿模式下建议隐藏或只读：

1. 病历绑定/解绑服务端操作。
2. 服药记录服务端数据。
3. 已保存附件的服务端管理入口。
4. 任何会直接调用 `workflowAPI` 的按钮。

## 13. 涉及文件与改动内容

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `DefaultTypedMedicalDocumentExtractor.swift` | 处方分支解码改为 `[PrescriptionRecognitionDraft]`；归一化数组；可选兼容单对象包装 | AI 抽取核心 |
| `Prompts.strings` | 处方抽取 Prompt 改为输出 JSON array；补充多处方规则 | 模型输出约束 |
| `MedicalDocumentTypedExtractionOutput` / typed result 定义 | `.prescription` 承载值改为数组 | 全流程数据结构 |
| `PrescriptionRecognitionResultContentView.swift` | `batch` 改为 `batches`；支持成员切换；保存使用最新数组 | 结果页状态 |
| `PrescriptionResultSections.swift` | 多处方展示；详情页传 `mode: .localDraft`；补齐本地更新/删除回调 | 结果页 UI 与导航 |
| `MedicationPrescriptionDetailPage.swift` | 增加 `Mode`；草稿模式编辑/删除只走本地回调；关联计划继续草稿模式 | 处方详情 |
| `MedicationPlanDetailPage.swift` | 增加 `Mode`；草稿模式编辑/删除只走本地回调；关联药箱继续草稿模式 | 用药计划详情 |
| `MedicineBoxDetailPage.swift` | 增加 `Mode`；草稿模式编辑/删除只走本地回调 | 药箱详情 |
| `MedicationPrescriptionEditPage.swift` | 可选：增加 `localEdit` 模式 | 处方本地编辑 |
| `MedicineBoxFormView.swift` | 增加 `localEdit` 模式 | 药箱本地编辑 |
| 新增 `PrescriptionRecognitionDraftMapper.swift` | 负责 draft 与 remote 模型互转、临时 ID 生成 | 降低 View 复杂度 |
| `DefaultTypedMedicalDocumentSaver.swift` / 保存用例 | 处方数组保存走 `/api/v1/medical/combined-create/` 一次提交，不做处方级循环请求 | 保存编排 |
| `SparkMedicalWorkflowAPI` / 医疗接口层 | 补齐 combined-create 批量保存 payload 和响应模型，接收 `prescription_ids`、`medicine_box_ids`、`medication_plan_ids` | 客户端网络契约 |
| `SparkService/medical/views.py` | 复用现有 `combined-create` 的 `prescriptions` 数组能力；不需要新增逐条接口 | 服务端契约 |
| `MedicalPreSubmitValidation` 相关文件 | 支持处方数组 issue path 和滚动目标 | 预校验 |
| `Localizable.strings` | 增加草稿预览提示、处方数组空态、成员切换文案 | 本地化 |

## 14. 验收标准

### 14.1 处方数组识别

1. AI 只识别到一张处方时，结果为 `[PrescriptionRecognitionDraft]`，页面展示 1 张处方。
2. AI 识别到多张处方时，页面展示多张处方卡片。
3. AI 返回 `[]` 时页面不崩溃，展示空态。
4. `extractedJSON` 保存为数组 JSON。
5. 解码失败自动重试时，能提示模型必须输出数组。

### 14.2 成员切换

1. 处方结果页可切换成员。
2. 切换成员后，处方详情、用药计划详情、药箱详情展示的新 memberID 一致。
3. 切换成员后保存，资源归属为新成员。
4. 切换成员不丢失已编辑草稿。

### 14.3 处方详情草稿模式

1. 识别结果页进入处方详情时为草稿模式。
2. 草稿模式下编辑处方不调用服务端。
3. 草稿模式下删除处方不调用服务端，并能从结果页移除。
4. 编辑后返回结果页，处方卡片内容同步更新。
5. 正式医疗档案入口进入处方详情仍是服务端模式。

### 14.4 用药计划详情草稿模式

1. 识别结果页进入单条药品/用药计划详情时为草稿模式。
2. 草稿模式下编辑计划不调用服务端。
3. 草稿模式下删除计划不调用服务端，并能从对应处方移除。
4. 编辑后结果页药品卡片同步更新。
5. 草稿模式下点击关联药箱，进入药箱草稿详情。

### 14.5 药箱详情草稿模式

1. 草稿模式下药箱编辑不调用服务端。
2. 编辑药箱后，同步更新对应用药计划中的药品基础信息。
3. 删除药箱时不丢失整条用药计划。
4. 正式药箱列表入口进入仍是服务端模式。

### 14.6 预校验与保存

1. 多处方下提交前预校验能定位到正确处方和药品。
2. 折叠处方存在错误时，点击保存能展开对应处方并滚动到错误字段。
3. 编辑/删除草稿后，错误列表同步刷新。
4. 保存提交使用编辑后的最新数组。
5. 保存成功回执能表达多处方保存结果。

## 15. 风险与注意事项

1. 不要用负数临时 ID 反向推断业务位置，草稿更新必须使用 index path。
2. 不要在草稿模式下误调用 `workflowAPI`，这是本工单最重要的边界。
3. 不要把处方数组强行合并成一个处方，否则会破坏真实医疗语义。
4. `PrescriptionRecognitionResultContentView` 不要继续堆大量转换逻辑，建议抽到 Mapper。
5. 详情页 Mode 先做页面内独立枚举即可，不要为了“统一”提前抽象出庞大的医疗资源编辑框架。
6. Prompt 改成数组后，所有测试样例都要同步更新，否则会误判解码失败。
7. 处方数组保存必须走服务端 `combined-create` 批量事务接口；不要在客户端按处方循环提交，否则会造成部分成功、重复创建和附件归属不一致。
8. 草稿模式的本地编辑必须和最终保存模型一致，避免用户看到的内容和实际提交内容不一致。

## 16. 建议实现顺序

1. 先改数据结构：`.prescription([PrescriptionRecognitionDraft])`。
2. 再改 Extractor：处方按数组解码、归一化、输出数组 JSON。
3. 再改 Prompt：要求输出数组。
4. 改结果页：`batch` -> `batches`，先完成多处方展示和保存。
5. 增加成员切换：复用体检报告结果页交互。
6. 增加 Mapper：集中处理 draft/remote 转换和临时 ID。
7. 给处方详情页增加 `mode` 和草稿编辑/删除回调。
8. 给用药计划详情页增加 `mode` 和草稿编辑/删除回调。
9. 给药箱详情页增加 `mode` 和草稿编辑/删除回调。
10. 接入 `/api/v1/medical/combined-create/`，把 `batches` 一次性组装为 `prescriptions` 数组提交。
11. 补齐预校验 path、滚动定位和保存回执。

这个顺序可以避免一开始就同时改抽取、UI、详情页和保存流程，降低回归风险。

## 工单 `MEDICAL-AI-OCR-000007`：处方提交前 dose_value 数值预校验修复

### 工单状态

修复需求/待实现。

## 1. 问题背景

处方识别结果页点击提交后，客户端已经进入 `/api/v1/medical/combined-create/` 保存流程，但本地预校验没有拦住 `dose_value` 非数字问题，导致服务端返回 400。

典型服务端错误：

```text
POST /api/v1/medical/combined-create/ status=400
body={"code": -1, "msg": {"dose_value": ["A valid number is required."]}, "data": null}
```

典型请求片段：

```json
{
  "drug_name": "阿托伐他汀钙片",
  "dose_per_time": "1片",
  "dose_value": "20mg",
  "dose_unit": "片"
}
```

```json
{
  "drug_name": "硫酸氨氯吡格雷片",
  "dose_per_time": "3片",
  "dose_value": "225mg",
  "dose_unit": "片"
}
```

服务端 `dose_value` 字段要求是纯数值。`20mg`、`225mg` 这类“数值 + 单位”的字符串不符合服务端存储规则，应在客户端提交前被本地预校验拦截。

## 2. 修复目标

1. 处方数组提交前必须校验每条 `medicationPlans[n].doseValue`。
2. `doseValue` 非空时必须是服务端可接受的数字字符串。
3. 发现 `20mg`、`225mg`、`1片`、`半片`、`1滴` 这类非纯数字值时，不发起 `/api/v1/medical/combined-create/`。
4. 在结果页顶部展示本地预校验错误摘要。
5. 高亮对应处方下的对应药品卡片。
6. 如果卡片在折叠模块内，复用 000004：先展开，再滚动定位。
7. 提示用户去编辑对应药品，把 `doseValue` 改为纯数字，单位放到 `doseUnit` 或 `dosePerTime`。

## 3. 校验规则

### 3.1 字段范围

需要覆盖：

```text
MedicalDocumentTypedResult.prescription([PrescriptionRecognitionDraft])
  -> prescriptions[n].medicationPlans[m].doseValue

MedicalDocumentTypedResult.medicationPlan([MedicationPlanRecognitionDraft])
  -> medicationPlans[m].doseValue

CaseRecognitionDraft.prescriptions[n].medicationPlans[m].doseValue
```

本工单重点修复处方结果页，但公共预校验器应尽量复用同一条规则，避免病例内处方和独立用药计划再次漏掉。

### 3.2 合法值

合法：

```text
1
1.5
0.5
20
225
```

非法：

```text
20mg
225mg
1片
1滴
半片
一片
每日一次
```

建议解析规则：

```swift
private static func isValidDecimalString(_ value: String) -> Bool {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.isEmpty == false else { return true }
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) != nil
}
```

注意：

1. 空值不阻断，由服务端或业务规则决定是否允许。
2. 只要包含单位、中文、英文字母，就应阻断。
3. 不在本工单内自动把 `20mg` 拆成 `doseValue=20`、`doseUnit=mg`，避免误改医疗语义。

## 4. 错误提示与定位

### 4.1 issue 字段路径

处方数组：

```text
prescriptions[1].medicationPlans[0].doseValue
```

滚动目标：

```text
preSubmitValidation.card.medicationPlan.1.0
```

用药计划独立页：

```text
medicationPlans[0].doseValue
```

病例内处方：

```text
case.prescriptions[1].medicationPlans[0].doseValue
```

### 4.2 用户提示文案

建议中文：

```text
单次剂量数值必须是纯数字，例如 1、0.5、20；单位请填写到剂量单位或单次剂量描述中。
```

建议英文：

```text
Dose value must be a number, such as 1, 0.5, or 20. Put units in dose unit or dose description.
```

### 4.3 UI 表现

1. 顶部 `MedicalPreSubmitValidationSummaryBanner` 展示错误。
2. 对应药品卡片高亮。
3. 卡片内展示内联错误。
4. 点击错误摘要时滚动到对应药品卡片。
5. 不调用服务端保存接口。

## 5. 涉及文件

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `MedicalPreSubmitValidator.swift` | 增加 `doseValue` 纯数字校验；覆盖处方数组、病例处方、独立用药计划 | 保存前拦截 |
| `MedicalPreSubmitValidationIssue.swift` | 如当前 fieldKey/scrollTargetID 不够精确，补充 `dose_value` / `doseValue` 定位 | 字段高亮 |
| `PrescriptionResultSections.swift` | 确认药品卡片能展示 `doseValue` 错误 inline issue | UI 展示 |
| `MedicationRecognitionResultContentView.swift` | 确认独立用药计划结果页也能展示该错误 | UI 展示 |
| `Localizable.strings` | 增加 dose value 数字校验文案 | 本地化 |

## 6. 验收标准

1. 处方识别结果中 `doseValue = "20mg"` 时，点击提交不会请求 `/api/v1/medical/combined-create/`。
2. 顶部显示本地预校验错误。
3. 错误定位到对应处方、对应药品卡片。
4. 用户编辑为 `doseValue = "20"` 后，再次提交可以继续进入保存流程。
5. `dosePerTime = "1片"`、`doseUnit = "片"` 不因本规则报错；只校验 `doseValue`。
6. 多处方场景下，第 2 张处方第 1 个药品错误时，不定位到第 1 张处方。
7. 服务端不再收到明显可由客户端判断的 `dose_value` 非数字请求。

## 7. 风险与注意事项

1. 不要自动改写医疗剂量，尤其不要把 `225mg` 自动拆分成 `225` 和 `mg`，因为该值可能表达规格而不是单次剂量。
2. 不要把 `dosePerTime` 按纯数字校验，它本来就可以是 `1片`、`1滴`、`半片`。
3. 校验规则应放在公共预校验器中，不要只在 UI 层临时判断。
4. 服务端仍然保留最终校验，本工单只是补齐客户端可提前发现的规则缺口。

## 工单 `MEDICAL-AI-OCR-000008`：草稿模式删除关联药箱未清理用药计划草稿

### 工单状态

修复需求/待实现。

## 1. 问题背景

`MEDICAL-AI-OCR-000006` 已为处方识别结果页增加草稿模式详情链路：

```text
处方识别结果页
  -> 处方详情页 localDraft
  -> 用药计划详情页 localDraft
  -> 关联药箱详情页 localDraft
```

当前发现一个实际问题：

```text
草稿模式进入服药计划详情页面
  -> 点击关联药箱进入药箱详情页面
  -> 右上角删除药箱
  -> 返回服药计划详情页面
  -> 页面仍然显示旧药箱
  -> 最终草稿内 medicineBox 没有被真正清除
```

该问题会导致用户以为已经删除药箱，但结果页草稿和最终保存 payload 仍可能携带旧的 `medicineBox`，保存后仍创建药箱或仍把用药计划关联到药箱。

## 2. 当前代码定位

### 2.1 药箱详情页删除只抛事件

`MedicineBoxDetailPage.deleteCurrentBox()` 草稿模式下当前逻辑：

```swift
if mode == .localDraft {
    onLocalDraftDeleted?()
    dismiss()
    return
}
```

位置：

```text
SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/MedicineBoxDetailPage.swift:199-207
```

这个页面自身只负责触发 `onLocalDraftDeleted`，不直接知道上层用药计划草稿结构，这个方向是合理的。

### 2.2 用药计划详情页只继续向外抛，没有更新自身草稿

`MedicationPlanDetailPage` 进入关联药箱详情时当前逻辑：

```swift
MedicineBoxDetailPage(
    mode: mode == .localDraft ? .localDraft : .server,
    ...
    onLocalDraftDeleted: {
        onLocalDraftMedicineBoxDeleted?()
    }
)
```

位置：

```text
SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationPlanDetailPage.swift:95-112
```

问题在这里：`MedicationPlanDetailPage` 收到药箱删除事件后，只把事件继续抛给父级，没有同步更新本页的：

1. `sourcePlanDraft`
2. `currentPlan.medicineBox`
3. `medicineBoxes`
4. 页面 `medicineBox` 计算属性依赖的数据源

所以返回用药计划详情页时，本页仍然能从旧 `currentPlan.medicineBox` + `medicineBoxes` 里解析出旧药箱。

### 2.3 父级可能更新了最终草稿，但当前页面仍显示旧状态

处方详情页已有类似处理：

```swift
handleLocalDraftMedicineBoxDeleted(medicationIndex:)
```

但如果 `MedicationPlanDetailPage` 自己没有先清理本地状态，用户从药箱详情 dismiss 回到用药计划详情页时，当前页面仍显示旧药箱。父级更新不能自动反向刷新已经在导航栈里的子页面本地 `@State`。

## 3. 根因分析

根因不是服务端问题，也不是药箱详情页删除按钮没有触发，而是草稿模式下缺少“本页状态先行更新”。

当前删除链路是：

```text
MedicineBoxDetailPage
  -> onLocalDraftDeleted
  -> MedicationPlanDetailPage 直接 onLocalDraftMedicineBoxDeleted
  -> 父级更新结果页草稿
```

缺少：

```text
MedicationPlanDetailPage 清理自己的 sourcePlanDraft / currentPlan / medicineBoxes
```

这会造成两个层面的不一致：

1. UI 层：返回用药计划详情页仍能看到旧药箱。
2. 数据层：如果后续在用药计划详情页继续编辑并保存，可能基于旧 `sourcePlanDraft` 再次把药箱写回。

## 4. 修复目标

### 核心目标

草稿模式下，从用药计划详情页进入关联药箱详情页并删除药箱后，必须同时清理：

1. `MedicationPlanDetailPage` 当前页本地状态。
2. 父级 `MedicationPrescriptionDetailPage` 当前处方草稿状态。
3. 结果页 `PrescriptionRecognitionResultContentView.batches` 中对应的 `MedicationPlanRecognitionDraft.medicineBox`。
4. 最终保存到 `/api/v1/medical/combined-create/` 的 payload 中对应药品的 `medicine_box`。

同时需要保留一个重要交互原则：

1. 草稿模式下，用药计划详情页仍然需要展示“关联药品/关联药箱”模块。
2. 只要当前草稿 `medicineBox != nil`，就展示关联药品入口，用户可以点击进入药品/药箱详情。
3. 用户在药品/药箱详情里点击删除后，只清除该用药计划草稿中的关联药品，即 `medicineBox = nil`、`currentPlan.medicineBox = nil`。
4. 删除关联药品不等于删除用药计划；用药计划的药品名称、剂量、频次、提醒时间仍然保留。

### 非目标

1. 不删除整条用药计划。
2. 不调用服务端删除药箱接口。
3. 不关闭用药计划详情页。
4. 不自动删除处方草稿。

## 5. 修复方案

### 5.1 在 `MedicationPlanDetailPage` 增加本地删除处理方法

新增方法：

```swift
private func applyLocalDraftMedicineBoxDeleted() {
    let oldBoxID = currentPlan.medicineBox

    if let oldBoxID {
        medicineBoxes.removeAll { $0.id == oldBoxID }
    }

    var draft = currentSourcePlanDraft()
    draft = MedicationPlanRecognitionDraft(
        medicineName: draft.medicineName,
        medicineType: draft.medicineType,
        totalQuantity: draft.totalQuantity,
        expireDate: draft.expireDate,
        medicineBox: nil,
        brandName: draft.brandName,
        dosageForm: draft.dosageForm,
        strength: draft.strength,
        dosePerTime: draft.dosePerTime,
        doseValue: draft.doseValue,
        doseUnit: draft.doseUnit,
        frequencyType: draft.frequencyType,
        everyNDays: draft.everyNDays,
        weeklyWeekdays: draft.weeklyWeekdays,
        frequencyText: draft.frequencyText,
        startDate: draft.startDate,
        endDate: draft.endDate,
        instructions: draft.instructions,
        reminderEnabled: draft.reminderEnabled,
        reminderTimes: draft.reminderTimes,
        status: draft.status,
        sortOrder: draft.sortOrder,
        extra: draft.extra,
        attachmentFileIds: draft.attachmentFileIds
    )

    sourcePlanDraft = draft
    currentPlan = SparkMedicalSyncAPI.RemoteMedicationPlan(
        id: currentPlan.id,
        member: currentPlan.member,
        medicalCase: currentPlan.medicalCase,
        medicineBox: nil,
        prescription: currentPlan.prescription,
        drugName: currentPlan.drugName,
        dosePerTime: currentPlan.dosePerTime,
        doseValue: currentPlan.doseValue,
        doseUnit: currentPlan.doseUnit,
        frequencyType: currentPlan.frequencyType,
        everyNDays: currentPlan.everyNDays,
        weeklyWeekdays: currentPlan.weeklyWeekdays,
        frequencyText: currentPlan.frequencyText,
        startDate: currentPlan.startDate,
        endDate: currentPlan.endDate,
        instructions: currentPlan.instructions,
        reminderEnabled: currentPlan.reminderEnabled,
        reminderTimes: currentPlan.reminderTimes,
        status: currentPlan.status,
        extra: currentPlan.extra,
        attachments: currentPlan.attachments,
        updatedAt: currentPlan.updatedAt
    )

    onLocalDraftMedicineBoxDeleted?()
}
```

删除后的显示规则：

1. `medicineBox == nil` 时，关联药品模块不再展示旧药品卡片。
2. 如果业务希望用户能重新补充关联药品，可以显示空态入口，例如“暂无关联药品”或“添加关联药品”；第一期至少不能继续显示旧药品。
3. 用药计划基础信息区继续展示 `drugName` / `medicineName`、剂量、频次、说明等字段。

如果 `RemoteMedicationPlan` 初始化字段较多，建议不要手写散落构造，而是补一个 Mapper：

```swift
PrescriptionRecognitionDraftMapper.remoteMedicationPlan(
    from: draft,
    preserving: currentPlan,
    medicineBoxID: nil
)
```

这样可以避免未来模型字段新增时漏同步。

### 5.2 药箱删除回调改为先更新本页，再通知父级

当前：

```swift
onLocalDraftDeleted: {
    onLocalDraftMedicineBoxDeleted?()
}
```

改为：

```swift
onLocalDraftDeleted: {
    applyLocalDraftMedicineBoxDeleted()
}
```

删除后状态链路应变为：

```text
MedicineBoxDetailPage.deleteCurrentBox
  -> MedicationPlanDetailPage.applyLocalDraftMedicineBoxDeleted
      -> sourcePlanDraft.medicineBox = nil
      -> currentPlan.medicineBox = nil
      -> medicineBoxes 移除旧 box
      -> onLocalDraftMedicineBoxDeleted
  -> MedicationPrescriptionDetailPage.handleLocalDraftMedicineBoxDeleted
      -> 当前处方草稿对应 medicationPlans[index].medicineBox = nil
      -> onLocalDraftMedicationPlanSaved / onLocalDraftMedicineBoxDeleted
  -> PrescriptionRecognitionResultContentView.updateMedicationDraft
      -> batches[prescriptionIndex].medicationPlans[medicationIndex].medicineBox = nil
```

UI 刷新要求：

1. 删除前：服药计划详情页显示关联药品卡片。
2. 删除后：返回服药计划详情页，关联药品卡片立即消失或变为空态。
3. 再次进入该服药计划详情页，不应通过旧的 `sourcePlanDraft` 或 `currentPlan.medicineBox` 恢复出旧药品。

### 5.3 `applyLocalDraftPlan` 需要支持清空 medicineBox

当前 `MedicationPlanDetailPage.applyLocalDraftPlan(_:)` 中：

```swift
let boxID = currentPlan.medicineBox
let updatedPlan = updatedDraft.remoteMedicationPlan(
    ...
    medicineBoxID: boxID,
    ...
)
```

如果 `updatedDraft.medicineBox == nil`，但 `currentPlan.medicineBox` 仍有旧 ID，这里会把旧 `medicineBoxID` 再写回 `currentPlan`。

修复要求：

```swift
let boxID = updatedDraft.medicineBox == nil ? nil : currentPlan.medicineBox
```

或者更清晰：

```swift
let boxID: Int?
if updatedDraft.medicineBox == nil {
    boxID = nil
} else {
    boxID = currentPlan.medicineBox
        ?? PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(...)
}
```

这样编辑/删除药箱后，`currentPlan.medicineBox` 不会被旧值污染。

### 5.4 父级处方详情页避免重复回调

`MedicationPrescriptionDetailPage.handleLocalDraftMedicineBoxDeleted` 当前会构造 `medicineBox: nil` 的 plan，并调用 `handleLocalDraftPlanSaved`。这可以保持“药箱删除本质上也是计划草稿更新”。

但需要注意：

1. 不要同时让 `MedicationPlanDetailPage` 和 `MedicationPrescriptionDetailPage` 各自重复调用结果页两次。
2. 推荐统一约定：药箱删除最终以 `onLocalDraftMedicationPlanSaved(medicationIndex, updatedPlanDraftWithNilBox)` 作为结果页更新主通道。
3. `onLocalDraftMedicineBoxDeleted` 只用于父级本地清理 `medicineBoxesByID` 或日志，不再额外更新结果页同一条 plan。

## 6. 涉及文件

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `MedicationPlanDetailPage.swift` | 草稿模式保留关联药品展示；新增 `applyLocalDraftMedicineBoxDeleted`；药箱详情删除回调先清理本页状态；`applyLocalDraftPlan` 支持 `medicineBoxID=nil` | 修复当前页返回后仍显示旧药箱 |
| `MedicationPrescriptionDetailPage.swift` | 复核 `handleLocalDraftMedicineBoxDeleted`，确保父级草稿与结果页回调只更新一次 | 避免重复回调和状态抖动 |
| `PrescriptionResultSections.swift` | 复核从用药计划详情直接进入药箱详情的回调，确保 `onUpdateMedicationDraft` 收到 `medicineBox=nil` 的 draft | 结果页草稿最终一致 |
| `PrescriptionRecognitionResultContentView.swift` | 复核 `updateMedicationDraft` 后同步 `viewModel.updateTypedResult(.prescription(batches))` | 保存 payload 一致 |
| `PrescriptionRecognitionDraftMapper.swift` | 可选：增加保留原 `RemoteMedicationPlan` 但清空/替换 `medicineBoxID` 的转换方法 | 降低手写模型构造风险 |

## 7. 验收标准

1. 草稿模式进入“服药计划详情页 -> 关联药箱详情页”，点击右上角删除药箱后，不调用服务端删除接口。
2. 删除前，草稿模式用药计划详情页需要显示关联药品/药箱入口。
3. 返回服药计划详情页后，关联药品/药箱模块不再显示旧药箱；如有空态入口，只能展示空态。
4. 返回处方详情页后，对应用药计划行不再显示旧药箱信息。
5. 返回处方识别结果页后，对应药品草稿的 `medicineBox == nil`。
6. 点击提交时，`/api/v1/medical/combined-create/` payload 中该药品不再携带旧 `medicine_box`。
7. 删除药箱不删除整条用药计划，药品名称、剂量、频次、提醒时间仍保留。
8. 删除后再次进入该用药计划详情页，不会因为旧 `currentPlan.medicineBox` 或旧 `sourcePlanDraft` 重新显示药箱。
9. 如果用户删除药箱后继续编辑用药计划，保存编辑不会把旧药箱恢复回来。

## 8. 风险与注意事项

1. 不能只在 `MedicationPrescriptionDetailPage` 处理，因为用户删除后首先返回的是 `MedicationPlanDetailPage`，这个页面自己的 `@State` 必须同步更新。
2. 不能只删除 `medicineBoxes` 数组，必须同时清空 `currentPlan.medicineBox` 和 `sourcePlanDraft.medicineBox`。
3. 不要把“删除药箱”解释为“删除用药计划”，两者是不同业务动作。
4. 草稿模式下所有操作都不能调用 `workflowAPI.delete(kind: .medicineBoxes, ...)`。
5. 尽量通过 Mapper 构造更新后的 `RemoteMedicationPlan`，避免手写初始化遗漏字段。
6. 不要因为是草稿模式就隐藏关联药品入口；有 `medicineBox` 时必须可见，删除后才清空关联。

## 工单 `MEDICAL-AI-OCR-000009`：处方识别药箱候选确认与批量保存

### 工单状态

已实现。

## 1. 背景与问题

处方识别结果中的每条 `MedicationPlanRecognitionDraft` 可能包含：

```swift
let medicineBox: MedicineBoxRecognitionDraft?
```

这个 `medicineBox` 表示 AI 从处方、包装、说明或 OCR 中识别出的“可加入家庭药箱的药品候选”。但它不应该默认保存到药箱，因为：

1. AI 识别可能不准确，药品名、规格、数量、有效期可能需要用户确认。
2. 家庭药箱里可能已经有同名药品，应优先绑定已有药品，而不是新建重复药品；是否修改库存需要用户单独确认。
3. 同名药品可能有多个规格，不允许静默选择第一条。
4. 用户可能只想保存处方和用药计划，不想加入药箱。
5. 当前 `PrescriptionBatchWorkflowSaveView` / combined 保存如果 payload 中带 `medicineBox`，可能默认创建药箱；本工单要求未确认的候选不能默认创建。

因此处方识别结果页需要新增“药箱候选确认”机制：先加载当前成员家庭药箱，和 `batches[].medicationPlans[].medicineBox` 做匹配，展示候选状态；只有用户明确勾选确认后，提交时才允许该用药计划绑定已有药品或通过处方批量保存流程新建药箱药品。

## 2. 设计目标

### 核心目标

在 `PrescriptionRecognitionResultContentView` 里，根据当前 `selectedMemberID` 加载家庭药箱列表，和识别结果中的药箱候选进行匹配，展示识别概览和每条药品的药箱候选卡。提交时：

1. 用户未确认的候选：从处方保存 payload 中剥离 `medicineBox`，不绑定已有药品、不更新库存、不新建药箱。
2. 用户确认且匹配已有药品：提交处方批量保存 payload 时剥离 `medicineBox`，但携带“绑定已有药品”的目标 ID；由 `PrescriptionBatchWorkflowSaveView` 保存用药计划时绑定该药品。是否修改库存由用户勾选时单独确认，选择“是”后打开 `MedicineBoxFormView` 服务端编辑页，由用户基于服务端当前药品数据自行修改并保存。
3. 用户确认且无已有药品：提交处方批量保存 payload 时不剥离 `medicineBox`；直接使用 `PrescriptionBatchWorkflowSaveView` 内已有的药箱创建能力创建药箱药品，不再由客户端额外调用新建药箱接口。
4. 同名命中多条：必须用户选择目标药品后才能勾选确认，不允许静默选择第一条。

### 非目标

1. 不让 AI 自动决定是否加入药箱。
2. 不默认把所有 `medicineBox` 上送给处方批量保存接口；只有用户确认“新建药箱药品”时才保留。
3. 不在本工单内做复杂药品相似度模型，只做可解释的本地匹配规则。
4. 不自动合并不同规格药品。

## 3. UI 设计

### 3.1 识别概览区

处方识别结果页在成员确认区下方、处方列表上方增加“识别概览”。

示例：

```text
┌ 识别概览 ─────────────────────────────────┐
│ 处方 2 张 · 药品 5 个 · 药箱候选 3 个         │
│ 待确认：3 个                               │
│ 已匹配已有药品：2 个                         │
│ 可新建药箱药品：1 个                         │
└──────────────────────────────────────────┘
```

统计口径：

| 字段 | 口径 |
| --- | --- |
| 处方 N 张 | `batches.count` |
| 药品 N 个 | 所有 `batches[].medicationPlans` 总数 |
| 药箱候选 N 个 | `medicationPlan.medicineBox != nil` 的数量 |
| 待确认 N 个 | 有候选但用户未勾选确认的数量；多候选未选择目标也计入待确认 |
| 已匹配已有药品 N 个 | 候选匹配到唯一已有药品，或用户已从多条中选择目标 |
| 可新建药箱药品 N 个 | 候选没有匹配到已有药品 |

UI 要求：

1. 概览区只展示统计，不替代每个药品卡里的确认操作。
2. 家庭药箱加载中时，概览显示加载态或“正在匹配家庭药箱”。
3. 家庭药箱加载失败时，不阻断处方保存，但候选卡显示“药箱匹配失败，可重试”。

### 3.2 无药箱候选的药品卡

```text
┌ 药品 1/3 ───────────────────────────────┐
│ 头孢克肟片                               │
│ 100mg · 每日 2 次 · 饭后                   │
│ 2026-06-12 至 2026-06-18                 │
│ [编辑药品] [附件]                         │
└──────────────────────────────────────────┘
```

说明：

1. 没有 `medicineBox` 候选时，不展示药箱候选卡。
2. 仍然允许编辑药品和附件。

### 3.3 有候选且唯一匹配已有药品

```text
┌ 药品 2/3 ───────────────────────────────┐
│ 阿莫西林胶囊                             │
│ 0.5g · 每日 3 次 · 7 天                   │
│ [编辑药品] [附件]                         │
│                                          │
│ ┌ 药箱候选 ────────────────────────────┐ │
│ │ 识别到可加入药箱的药品                  │ │
│ │ 阿莫西林胶囊                            │ │
│ │ 规格：0.25g x 24 粒                     │ │
│ │ 有效期：2027-05-01                      │ │
│ │                                        │ │
│ │ 匹配结果：已有药品                       │ │
│ │ 当前库存：12 粒                          │ │
│ │ 提交时：绑定该已有药品                     │ │
│ │                                        │ │
│ │ [ ] 添加到药箱，提交时绑定该药品           │ │
│ │ [编辑候选]                              │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

行为：

1. 默认不勾选。
2. 用户勾选后，先弹窗询问“是否需要更新该药品的库存信息”。
3. 用户选择“是”：使用 sheet 打开 `MedicineBoxFormView` 药箱服务端编辑页面，加载匹配到的已有药品，用户自行确认是否修改库存、单位、有效期等信息，并在表单内直接提交到服务器。
4. 用户选择“否”：正常完成勾选确认，不打开 `MedicineBoxFormView`。
5. 无论是否打开编辑页，提交处方时该用药计划都绑定选中的已有药品。
6. 提交处方保存 payload 时，该条用药计划下的 `medicineBox` 必须剥离，避免服务端重复创建药箱。
7. payload 需要携带目标已有药品 ID，字段统一使用 Swift `medicineBoxID` / JSON `medicine_box_id`。
8. 客户端不使用本次识别草稿里的库存数量、库存单位自动更新已有药品；已有药品库存以服务端药箱编辑页中的数据为准，由用户自行修改并提交。

### 3.4 有候选且无已有药品

```text
┌ 药品 3/3 ───────────────────────────────┐
│ 布洛芬缓释胶囊                           │
│ 必要时 · 疼痛或发热                       │
│ [编辑药品] [附件]                         │
│                                          │
│ ┌ 药箱候选 ────────────────────────────┐ │
│ │ 识别到可加入药箱的药品                  │ │
│ │ 布洛芬缓释胶囊                          │ │
│ │ 规格：0.3g x 10 粒                      │ │
│ │ 有效期：未识别                           │ │
│ │                                        │ │
│ │ 匹配结果：无已有药品                     │ │
│ │ 提交后：新建药箱药品                     │ │
│ │                                        │ │
│ │ [ ] 添加到药箱，提交后新建                │ │
│ │ [编辑候选]                              │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

行为：

1. 默认不勾选。
2. 用户勾选后，提交时保留 `medicineBox`，由 `PrescriptionBatchWorkflowSaveView` 内部创建药箱药品。
3. 如果用户未勾选，提交时剥离该条 `medicineBox`，不新建药箱。

### 3.5 同名命中多条

```text
┌ 药箱候选 ───────────────────────────────┐
│ 阿莫西林胶囊                              │
│ 匹配结果：找到 2 个同名已有药品              │
│ 请选择要绑定的药品                         │
│                                          │
│ ( ) 阿莫西林胶囊 · 0.25g x 24 粒 · 库存 12  │
│ ( ) 阿莫西林胶囊 · 0.5g x 12 粒 · 库存 6    │
│                                          │
│ [ ] 添加到药箱，提交时绑定所选药品           │
└──────────────────────────────────────────┘
```

规则：

1. 多条同名时，未选择目标药品不能确认添加。
2. 不允许静默选择第一条。
3. 用户选择目标药品后，勾选才可用。
4. 用户勾选后同样弹窗询问是否打开 `MedicineBoxFormView` 更新该药品库存信息。
5. 用户也可以不勾选，表示不加入药箱。

## 4. 数据加载设计

### 4.1 进入结果页加载家庭药箱

`PrescriptionRecognitionResultContentView` 进入后，根据当前 `selectedMemberID` 调用：

```swift
MedicalQueryAPI.listFamilyMedicineCabinet(memberID:)
```

接口位置：

```text
SparkClient/Projects/Core/Networking/API/Medical/MedicalQueryAPI.swift:125-132
```

后端接口：

```text
GET /api/v1/medical/medicine-cabinet/summary/?member_id={selectedMemberID}
```

### 4.2 切换成员后重新加载

当用户切换 `selectedMemberID`：

```text
selectedMemberID changed
  -> 清空旧家庭药箱列表
  -> 清空或重置旧匹配结果
  -> 调用 listFamilyMedicineCabinet(newMemberID)
  -> 重新匹配 batches 内所有 medicineBox 候选
```

要求：

1. 旧成员的匹配结果不能沿用到新成员。
2. 用户在旧成员下勾选的药箱确认状态，切换成员后默认失效，需要重新确认。
3. 如果切回旧成员，第一期不要求恢复之前勾选状态，避免状态复杂。

### 4.3 加载状态

建议状态：

```swift
@State private var familyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = []
@State private var isLoadingFamilyMedicineBoxes = false
@State private var familyMedicineBoxLoadError: String?
@State private var medicineCandidateMatches: [MedicationCandidateKey: MedicineBoxCandidateMatch] = [:]
@State private var medicineCandidateConfirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation] = [:]
```

`MedicationCandidateKey`：

```swift
struct MedicationCandidateKey: Hashable, Sendable {
    let prescriptionIndex: Int
    let medicationIndex: Int
}
```

## 5. 匹配规则设计

### 5.1 候选来源

候选来源：

```swift
batches[prescriptionIndex]
    .medicationPlans?[medicationIndex]
    .medicineBox
```

匹配字段第一期只使用药品名称：

1. 优先使用 `medicineBox.medicineName`。
2. `medicineBox.medicineName` 为空时，兜底使用 `medicationPlan.medicineName`。
3. 不使用 `brandName`、`strength`、`dosageForm`、`doseUnit` 参与匹配。
4. 不做药品别名匹配，例如“阿莫西林胶囊”和“阿莫西林”第一期不视为同一药品。

### 5.2 标准化规则

第一期建议只做轻量标准化：

1. 去掉前后空格。
2. 英文大小写不敏感。
3. 中文全角/半角符号标准化。
4. 去掉常见空白符。
5. 规格、剂型、单位只用于卡片展示，不参与匹配。

### 5.3 匹配结果枚举

```swift
enum MedicineBoxCandidateMatch: Equatable, Sendable {
    case noCandidate
    case noExisting(candidate: MedicineBoxRecognitionDraft)
    case uniqueExisting(candidate: MedicineBoxRecognitionDraft, target: SparkMedicalSyncAPI.RemoteMedicineBox)
    case multipleExisting(candidate: MedicineBoxRecognitionDraft, targets: [SparkMedicalSyncAPI.RemoteMedicineBox])
    case loadFailed(candidate: MedicineBoxRecognitionDraft, message: String)
}
```

### 5.4 匹配优先级

建议第一期规则：

1. 药品名称完全一致，且只命中一条家庭药箱药品：唯一匹配已有药品。
2. 药品名称完全一致，命中多条家庭药箱药品：多候选，必须用户选择目标后才能勾选绑定。
3. 药品名称不一致：无已有药品，可由用户确认后新建药箱药品。
4. 同名但规格不同仍然按同名候选处理，不因为规格不同自动判定为无已有药品。
5. 药品别名、品牌名、规格、剂型、单位第一期不参与匹配，避免误合并。

## 6. 用户确认状态

### 6.1 确认模型

```swift
enum MedicineBoxCandidateAction: Equatable, Sendable {
    case none
    case bindExisting(medicineBoxID: Int)
    case createNew
}

struct MedicineBoxCandidateConfirmation: Equatable, Sendable {
    var isConfirmed: Bool
    var action: MedicineBoxCandidateAction
    var editedCandidate: MedicineBoxRecognitionDraft?
}
```

默认：

```swift
isConfirmed = false
action = .none
```

### 6.2 勾选规则

| 匹配结果 | 勾选是否可用 | 勾选后动作 |
| --- | --- | --- |
| 无候选 | 不展示 | 无 |
| 唯一已有药品 | 可用 | `.bindExisting(medicineBoxID)` |
| 无已有药品 | 可用 | `.createNew` |
| 同名多条 | 选择目标前不可用 | 选择后 `.bindExisting(medicineBoxID)` |
| 加载失败 | 不可用或允许仅保存处方 | 不执行药箱动作 |

### 6.3 编辑候选

“编辑候选”用于修改将要加入药箱的候选信息，例如：

1. 药品名称。
2. 规格。
3. 总数量。
4. 单位。
5. 有效期。
6. 备注。

编辑后需要重新匹配家庭药箱：

```text
编辑候选保存
  -> 更新 editedCandidate
  -> 用 editedCandidate 重新匹配 familyMedicineBoxes
  -> 重置 confirmation，要求用户重新勾选
```

避免用户在修改药品名/规格后沿用旧的匹配确认。

### 6.4 已有药品绑定字段

匹配已有药品并经用户确认后，需要在最终保存 payload 中表达“该用药计划绑定已有药箱药品”。字段名定为 Swift `medicineBoxID` / JSON `medicine_box_id`。

```swift
medicineBoxID: Int?
```

语义：

1. `medicineBoxID != nil`：用药计划绑定已有药品；提交时剥离 `medicineBox`。
2. `medicineBoxID == nil && medicineBox != nil`：用户确认新建药箱药品；提交时保留 `medicineBox`。
3. `medicineBoxID == nil && medicineBox == nil`：不处理药箱，只保存用药计划。

该字段只表达用户确认后的绑定结果，不能由匹配算法静默写入；多条同名时必须由用户选择目标后才写入。

命名原因：

1. 服务端 `MedicationPlan` 模型已有 `medicine_box` 外键，数据库和接口语义天然对应 `medicine_box_id`。
2. 现有查询、回执和过滤已使用 `medicine_box_id`，继续沿用可以减少特殊分支。
3. `medicine_box` 保留给“新建药箱药品”的嵌套对象；`medicine_box_id` 表达“绑定已有药箱药品”，两者互斥且清晰。
4. 不使用 `existing_medicine_box_id`，避免和模型字段产生重复概念。

## 7. 提交流程设计

### 7.1 提交时只决定是否剥离 medicineBox

本工单最新流程：点击提交时，客户端不再额外调用“更新库存”或“新建药箱”接口，而是只根据用户确认状态决定每条用药计划在处方批量保存 payload 中如何表达药箱关系。

保存前生成一个“按确认状态处理药箱候选后的处方数组”：

```swift
let prescriptionDraftsForSave = batches.resolvingMedicineBoxCandidates(
    confirmations: medicineCandidateConfirmations
)
```

处理规则：

| 状态 | medicineBox | 已有药品 ID | 结果 |
| --- | --- | --- | --- |
| 无候选 | 无 | 无 | 正常保存用药计划 |
| 有候选但未勾选 | 剥离 | 无 | 只保存处方和用药计划，不处理药箱 |
| 勾选 + 匹配已有药品 | 剥离 | 携带 `medicineBoxID` | 用药计划绑定已有药品；库存是否修改由用户在 `MedicineBoxFormView` 中单独处理 |
| 勾选 + 无已有药品 | 保留 | 无 | `PrescriptionBatchWorkflowSaveView` 内部创建药箱药品 |
| 同名多条但未选择目标 | 剥离或阻止勾选 | 无 | 不允许静默绑定第一条 |

说明：

1. 客户端提交流程内不单独调用 `SparkMedicalWorkflowAPI` 更新库存。
2. 客户端提交流程内不单独调用药箱创建接口。
3. 匹配已有药品时，处方提交只负责绑定已有药品 ID；不从识别草稿推断或生成任何库存变更。
4. 新建药箱药品继续使用 `PrescriptionBatchWorkflowSaveView` 当前对 `medicineBox` 的创建能力。
5. 绑定已有药品、新建药箱药品都由 `PrescriptionBatchWorkflowSaveView` 在一次批量保存事务内处理，客户端不拆分调用。

### 7.2 用户未确认

```text
用户未勾选
  -> 保存处方 payload 剥离 medicineBox
  -> 不绑定已有药品
  -> 不更新库存
  -> 不新建药箱
```

### 7.3 用户确认，匹配已有药品

```text
用户勾选 + 已选择 medicineBoxID
  -> 弹窗询问是否需要更新该药品库存信息
  -> 如果选择是：sheet 打开 MedicineBoxFormView 服务端编辑页，用户直接保存药箱修改
  -> 如果选择否：仅保留绑定确认状态
  -> 保存处方 payload 剥离 medicineBox
  -> 用药计划 payload 携带 medicineBoxID
  -> PrescriptionBatchWorkflowSaveView 保存用药计划时绑定已有药品
```

要求：

1. 使用已有药品 ID。
2. 该条用药计划下的 `medicineBox` 必须剥离，避免重复创建药箱。
3. 如果当前 `PrescriptionBatchWorkflowSaveView` 不支持“用药计划绑定已有药品”，需要扩展请求模型，例如给 `MedicationPlanRecognitionDraft` / payload 增加关联药品字段：

```swift
medicineBoxID: Int?
```

4. 处方批量保存只负责绑定已有药品，不负责根据识别草稿自动修改库存。
5. 用户是否修改库存、单位、有效期等信息，完全交给 `MedicineBoxFormView` 服务端编辑页处理；不使用本次识别草稿中的 `totalQuantity`、`doseUnit` 等字段自动覆盖已有药品。
6. 进入 `MedicineBoxFormView` 后，保存动作直接更新服务器上的药箱药品；该动作与后续处方批量保存解耦。
7. 如果用户打开编辑页后取消或保存失败，仍保留“绑定已有药品”的勾选状态，但不改变服务端药箱库存。

### 7.4 用户确认，无已有药品

```text
用户勾选 + createNew
  -> 保存处方 payload 不剥离 medicineBox
  -> PrescriptionBatchWorkflowSaveView 内部使用 medicineBox 创建药箱药品
```

新建要求：

1. member 使用当前 `selectedMemberID`。
2. 数据使用用户确认后的候选。
3. 不额外调用药箱创建接口。
4. 如果用户未勾选，仍然剥离 `medicineBox`，不创建药箱。
5. 附件归属沿用现有保存规则，不为新建药箱额外增加附件处理流程。

### 7.5 操作顺序

推荐顺序：

```text
勾选已有药品候选
  -> 弹窗询问是否更新该药品库存信息
  -> 是：打开 MedicineBoxFormView，用户按服务端当前数据编辑并保存
  -> 否：只确认绑定

点击提交
  -> 本地预校验处方/用药计划
  -> 校验药箱候选确认状态
  -> 根据确认状态生成处方批量保存 payload
       - 未确认：剥离 medicineBox
       - 确认已有药品：剥离 medicineBox + 携带已有药品 ID
       - 确认新建药箱：保留 medicineBox
  -> 调用 PrescriptionBatchWorkflowSaveView / 处方批量保存接口
  -> 展示保存回执
```

提交流程内不再拆成“先保存处方、再单独处理药箱动作”。药箱相关动作统一由处方批量保存接口根据 payload 一次处理。

### 7.6 失败处理

因为药箱处理并入处方批量保存流程，第一期按一次提交结果处理，且必须在 `PrescriptionBatchWorkflowSaveView` 内使用同一个事务：

1. 保存成功：展示处方、用药计划、绑定已有药品、新建药箱等回执。
2. 保存失败：整体失败并回滚，保留草稿，展示错误，允许用户修复后再次提交。
3. 不设计“绑定药箱失败但处方成功”的部分成功态。
4. 客户端提交流程内不单独调用绑定已有药品或新建药箱接口，因此不存在客户端侧药箱动作重试。

## 8. 接口设计

### 8.1 查询家庭药箱

使用：

```swift
MedicalQueryAPI.listFamilyMedicineCabinet(memberID:)
```

### 8.2 处方批量保存接口扩展

用户确认药箱候选后，统一通过处方批量保存接口处理：

```text
POST /api/v1/medical/workflows/prescriptions/batch-save/
```

服务端位置：

```text
SparkService/medical/urls.py:86-87
PrescriptionBatchWorkflowSaveView
```

接口需要支持两类药箱表达：

1. **绑定已有药品**：用药计划 payload 携带已有药品 ID，字段为 `medicine_box_id`。
2. **新建药箱药品**：用药计划 payload 携带 `medicine_box` 对象，沿用当前 `PrescriptionBatchWorkflowSaveView` 内部创建药箱能力。

如果现有接口不支持“用药计划绑定已有药品”，需要补充服务端和客户端请求字段。

事务要求：

1. 处方、用药计划、绑定已有药品、新建药箱必须在 `PrescriptionBatchWorkflowSaveView` 内一个事务完成。
2. 任一环节失败，服务端整体回滚并返回失败。
3. 客户端不在提交流程内单独调用“绑定已有药品”或“新建药箱”接口。

### 8.3 已有药品库存编辑交互

已有药品的库存、单位、有效期等信息不通过本次识别草稿自动计算和更新，而是由用户进入药箱服务端编辑页自行确认。

要求：

1. 不由客户端在提交流程中单独调用库存更新接口。
2. 用户勾选匹配已有药品后，弹窗询问是否需要更新该药品库存信息。
3. 选择“是”时，sheet 打开 `MedicineBoxFormView`，传入匹配到的服务端药箱药品，使用服务端编辑模式。
4. 用户在 `MedicineBoxFormView` 内看到服务端当前库存、单位、有效期等字段，自行判断是否更新。
5. `MedicineBoxFormView` 的保存直接调用现有药箱编辑接口更新服务器；处方批量保存不再负责已有药品库存变更。
6. 选择“否”时，不打开编辑页，只保留绑定已有药品的确认状态。
7. 本次识别草稿中的候选数量、单位只作为展示参考，不作为已有药品库存更新来源。

### 8.4 新建药箱药品

用户确认“添加到药箱，提交后新建”时：

1. 客户端保留该条用药计划下的 `medicineBox`。
2. 不额外调用药箱创建接口。
3. `PrescriptionBatchWorkflowSaveView` 按现有逻辑创建药箱药品，并绑定用药计划。
4. 创建成功后可把新药箱 ID 展示在回执中。
5. 新建药箱默认归属当前 `selectedMemberID`。

### 8.5 附件归属

药品附件归属沿用现有保存规则，不因本工单额外改造：

1. 不新增附件绑定规则。
2. 不为新建药箱或绑定已有药品单独增加附件处理流程。
3. 处方、用药计划、药箱之间的附件关联以现有服务端保存逻辑为准。

## 9. 涉及文件

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `PrescriptionRecognitionResultContentView.swift` | 加载家庭药箱；维护候选匹配和确认状态；切换成员重新加载和匹配；勾选已有药品时弹窗询问是否打开药箱编辑页；提交时按确认状态决定剥离/保留 medicineBox 和绑定已有药品 ID | 核心状态与流程 |
| `PrescriptionResultSections.swift` | 增加识别概览区和药箱候选卡；每条药品显示候选匹配、勾选、目标选择、编辑候选；勾选动作回调到结果页触发库存编辑询问 | UI 展示 |
| `MedicineBoxFormView.swift` | 复用服务端编辑模式，用于用户确认是否修改已有药品库存、单位、有效期等信息 | 已有药品编辑 |
| `MedicalQueryAPI.swift` | 复用 `listFamilyMedicineCabinet(memberID:)` | 家庭药箱加载 |
| `SparkMedicalWorkflowAPI.swift` | 补齐处方批量保存 payload 中 `medicine_box_id` / 保留 `medicineBox` 新建药箱的请求字段 | 保存接口 |
| `DefaultTypedMedicalDocumentSaver.swift` | 处方保存前按确认状态剥离或保留 `medicineBox`；已有药品场景携带 `medicineBoxID` | 保存编排 |
| `PrescriptionRecognitionDraftMapper.swift` | 增加按确认状态生成保存草稿、剥离 medicineBox、注入 `medicineBoxID` 的辅助方法 | 降低 View 复杂度 |
| `SparkService/medical/views.py` | `PrescriptionBatchWorkflowSaveView` 支持绑定已有药品；保留 medicineBox 时创建新药箱 | 服务端保存能力 |
| `Localizable.strings` | 增加识别概览、药箱候选、匹配结果、确认勾选、错误提示文案 | 本地化 |

## 10. 验收标准

1. 进入处方识别结果页后，根据 `selectedMemberID` 调用一次家庭药箱接口。
2. 切换成员后，重新调用家庭药箱接口并重新匹配候选。
3. 识别概览区统计处方数、药品数、药箱候选数、待确认数、已匹配数、可新建数。
4. 无 `medicineBox` 候选的药品不展示药箱候选卡。
5. 有候选且唯一匹配已有药品时，展示当前库存和提交时绑定已有药品说明。
6. 有候选且无已有药品时，展示提交后新建药箱药品说明。
7. 同名命中多条时，必须选择目标药品后才能勾选确认。
8. 同名命中多条但未选择目标、未勾选时，允许提交处方，默认不绑定药箱、不新建药箱。
9. 未勾选确认时，提交不会绑定已有药品，不会更新库存，不会新建药箱，处方保存 payload 不带该条 `medicineBox`。
10. 勾选确认且匹配已有药品时，弹窗询问是否需要更新该药品库存信息。
11. 用户选择“是”时，sheet 打开 `MedicineBoxFormView` 服务端编辑页；用户提交后直接更新服务器药箱数据。
12. 用户选择“否”时，不打开 `MedicineBoxFormView`，只确认提交时绑定已有药品。
13. 勾选确认且匹配已有药品时，处方保存 payload 不带该条 `medicineBox`，但携带目标已有药品 ID；保存后用药计划绑定该药品。
14. 已有药品库存、单位不使用识别草稿自动更新，必须以服务端药箱编辑页为准。
15. 勾选确认且无已有药品时，处方保存 payload 保留该条 `medicineBox`，由 `PrescriptionBatchWorkflowSaveView` 创建新药箱药品，并绑定当前成员。
16. 批量保存中处方、用药计划、绑定已有药品、新建药箱必须同事务完成；失败时整体回滚。
17. 编辑候选后重新匹配，旧确认状态失效。
18. 切换成员后清空所有勾选状态，并基于新成员家庭药箱重新匹配。
19. 家庭药箱加载失败时，仍可保存处方，但不能执行药箱确认动作。
20. 保存成功回执展示处方数、用药计划数、绑定已有药品数、新建药箱数。

## 11. 已确认规则汇总

1. 已有药品绑定字段名：Swift 使用 `medicineBoxID`，JSON payload 使用 `medicine_box_id`。
2. `medicine_box` 保留给新建药箱药品的嵌套对象；`medicine_box_id` 表达绑定已有药箱药品。
3. 服务端事务：处方、用药计划、绑定已有药品、新建药箱必须在 `PrescriptionBatchWorkflowSaveView` 内一个事务完成。
4. 提交流程内不单独调用绑定或新建药箱接口。
5. 附件归属沿用现有规则，不额外改造。
6. 匹配规则只按名称匹配，不考虑规格、剂型、单位、别名。
7. 公共药品允许客户端打开编辑页，是否允许更新由服务端现有规则控制。
8. 切换成员后清空所有勾选状态。
9. 不需要“忽略该药箱候选”按钮。
10. 新建药箱绑定当前 `selectedMemberID`。
11. 多候选未选择目标且未勾选时，允许提交处方，默认不绑定药箱、不新建药箱。
12. 待确认统计包含所有有候选但未勾选的药品，多候选未选择目标也计入。
13. 保存回执需要展示处方数、用药计划数、绑定已有药品数、新建药箱数。

## 12. 风险与注意事项

1. 不能让未确认的 `medicineBox` 进入处方保存 payload，否则会绕过用户确认。
2. 同名多条不能静默选择第一条，这是高风险医疗数据合并错误。
3. 匹配规则必须可解释，第一期宁可少匹配，也不要误匹配。
4. 切换成员必须重新加载和重新匹配，避免把 A 成员药箱库存更新到 B 成员。
5. 已确认新建药箱时必须保留 `medicineBox`，否则 `PrescriptionBatchWorkflowSaveView` 无法创建新药箱。
6. 已确认绑定已有药品时必须剥离 `medicineBox`，否则可能同时绑定旧药品又新建药箱。
7. 已有药品库存、单位、有效期等信息必须以服务端药箱编辑页为准，不能用本次识别草稿自动覆盖。
8. 打开 `MedicineBoxFormView` 编辑已有药品和后续处方批量保存是两个动作，UI 需要避免让用户误以为“勾选即自动增加库存”。
9. 处方批量保存必须保持事务一致性，不能出现处方保存成功但药箱绑定或新建失败的半成功状态。

## 工单 `MEDICAL-AI-OCR-000010`：处方识别保存前检查点补全

### 工单状态

修复需求/待实现。

## 1. 问题背景

处方识别结果页提交时，已经进入处方批量保存接口：

```text
POST /api/v1/medical/workflows/prescriptions/batch-save/
```

但客户端保存前检查点没有拦住处方状态枚举错误，导致服务端返回 400。

典型请求片段：

```json
{
  "institution_name": "东部战区总医院",
  "prescribed_at": "2025-06-27",
  "status": "普通"
}
```

新的失败样例中，客户端把支付状态写入了处方生命周期 `status`：

```json
{
  "institution_name": "东部战区总医院",
  "prescribed_at": "2025-06-27",
  "status": "paid"
}
```

典型服务端错误：

```json
{
  "code": -1,
  "msg": {
    "status": ["\"普通\" is not a valid choice."]
  },
  "data": null
}
```

服务端处方状态只允许：

```text
active
completed
cancelled
```

AI 识别把处方类型、处方属性或支付状态误填到了 `status`，客户端没有在提交前归一化或预校验，导致可预知错误进入网络层。

000007 已补 `dose_value` 数值校验，但实际保存链路还需要更完整的处方检查点，覆盖服务端模型和序列化器的主要约束。

## 2. 修复目标

新增“处方识别保存前检查点”机制，在真正发起处方批量保存请求之前，对处方数组和内部用药计划执行完整检查。

目标：

1. 保存前拦截处方 `status` 非法值，例如 `普通`。
2. 保存前拦截用药计划 `status` 非法值。
3. 保存前拦截 `frequencyType` 与 `everyNDays / weeklyWeekdays` 不匹配。
4. 保存前拦截日期格式错误和结束日期早于开始日期。
5. 保存前拦截 `doseValue` 非数字，复用 000007。
6. 保存前识别明显异常但服务端未必会拦截的高风险剂量，提示用户确认。
7. 保存前检查 `medicineBoxID` 与 `medicineBox` 二选一表达，避免同一条药品同时绑定已有药箱又新建药箱。
8. 保存前检查 `reminderTimes` 结构，避免时间格式或对象结构错误。
9. 检查失败时不发网络请求，展示本地预校验错误并定位。
10. 对可安全归一化的字段，在抽取后或保存 payload 生成前统一归一化，不把 AI 原始脏值直传服务端。
11. 不新增 `Prescription` 服务端字段，不新增支付状态字段，不把 `paid` 等支付信息作为结构化字段保存。
12. 客户端 payload 只提交服务端已支持的处方生命周期状态：`active`、`completed`、`cancelled`。
13. 客户端处方状态选择项与服务端保持完全一致，只保留 `active`、`completed`、`cancelled`，取消其他所有状态选项。

## 3. 检查点分层

### 3.1 抽取后归一化检查点

位置：

```text
DefaultTypedMedicalDocumentExtractor
  -> normalizedPrescriptionDrafts
  -> normalizedMedicationPlanDrafts
```

职责：

1. 把空 `medicationPlans` 归一化为 `[]`。
2. 补齐 `sortOrder`。
3. 处方 `status` 非法时，不保留 AI 原始值。
4. 用药计划 `status` 非法时，默认归一化为 `active`。
5. `frequencyType` 空值归一化为 `daily`。
6. 明显属于处方类型、处方类别的文本，例如 `普通`、`门诊`、`急诊`，不要写入 `status`，状态默认归一化为 `active`。
7. 明显属于支付状态的文本，例如 `paid`、`已支付`、`未支付`，不要写入 `status`，状态默认归一化为 `active`；第一期不保存支付状态结构化字段。

推荐规则：

```text
prescription.status in active/completed/cancelled -> 保留
prescription.status 为空 -> active
prescription.status 为 普通/门诊/急诊/医保/自费 -> status=active
prescription.status 为 paid/已支付/未支付/待支付 -> status=active
prescription.status 其他非法值 -> 清空或 active，并生成 debug 诊断
```

说明：

1. 抽取后归一化用于减少明显 AI 脏值。
2. 归一化不能吞掉高风险字段，仍需要保存前预校验兜底。

### 3.2 结果页提交前预校验检查点

位置：

```text
MedicalDocumentUploadViewModel.saveResult()
  -> MedicalPreSubmitValidator.validate(...)
```

职责：

1. 校验用户当前编辑后的草稿。
2. 发现阻断错误时写入 `preSubmitValidationIssues`。
3. 结果页顶部展示错误摘要。
4. 处方/药品卡片高亮。
5. 点击错误后展开并滚动到对应位置。
6. 校验失败不进入 Saver。

这是用户可感知的主要检查点。

### 3.3 网络前 payload preflight 检查点

位置：

```text
DefaultTypedMedicalDocumentSaver
  -> buildPrescriptionBatchSavePayload / buildPrescriptionCreateRequests
  -> preflightValidatePrescriptionPayload
  -> API request
```

职责：

1. 检查最终 JSON payload 是否仍包含服务端不接受的值。
2. 避免 ViewModel 或 UI 漏同步导致旧脏数据进入网络层。
3. 作为最后一道本地保护：失败时抛出本地错误，不发请求。

要求：

1. preflight 失败错误要能转换为 `MedicalPreSubmitValidationIssue` 或至少映射成用户可理解错误。
2. 不能只 `assert` 或只打日志。
3. 不允许“明知服务端会 400 还继续请求”。

## 4. 需要补全的规则

### 4.1 处方状态 `prescription.status`

服务端合法值：

```text
active
completed
cancelled
```

非法示例：

```text
普通
门诊
急诊
有效
已开具
paid
已支付
未支付
```

处理策略：

1. 抽取后归一化：`普通/门诊/急诊` 不作为 status，默认 `active`。
2. 抽取后归一化：`paid/已支付/未支付/待支付` 不作为 status，默认 `active`；不新增支付状态字段。
3. 提交前预校验：如果仍然不是合法值，阻断提交。
4. UI 提示：`处方状态不合法，请选择生效中、已完成或已取消。`

客户端状态选项：

| 保存值 | 展示文案 | 含义 |
| --- | --- | --- |
| `active` | 生效中 | 当前处方仍有效或默认保存状态 |
| `completed` | 已完成 | 处方相关用药或处理已完成 |
| `cancelled` | 已取消 | 处方被取消或不再执行 |

客户端必须取消的状态选项：

```text
普通
门诊
急诊
有效
已开具
paid
已支付
未支付
待支付
```

说明：

1. `普通/门诊/急诊` 属于处方类型，不允许作为 `status` 提交；本期不新增处方类型字段。
2. `paid/已支付/未支付/待支付` 属于支付状态，不允许作为 `status` 提交；本期不新增支付状态字段。
3. 结果页、详情页草稿模式、编辑页、保存前校验、payload 生成都必须使用同一组状态定义，不能各自维护一套状态列表。
4. 如需保留 AI 原始文本，仅可作为本地调试信息或非结构化备注候选，不进入 `Prescription` 新字段。

字段路径：

```text
prescriptions[n].status
```

### 4.1.1 服务端字段边界

本工单不改服务端 `Prescription` 模型，不新增字段。

明确不做：

1. 不新增 `prescription_type`。
2. 不新增 `payment_status`。
3. 不新增支付状态枚举。
4. 不改处方保存接口字段契约。
5. 不为了兼容 AI 脏值放宽服务端 `Prescription.status` choices。

处理原则：

1. 服务端 `Prescription.status` 仍是唯一生命周期状态字段。
2. 客户端提交前必须把 `status` 归一化为 `active/completed/cancelled` 之一。
3. `普通/门诊/急诊/paid/已支付/未支付` 等识别文本只能用于本地判断和提示，不能进入保存 payload。
4. 如果后续产品明确需要保存处方类型或支付状态，应另开工单重新评估服务端模型、历史数据和展示入口。

### 4.2 用药计划状态 `medicationPlans.status`

服务端合法值：

```text
active
paused
completed
cancelled
```

处理策略：

1. 空值默认 `active`。
2. 中文 `执行中/生效/有效` 可归一化为 `active`。
3. 其他非法值提交前阻断。

字段路径：

```text
prescriptions[n].medicationPlans[m].status
```

### 4.3 频次类型与联动字段

服务端合法 `frequency_type`：

```text
daily
every_n_days
weekly
```

规则：

1. `frequencyType = daily`：`everyNDays` 可为空，`weeklyWeekdays` 可为空。
2. `frequencyType = every_n_days`：`everyNDays` 必填，且 `1...365`。
3. `frequencyType = weekly`：`weeklyWeekdays` 必须非空，且每项是 `1...7` 的整数。
4. 非法 `frequencyType` 提交前阻断，不直接发服务端。

字段路径：

```text
prescriptions[n].medicationPlans[m].frequencyType
prescriptions[n].medicationPlans[m].everyNDays
prescriptions[n].medicationPlans[m].weeklyWeekdays
```

### 4.4 日期字段

需要检查：

```text
prescriptions[n].prescribedAt
prescriptions[n].medicationPlans[m].startDate
prescriptions[n].medicationPlans[m].endDate
prescriptions[n].medicationPlans[m].medicineBox.expireDate
```

规则：

1. 日期必须是 `yyyy-MM-dd`。
2. `endDate >= startDate`。
3. 空 `prescribedAt` 可允许。
4. `startDate` 如果服务端必填，客户端保存 payload 生成前必须有默认值或阻断。

### 4.5 剂量数值与异常剂量

复用 000007：

1. `doseValue` 非空时必须是纯数字。
2. `dosePerTime` 可保留 `1片`、`1滴`、`半片` 等文本。

新增高风险提示：

1. `doseUnit = 片/粒/袋/滴` 且 `doseValue > 20` 时，标记为高风险，需要用户确认。
2. 如日志中的 `doseValue = 93`、`dosePerTime = 93片`，服务端可能能保存，但业务上明显异常，应进入“风险确认”或阻断提交。
3. 第一阶段建议作为阻断错误：提示用户编辑确认；后续可做“确认无误后继续”。

字段路径：

```text
prescriptions[n].medicationPlans[m].doseValue
prescriptions[n].medicationPlans[m].dosePerTime
```

### 4.6 提醒时间 `reminderTimes`

规则：

1. 必须是对象数组。
2. 每项必须包含 `time`。
3. `time` 必须是 `HH:mm`。
4. `dose` 如果存在，必须是数字。
5. 空数组允许。

字段路径：

```text
prescriptions[n].medicationPlans[m].reminderTimes
```

### 4.7 药箱表达 `medicineBoxID` / `medicineBox`

规则：

1. 绑定已有药品：只传 `medicineBoxID`，不传 `medicineBox`。
2. 新建药箱：只传 `medicineBox`，不传 `medicineBoxID`。
3. 未确认药箱候选：两者都不传。
4. 同一条药品不能同时传 `medicineBoxID` 和 `medicineBox`。
5. `medicineBoxID` 必须来自当前成员或家庭药箱可访问范围。

字段路径：

```text
prescriptions[n].medicationPlans[m].medicineBoxID
prescriptions[n].medicationPlans[m].medicineBox
```

## 5. UI 与用户交互

### 5.1 错误摘要

顶部错误摘要需要支持处方检查点错误：

```text
第 1 张处方：处方状态“普通”不合法
第 1 张处方第 2 个药品：单次剂量 93片 疑似异常，请编辑确认
```

### 5.2 卡片高亮

1. 处方级错误高亮处方卡片。
2. 药品级错误高亮药品卡片。
3. 药箱候选错误高亮候选确认区域。
4. 点击错误摘要滚动到具体卡片。

### 5.3 自动修复与人工修复

可以自动修复：

1. `status = 普通/门诊/急诊` -> `active`，原文放入 `extra`。
2. 空 `frequencyType` -> `daily`。
3. 空 `medicationPlan.status` -> `active`。

必须人工确认：

1. `doseValue = 93` 且 `doseUnit = 片`。
2. `endDate < startDate`。
3. `weekly` 但没有星期。
4. 同一条药品同时带 `medicineBoxID` 和 `medicineBox`。

## 6. 涉及文件

| 文件 | 改动内容 | 影响 |
| --- | --- | --- |
| `DefaultTypedMedicalDocumentExtractor.swift` | 抽取后归一化处方/用药状态、频次默认值，保留原始异常文本到 extra | 降低 AI 脏值进入结果页 |
| `MedicalPreSubmitValidator.swift` | 增加处方保存前检查点规则：status、frequency、date、dose、reminderTimes、medicineBox 表达 | 保存前阻断 |
| `DefaultTypedMedicalDocumentSaver.swift` | 增加 payload preflight，最终发请求前再次检查服务端不可接受字段 | 网络前兜底 |
| `MedicalDocumentTypedModels.swift` | 不新增处方类型/支付状态字段；确认 `status` 仅承载 `active/completed/cancelled` | 模型收敛 |
| `SparkMedicalWorkflowAPI.swift` / 批量保存 payload | 不新增 `prescription_type/payment_status`；payload 只提交服务端既有字段 | 客户端请求 |
| `PrescriptionRecognitionResultContentView.swift` | 展示检查点错误、同步编辑后重新校验 | UI 状态 |
| `PrescriptionResultSections.swift` | 处方卡、药品卡、药箱候选区域展示检查点错误；处方状态选择项只保留 `active/completed/cancelled` | UI 定位 |
| `MedicationPrescriptionDetailPage.swift` / 处方编辑入口 | 草稿预览和本地编辑时复用同一组处方状态选项，取消其他状态 | 编辑一致性 |
| `Localizable.strings` | 增加处方状态、频次、日期、提醒、异常剂量、药箱表达错误文案 | 本地化 |
| `SparkService/medical/models.py` | 不改动 `Prescription` 字段；保持 `status` choices 不变 | 服务端边界 |
| `SparkService/medical/serializers.py` | 不放宽 `status` 校验，不新增支付状态字段 | 服务端 API |
| `SparkService/medical/views.py` | 不改接口契约；继续按既有字段保存 | 服务端保存流程 |

## 7. 验收标准

1. 处方 `status = "普通"` 时，点击提交不会请求 `/api/v1/medical/workflows/prescriptions/batch-save/`。
2. 处方 `status = "普通"` 可在抽取后归一化为 `active`，但不新增字段保存“普通”。
3. 处方 `status = "paid"` 可在抽取后归一化为 `active`，但不新增字段保存支付状态。
4. 客户端不向 batch-save / combined-create 发送 `prescription_type`、`payment_status`。
5. 服务端 `Prescription` 不新增字段，不新增迁移。
6. 如果保存前仍存在非法 status，顶部展示本地预校验错误，并高亮对应处方卡片。
7. 客户端处方状态选择器只展示 `active`、`completed`、`cancelled` 对应文案，不再展示 `普通/门诊/急诊/paid/已支付/未支付` 等选项。
8. 草稿详情、编辑页、结果页卡片内展示的处方状态文案来自同一份状态定义。
9. 用药计划非法 status 不发请求。
10. `frequencyType = every_n_days` 但 `everyNDays` 为空时不发请求。
11. `frequencyType = weekly` 但 `weeklyWeekdays` 为空或含非法值时不发请求。
12. `endDate < startDate` 时不发请求。
13. `reminderTimes = [{"time": ""}]` 或 `time = "8点"` 时不发请求。
14. 同一条药品同时带 `medicineBoxID` 和 `medicineBox` 时不发请求。
15. `doseValue = "20mg"` 继续由 000007 拦截。
16. `doseValue = "93"` 且 `doseUnit = "片"` 时提示高风险剂量，需要用户编辑确认或阻断。
17. 所有检查点通过后，才允许进入处方批量保存接口。
18. 服务端不再收到可由客户端检查点提前发现的 `status invalid choice` 请求。

## 8. 风险与注意事项

1. 检查点不能替代服务端校验，服务端仍是最终边界。
2. 自动归一化必须保留原始文本到 `extra`，避免丢失 OCR 事实。
3. 高风险剂量第一期建议阻断，后续如要支持“确认无误继续”，必须有明确确认状态写入草稿。
4. payload preflight 不能只打日志，必须阻断网络请求。
5. 检查点规则需要和服务端模型/Serializer 同步维护，新增服务端约束时要补客户端规则。
6. 客户端不能继续把 `paid`、`普通` 发送到 `status`，也不能通过新增临时字段绕过服务端模型边界。
7. 客户端不要为了展示方便再增加本地专用状态枚举；处方生命周期状态必须以服务端 `Prescription.Status` 为唯一来源。
