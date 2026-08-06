# DEEPTUTORCHAT-000031 DeepTutor 消息 Markdown 格式未渲染与换行保真修复工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000031 |
| 工单类型 | P1 消息 Markdown 渲染缺失 + 流式文本换行保真 + 内部 Markdown 容错增强 |
| 当前范围 | 只创建问题定位与修复工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 内部 Markdown 目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown` |
| 创建日期 | 2026-08-06 |
| 触发问题 | DeepTutorChat 助手回答中 `###`、`####`、`---`、列表符号原样显示，消息没有呈现标题、分隔线、列表等 Markdown 样式 |
| 关联变更 | 已移除外部 `swift-markdown-ui / cmark-gfm / NetworkImage`，DeepTutorChat 改为使用内部 `Core/Markdown` |
| 关联提交 | `9aa4d0a Use internal markdown for DeepTutorChat` |

## 1. 用户现象

截图中的回答正文显示为一整段大文本：

```text
###这份是57岁男性的泌尿系超声报告，整体没有严重的异常提示，两个诊断都属于中老年男性非常常见的良性情况，我给你逐项拆解： ---####1.肾脏相关：...
```

用户期望：

```text
1. `###` 应该渲染为标题。
2. `---` 应该渲染为分隔线。
3. `####1.肾脏相关：` 应该成为小标题，或至少不原样挤在正文中。
4. `-` / `1.` 这类结构应该换行显示为列表或分段。
5. 重点内容如 `0.8×0.7cm`、`5ml` 的粗体仍要保留。
```

当前实际：

```text
1. `###`、`####` 没有变成标题。
2. `---` 没有变成分隔线。
3. 多个段落被合并成一行。
4. 内部 Markdown 只能解析少量 inline 样式，所以粗体可能生效，但块级结构整体失效。
```

## 2. 已定位代码事实

### 2.1 DeepTutorChat 已经接入内部 Markdown

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorMarkdownRenderer.swift
```

当前实现：

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

结论：

```text
DeepTutorChat 没有继续走外部 MarkdownUI，消息确实进入了内部 `Core/Markdown/Markdown.swift`。
```

### 2.2 消息卡片直接把文本块交给 Markdown 渲染器

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorAssistantResponseView.swift
```

关键链路：

```swift
case .text(let text):
    DeepTutorMarkdownRenderer(markdown: text)
```

结论：

```text
UI 层没有把 Markdown 降级成 Text。问题不在 `DeepTutorMarkdownRenderer` 是否被调用，而在传入的 markdown 文本是否仍保留合法块级 Markdown 结构，以及内部 parser 是否能识别。
```

### 2.3 内部 Markdown 块级 parser 对标题语法要求严格

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown/MarkdownSegment.swift
```

当前标题解析逻辑：

```swift
private static func parseHeading(_ line: String) -> MarkdownSegment? {
    let leadingHashes = line.prefix { $0 == "#" }.count
    guard (1 ... 6).contains(leadingHashes) else { return nil }
    let remainder = line.dropFirst(leadingHashes)
    guard remainder.first == " " else { return nil }
    return .heading(
        level: leadingHashes,
        text: remainder.trimmingCharacters(in: .whitespaces)
    )
}
```

影响：

```text
1. `### 标题` 可以识别。
2. `###标题` 不识别。
3. `####1.肾脏相关：` 不识别，因为 `####` 后面不是空格。
```

### 2.4 内部 Markdown 分隔线必须单独成行

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown/MarkdownSegment.swift
```

当前分隔线解析：

```swift
private static func isThematicBreak(_ line: String) -> Bool {
    let compact = line.replacingOccurrences(of: " ", with: "")
    guard compact.count >= 3 else { return false }
    if compact.allSatisfy({ $0 == "-" }) { return true }
    if compact.allSatisfy({ $0 == "*" }) { return true }
    if compact.allSatisfy({ $0 == "_" }) { return true }
    return false
}
```

影响：

```text
1. 单独一行 `---` 可以识别。
2. `正文： ---####1.肾脏相关` 不能识别，因为它已经不是单独一行。
```

### 2.5 流式合并阶段按 delta 直接拼接

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMarkdownPreserver.swift
```

当前合并逻辑：

```swift
let fromEvents = events.compactMap { event -> String? in
    if case let .contentDelta(text, _, _) = event { return text }
    return nil
}.joined()
```

风险：

```text
如果上游 `contentDelta` 本身丢了 `\n`，或者后续模型输出没有在 `---` / `####` 前后写换行，最终传给 Markdown parser 的就是一整段文本。内部 parser 只能按行识别块级 Markdown，一整段自然不会渲染出标题和分隔线。
```

## 3. 根因判断

### 3.1 直接根因

当前截图里的 Markdown 标记不是合法块级 Markdown：

```text
###这份...
---####1.肾脏相关：
####2.输尿管、膀胱...
```

缺少必要换行与空格：

```text
### 这份...

---

#### 1. 肾脏相关：
```

所以内部 Markdown parser 只能把它当普通段落处理。

### 3.2 系统根因

```text
1. DeepTutorPromptBuilder 要求“Prefer structured markdown headings”，但没有明确要求标题后必须有空格、块级元素必须独立成行。
2. DeepTutorMarkdownPreserver 只做保留与评分，没有对常见 AI 输出的非标准 Markdown 做渲染前规范化。
3. 内部 Markdown parser 比 MarkdownUI/cmark-gfm 更严格，移除外部包后缺少对 `###标题`、`---####标题` 这类模型输出的兼容。
4. 缺少一个针对 DeepTutor 最终回答 Markdown 保真的单元测试，导致 UI 从外部 MarkdownUI 切到内部 Markdown 后没有覆盖这类真实输出。
```

## 4. 修复方案

### 4.1 P0 修复：DeepTutor 渲染前 Markdown 规范化

新增一个 DeepTutor 专用文本规范化层，建议位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMarkdownNormalizer.swift
```

职责：

```text
1. 在不破坏代码块的前提下，将 `###标题` 规范化为 `### 标题`。
2. 将正文中的 `---####` 规范化为 `\n\n---\n\n#### `。
3. 将 `####1.` 规范化为 `#### 1.`。
4. 将连续小标题前补换行：`正文。#### 2.` -> `正文。\n\n#### 2.`
5. 只处理块级 Markdown 标记，不改 inline 粗体、链接、图片、代码片段。
```

接入点建议：

```text
1. `DeepTutorMarkdownRenderer` 初始化前对传入 markdown 做 display normalizer。
2. 或 `DeepTutorMarkdownPreserver.renderMarkdownText(from:)` 返回前做 final answer normalizer。
3. 优先选择 UI 渲染前 normalizer，避免修改已落库原文；稳定后再评估是否在落库前修正。
```

### 4.2 P1 修复：Prompt 约束模型输出合法 Markdown

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPromptBuilder.swift
```

需要补充输出约束：

```text
1. Markdown 标题必须使用 `### 标题`，`#` 后面必须有一个空格。
2. 标题、分隔线、列表必须独立成行，前后保留空行。
3. 不要输出 `---####标题` 这种连续块级标记。
4. 医疗报告解读建议使用固定结构：摘要、关键发现、逐项解释、建议、何时就医。
```

### 4.3 P1 修复：增强内部 Markdown parser 容错

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown/MarkdownSegment.swift
```

建议增强：

```text
1. `parseHeading` 可兼容 `###标题`，但只在标题内容不是 `#` 且非空时生效。
2. 对 `####1.` 这类医学解读常见编号标题兼容为标题。
3. 容错应放在 parser 或 normalizer 其中一处，避免重复处理导致输出异常。
```

注意：

```text
如果选择在 `Core/Markdown` 做通用容错，需要补充更多测试，因为会影响 Chat、科普、设置等所有内部 Markdown 使用方。
```

### 4.4 P2 修复：增加 Markdown 保真日志

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

建议新增调试日志：

```text
deeptutor.markdown.render_input message=<id> length=<n> newlineCount=<n> headingTokenCount=<n> normalized=<true|false>
```

默认只在异常时打印：

```text
1. 文本包含 `###` 但 newlineCount 为 0。
2. 文本包含 `---####`。
3. 文本包含正则 `#{1,6}\\S`。
```

## 5. 验收标准

### 5.1 UI 验收

输入以下文本：

```markdown
###这份是57岁男性的泌尿系超声报告，整体没有严重异常
---####1.肾脏相关：
- 左肾囊肿伴囊壁钙化，大小 **0.8×0.7cm**。
- ✅ 结论：每年复查即可。
####2.输尿管、膀胱：
排尿后残余尿仅 **5ml**，属于非常好的结果。
```

渲染后必须满足：

```text
1. 第一行显示为标题，不显示原始 `###`。
2. `肾脏相关` 与 `输尿管、膀胱` 显示为小标题，不显示原始 `####`。
3. `---` 显示为分隔线或至少不原样贴在正文中。
4. 两个 `-` 项显示为列表或独立段落。
5. `0.8×0.7cm`、`5ml` 保持粗体。
```

### 5.2 数据保真验收

```text
1. 如果原始流式 delta 带有换行，最终 `message.content` 不得丢失换行。
2. 如果原始文本不规范，渲染层可规范化显示，但 debug export 仍能看到原始文本。
3. 代码块内的 `###`、`---` 不得被 normalizer 修改。
```

### 5.3 回归测试

建议新增测试：

```text
1. `DeepTutorMarkdownNormalizerTests`
2. `MarkdownSegmentParserTests`
3. `DeepTutorMarkdownPreserverTests`
```

测试用例：

```text
1. `###标题` -> heading。
2. `---####1.标题` -> thematicBreak + heading。
3. 代码块内 `###not heading` 不被改写。
4. 普通正文 `C###` 不被误判为标题。
5. `####2.输尿管、膀胱` 可渲染为标题。
```

## 6. 风险与注意事项

```text
1. 不建议重新引入 `swift-markdown-ui`，本工单目标是在内部 `Core/Markdown` 上补齐 DeepTutor 需要的渲染能力。
2. 不要只改 prompt，因为历史消息和不稳定模型输出仍可能出现非标准 Markdown。
3. 不要直接把所有 `###` 前都加换行，代码块、URL、普通文本可能被误伤。
4. 若修改通用 `Core/Markdown` parser，需要确认 Chat 主消息、科普文章、报告详情等其他调用方不会受影响。
```

## 7. 建议拆分任务

```text
1. 新增 `DeepTutorMarkdownNormalizer`，先只在 `DeepTutorMarkdownRenderer` 使用。
2. 为截图样例和代码块样例补测试。
3. 更新 `DeepTutorPromptBuilder`，约束模型输出合法 Markdown。
4. 视测试结果决定是否把标题容错下沉到 `Core/Markdown/MarkdownSegmentParser`。
5. 添加低频异常日志，帮助后续确认线上是否仍有换行丢失。
```

## 8. 结论

本问题不是 DeepTutorChat 没调用 Markdown 渲染器，而是最终进入内部 Markdown 的文本不满足块级 Markdown 解析条件：

```text
1. 标题符号后缺少空格。
2. 分隔线和标题没有独立成行。
3. 流式/模型输出形成了一整段文本。
4. 内部 Markdown parser 比之前外部 MarkdownUI 更严格。
```

推荐按“渲染前规范化 + prompt 约束 + parser 测试”的方式修复，既保留内部 Markdown 方案，也能覆盖真实 AI 输出里的非标准 Markdown。
