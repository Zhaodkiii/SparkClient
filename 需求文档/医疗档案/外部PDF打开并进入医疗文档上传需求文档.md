# 外部 PDF 打开并进入医疗文档上传需求文档

> 范围说明：本文描述 SparkClient 通过系统“用 SparkClient 打开”接收外部 PDF 后，在应用完成冷启动、登录态恢复并进入首页后，自动打开医疗文档上传页并把外部 PDF 带入待上传文件列表的需求。本文只描述问题、目标、方案、涉及文件和验收口径，不代表代码已实现。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `MEDICAL-IMPORT-000001` | 外部 PDF 打开并进入医疗文档上传 | 新需求/待实现 | iOS 外部文档打开、冷启动延迟消费、首页上传弹层、`selectedFiles` 注入 |

## 工单 `MEDICAL-IMPORT-000001`：外部 PDF 打开并进入医疗文档上传

### 1. 背景

### Q：现在需要支持什么用户场景？

A：用户在微信、系统文件 App、浏览器、邮件或其他第三方 App 中看到一份 PDF 医疗文档时，可以通过系统分享/打开方式选择 SparkClient。SparkClient 被唤起后，需要等待应用完整启动、恢复登录态并进入首页，然后自动打开医疗文档上传页，把这份外部 PDF 作为待上传文件带入上传流程。

用户期望链路：

```text
外部 App / 文件 App
  -> 用 SparkClient 打开 PDF
  -> SparkClient 冷启动或前台唤起
  -> 完成网络、会话、账号运行时准备
  -> 进入 MainTabCoordinatorView 首页
  -> 自动弹出 MedicalDocumentUploadHostView
  -> selectedFiles 中已有该 PDF
```

### Q：为什么不能在收到 URL 时立刻打开上传页？

A：外部 PDF 可能在 App 未启动、未完成会话恢复、未完成账号准备、甚至还停留在登录/启动页时进入。此时 `MainTabCoordinatorView`、`HomeView` 和 `MedicalDocumentUploadViewModel` 可能还未构建完成，直接展示上传页会出现：

1. 找不到当前登录账号和当前家庭成员。
2. 上传 VM 还未绑定首页依赖。
3. 弹层挂载点尚未进入 SwiftUI 视图树。
4. 冷启动准备任务仍在执行，上传页可能被启动页或登录态切换打断。

因此外部 PDF 需要先进入一个 App 级暂存队列，等待 `AppCoordinatorView` 确认进入已登录主界面后再消费。

### 2. 当前链路

### Q：现有启动链路的关键位置是什么？

A：`AppCoordinatorView` 根据 `lifecycle.sessionState` 决定展示启动页、登录页或主 Tab。

```text
SparkClient/SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift:35-91
```

当状态为 `.signedIn` 且 `lifecycle.preparedAccountID == session.accountID`，并且不需要 onboarding 时，才会构建 `MainTabCoordinatorView`：

```text
MainTabCoordinatorView(
    session: session,
    routeStore: mainTab.routeStore,
    homeDependencies: mainTab.homeDependencies,
    ...
    medicalDocumentUploadViewModel: mainTab.medicalDocumentUploadViewModel,
    ...
)
```

这表示“可以承接外部 PDF 自动打开上传页”的最早稳定时机，应晚于主 Tab 构建并进入首页。

### Q：首页现有上传入口在哪里？

A：首页通过 `HomeFullScreenCover.medicalDocumentUpload` 展示医疗文档上传页。

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift:220-228
```

现有代码会展示：

```swift
MedicalDocumentUploadHostView(
    viewModel: medicalDocumentUploadViewModel,
    aiSettingsViewModel: dependencies.aiSettingsViewModel
)
```

外部 PDF 导入需要复用该入口，避免新增一套上传容器。

### Q：上传页当前如何保存待上传文件？

A：`MedicalDocumentUploadViewModel` 使用 `selectedFiles` 保存本地待上传文件。

```text
SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentUploadViewModel.swift:52-54
```

当前定义：

```swift
/// 本地选择待上传的文件列表
@Published private(set) var selectedFiles: [MedicalUploadLocalFile] = []
```

因此外部 PDF 最终必须被转换为 `MedicalUploadLocalFile`，再写入 `selectedFiles`。

### Q：现有文件选择器能提供什么可复用能力？

A：`MedicalDocumentFilePickerMenu` 已经支持通过系统文件选择器导入 `.pdf`，并把外部安全作用域 URL 复制到 App 临时目录，再生成 `MedicalUploadLocalFile`。

```text
SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentFilePickerMenu.swift
```

外部 PDF 打开也应遵循同一原则：不要长期依赖第三方沙盒 URL，应先复制到 App 可访问的临时目录或导入目录，再交给上传流程。

### Q：当前代码里哪些部分已经实现？

A：当前代码已经补了部分 `MEDICAL-IMPORT-000001` 能力：

1. `SparkClient/SparkClient/Info.plist` 已声明 `CFBundleDocumentTypes` 和 `LSSupportsOpeningDocumentsInPlace=false`。
2. `ContentView.onOpenURL` 已尝试调用 `externalMedicalDocumentImportCoordinator.tryReceive(url)`。
3. `SparkApplicationDelegate.application(_:open:options:)` 已尝试处理外部 URL。
4. `ExternalMedicalDocumentImportCoordinator` 已存在，能校验 PDF、复制临时文件并保存 `pendingDocument`。
5. `MainTabCoordinatorView` 已把 `externalMedicalDocumentImportCoordinator` 传入 `HomeView`。
6. `HomeView` 已监听 `pendingDocument?.id`，并在消费后调用 `medicalDocumentUploadViewModel.prepareForExternalImport(files:)`。
7. `MedicalDocumentUploadViewModel.prepareForExternalImport(files:)` 已实现 reset、注入文件、打开上传页。

### Q：冷启动外部 PDF 无法打开 `MedicalDocumentUploadHostView` 的问题点在哪里？

A：当前实现有两个关键缺口，导致冷启动场景仍可能到不了上传页。

第一个缺口是：**冷启动文档 URL 的入口没有覆盖完整 Scene 启动路径。**

当前入口主要是：

```text
SparkClient/SparkClient/Projects/App/Sources/ContentView.swift:14-19
SparkClient/SparkClient/Projects/App/Sources/App/SparkApplicationDelegate.swift:26-35
```

但冷启动由系统“打开 PDF”拉起 App 时，URL 可能通过 launch options / scene connection options 进入，而不是等 `ContentView.onOpenURL` 已挂载后再投递。当前 `SparkApplicationDelegate.application(_:didFinishLaunchingWithOptions:)` 只初始化依赖，没有读取 `launchOptions[.url]`，也没有明确处理 `UIScene.ConnectionOptions.urlContexts`。如果冷启动 URL 在 SwiftUI 根视图建立前被系统投递，`pendingDocument` 不会生成，后续首页没有可消费任务。

第二个缺口是：**首页消费 pending 后没有直接驱动 fullScreenCover 的实际绑定值。**

当前首页弹层绑定为：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift:52-53
```

```swift
.fullScreenCover(item: $activeFullScreenCover) { cover in
    homeFullScreenCoverContent(cover)
}
```

真正能进入上传页的分支是：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift:220-228
```

但外部 PDF 消费逻辑只执行：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift:201-217
```

核心代码为：

```swift
dependencies.routeStore.route(to: .home, replaceStack: false)
medicalDocumentUploadViewModel.prepareForExternalImport(files: [pending.localFile])
```

`prepareForExternalImport(files:)` 只会把 `medicalDocumentUploadViewModel.isUploadPresented` 改为 `true`，而 `fullScreenCover` 绑定的不是这个值，而是 `activeFullScreenCover`。当前代码依赖：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift:66-73
```

```swift
.onChange(of: medicalDocumentUploadViewModel.isUploadPresented) { isPresented in
    if isPresented {
        activeFullScreenCover = .medicalDocumentUpload
    }
    ...
}
```

冷启动首次进入首页时，`consumePendingExternalMedicalDocumentIfNeeded()` 在 `.task` 中立即执行；如果这次状态变化没有被 `onChange` 捕获，`activeFullScreenCover` 仍然是 `nil`，所以 `HomeView.swift:224-228` 的 `MedicalDocumentUploadHostView` 不会被构建。

### Q：当前实现还缺哪些工单要求？

A：对照 `MEDICAL-IMPORT-000001`，当前仍未完整实现以下要求：

1. 未明确处理冷启动 launch options / scene connection options 中携带的 PDF URL。
2. 未在 App 启动日志中区分“冷启动收到 URL”“onOpenURL 收到 URL”“application open 收到 URL”，排查链路困难。
3. 首页消费 pending 后未直接设置 `activeFullScreenCover = .medicalDocumentUpload`，弹层展示依赖间接 `onChange`。
4. `consumePendingExternalMedicalDocumentIfNeeded()` 没有在 `prepareForExternalImport(files:)` 后立即校验 `activeFullScreenCover` 是否被置位。
5. 当前错误提示挂在 `HomeView`，如果非 PDF/复制失败发生在登录页、启动页或 onboarding 阶段，错误需要等首页出现才可能展示。
6. Info.plist 只声明了 `com.adobe.pdf`，建议补充 `public.pdf`，提高系统文件类型匹配稳定性。
7. 没有冷启动手工验收日志模板，无法判断失败发生在 URL 接收、文件复制、pending 消费还是 fullScreenCover 展示阶段。

### 3. 需求目标

### Q：本工单要达成什么目标？

A：

1. 支持 SparkClient 作为 PDF 文档打开目标，在 iOS 系统“打开方式/分享”中接收外部 PDF。
2. 支持冷启动、后台唤起、前台唤起三种状态下接收外部 PDF。
3. 如果用户已登录，等待 App 完整进入 `MainTabCoordinatorView` 首页后，自动打开 `MedicalDocumentUploadHostView`。
4. 外部 PDF 自动出现在 `MedicalDocumentUploadViewModel.selectedFiles` 中，文件名保持原始 PDF 文件名，MIME 类型为 `application/pdf`。
5. 自动打开上传页后，用户可以直接开始识别，也可以删除该 PDF、补充更多图片/PDF 或关闭上传页。
6. 如果启动时还未登录，应暂存外部 PDF；用户登录并完成账号准备进入首页后再自动打开上传页。
7. 如果外部文件不是 PDF 或文件无法复制，应提示用户“仅支持导入 PDF 文档”或“文件导入失败”，不能打开空上传页。

### 4. 非目标

1. 不在本工单内支持 Word、Excel、TXT、ZIP 等其他文件类型。
2. 不改变现有 OCR、类型识别、结构化抽取、保存接口。
3. 不新增独立的“外部导入上传页”，复用现有 `MedicalDocumentUploadHostView`。
4. 不在收到外部 PDF 后自动开始 AI 识别，默认只自动打开上传页并带入文件。
5. 不在后台静默上传或识别用户文件。

### 5. 解决方案

### Q：推荐整体方案是什么？

A：新增一个 App 级外部文档导入协调器，负责接收、暂存、复制和延迟消费外部 PDF。主 Tab 首页准备完成后，从协调器取出待处理 PDF，注入 `MedicalDocumentUploadViewModel.selectedFiles`，再通过首页现有 fullScreenCover 打开 `MedicalDocumentUploadHostView`。

推荐链路：

```text
系统 openURL / document interaction
  -> ExternalDocumentImportCoordinator.receive(url)
  -> 校验 PDF
  -> 复制到 App 临时目录
  -> 暂存 PendingExternalMedicalDocument
  -> AppCoordinatorView 进入 signedIn 且 preparedAccountID 匹配
  -> MainTabCoordinatorView / HomeView 首页可展示
  -> routeStore 切到 .home
  -> medicalDocumentUploadViewModel.setSelectedFiles([localFile])
  -> medicalDocumentUploadViewModel.presentUploadPage()
  -> HomeView.activeFullScreenCover = .medicalDocumentUpload
  -> HomeView 展示 MedicalDocumentUploadHostView
```

### Q：为什么要新增协调器，而不是直接在 AppDelegate 里操作 ViewModel？

A：`AppDelegate` 或 URL 回调层不应直接持有首页 VM。URL 到达时，主界面可能尚未创建，直接访问会造成生命周期耦合。协调器只保存“待处理导入任务”，由主界面在合适时机消费，符合当前 `AppCoordinatorView -> MainTabCoordinatorView -> HomeView` 的依赖方向。

### Q：外部 PDF 如何转换为上传文件？

A：转换规则与文件选择器保持一致：

1. 对传入 URL 调用 `startAccessingSecurityScopedResource()`。
2. 校验文件类型：
   - `UTType(filenameExtension:)` 符合 `.pdf`；
   - 或 MIME/类型标识符合 `application/pdf`；
   - 或文件扩展名大小写不敏感等于 `pdf`。
3. 复制到 App 可访问目录，建议文件名形如：

```text
external_medical_upload_<UUID>.pdf
```

4. 生成：

```swift
MedicalUploadLocalFile(
    url: copiedURL,
    displayName: originalURL.lastPathComponent,
    mimeType: "application/pdf"
)
```

5. 复制失败或文件不存在时，写入错误状态，由首页展示错误提示。

### Q：进入首页后如何打开上传页？

A：主界面消费外部导入任务时应执行：

```swift
routeStore.route(to: .home, replaceStack: false)
medicalDocumentUploadViewModel.reset()
medicalDocumentUploadViewModel.setSelectedFiles([externalPDF])
medicalDocumentUploadViewModel.presentUploadPage()
activeFullScreenCover = .medicalDocumentUpload
```

页面打开后保持在 `.picking` 阶段，让用户确认文件和文档类型后手动开始识别。

当前代码应优先修正为：

```swift
dependencies.routeStore.route(to: .home, replaceStack: false)
medicalDocumentUploadViewModel.prepareForExternalImport(files: [pending.localFile])
activeFullScreenCover = .medicalDocumentUpload
```

原因是 `HomeView` 的上传弹层实际绑定 `activeFullScreenCover`，不能只依赖 `medicalDocumentUploadViewModel.isUploadPresented` 的 `onChange` 间接触发。

如后续产品要求“导入后自动开始识别”，可改为复用现有：

```swift
medicalDocumentUploadViewModel.prepareAndStart(files: [externalPDF], kind: .auto)
```

但本工单第一期不自动开始识别。

### Q：如果用户当前已经在上传页怎么办？

A：按以下规则处理：

1. 如果上传页处于 `.picking` 且没有进行中的识别任务，可以提示或直接追加/替换外部 PDF。第一期建议采用替换策略，保证外部打开动作语义明确。
2. 如果上传页处于 `.processing` 或 `.result`，不打断当前流程；暂存外部 PDF，并在当前上传页关闭后提示用户打开新导入文件。
3. 如果短时间收到多个 PDF，第一期只保留最后一次导入任务，并记录日志；后续可扩展为队列或多文件合并。

### Q：如果用户未登录怎么办？

A：收到外部 PDF 后先完成本地复制和暂存。启动流程仍按现有登录态判断执行：

1. 未登录：展示登录页，不打开上传页。
2. 登录成功并完成账号准备：进入首页后消费暂存 PDF。
3. 用户取消登录或退出 App：本次暂存任务保留到当前进程生命周期即可，不要求跨重启持久化。

### 6. 涉及文件

### App 启动与外部 URL 接收

| 文件 | 变更说明 |
| --- | --- |
| `SparkClient/SparkClient/Projects/App/Sources/App/SparkApplicationDelegate.swift` | 接收外部 URL / document open 事件，并转发给导入协调器；必须补充冷启动 `launchOptions[.url]` 或 Scene connection options 的处理。 |
| `SparkClient/SparkClient/Projects/App/Sources/ContentView.swift` | 保留 `.onOpenURL` 作为前台/已建 Scene 的 URL 入口，并补充日志标记来源。 |
| `SparkClient/SparkClient/Projects/App/Sources/App/AppEnvironment.swift` | 如当前依赖容器适合放置 App 级服务，在此接入外部文档导入协调器。 |
| `SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift` | 创建并注入外部文档导入协调器实例，确保冷启动和主界面消费的是同一个对象。 |
| `SparkClient/SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift` | 在 `.signedIn` 且账号准备完成后，把协调器传入 `MainTabCoordinatorView` 或触发主界面消费。 |
| `SparkClient/SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` | 监听待导入 PDF，切换到首页并驱动上传 VM 展示上传页；如消费逻辑留在 `HomeView`，主 Tab 需保证首页已实例化并可展示。 |

### 首页与上传页

| 文件 | 变更说明 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Features/Home/Presentation/HomeView.swift` | 复用现有 `HomeFullScreenCover.medicalDocumentUpload`；消费 pending 后必须直接设置 `activeFullScreenCover = .medicalDocumentUpload`，确保 `MedicalDocumentUploadHostView` 被构建。 |
| `SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentUploadViewModel.swift` | 必要时新增 `prepareForExternalImport(files:)`，封装 reset、setSelectedFiles、presentUploadPage。 |
| `SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Domain/MedicalDocumentUploadModels.swift` | 复用 `MedicalUploadLocalFile`，不新增上传文件模型。 |
| `SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Presentation/MedicalDocumentFilePickerMenu.swift` | 可抽取现有 PDF 复制逻辑为公共 helper，避免外部导入和文件选择器各自实现。 |

### 配置与权限

| 文件 | 变更说明 |
| --- | --- |
| `SparkClient/SparkClient/Info.plist` | 注册 PDF 文档类型，声明 SparkClient 可作为 PDF 打开目标；建议 `LSItemContentTypes` 同时包含 `public.pdf` 与 `com.adobe.pdf`。 |

### 7. 数据结构建议

### `PendingExternalMedicalDocument`

建议新增轻量模型：

```swift
struct PendingExternalMedicalDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    let localFile: MedicalUploadLocalFile
    let receivedAt: Date
    let sourceDescription: String?
}
```

### `ExternalMedicalDocumentImportCoordinator`

建议职责：

```swift
@MainActor
final class ExternalMedicalDocumentImportCoordinator: ObservableObject {
    @Published private(set) var pendingDocument: PendingExternalMedicalDocument?
    @Published var errorMessage: String?

    func receiveExternalURL(_ url: URL)
    func consumePendingDocument() -> PendingExternalMedicalDocument?
    func clearError()
}
```

核心要求：

1. 只接收 PDF。
2. 收到 URL 后尽早复制到 App 可访问目录。
3. `pendingDocument` 在被首页消费前不清空。
4. 消费后清空，避免重复弹出上传页。
5. 所有失败都写日志并给出可展示错误。

### 8. UI 行为

### Q：自动打开上传页后页面应是什么状态？

A：应与用户在首页手动点击“上传医疗文档”并选择一个 PDF 后保持一致：

1. 展示 `MedicalDocumentUploadHostView`。
2. 当前阶段为 `.picking`。
3. 文件列表显示外部 PDF 文件名。
4. 用户可删除该 PDF。
5. 用户可继续通过“拍摄 / 照片 / 文件”追加或重新选择文件。
6. 用户点击开始后进入现有识别流程。

### Q：错误提示如何展示？

A：

1. 非 PDF：提示“仅支持导入 PDF 文档”。
2. 文件不存在或无法读取：提示“无法读取该文档，请重新选择文件”。
3. 复制失败：提示“文档导入失败，请稍后重试”。
4. 未登录：不展示错误，保留待导入任务，登录后继续。

### 9. 验收标准

### 功能验收

1. 在系统文件 App 中选择 PDF，使用 SparkClient 打开；App 冷启动后能进入首页并自动弹出医疗文档上传页。
2. 外部 PDF 出现在上传页文件列表中，文件名与原始文件名一致，上传页不为空。
3. App 已在后台时，从外部 PDF 打开 SparkClient，同样能切回首页并弹出上传页。
4. App 已在前台首页时，从外部 PDF 打开 SparkClient，能直接弹出上传页。
5. 未登录状态下打开外部 PDF，登录完成并进入首页后才弹出上传页。
6. 用户关闭上传页后，不会因为同一个 pending PDF 再次自动弹出。
7. 导入非 PDF 文件时不打开上传页，并展示错误提示。
8. 冷启动导入时日志能看到 URL 接收来源、文件复制、pending 消费、`activeFullScreenCover` 置位和 `MedicalDocumentUploadHostView` 展示链路。

### 回归验收

1. 首页手动打开 `MedicalDocumentUploadHostView` 的原流程不受影响。
2. 文件选择器中选择 PDF / 图片的原流程不受影响。
3. 医疗文档上传、OCR、类型识别、结构化抽取、保存流程不受影响。
4. 登录、冷启动、onboarding、版本更新弹层不被外部 PDF 导入打断。

### 日志验收

至少需要覆盖以下日志：

```text
收到外部 PDF 打开请求 source=launchOptions/onOpenURL/applicationOpen/sceneOpen url=...
外部 PDF 已复制到本地 path=...
外部 PDF 等待主界面消费 documentID=...
外部 PDF 已进入医疗文档上传页 documentID=...
外部 PDF 上传弹层已置位 cover=medicalDocumentUpload documentID=...
外部文档导入失败 reason=...
```

### 10. 风险与边界

1. iOS 外部文件 URL 可能只在安全作用域访问期间可读，必须尽早复制。
2. URL 回调可能早于依赖容器构建完成，需要保证协调器在 App 生命周期足够早的位置可用。
3. 如果 onboarding 必须先完成，外部 PDF 只能在 onboarding 结束后打开上传页。
4. 如果当前没有选中家庭成员，上传页可以打开但开始识别前仍需按现有逻辑阻断并提示选择成员。
5. 临时文件清理由现有上传流程或后续统一缓存清理处理，本工单不要求长期持久化外部 PDF。

### 11. 推荐实施顺序

1. 注册 PDF 文档打开能力，确认系统能把外部 PDF URL 传入 SparkClient。
2. 补齐冷启动 URL 捕获：处理 launch options / scene connection options，确保 App 未运行时也能生成 pending。
3. 新增或完善外部文档导入协调器，实现 PDF 校验、复制、pending 暂存与消费。
4. 将协调器接入 App 容器和 URL 回调入口，并确保所有入口使用同一个 coordinator 实例。
5. 在已登录且主 Tab 可用后消费 pending PDF，切到首页、注入上传 VM，并直接设置首页 fullScreenCover 的 `activeFullScreenCover`。
6. 抽取或复用 `MedicalDocumentFilePickerMenu` 的文件复制逻辑，统一生成 `MedicalUploadLocalFile`。
7. 补充日志、错误提示与手工验收用例。
