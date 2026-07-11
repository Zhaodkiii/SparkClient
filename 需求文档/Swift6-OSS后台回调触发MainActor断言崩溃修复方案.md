# Swift 6 升级问题：OSS 后台回调触发 MainActor 断言崩溃

## 结论

这是一次 **Swift 6 严格并发运行时检查** 触发的隔离违规，不是阿里云 OSS SDK 在 `OSSTask.m:470-485` 发生了内存访问错误。

工程启用了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。因此未显式声明隔离域的 `OSSClientWrapper.awaitTask(_:)` 被默认隔离到 `MainActor`，其传给 Objective-C SDK 的 `successBlock` 也要求在主执行器运行；但 OSS SDK 通过 `NSOperationQueue` 的后台队列调用该闭包。Swift 6 检测到当前执行器与闭包要求的 MainActor 不一致，于 `_swift_task_checkIsolatedSwift` 主动触发断言并中止进程。

推荐修复：**仅把 OSS SDK 的回调桥接方法标记为 `nonisolated`，不要把整个 OSS 客户端或 SDK 回调强行切到主线程。** UI 更新仍应通过 `Task { @MainActor in ... }` 完成。

## 影响范围

| 项目 | 位置 | 说明 |
| --- | --- | --- |
| 工程并发配置 | `SparkClient.xcodeproj/project.pbxproj` | 启用 Swift 6，且默认 Actor 为 `MainActor`。 |
| Swift 回调桥接 | `Projects/Core/OSS/OSSClient.swift:164` | `awaitTask(_:)` 将 `OSSTask` 回调转换为 `async/await`。 |
| SDK 实际调用点 | `Projects/Core/Utilities/Objective-C/AliyunOSSSDK/OSSTask/OSSTask.m:471-485` | SDK 在选定 executor 上执行 `successBlock`。 |

## 崩溃链路

```text
Swift async 调用 OSSClientWrapper.awaitTask
        │
        ├─ 工程默认隔离：awaitTask / successBlock 被视为 MainActor
        │
OSS SDK 网络请求完成
        │
        ├─ NSOperationQueue（后台并发队列）执行 OSSTask continuation
        │
        ├─ OSSTask.m:482 调用 Swift successBlock
        │
        └─ Swift 6 校验：后台队列 ≠ MainActor
               └─ _swift_task_checkIsolatedSwift → dispatch_assert_queue_fail → 崩溃
```

堆栈中的两处关键证据：

- `OSSClientWrapper.awaitTask` 的 `successBlock` 位于第 5、6 帧，说明崩溃发生在 Swift 回调桥接闭包进入时。
- `OSSTask.m:482` 仅执行 `return block(task);`；它是触发点而非根因。上游第 9、10、26-30 帧表明该回调来自后台 `NSOperationQueue`。

## 根因说明

### 1. Swift 6 的默认 Actor 隔离扩大了隔离范围

项目设置为：

```text
SWIFT_VERSION = 6.0
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

该设置使应用 target 中未单独标注的声明默认属于 `MainActor`。`OSSClientWrapper` 没有显式标注，`awaitTask(_:)` 因而成为 MainActor 隔离方法。

### 2. Objective-C SDK 不知道 Swift 的 Actor 语义

`OSSTask` 的 `continueWithSuccessBlock:` 默认使用 `OSSExecutor.defaultExecutor`。该 executor 会在当前调用栈或全局后台队列执行回调；本次堆栈显示最终位于 `NSOperationQueue`。它无法自动跳转至 Swift 的 MainActor。

### 3. 运行时检查比编译器诊断更晚暴露问题

Objective-C Block 缺少完整的 Swift `@Sendable` / actor 元数据，编译期不一定能完整报告这个跨语言边界问题。Swift 6 在闭包实际运行时补做执行器一致性校验，因此表现为运行期断言崩溃。

## 推荐修复

在 `Projects/Core/OSS/OSSClient.swift` 中，仅给 SDK 回调桥接方法添加 `nonisolated`：

```swift
/// 该方法只桥接 OSS SDK 的后台回调，不访问 UI 或 MainActor 状态。
/// SDK 可以在任意 executor 调用 continuation 闭包。
private nonisolated func awaitTask<T: AnyObject>(_ task: OSSTask<T>) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        task.`continue`(successBlock: { task in
            if let error = task.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
            return nil
        })
    }
}
```

### 为什么该修复正确

- `nonisolated` 让 `successBlock` 不再携带 MainActor 前置条件，OSS 可以在它自己的后台 executor 正常调用。
- 方法内部只读取 SDK task 的完成状态并恢复 continuation，不读取 UI、ViewModel 或其他 MainActor 状态，职责与隔离域一致。
- `continuation.resume(...)` 只负责恢复等待中的 Swift 任务；等待方会根据自身隔离域恢复执行。它不等价于在 OSS 后台线程直接操作 UI。
- 上传、下载进度回调中的 UI 派发应保持现有模式：`Task { @MainActor in progressCallback?(progress) }`。

## 若出现 Swift 6 编译期 Sendable 诊断

旧版 Objective-C SDK 的 `OSSTask` 没有 `Sendable` 标注。若在给 `awaitTask` 添加 `nonisolated` 后出现 SDK 类型跨隔离域警告或错误，应先确认 SDK 模块导入采用预并发兼容方式：

```swift
@preconcurrency import AliyunOSSiOS
```

本项目当前通过 Bridging Header 暴露 OSS 类型；对应做法是在**单一 OSS 适配层**集中处理该兼容边界。不要把 `@preconcurrency`、`@unchecked Sendable` 或 `nonisolated(unsafe)` 扩散到业务层。

如果 Swift 接口仍无法表达 SDK 的线程安全契约，可在适配层将 SDK 调用封装在专用串行执行器/actor 内，并只向外暴露 `Data`、`URL`、`Error` 等可安全传递的值。该方案适合作为后续 SDK 升级前的长期隔离策略，不是本次崩溃的首选最小修复。

## 不建议的修复方式

| 方式 | 不建议原因 |
| --- | --- |
| 修改 `OSSTask.m:482` 或把 SDK 所有 continuation 强制派发主线程 | 会把网络完成回调、解码和续接工作压到主线程，影响流畅度，且修改第三方 SDK 增加维护成本。 |
| 为 `OSSClientWrapper` 整体加 `@MainActor` | 会把上传、下载和 SDK 调用语义错误地绑定到 UI 域，不能解决 SDK 后台回调进入闭包的断言。 |
| 使用 `MainActor.assumeIsolated` | 回调明确发生在后台队列时会继续触发断言，属于错误承诺。 |
| 使用 `nonisolated(unsafe)` 作为首选 | 会绕开更多安全检查，无法表达“方法不依赖 MainActor”的真实语义；本问题应优先使用普通 `nonisolated`。 |
| 关闭 `SWIFT_DEFAULT_ACTOR_ISOLATION` 或退回 Swift 5 | 能掩盖问题，但会削弱 Swift 6 并发迁移收益，并可能让其他 UI 越界继续潜伏。 |

## 验收清单

- [ ] Debug 与 Release 均完成一次 OSS 上传、内存下载、文件下载和预签名 URL 请求。
- [ ] 在 Xcode 开启 Thread Sanitizer 后重复上传/下载，不出现 actor/executor 断言。
- [ ] 主线程检查器无网络回调或大数据处理被错误调度到主线程的告警。
- [ ] 进度回调仍在主线程更新 UI；后台调用方不直接触碰 UI。
- [ ] 取消、网络失败、STS 过期等异常路径均只恢复一次 continuation。
- [ ] 真机与模拟器均不再出现 `_swift_task_checkIsolatedSwift`、`dispatch_assert_queue_fail`。

## 后续建议

将阿里云 OSS SDK 视为一个独立的“遗留 Objective-C 异步边界”：所有 `OSSTask`、`OSSRequest`、`OSSResult` 只停留在 `Projects/Core/OSS` 适配层，业务层仅使用 `async throws` API 和 Swift 值类型。这样后续升级 SDK 或调整 Swift 并发策略时，影响面会保持可控。
