# AI 识别报告详设文档

> 范围说明：本文详细设计 SparkClient 医疗档案内 AI 文档识别、OCR、类型识别、结构化抽取、失败重试与结果修正流程。本文为详设文档，用于指导后续客户端实现；重点设计“结构化抽取失败后，继续识别时携带上次失败原因”的公共能力。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICAL-AI-OCR-000001` | 结构化抽取失败后继续识别需携带上次失败原因 | 已实现 | AI 识别报告、解码失败反馈、公共 Prompt 追加、本地化、继续识别流程 |
| `MEDICAL-AI-OCR-000002` | 解码失败自动重试与本地配置开关 | 已实现 | 仅解码失败带入失败原因、自动重试、通用设置、重试次数本地配置 |
| `MEDICAL-AI-OCR-000003` | 保存字段校验失败后的结果页纠错引导 | 设计中 | 服务端字段错误协议、客户端字段定位、结果页高亮、跳转对应编辑模块、重新提交 |

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
