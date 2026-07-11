# Swift 6 生产包问题：Release 归档触发 EarlyPerfInliner 编译器崩溃

## 工单摘要

| 项目 | 内容 |
| --- | --- |
| 问题类型 | Swift 编译器 Release 优化阶段崩溃 |
| 影响流程 | Archive / 生产包归档 |
| 影响配置 | Release，`-O`，Whole Module Optimization |
| 当前工具链 | Apple Swift 6.3.3（`swiftlang-6.3.3.1.3 clang-2100.1.1.101`） |
| 触发文件 | `SecondCameraImageEditorViewController+Blur.swift` |
| 触发声明 | `SecondCameraEditorBlurWeakRef<T>` 的合成 `deinit`，源码约第 253 行 |
| 严重程度 | 阻断生产包发布 |
| 推荐处理 | 将弱引用容器改为显式 `nonisolated` 的非泛型容器，规避优化器缺陷 |

## 结论

本次失败不是一般的 Swift 语法、类型或并发诊断，而是 **Swift 6.3.3 编译器自身在 Release SIL 优化阶段崩溃**。

日志显示 `swift-frontend` 在执行 `EarlyPerfInliner` 时，处理以下合成析构函数发生异常：

```text
SecondCameraEditorBlurWeakRef<T>.deinit
```

触发代码同时具备以下特征：

- 泛型引用类型：`SecondCameraEditorBlurWeakRef<T: AnyObject>`；
- 弱引用存储：`weak var object: T?`，编译器需要合成弱引用清理逻辑；
- `@unchecked Sendable` 一致性声明；
- 工程启用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，但该辅助类型未显式声明 `nonisolated`；
- Release 使用 `-O` 与 Whole Module Optimization，Debug 的 `-Onone` 不经过相同优化路径。

这些条件共同触发 Swift 6.3.3 `EarlyPerfInliner` 的布局兼容性处理缺陷。源码本身不一定存在语义错误，但当前写法会稳定阻断生产归档，应通过小范围重构规避编译器崩溃。

## 日志证据

### 编译器而非业务代码主动报错

日志没有常见的 `error: ...` 源码诊断，而是输出编译器栈：

```text
While running pass ... SILFunctionTransform "EarlyPerfInliner"
on SILFunction ... SecondCameraEditorBlurWeakRef ... deinit
swift-frontend ... isCallerAndCalleeLayoutConstraintsCompatible
Command SwiftCompile failed with a nonzero exit code
```

`isCallerAndCalleeLayoutConstraintsCompatible`、`SILPerformanceInliner` 和 `swift-frontend` 信号栈表明，失败发生在 Swift 编译器优化器内部。

### 只在生产构建路径触发

归档命令包含：

```text
-swift-version 6
-O
-default-isolation=MainActor
-enable-default-cmo
```

项目 Release 配置同时启用了：

```text
SWIFT_COMPILATION_MODE = wholemodule
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_VERSION = 6.0
```

Debug 使用 `SWIFT_OPTIMIZATION_LEVEL = -Onone`，因此 Debug 编译成功不能证明 Archive 可以成功。

## 触发代码

当前代码位于：

```text
SparkClient/Projects/Features/CustomCamera/CustomCamera/Internal/Editing/
ImageEditor/SecondCameraImageEditorViewController+Blur.swift:253
```

```swift
private final class SecondCameraEditorBlurWeakRef<T: AnyObject>: @unchecked Sendable {
    weak var object: T?
    init(_ object: T?) { self.object = object }
}
```

该通用盒子分别包装 `SecondCameraImageEditorViewController` 和 `UISwitch`。编译器会为泛型实例生成并优化包含弱引用销毁逻辑的 `deinit`；崩溃恰好发生在这一合成函数上。

## 推荐修复方案

### 方案 A：改为显式非隔离、非泛型的专用弱引用上下文

这是本工单的首选方案。它同时去掉触发崩溃的泛型析构特化，并明确该并发桥接容器不属于 MainActor。

将两个泛型盒子：

```swift
let selfBox = SecondCameraEditorBlurWeakRef(self)
let senderBox = SecondCameraEditorBlurWeakRef(sender)
```

替换为一个专用上下文：

```swift
let weakReferences = SecondCameraEditorBlurWeakReferences(
    viewController: self,
    toggle: sender
)
```

容器实现：

```swift
private nonisolated final class SecondCameraEditorBlurWeakReferences: @unchecked Sendable {
    weak var viewController: SecondCameraImageEditorViewController?
    weak var toggle: UISwitch?

    init(
        viewController: SecondCameraImageEditorViewController?,
        toggle: UISwitch?
    ) {
        self.viewController = viewController
        self.toggle = toggle
    }
}
```

主线程回调中的引用相应调整：

```swift
DispatchQueue.main.async {
    switch result {
    case .failure(let error):
        print("[ImageEditor] Face Detection Error: \(error)")
        weakReferences.toggle?.isOn = false
        modal.dismiss {}

    case .success(let boxes) where boxes.isEmpty:
        weakReferences.toggle?.isOn = false
        modal.dismiss {}

    case .success(let boxes):
        guard let vc = weakReferences.viewController else {
            modal.dismiss {}
            return
        }
        // 后续现有逻辑保持不变。
    }
}
```

方案优势：

- 删除 `SecondCameraEditorBlurWeakRef<T>` 泛型特化和对应的泛型合成 `deinit`，直接避开日志中的崩溃函数；
- `nonisolated` 与容器承担跨执行器捕获的用途一致，避免默认 MainActor 隔离参与 SIL 优化；
- 保留弱引用，避免 Vision 回调持有控制器或开关；
- 所有 UIKit 对象仍只在 `DispatchQueue.main.async` 内使用，不改变 UI 线程约束；
- 修改范围只限于相机模糊识别文件，不影响整个工程的优化等级。

### 方案 B：最小改动，仅为泛型盒子添加 `nonisolated`

可先作为快速验证：

```swift
private nonisolated final class SecondCameraEditorBlurWeakRef<T: AnyObject>: @unchecked Sendable {
    weak var object: T?
    init(_ object: T?) { self.object = object }
}
```

该方案可能避开“默认 MainActor + 泛型析构”的优化组合，但仍保留日志明确指向的泛型弱引用 `deinit`。如果 Archive 仍在同一 SIL 函数崩溃，应立即采用方案 A，不建议继续叠加编译器属性。

## 临时止血方案

如果发布窗口不允许立即重构，可只对问题文件或最小文件集合降低优化级别，例如使用 `-Onone`。该方式仅用于短期发版验证：

```text
OTHER_SWIFT_FLAGS（对应文件）= -Onone
```

不建议把整个 Release target 改为 `-Onone`，因为会增加包体、降低运行性能，并掩盖其他仅在优化构建出现的问题。Xcode 对单个 Swift 文件设置编译参数的维护成本也较高，完成方案 A 后应移除临时参数。

若团队允许切换工具链，也可使用更新的稳定版 Xcode 复测；但在当前工具链仍需归档的情况下，代码规避比等待编译器修复更可控。

## 不建议的处理方式

| 处理方式 | 原因 |
| --- | --- |
| 反复清理 DerivedData 后继续 Archive | 编译器正在稳定处理同一 SIL 函数时崩溃，清缓存通常不能消除源码触发条件。可清理一次排除缓存，但不能作为修复。 |
| 全局关闭 Release 优化 | 影响整个应用性能与包体，扩大变更范围。 |
| 删除 `weak` 改为强引用 | 可能让 Vision/弹窗回调延长控制器生命周期，甚至形成引用环，改变业务内存语义。 |
| 直接删除 `@unchecked Sendable` | 可能恢复 Swift 6 的跨隔离域编译错误，且没有消除泛型弱引用析构特化。 |
| 给 UIKit 类型声明 `@unchecked Sendable` | 会把不安全承诺扩散到系统 UI 类型，无法修复编译器优化器问题。 |
| 将 Vision 工作全部切到主线程 | 可能造成图像识别期间掉帧或 UI 卡顿。 |

## 实施步骤

1. 按方案 A 将两个泛型弱引用盒子合并为专用非泛型上下文。
2. 保持 Vision 检测在非隔离辅助方法中运行。
3. 保持 UIKit 对象访问位于主队列回调内。
4. 删除不再使用的 `SecondCameraEditorBlurWeakRef<T>`。
5. 清理一次该项目 DerivedData，避免旧 SIL 产物干扰验证。
6. 先执行 Release 真机编译，再执行 Product > Archive。
7. 对归档产物完成模糊人脸功能回归测试。

## 验收标准

- [ ] Release `-O` + Whole Module Optimization 编译成功。
- [ ] Product > Archive 成功生成 `.xcarchive`，不再出现 `EarlyPerfInliner` 堆栈。
- [ ] 不通过全局 `-Onone`、关闭 Swift 6 或关闭默认 MainActor 隔离绕过问题。
- [ ] 自动人脸模糊可以正常识别人脸并添加模糊区域。
- [ ] 无人脸和 Vision 识别失败时，开关正确恢复为关闭状态。
- [ ] 检测期间退出页面不会崩溃，控制器可以正常释放。
- [ ] Thread Sanitizer 与 Main Thread Checker 不报告新增问题。
- [ ] Staging 配置同步完成相同归档验证，因为它同样使用 Whole Module Optimization。

## 风险与回滚

方案 A 不改变业务流程，只调整闭包捕获所使用的弱引用容器，风险较低。若修改后出现功能回归，可以回滚该文件，并临时对问题文件使用 `-Onone` 完成紧急构建；不要回滚整个 Swift 6 迁移或全局 MainActor 配置。

## 后续跟踪

- 记录当前 Xcode 完整版本、macOS 版本和最小复现代码，便于提交 Swift 编译器反馈。
- 后续升级 Xcode 后移除任何临时优化参数，并重新使用 Release Archive 验证。
- 对 Swift 6 迁移中新增加的泛型 `@unchecked Sendable` 辅助类进行一次扫描；与 UI、弱引用和默认 MainActor 同时出现的类型应优先显式声明隔离域或改为专用值域容器。
