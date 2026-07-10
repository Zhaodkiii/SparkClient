# CAMERA-000009 SecondCamera 公共预览内核底座迁移需求工单

> 文档性质：底座能力迁移工单。只整理 `SecondCamera` 公共预览与相机适配相关文件，不包含聊天输入框、医疗档案或其他业务模块接入。

## 1. 工单目标

将 `SupportClient` 当前与图片预览相关的未提交代码整理为 `SecondCamera` 通用客户端底座能力，形成：

1. 可独立使用的公共只读图片预览。
2. 可复用的缩放、加载、错误和空状态视口。
3. `fullScreenCover` 公共入口。
4. 原相机拍摄后预览页对公共视口的适配。
5. 相机现有编辑、继续拍摄、删除和确认流程保持不变。

源目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/SecondCamera
```

## 2. 业务边界

### 2.1 本工单包含

- 图片预览输入模型。
- 图片按需加载与 ImageIO 解码。
- 图片缩放、拖动、居中和圆角显示。
- 加载中、文件失效、解码失败和空数据状态。
- 只读多图选择状态。
- 只读缩略图轨道。
- 公共全屏预览页面及 SwiftUI View 扩展。
- `DefaultCustomCapturedMediaScreen` 对公共视口的接入。
- 编辑结果变化后刷新预览 identity。

### 2.2 本工单不包含

- `HanlinChatInputView` 或其他聊天输入框接入。
- `ChatComposerAttachmentPreview`、`ChatStateStore` 等聊天模型。
- 医疗档案、Markdown、上传列表等业务接入。
- PDF、Office 文档和普通文件 Quick Look 预览。
- 附件上传、下载、OCR、发送和临时文件业务管理。
- 第二阶段公共编辑结果回传。
- 任何业务路由或业务文案。

公共预览只接受底座输入模型或本地图片 URL，不直接依赖业务模块的 `FilePreviewInput`。

## 3. 目标目录结构

需要在 `SecondCamera` 内形成以下目录：

```text
SupportClient/Projects/Features/SecondCamera/CustomCamera/Presentation/
├── Preview/
│   ├── SecondCameraMediaPreviewInput.swift
│   ├── SecondCameraMediaPreviewViewport.swift
│   ├── SecondCameraPreviewImageLoader.swift
│   ├── SecondCameraReadOnlyPreviewStore.swift
│   ├── SecondCameraReadOnlyPreviewRail.swift
│   ├── SecondCameraPublicMediaPreview.swift
│   ├── View+SecondCameraMediaPreview.swift
│   └── UIKit/
│       ├── SecondCameraImagePreviewLayout.swift
│       ├── SecondCameraRoundedImageContainerView.swift
│       ├── SecondCameraUIKitImagePreviewRepresentable.swift
│       └── SecondCameraUIKitImagePreviewViewController.swift
└── Default/
    └── CapturedMedia/
        ├── DefaultCustomCapturedMediaScreen.swift
        ├── DefaultCustomCapturedMediaScreen+PreviewToolbar.swift
        └── MultiPreview/
            └── SecondCameraPreviewRailCellView.swift
```

相机状态配套文件保持原目录：

```text
SupportClient/Projects/Features/SecondCamera/CustomCamera/Internal/MultiCapture/
└── SecondCameraPreviewItem.swift
```

## 4. 公共预览文件清单

### 4.1 待新增文件

| 文件 | 职责 |
| --- | --- |
| `SecondCameraMediaPreviewInput.swift` | 底座输入模型，包含稳定 ID、本地图片 URL 和可选显示名 |
| `SecondCameraMediaPreviewViewport.swift` | 无状态视口，统一渲染图片、加载、错误和空状态 |
| `SecondCameraPreviewImageLoader.swift` | 使用 ImageIO 按需解码原图和缩略图 |
| `SecondCameraReadOnlyPreviewStore.swift` | 只读会话状态，维护项目、选中项和加载任务，不提供增删 API |
| `SecondCameraReadOnlyPreviewRail.swift` | 只读缩略图轨，只允许选择图片 |
| `SecondCameraPublicMediaPreview.swift` | 公共全屏预览页面，组合 Viewport、关闭按钮和只读轨道 |
| `View+SecondCameraMediaPreview.swift` | 提供 `View.secondCameraMediaPreview` 的 `fullScreenCover` 入口 |

### 4.2 当前 Git 已暂存、可直接迁移的文件

以下 4 个文件已存在于当前未提交代码中，迁移时移动到 `Presentation/Preview/UIKit/`：

```text
CustomCamera/Presentation/UIKitPreview/
├── SecondCameraImagePreviewLayout.swift
├── SecondCameraRoundedImageContainerView.swift
├── SecondCameraUIKitImagePreviewRepresentable.swift
└── SecondCameraUIKitImagePreviewViewController.swift
```

能力范围：

- `UIScrollView` 双指缩放与拖动。
- 图片按可视区域计算最小缩放比例。
- 最大缩放倍率配置。
- 小图自动居中。
- 图片或 revision 变化时重置缩放。
- 旋转或布局变化时保留相对缩放比例。
- 圆角裁剪。
- SwiftUI 与 UIKit 桥接。

## 5. 相机适配文件清单

当前 Git 未暂存改动中，以下文件属于公共预览的相机适配，需要随底座改造保留：

| 文件 | 需要保留的改动 |
| --- | --- |
| `Internal/MultiCapture/SecondCameraPreviewItem.swift` | 增加 `previewRevision`、`previewImageIdentity` 和 `bumpPreviewRevision()` |
| `Presentation/Default/CapturedMedia/DefaultCustomCapturedMediaScreen.swift` | 用公共 Viewport/UIKit 预览替换原图片 View；传入稳定 identity；保留相机按钮和流程 |
| `Presentation/Default/CapturedMedia/DefaultCustomCapturedMediaScreen+PreviewToolbar.swift` | 质量变化后 bump revision，刷新 UIKit 预览并重置缩放 |

`DefaultCustomCapturedMediaScreen` 的以下接口和行为不得改变：

```swift
init(_ context: SecondCameraCapturedMediaContext)
```

```swift
.setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
```

继续保持：

- `discardAction`。
- `continueCaptureAction`。
- `acceptMediaAction`。
- 相册追加。
- 删除媒体。
- 图片编辑和裁剪。
- 输出质量调整。
- 视频预览。
- 最终结果确认和回传。

## 6. 公共 API 最小范围

底座只需要提供以下入口语义：

```swift
struct SecondCameraMediaPreviewInput: Identifiable, Sendable {
    let id: UUID
    let fileURL: URL
    let displayName: String?
}
```

```swift
extension View {
    func secondCameraMediaPreview(
        isPresented: Binding<Bool>,
        inputs: [SecondCameraMediaPreviewInput],
        selectedID: UUID? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View
}
```

第一阶段固定为只读模式：

- 可以关闭、缩放、拖动和切换图片。
- 不可以添加、删除、编辑、裁剪、保存或确认输出。

相机内部仍使用现有可编辑流程，不通过公共只读 API 驱动相机行为。

## 7. 复制边界

### 7.1 复制到 SecondCamera 底座

```text
Presentation/Preview/**
Internal/MultiCapture/SecondCameraPreviewItem.swift 中的 revision 改动
DefaultCustomCapturedMediaScreen.swift 中的 Viewport 接入改动
DefaultCustomCapturedMediaScreen+PreviewToolbar.swift 中的 revision 改动
```

### 7.2 不复制

```text
SupportClient/Projects/Features/Chat/**
SupportClient/Projects/Core/UI/FilePreview/UnifiedFilePreview.swift
SupportClient/Projects/Core/UI/FilePreview/View+UnifiedFilePreview.swift
SupportClient/Projects/Core/UI/FilePreview/QuickLookPreviewBridge.swift
任何医疗、上传、Markdown 或业务路由文件
```

`SupportClient.xcodeproj/project.pbxproj` 当前未提交的 modulemap membership 删除与公共预览无关，不纳入本工单，也不要随公共预览代码一起复制。

## 8. 完成标准

- [ ] `Presentation/Preview/` 下文件可作为完整目录复制。
- [ ] 公共预览不 import 任何业务模块。
- [ ] 公共预览使用自己的 `SecondCameraMediaPreviewInput`。
- [ ] 只读 Store 没有追加、删除和编辑 API。
- [ ] `View.secondCameraMediaPreview` 使用 `fullScreenCover`。
- [ ] `DefaultCustomCapturedMediaScreen` 已改用公共 Viewport。
- [ ] 相机 builder 和 `init(_ context:)` 保持不变。
- [ ] 相机编辑、继续拍摄、删除和确认流程无回归。
- [ ] 工程配置中的无关改动未混入迁移提交。
