# DEEPTUTORCHAT-000033 消息卡片 Text 文字使用 Core Markdown 对齐 Chat 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000033 |
| 工单类型 | P1 DeepTutorChat 消息卡片 text 文字 Markdown 渲染收口 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 对齐参考模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 内部 Markdown 目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown` |
| 创建日期 | 2026-08-06 |
| 触发问题 | DeepTutorChat 消息卡片内 text 文字部分需要明确走内部 `Core/Markdown`，并按普通 Chat 消息文字块方式使用 |
| 非目标 | 不做 DeepTutorChat 与 Chat 的整卡样式、布局、交互、工具卡、附件卡、底部操作区的完全对齐 |

## 1. 本工单目标

本工单只处理一个边界清晰的问题：

```text
DeepTutorChat 消息卡片内 `.text` 文字内容，必须使用项目内部 `Core/Markdown` 渲染，并参考普通 Chat 的 text 消息块用法。
```

要达成的结果：

```text
1. DeepTutorChat 助手消息中的 `.text(let text)` 统一进入 `Markdown(text)`。
2. `Markdown` 必须来自 `SparkClient/Projects/Core/Markdown`。
3. 不引入 `swift-markdown-ui`、`cmark-gfm`、`NetworkImage` 或其他外部 Markdown UI 包。
4. DeepTutorChat 的普通 text 文字应支持和 Chat 一致的基础 Markdown 表现：标题、段落、列表、引用、代码块、链接、粗体、斜体、删除线、分隔线。
5. 只对齐“消息卡片内 text 文字部分 Markdown”，不扩大为整个消息卡片 UI 对齐。
```

## 2. Chat 参考实现

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
```

普通 Chat 的 text 渲染逻辑：

```swift
case .text(let text):
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        if context.isMathMode {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Markdown(text)
                .markdownTheme(.chatBubble(
                    foreground: context.message.role == .user ? .white : .primary
                ))
        }
    }
```

对 DeepTutorChat 的参考结论：

```text
1. DeepTutorChat 没有数学模式分支时，可以直接走 `Markdown(text)`。
2. 助手消息 foreground 使用 `.primary`。
3. 如果未来 DeepTutorChat 支持用户 text Markdown，则用户消息 foreground 可参考 Chat 使用 `.white`。
4. 不需要复制 Chat 的所有 block renderer，只参考 `.text` 分支的 Markdown 使用方式。
```

另一个参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatRichMessageBlocks.swift
```

翻译块内也直接使用内部 Markdown：

```swift
Markdown(text)
    .markdownTheme(.chatBubble(foreground: .primary))
    .frame(maxWidth: .infinity, alignment: .leading)
```

## 3. DeepTutorChat 当前入口

相关文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorAssistantResponseView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorMarkdownRenderer.swift
```

当前 DeepTutorChat 助手消息卡片的文字入口：

```swift
case .text(let text):
    DeepTutorMarkdownRenderer(markdown: text)
```

当前 `DeepTutorMarkdownRenderer` 应满足：

```swift
Markdown(markdown)
    .markdownTheme(.chatBubble(foreground: .primary))
    .font(.body)
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
```

验收时需要确认：

```text
1. `DeepTutorMarkdownRenderer.swift` 不能出现 `import MarkdownUI`。
2. `DeepTutorMarkdownRenderer.swift` 不能出现 `MarkdownUI.Markdown`。
3. Xcode 工程不能挂载 `swift-markdown-ui`、`cmark-gfm`、`NetworkImage` 作为 DeepTutorChat Markdown 的 UI 依赖。
4. `.text(let text)` 不得退回 `Text(text)`，除非明确是错误态、调试态或非正文展示。
```

## 4. 明确不做的范围

本工单不包含：

```text
1. 不要求 DeepTutorChat 消息卡片整体布局完全对齐 Chat。
2. 不要求 DeepTutorChat 的 trace、askUser、memberSelection、quiz、visualization、generatedFile 等结构化卡片走 Markdown。
3. 不调整 DeepTutorChat 的按钮、气泡圆角、间距、头像、底部操作区。
4. 不重新引入任何外部 Markdown 包。
5. 不把普通 Chat 的全部渲染器迁移到 DeepTutorChat。
```

本工单只聚焦：

```text
消息卡片内 `.text` 文字部分 Markdown。
```

## 5. 实现建议

### 5.1 保持 DeepTutorChat 独立包装器

建议继续保留：

```text
DeepTutorMarkdownRenderer
```

原因：

```text
1. DeepTutorChat 后续可能需要渲染前 Markdown normalizer。
2. DeepTutorChat 可以独立打开 `.textSelection(.enabled)`。
3. 不需要让 DeepTutorChat 直接依赖 Chat 的 context 和消息角色模型。
```

### 5.2 包装器内部对齐 Chat 的 Core Markdown 用法

推荐实现形态：

```swift
struct DeepTutorMarkdownRenderer: View {
    let markdown: String

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.chatBubble(foreground: .primary))
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
```

如果后续加 normalizer：

```text
1. normalizer 只能处理 DeepTutorChat 的 text 正文。
2. normalizer 不能改变 Chat 模块的 Markdown 行为。
3. normalizer 不能影响工具卡、Quiz 卡等结构化 payload。
```

## 6. 验收标准

### 6.1 代码验收

```text
1. `DeepTutorAssistantBubble.swift` 的 `.text(let text)` 进入 `DeepTutorMarkdownRenderer(markdown: text)`。
2. `DeepTutorAssistantResponseView.swift` 中 fallback 的 `.markdown(message.content)` 也进入同一渲染器。
3. `DeepTutorMarkdownRenderer.swift` 内部使用 `Markdown(markdown)`。
4. `Markdown` 来源为 `SparkClient/Projects/Core/Markdown/Markdown.swift`。
5. 工程文件中没有 DeepTutorChat 为 Markdown UI 引入外部 Swift Package。
```

### 6.2 UI 验收

输入：

```markdown
### 报告总结

这是一段 **重点文字**。

---

#### 1. 肾脏相关

- 左肾囊肿大小 **0.8×0.7cm**
- 每年复查即可
```

期望：

```text
1. `报告总结` 显示为标题，不显示原始 `###`。
2. `肾脏相关` 显示为小标题，不显示原始 `####`。
3. 分隔线正常显示。
4. 列表分行显示。
5. `重点文字` 与 `0.8×0.7cm` 保持粗体。
```

### 6.3 非目标验收

```text
1. trace 卡片仍由 `DeepTutorTracePanelView` 渲染。
2. quiz 卡片仍由 `DeepTutorQuizCardView` 渲染。
3. askUser/memberSelection 卡片仍由各自专用 View 渲染。
4. 本工单完成后不要求 DeepTutorChat 卡片外观与 Chat 完全一致。
```

## 7. 回归检查命令

建议执行：

```bash
rg -n "MarkdownUI|NetworkImage|cmark-gfm|swift-markdown-ui" SparkClient.xcodeproj SparkClient/Projects/Features/DeepTutorChat
rg -n "case \\.text\\(let text\\)|DeepTutorMarkdownRenderer|Markdown\\(" SparkClient/Projects/Features/DeepTutorChat SparkClient/Projects/Features/Chat/Presentation/ChatView
```

期望：

```text
1. DeepTutorChat 不出现 `MarkdownUI`。
2. DeepTutorChat 的 `.text` 正文仍进入 `DeepTutorMarkdownRenderer`。
3. DeepTutorMarkdownRenderer 内部使用 `Core/Markdown` 的 `Markdown`。
```

## 8. 结论

本工单要求的是“DeepTutorChat 消息卡片内 text 文字 Markdown 能力”对齐普通 Chat 的 text 文字块，不是全量 UI 对齐。

最终判定标准只有一个：

```text
DeepTutorChat 的 `.text` 正文必须稳定走内部 `Core/Markdown`，并呈现与 Chat text 消息一致的基础 Markdown 格式。
```
