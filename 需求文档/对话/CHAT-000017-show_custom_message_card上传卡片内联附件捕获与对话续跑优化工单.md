# CHAT-000017 show_custom_message_card 上传卡片内联附件捕获与对话续跑优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000017 |
| 工单类型 | P1 Chat 工具交互 / 上传卡片 / 附件捕获 / AI 对话续跑 |
| 当前范围 | 只创建需求与技术方案工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 工具入口 | `show_custom_message_card` |
| 创建日期 | 2026-08-11 |
| 触发问题 | 当前上传/拍照卡片只负责打开相机、相册或文件选择，选中附件后进入 Composer 预览区，需要用户再次发送；AI 本轮工具调用已经结束，无法像问答或选择成员一样在用户补充材料后继续同一轮对话 |
| 核心目标 | 将 `show_custom_message_card` 从“展示入口卡片”升级为“阻塞式附件捕获工具交互”：用户在卡片内选择照片、拍照或文件后，卡片自身展示附件预览与处理状态，附件上传 OSS、压缩/抽取后作为工具结果返回 AI，本轮对话继续生成 |

## 1. 一句话结论

可以实现，而且项目现有架构已经具备主要基础：`ToolInteractionCoordinator` 已支持类似 `ask_user_question`、成员选择的 continuation 式等待恢复；`MessageRunActor` 和 `ToolSideEffectBlockMapper` 已支持工具副作用写入消息卡片；Chat 附件链路已有 OSS 上传、OCR、图片压缩、消息附件组装能力。

但这不是简单改 UI。正确方案应把 `show_custom_message_card` 改造成一种新的工具交互类型，而不是继续把用户选择的文件塞进 Composer 预览区。

## 2. 当前流程梳理

### 2.1 AI 调用工具

工具 schema 定义在：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift
```

当前 `show_custom_message_card` 只接收一个必填参数：

```text
card_type = report_photo / medicine_box_photo / skin_photo
```

其中：

1. `report_photo`：报告/PDF 上传卡片。
2. `medicine_box_photo`：药盒照片卡片。
3. `skin_photo`：皮肤照片卡片。

### 2.2 ToolHub 执行器

关键代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubShowCustomMessageCard.swift
```

当前行为：

```text
1. 读取 invocation.arguments["card_type"]。
2. 校验能否转成 ChatCaptureCardType。
3. 构造 ChatCaptureMessageCardPayload(cardType: type)。
4. 返回 ToolExecutionResult(..., shouldBypassModel: true, sideEffects: [.captureCard(payload)])。
```

这里的本质是“工具执行完成并产生 UI 副作用”。它没有等待用户上传，也没有把上传结果返回给 AI。

### 2.3 副作用落入消息 block

关键代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/ToolSideEffectBlockMapper.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/MessageRunActor.swift
```

当前 `.captureCard(payload)` 会被映射为：

```text
ChatMessageBlock(kind: .captureCard, captureMessageCard: payload)
```

并作为 assistant 消息内的工具展示块写入数据库。

### 2.4 卡片渲染

关键代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatCaptureMessageCards.swift
```

当前 `.captureCard` 渲染为 `ChatCaptureTypeMessageCard`。卡片显示标题、提示、示例和操作按钮。

### 2.5 用户点击按钮后的现状

关键代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ChatConversationMessageRow.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/Composer/HanlinChatInputView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift
```

当前行为：

```text
卡片点击拍照
  -> stateStore.setCameraPresented(true)
  -> Composer 侧 fullScreenCover 打开相机
  -> 选择完成后 onAttachmentsPicked
  -> detailViewModel.enqueueComposerAttachments
  -> 附件进入 Composer 预览区

卡片点击上传照片
  -> stateStore.setPhotoPickerPresented(true)
  -> Composer 侧 sheet 打开相册
  -> 选择完成后 onAttachmentsPicked
  -> 附件进入 Composer 预览区

卡片点击选择文件
  -> showCaptureFileImporter = true
  -> fileImporter 选择文件
  -> detailViewModel.enqueueComposerAttachments
  -> 附件进入 Composer 预览区
```

这条流程的关键问题是：选择文件后，附件归属 Composer 草稿，不归属消息内那张上传卡片；AI 本轮已经结束，后续必须由用户再次点发送发起新一轮。

## 3. 目标流程

目标不是“卡片帮用户打开上传入口”，而是“卡片成为本轮工具调用的等待态 UI”。

```text
AI 调用 show_custom_message_card(card_type=report_photo)
  -> ToolHub 创建附件捕获 prompt
  -> ToolInteractionCoordinator 挂起当前工具调用 continuation
  -> MessageRunActor 在 assistant 消息内插入 captureCard pending block
  -> 用户在卡片内选择照片 / 拍照 / 文件
  -> 选中文件不进入 Composer 预览区
  -> captureCard block 切换为 processing 样式并展示所选附件预览
  -> 上传 OSS
  -> 上传成功后对图片走 AI 压缩，对 PDF/文件走文本抽取或文件上下文组装
  -> 生成 ToolAttachmentCaptureResult
  -> continuation resume
  -> ToolHub 返回工具结果给 AI
  -> AI 基于上传材料继续同一轮回答
  -> captureCard block 切换为 completed 样式
```

用户感知上应类似：

```text
AI：请上传报告
[上传报告卡片：拍照 / 上传照片 / 选择文件]
用户选择 report.pdf
[卡片：report.pdf 上传中 42%]
[卡片：report.pdf 已上传，正在压缩/识别]
AI：我看到了这份报告，下面帮你解读...
```

## 4. 强边界

1. 本工单只梳理流程和技术方案，不实现代码。
2. 用户通过上传卡片选择的附件不再进入 Composer 附件预览区。
3. 上传卡片必须在原消息内展示附件预览、上传进度、处理状态和失败重试入口。
4. `show_custom_message_card` 必须能像 `ask_user_question` / `request_member_selection` 一样等待用户操作后恢复工具调用。
5. 不新增第二套 AI Runtime；应复用 `ToolInteractionCoordinator`、`MessageRunActor`、`ToolSideEffectBlockMapper` 的架构。
6. 不复用 DeepTutorChat 类型；可以参考 DeepTutorChat 的体验，但 Chat 模块必须使用 Chat 自己的 Domain/ViewModel/View。
7. OSS 上传必须在工具结果返回 AI 前完成。
8. 图片进入 AI 前必须走现有压缩策略，避免原图直接进入模型。
9. 卡片内捕获的附件应绑定到对应 `toolCallID`，不能跨消息、跨工具调用污染。

## 5. 关键技术可行性

### 5.1 continuation 式等待恢复：可行

现有 `ToolInteractionCoordinator` 已有类似机制：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionCoordinator.swift
```

当前已支持：

```text
1. requestQuestionAnswer
2. requestMemberSelection
3. requestConsentDecision
4. requestInlineQuestionAnswer
5. requestInlineMemberSelection
```

实现上已经有：

```text
CheckedContinuation<InteractionResult<ToolQuestionAnswer>, Never>
CheckedContinuation<InteractionResult<Int>, Never>
inlineQuestionContinuations
inlineMemberContinuations
inlineCardSink
```

因此可以新增同类能力：

```text
requestAttachmentCapture(...)
inlineAttachmentCaptureContinuations
presentInlineAttachmentCaptureCard(...)
completeInlineAttachmentCapture(...)
```

### 5.2 消息内卡片落库：可行

现有工具副作用已能写入消息 block：

```text
ToolSideEffect.captureCard
  -> ToolSideEffectBlockMapper.blocks(...)
  -> ChatMessageBlock(kind: .captureCard)
  -> MessageRunActor.submitRichBlocks(...)
```

目标方案需要把一次性 `captureCard` 扩展成可更新状态的 block：

```text
pending
selected
uploading
uploaded
processing
completed
failed
cancelled
```

技术上可通过现有 `repository.upsertMessageBlock` 更新同一个 block。

### 5.3 OSS 上传：可行

现有 Chat 附件预处理已经使用：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift
```

关键能力：

```text
fileTransferService.upload(ManagedFileUploadPayload(...))
stateStore.setComposerAttachmentUploadProgress(...)
ChatPreparedAttachment
```

新流程不应复用 Composer state，但可以复用上传服务和组装逻辑。建议抽取 Chat 专属附件处理服务，避免卡片流程依赖 Composer。

### 5.4 图片压缩后丢给 AI：可行

现有发送链路已经有图片压缩能力：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/ChatAIImageCompressor.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift
```

目标流程应复用同一压缩策略：

```text
原始图片 / 文件
  -> OSS 上传并生成 ManagedFileRecord
  -> 图片压缩为 AI 输入版本
  -> 构造工具结果中的 attachment context
  -> 返回给模型继续生成
```

注意：OSS 上传保存的是原始材料或业务所需材料；AI 输入可使用压缩图或 OCR 文本，不应把大图原样塞给模型。

### 5.5 使用项目对话中已有组件：可行，但需要轻度抽取

可直接参考/复用的能力：

```text
ChatCaptureTypeMessageCard 的视觉基础
ChatComposerAttachmentPreview 的附件草稿模型思想
ChatComposerPhotoLibraryLoader 的相册数据加载
ChatComposerAttachmentImporter 的文件导入
FilePreviewInput / 现有附件预览视图的展示能力
ChatFileAttachmentBlockView / imageGallery / fileAttachments 的局部展示样式
```

但需要注意：很多 Composer 预览 UI 当前是输入区私有语义，不适合原样塞到消息卡片里。建议抽取一个更通用的卡片附件预览子组件，例如：

```text
ChatInlineAttachmentPreviewStrip
ChatInlineAttachmentPreviewItem
ChatInlineAttachmentProcessingBadge
```

这类组件只负责展示附件缩略图、文件名、大小、进度、失败状态，不持有 Composer 草稿。

## 6. 建议目标模型

### 6.1 工具交互 prompt

建议新增 Chat 专属 prompt：

```swift
nonisolated struct ToolAttachmentCapturePrompt: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let cardType: ChatCaptureCardType
    let title: String
    let subtitle: String
    let allowedSources: [ToolAttachmentCaptureSource]
    let allowedContentTypes: [String]
    let maxFileCount: Int
    let maxFileSizeBytes: Int
}
```

### 6.2 卡片 payload

现有 payload 只有：

```swift
struct ChatCaptureMessageCardPayload {
    let cardType: ChatCaptureCardType
}
```

目标 payload 需要能表达状态：

```swift
nonisolated struct ChatCaptureMessageCardPayload: Codable, Equatable, Sendable {
    let id: UUID
    let cardType: ChatCaptureCardType
    let sourceToolCallID: String?
    var status: ChatCaptureCardStatus
    var selectedAttachments: [ChatInlineCapturedAttachment]
    var errorMessage: String?
    var resultSummary: String?
}
```

状态建议：

```swift
enum ChatCaptureCardStatus: String, Codable, Sendable {
    case pending
    case selected
    case uploading
    case uploaded
    case processing
    case completed
    case failed
    case cancelled
}
```

### 6.3 工具结果

建议新增：

```swift
nonisolated struct ToolAttachmentCaptureResult: Codable, Equatable, Sendable {
    let cardType: ChatCaptureCardType
    let attachments: [ToolCapturedAttachmentResult]
    let modelContextText: String
}
```

每个附件结果至少包含：

```text
previewID
fileName
mimeType
fileId / objectKey / publicURL
ocrText
compressedImagePayload 或 compressedImageURL
sizeBytes
source: camera / photoLibrary / document
```

## 7. 目标架构改造点

### 7.1 ToolInteractionCoordinator 新增附件捕获交互

建议新增：

```text
QueuedCompletion.attachmentCapture
PendingOutcome.attachmentCapture
inlineAttachmentCaptureContinuations
requestAttachmentCapture(...)
requestInlineAttachmentCapture(...)
completeInlineAttachmentCapture(...)
cancelInlineAttachmentCapture(...)
```

它的职责只负责等待用户结果，不负责上传、压缩、OCR。

### 7.2 ChatInlineToolInteractionCardSink 新增方法

当前 sink 支持 question/member/healthResource/consent。建议新增：

```swift
func presentInlineAttachmentCaptureCard(
    threadID: UUID?,
    prompt: ToolAttachmentCapturePrompt,
    completionID: UUID,
    toolCallID: String?
) async -> Bool
```

由 ChatDetailViewModel 或已有 inline card sink 实现负责把 pending card 写入消息。

### 7.3 ToolHubShowCustomMessageCard 改为等待型工具

当前：

```text
runShowCustomMessageCard
  -> sideEffects: [.captureCard(payload)]
  -> shouldBypassModel: true
  -> 工具结束
```

目标：

```text
runShowCustomMessageCard
  -> 构造 ToolAttachmentCapturePrompt
  -> await toolInteractionCoordinator.requestAttachmentCapture(...)
  -> 用户上传成功后返回 ToolAttachmentCaptureResult
  -> ToolExecutionResult.outputText 包含附件摘要与 OCR/压缩上下文
  -> AI 继续本轮生成
```

取消或失败时：

```text
1. 用户取消：返回 isAwaitingUserInput=true 或明确取消结果，让 AI 用自然语言继续引导。
2. 上传失败：卡片停留 failed，可重试；不应把失败附件返回给 AI。
3. 文件不支持：卡片显示错误，并允许重新选择。
```

### 7.4 新增卡片附件处理服务

不要把 Composer 的 `enqueueComposerAttachments` 直接用于卡片流程。建议新增服务：

```text
ChatInlineAttachmentCaptureProcessor
```

职责：

```text
1. 接收用户选择的本地附件。
2. 更新 captureCard block 为 selected/uploading/processing。
3. 调用 FileTransferService 上传 OSS。
4. 对图片执行压缩。
5. 对图片/PDF/文件执行 OCR 或文本抽取。
6. 生成 ToolAttachmentCaptureResult。
7. 更新 captureCard block 为 completed。
8. resume ToolInteractionCoordinator continuation。
```

### 7.5 UI 层改造

`ChatCaptureTypeMessageCard` 需要从静态入口卡片变成状态卡片：

```text
pending:
  展示原来的说明、示例、拍照/上传照片/选择文件按钮

selected/uploading:
  展示用户选择的缩略图/文件名/进度条
  按钮变为取消/重选

processing:
  展示“正在处理图片/文件”

completed:
  展示已上传附件摘要，可查看预览
  不再显示主操作按钮

failed:
  展示失败原因，提供重试/重新选择
```

文件选择能力：

```text
report_photo:
  camera + photoLibrary + files

medicine_box_photo:
  camera + photoLibrary

skin_photo:
  camera + photoLibrary
```

## 8. 与 Composer 附件流程的关系

本工单必须把两条链路拆清楚：

```text
Composer 普通附件:
  用户主动添加附件
  -> Composer 预览区
  -> 用户点击发送
  -> 新的一轮用户消息

show_custom_message_card 附件:
  AI 工具要求用户补材料
  -> 消息内卡片选择附件
  -> 卡片内预览与上传
  -> 工具 continuation 恢复
  -> 同一轮 assistant 继续回答
```

因此：

1. 卡片附件不能调用 `detailViewModel.enqueueComposerAttachments`。
2. 卡片附件不应出现在输入框上方预览区。
3. 卡片附件应该成为 assistant 工具交互 block 的一部分。
4. 后续 AI 继续回答时，用户不需要再点发送。

## 9. 对 AI 上下文的要求

工具结果返回 AI 时，应包含足够明确的上下文：

```text
【用户已上传材料】
类型：report_photo
文件：
1. report.pdf
   - MIME: application/pdf
   - OSS file_id: ...
   - OCR/抽取文本：...
2. image.jpg
   - MIME: image/jpeg
   - OSS file_id: ...
   - AI 压缩图：已附加/已生成
   - OCR 文本：...

请基于以上材料继续完成用户原始请求。
```

如果模型支持多模态，应把压缩后的图片作为模型输入；如果不支持，则至少返回 OCR 文本和文件摘要。

## 10. 需要重点检查的现有代码

### 工具定义与执行

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubShowCustomMessageCard.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift
```

### 工具交互与 continuation

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionCoordinator.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionSnapshot.swift
```

### 消息 block 与副作用落库

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Domain/ChatMessage/BlockPayloads/ChatCaptureMessageCardPayload.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/ToolSideEffectBlockMapper.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/MessageRunActor.swift
```

### 卡片渲染与列表

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatCaptureMessageCards.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ChatConversationMessageRow.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIConversationView.swift
```

### 附件导入、上传、OCR、压缩

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerAttachmentImporter.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatPhotoLibraryPickerSupport.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/ChatAIImageCompressor.swift
```

## 11. 分阶段实施建议

### Phase 1：只做架构底座

1. 新增附件捕获 prompt/result/status 模型。
2. 扩展 `ToolInteractionCoordinator`，支持附件捕获 continuation。
3. 扩展 inline card sink，能插入 pending capture card。
4. `show_custom_message_card` 改为等待型工具，但先只返回模拟结果或取消结果。

验收重点：AI 调用工具后能挂起，卡片提交后能恢复工具调用。

### Phase 2：卡片内选择与预览

1. 卡片按钮直接驱动卡片附件选择流程。
2. 选择结果不进入 Composer。
3. 卡片内展示图片缩略图、PDF/文件名、大小、来源。
4. 支持取消、重选、失败状态。

验收重点：Composer 预览区保持空，卡片状态正确更新。

### Phase 3：OSS 上传与处理

1. 新增 `ChatInlineAttachmentCaptureProcessor`。
2. 接入 `FileTransferService.upload`。
3. 接入上传进度。
4. 图片接入压缩。
5. PDF/文件接入文本抽取或 OCR。
6. 成功后生成 `ToolAttachmentCaptureResult`。

验收重点：OSS 上传成功后才 resume continuation。

### Phase 4：AI 续跑与异常闭环

1. 工具结果携带附件摘要、OCR 文本、压缩图上下文。
2. AI 在同一轮继续回答。
3. 用户取消、上传失败、文件过大、类型不支持都有明确 UI 和工具结果语义。
4. 刷新页面或重载消息时，卡片状态不丢失。

验收重点：用户不点发送，AI 仍能在上传完成后继续输出。

## 12. 风险与注意事项

1. **continuation 泄漏风险**：用户离开页面、切线程、取消生成时，必须取消并 resume 对应 continuation。
2. **消息 block 幂等风险**：同一个 `toolCallID` 对应的 capture card 需要稳定 block id，避免重复插卡。
3. **上传任务生命周期风险**：卡片上传任务不应依赖 Composer 生命周期，但要随当前工具调用取消。
4. **多架构列表一致性风险**：UIKit 列表和 SwiftUI 列表都要接入同样的卡片命令。
5. **AI 输入大小风险**：图片必须压缩，PDF/OCR 文本要限长，避免上下文爆炸。
6. **隐私与敏感数据风险**：上传报告、药盒、皮肤照片属于敏感医疗材料，工具结果进入模型前要沿用现有外部模型/工具 consent 策略。
7. **历史消息兼容风险**：旧版 `ChatCaptureMessageCardPayload(cardType)` 已落库，新增字段要有默认值，保证旧消息可解码。
8. **用户体验风险**：卡片 processing 时间较长时，要有明确状态和取消入口，否则用户会误以为卡住。

## 13. 验收标准

1. AI 调用 `show_custom_message_card(card_type=report_photo)` 后，对话内出现上传报告卡片。
2. 用户从卡片选择照片、拍照或文件后，附件不进入 Composer 预览区。
3. 上传卡片自身切换为附件预览与进度样式。
4. 附件成功上传 OSS 后，图片走压缩，PDF/文件走文本抽取或可用上下文组装。
5. 工具 continuation 恢复，AI 在同一轮继续回答，不需要用户手动发送。
6. 用户取消选择时，卡片显示取消态或恢复待选择态，AI 不编造材料内容。
7. 上传失败时，卡片显示失败原因并支持重试或重新选择。
8. 关闭并重新进入会话后，已完成/失败/取消的卡片状态可正确恢复。
9. UIKit 会话列表和 SwiftUI 会话列表行为一致。
10. 旧历史消息中的 capture card 不崩溃、不丢失。

## 14. 最终判断

这条优化是可实现的，并且方向正确。它会让 `show_custom_message_card` 从“入口提示卡片”升级成真正的“工具等待用户补充材料”的交互节点，体验上会明显接近问答卡片和成员选择卡片。

推荐不要走“选完附件自动点发送”的捷径。那样虽然短期容易，但会产生新的用户消息和新一轮 AI 请求，无法表达“这是当前工具调用缺少的材料”。更稳的路线是把附件捕获纳入 `ToolInteractionCoordinator` 的 continuation 体系，让上传卡片成为工具调用的一部分。
