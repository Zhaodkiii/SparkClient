# DEEPTUTORCHAT-000010 回答卡片、工具思考流程与 DeepTutor-main 展示对齐优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000010 |
| 工单类型 | P0 展示缺陷 + DeepTutor Web 对齐 + 日志分析 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 1 | `/Users/hua/.codex/attachments/9358e28f-a930-4244-a108-ed0e98dfdcb9/pasted-text.txt` |
| 日志附件 2 | `/Users/hua/.codex/attachments/4b49a3f5-a140-4a41-8e93-58f0a01ca1ca/pasted-text.txt` |
| 对比截图 | `/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-d3433d14-2536-409b-86b8-10a1f4cb1fd2.png` |
| iOS 问题截图 | `/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-2731995d-e7af-469a-899d-49b9c0dfe067.png` |
| 创建日期 | 2026-08-05 |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000008`、`DEEPTUTORCHAT-000009` |

## 1. 本工单目标

本工单继续优化 DeepTutorChat 与 `DeepTutor-main` 的消息会话展示对齐，重点解决：

```text
1. iOS 回答卡片与 Web 不一致。
2. ask_user 提问卡片数据解析错误，卡片正文出现 `{` 或 JSON 残片。
3. AI 工具使用前的规划/推理过程被当成正式正文展示。
4. 工具思考、工具调用、AskUser 卡片、正式回答四类内容没有按 Web 的分层渲染。
5. 日志中出现“生成内容为空”、`askUserBlockCount=0`、`roundtrip_failed` 等异常，需要继续补充定位方案。
```

本工单只创建需求与技术方案，不直接改动 Swift 代码。

## 2. 当前现象

### 2.1 Web 正确效果

用户问题：

```text
今天的天气怎么样？先问...
```

Web 展示效果：

```text
1. 顶部显示助手活动区：调用工具中... · 1m38s。
2. 活动区里展示思考内容：
   我将询问用户所在城市。为了符合工具的使用规则，我将设计相关问询内容...
3. 活动区里展示工具动作：向你提问。
4. 下方展示 AskUser 卡片：
   标题：请作答以继续。
   说明：选择一个选项或输入自定义回复以继续。
   问题：请问你现在在哪个城市？我来帮你查一下今天的天气。
   选项：北京、上海、广州、深圳、其他。
   底部：未回答的问题将作为「已跳过」提交。
   按钮：Submit。
```

关键点：

```text
思考/工具规划属于 trace。
真正的问题和选项属于 AskUser 卡片。
正式回答正文不展示工具规划文本。
```

### 2.2 iOS 当前错误效果

iOS 截图表现：

```text
1. 正文区域直接展示大段工具规划：
   “入其他城市名称。接下来，获取城市后，需要调用 querylocation 来获取经纬度...”
2. 工具名和参数说明被拼进正文：
   “askuserquestion 的 parameters 中的 required 是[]...”
3. trace 区域出现两个灰色“向你提问”，但没有正确的工具层级和状态。
4. AskUser 卡片出现，但问题正文显示为 `{`。
5. 卡片只有一个自由输入框，没有正确展示“请问你现在在哪个城市？”以及北京/上海/广州/深圳快捷选项。
6. 底部输入区被置灰，页面停在错误/等待状态，用户无法获得 Web 一样清晰的继续路径。
```

这说明 iOS 不是简单“卡片样式没对齐”，而是数据分层已经偏了。

## 3. 日志结论摘要

### 3.1 Debug 快照显示当前会话进入错误态

日志：

```text
deeptutor.debug.snapshot conversation=62B4A897 phase=error(⚠️ 生成内容为空，请重新尝试！) isStreaming=false messageCount=6 blockKinds=envelope=6,error=1,text=5,trace=2 askUserBlockCount=0 eventTypes=contentDelta=2,error=1,reasoningDelta=1,result=2 activePresentationSnapshot=none allowedTools=ask_user_question schemaNames=ask_user_question decodeFailureCount=-1
```

说明：

```text
1. 当前页面最终是 error phase。
2. askUserBlockCount=0，说明最终消息流没有稳定生成可渲染 AskUser block。
3. activePresentationSnapshot=none，说明统一 sheet 当前也没有待展示提问。
4. allowedTools/schemaNames 只有 ask_user_question，模型被允许问用户，但 UI 最终没有形成正确 ask_user 卡片。
```

### 3.2 日志显示推理内容被完整保存在 trace 中

日志 JSON 中可见：

```text
reasoningTextLength=384
eventTypes=reasoningDelta
trace row result_detail=我现在需要处理用户的问题“你好”...
```

这说明 iOS 已经能拿到 reasoning，但当前产品问题是：

```text
1. reasoning 的展示策略不稳定。
2. 工具规划文本有时被放进正文。
3. DeepTutor Web 会把这些内容放在 AssistantActivity / TracePanels 中，而不是 AssistantResponse 正文里。
```

### 3.3 真实天气追问场景出现空文本失败

日志：

```text
DeepTutor AI 推理开始，conversation=62B4A897, capability=chat, userContent=今天的天气怎么样？先问问我在那个城市
deeptutor.tool_policy.resolved ... policyReason=ask_user_explicit+weather_location ... allowedTools=ask_user_question,query_weather
deeptutor.tool_schema.outbound ... schemaNames=ask_user_question,query_weather
AI 流式网关请求完成 ...
AI输出 ... finish=stop textLen=0 preview=
AI 返回空文本，转为可见错误气泡
DeepTutor AI 流式失败 ... error=⚠️ 生成内容为空，请重新尝试！
```

说明：

```text
1. 工具策略层已经识别了 ask_user_explicit+weather_location。
2. 工具 schema 已出站。
3. 模型最终 finish=stop 且 textLen=0。
4. 当前 runtime 把空文本直接转成错误气泡。
5. 如果供应商实际产出了 reasoning 或 tool call，但 accumulator 没拿到，应继续排查流式候选结果收集。
```

### 3.4 日志中出现 Result accumulator timeout

日志：

```text
Result accumulator timeout: 3.000000, exceeded.
containerToPush is nil, will not push anything to candidate receiver for request token: 36F0A8B9
```

风险：

```text
1. 供应商 SDK / runtime 的 candidate accumulator 可能没有拿到最终 container。
2. iOS 上层只看到空 text，没有拿到 tool_call 或 structured result。
3. 这会直接造成 askUserBlockCount=0 和 error bubble。
```

该问题需要作为 AI Runtime 层 P0 排查项，不应只在 UI 层兜底。

### 3.5 roundtrip_failed 仍在新消息中出现

日志：

```text
deeptutor.message.persist.roundtrip_failed conversation=62B4A897 message=AD57DB58 failedKinds=deepTutorEnvelope
```

说明：

```text
1. `DEEPTUTORCHAT-000009` 的 block 编解码问题仍影响当前新消息。
2. 新生成消息的 envelope 自检失败，会继续影响回放与卡片恢复。
3. 回答卡片和 AskUser 卡片不稳定，不能只按渲染组件排查。
```

## 4. DeepTutor-main 对齐基线

### 4.1 Web 的助手消息分层

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

Web 链路：

```text
AssistantMessage
  -> AssistantActivity(events, isStreaming, content)
  -> extractAskUserPayload(msg.events)
  -> extractMessageSegments(msg.events)
  -> capability 分支渲染
  -> AssistantResponse(content)
  -> AskUserOptions(data)
```

关键行为：

```text
1. AssistantActivity 始终在助手消息顶部。
2. trace / thinking / tool narration 不直接进入最终 answer body。
3. 默认 chat 分支通过 `extractMessageSegments` 把 text 与 ask_user 按事件顺序交错渲染。
4. ask_user fallback 只用于非默认分支或未走 inline segments 的场景。
```

### 4.2 Web 会过滤工具调用轮次的 narration

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx
```

关键逻辑：

```text
extractMessageSegments(events)
  -> collectNarrationCallIds(events)
  -> shouldAppendEventContent(event)
  -> 如果 content 属于 narrationCallIds，则跳过正文拼接
```

对齐含义：

```text
“我将询问用户所在城市...”这类工具规划文本应保留在 trace，而不是进入 AssistantResponse 正文。
```

### 4.3 Web AskUser 数据归一化

Web 支持两种结构：

```text
v2/v3:
{ intro?, questions: [...] }

legacy:
{ question, options, selection_mode, allows_other }
```

并统一归一化成：

```text
payload.questions[].prompt
payload.questions[].options[].label
payload.questions[].options[].description
payload.questions[].allow_free_text
```

iOS 需要对齐：

```text
1. 不能把原始 JSON 字符串或 `{` 当成 prompt。
2. options 为字符串数组时，要转成 option.label。
3. options 为对象数组时，要保留 label + description。
4. legacy 单问题结构必须能转成 questions[0]。
```

## 5. 当前 iOS 偏差清单

| 类型 | Web 目标 | iOS 当前问题 | 影响 |
| --- | --- | --- | --- |
| 正文分层 | 正文只显示最终回答 | 工具规划进入正文 | 用户看到内部过程，回答卡片显脏 |
| trace 展示 | 工具思考显示在 AssistantActivity | trace 和正文边界不清 | 思考流程不符合 DeepTutor-main |
| AskUser 数据 | prompt/options 结构化展示 | prompt 显示 `{` | 卡片不可用 |
| AskUser 选项 | 北京/上海/广州/深圳/其他 | 只出现输入框 | 没有 Web 快捷选项体验 |
| 工具状态 | 一个“向你提问”行对应一个 tool call | 出现重复灰色“向你提问” | 用户不知道当前状态 |
| 错误处理 | ask_user 等待输入不应转空内容错误 | textLen=0 被转错误 | 等待输入场景被误判失败 |
| 持久化 | blocks/events 重载后稳定 | roundtrip_failed | 卡片回放不稳定 |
| UI 对齐 | 卡片宽度、圆角、阴影、间距一致 | iOS 卡片更像普通表单 | 视觉不一致 |

## 6. 当前 iOS 关键代码位置

| 职责 | 文件 |
| --- | --- |
| 助手消息 block 分发 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift` |
| AskUser 卡片 UI | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorAskUserCardView.swift` |
| trace 面板 UI | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift` |
| Markdown 正文渲染 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Markdown/DeepTutorMarkdownRenderer.swift` |
| DeepTutor palette | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorPalette.swift` |
| 事件到 block reducer | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| trace 内容分流 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorTraceFormatter.swift` |
| ask_user 归一化 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAskUserNormalizer.swift` |
| AI runtime 事件映射 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeEventMapper.swift` |
| AI runtime adapter | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift` |
| 本地消息仓储 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` |

## 7. P0 优化方案

### 7.1 正文与工具规划必须分流

要求：

```text
1. 工具调用轮次中的规划文本只进入 trace。
2. 正式 answer body 只展示最终回答。
3. 如果一个 assistant turn 以 ask_user 暂停，且没有最终回答，则正文可以为空，但不能显示“生成内容为空”错误。
4. 如果供应商把 reasoning 写进 content，需要在 mapper/reducer 层识别并迁移到 trace。
```

针对截图里的文本：

```text
“我将询问用户所在城市...”
“接下来，获取城市后，需要调用 querylocation...”
“确认是否符合所有格式要求...”
```

这些都属于：

```text
trace / reasoning / narration
```

不应属于：

```text
AssistantResponse 正文
```

### 7.2 ask_user payload 归一化必须对齐 Web

要求：

```text
1. 支持 `{ question, options, selection_mode, allows_other }`。
2. 支持 `{ questions: [...] }`。
3. 支持 options 为字符串数组。
4. 支持 options 为 `{ label, description }` 对象数组。
5. 支持 `allows_other` / `allow_free_text` 字段互转。
6. question/prompt 为空或等于 `{` 时必须判为协议错误，不能渲染坏卡片。
```

天气场景期望 payload：

```json
{
  "questions": [
    {
      "id": "q1",
      "prompt": "请问你现在在哪个城市？我来帮你查一下今天的天气。",
      "options": [
        { "label": "北京", "description": "查询北京今天的天气" },
        { "label": "上海", "description": "查询上海今天的天气" },
        { "label": "广州", "description": "查询广州今天的天气" },
        { "label": "深圳", "description": "查询深圳今天的天气" }
      ],
      "multi_select": false,
      "allow_free_text": true
    }
  ]
}
```

### 7.3 awaiting_user_input 不应被当成空回答失败

当前错误路径：

```text
finish=stop textLen=0
AI 返回空文本
转为可见错误气泡
```

优化要求：

```text
1. 如果本轮存在 ask_user tool call 或 activePresentation/question payload，textLen=0 是合法状态。
2. 如果 finishReason=awaiting_user_input，必须进入 waiting/ready-with-askUser 状态。
3. 如果 finish=stop 且 textLen=0，但 reasoning/tool delta 存在，需要先检查是否有未落地 tool_call。
4. 只有完全没有 text、reasoning、tool_call、ask_user payload 时，才显示“生成内容为空”。
```

### 7.4 工具状态去重

截图里 iOS 出现两个灰色“向你提问”。要求：

```text
1. 同一个 toolCallID 只能有一个 trace row。
2. ask_user block 与 trace row 共享 toolCallID。
3. tool started、tool result、ask user pending 只能更新同一行状态，不新增重复行。
4. 如果 toolCallID 缺失，必须以 payload hash 做短期去重，并记录日志。
```

### 7.5 roundtrip_failed 必须并入展示验收

要求：

```text
1. 新消息不应再出现 deepTutorEnvelope roundtrip_failed。
2. 发送后立即重载，卡片仍保持正确 prompt/options。
3. 历史兼容恢复产生 repair_needed 时，UI 不能把坏 payload 渲染成 `{`。
```

## 8. P1 UI 视觉对齐方案

### 8.1 AskUser 卡片视觉细节

对齐 Web：

```text
外层卡片：
  圆角约 26px，iOS 可映射为 24-26pt。
  白底或 system background。
  1px 浅灰边框。
  轻阴影，阴影不能过重。
  顶部间距约 24px。

头部：
  左侧圆形 ? badge。
  主标题“请作答以继续。”加粗。
  副标题“选择一个选项或输入自定义回复以继续。”浅灰。

问题：
  字号大于副标题，medium/semi-bold。
  与选项区保持 14-18pt 间距。

选项：
  每个选项独立圆角行。
  左侧 A/B/C/D 字母。
  第一行城市名。
  第二行说明文本。
  行高足够，不能像紧凑表单。

其他输入：
  虚线边框。
  文案“其他 — 自定义回复...”。
  展开后显示输入框。

底部：
  顶部细分割线。
  左侧“未回答的问题将作为「已跳过」提交。”
  右侧蓝色 Submit。
```

### 8.2 trace 视觉和自动展开/收起

对齐 Web：

```text
1. 工具运行中：显示“调用工具中...”。
2. 完成后：显示“已完成”。
3. 正式回答开始后：思考区自动收起。
4. ask_user pending 时：trace 保持可展开，但不压过提问卡片。
5. trace 文本使用弱化灰色和斜体/轻量样式，不像正式正文。
```

### 8.3 回答正文卡片

要求：

```text
1. 正文 Markdown 与 trace 保持视觉区隔。
2. 没有正式正文时，不渲染空白正文块。
3. 不把工具 schema、parameters、required 等内部信息展示给用户。
4. 错误气泡只用于真正 terminal error，不用于 ask_user pending。
```

## 9. 日志需求

### 9.1 内容分流日志

新增：

```text
deeptutor.content_router.segmented
```

字段：

```text
conversation
message
contentSegments
traceSegments
askUserSegments
droppedNarrationLength
finalAnswerLength
reason
```

### 9.2 AskUser payload 校验日志

新增：

```text
deeptutor.ask_user.payload_validated
deeptutor.ask_user.payload_invalid
```

字段：

```text
conversation
message
toolCallID
questionCount
optionCounts
allowFreeText
promptPreview
rawLength
reason
```

### 9.3 空内容判定日志

新增：

```text
deeptutor.empty_output.classified
```

字段：

```text
conversation
message
finishReason
textLen
reasoningLen
toolCallCount
askUserPayloadCount
activePresentationSnapshot
decision
```

决策值：

```text
pending_ask_user
final_answer_empty_error
tool_call_missing_from_accumulator
reasoning_only_trace
runtime_error
```

### 9.4 trace 去重日志

新增：

```text
deeptutor.trace.row_deduped
```

字段：

```text
conversation
message
toolCallID
rowKind
reason
```

## 10. 验收用例

### 10.1 天气问题先问城市

输入：

```text
今天的天气怎么样？先问问我在哪个城市
```

期望：

```text
1. 不显示“生成内容为空，请重新尝试！”。
2. 不把“我将询问用户所在城市...”展示为正文。
3. trace 中显示工具规划和“向你提问”。
4. AskUser 卡片显示完整问题。
5. AskUser 卡片显示北京、上海、广州、深圳和其他输入。
6. Submit 后继续同一 turn 或同一工具调用恢复。
```

### 10.2 模型只返回 reasoning + ask_user

期望：

```text
1. reasoning 进入 trace。
2. ask_user 进入卡片或统一 sheet。
3. 正文为空也不报错。
4. message.status 为 ready/awaitingUserInput 等可等待状态，不是 failed。
```

### 10.3 坏 payload 不渲染坏卡片

如果 prompt 被解析成 `{`：

```text
1. 不展示 `{` 卡片。
2. 展示 trace 错误或 fallback 提问。
3. 日志记录 payload_invalid reason=prompt_invalid。
4. 不影响后续消息列表加载。
```

### 10.4 Web 视觉对齐截图验收

对比截图要求：

```text
1. 卡片层级、圆角、阴影、边框接近 Web。
2. 选项行高度、字母 badge、描述文本层级接近 Web。
3. trace 与卡片的上下距离接近 Web。
4. 正文不会挤压 trace 和卡片。
5. 底部输入区在 awaiting_user_input 时状态清晰，不误导用户继续普通输入。
```

## 11. 实施拆分

### P0：修复内容分流和空回答误判

```text
1. 增加 DeepTutor 内容分流层，对 reasoning/narration/final answer 做明确归类。
2. ask_user pending 时允许 final answer 为空。
3. 避免工具规划文本进入 text block。
```

### P0：修复 AskUser payload normalizer

```text
1. 对齐 Web `normaliseAskUserPayload`。
2. 支持 legacy 单问题和 questions 数组。
3. 修复 prompt 解析成 `{` 的路径。
4. 对 options 字符串/对象数组统一建模。
```

### P0：修复 trace row 去重

```text
1. 同一 toolCallID 的“向你提问”只能出现一次。
2. tool start/result/ask pending 更新同一 trace row。
3. 缺失 toolCallID 时记录降级去重日志。
```

### P1：视觉对齐 DeepTutor-main

```text
1. 微调 DeepTutorAskUserCardView。
2. 微调 DeepTutorTracePanelView。
3. 微调 DeepTutorAssistantBubble block spacing。
4. 对照 Web 截图完成 iPhone 13 Pro Max 尺寸验收。
```

### P1：继续收敛日志

```text
1. 增加 content_router / empty_output / payload_validated 日志。
2. 保留未脱敏完整 payload，方便本地排查。
3. debug snapshot 中增加 finalAnswerLength、narrationLength、pendingAskUserCount。
```

## 12. 风险与注意事项

### 12.1 不要只调卡片 UI

截图里卡片显示 `{`，说明数据源已经错了。只改圆角、字体、阴影无法解决。

### 12.2 不要把 reasoning 当正文兜底

“生成内容为空”时不能把 reasoning 直接塞进正文。reasoning 应进入 trace，正文为空时要结合 ask_user/tool_call 判断状态。

### 12.3 不要让 prompt 诱导模型输出内部规划

系统 prompt 中“Explain clearly, cite reasoning steps”可能会让模型把内部工具规划写成用户可见内容。需要改成：

```text
对用户解释解题步骤可以出现在最终回答；
工具调用决策、参数构造、schema 校验不得出现在最终回答。
```

### 12.4 不要把 query_weather 暴露给还没有位置的模型路径

如果当前没有 `query_location` 或 `get_current_location`，天气策略应先只允许：

```text
ask_user_question
```

待拿到城市后再进入下一轮：

```text
query_location
query_weather
```

否则模型会一边解释 query_weather 需要经纬度，一边尝试构造工具参数，增加正文污染风险。

## 13. 最终验收标准

实现完成后必须满足：

```text
1. iOS 不再把工具规划/参数校验文本展示为正式回答。
2. iOS AskUser 卡片不再显示 `{` 或 JSON 残片。
3. 天气追问场景展示完整问题与北京/上海/广州/深圳/其他输入。
4. reasoning 和工具调用过程在 trace 中展示，正式回答开始后自动收起。
5. ask_user pending 不再触发“生成内容为空”错误。
6. 同一工具调用不重复展示多个“向你提问”行。
7. 新消息不再出现 deepTutorEnvelope roundtrip_failed。
8. 视觉效果与 DeepTutor-main 的 AskUser 卡片、trace、正文分层基本一致。
9. 新增日志能解释每次内容为什么进入 trace、正文、askUser 或错误。
10. 所有日志按当前排查要求保留完整原文与完整 tool payload，不脱敏。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
