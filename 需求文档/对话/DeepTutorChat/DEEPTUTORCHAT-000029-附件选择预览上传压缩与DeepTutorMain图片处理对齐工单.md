# DEEPTUTORCHAT-000029 附件选择、预览上传、图片压缩与 DeepTutorMain 图片处理对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000029 |
| 工单类型 | P1 附件能力接入 + Composer 预览区 + AI 多模态图片处理对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| iOS 入口文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerToolbarView.swift` |
| 公共文件组件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentFilePickerMenu.swift` |
| iOS 对标流程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| Web 对标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | DeepTutorChat Composer 的附件按钮未接入，缺少附件选择、预览、上传、发送、AI 压缩处理完整链路 |
| 关联工单 | `DEEPTUTORCHAT-000019`、`DEEPTUTORCHAT-000021`、`DEEPTUTORCHAT-000022`、`DEEPTUTORCHAT-000028` |

## 1. 本工单目标

为 DeepTutorChat 补齐附件能力，但实现方式必须对齐项目已有能力和 DeepTutor Web 架构：

```text
1. 点击 DeepTutorChat 输入区回形针按钮后，使用项目公共添加文件组件。
2. 支持图片、拍照、PDF/文件选择。
3. Composer 内需要有附件预览区，选中后先展示，不直接发送。
4. 预览区支持上传，上传成功后才允许带附件发送。
5. 发送给 AI 前，图片必须走项目已有压缩链路，避免原图直接进入模型。
6. 附件必须进入 DeepTutor 消息数据模型、本地数据库、requestSnapshot 和重试/重新生成链路。
7. AI 对图片附件的处理需参考 DeepTutor-main：附件作为本轮 start_turn 的一部分，而不是拆成额外消息。
```

这不是“把回形针按钮打开”这么小的改动，而是给 DeepTutorChat 接上一条完整的附件草稿状态机。

## 2. 当前问题

### 2.1 DeepTutorChat 回形针仍是 placeholder

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerToolbarView.swift
```

当前 `paperclip` 按钮使用的是 placeholder：

```swift
placeholderButton(systemName: "paperclip")
```

`placeholderButton` 当前为空 action 且禁用：

```swift
Button(action: {}) { ... }
.disabled(true)
.opacity(0.55)
```

现状问题：

```text
1. 用户无法选择附件。
2. 无法拍照、选择相册图片或选择 PDF。
3. 无附件草稿态。
4. 无上传进度。
5. 无发送前预览。
6. 无附件进入 AI 请求。
```

### 2.2 DeepTutorChat 已有附件模型，但没有 Composer 接入链路

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift
```

当前已有附件模型：

```swift
nonisolated struct DeepTutorAttachment: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var type: String
    var filename: String?
    var mimeType: String?
    var localPath: String?
    var previewURL: String?
    var generated: Bool
}
```

当前也已有引用展示入口：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerReferenceBandView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorContextReferenceTreeView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorUserBubble.swift
```

但目前缺少：

```text
1. 从文件选择组件生成 DeepTutorAttachment 草稿的转换器。
2. 草稿附件与已上传附件的状态区分。
3. 附件预览区 UI。
4. 附件上传服务调用。
5. 发送时附件组包。
6. AI 图片压缩与多模态输入。
```

### 2.3 Composer 发送条件没有考虑附件

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerCardView.swift
```

当前 `canSend` 只看文本：

```swift
private var canSend: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
}
```

需要改成：

```text
1. 有文本可以发送。
2. 无文本但有已上传成功附件也可以发送。
3. 附件还在上传中不能发送。
4. 附件上传失败不能发送，除非用户删除失败附件或重新上传成功。
5. DeepTutor-main 中如果只有图片附件，会自动补默认提示文本；iOS 也需要有同等策略。
```

## 3. iOS 现有能力对标

### 3.1 公共文件组件能力

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentFilePickerMenu.swift
```

现有能力：

```text
1. Camera：通过 CustomCameraFullScreenView 拍照。
2. Photos：通过 PhotosPicker 选择相册图片。
3. Files：通过 fileImporter 选择文件。
4. allowedContentTypes 当前覆盖 image 与 pdf。
5. 输出统一为 [MedicalUploadLocalFile]。
```

DeepTutorChat 要求：

```text
1. DeepTutorComposerToolbarView 的 paperclip 不再使用 disabled placeholder。
2. paperclip 作为 MedicalDocumentFilePickerMenu 的 label。
3. 选择完成后通过 onFilesSelected 回调进入 DeepTutorChat 自己的 Composer 草稿态。
4. 不复制一套相册/拍照/fileImporter 逻辑。
```

### 3.2 Chat 现有附件草稿与预览流程

对标目录：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat
```

关键文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerDraft.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerAttachmentImporter.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift
```

Chat 已有草稿模型：

```swift
struct ChatComposerAttachmentPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: ChatComposerAttachmentSource
    let kind: ChatComposerAttachmentKind
    let data: Data
    let displayName: String
    let mimeType: String?
    let utTypeIdentifier: String?
}
```

Chat 已有附件阶段：

```swift
enum ChatComposerAttachmentPhase: String, Equatable, Sendable {
    case pending
    case uploading
    case ocring
    case success
    case failed
}
```

Chat 已有预览输入：

```swift
var previewInput: FilePreviewInput
```

Chat 已有发送模型：

```text
1. composerAttachments：本地草稿附件。
2. preparedAttachments：已预处理附件。
3. onImageUploadProgress：上传进度回调。
4. user message block：imageGallery / fileAttachments。
5. ChatAIImageCompressor：发送给 AI 前压缩图片。
```

DeepTutorChat 应复用这一套设计思想：

```text
1. 草稿态和消息态分离。
2. 本地预览和上传后 URL 分离。
3. 原图/原文件用于本地预览和落库附件，压缩图用于 AI 多模态输入。
4. 发送动作只消费已经完成准备的附件。
```

## 4. DeepTutor-main Web 对齐事实

### 4.1 Web Composer 附件草稿结构

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

Web 草稿附件结构：

```ts
interface PendingAttachment {
  type: string;
  filename: string;
  base64?: string;
  previewUrl?: string;
  size?: number;
  mimeType?: string;
}
```

Web 文件转附件逻辑：

```text
1. readFileAsDataUrl(file)。
2. extractBase64FromDataUrl(raw)。
3. image 文件 type=image。
4. 非图片文件 type=file。
5. 图片和 SVG 保留 previewUrl 供 UI 预览。
6. 发送时把 mimeType 映射为 mime_type。
```

Web 发送前附件 payload：

```ts
let extraAttachments = attachments.map((a) => ({
  type: a.type,
  filename: a.filename,
  base64: a.base64,
  mime_type: a.mimeType,
}));
```

只有图片附件且没有文本时，Web 会补默认提示：

```text
Please analyze the attached image(s).
```

### 4.2 Web UnifiedChatContext 将附件并入 start_turn

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx
```

关键事实：

```text
1. sendMessage 入参支持 attachments。
2. attachments 会进入 ADD_USER_MSG。
3. attachments 会进入 requestSnapshot。
4. attachments 会进入 start_turn WebSocket payload。
5. regenerate/replay 会从 requestSnapshot 恢复 attachments。
```

对齐要求：

```text
DeepTutorChat iOS 发送附件时，也必须让附件成为“本轮用户消息”的组成部分，而不是上传成功后另发一条系统消息或额外提示消息。
```

### 4.3 Web 后端附件处理

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py
```

后端处理流程：

```text
1. 从 payload.attachments 读取 type/url/base64/filename/mime_type/id。
2. 如果附件没有 url 且存在 base64，将原始 bytes 写入 AttachmentStore。
3. 写入成功后生成稳定 url。
4. 文档类附件进入 extract_documents_from_records 抽取文本。
5. 构造 UnifiedContext.attachments。
6. 持久化 message 时清掉 base64，只保留 url、filename、mime_type、id 等轻量字段。
7. requestSnapshot metadata 也保存附件信息。
```

DeepTutorChat iOS 应对齐这些语义：

```text
1. 本地数据库不要保存巨大 base64。
2. 本地消息保留附件元数据、localPath、previewURL 或远端 URL。
3. AI 请求可使用压缩后的 base64 或多模态 contentParts。
4. 重新生成时必须能从 requestSnapshot 找回附件。
```

## 5. 目标用户体验

### 5.1 Composer 初始态

```text
1. 回形针按钮可点击。
2. 图标样式保持当前 DeepTutorComposerToolbarView 的圆角胶囊工具栏风格。
3. 未选择附件时，Composer 与当前视觉保持一致。
4. 正在 streaming 时，如果当前产品策略禁止编辑，则回形针随发送按钮一起禁用。
```

### 5.2 点击回形针

点击后弹出公共文件选择菜单：

```text
1. 拍照。
2. 从相册选择。
3. 从文件选择。
```

组件必须使用：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentFilePickerMenu.swift
```

不允许：

```text
1. 在 DeepTutorChat 内复制一份 fileImporter。
2. 在 DeepTutorChat 内复制一份 PhotosPicker。
3. 在 DeepTutorChat 内自建拍照封装。
```

### 5.3 附件预览区

选择完成后，Composer 上方出现附件预览区。

位置建议：

```text
DeepTutorComposerCardView
├── DeepTutorComposerAttachmentPreviewBandView
├── DeepTutorComposerReferenceBandView
├── DeepTutorComposerTextView
└── DeepTutorComposerToolbarView
```

预览区 UI 细节：

```text
1. 位于输入文字区域上方，属于 Composer 卡片内部。
2. 背景使用 DeepTutorPalette.mutedSurface。
3. 底部有 1px 分割线，使用 DeepTutorPalette.mutedBorderColor。
4. 横向滚动排列附件卡片。
5. 图片显示缩略图。
6. PDF 显示 PDF 图标、文件名、大小。
7. 其他文件显示文件图标、文件名、MIME 或扩展名。
8. 每个卡片右上角有删除按钮。
9. 上传中显示进度环或进度条。
10. 上传失败显示错误状态与重试按钮。
11. 上传成功显示完成状态。
12. 点击附件卡片打开项目统一预览组件。
```

需要参考 Chat 现有预览能力：

```text
1. ChatComposerAttachmentThumbnail。
2. FilePreviewInput。
3. unifiedFilePreview。
4. composerDraft.attachments.map(\.previewInput)。
```

### 5.4 上传后才能发送

本工单要求“在预览区点上传成功之后可以发送”。

因此 DeepTutorChat 需要显式附件准备状态：

```text
localSelected
uploading
uploaded
failed
```

发送按钮规则：

```text
1. 没有文本且没有 uploaded 附件：禁用。
2. 有文本但存在 localSelected 附件：如果产品要求附件必须上传，则禁用并提示先上传。
3. 有 uploading 附件：禁用。
4. 有 failed 附件：禁用或要求删除失败附件后发送。
5. 所有附件 uploaded 且有文本或附件：允许发送。
```

发送成功后：

```text
1. 清空 text。
2. 清空 composer attachment drafts。
3. 重置 preview selection。
4. 收起键盘，沿用 DeepTutorChat 现有 composer_send 行为。
```

## 6. 数据模型设计

### 6.1 DeepTutor Composer 草稿附件

建议新增 DeepTutor 专用草稿模型，不直接把持久化模型当草稿态使用：

```swift
struct DeepTutorComposerAttachmentDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var source: DeepTutorComposerAttachmentSource
    var kind: DeepTutorComposerAttachmentKind
    var data: Data
    var displayName: String
    var mimeType: String?
    var utTypeIdentifier: String?
    var byteCount: Int
    var phase: DeepTutorComposerAttachmentPhase
    var uploadProgress: Double
    var uploaded: DeepTutorUploadedAttachment?
    var errorMessage: String?
}
```

建议阶段：

```swift
enum DeepTutorComposerAttachmentPhase: String, Equatable, Sendable {
    case localSelected
    case uploading
    case uploaded
    case failed
}
```

建议类型：

```swift
enum DeepTutorComposerAttachmentKind: String, Equatable, Sendable {
    case image
    case pdf
    case file
}
```

### 6.2 已上传附件

```swift
struct DeepTutorUploadedAttachment: Equatable, Sendable {
    var id: String
    var type: String
    var filename: String
    var mimeType: String?
    var localPath: String?
    var previewURL: String?
    var remoteURL: URL?
    var originalByteCount: Int
    var aiByteCount: Int?
}
```

### 6.3 requestSnapshot 需要扩展附件

当前：

```swift
nonisolated struct DeepTutorRequestSnapshot: Codable, Equatable, Sendable {
    var references: [DeepTutorContextReference]
    var capability: DeepTutorCapability?
    var enabledTools: [String]?
    var toolSnapshot: DeepTutorPerTurnToolSnapshot?
}
```

需要补充：

```swift
var attachments: [DeepTutorAttachment]
```

原因：

```text
1. 对齐 DeepTutor-main 的 MessageRequestSnapshot.attachments。
2. regenerate 时可以复用原始附件。
3. 本地数据库恢复时不会丢失本轮输入上下文。
4. Debug exporter 可以导出附件元数据。
```

### 6.4 DeepTutorAttachment 字段补充建议

当前字段：

```swift
var id: String
var type: String
var filename: String?
var mimeType: String?
var localPath: String?
var previewURL: String?
var generated: Bool
```

建议评估补充：

```text
1. remoteURL：上传后可访问地址或 OSS URL。
2. byteCount：原始文件大小。
3. aiByteCount：发送给 AI 的压缩后大小，仅图片有值。
4. extractedText：如果未来接 OCR/PDF 文本抽取，可落在这里。
5. uploadStatus 不建议进入消息持久化模型，只属于 Composer draft。
```

## 7. 上传与发送链路

### 7.1 选择链路

```text
DeepTutorComposerToolbarView
  -> MedicalDocumentFilePickerMenu
  -> [MedicalUploadLocalFile]
  -> DeepTutorComposerAttachmentMapper
  -> [DeepTutorComposerAttachmentDraft]
  -> DeepTutorComposerAttachmentPreviewBandView
```

转换器职责：

```text
1. 读取本地临时文件 Data。
2. 推断 UTType、mimeType、kind。
3. 生成稳定 UUID。
4. 记录 displayName、byteCount、localPath。
5. 初始 phase=localSelected。
```

### 7.2 上传链路

```text
用户点击预览区上传
  -> DeepTutorAttachmentUploadUseCase
  -> FileTransferService / 项目现有上传服务
  -> 更新 draft.phase/uploadProgress
  -> 成功写入 DeepTutorUploadedAttachment
  -> 失败写入 errorMessage
```

上传策略：

```text
1. 原始文件必须上传 OSS，用于历史消息预览、跨设备恢复和必要时的服务端读取。
2. 图片上传 OSS 不等于 AI 输入，AI 输入必须另走压缩。
3. PDF/文件上传成功后记录 remoteURL、objectKey、fileId、mimeType、filename。
4. 上传失败不能静默吞掉，必须在预览区可见。
5. 本地 localPath 只作为上传前预览和缓存命中使用，不得作为消息历史的唯一来源。
```

业务类型建议：

```text
1. 优先新增 deep_tutor_attachment businessType。
2. 如果后端/上传服务当前只接受 chat attachment 业务类型，需要在工单实现阶段确认是否复用 ChatSendAttachmentAssembly.chatAttachmentBusinessType。
3. 不建议用 medical_document 的业务类型混入 DeepTutorChat 普通对话附件。
```

### 7.3 OSS 上传硬性要求

DeepTutorChat 附件上传必须走项目已有 OSS 文件传输服务，不允许只保存本地临时路径。

核心代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/FileStorage/FileTransferService.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/OSS
```

现有 `FileTransferService.upload` 能力：

```text
1. 生成 fileUuid。
2. 计算文件 MD5。
3. 先保存本地缓存，失败后可重试。
4. 通过 SparkOSSConfigurationStore 获取 STS、bucket、endpoint、region。
5. 调用 OSSClientWrapper.putObject 直传 OSS。
6. 调用 SparkFileAPI.registerFile 登记文件。
7. 登记记录包含 filePath、objectKey、storageType=oss。
8. 可通过 publicHTTPSURLForObjectKey(objectKey) 拼接公网 HTTPS URL。
```

DeepTutorChat 上传成功后，附件模型必须至少记录：

```text
1. fileId：文件服务登记 ID。
2. fileUuid：文件 UUID。
3. objectKey：OSS object key。
4. remoteURL：publicHTTPSURLForObjectKey 生成的 HTTPS URL。
5. fullCacheKey：fileUuid/fileName，供后续本地缓存命中。
6. fileMd5：用于缓存校验和排查。
7. storageType：语义上为 oss。
```

对齐 Chat 附件缓存语义：

```text
ChatAttachment.makeFullCacheKey(fileUUID:fileName:)
ChatAttachment.sparkClientOSSFileUUIDAndFileName()
```

DeepTutorChat 需要提供等价能力：

```text
1. 能从 remoteURL 或 fullCacheKey 解析 fileUUID/fileName。
2. 消息内图片卡片优先命中本地缓存。
3. 缓存未命中时通过 fileTransferService.download 或 HTTPS URL 拉取。
4. 下载成功后写入 local cache，后续预览直接走缓存。
```

禁止方案：

```text
1. 只把图片 Data/base64 存到本地数据库。
2. 只保存 tmp localPath，App 重启后附件失效。
3. 上传到 OSS 后不登记 file_manager/file record。
4. 只给 AI 压缩图，不保存原附件的 OSS 记录。
```

### 7.4 图片压缩给 AI

必须复用项目通用压缩能力：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIImageCompressor.swift
```

现有压缩目标：

```swift
nonisolated static let defaultTargetByteCount = 1_048_576
```

现有 Chat 多模态链路：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift
```

当前 ChatOrchestrator 已有逻辑：

```text
1. deliverMultimodalImages=true 时，从附件读取本地缓存或 URL 图片字节。
2. sendsOriginalImagesToAI=false 时调用 ChatAIImageCompressor.compressForAI。
3. 把压缩后的 JPEG 转 base64。
4. 以 imageInlineJPEGBase64 形式放入 AI contentParts。
5. 非多模态路径则使用 LocalOCR 附件增强。
```

DeepTutorChat 要求：

```text
1. 不允许把原始大图默认直接给 AI。
2. 默认使用压缩图进入 AI。
3. 日志记录 originalBytes、aiBytes、targetBytes。
4. 用户或调试开关明确选择时，才允许 sendsOriginalImagesToAI。
5. 如果当前模型不支持多模态，需要降级为本地 OCR/文档文本上下文或明确提示暂不支持图片理解。
```

### 7.5 发送组包

DeepTutorChat iOS 需要对齐 Web 的 `start_turn.attachments` 语义。

建议 iOS 内部发送 payload：

```swift
struct DeepTutorOutgoingAttachment: Codable, Equatable, Sendable {
    var id: String
    var type: String
    var filename: String
    var base64: String?
    var url: String?
    var mimeType: String?
}
```

映射到 Web 语义：

```json
{
  "type": "image",
  "filename": "photo.jpg",
  "base64": "...",
  "url": "...",
  "mime_type": "image/jpeg"
}
```

发送文本规则：

```text
1. 有文本：使用用户输入文本。
2. 无文本但有图片：补默认提示“请分析附件图片。”，语义对齐 Web 的 Please analyze the attached image(s).
3. 无文本但有 PDF/文件：补默认提示“请阅读附件并回答。”。
4. 补全文案需要进入 requestSnapshot，保证重试一致。
```

### 7.6 OSS 附件与 AI 附件的双轨关系

DeepTutorChat 必须区分“消息附件”和“AI 输入附件”：

```text
消息附件：
  用途：历史展示、跨设备恢复、统一预览、下载、复制/保存。
  来源：OSS 上传后的 ManagedFileRecord + public URL + 本地缓存。
  持久化：保存元数据，不保存巨大 base64。

AI 输入附件：
  用途：本轮模型理解图片或文档。
  来源：图片使用压缩 JPEG；文档使用抽取文本或文件上下文。
  生命周期：仅本轮请求构造时临时生成。
```

硬性要求：

```text
1. 发送消息时必须先有 OSS 消息附件记录。
2. AI 压缩图不能替代 OSS 原附件。
3. OSS 原附件不能直接无压缩塞给 AI。
4. requestSnapshot 记录消息附件元数据，不记录 AI 临时 base64。
```

## 8. UI 组件落地方案

### 8.1 DeepTutorComposerToolbarView

需要新增输入：

```swift
let onAttachmentsPicked: ([MedicalUploadLocalFile]) -> Void
let canPickAttachments: Bool
```

paperclip 改为：

```text
MedicalDocumentFilePickerMenu(
    maxPhotoSelectionCount: ...,
    onFilesSelected: onAttachmentsPicked
) {
    toolbar button content
}
```

禁用逻辑：

```text
1. isStreaming=true 时禁用。
2. 达到附件数量上限时禁用。
3. 上传中可继续选择与否需由产品策略决定，建议先禁用，避免状态复杂化。
```

### 8.2 DeepTutorComposerCardView

需要新增：

```swift
let attachmentDrafts: [DeepTutorComposerAttachmentDraft]
let onUploadAttachment: (UUID) -> Void
let onRemoveAttachment: (UUID) -> Void
let onRetryAttachmentUpload: (UUID) -> Void
let onPreviewAttachment: (UUID) -> Void
let onAttachmentsPicked: ([MedicalUploadLocalFile]) -> Void
```

`canSend` 改为：

```text
canSend = !isStreaming && (
    trimmedText 非空 ||
    hasUploadedAttachments
) && noBlockingAttachmentWork
```

### 8.3 新增 DeepTutorComposerAttachmentPreviewBandView

建议职责：

```text
1. 横向显示附件草稿卡片。
2. 显示缩略图/文件图标。
3. 显示文件名、大小、状态。
4. 提供上传、重试、删除。
5. 点击卡片进入统一预览。
```

### 8.4 新增 DeepTutorComposerAttachmentThumbnailView

状态视觉：

```text
localSelected：显示“待上传”与上传按钮。
uploading：显示进度，不可删除或删除需确认。
uploaded：显示成功标记。
failed：显示错误色边框、错误文案、重试按钮。
```

尺寸建议：

```text
1. 图片卡片高度 64-72pt。
2. 文件卡片宽度 180-220pt。
3. 圆角 14-16pt。
4. 缩略图圆角 10-12pt。
5. 删除按钮 24pt，右上角悬浮。
```

视觉原则：

```text
1. 要和 DeepTutor 输入框的柔和浮层一致。
2. 不要做成系统默认列表。
3. 状态要明显，但不要抢消息输入的主视觉。
```

### 8.5 预览交互必须对齐 Chat

DeepTutorChat 的预览不能只做一个简单 sheet，需要对齐 Chat 的统一文件预览入口。

Chat 对标文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatRichMessageBlocks.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatFileAttachmentBlockView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/UI/FilePreview
```

需要复用或对齐：

```text
1. FilePreviewInput。
2. unifiedFilePreview。
3. startIndex 定位到当前点击附件。
4. 多附件预览时可左右切换。
5. 本地文件优先预览。
6. 本地没有时下载 OSS 文件后预览。
7. 预览不可用时显示可诊断占位，而不是崩溃或无响应。
```

Composer 预览区交互：

```text
1. 点击未上传附件：打开本地临时文件预览。
2. 点击已上传附件：优先打开本地缓存；没有缓存则使用 OSS 下载后打开。
3. 上传中附件点击：可以打开本地预览，但需要显示上传中状态。
4. 上传失败附件点击：仍可打开本地预览，同时显示失败重试入口。
```

消息内预览交互：

```text
1. 点击图片缩略图打开统一预览。
2. 点击 PDF/文件卡片打开统一预览。
3. 如果 OSS 文件尚未下载，先显示下载进度。
4. 下载失败显示重试，不允许静默失败。
```

## 9. 消息展示与本地持久化

### 9.1 用户消息气泡展示附件

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorUserBubble.swift
```

要求：

```text
1. 用户发送后，附件要显示在用户消息气泡附近。
2. 图片附件不能只显示为引用树或文件名，必须显示为图片画廊卡片。
3. PDF/文件显示文件卡片。
4. 点击后进入统一预览。
5. 展示顺序与发送顺序一致。
```

### 9.1.1 消息内图片卡片必须对齐 Chat

Chat 当前图片消息卡片由以下组件负责：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatRichMessageBlocks.swift
ChatImageGalleryBlockView
ChatImagePayloadBuilder
ChatImageGalleryStyle
```

DeepTutorChat 需要实现等价能力，优先复用可抽象组件；如果不能直接复用，也必须在 UI 和行为上对齐。

Chat 图片画廊关键表现：

```text
1. 横向滚动缩略图画廊。
2. 单个缩略图为正方形。
3. 多图时宽度按 min(count, 2.5) 个缩略图计算，露出半张提示可横滑。
4. 缩略图使用 rounded rectangle 裁切。
5. 本地已缓存图片直接显示。
6. 有 UIImage 时直接显示。
7. 有 managedFile/OSS 记录时显示 loading placeholder 并懒加载。
8. 有 URL 时使用 AsyncImage 或下载服务加载。
9. 加载失败显示失败占位和重试能力。
10. 点击缩略图打开 unifiedFilePreview。
11. 长按/上下文菜单支持复制、保存等图片操作。
```

DeepTutorChat 图片卡片验收：

```text
1. iOS DeepTutorChat 内发送 1 张图片，消息内显示图片缩略图，不显示裸文件名。
2. 发送多张图片，消息内显示横向画廊。
3. 图片圆角、尺寸、间距、加载态与 Chat 保持一致。
4. 本地缓存命中时不重复下载。
5. OSS 远程图未缓存时可下载展示。
6. 下载失败时卡片内显示重试，而不是空白。
7. 点击任意图片进入统一预览，并定位到被点击图片。
```

### 9.1.2 消息内文件卡片必须对齐 Chat

Chat 当前文件卡片由以下组件负责：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatFileAttachmentBlockView.swift
```

DeepTutorChat PDF/文件卡片需要对齐：

```text
1. 左侧 52pt 文件图标容器。
2. PDF 使用 doc.richtext.fill 语义图标，普通文件使用 doc.fill。
3. 文件扩展名以小胶囊叠在图标右下角。
4. 中间显示文件名，最多 2 行。
5. 副标题根据状态显示“点击下载”或“点击预览”。
6. 右侧显示下载、预览或 ProgressView 状态。
7. 卡片圆角 16pt。
8. 点击后通过 FileTransferService 下载/缓存，再进入 unifiedFilePreview。
```

DeepTutorChat 不应把 PDF/文件只放在 ContextReferenceTree 中。ContextReferenceTree 可以保留为上下文来源摘要，但消息主体必须有可点击、可预览、可下载的附件卡片。

### 9.2 本地数据库

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec.swift
```

要求：

```text
1. DeepTutorMessage.attachments 必须落库。
2. requestSnapshot.attachments 必须落库。
3. 本地数据库不保存巨大 base64。
4. 保存 localPath/previewURL/remoteURL/filename/mimeType/type/id。
5. 加载历史会话时附件卡片可以恢复显示。
6. 附件损坏或本地文件丢失时，UI 显示“文件不可用”，不能导致整条消息解码失败。
```

### 9.3 重试与重新生成

要求：

```text
1. regenerate assistant message 时复用原用户消息的 requestSnapshot.attachments。
2. 如果附件只有 localPath，需要重新构造 AI 输入。
3. 如果附件有 remoteURL，优先复用 remoteURL。
4. 如果图片原始文件丢失但存在预览 URL，需要给出可诊断错误。
```

## 10. 日志方案

日志不需要脱敏，但要避免刷屏。

建议新增日志：

```text
deeptutor.attachment.pick.start source=paperclip
deeptutor.attachment.pick.done count=2 image=1 pdf=1 totalBytes=...
deeptutor.attachment.preview.added draft=ABCD1234 kind=image filename=... bytes=...
deeptutor.attachment.upload.start draft=ABCD1234 filename=...
deeptutor.attachment.upload.progress draft=ABCD1234 progress=0.42
deeptutor.attachment.upload.done draft=ABCD1234 attachment=EFGH5678 url=... durationMs=...
deeptutor.attachment.upload.failed draft=ABCD1234 error=...
deeptutor.attachment.ai_compress.start attachment=EFGH5678 originalBytes=...
deeptutor.attachment.ai_compress.done attachment=EFGH5678 originalBytes=... aiBytes=... targetBytes=1048576
deeptutor.attachment.send.build count=2 image=1 file=1 hasText=true
deeptutor.attachment.snapshot.saved message=... attachments=2
deeptutor.attachment.history.restore message=... attachments=2 missingLocal=0
```

日志收口要求：

```text
1. progress 日志按 10% 阈值或时间窗口输出，不逐帧打印。
2. 图片压缩只输出摘要，不输出 base64。
3. 发送日志只输出数量、大小、类型、ID，不输出 base64。
4. 失败日志必须带 phase 与可定位 ID。
```

## 11. 验收标准

### 11.1 附件选择

```text
Given 用户在 DeepTutorChat 点击回形针
When 菜单弹出
Then 可以选择拍照、相册、文件
And 使用 MedicalDocumentFilePickerMenu
And DeepTutorChat 内没有重复实现文件选择 UI
```

### 11.2 预览区

```text
Given 用户选择 1 张图片和 1 个 PDF
When 回到 DeepTutorChat
Then Composer 内展示附件预览区
And 图片显示缩略图
And PDF 显示文件卡片
And 每个附件都可以删除
And 点击附件可以打开统一预览
```

### 11.3 上传后发送

```text
Given 用户已选择附件
When 附件还没有上传成功
Then 发送按钮不可发送带附件消息

Given 用户点击预览区上传
When 上传成功
Then 附件状态显示成功
And 发送按钮可用
```

### 11.3.1 OSS 上传

```text
Given 用户在 DeepTutorChat 选择图片或 PDF
When 用户点击预览区上传
Then 文件通过 FileTransferService 上传到 OSS
And 文件服务完成 registerFile
And 附件记录包含 fileId、objectKey、remoteURL、fileMd5、fullCacheKey
And 本地数据库不保存巨大 base64
And App 重启后仍可通过 OSS/缓存恢复附件
```

### 11.4 图片压缩给 AI

```text
Given 用户发送图片附件
When DeepTutorChat 构造 AI 请求
Then 图片先经过 AIImageCompressor.compressForAI
And 默认目标大小为 1048576 bytes
And 日志记录 originalBytes 与 aiBytes
And 不默认把原图直接给 AI
```

### 11.4.1 OSS 原图与 AI 压缩图分离

```text
Given 用户发送一张 5MB 原图
When 附件发送成功
Then OSS 保存原附件或项目要求的上传版本
And AI 请求使用压缩后的 JPEG
And requestSnapshot 只保存附件元数据
And 日志包含 originalBytes、aiBytes、objectKey
```

### 11.5 消息与历史恢复

```text
Given 用户发送带附件消息
When 重新进入会话
Then 用户消息仍显示附件卡片
And 本地数据库可以加载 attachments
And requestSnapshot 包含 attachments
And 重新生成回答时可以复用附件上下文
```

### 11.5.1 消息内图片卡片对齐 Chat

```text
Given 用户发送多张图片附件
When 消息出现在 DeepTutorChat 列表内
Then 展示为与 Chat 一致的横向图片画廊
And 缩略图圆角、间距、加载态、失败态与 Chat 对齐
And 点击图片进入 unifiedFilePreview
And 当前预览 startIndex 与点击图片一致
And 长按菜单或图片操作能力按 Chat 现有能力对齐
```

### 11.5.2 消息内文件预览对齐 Chat

```text
Given 用户发送 PDF 附件
When 消息出现在 DeepTutorChat 列表内
Then 展示为与 Chat 一致的文件卡片
And 点击后先下载/读取缓存
And 下载成功后进入 unifiedFilePreview
And 下载失败显示可重试状态
```

### 11.6 DeepTutor-main 对齐

```text
Given iOS 发送带附件 DeepTutor 消息
When 请求进入 AI 链路
Then 附件作为本轮用户消息上下文参与生成
And 语义对齐 Web start_turn.attachments
And 不是额外插入一条系统提示消息
```

## 12. 非目标范围

本工单不要求：

```text
1. 直接修改 Swift 代码。
2. 新建后端接口。
3. 实现服务端文件解析。
4. 支持所有任意文件类型。
5. 实现复杂附件批量管理页面。
6. 改动 Chat 主功能现有附件流程。
```

## 13. 风险与注意事项

### 13.1 不要把 MedicalDocumentUpload 业务语义带进 DeepTutorChat

`MedicalDocumentFilePickerMenu` 可以复用为“公共文件选择组件”，但上传后的业务类型、日志、消息模型不应直接叫 medical document。

### 13.2 不要保存巨大 base64

DeepTutor-main 后端已经明确在持久化时清掉 base64。iOS 本地数据库也应遵循同一原则：

```text
1. 原始文件存在本地文件或上传存储。
2. 消息里只存元数据。
3. AI 请求临时构造压缩 base64。
```

### 13.3 不要绕过现有 Chat/AI 压缩能力

项目已有：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIImageCompressor.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift
```

DeepTutorChat 需要复用同一套压缩和多模态判断思想，不应自写不可维护的图片压缩。

### 13.4 附件状态必须可恢复

如果上传成功后 App 被杀掉：

```text
1. 已发送消息必须可恢复附件。
2. 未发送草稿是否恢复由产品决定，但不能影响历史消息加载。
```

## 14. 建议目录结构

本工单建议在 DeepTutorChat 功能内按“Domain / Application / Presentation / Infrastructure”继续拆分，不要把附件逻辑全部堆进 `DeepTutorChatViewModel` 或 `DeepTutorComposerCardView`。

### 14.1 推荐新增/调整文件树

建议目录：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat
├── Domain
│   ├── DeepTutorMessage.swift
│   ├── DeepTutorMessageBlock.swift
│   ├── DeepTutorAttachmentDraft.swift                  # 新增：Composer 草稿附件模型
│   ├── DeepTutorOutgoingAttachment.swift               # 新增：发送给 DeepTutor AI/WS 的附件语义
│   └── DeepTutorAttachmentDisplayModels.swift          # 新增：消息内图片/文件展示 payload
├── Application
│   ├── DeepTutorChatViewModel.swift
│   ├── SendDeepTutorAIMessageUseCase.swift
│   ├── DeepTutorAttachmentMapper.swift                 # 新增：MedicalUploadLocalFile -> Draft/Outgoing
│   ├── DeepTutorAttachmentUploadUseCase.swift          # 新增：OSS 上传与进度状态机
│   ├── DeepTutorAttachmentAIInputBuilder.swift         # 新增：图片压缩、多模态输入、文本降级
│   ├── DeepTutorAttachmentPreviewInputBuilder.swift    # 新增：FilePreviewInput 构造与缓存查找
│   └── DeepTutorAttachmentDiagnostics.swift            # 新增：附件专用日志收口
├── Infrastructure
│   ├── DeepTutorLocalChatStore.swift
│   ├── DeepTutorMessageCodec.swift
│   └── DeepTutorAttachmentCacheResolver.swift          # 新增：OSS fullCacheKey/localPath 恢复
└── Presentation
    ├── DeepTutorComposerCardView.swift
    ├── DeepTutorComposerToolbarView.swift
    ├── DeepTutorComposerAttachmentPreviewBandView.swift # 新增：Composer 附件预览横条
    ├── DeepTutorComposerAttachmentThumbnailView.swift   # 新增：预览区单个附件缩略卡
    ├── Bubbles
    │   ├── DeepTutorUserBubble.swift
    │   ├── DeepTutorAttachmentGalleryBlockView.swift    # 新增：消息内图片画廊，对齐 ChatImageGalleryBlockView
    │   └── DeepTutorFileAttachmentBlockView.swift       # 新增：消息内文件卡片，对齐 ChatFileAttachmentBlockView
    └── Preview
        └── DeepTutorAttachmentPreviewRouter.swift       # 新增：统一预览弹出路由，可选
```

### 14.2 不建议的目录做法

```text
1. 不建议把附件草稿模型写进 DeepTutorComposerCardView。
2. 不建议把 OSS 上传直接写进 View。
3. 不建议把图片压缩逻辑写进 Presentation。
4. 不建议复用 MedicalDocumentUpload 的业务命名保存 DeepTutor 附件。
5. 不建议把 Chat 的 View 整个复制到 DeepTutorChat 后改名，应该先抽象可复用语义，再按 DeepTutor UI 做适配。
```

## 15. 核心技术细节

### 15.1 状态机必须单向流动

附件从选择到发送必须遵守单向状态流：

```text
MedicalUploadLocalFile
  -> DeepTutorComposerAttachmentDraft(localSelected)
  -> DeepTutorComposerAttachmentDraft(uploading)
  -> DeepTutorComposerAttachmentDraft(uploaded + DeepTutorUploadedAttachment)
  -> DeepTutorOutgoingAttachment
  -> DeepTutorMessage.attachments
  -> DeepTutorRequestSnapshot.attachments
  -> DeepTutorAttachmentDisplayPayload
```

不允许：

```text
1. 选择后直接写入 DeepTutorMessage。
2. 上传中直接允许发送。
3. 发送时再临时找 View 里的图片 Data。
4. 历史消息依赖 Composer draft 恢复。
```

### 15.2 草稿态与消息态必须分离

草稿态：

```text
1. 有 Data。
2. 有本地临时文件。
3. 有上传进度。
4. 有失败错误。
5. 可删除、可重试。
```

消息态：

```text
1. 没有上传进度。
2. 不保存巨大 Data/base64。
3. 保存 OSS 元数据。
4. 可以从缓存或 OSS 恢复预览。
5. 可进入 requestSnapshot。
```

### 15.3 OSS 与 AI 输入双轨

发送一张图片时要产生两条不同用途的数据：

```text
OSS 原附件：
  data = 原始选择图片或项目允许的上传版本
  目的 = 历史展示、预览、跨设备恢复
  持久化 = fileId/objectKey/remoteURL/fullCacheKey/fileMd5

AI 压缩附件：
  data = AIImageCompressor.compressForAI 后的 JPEG
  目的 = 当前模型理解图片
  持久化 = 不落库，只记录 aiByteCount 日志
```

这个分离是硬性要求。否则会出现两类问题：

```text
1. 只给 AI 压缩图：历史预览质量和跨设备恢复差。
2. 直接给 AI 原图：请求体过大、成本高、失败率上升。
```

### 15.4 UI 刷新必须增量更新

附件上传过程中会频繁更新 progress，不能导致整条消息列表重载。

ViewModel 层建议：

```text
1. Composer draft 附件状态单独放在 composerState。
2. 上传进度只刷新 Composer 预览区。
3. 消息列表只在发送成功、消息插入、AI partial、完成时更新。
4. 发送后清空 composer attachment drafts，但消息里的 attachments 是新数组副本。
```

避免：

```text
1. upload progress 触发 messages 全量重算。
2. 上传中反复保存会话数据库。
3. 预览区状态和消息状态引用同一个对象。
```

### 15.5 预览必须走统一入口

所有预览都要最终进入：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/UI/FilePreview/View+UnifiedFilePreview.swift
```

DeepTutorChat 不应实现独立 QuickLook sheet。

预览输入构造优先级：

```text
1. 本地 draft data 写入临时文件 -> FilePreviewInput。
2. 已发送消息 localPath 存在 -> FilePreviewInput。
3. fullCacheKey 命中 FileCacheManager -> FilePreviewInput。
4. managed file/objectKey 可下载 -> 下载后 FilePreviewInput。
5. remoteURL 可下载 -> 下载后 FilePreviewInput。
6. 都失败 -> Preview unavailable 占位 FilePreviewInput。
```

## 16. 关键代码示例

以下代码是落地参考示例，不是本工单直接实现内容。开发时需按项目真实依赖、Actor 隔离和命名调整。

### 16.1 DeepTutorComposerAttachmentDraft

```swift
import Foundation
import UniformTypeIdentifiers

enum DeepTutorComposerAttachmentSource: String, Sendable {
    case camera
    case photoLibrary
    case document
}

enum DeepTutorComposerAttachmentKind: String, Equatable, Sendable {
    case image
    case pdf
    case file
}

enum DeepTutorComposerAttachmentPhase: String, Equatable, Sendable {
    case localSelected
    case uploading
    case uploaded
    case failed
}

struct DeepTutorComposerAttachmentDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var source: DeepTutorComposerAttachmentSource
    var kind: DeepTutorComposerAttachmentKind
    var data: Data
    var displayName: String
    var mimeType: String?
    var utTypeIdentifier: String?
    var byteCount: Int
    var localPreviewURL: URL?
    var phase: DeepTutorComposerAttachmentPhase
    var uploadProgress: Double
    var uploaded: DeepTutorUploadedAttachment?
    var errorMessage: String?

    var isBlockingSend: Bool {
        switch phase {
        case .localSelected, .uploading, .failed:
            return true
        case .uploaded:
            return false
        }
    }
}
```

### 16.2 DeepTutorUploadedAttachment

```swift
import Foundation

struct DeepTutorUploadedAttachment: Equatable, Sendable {
    var id: String
    var type: String
    var filename: String
    var mimeType: String?
    var fileId: Int64?
    var fileUuid: String?
    var objectKey: String?
    var remoteURL: URL?
    var fullCacheKey: String?
    var fileMd5: String?
    var localPath: String?
    var originalByteCount: Int
    var aiByteCount: Int?
}
```

### 16.3 MedicalUploadLocalFile 转草稿

```swift
enum DeepTutorAttachmentMapper {
    static func makeDrafts(from files: [MedicalUploadLocalFile]) async -> [DeepTutorComposerAttachmentDraft] {
        var drafts: [DeepTutorComposerAttachmentDraft] = []

        for file in files {
            guard let data = try? Data(contentsOf: file.fileURL), data.isEmpty == false else {
                continue
            }

            let inferred = UTType(filenameExtension: file.fileURL.pathExtension)
            let kind: DeepTutorComposerAttachmentKind
            if inferred?.conforms(to: .pdf) == true {
                kind = .pdf
            } else if inferred?.conforms(to: .image) == true {
                kind = .image
            } else {
                kind = .file
            }

            drafts.append(
                DeepTutorComposerAttachmentDraft(
                    id: UUID(),
                    source: .document,
                    kind: kind,
                    data: data,
                    displayName: file.displayName,
                    mimeType: inferred?.preferredMIMEType,
                    utTypeIdentifier: inferred?.identifier,
                    byteCount: data.count,
                    localPreviewURL: file.fileURL,
                    phase: .localSelected,
                    uploadProgress: 0,
                    uploaded: nil,
                    errorMessage: nil
                )
            )
        }

        return drafts
    }
}
```

注意：

```text
1. 示例假设 MedicalUploadLocalFile 有 fileURL/displayName 字段，实际字段以真实定义为准。
2. 如果 MedicalUploadLocalFile 已有 Data，则优先使用现有 Data，避免重复读盘。
3. source 需要根据公共组件回调补充真实来源；如果组件无法区分，先用 document 或 unknown。
```

### 16.4 Composer Toolbar 接入公共文件菜单

目标结构：

```swift
struct DeepTutorComposerToolbarView: View {
    @Binding var capability: DeepTutorCapability
    let modelName: String?
    let isStreaming: Bool
    let canSend: Bool
    let canPickAttachments: Bool
    let onAttachmentsPicked: ([MedicalUploadLocalFile]) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            MedicalDocumentFilePickerMenu(
                maxPhotoSelectionCount: 6,
                onFilesSelected: onAttachmentsPicked
            ) {
                Image(systemName: "paperclip")
                    .frame(width: 34, height: 34)
            }
            .disabled(isStreaming || !canPickAttachments)

            // 保留现有 capability/model/send 区域
        }
    }
}
```

落地注意：

```text
1. 如果 MedicalDocumentFilePickerMenu 内部使用 Menu，外层不要再套 Button。
2. disabled 状态要保证相册/文件弹窗不会被触发。
3. 图标视觉要沿用当前 toolbar 的 foreground/background，不要变成默认蓝色按钮。
```

### 16.5 OSS 上传 UseCase

```swift
struct DeepTutorAttachmentUploadUseCase {
    let fileTransferService: FileTransferService

    func upload(
        draft: DeepTutorComposerAttachmentDraft,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> DeepTutorUploadedAttachment {
        let record = try await fileTransferService.upload(
            ManagedFileUploadPayload(
                data: draft.data,
                fileName: draft.displayName,
                businessType: "deep_tutor_attachment",
                businessId: draft.id.uuidString,
                isPublic: false,
                onUploadProgress: onProgress
            )
        )

        let publicURL = await fileTransferService.publicHTTPSURLForObjectKey(record.objectKey)
        let fullCacheKey = record.fileUuid.map {
            ChatAttachment.makeFullCacheKey(fileUUID: $0, fileName: record.originalName)
        }

        return DeepTutorUploadedAttachment(
            id: draft.id.uuidString,
            type: draft.kind == .image ? "image" : draft.kind == .pdf ? "pdf" : "file",
            filename: record.originalName,
            mimeType: record.mimeType,
            fileId: record.id,
            fileUuid: record.fileUuid,
            objectKey: record.objectKey,
            remoteURL: publicURL,
            fullCacheKey: fullCacheKey,
            fileMd5: record.fileMd5,
            localPath: draft.localPreviewURL?.path,
            originalByteCount: draft.byteCount,
            aiByteCount: nil
        )
    }
}
```

注意：

```text
1. `record.fileUuid`、`record.originalName`、`record.fileMd5` 等字段以 ManagedFileRecord 真实定义为准。
2. 如果不能直接引用 ChatAttachment.makeFullCacheKey，需要把 fullCacheKey 生成逻辑抽到 Core 或 DeepTutor 自己实现等价函数。
3. businessType 最终值必须与后端/文件系统约定一致。
```

### 16.6 ViewModel 附件状态更新

```swift
@MainActor
func handleDeepTutorAttachmentsPicked(_ files: [MedicalUploadLocalFile]) {
    Task {
        let drafts = await DeepTutorAttachmentMapper.makeDrafts(from: files)
        await MainActor.run {
            composerAttachmentDrafts.append(contentsOf: drafts)
            DeepTutorAttachmentDiagnostics.pickDone(drafts)
        }
    }
}

@MainActor
func uploadDeepTutorAttachment(id: UUID) {
    guard let index = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
    composerAttachmentDrafts[index].phase = .uploading
    composerAttachmentDrafts[index].uploadProgress = 0
    composerAttachmentDrafts[index].errorMessage = nil

    let draft = composerAttachmentDrafts[index]

    Task {
        do {
            let uploaded = try await uploadUseCase.upload(draft: draft) { [weak self] progress in
                Task { @MainActor in
                    self?.updateAttachmentProgress(id: id, progress: progress)
                }
            }

            await MainActor.run {
                guard let current = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
                composerAttachmentDrafts[current].phase = .uploaded
                composerAttachmentDrafts[current].uploadProgress = 1
                composerAttachmentDrafts[current].uploaded = uploaded
            }
        } catch {
            await MainActor.run {
                guard let current = composerAttachmentDrafts.firstIndex(where: { $0.id == id }) else { return }
                composerAttachmentDrafts[current].phase = .failed
                composerAttachmentDrafts[current].errorMessage = error.localizedDescription
            }
        }
    }
}
```

刷新要求：

```text
1. `updateAttachmentProgress` 只更新对应 draft，不重建 messages。
2. progress 需要做节流，避免每 1% 都触发复杂布局。
3. 失败后保留 draft.data，允许重试。
```

### 16.7 Composer canSend

```swift
private var canSend: Bool {
    let hasText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasUploadedAttachment = attachmentDrafts.contains { $0.phase == .uploaded }
    let hasBlockingAttachment = attachmentDrafts.contains(\.isBlockingSend)

    return !isStreaming
        && !hasBlockingAttachment
        && (hasText || hasUploadedAttachment)
}
```

如果产品希望“纯文本可忽略未上传附件发送”，必须明确：

```text
1. 发送纯文本时是否自动丢弃未上传附件。
2. 是否需要二次确认。
3. 未上传附件是否保留在 Composer。
```

当前建议：只要 Composer 中存在未完成附件，就禁用发送，降低误发风险。

### 16.8 构造 DeepTutorOutgoingAttachment

```swift
extension DeepTutorUploadedAttachment {
    func outgoingAttachment() -> DeepTutorOutgoingAttachment {
        DeepTutorOutgoingAttachment(
            id: id,
            type: type,
            filename: filename,
            base64: nil,
            url: remoteURL?.absoluteString,
            mimeType: mimeType
        )
    }

    func persistedAttachment() -> DeepTutorAttachment {
        DeepTutorAttachment(
            id: id,
            type: type,
            filename: filename,
            mimeType: mimeType,
            localPath: localPath,
            previewURL: remoteURL?.absoluteString,
            generated: false
        )
    }
}
```

后续如果 `DeepTutorAttachment` 补充 `fileId/objectKey/fullCacheKey/fileMd5`，这里也需要一起映射。

### 16.9 发送前图片 AI 压缩

```swift
enum DeepTutorAttachmentAIInputBuilder {
    static func compressedImageBase64IfNeeded(
        draft: DeepTutorComposerAttachmentDraft
    ) async -> (base64: String, byteCount: Int)? {
        guard draft.kind == .image else { return nil }

        let compressed = await Task.detached(priority: .utility) {
            AIImageCompressor.compressForAI(imageData: draft.data)
        }.value

        guard let jpegData = compressed else { return nil }
        return (jpegData.base64EncodedString(), jpegData.count)
    }
}
```

落地注意：

```text
1. 压缩要在后台任务中进行，避免卡 UI。
2. 压缩失败可以降级为 UIImage(data:)?.jpegData(compressionQuality: 0.45)。
3. 日志必须记录 originalBytes、aiBytes、targetBytes。
4. AI 临时 base64 不进入 DeepTutorLocalChatStore。
```

### 16.10 消息内图片画廊 payload

```swift
struct DeepTutorImageAttachmentPayload: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let localURL: URL?
    let displayName: String
    let mimeType: String?
    let fullCacheKey: String?
}

enum DeepTutorAttachmentDisplayBuilder {
    static func imagePayloads(from attachments: [DeepTutorAttachment]) -> [DeepTutorImageAttachmentPayload] {
        attachments.compactMap { attachment in
            guard attachment.type == "image" else { return nil }
            return DeepTutorImageAttachmentPayload(
                id: UUID(uuidString: attachment.id) ?? UUID(),
                url: attachment.previewURL.flatMap(URL.init(string:)),
                localURL: attachment.localPath.map(URL.init(fileURLWithPath:)),
                displayName: attachment.filename ?? "image.jpg",
                mimeType: attachment.mimeType,
                fullCacheKey: nil
            )
        }
    }
}
```

要求：

```text
1. 如果 attachment.id 不是 UUID 字符串，需要建立稳定 UUID 映射，不能每次刷新 UUID() 导致 Diff 抖动。
2. fullCacheKey 应从真实模型字段读取，不应一直 nil。
3. payload builder 不做网络下载，只做纯映射。
```

### 16.11 消息内图片画廊 View

```swift
struct DeepTutorAttachmentGalleryBlockView: View {
    let images: [DeepTutorImageAttachmentPayload]
    let fileTransferService: FileTransferService

    @State private var localFiles: [UUID: URL] = [:]
    @State private var failedIDs: Set<UUID> = []
    @State private var previewInputs: [FilePreviewInput] = []
    @State private var previewStartIndex = 0
    @State private var showPreview = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(images) { payload in
                    thumbnail(payload)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            Task { await openPreview(payload) }
                        }
                }
            }
        }
        .frame(height: 96)
        .unifiedFilePreview(
            isPresented: $showPreview,
            inputs: previewInputs,
            startIndex: previewStartIndex
        )
    }
}
```

对齐要求：

```text
1. 实际尺寸需参考 ChatImageGalleryStyle，不一定固定 96。
2. 需要实现 loading placeholder、failedDownloadCell、retryDownload、contextMenu。
3. openPreview 逻辑要和 Chat 的 buildPreviewInputs/startIndex 一致。
```

### 16.12 消息内文件卡片 View

```swift
struct DeepTutorFileAttachmentBlockView: View {
    let attachments: [DeepTutorAttachment]
    let fileTransferService: FileTransferService

    @State private var localFiles: [String: URL] = [:]
    @State private var downloadingIDs: Set<String> = []
    @State private var previewInputs: [FilePreviewInput] = []
    @State private var previewIndex = 0
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(attachments, id: \.id) { attachment in
                Button {
                    Task { await openPreview(attachment) }
                } label: {
                    // UI 对齐 ChatFileAttachmentBlockView：
                    // 52pt 图标、扩展名胶囊、文件名、副标题、下载/预览状态
                }
                .buttonStyle(.plain)
            }
        }
        .unifiedFilePreview(
            isPresented: $showPreview,
            inputs: previewInputs,
            startIndex: previewIndex
        )
    }
}
```

### 16.13 requestSnapshot 扩展示例

```swift
nonisolated struct DeepTutorRequestSnapshot: Codable, Equatable, Sendable {
    var references: [DeepTutorContextReference]
    var capability: DeepTutorCapability?
    var enabledTools: [String]?
    var toolSnapshot: DeepTutorPerTurnToolSnapshot?
    var attachments: [DeepTutorAttachment]

    init(
        references: [DeepTutorContextReference] = [],
        capability: DeepTutorCapability? = nil,
        enabledTools: [String]? = nil,
        toolSnapshot: DeepTutorPerTurnToolSnapshot? = nil,
        attachments: [DeepTutorAttachment] = []
    ) {
        self.references = references
        self.capability = capability
        self.enabledTools = enabledTools
        self.toolSnapshot = toolSnapshot
        self.attachments = attachments
    }
}
```

兼容要求：

```text
1. decodeIfPresent attachments，旧数据没有 attachments 时默认 []。
2. DeepTutorMessageCodec 要保持向后兼容。
3. DebugExporter 输出 attachments 数量和元数据。
```

## 17. 极细落地步骤

### 17.1 第一步：打开入口，但不发送

目标：

```text
1. paperclip 可点击。
2. 能从公共组件拿到 [MedicalUploadLocalFile]。
3. 能转换为 draft。
4. Composer 出现预览区。
```

验收：

```text
1. 不需要 OSS。
2. 不需要 AI。
3. 不需要落库。
4. 先确保 UI 选择和预览稳定。
```

### 17.2 第二步：接 unifiedFilePreview

目标：

```text
1. Composer 本地附件可预览。
2. 多附件 startIndex 正确。
3. 图片/PDF 都走统一预览。
```

关键点：

```text
1. Data 写临时文件时文件扩展名必须正确。
2. mimeType 要传入 FilePreviewInput。
3. 临时文件路径要稳定到本次 draft 生命周期。
```

### 17.3 第三步：接 OSS 上传

目标：

```text
1. 预览区出现上传按钮。
2. 上传进度可见。
3. 成功后 phase=uploaded。
4. 失败后 phase=failed，可重试。
```

关键点：

```text
1. 调用 FileTransferService.upload。
2. businessType 使用 deep_tutor_attachment 或确认后的统一值。
3. businessId 使用 draft.id.uuidString。
4. 上传完成后调用 publicHTTPSURLForObjectKey。
5. 上传日志只打摘要。
```

### 17.4 第四步：发送按钮规则

目标：

```text
1. 没文字没附件不能发。
2. 有 uploaded 附件可以发。
3. uploading/failed/localSelected 不能发。
4. 发送后清空 draft。
```

边界：

```text
1. 用户选择附件后不上传，按钮应保持禁用或提示先上传。
2. 上传中用户切换能力，附件是否保留需要保持一致，建议保留。
3. streaming 中禁止新增附件。
```

### 17.5 第五步：消息插入与落库

目标：

```text
1. 发送时将 uploaded 转成 DeepTutorAttachment。
2. 用户消息立即显示附件卡片。
3. DeepTutorLocalChatStore 落库。
4. 重新进入会话可恢复。
```

关键点：

```text
1. 消息里的 attachment 不能引用 draft 对象。
2. 本地数据库不保存 draft.data。
3. 旧消息 decode 不能失败。
```

### 17.6 第六步：消息内卡片对齐 Chat

目标：

```text
1. 图片显示横向 gallery。
2. PDF/文件显示文件卡片。
3. 点击进入 unifiedFilePreview。
4. OSS 未缓存时可下载。
```

关键点：

```text
1. 图片不要走 ContextReferenceTree 的普通行展示。
2. ContextReferenceTree 可作为“上下文摘要”，但不能替代消息附件卡片。
3. 卡片 loading/failed/retry 状态必须完整。
```

### 17.7 第七步：AI 输入压缩

目标：

```text
1. 图片给 AI 前压缩。
2. AI 请求有图片语义。
3. 非多模态模型有降级策略。
```

关键点：

```text
1. 使用 AIImageCompressor.compressForAI。
2. 压缩在后台线程。
3. requestSnapshot 不保存压缩 base64。
4. 日志记录 objectKey、originalBytes、aiBytes。
```

### 17.8 第八步：重新生成与恢复

目标：

```text
1. regenerate 复用 requestSnapshot.attachments。
2. 附件可从 OSS/cache 恢复。
3. 本地文件丢失时不影响消息加载。
```

关键点：

```text
1. requestSnapshot.attachments 是重试的单一事实源。
2. localPath 丢失时，用 objectKey/remoteURL。
3. objectKey 丢失时，降级到 remoteURL。
```

### 17.9 第九步：日志与调试

目标：

```text
1. 每个阶段有边界日志。
2. 上传进度不刷屏。
3. Debug 面板能看到附件状态。
```

建议右上角调试信息补充：

```text
attachmentsDraftCount
attachmentsUploadedCount
attachmentsUploadingCount
attachmentsFailedCount
lastAttachmentError
lastUploadedObjectKey
lastAIImageBytes
```

## 18. 建议拆分子任务

### 子任务 A：Composer 选择入口

```text
1. DeepTutorComposerToolbarView 接入 MedicalDocumentFilePickerMenu。
2. 新增 onAttachmentsPicked 回调。
3. 回形针按 streaming / limit 状态禁用。
```

### 子任务 B：草稿模型与预览区

```text
1. 新增 DeepTutorComposerAttachmentDraft。
2. 新增 DeepTutorComposerAttachmentPreviewBandView。
3. 接 unifiedFilePreview。
4. 支持删除与重试 UI。
```

### 子任务 C：上传与发送状态机

```text
1. 新增 DeepTutorAttachmentUploadUseCase。
2. 接 FileTransferService。
3. 维护 localSelected/uploading/uploaded/failed。
4. 修改 canSend 规则。
```

### 子任务 D：AI 请求与图片压缩

```text
1. 发送前构造 DeepTutorOutgoingAttachment。
2. 图片走 AIImageCompressor.compressForAI。
3. 多模态模型走 image contentParts。
4. 非多模态模型走 OCR/文本降级或明确提示。
```

### 子任务 E：消息落库与重试

```text
1. DeepTutorMessage.attachments 落库。
2. DeepTutorRequestSnapshot.attachments 落库。
3. 历史加载恢复附件卡片。
4. regenerate 复用附件。
```

### 子任务 F：日志与验收

```text
1. 增加附件全链路日志。
2. 控制 upload progress 日志频率。
3. 验证 Web/iOS 语义对齐。
```

## 19. 结论

DeepTutorChat 当前附件问题的核心不是“按钮没点亮”，而是缺少从 Composer 到 AI 的完整附件生命周期：

```text
选择
  -> 草稿
  -> 预览
  -> 上传
  -> 压缩
  -> 发送
  -> 消息展示
  -> 本地持久化
  -> requestSnapshot 重试恢复
```

本工单要求 iOS 端复用项目公共文件选择组件、参考 Chat 的附件预览/上传/压缩流程，并对齐 DeepTutor-main 的 `start_turn.attachments` 语义，确保附件真正成为 DeepTutor 本轮对话上下文的一部分。
