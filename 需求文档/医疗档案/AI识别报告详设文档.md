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
| `MEDICAL-AI-OCR-000006` | 处方识别支持多笔处方全流程 | 设计中 | AI 返回 `[PrescriptionRecognitionDraft]`、结果页切换成员、多处方页面展示、预校验、附件关联、逐笔保存提交 |

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

## 工单 `MEDICAL-AI-OCR-000006`：处方识别支持多笔处方全流程

### 工单状态

设计中。

## 1. 背景与问题

当前独立处方识别链路整体仍以单笔处方为主：

1. `MedicalDocumentTypedResult.prescription` 关联值是 `PrescriptionRecognitionDraft`。
2. `DefaultTypedMedicalDocumentExtractor` 的处方抽取按单对象解码。
3. `PrescriptionRecognitionResultContentView` 内部状态是单个 `batch`，页面虽然复用了 `PrescriptionBatchListSectionView(batches:)`，但实际只传入 `[batch]`。
4. `DefaultTypedMedicalDocumentSaver.savePrescriptionWithPlans` 一次只保存一笔处方。

真实处方照片、PDF 或多页资料里，经常会出现同一次上传包含多张处方单、多名医生处方、门诊处方与续方混在一起的情况。如果仍强制识别成单笔，会导致：

1. AI 把多张处方合并到一张处方内，诊断、开方日期、医生、处方号互相污染。
2. 多个处方下的药品被塞进同一个药品列表，保存后无法还原真实业务归属。
3. 用户在结果页只能编辑一个处方头信息，无法分别修正每笔处方。
4. 保存提交只能生成一条处方记录，后续用药计划、附件、问报告引用都会失真。

本工单要求处方识别从 AI 抽取、页面展示、用户编辑、预校验、附件关联到保存提交全流程支持多笔处方，核心数据形态为：

```swift
[PrescriptionRecognitionDraft]
```

## 2. 设计目标

### 核心目标

独立处方识别结果应允许一次上传识别出 0 到 N 笔处方，结果页支持像体检报告结果页一样切换保存归属成员；每笔处方都有自己的处方头信息、药品列表、附件关联、预校验结果和保存结果。

### 第一期目标

1. 处方抽取 Prompt 明确要求返回 JSON 数组。
2. 处方抽取解码目标改为 `[PrescriptionRecognitionDraft]`。
3. `MedicalDocumentTypedResult.prescription` 改为承载 `[PrescriptionRecognitionDraft]`。
4. 结果页状态从单个 `batch` 改为 `batches: [PrescriptionRecognitionDraft]`。
5. 页面复用现有 `PrescriptionBatchListSectionView` 展示多笔处方。
6. 结果页支持切换成员，交互方式参考体检报告结果页。
7. 每笔处方支持编辑处方头信息、编辑药品、管理处方附件、管理药品附件。
8. 点击提交前对所有处方和药品执行本地预校验。
9. 校验失败时复用 000003/000004 的字段高亮、折叠展开、滚动定位能力。
10. 保存提交时按处方逐笔调用现有保存接口，并记录所有保存成功的处方 ID。

### 非目标

1. 不新增服务端批量保存接口，第一期客户端串行或受控并发逐笔保存。
2. 不改变病例文档内 `CaseRecognitionDraft.prescriptions` 的已有数组结构。
3. 不把多笔处方强行合并成一个处方。
4. 不新增独立的多处方编辑页面，优先复用现有详情/编辑组件。
5. 不改变药品字段、用药计划字段和服务端 payload 字段语义。

## 3. 数据模型调整

### 3.1 Typed Result

目标结构：

```swift
enum MedicalDocumentTypedResult: Sendable, Equatable {
    case caseDocument(CaseRecognitionDraft)
    case healthExamReport(HealthExamRecognitionDraft)
    case medicalReport([MedicalReportRecognitionDraft])
    case prescription([PrescriptionRecognitionDraft])
    case medicationPlan([MedicationPlanRecognitionDraft])
    case medicineBoxes([MedicineBoxRecognitionDraft])
}
```

### 3.2 兼容策略

为降低改动风险，需要提供兼容入口：

1. 新识别结果统一写入 `.prescription([PrescriptionRecognitionDraft])`。
2. 如果历史调试数据、预览数据或对话结构化卡片仍传入单个 `PrescriptionRecognitionDraft`，在边界层包装成数组。
3. 解码 AI 输出时优先按数组解码；如确实存在旧模型返回单对象，可在第一期保留 fallback：单对象解码成功后包装成单元素数组，并在 normalized JSON 中转成数组格式。
4. UI 和保存层只消费数组，不在页面内继续维护“单笔处方特例”。

### 3.3 空结果

如果 AI 判断没有处方：

```json
[]
```

客户端展示空态：提示未识别到处方，可返回重新上传或手动补充，不自动创建空处方提交。

## 4. AI 抽取要求

### Prompt 要求

处方抽取场景需要明确：

1. 返回 JSON array only。
2. 每个数组元素是一笔独立处方。
3. 如果同一份资料中出现多张处方、多个处方号、多个开方日期或多个医生，应拆成多笔。
4. 每笔处方内只包含属于该处方的药品列表。
5. 不确定归属的药品可以放入最可能的处方，并在 `extra` 中标记低置信度说明。
6. 无法识别处方时返回 `[]`，不要返回空对象。

### 解码目标

```swift
let final = try await extractStructured(
    prompt: prompt,
    scenario: .prescriptionExtraction,
    kindLabel: "prescription",
    as: [PrescriptionRecognitionDraft].self,
    preferredModelName: preferredModelName,
    cancellationToken: cancellationToken
)
```

解码后统一执行：

1. `normalizedPrescriptionDraft(_:)` 对数组逐项处理。
2. 去除完全空白的处方草稿。
3. 保留含有有效药品但处方头为空的草稿，让用户在页面修正。
4. `extractedJSON` 标准化为数组 JSON，方便调试和后续重试反馈。

## 5. 结果页 UI 设计

### 页面状态

从：

```swift
@State private var batch: PrescriptionRecognitionDraft
```

调整为：

```swift
@State private var batches: [PrescriptionRecognitionDraft]
@State private var selectedMemberID: Int?
```

`selectedMemberID` 初始值使用 `output.envelope.memberID`，用户在结果页切换成员后同步更新。

### 页面结构

1. 顶部继续展示成员确认区域，并支持切换成员。
2. 处方内容区展示多笔处方列表。
3. 每笔处方卡片显示序号，例如“处方 1/3”。
4. 卡片摘要展示机构、医生、开方日期、诊断、处方号。
5. 每笔处方下展示该处方的药品列表。
6. 每笔处方支持进入处方详情编辑。
7. 每个药品支持进入药品详情编辑。
8. 未关联附件区域继续展示未匹配到处方或药品的源文件。

现有 `PrescriptionBatchListSectionView` 已接收：

```swift
let batches: [PrescriptionRecognitionDraft]
```

因此页面层应优先复用它，不再新建一套多处方列表组件。

### 成员切换

处方结果页成员切换需要参考体检报告结果页：

```swift
HealthExamMemberSectionView(
    memberContextStore: memberContextStore,
    selectedMemberID: selectedMemberID,
    draft: draft,
    onSelectMember: mode.isEditable ? { memberID in
        selectedMemberID = memberID
        viewModel?.updateResultMemberID(memberID)
    } : nil
)
```

处方页对应要求：

1. `PrescriptionRecognitionResultContentView` 持有 `selectedMemberID`。
2. 成员确认区域改造为可切换形态，复用 `MemberProfileBindingMenu`。
3. 切换成员后调用 `viewModel.updateResultMemberID(memberID)`，保证 `typedOutput.envelope.memberID` 和页面状态一致。
4. `detailNavigationContext`、处方详情预览、药品详情预览使用当前 `selectedMemberID`。
5. 保存提交使用当前 `selectedMemberID`，不能继续使用初始 `output.envelope.memberID`。
6. 如果当前没有可选成员或用户清空成员，提交按钮应禁用或预校验提示“请选择成员”。

建议新增或改造：

```swift
struct PrescriptionMemberConfirmSectionView: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    var onSelectMember: ((Int?) -> Void)?
}
```

展示样式、菜单触发区域、未选择文案与 `HealthExamMemberSectionView` 保持一致，避免不同报告结果页交互割裂。

### 编辑回写

处方编辑回写需要带 `batchIndex`：

```swift
case batch(index: Int, draft: PrescriptionRecognitionDraft)
case medication(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft)
```

回写规则：

1. 编辑处方头：替换 `batches[batchIndex]`。
2. 编辑药品：替换 `batches[batchIndex].medicationPlans[itemIndex]`。
3. 删除药品后，如果该处方没有任何有效信息，页面可保留空处方让用户继续编辑，不自动删除。
4. 删除处方需要二次确认，第一期可不做删除能力，只支持编辑修正。

## 6. 附件关联

多处方后附件关联不能再基于单个 `batch`。

### 关联规则

1. 处方级附件：写入对应 `batches[batchIndex].attachmentFileIds`。
2. 药品级附件：写入对应 `batches[batchIndex].medicationPlans[itemIndex].attachmentFileIds`。
3. `unlinkedAttachments` 需要聚合所有处方和药品已关联的附件 ID 后再求差集。
4. 附件管理 sheet 的 target 需要包含 `batchIndex`。

建议结构：

```swift
enum PrescriptionAttachmentTarget: Identifiable {
    case batch(index: Int)
    case medication(batchIndex: Int, itemIndex: Int)
}
```

## 7. 预校验与定位

多处方必须复用 000003/000004 的校验和定位能力。

### 校验范围

提交前遍历所有处方：

```text
prescriptions[n].prescribed_at
prescriptions[n].medication_plans[m].drug_name
prescriptions[n].medication_plans[m].start_date
prescriptions[n].medication_plans[m].frequency_type
```

### 定位要求

1. `MedicalPreSubmitValidationIssue` 必须携带处方 index 和药品 index。
2. 滚动 ID 必须包含 `batchIndex` 和 `itemIndex`。
3. 多笔处方下第 2 笔第 1 个药品错误时，不能滚动到第 1 笔第 1 个药品。
4. 错误处方卡片折叠时，点击提交需要自动展开该处方区域并滚动到错误字段。
5. 顶部错误摘要点击某条错误，也应定位到对应处方/药品。

000004 已对多处方定位 ID 做了要求，本工单需要在独立处方结果页真正接入数组状态后验证。

## 8. 保存提交编排

### 保存策略

第一期不新增批量接口，客户端逐笔保存：

```text
for draft in batches:
    savePrescriptionWithPlans(selectedMemberID, draft, envelope, now)
```

保存前必须确认 `selectedMemberID` 有值，并已同步到 `viewModel.updateResultMemberID(selectedMemberID)`。

建议串行保存，原因：

1. 用户一次识别的处方数量通常不大。
2. 串行更容易处理部分成功、失败提示和日志定位。
3. 不需要服务端保证批量事务。

### 部分成功处理

保存过程中可能出现第 1 笔成功、第 2 笔失败：

1. 保存成功的处方 ID 需要记录到回执里。
2. 失败时提示“已保存 n 笔，m 笔失败”，保留页面草稿，允许用户修正后重新提交。
3. 已成功保存的处方再次提交前需要有保护策略，避免重复创建。第一期建议保存成功后禁用整页再次提交，失败场景再按具体保存结果设计重试。

### 回执设计

当前 `MedicalDocumentSaveReceipt` 只有单个 `recordID` 时，需要扩展或新增多记录回执能力：

```swift
struct MedicalDocumentSaveReceipt {
    let recordID: Int
    let savedRecordIDs: [Int]
    let savedAt: Date
    let isSuccess: Bool
}
```

如果不想立刻改公共回执结构，处方保存层可以先用 `recordID = firstSavedID`，并在 `extra`/新增展示模型里保存全部 ID；但长期建议公共回执支持多 ID，因为医疗报告、药箱、多处方都存在多记录保存场景。

## 9. 涉及文件

| 文件 | 改动 |
| --- | --- |
| `MedicalDocumentTypedModels.swift` | `MedicalDocumentTypedResult.prescription` 从单个 draft 改为 `[PrescriptionRecognitionDraft]` |
| `DefaultTypedMedicalDocumentExtractor.swift` | 处方抽取按数组解码，单对象 fallback 包装为数组，normalized JSON 输出数组 |
| `MedicalDocumentUploadViewModel.swift` | 更新 typed result 更新、保存前预校验、调试预览和错误处理中的处方数组分支 |
| `PrescriptionRecognitionResultContentView.swift` | 页面状态改为 `batches`，增加 `selectedMemberID`，切换成员后同步 `updateResultMemberID`，提交前写回 `.prescription(batches)` |
| `PrescriptionResultSections.swift` | 复核多处方展示、编辑、附件、定位 ID，改造成员确认区支持 `MemberProfileBindingMenu` |
| `PrescriptionRecognitionResultSupport.swift` | 编辑器状态增加 `batchIndex` |
| `MedicalPreSubmitValidator.swift` | 独立处方页按 `[PrescriptionRecognitionDraft]` 校验 |
| `MedicalPreSubmitValidationIssue.swift` | 确认 issue 字段路径、scrollTargetID 支持 `prescriptions[n]` |
| `DefaultTypedMedicalDocumentSaver.swift` | 新增或调整多处方保存编排，逐笔调用现有保存方法 |
| `MedicalDocumentSaveReceipt` 相关文件 | 如需要，支持多记录 ID 回执展示 |
| `PrescriptionRecognitionResultView` Preview | 预览数据改为多笔处方，覆盖 2 笔处方、多药品场景 |

## 10. 兼容影响

### 对病例识别的影响

病例识别内 `CaseRecognitionDraft.prescriptions` 已经是数组，不需要改变语义。但如果共用处方卡片、编辑弹窗或校验逻辑，需要确保独立处方页和病例页都传入正确的 `batchIndex`。

### 对对话结构化卡片的影响

对话内保存处方卡片如果当前仍是单个 `PrescriptionRecognitionDraft`，第一期不强制改为多卡片。但进入识别结果页时需要在边界层包装为单元素数组，避免编译期和运行期断裂。

### 对已保存数据的影响

本工单不涉及 CoreData 迁移或服务端历史数据迁移。因为识别结果页是临时草稿态，保存后仍落到既有处方和用药计划资源。

## 11. 验收标准

1. AI 返回两个处方对象时，结果页展示两张处方卡片。
2. 结果页顶部成员区域可切换成员，交互与体检报告结果页一致。
3. 切换成员后，详情预览和保存提交均使用新成员 ID。
4. 每张处方卡片展示自己的机构、医生、日期、诊断、处方号和药品列表。
5. 编辑第 2 笔处方头信息后，不影响第 1 笔处方。
6. 编辑第 2 笔第 1 个药品后，不影响其他处方药品。
7. 附件可分别关联到处方级和药品级，未关联附件区域显示正确。
8. 第 2 笔处方存在校验错误时，提交后自动展开并滚动到第 2 笔对应字段。
9. 保存提交后，服务端在当前选中成员下生成多条处方记录及对应用药计划。
10. 保存成功回执能展示或至少记录所有保存成功的处方 ID。
11. AI 返回单对象旧格式时，客户端可兼容包装成单笔数组展示。
12. AI 返回 `[]` 时，页面展示空态，不允许提交空处方。

## 12. 风险与注意事项

1. 不要只改 UI 为数组，Extractor 和 Saver 仍然单笔，否则会形成“看起来支持多笔，实际只保存第一笔”的假支持。
2. 不要把多笔处方合并成一个 `PrescriptionRecognitionDraft`，这会破坏处方号、开方日期和药品归属。
3. 滚动定位 ID 必须包含处方 index，避免多处方下定位错位。
4. 成员切换后保存不能继续读取旧的 `output.envelope.memberID`，否则会保存到错误成员。
5. 切换成员后详情预览也要使用新成员 ID，否则页面看到的是新成员但详情里还是旧成员。
6. 保存逐笔执行时要明确部分成功策略，避免重复提交造成重复处方。
7. Prompt 改为数组后，需要继续保留 000001/000002 的解码失败反馈和自动重试能力。
