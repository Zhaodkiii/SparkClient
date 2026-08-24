# CHAT-000035 对话内新建 Thread 切换后输入框无法输入修复工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000035 |
| 工单类型 | P1 缺陷修复 / Chat / Thread 原地切换 / Composer / UIKit-SwiftUI 状态同步 |
| 当前阶段 | 问题排查与落地方案；本工单不直接修改现有 Swift 代码 |
| 目标工程 | `SparkClient` |
| 关联工单 | `CHAT-000030` |
| 影响入口 | 对话详情页右上角“新建对话”按钮 |
| 影响组件 | 专业版输入框、简洁版输入框 |
| 创建日期 | 2026-08-22 |

## 1. 问题描述

用户在对话详情页点击右上角“新建对话”按钮后，页面没有发生导航跳转，并已在当前页面完成 Thread 切换；但是切换到新 Thread 后，对话底部输入区域无法正常输入内容。

复现路径：

```text
进入已有对话 A
  ↓
点击右上角“新建对话”
  ↓
本地创建 Thread B
  ↓
ChatView.activeThreadID 从 A 切换为 B
  ↓
消息区显示 Thread B 的首条 guide card
  ↓
点击输入框并输入文字
  ↓
文字无法保留，表象为输入框无法输入
```

预期行为：

1. Thread B 切换完成后输入框可以立即获得焦点。
2. 输入内容写入 Thread B 对应的 `ChatComposerDraft`。
3. Thread A 和 Thread B 的草稿彼此隔离。
4. 切回 Thread A 时可以恢复 A 的原草稿。
5. 专业版与简洁版输入框行为一致。

## 2. 排查结论

### 2.1 结论等级

本问题已有明确代码证据，可以直接确定主要根因，不需要先增加临时日志才能开始修复。

已确认：

- Thread 切换后，SwiftUI 输入组件收到的新 `threadID` 是正确的。
- `draftBinding` 会根据输入组件当前 `threadID` 构造新 Binding。
- UIKit `UITextView` 的 delegate Coordinator 被 SwiftUI 复用。
- Coordinator 只保留初始化时的旧 `parent`，后续没有接收新的 SwiftUI View/Binding。
- 用户输入通过旧 Coordinator 写入旧 Thread 草稿。
- 当前新 Thread 的空草稿随后通过 `updateUIView` 覆盖 `UITextView.text`。

因此用户看到的“无法输入”，本质上不是键盘或 `UITextView.isEditable` 被关闭，而是输入内容被写入旧 Thread 后又被新 Thread 的空值回刷。

### 2.2 主根因：Coordinator 持有过期 Binding

文件：`SparkClient/Projects/Features/Chat/Presentation/Composer/HanlinChatInputView.swift`

当前专业版输入框：

```swift
private struct HanlinChatTextUIKitView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        recalculateHeight(for: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: HanlinChatTextUIKitView

        init(_ parent: HanlinChatTextUIKitView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
```

问题点：

1. `Coordinator.parent` 是 `private let`。
2. `parent` 只在 `makeCoordinator()` 中设置一次。
3. `updateUIView` 没有把当前 `self` 更新给 Coordinator。
4. `ChatView.activeThreadID` 改变时，SwiftUI 可以复用原 `UIViewRepresentable` 和原 Coordinator。
5. 新 SwiftUI View 中的 `text` 已绑定 Thread B，但 Coordinator 仍持有 Thread A 的 Binding。

### 2.3 同类缺陷：简洁版输入框也存在

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift`

`ChatComposerTextView` 使用相同结构：

```swift
final class Coordinator: NSObject, UITextViewDelegate {
    private let parent: ChatComposerTextView
}
```

其 `updateUIView` 同样没有执行：

```swift
context.coordinator.parent = self
```

因此：

- 当前若默认使用专业版，问题首先在 `HanlinChatTextUIKitView` 暴露。
- 用户切换到简洁版 Composer 后，也可能出现同样的 Thread 切换输入异常。
- 修复不能只覆盖当前默认 Composer，必须同时修复两个 `UIViewRepresentable`。

### 2.4 项目内已有正确实现可参考

文件：`SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerTextView.swift`

当前 DeepTutor 输入框已正确处理 SwiftUI View 更新：

```swift
func updateUIView(_ textView: UITextView, context: Context) {
    if textView.text != text {
        textView.text = text
    }
    context.coordinator.parent = self
    ...
}

final class Coordinator: NSObject, UITextViewDelegate {
    var parent: DeepTutorComposerTextView
}
```

该实现可以作为本工单直接参考，不需要新增一套输入状态架构。

## 3. 完整故障链路

```text
ChatView 当前显示 Thread A
  ↓
HanlinChatInputView(threadID: A)
  ↓
draftBinding 指向 stateStore.composerDrafts[A].text
  ↓
HanlinChatTextUIKitView.makeCoordinator()
  ↓
Coordinator.parent 固化为 Thread A 的 Binding
  ↓
用户点击新建对话，创建 Thread B
  ↓
ChatView.activeThreadID = B
  ↓
HanlinChatInputView(threadID: B)
  ↓
SwiftUI 复用原 UITextView 与 Coordinator
  ↓
新 View 的 draftBinding 指向 composerDrafts[B].text
  ↓
Coordinator.parent 仍指向 composerDrafts[A].text
  ↓
用户在 UITextView 输入“你好”
  ↓
textViewDidChange 将“你好”写入 Thread A
  ↓
ChatStateStore 发布 composerDrafts 变化并触发界面刷新
  ↓
当前 Thread B 的 text 仍为空
  ↓
updateUIView 将 UITextView.text 重置为空
  ↓
用户看到输入字符立即消失，误以为输入框不可输入
```

## 4. 当前实现事实

### 4.1 Thread 切换入口已使用运行时 Thread ID

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`

当前已存在：

```swift
@State private var activeThreadID: UUID

private var currentThreadID: UUID {
    activeThreadID
}
```

Composer 创建时也已传入：

```swift
ChatComposerView(threadID: currentThreadID, ...)
HanlinChatComposerView(threadID: currentThreadID, ...)
```

说明 Thread B 已传入输入组件，问题不在 `ChatView` 仍传递初始 `threadID`。

### 4.2 草稿存储已经按 Thread 隔离

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift`

当前草稿容器：

```swift
@Published private var composerDrafts: [UUID: ChatComposerDraft] = [:]
```

输入框 Binding：

```swift
Binding(
    get: { stateStore.draft(for: threadID) },
    set: { stateStore.setDraft($0, for: threadID) }
)
```

说明领域状态和缓存结构已经支持 Thread 隔离；缺陷发生在 UIKit delegate 到 SwiftUI Binding 的桥接层。

### 4.3 `isSending` 不是当前主根因，但仍是状态设计风险

`ChatStateStore.isSending` 当前是全局 Bool，而不是按 Thread 存储。专业版若处于发送中，会禁用部分输入区操作；但右上角新建按钮本身在 `isSending == true` 时已禁用，因此本次成功创建并切换 Thread 的场景通常发生在 `isSending == false`。

结论：

- 本次“输入文字立即消失”的主要根因是 Coordinator 绑定过期。
- `isSending` 全局化不是本工单最小修复的阻塞项。
- 后续若支持“旧 Thread 后台继续生成，同时切到新 Thread 输入”，需要另开工单把发送状态按 Thread 隔离。

## 5. 修复目标

### 5.1 核心目标

Thread 原地切换后，所有 UIKit 输入代理必须把用户输入回写到当前 Thread 的 SwiftUI Binding，而不是初始化时的旧 Binding。

### 5.2 非目标

本工单不处理：

- 改造消息发送协议。
- 修改 guide card 科普问题生成流程。
- 修改 Thread 创建和服务端同步协议。
- 重新设计 Composer UI。
- 将全局 `isSending` 改成按 Thread 状态。
- 改变旧 Thread 草稿保留策略。

## 6. 推荐落地方案

### 6.1 专业版：允许 Coordinator 更新 parent

文件：`SparkClient/Projects/Features/Chat/Presentation/Composer/HanlinChatInputView.swift`

建议将：

```swift
private let parent: HanlinChatTextUIKitView
```

改为：

```swift
var parent: HanlinChatTextUIKitView
```

并在 `updateUIView` 最前面同步当前 View：

```swift
func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self

    if uiView.text != text {
        uiView.text = text
    }
    recalculateHeight(for: uiView)
}
```

为什么放在最前面：

- 本轮更新开始后，任何后续 delegate 回调都应使用当前 Binding。
- 避免更新 `uiView.text`、高度或滚动状态时产生同步/异步回调并访问旧 parent。

### 6.2 简洁版：同步应用同一修复

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift`

建议：

```swift
func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self

    if uiView.text != text {
        uiView.text = text
    }
    recalculateHeight(for: uiView)
}

final class Coordinator: NSObject, UITextViewDelegate {
    var parent: ChatComposerTextView
}
```

专业版与简洁版必须同批修改和回归，避免用户切换 Composer 样式后再次遇到同类问题。

### 6.3 Thread 切换时重置输入高度状态

当前专业版和简洁版输入高度分别保存在组件内部 `@State inputHeight`。切换 Thread 后组件可能继续复用旧 Thread 的高度。

建议优先验证 Coordinator 修复后高度是否能在 `updateUIView` 中通过 `recalculateHeight` 自动恢复。如果仍存在旧高度闪烁，可采用以下一种方式：

方案 A，优先：让输入子树以 Thread 为身份重建。

```swift
HanlinChatComposerView(...)
    .id(currentThreadID)
```

方案 B：在输入组件中监听 `threadID`，将 `inputHeight` 重置为最小高度。

本工单不建议把 `.id(currentThreadID)` 作为主修复，因为它会销毁并重建完整 Composer 子树、焦点、Sheet 和附件选择瞬时状态。它可以作为防御性补充，但不能替代 Coordinator 更新。

### 6.4 Thread 切换时的焦点规则

切换到新 Thread 后建议：

1. 旧 Thread 的键盘焦点允许自然结束。
2. 新 Thread 不强制自动弹键盘，避免新建后干扰 guide card 浏览。
3. 用户点击新 Thread 输入框后必须正常成为 first responder。
4. 不应因 guide card 后台生成或本地回写抢走输入焦点。

## 7. 修改文件清单

| 文件 | 必须修改 | 落地内容 |
| --- | --- | --- |
| `SparkClient/Projects/Features/Chat/Presentation/Composer/HanlinChatInputView.swift` | 是 | Coordinator `parent` 改为可更新；`updateUIView` 同步当前 parent |
| `SparkClient/Projects/Features/Chat/Presentation/ChatComposerView.swift` | 是 | 简洁版应用相同 Coordinator 生命周期修复 |
| `SparkClient/Tests/Chat/...` | 是 | 增加 Thread 切换后的草稿回写和隔离测试 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` | 视验证结果 | 仅在输入高度/瞬时状态仍串线时增加 Composer identity 或切换重置；主修复不需要改 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift` | 否 | 现有按 Thread 草稿字典可以复用 |

## 8. 建议测试设计

### 8.1 Coordinator 当前 Binding 更新测试

建议为两个 UIKit 输入桥接层补充可测试边界，至少验证：

```text
初始 parent 绑定 Thread A
  ↓
updateUIView 注入 Thread B parent
  ↓
模拟 textViewDidChange("B-draft")
  ↓
Thread B 草稿变为 B-draft
  ↓
Thread A 草稿保持不变
```

### 8.2 详情页 Thread 切换回归

| 用例 | 操作 | 预期 |
| --- | --- | --- |
| A1 | 在 Thread A 输入草稿，不发送，新建 Thread B | B 输入框为空；A 草稿保留 |
| A2 | 在 Thread B 输入“你好” | 文本稳定显示，不会立即消失 |
| A3 | B 输入后切回 A | A 恢复原草稿，不显示 B 草稿 |
| A4 | 再切回 B | B 恢复自己的草稿 |
| A5 | Thread B guide card 后台生成完成并回写 | 输入中的文字和焦点不丢失 |
| A6 | 专业版执行 A1-A5 | 全部通过 |
| A7 | 简洁版执行 A1-A5 | 全部通过 |
| A8 | 新建后立即点击输入框快速输入 | 首字符不丢失 |
| A9 | 中文拼音存在 marked text 时切换 Thread | 不串写，不崩溃，组合输入行为可预测 |
| A10 | 新建 Thread 失败 | 仍停留 A，A 输入框继续可输入 |

### 8.3 发送目标验证

除输入可见性外，还必须验证：

1. Thread B 输入完成后点击发送，用户消息写入 B。
2. AI 请求上下文使用 B 的消息和配置。
3. A 不出现 B 的用户消息。
4. B 发送完成后草稿清空，A 草稿不被清空。

## 9. 可观测性方案

主因已确认，生产代码不要求长期保留逐字符日志。若首次修复后仍无法输入，可在 Debug 构建临时增加以下低频日志，禁止记录实际输入内容：

```text
chat.composer.text_view.update style=hanlin thread=<id> coordinatorThread=<id>
chat.composer.text_view.begin_editing style=hanlin thread=<id>
chat.composer.text_view.change style=hanlin thread=<id> length=<n>
chat.composer.text_view.update style=signal thread=<id> coordinatorThread=<id>
```

为了能打印 Thread ID，可将仅用于诊断的 `threadID` 显式传入 UIKit bridge；日志只记录短 ID 和字符长度，不记录健康信息或输入正文。

修复验收后应删除逐次 `textViewDidChange` 日志，避免高频刷屏。

## 10. 风险与边界

### 10.1 异步高度回写仍可能引用旧 View

`recalculateHeight` 中存在 `DispatchQueue.main.async`：

```swift
DispatchQueue.main.async {
    measuredHeight = nextHeight
}
```

该闭包捕获的是调用时 View 的 Binding。Thread 快速连续切换时，旧回调可能晚于新 Thread 执行。

建议：

- 先验证该回调只影响视图高度、不影响草稿内容。
- 若出现高度串线，给异步高度回写增加当前身份校验，或用 `.id(threadID)` 隔离输入子树。
- 不要把高度状态问题与文本 Binding 主根因混在一个不可验证的大改中。

### 10.2 全局 `isSending` 后续风险

当前 `isSending` 属于整个 `ChatStateStore`。若未来允许发送中切换 Thread，新 Thread 输入框可能被旧 Thread 发送状态影响。

本工单验收条件仍以当前产品规则为准：发送中禁止点击右上角新建。未来要放开该限制时，应将发送状态、取消句柄和流式占位消息按 Thread 隔离。

### 10.3 使用 `.id(threadID)` 的副作用

强制重建 Composer 会同时重置：

- 输入框焦点。
- 输入高度。
- 附件菜单展示状态。
- 图片/文件选择瞬时状态。
- 专业版内部展开 Sheet 状态。

因此只在确有状态复用残留时采用，并补充对应 UI 回归。

## 11. 实施顺序

1. 修复 `HanlinChatTextUIKitView.Coordinator.parent` 的更新机制。
2. 修复 `ChatComposerTextView.Coordinator.parent` 的更新机制。
3. 验证 A → B 输入、草稿隔离和发送目标。
4. 验证 guide card 后台生成回写不会清空输入。
5. 验证输入高度和焦点是否存在残留。
6. 仅在仍有残留时增加 Thread identity 或高度重置。
7. 补充专业版、简洁版自动化测试。

## 12. 整体验收标准

1. 对话内点击右上角新建按钮后，成功切换到新 Thread。
2. 新 Thread 输入框可以立即响应点击并输入文本。
3. 输入字符不会立即消失或回退为空。
4. 输入内容只写入当前新 Thread 的草稿。
5. 旧 Thread 草稿不会被新 Thread 输入覆盖。
6. 新 Thread 发送的消息只进入新 Thread。
7. guide card 插入、AI 科普问题生成与服务端同步期间，用户输入不丢失。
8. 专业版 `HanlinChatComposerView` 验收通过。
9. 简洁版 `ChatComposerView` 验收通过。
10. 快速连续切换 Thread 不发生草稿串线或崩溃。
11. 修复不依赖强制导航跳转或重建整个 `ChatView`。
12. 不记录用户输入正文到日志。

## 13. 最终结论

本缺陷的主要原因不是 Thread 创建失败、输入框被显式禁用或草稿缓存未按 Thread 隔离，而是两个 UIKit `UITextView` 桥接组件的 Coordinator 生命周期处理不完整：Coordinator 保留了旧 Thread 的 SwiftUI Binding。

推荐按项目内 `DeepTutorComposerTextView` 的现有实现方式，在每次 `updateUIView` 时更新 Coordinator 的 `parent`。该方案改动范围小、与现有架构一致，并能从根源保证 Thread 原地切换后输入回写到当前草稿。
