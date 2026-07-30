# 文件与 OSS

## 一、模块目标

文件与 OSS 模块负责客户端文件的统一传输、对象存储接入、远端文件登记、业务绑定、本地缓存和下载完整性校验。它被医疗档案、聊天附件、用药/医疗业务附件等功能复用。

当前实现是“应用内文件门面 + 阿里云 OSS 直传 + 后端文件元数据 API + 账号隔离文件缓存”的组合。文件二进制不进入业务 JSON 请求；业务模块只持有 `ManagedFileRecord` 及其业务绑定信息。

本文档只描述当前 iOS `SparkClient` 工程的文件与 OSS 能力。Android 工程中的阿里云 SDK Vendor 不作为本模块当前实现依据。

## 二、文件与 OSS 模块结构

| 层级 | 当前实现 | 关键代码 |
| --- | --- | --- |
| 业务入口 | 医疗文档上传、聊天附件、医疗/用药附件 | `SparkClient/Projects/Features/MedicalDocumentUpload/`、`SparkClient/Projects/Features/Chat/`、`SparkClient/Projects/Features/Home/` |
| 传输门面 | 统一编排上传、下载、列表、绑定、删除和运行时凭证清理 | `SparkClient/Projects/Core/FileStorage/FileTransferService.swift` |
| 文件模型 | 远端文件记录、上传负载、登记请求、业务绑定项 | `SparkClient/Projects/Core/FileStorage/FileStorageModels.swift` |
| OSS 凭证 | 登录后预取、上传前续期、退出登录时清理的 STS 快照 | `SparkClient/Projects/Core/OSS/SparkOSSConfigurationStore.swift`、`AliyunOSSRuntimeConfig.swift` |
| OSS SDK 适配 | 将阿里云回调任务桥接为 `async/await`，提供上传、下载和预签名 URL | `SparkClient/Projects/Core/OSS/OSSClient.swift`、`OSSManager.swift` |
| 后端文件 API | 文件列表、登记、业务绑定、删除、后端预签名下载 URL | `SparkClient/Projects/Core/Networking/API/File/FileAPI.swift` |
| 本地缓存 | `Library/Caches/SparkClient.FileCache/<账号命名空间>/<fileUUID>/`，原子写入和 MD5 校验 | `SparkClient/Projects/Core/FileStorage/FileCacheManager.swift` |
| 组合根/生命周期 | 统一装配 `FileTransferService`，账号切换和退出时重置缓存命名空间及 OSS 凭证 | `SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift`、`StorageRegistry.swift`、`AccountSessionRuntime.swift` |

### 2.1 具体目录结构

以下目录均为当前 `SparkClient` iOS 工程中的实际目录；文件与 OSS 能力横跨 Core 基础设施、App 组合根和多个业务 Feature。

```text
SparkClient/
├── Projects/
│   ├── App/
│   │   └── Sources/App/
│   │       ├── AppContainer.swift
│   │       └── Architecture/
│   │           ├── AssemblyProducts.swift
│   │           ├── FeatureAssemblies.swift
│   │           ├── StorageRegistry.swift
│   │           └── AccountSessionRuntime.swift
│   │
│   ├── Core/
│   │   ├── FileStorage/
│   │   │   ├── FileStorageModels.swift
│   │   │   ├── FileCacheManager.swift
│   │   │   └── FileTransferService.swift
│   │   │
│   │   ├── OSS/
│   │   │   ├── AliyunOSSRuntimeConfig.swift
│   │   │   ├── OSSConfiguration.swift
│   │   │   ├── OSSClient.swift
│   │   │   ├── OSSManager.swift
│   │   │   ├── SparkOSSConfigurationStore.swift
│   │   │   └── FileUtilities.swift
│   │   │
│   │   ├── Networking/
│   │   │   └── API/
│   │   │       ├── File/
│   │   │       │   └── FileAPI.swift
│   │   │       ├── OSS/
│   │   │       │   └── SparkOSSAPI.swift
│   │   │       └── OCR/
│   │   │           └── OCRAPI.swift
│   │   │
│   │   └── Utilities/
│   │       └── Objective-C/AliyunOSSSDK/
│   │           └── OSSLog.swift
│   │
│   └── Features/
│       ├── MedicalDocumentUpload/
│       │   ├── Application/
│       │   │   └── UploadMedicalDocumentFilesUseCase.swift
│       │   ├── Domain/
│       │   │   └── MedicalDocumentUploadModels.swift
│       │   ├── Infrastructure/
│       │   │   └── DefaultMedicalDocumentAttachmentBinder.swift
│       │   └── Presentation/
│       │       ├── MedicalDocumentUploadHostView.swift
│       │       ├── MedicalDocumentFilePickerMenu.swift
│       │       └── MedicalDocumentUploadProgressView.swift
│       │
│       ├── Chat/
│       │   ├── Application/
│       │   │   └── ChatSendImageAssembly.swift
│       │   └── Infrastructure/
│       │       └── ChatAttachmentPipeline.swift
│       │
│       └── Home/
│           └── Presentation/MedicalLists/
│               ├── MedicalCases/MedicalCaseDetail/AttachmentPill.swift
│               └── Medications/
│                   ├── MedicineBox/MedicineBoxDetailPage.swift
│                   ├── MedicationPlanDetailPage.swift
│                   └── MedicationPrescriptionDetailPage.swift
│
└── Tests/
    ├── MedicalDocumentUpload/
    │   ├── MedicalExtractionInputSourceTests.swift
    │   ├── MedicalPreSubmitValidatorTests.swift
    │   └── PrescriptionPreSubmitValidationTests.swift
    ├── Chat/
    │   └── ChatArchitectureGateTests.swift
    └── Networking/
        └── SparkNetworkEngineTests.swift
```

### 2.2 目录职责与依赖方向

```text
Feature Presentation
  ├── 医疗文档选择/上传页面
  ├── 聊天附件 UI
  └── 医疗/用药附件展示
          ↓
Feature Application / Infrastructure
  ├── UploadMedicalDocumentFilesUseCase
  ├── DefaultMedicalDocumentAttachmentBinder
  └── ChatAttachmentPipeline
          ↓
Core FileStorage
  └── FileTransferService
      ├── FileCacheManager
      ├── SparkFileAPI
      ├── SparkOSSAPI
      └── OSSClientWrapper
              ↓
Core OSS / Networking
  ├── SparkOSSConfigurationStore
  ├── OSSManager
  ├── Aliyun OSS SDK
  └── SparkNetworkEngine
```

其中 `FileTransferService` 是文件能力的统一边界：业务 Feature 不应直接依赖 `OSSManager`、`OSSClientWrapper` 或阿里云 SDK。`AppContainer` 和 `AssemblyProducts` 负责装配具体实现；`StorageRegistry` 与 `AccountSessionRuntime` 只负责账号生命周期下的缓存命名空间和临时凭证清理，不参与文件业务规则。

## 三、功能模块

### 3.1 文件模型、命名与业务归属

#### 需求说明

所有远端文件必须有稳定的文件 UUID、文件名、大小、MIME 类型、MD5、业务类型和业务 ID。OSS 对象键与后端登记记录保持一致，业务模块通过文件 ID 或业务绑定读取附件。

#### 基础要求与业务规则

- `ManagedFileRecord` 是远端文件元数据的客户端模型，包含 `id`、`fileUuid`、`filePath`、`objectKey`、`storageType` 和业务归属字段。
- 上传前使用 `FileUtilities.sanitizeFileName` 清理路径分隔符和非法字符；空文件名降级为 `unnamed_file`。
- MIME 类型优先由 `UTType(filenameExtension:)` 推断，无法推断时降级为 `application/octet-stream`。
- MD5 在客户端计算并写入 `FileRegistrationRequest.fileMd5`，用于本地上传后和下载后的完整性校验。
- 当前对象键格式为 `SparkClient/<yyyyMMdd>/<uuid>/<sanitizedFileName>`；日期使用 UTC。
- 医疗文档初始登记使用 `businessType=medical_document_upload_source`、成员 ID 作为 `businessId`、`isPublic=false`，保存业务记录后再通过绑定接口改为具体业务类型。

#### 数据模型与完整字段

| 模型 | 字段 | 类型 | 必填/可空 | 含义与约束 |
| --- | --- | --- | --- | --- |
| `ManagedFileRecord` | `id` | `Int` | 必填 | 后端文件记录主键；绑定、删除使用此值。 |
|  | `fileUuid` | `String` | 必填 | 文件传输实例 UUID；本地缓存按其小写值分目录。 |
|  | `filePath` | `String?` | 可空 | 后端返回的文件路径或下载地址；当前下载流程直接尝试将其解析为 URL。 |
|  | `originalName` | `String` | 必填 | 清理后的原始文件名；用于 UI 展示、MIME 推断和本地缓存文件名。 |
|  | `fileSize` | `Int` | 必填 | 文件字节数；上传登记取 `Data.count`。 |
|  | `mimeType` | `String` | 必填 | MIME 类型；优先由文件扩展名推断。 |
|  | `fileMd5` | `String?` | 可空 | 小写十六进制 MD5；存在时用于缓存和下载校验。 |
|  | `isPublic` | `Bool` | 必填 | 文件公开性；医疗文档和聊天附件当前传 `false`。 |
|  | `businessType` | `String` | 必填 | 业务归属类型，不是 Swift enum，由客户端与服务端字符串契约共同维护。 |
|  | `businessId` | `String` | 必填 | 业务记录 ID、成员 ID 或聊天附件临时 UUID 字符串。 |
|  | `createdAt` | `String` | 必填 | 服务端创建时间原始字符串；当前客户端不转换为 `Date`。 |
|  | `objectKey` | `String?` | 可空 | OSS 对象键；用于生成公开地址或预签名下载 URL。 |
|  | `storageType` | `String?` | 可空 | 存储后端标识；当前登记固定为 `oss`。 |
| `ManagedFileUploadPayload` | `data` | `Data` | 必填 | 待上传的完整二进制；当前实现一次性驻留内存。 |
|  | `fileName` | `String` | 必填 | 业务调用方提供的文件名，上传前清理。 |
|  | `businessType` | `String` | 必填 | 初始业务归属。 |
|  | `businessId` | `String` | 必填 | 初始业务 ID。 |
|  | `isPublic` | `Bool` | 必填 | 是否公开。 |
|  | `onUploadProgress` | `(@Sendable (Double) -> Void)?` | 可空 | OSS `putObject` 阶段进度，范围约定为 `0...1`。 |
| `FileRegistrationRequest` | `fileUuid`、`originalName`、`fileSize`、`mimeType`、`fileMd5` | `String`/`Int` | 必填 | 对象与客户端文件的身份、展示和完整性字段。 |
|  | `isPublic`、`businessType`、`businessId` | `Bool`/`String` | 必填 | 访问范围及业务归属字段。 |
|  | `filePath` | `String` | 必填 | 当前传入对象键，而不是客户端本地路径。 |
|  | `objectKey` | `String` | 必填 | 与 `filePath` 当前相同的 OSS 对象键。 |
|  | `storageType` | `String` | 必填 | 当前固定为 `oss`。 |
| `ManagedFileBusinessUpdateItem` | `fileId` | `Int` | 必填 | 已登记文件主键。 |
|  | `businessType` | `String` | 必填 | 新业务归属类型。 |
|  | `businessId` | `String` | 必填 | 新业务记录 ID。 |

当前代码没有为 `businessType` 建立统一枚举。已确认的实际值包括：`medical_document_upload_source`、`medical_document`、`medical_case`、`health_exam_report`、`examination_report`、`prescription_batch`、`medication_plan`、`medicine_box`、`chat_attachment`；新增值必须同时核对后端、上传入口、绑定入口和列表过滤逻辑。

#### 功能、实现细节与业务流程

| 功能 | 入口 | 处理 | 输出 |
| --- | --- | --- | --- |
| 创建上传模型 | 医疗文档/聊天附件上传入口 | 读取 `Data`，填入业务类型、业务 ID、公开性和进度回调 | `ManagedFileUploadPayload` |
| 生成文件身份 | `FileTransferService.upload` | `UUID()` 生成 `fileUuid`，`FileUtilities.md5Hex` 生成摘要 | 文件身份和完整性信息 |
| 生成 OSS 键 | `FileUtilities.makeObjectKey` | `SparkClient/<UTC日期>/<UUID>/<清理文件名>` | `objectKey` |
| 生成远端记录 | `SparkFileAPI.registerFile` | OSS 成功后提交完整登记请求 | `ManagedFileRecord` |
| 迁移业务归属 | `updateBusinessBinding` | 业务记录保存后用文件 ID 更新 `businessType/businessId` | 更新后的 `ManagedFileRecord` |

主流程为：本地文件可读 → 构造上传负载 → 生成 UUID/MD5/MIME/对象键 → 写缓存 → OSS 上传 → 文件登记 → 业务保存 → 文件绑定。文件模型只承载元数据，不负责 OCR、医疗记录保存或聊天消息同步。

#### 验收标准

- 含路径分隔符的文件名不会逃逸缓存目录或对象键目录。
- 上传登记请求中的大小、MIME、MD5、对象键和业务字段与实际文件一致。
- 不同上传实例即使文件名相同，也不会因为对象键冲突而覆盖彼此。
- 业务模块能够区分“已上传但尚未绑定”和“已绑定到业务记录”的文件。

#### 技术细节与设计代码位置

- 模型：`SparkClient/Projects/Core/FileStorage/FileStorageModels.swift`
- 规则：`SparkClient/Projects/Core/OSS/FileUtilities.swift`
- 医疗文件模型：`SparkClient/Projects/Features/MedicalDocumentUpload/Domain/MedicalDocumentUploadModels.swift`
- 医疗绑定：`SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultMedicalDocumentAttachmentBinder.swift`

### 3.2 STS 凭证、桶配置与 OSS 客户端生命周期

#### 需求说明

客户端不得固化长期 AccessKey。上传和预签名下载使用后端返回的短期 STS 凭证、bucket、region 和 endpoint，并在账号生命周期结束时清理。

#### 基础要求与业务规则

- OSS 凭证通过鉴权接口 `GET /api/v1/oss/sts/credentials/` 获取。
- `SparkOSSConfigurationStore` 在冷启动/登录后尽力预取；上传前若无快照或距离过期少于 300 秒则重新拉取。
- `AssemblyProducts` 将配置 Store 转换为 `OSSManager.credentialsProvider`，由 `OSSManager` 去重并发刷新并创建 `OSSStsTokenCredentialProvider`。
- `OSSClientWrapper` 负责阿里云 SDK 任务到 `async/await` 的桥接，并提供上传进度回调。
- 账号切换或退出登录时，`StorageRegistry` 调用 `FileTransferService.resetRuntimeCredentials()`，同时清理 STS 快照、OSS client 和当前临时凭证。
- 预签名下载 URL 默认有效期为 3600 秒；客户端也支持基于对象键直接生成预签名 URL。

#### 数据模型与完整字段

| 模型 | 字段 | 类型 | 必填/可空 | 含义与处理 |
| --- | --- | --- | --- | --- |
| `OCRSTSCredentialsResponse` | `accessKeyID` | `String` | 必填 | 服务端返回的临时 AccessKey ID；空值使配置无效。 |
|  | `accessKeySecret` | `String` | 必填 | 临时 AccessKey Secret；空值使配置无效。 |
|  | `securityToken` | `String?` | 可空 | STS 安全令牌；传给 `OSSStsTokenCredentialProvider`，生产响应应提供。 |
|  | `expiration` | `String?` | 可空 | 可为 ISO-8601 或 Unix 秒字符串；客户端解析失败时视为未知过期时间。 |
|  | `bucketName` | `String?` | 配置必填 | OSS bucket 名称；空值导致 `AliyunOSSRuntimeConfig` 初始化失败。 |
|  | `region` | `String?` | 配置必填 | OSS 区域；用于配置和服务端契约校验。 |
|  | `endpoint` | `String?` | 配置必填 | OSS endpoint，可含 scheme；空值导致配置无效。 |
| `AliyunOSSRuntimeConfig` | `accessKeyId`、`accessKeySecret` | `String` | 必填 | 从 STS 响应转出的凭证字段。 |
|  | `securityToken` | `String?` | 可空 | 临时安全令牌。 |
|  | `bucketName`、`region`、`endpointURL` | `String` | 必填 | OSS 连接目标；字符串会去除首尾空白。 |
|  | `credentialExpiresAt` | `Date?` | 可空 | 解析后的过期时间；`isFresh(300)` 要求剩余时间大于 300 秒。 |
| `OSSCredentials` | `accessKeyId`、`accessKeySecret` | `String` | 必填 | 供 `OSSManager` 创建 SDK 凭证 Provider。 |
|  | `securityToken` | `String?` | 可空 | STS token。 |
|  | `expiration` | `Date?` | 可空 | 用于 `isExpired` 判断；剩余时间少于 300 秒视为过期。 |
| `OSSConfiguration` | `endpoint`、`bucket`、`region` | `String` | 运行时必填 | 当前全局运行时配置，由 `OSSManager.updateConfiguration` 写入。 |
| `SparkOSSConfigurationStore` | `snapshot` | `AliyunOSSRuntimeConfig?` | 可空 | `@MainActor` 内存快照；不写入磁盘。 |
| `OSSManager` | `client`、`currentCredentials`、`refreshingTask` | SDK/内存/Task | 运行时 | 当前 SDK client、凭证和并发刷新去重任务。 |

#### 接口、功能与实现细节

| 功能 | 方法/接口 | 实现细节 |
| --- | --- | --- |
| 获取 STS | `GET /api/v1/oss/sts/credentials/` | 需要鉴权；`SparkOSSAPI` 通过 `SparkNetworkEngine` 调用并解包标准响应。 |
| 启动预取 | `SparkOSSConfigurationStore.prefetchFromBackend` | 失败只记录 warning，不阻塞启动；后续上传重新请求。 |
| 上传前取配置 | `configurationForUpload(using:)` | 快照剩余时间大于 300 秒直接复用，否则重新请求并替换快照。 |
| 更新 endpoint | `OSSManager.updateConfiguration` | 写入全局 `OSSConfiguration.endpoint/bucket/region`，使用锁保护。 |
| 更新凭证 | `OSSManager.updateCredentials` | 校验 `OSSCredentials.isValid`，创建 `OSSStsTokenCredentialProvider` 和 `OSSClient`。 |
| 并发刷新 | `OSSManager.getValidCredentials` | 已有 `refreshingTask` 时复用同一个 Task，避免并发重复拉取。 |
| 上传/下载 | `OSSClientWrapper` | `ensureInitialized` 后创建 SDK Request，通过 `CheckedContinuation` 等待 `OSSTask`。 |
| 预签名 | `OSSClientWrapper.presignedURL` | 以 bucket、objectKey 和有效期生成可访问 URL。 |
| 退出清理 | `FileTransferService.resetRuntimeCredentials` | 清空 Store 快照、当前凭证、OSS client 和刷新 Task。 |

#### 凭证生命周期业务流程

```text
AppAssembly 创建 SparkOSSConfigurationStore / OSSManager / OSSClientWrapper
  -> 登录或启动时 prefetchFromBackend（尽力预取）
  -> upload 或 makePresignedDownloadURL
  -> configurationForUpload(using:)
  -> 无快照/临近过期：请求 STS；有效：复用快照
  -> OSSManager 更新 endpoint 与临时凭证
  -> OSS SDK 执行上传或生成签名 URL
  -> 账号切换/退出：StorageRegistry 调用 resetRuntimeCredentials
```

STS 失败、字段不全、过期和账号切换必须分别记录；不能把 STS 配置错误包装成文件 MD5 或业务绑定错误。

#### 验收标准

- 首次上传无预取结果时仍能在上传前获取有效 STS。
- 临近过期的凭证不会继续用于新上传。
- 并发上传不会为同一运行时创建无界的凭证刷新任务。
- 退出账号后，旧账号的 STS、OSS client 和凭证不能被新账号复用。
- STS 响应字段不完整时，上传失败原因可定位为配置不完整，而不是泛化为文件损坏。

#### 技术细节与设计代码位置

- 接口：`SparkClient/Projects/Core/Networking/API/OSS/SparkOSSAPI.swift`
- STS 响应：`SparkClient/Projects/Core/Networking/API/OCR/OCRAPI.swift`
- 配置解析：`SparkClient/Projects/Core/OSS/AliyunOSSRuntimeConfig.swift`
- 快照与续期：`SparkClient/Projects/Core/OSS/SparkOSSConfigurationStore.swift`
- 凭证和 SDK client：`SparkClient/Projects/Core/OSS/OSSManager.swift`
- SDK 适配：`SparkClient/Projects/Core/OSS/OSSClient.swift`
- 装配：`SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift`

### 3.3 上传、远端登记与进度

#### 需求说明

上传必须先把二进制写入本地缓存，再直传 OSS，成功后向后端登记文件元数据，最后向业务调用方返回 `ManagedFileRecord`。

#### 基础要求与业务规则

- `FileTransferService.upload` 为每次上传生成 UUID，计算 MD5，清理文件名并推断 MIME。
- 上传前写入账号命名空间下的本地缓存；本地写入采用原子写入，便于失败后重试。
- OSS 上传阶段通过 `onUploadProgress` 向调用方报告 0.0 到 1.0 的进度。
- OSS 上传成功后调用 `POST /api/v1/files/register/` 登记 `FileRegistrationRequest`。
- 后端登记失败时，当前实现保留本地缓存，但没有调用 OSS 删除对象，也没有持久化可恢复的“待登记”任务。
- 医疗文档上传当前按数组顺序串行读取和上传本地文件；`reuploadAll=false` 且已有 `remoteFile` 时跳过上传。

#### 数据模型与字段映射

| 阶段 | 输入字段 | 处理/来源 | 输出字段 |
| --- | --- | --- | --- |
| 业务本地文件 | `MedicalUploadLocalFile.id`、`url`、`displayName`、`mimeType`、`ocrText`、`remoteFile` | 医疗文件选择、OCR 和上传状态持有；`url` 读取为 `Data`。 | 传给 `ManagedFileUploadPayload` 的 `data/fileName`。 |
| 上传负载 | `data`、`fileName`、`businessType`、`businessId`、`isPublic`、`onUploadProgress` | 由医疗用例或聊天发送用例构造；当前无文件大小字段，大小从 `data.count` 计算。 | `FileTransferService.upload` 内部传输上下文。 |
| 传输中间值 | `fileUuid`、`fileMD5`、`safeFileName`、`ymd`、`objectKey`、`mimeType` | 分别由 `UUID()`、`FileUtilities.md5Hex`、文件名清理、UTC 日期、对象键和 MIME 推断产生。 | `FileRegistrationRequest`。 |
| 登记请求 | `fileUuid`、`originalName`、`fileSize`、`mimeType`、`fileMd5`、`isPublic`、`businessType`、`businessId`、`filePath`、`objectKey`、`storageType` | 当前 `filePath == objectKey`，`storageType == "oss"`。 | 后端创建 `ManagedFileRecord`。 |
| 上传进度 | `sent`、`total` | `OSSClientWrapper` 的 `uploadProgress` 转为 `Double(sent)/Double(total)`，再通过 `Task { @MainActor ... }` 回调 UI。 | `0...1` 的进度值。 |

#### 具体实现与功能边界

1. `FileTransferService` 是 `actor`，串行保护同一个服务实例的 API、OSS 配置和缓存编排状态；它不持久化上传任务。
2. 上传顺序固定为：生成 UUID → 计算 MD5 → 写本地缓存 → 获取 STS → 更新 OSS 运行时配置 → `putObject` → `registerFile` → 再校验本地缓存 → 返回登记记录。
3. 本地缓存写入成功不代表远端上传成功；OSS 上传成功也不代表后端文件记录已经存在。
4. `OSSClientWrapper.putObject` 将完整 `Data` 放入 `OSSPutObjectRequest.uploadingData`，当前没有分片、断点续传或后台 `URLSession` 上传。
5. 医疗批量上传由 `UploadMedicalDocumentFilesUseCase.execute` 使用 `for` 循环串行执行；每个文件完成后通过 `withRemoteFile` 放入内存数组。
6. 聊天附件上传由 `SendChatMessageUseCase`/`ChatDetailViewModel` 提供 `chat_attachment` 和附件 UUID 作为初始业务归属，并传递实时上传进度。

#### 上传业务流程与失败恢复

```text
用户选择文件/发送聊天附件
  -> 校验本地 URL 或准备 Data
  -> 组装 businessType、businessId、isPublic、progress callback
  -> FileTransferService.upload
  -> 本地缓存成功？否：结束并报本地写入错误
  -> STS 有效？否：请求/解析 STS；失败则结束
  -> OSS putObject；失败则不调用 registerFile
  -> registerFile；失败则当前返回错误，保留缓存和 OSS 对象
  -> 返回 ManagedFileRecord
  -> 医疗记录/结构化卡片保存成功
  -> updateBusinessBinding 将临时归属改为最终业务归属
```

当前可重试的是“重新执行上传”或“重新调用登记/绑定”；由于没有持久化 `uploaded`/`registered` 任务，应用被杀死后无法自动识别和恢复“OSS 已成功、登记未完成”的中间状态。

#### 验收标准

- OSS 上传成功且文件登记成功时返回完整远端文件记录。
- 网络中断或 OSS 失败时不会返回成功记录，调用方能收到错误。
- 用户取消上传时不应把文件标记为已登记；已产生的本地临时缓存可再次使用或清理。
- 多个医疗源文件中单个文件失败时，失败策略应明确：当前调用会抛错并停止后续文件，已完成文件通过返回值不可见，需补充可恢复批量结果。
- 上传进度不会出现负数、超过 1 或因回调线程导致 UI 崩溃。

#### 技术细节与设计代码位置

- 编排：`SparkClient/Projects/Core/FileStorage/FileTransferService.swift`
- OSS 直传：`SparkClient/Projects/Core/OSS/OSSClient.swift`
- 后端登记：`SparkClient/Projects/Core/Networking/API/File/FileAPI.swift`
- 医疗上传用例：`SparkClient/Projects/Features/MedicalDocumentUpload/Application/UploadMedicalDocumentFilesUseCase.swift`
- 容器注入：`SparkClient/Projects/App/Sources/App/AppContainer.swift`

### 3.4 下载、缓存与完整性校验

#### 需求说明

下载优先复用本地文件缓存；缓存命中时按 MD5 校验，未命中或校验失败时从远端下载，校验通过后再落盘。

#### 基础要求与业务规则

- 缓存根目录位于 `Library/Caches`，系统可在磁盘紧张时清理，因此缓存不是远端数据的唯一事实源。
- 账号命名空间默认为 `guest`，登录后切换为 `account-<accountID>`；切换账号不迁移旧缓存。
- 缓存路径以 `fileUUID` 分目录，文件名经过清理；写入使用 `.atomic`。
- 有 `fileMd5` 时，缓存命中和下载完成后都必须进行 MD5 校验；校验失败的缓存会被删除并重新下载。
- 当前 `download(file:)` 直接使用 `ManagedFileRecord.filePath` 作为 URL；如果 `filePath` 不是有效 URL 会抛出解码错误。
- `SparkFileAPI` 还提供 `GET /api/v1/files/{id}/download-url/`，但 `FileTransferService.download` 当前未调用该后端预签名接口。
- `ChatAttachmentPipeline` 只把本地 `file://` URL 写入附件下载任务表，不覆盖消息中的远端 HTTPS URL。

#### 数据模型与本地存储字段

| 模型/存储 | 字段或路径 | 类型 | 含义 |
| --- | --- | --- | --- |
| `FileCacheManager` | `baseDirectory` | `URL` | 优先为沙盒 `Library/Caches/SparkClient.FileCache`，不可用时降级到 `NSTemporaryDirectory()/SparkClient.FileCache`。 |
|  | `accountNamespace` | `String` | 初始为 `guest`；登录后为 `account-<accountID>`。 |
|  | `<namespace>/<fileUUID>/<sanitizedFileName>` | 文件路径 | 单文件缓存位置；UUID 小写，文件名清理非法字符。 |
| `ChatAttachment` | `id` | `UUID` | 聊天附件本地身份。 |
|  | `type` | `ChatAttachmentType` | `image/video/pdf/file` 等附件或结构化卡片类型。 |
|  | `url` | `URL?` | 远端 HTTP(S) 地址；不得被本地 `file://` 地址覆盖。 |
|  | `text` | `String?` | OCR 文本或结构化附件文本。 |
|  | `fileId` | `Int?` | 文件服务登记后的文件 ID。 |
|  | `fullCacheKey` | `String?` | 与缓存布局对应的 `<fileUUID>/<原始文件名>` 键。 |
|  | `fileMd5` | `String?` | 下载和缓存校验使用的小写 MD5。 |
| `ManagedFileRecord` | `fileUuid`、`originalName` | `String` | 下载缓存的身份和文件名来源。 |
|  | `filePath` | `String?` | 当前普通下载流程使用的远端 URL。 |
|  | `fileMd5` | `String?` | 有值时必须进行本地命中和下载后校验。 |
|  | `objectKey` | `String?` | 可供预签名 URL 生成使用，但普通 `download(file:)` 当前未优先使用它。 |
|  | `fileSize`、`mimeType` | `Int`/`String` | 文件展示和元数据；当前下载校验不单独检查大小。 |

#### 缓存功能与实现细节

| 功能 | 实现 | 关键规则 |
| --- | --- | --- |
| 缓存查询 | `cachedFileURL(fileUUID:fileName:)` | 只检查物理文件是否存在，不自动校验 MD5。 |
| 缓存写入 | `save(data:fileUUID:fileName:)` | 先创建 UUID 目录；同路径文件大小相同则直接复用；否则 `.atomic` 写入。 |
| MD5 校验 | `validateMD5(fileUUID:fileName:expectedMD5:)` | 读取缓存全量 `Data`，使用 `CryptoKit.Insecure.MD5` 比较，不区分大小写。 |
| 单文件清理 | `remove(fileUUID:)` | 删除 UUID 目录下的全部文件。 |
| 全量清理 | `clearAll()` | 删除整个缓存根目录；当前账号切换实际使用的是切换 namespace，不是清空。 |
| 统计 | `cacheStatistics()` | 遍历常规文件，返回文件数量和总字节数。 |
| 下载 | `FileTransferService.download` | 命中缓存且校验通过直接返回；否则下载、校验、写缓存。 |
| 强制刷新 | `download(file:forceRefresh: true)` | 跳过缓存查询，仍会覆盖写入目标缓存。 |

#### 下载业务流程与分支

```text
请求 ManagedFileRecord
  -> forceRefresh == false 且缓存存在？
      -> 有 fileMd5：MD5 正确？是 -> 返回本地 URL
      -> 无 fileMd5：直接返回本地 URL
      -> MD5 错误 -> 删除 UUID 缓存目录
  -> 读取 filePath 并解析 URL
      -> URL 无效 -> decoding 错误，不写缓存
      -> URLSession.shared.data(from:)
  -> 有 fileMd5：计算下载数据 MD5
      -> 不一致 -> 抛错，不写缓存
      -> 一致/无 MD5 -> 原子写入账号缓存
  -> 返回本地 file:// URL
```

`ChatAttachmentPipeline` 的额外流程是：从聊天仓库加载有限数量的 pending 任务 → 标记 `processing` → 将附件快照转换为 `ManagedFileRecord` → 复用缓存或调用下载 → 成功写入本地 URL 并标记 `completed`，异常标记 `failed`。当前没有任务级退避次数和自动重试计数。

#### 验收标准

- 缓存命中且 MD5 正确时不发生网络下载。
- 缓存损坏、MD5 不匹配或强制刷新时重新下载。
- 下载数据 MD5 不匹配时不会写入可用缓存。
- 不同账号不能从对方的缓存命名空间命中文件。
- 聊天附件下载任务能从 `pending` 进入 `processing`、`completed` 或 `failed`，失败不会伪装成已完成。

#### 技术细节与设计代码位置

- 缓存实现：`SparkClient/Projects/Core/FileStorage/FileCacheManager.swift`
- 下载编排：`SparkClient/Projects/Core/FileStorage/FileTransferService.swift`
- 聊天附件任务：`SparkClient/Projects/Features/Chat/Infrastructure/ChatAttachmentPipeline.swift`
- 医疗附件展示：`SparkClient/Projects/Features/Home/Presentation/MedicalLists/MedicalCases/MedicalCaseDetail/AttachmentPill.swift`
- 后端预签名 API：`SparkClient/Projects/Core/Networking/API/File/FileAPI.swift`

### 3.5 文件列表、业务绑定与删除

#### 需求说明

文件服务需要提供按业务类型、业务 ID 和公开性过滤的查询，并支持在业务记录创建后更新文件归属以及删除远端文件记录。

#### 基础要求与业务规则

- 列表接口为 `GET /api/v1/files/`，支持 `business_type`、`business_id`、`is_public` 查询，启用 ETag 缓存和幂等重试。
- 业务绑定接口为 `PATCH /api/v1/files/business/update/`，当前由医疗文档、处方、用药计划、药箱等页面/用例调用。
- 删除接口为 `DELETE /api/v1/files/{id}/`；客户端未在删除成功后自动清理对应本地缓存。
- 文件二进制生命周期与业务元数据生命周期分属 OSS 和文件 API；服务端是否级联删除 OSS 对象需以后端实现确认。

#### 接口契约与数据字段

| 功能 | HTTP | 路径 | 请求/查询字段 | 响应 |
| --- | --- | --- | --- | --- |
| 文件列表 | `GET` | `/api/v1/files/` | `business_type?`、`business_id?`、`is_public?`；布尔值编码为 `1/0`。 | 包装响应中的 `[ManagedFileRecord]`。 |
| 文件登记 | `POST` | `/api/v1/files/register/` | `FileRegistrationRequest` 的 13 个字段：`fileUuid`、`originalName`、`fileSize`、`mimeType`、`fileMd5`、`isPublic`、`businessType`、`businessId`、`filePath`、`objectKey`、`storageType`（其中字段组按 JSON 编码展开）。 | 包装响应中的 `ManagedFileRecord`。 |
| 业务绑定 | `PATCH` | `/api/v1/files/business/update/` | `fileId`、`businessType`、`businessId`。 | 包装响应中的更新后 `ManagedFileRecord`。 |
| 删除文件记录 | `DELETE` | `/api/v1/files/{fileID}/` | 路径参数 `fileID`。 | 成功状态；客户端不读取文件记录响应。 |
| 获取后端下载 URL | `GET` | `/api/v1/files/{fileID}/download-url/` | 查询 `expires`，默认 3600 秒。 | 包装响应 `{ url: String }`；当前只在 `SparkFileAPI` 暴露，未接入普通下载流程。 |

所有上述后端 API 均通过 `SparkNetworkEngine`，使用鉴权头、请求 ID、统一业务错误解码和网络重试策略。列表使用 `CacheableSparkNetworkOperation`、ETag、`serialKey=file.list` 和 120 秒 ETag TTL；登记和绑定不启用 ETag，删除和列表的幂等性策略由 `NetworkStrategy` 分别声明。

#### 业务类型与绑定矩阵

| 上游场景 | 初始 `businessType` | 初始 `businessId` | 最终绑定类型 | 最终 ID |
| --- | --- | --- | --- | --- |
| 医疗文档源文件 | `medical_document_upload_source` | 成员 ID | 由 `MedicalDocumentKind` 映射 | 保存回执 `recordID` |
| 医疗文档 `.auto` | 同上 | 成员 ID | `medical_document` | `recordID` |
| 病历文档 | 同上 | 成员 ID | `medical_case` | `recordID` |
| 体检报告 | 同上 | 成员 ID | `health_exam_report` | `recordID` |
| 医学检查/报告 | 同上 | 成员 ID | `examination_report` | `recordID` |
| 处方 | 同上 | 成员 ID | `prescription_batch` | `recordID` |
| 用药计划 | 同上 | 成员 ID | `medication_plan` | `recordID` |
| 药箱 | 由页面上传入口决定 | 业务 ID | `medicine_box` | 药箱 ID |
| 聊天附件 | `chat_attachment` | 附件 UUID | 发送附件通常保持该类型；结构化医疗卡片保存后按医疗类型重新绑定 | 消息/医疗保存回执 ID |

上表的最终类型映射由 `DefaultMedicalDocumentAttachmentBinder` 和聊天结构化医疗卡片保存逻辑分别实现；文件基础设施不应自行推断医疗类型。

#### 列表、绑定、删除功能流程

```text
列表：业务页面传 businessType/businessID/isPublic
  -> FileTransferService.list
  -> SparkFileAPI.list 构造 query items
  -> SparkNetworkEngine 鉴权 + ETag + 重试
  -> 解包 [ManagedFileRecord]
  -> 页面按 fileId/objectKey/filePath 展示或下载

绑定：业务记录保存成功获得 receipt
  -> 遍历已上传文件
  -> 跳过 remoteFile 为空的本地项
  -> PATCH fileId + 最终 businessType + receipt.recordID
  -> 成功：文件归属完成；失败：记录错误，当前继续处理后续文件

删除：页面确认删除
  -> FileTransferService.delete(fileID)
  -> DELETE /api/v1/files/{id}/
  -> 成功：刷新列表/移除业务引用
  -> 当前不会自动按 fileUuid 删除本地缓存，也未确认服务端是否删除 OSS 对象
```

#### 实现细节与并发规则

- 列表请求的 `serialKey` 固定为 `file.list`，同一服务内通过网络层串行门控避免同类请求无序竞争；绑定使用固定 `file.binding.update`，不同文件的绑定是否允许并行由上层调用方式决定。
- `updateBusinessBinding` 的网络策略标记为非幂等；网络超时后不得无条件重复提交，除非服务端以 `fileId + businessType + businessId` 保证幂等。
- `delete(fileID:)` 标记为幂等，但客户端只删除文件元数据记录，不直接调用 OSS SDK 删除对象。
- Binder 当前逐文件处理并吞掉单文件错误，只记录日志；调用方拿不到失败文件列表，不能把 Binder 返回值当作“全部绑定成功”凭据。
- `filePath`、`objectKey`、`storageType` 可能来自旧服务端记录，下载前必须允许字段缺失，并明确 fallback 到后端预签名接口或错误提示。

#### 验收标准

- 相同业务条件下重复列表请求可使用 ETag 机制减少无变化响应。
- 绑定成功后重新读取文件记录能看到新的业务类型和业务 ID。
- 删除操作失败时不会从 UI 误报为已删除。
- 删除文件后若本地仍有缓存，调用方应有明确的缓存清理策略；当前实现需补充并验证。

#### 技术细节与设计代码位置

- API：`SparkClient/Projects/Core/Networking/API/File/FileAPI.swift`
- 门面：`SparkClient/Projects/Core/FileStorage/FileTransferService.swift`
- 医疗绑定：`SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultMedicalDocumentAttachmentBinder.swift`
- 其他业务绑定示例：`SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/MedicineBoxDetailPage.swift`、`MedicationPlanDetailPage.swift`、`MedicationPrescriptionDetailPage.swift`

## 四、整体业务流程

### 4.1 上传与登记

```text
业务页面/UseCase 提供本地 URL 或 Data
  -> FileTransferService.upload
  -> 生成 fileUUID、清理文件名、计算 MD5、推断 MIME
  -> FileCacheManager 原子写入账号隔离缓存
  -> SparkOSSConfigurationStore 返回有效 STS/bucket/endpoint
  -> OSSManager/OSSClientWrapper 初始化或复用临时凭证
  -> OSS putObject（回调进度）
  -> SparkFileAPI.registerFile 登记文件元数据
  -> 返回 ManagedFileRecord
  -> 业务保存成功后调用 updateBusinessBinding
```

### 4.2 下载与消费

```text
业务页面或 ChatAttachmentPipeline 请求文件
  -> 查询账号隔离本地缓存
  -> 有缓存且 MD5 正确：直接返回本地 URL
  -> 否则校验 filePath/下载 URL
  -> URLSession 下载远端数据
  -> 下载数据 MD5 校验
  -> FileCacheManager 原子写入
  -> 返回本地 file:// URL
```

### 4.3 失败、重试和恢复

| 阶段 | 当前失败行为 | 当前恢复能力 | 当前缺口 |
| --- | --- | --- | --- |
| 读取本地文件 | `Data(contentsOf:)` 抛错 | 调用方重新执行 | 无统一文件读取错误映射 |
| STS 获取/解析 | 抛出网络错误或 `incompleteSTSResponse` | 上传前再次请求 | 无专门用户可见错误模型 |
| OSS 上传 | 抛出 `OSSError.uploadFailed` | 调用方重试整次上传 | 无断点续传/上传任务持久化 |
| 文件登记 | 抛出 API 错误 | 可重试登记，但当前无待登记队列 | OSS 孤儿对象清理未确认 |
| 下载/MD5 | 抛出下载或解码错误 | 下次重新下载 | 未统一使用后端预签名下载 URL |
| 业务绑定 | Binder 记录错误并继续 | 需业务侧再次绑定 | 没有独立待绑定任务 |
| 账号切换/退出 | 停止同步并清理运行时 | 新账号使用新命名空间 | 已下载旧缓存是否按策略保留需产品确认 |

## 五、状态模型

### 5.1 上传状态

当前文件传输服务没有公开的持久化上传状态枚举，状态由调用栈和错误结果隐含表达。业务层至少应能区分以下阶段：

| 状态 | 含义 |
| --- | --- |
| `localReady` | 本地文件可读，尚未开始上传 |
| `caching` | 正在写入本地缓存 |
| `uploading` | OSS 直传进行中，可报告进度 |
| `uploaded` | OSS 对象已写入，但后端文件记录尚未确认 |
| `registered` | 文件 API 登记成功，获得 `ManagedFileRecord` |
| `bound` | 已绑定到具体医疗/用药/聊天业务 |
| `failed` | 任一阶段失败，当前需由调用方重试 |

其中 `uploaded` 是当前实现中最重要但未持久化的中间状态：如果登记失败，客户端无法在应用重启后可靠恢复登记。

### 5.2 下载状态

聊天附件下载管线已有持久化任务状态：`pending → processing → completed/failed`。普通 `FileTransferService.download` 本身不维护任务状态，只通过返回值或抛错表示成功/失败。

### 5.3 账号与缓存状态

- 访客：`guest` 文件缓存命名空间。
- 已登录账号：`account-<accountID>` 文件缓存命名空间。
- 账号切换：先停止聊天实时同步，再执行 StorageRegistry 清理/切换，之后激活新账号。
- OSS 运行时凭证：内存态，不写入文件缓存或业务持久化存储；退出或切换时清理。

## 六、数据与持久化

| 数据 | 所在位置 | 账号隔离 | 敏感性/清理责任 |
| --- | --- | --- | --- |
| 文件二进制缓存 | `Library/Caches/SparkClient.FileCache` | 是，按 namespace | 医疗附件，系统可清理；账号切换由 `FileCacheManager` 切换上下文 |
| STS AccessKey/Token | 内存 `SparkOSSConfigurationStore`、`OSSManager` | 是，运行时清理 | 敏感临时凭证；退出/切换必须清理 |
| 文件元数据 | 后端 `/api/v1/files/` | 由鉴权和业务字段控制 | 服务端事实源；客户端不保存独立文件数据库 |
| 聊天附件任务 | 聊天本地仓库/Core Data | 随聊天会话隔离 | `ChatAttachmentPipeline` 更新任务状态 |
| 业务绑定 | 医疗/用药等远端业务 API | 由业务记录决定 | 文件传输模块只提供更新接口，不拥有医疗事实源 |

当前未发现文件元数据的独立 Core Data Entity 或离线 outbox；文件缓存与聊天附件下载任务不能替代远端文件登记的持久化队列。

## 七、错误模型

| 错误类别 | 现有错误/表现 | 用户或上层处理要求 |
| --- | --- | --- |
| 本地文件不可读 | `Data(contentsOf:)` 原始错误 | 显示文件不可读，并允许重新选择 |
| STS 字段缺失 | `SparkOSSConfigurationError.incompleteSTSResponse` | 不重试无效响应；记录 request ID/接口上下文 |
| STS/网络失败 | `SparkNetworkError` | 按网络策略重试，最终保留可重试语义 |
| OSS 未初始化/上传失败 | `OSSError.clientNotInitialized`、`uploadFailed` | 不登记成功；允许重试，避免重复业务绑定 |
| 文件登记失败 | `SparkNetworkError.httpError` 等 | 将文件置为待登记或清理 OSS 孤儿对象；当前缺少实现 |
| 下载 URL 无效 | `SparkNetworkError.decoding` | 不写缓存，提示附件暂不可用 |
| MD5 不一致 | `SparkNetworkError.decoding` | 删除损坏缓存并重新下载；重复失败应停止重试并上报 |
| 业务绑定失败 | Binder 日志错误 | 不把附件标记为已绑定；当前 Binder 会继续处理其他文件 |
| 取消 | SDK/任务取消错误 | 保留已确认的远端状态，不伪造成功；清理未完成临时任务 |

## 八、与其他模块的接口边界

### 本模块负责

- 文件名/MIME/MD5/对象键等传输元数据准备。
- OSS STS 获取、临时凭证生命周期和 OSS SDK 适配。
- 文件二进制直传、下载、缓存和完整性校验。
- 文件元数据登记、查询、业务绑定和删除 API。
- 账号切换/退出时的缓存命名空间和 OSS 运行时清理。

### 本模块不负责

- 医疗记录、处方、用药计划或病例的领域保存规则。
- OCR 文本抽取和结构化识别。
- 聊天消息的本地落库、同步游标和消息合并。
- 业务页面的文件选择、预览和上传交互。
- 服务端 OSS 对象最终删除、生命周期策略和权限判断；这些需以后端契约确认。

### 上下游接口

| 方向 | 模块 | 接口 |
| --- | --- | --- |
| 上游 | 医疗文档、聊天、医疗/用药附件页面 | `FileTransferService.upload/download/list/updateBusinessBinding/delete` |
| 下游 | Spark 后端 | `SparkOSSAPI`、`SparkFileAPI` |
| 下游 | 阿里云 OSS | `OSSClientWrapper`、`OSSManager` |
| 横向 | 账号运行时 | `StorageRegistry`、`AccountSessionRuntime` |
| 横向 | 聊天同步 | `ChatAttachmentPipeline` 消费下载任务 |

## 九、关键代码对应关系

| 能力 | 代码位置 |
| --- | --- |
| 文件模型与登记请求 | `SparkClient/Projects/Core/FileStorage/FileStorageModels.swift` |
| 文件传输编排 | `SparkClient/Projects/Core/FileStorage/FileTransferService.swift` |
| 文件缓存与账号命名空间 | `SparkClient/Projects/Core/FileStorage/FileCacheManager.swift` |
| 文件名、MIME、MD5、对象键 | `SparkClient/Projects/Core/OSS/FileUtilities.swift` |
| OSS STS API | `SparkClient/Projects/Core/Networking/API/OSS/SparkOSSAPI.swift` |
| 文件 REST API | `SparkClient/Projects/Core/Networking/API/File/FileAPI.swift` |
| STS 快照和续期 | `SparkClient/Projects/Core/OSS/SparkOSSConfigurationStore.swift` |
| OSS SDK async 适配 | `SparkClient/Projects/Core/OSS/OSSClient.swift` |
| OSS 凭证刷新与 client | `SparkClient/Projects/Core/OSS/OSSManager.swift` |
| 医疗文档上传入口 | `SparkClient/Projects/Features/MedicalDocumentUpload/Application/UploadMedicalDocumentFilesUseCase.swift` |
| 医疗业务绑定 | `SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultMedicalDocumentAttachmentBinder.swift` |
| 聊天附件下载 | `SparkClient/Projects/Features/Chat/Infrastructure/ChatAttachmentPipeline.swift` |
| 账号清理注册 | `SparkClient/Projects/App/Sources/App/Architecture/StorageRegistry.swift` |

## 十、测试策略

### 当前实现

- 已有 `SparkNetworkEngineTests` 覆盖通用网络请求、ETag 合并和重试行为。
- 已有医疗文档领域校验测试，但未发现专门覆盖 `FileTransferService`、`FileCacheManager`、`OSSClientWrapper` 或 `SparkFileAPI` 文件接口的测试文件。
- `ChatAttachmentPipeline` 的附件下载状态流转目前也未发现专项测试。

### 应补充的高风险测试

- `FileUtilities`：非法文件名、空文件名、MIME 降级、对象键生成和 MD5。
- `FileCacheManager`：账号隔离、原子写入、同大小缓存命中、MD5 失败清理、清空缓存。
- `SparkOSSConfigurationStore`：预取失败、字段不完整、临近过期续期、过期时间格式解析。
- `OSSManager`：并发凭证刷新去重、凭证过期、reset 后旧 client 不可用。
- `FileTransferService`：缓存失败、OSS 上传失败、登记失败、上传进度、下载 MD5 不一致、强制刷新。
- 文件 API：列表过滤、登记请求字段、绑定和删除的 HTTP 方法/路径/鉴权/幂等策略。
- 业务链路：医疗文件上传后绑定、绑定失败、部分文件上传失败、聊天附件下载任务重试。

## 十一、当前实现、缺口与演进

### 当前实现

- iOS 已形成统一 `FileTransferService`，医疗文档、聊天附件和多个医疗/用药页面共享它。
- 文件使用阿里云 OSS STS 直传，后端只登记文件元数据和业务归属。
- 下载具有账号隔离缓存和 MD5 校验；聊天附件有独立的待下载任务管线。
- 账号生命周期已注册文件缓存命名空间和 OSS 运行时凭证清理。

### 当前缺口

- OSS 上传成功、文件登记失败时没有持久化补偿任务，也没有确认的孤儿对象清理流程。
- 批量医疗文件上传是串行且整体抛错，未返回每个文件的成功/失败结果，应用重启后不能恢复中间进度。
- `FileTransferService.download` 直接消费 `filePath`；虽然 `SparkFileAPI` 已提供后端预签名下载 URL，但两条下载策略尚未统一。
- 删除文件记录后没有由客户端统一清理本地缓存，服务端是否删除 OSS 对象也未从当前 iOS 代码确认。
- 文件传输层没有独立的可观察状态模型、统一面向用户的错误映射和专项测试。
- 代码中保留 `OSSConfiguration` 的全局可变配置以及 `OSSManager.shared`；虽有锁保护，仍增加多账号和测试隔离成本。

### 建议演进

1. 增加持久化 `FileTransferJob`，至少记录本地文件引用、file UUID、object key、MD5、上传阶段、重试次数和账号 ID；登记失败可恢复，收益是避免 OSS 对象与文件元数据永久分离，代价是需要定义任务清理和磁盘占用策略。
2. 将“上传对象”和“登记文件”封装为可补偿事务：登记失败时优先重试登记，超过策略后由服务端按 object key 清理；不要只在客户端猜测删除权限。
3. 统一下载入口优先使用后端鉴权的预签名 URL，并保留 `filePath` 仅作为兼容回退；收益是减少公开直链误用，代价是每次冷下载增加一次文件 URL API 交互。
4. 为批量上传返回逐文件结果和可取消状态，避免一个文件失败使已完成文件只能依赖调用方内存恢复。
5. 用可注入的 `OSSRuntime`/`FileCache` 协议替代全局 SDK 状态，降低单元测试和账号切换的耦合；代价是需要调整 `AssemblyProducts` 和现有调用方。

## 十二、整体验收标准

- [ ] 所有文件上传均通过 `FileTransferService`，业务页面不直接操作 OSS SDK。
- [ ] 上传使用短期 STS，不在客户端保存长期 AccessKey。
- [ ] 上传前完成文件名清理、MIME 推断、MD5 计算和账号隔离缓存。
- [ ] OSS 上传成功后才登记文件；登记未成功时不会返回“已完成”业务状态。
- [ ] 下载优先命中正确账号的本地缓存，并对存在的 MD5 做完整性校验。
- [ ] 文件列表、业务绑定、删除接口的错误能传递到上层且不会伪造成功。
- [ ] 账号切换和退出登录会清理旧 OSS 临时凭证并切换文件缓存命名空间。
- [ ] 聊天附件下载任务支持 pending、processing、completed、failed 状态，不把本地 URL 写回远端附件字段。
- [ ] 具备覆盖文件工具、缓存、STS、OSS 适配、文件 API 和失败补偿的自动化测试。
- [ ] 已明确 OSS 对象删除、下载鉴权、登记补偿和批量上传恢复的服务端契约。
