# DEEPTUTORCHAT-000048 DeepTutorChat 独立上传/拍摄卡片工具工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000048 |
| 标题 | DeepTutorChat 独立新增上传/拍摄卡片工具 |
| 业务模块 | DeepTutorChat / 独立工具架构 / 消息卡片 / 附件输入 |
| 优先级 | P1 |
| 状态 | 待实现 |
| 关联工单 | DEEPTUTORCHAT-000043、DEEPTUTORCHAT-000046、DEEPTUTORCHAT-000047 |
| 参考模块 | `SparkClient/Projects/Features/Chat` 的 `show_custom_message_card` 与 `ChatCaptureTypeMessageCard` |
| 核心原则 | DeepTutorChat 工具链独立实现，不复用 `Projects/Core/AIRuntime/ToolHub` 的执行链路 |

## 1. 背景

DeepTutorChat 已建立独立工具目录与独立工具调度体系，第一阶段已经覆盖成员选择、问答、记忆等交互。当前还缺少一类“模型主动插入卡片，引导用户补充附件”的工具能力。

Chat 模块已有 `show_custom_message_card` 工具，支持在对话中插入上传/拍摄入口卡片：

| 场景 | `card_type` | Chat 枚举 |
| --- | --- | --- |
| 上传/解读报告 | `report_photo` | `ChatCaptureCardType.reportPhoto` |
| 拍药盒 | `medicine_box_photo` | `ChatCaptureCardType.medicineBoxPhoto` |
| 拍皮肤 | `skin_photo` | `ChatCaptureCardType.skinPhoto` |

Chat 的工具链路为：

```text
AI 调用 show_custom_message_card(card_type)
  -> ToolHubShowCustomMessageCard
  -> sideEffects: [.captureCard(payload)]
  -> MessageRunActor.apply(.toolSideEffect)
  -> ToolSideEffectBlockMapper
  -> ChatMessageBlockKind.captureCard
  -> ChatCaptureTypeMessageCard
  -> 点击按钮后唤起输入区附件流程
```

DeepTutorChat 需要对齐这个用户体验，但必须使用 DeepTutorChat 自己的工具、消息块、暂停/恢复和附件输入体系。

## 2. 目标

1. 在 DeepTutorChat 独立工具架构中新增 `show_custom_message_card` 工具。
2. 支持三个 `card_type`：`report_photo`、`medicine_box_photo`、`skin_photo`。
3. 工具调用后在 DeepTutorChat 消息流中插入对应卡片。
4. 用户点击卡片按钮后，唤起 DeepTutorChat 输入区的相机、相册、文件选择流程。
5. 选择的图片、PDF 或文件必须进入 DeepTutorChat 输入区域的附件预览区，由用户确认后发送。
6. 卡片消息必须可持久化、可重载、可去重，不能出现刷新后丢失、重复插入或解码失败。

## 3. 非目标

1. 不复用 `Projects/Core/AIRuntime/ToolHub` 的 `ToolHubShowCustomMessageCard`。
2. 不复用 Chat 的 `ToolSideEffectBlockMapper`、`ChatMessageBlockKind.captureCard` 或 Chat 消息 reducer。
3. 不在本工单实现附件自动发送。V1 只负责把附件放入输入区预览，由用户主动点击发送。
4. 不新增服务端接口。该工具只生成本地消息卡片并触发客户端附件选择。
5. 不改变 Chat 模块既有 `show_custom_message_card` 行为。

## 4. 工具定义

### 4.1 工具名称

DeepTutorChat 侧工具名保持与 Chat / DeepTutor-main 提示词兼容：

```swift
show_custom_message_card
```

建议在 DeepTutorChat 独立枚举中新增：

```swift
case showCustomMessageCard = "show_custom_message_card"
```

涉及文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Domain/Tools/DeepTutorToolName.swift
SparkClient/Projects/Features/DeepTutorChat/Application/Tools/Builtins/DeepTutorShowCustomMessageCardTool.swift
SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolRegistryFactory.swift
SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolSchemaBuilder.swift
SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolPromptManifestBuilder.swift
```

### 4.2 参数 Schema

```json
{
  "name": "show_custom_message_card",
  "description": "在 DeepTutorChat 对话中展示上传或拍摄入口卡片，用于引导用户补充报告、药盒或皮肤照片等附件。",
  "parameters": {
    "type": "object",
    "properties": {
      "card_type": {
        "type": "string",
        "enum": [
          "report_photo",
          "medicine_box_photo",
          "skin_photo"
        ],
        "description": "需要展示的卡片类型。report_photo 用于上传/解读体检报告、化验单、PDF；medicine_box_photo 用于拍摄药盒；skin_photo 用于拍摄皮肤问题。"
      }
    },
    "required": ["card_type"],
    "additionalProperties": false
  }
}
```

### 4.3 模型调用示例

```json
{
  "name": "show_custom_message_card",
  "arguments": {
    "card_type": "report_photo"
  }
}
```

## 5. 独立数据模型

### 5.1 卡片类型

新增文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Domain/Tools/DeepTutorCaptureCardType.swift
```

建议定义：

```swift
enum DeepTutorCaptureCardType: String, Codable, CaseIterable, Sendable {
    case reportPhoto = "report_photo"
    case medicineBoxPhoto = "medicine_box_photo"
    case skinPhoto = "skin_photo"
}
```

### 5.2 卡片消息 Payload

新增文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Domain/Tools/DeepTutorCaptureCardPayload.swift
```

建议字段：

```swift
struct DeepTutorCaptureCardPayload: Codable, Equatable, Sendable {
    let cardType: DeepTutorCaptureCardType
    let title: String
    let subtitle: String
    let createdAt: Date
    let sourceToolCallID: String?
}
```

说明：

| 字段 | 说明 |
| --- | --- |
| `cardType` | 卡片业务类型 |
| `title` | 落库时固化标题，避免以后文案变更影响历史消息 |
| `subtitle` | 落库时固化副标题 |
| `createdAt` | 卡片生成时间 |
| `sourceToolCallID` | 用于去重和审计 |

## 6. 消息块设计

DeepTutorChat 需要新增自己的消息块类型，不使用 Chat 的 `captureCard` block。

建议新增：

```swift
case captureCard
```

Payload 使用 `DeepTutorCaptureCardPayload`。

插入后的消息块语义：

```text
assistant message
  block: text / thinking / status
  block: deepTutorCaptureCard(payload)
```

要求：

1. `Codable` 往返必须稳定，不能触发 `block_decode_failed`。
2. block kind 命名必须与 DeepTutorChat 既有 block 体系一致。
3. reducer 插入卡片时必须使用稳定 block id。
4. 同一个 `messageClientID + toolCallID + cardType` 重复到达时只保留一张卡片。

## 7. 工具执行流程

### 7.1 DeepTutor 独立链路

```text
AI tool_call: show_custom_message_card(card_type)
  -> DeepTutorToolDispatcher
  -> DeepTutorShowCustomMessageCardTool
  -> DeepTutorToolResult.captureCard(payload)
  -> DeepTutorAgenticRuntime / DeepTutorAgentLoop
  -> DeepTutorMessageReducer 插入 DeepTutor capture card block
  -> DeepTutorMessageRow 渲染 DeepTutorCaptureCardView
  -> 用户点击拍照/上传/选择文件
  -> DeepTutorChatPage 打开相机/相册/fileImporter
  -> 选中的附件进入 DeepTutorComposer 附件预览区
  -> 用户点击发送
```

### 7.2 工具结果

建议扩展 DeepTutor 工具结果，让工具可以表达“插入卡片 + 当前轮次等待用户补附件”：

```swift
struct DeepTutorToolResult {
    let toolName: String
    let outputText: String
    let sensitive: Bool
    let cardPayload: DeepTutorCaptureCardPayload?
    let pauseForUser: DeepTutorToolPauseRequest?
}
```

如果现有 `DeepTutorToolResult` 已有 metadata / sideEffect 类型，应优先沿用现有结构，但语义必须明确为 DeepTutor 内部 side effect，不与 Chat ToolHub 混用。

### 7.3 暂停语义

建议在 `DeepTutorToolPauseRequest` 中新增：

```swift
case attachmentCapture(cardType: DeepTutorCaptureCardType)
```

V1 行为：

1. 插入卡片。
2. 当前 assistant 回合结束，状态变为等待用户补充附件。
3. 用户点击卡片选择附件后，附件进入输入区预览。
4. 用户手动发送附件后开启新一轮推理。

这样可以避免模型在用户尚未上传材料前继续输出无效结论。

## 8. 卡片 UI 方案

### 8.1 组件位置

新增 DeepTutorChat 自有组件：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorCaptureCardView.swift
```

可参考 Chat 的：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatCaptureMessageCards.swift
```

但 DeepTutorChat 不应直接依赖 Chat Feature 内部 View。推荐先复制并改造成 DeepTutor 专属组件；后续如果多个 Feature 继续复用，再抽到 Shared UI。

### 8.2 三种卡片配置

| 类型 | 标题 | 副标题 | 主色 | 操作 |
| --- | --- | --- | --- | --- |
| `report_photo` | AI智能解读报告 | 上传体检报告、化验单、影像报告或 PDF，DeepTutor 将结合对话继续解读。 | 蓝色 | 拍照、上传照片、选择文件 |
| `medicine_box_photo` | AI智能识别药盒 | 拍摄药盒正面和关键信息，DeepTutor 将辅助识别药品名称与用法信息。 | 紫色 | 拍照、上传照片 |
| `skin_photo` | AI 皮肤拍照辅助 | 上传清晰皮肤照片，DeepTutor 将根据图片信息给出就医和记录建议。 | 绿色 | 拍照、上传照片 |

### 8.3 UI 要求

1. 卡片必须出现在 assistant 消息流内。
2. 卡片标题、说明、按钮应与 DeepTutorChat 视觉风格一致。
3. `report_photo` 显示“选择文件”，支持 PDF、图片、文本等报告材料。
4. `medicine_box_photo` 与 `skin_photo` 不显示“选择文件”按钮。
5. 点击按钮后不直接发送消息，只把附件放入输入区预览区域。
6. 附件进入预览区后应自动滚动或聚焦到输入区域附近，让用户明确已经选择成功。
7. 卡片在历史消息中只负责再次触发附件选择，不展示“已上传”态；已上传附件归属于用户后续消息。

## 9. 附件选择与输入区对接

DeepTutorChat 需要建立卡片按钮到输入区附件队列的显式路由。

建议新增或扩展：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorCaptureCardActionRouter.swift
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorComposerAttachmentEnqueuer.swift
```

### 9.1 事件接口

卡片 View 不直接打开系统选择器，只发出意图：

```swift
onOpenCamera(cardType)
onOpenPhotoLibrary(cardType)
onOpenFiles(cardType)
```

页面层接收后：

| 操作 | 页面行为 |
| --- | --- |
| 拍照 | 设置 DeepTutorChat 相机展示状态 |
| 上传照片 | 设置 DeepTutorChat PhotoPicker 展示状态 |
| 选择文件 | 设置 DeepTutorChat fileImporter 展示状态 |

### 9.2 附件入队

选择完成后统一进入 DeepTutorChat composer draft：

```text
DeepTutor selected files/photos
  -> DeepTutorAttachmentDraft
  -> DeepTutorComposerAttachmentPreviewBandView
  -> DeepTutor 输入区预览
```

要求：

1. 附件来源需要记录 `sourceCardType`，便于发送时提示词增强。
2. 报告类附件建议标记为 `purpose=report_interpretation`。
3. 药盒类附件建议标记为 `purpose=medicine_identification`。
4. 皮肤类附件建议标记为 `purpose=skin_photo_assist`。
5. 多附件选择应保留原有顺序。
6. 附件入队失败时需要展示 toast 或轻量错误提示，不能静默失败。

## 10. Prompt Manifest 约束

`show_custom_message_card` 需要写入 DeepTutor 独立工具提示词，指导模型在合适时机调用。

建议提示：

```text
当用户需要上传体检报告、化验单、影像报告或 PDF 才能继续解读时，调用 show_custom_message_card，card_type=report_photo。
当用户需要提供药盒、药品外包装、说明书照片以辅助识别药品时，调用 show_custom_message_card，card_type=medicine_box_photo。
当用户需要提供皮肤局部照片以辅助记录症状或判断是否需要就医时，调用 show_custom_message_card，card_type=skin_photo。
调用后应等待用户上传附件，不要在没有材料时编造报告、药品或皮肤结论。
```

## 11. 与 Chat 模块的边界

| 能力 | Chat 现有实现 | DeepTutorChat 本工单实现 |
| --- | --- | --- |
| 工具名 | `show_custom_message_card` | 同名，独立注册 |
| 执行器 | `ToolHubShowCustomMessageCard` | `DeepTutorShowCustomMessageCardTool` |
| 工具注册 | `ToolHub+Schema` | `DeepTutorToolRegistryFactory` / `DeepTutorToolSchemaBuilder` |
| side effect | `ToolExecutionResult.sideEffects` | DeepTutor 内部 card result / pause request |
| 消息块 | `ChatMessageBlockKind.captureCard` | DeepTutor 自有 capture card block |
| UI | `ChatCaptureTypeMessageCard` | `DeepTutorCaptureCardView` |
| 附件入口 | Chat composer state store | DeepTutorChat composer draft / attachment preview |

## 12. 异常处理

| 场景 | 处理 |
| --- | --- |
| `card_type` 缺失 | 工具返回错误文本，不插入卡片 |
| `card_type` 非枚举值 | 工具返回错误文本，不插入卡片，并记录审计日志 |
| 当前无 assistant message id | 工具返回文本结果，不插入卡片，避免孤儿 block |
| 重复 tool call | 使用 `toolCallID + cardType` 去重 |
| 图片选择取消 | 不插入附件，不提示错误 |
| 文件读取失败 | 展示错误提示，并保留卡片可再次点击 |
| 消息重载 payload 解码失败 | 不能导致整条消息丢失；应降级为文本错误块并记录日志 |

## 13. 日志与审计

建议新增日志点：

```text
deeptutor.capture_card.tool_called conversation=... message=... cardType=...
deeptutor.capture_card.block_inserted conversation=... message=... block=... cardType=...
deeptutor.capture_card.duplicate_skipped conversation=... message=... toolCallID=...
deeptutor.capture_card.action_tapped conversation=... cardType=... action=camera|photo|file
deeptutor.capture_card.attachment_enqueued conversation=... cardType=... count=...
deeptutor.capture_card.decode_failed conversation=... message=... block=... error=...
```

日志中不得输出本地文件完整路径、图片内容、报告 OCR 内容或任何隐私医疗文本。

## 14. 实施步骤

### 阶段一：领域模型与工具注册

1. 新增 `DeepTutorCaptureCardType`。
2. 新增 `DeepTutorCaptureCardPayload`。
3. 在 `DeepTutorToolName` 注册 `show_custom_message_card`。
4. 在 `DeepTutorToolSchemaBuilder` 增加 schema。
5. 在 `DeepTutorToolPromptManifestBuilder` 增加工具使用提示。
6. 在 `DeepTutorToolRegistryFactory` 注册 `DeepTutorShowCustomMessageCardTool`。

### 阶段二：工具执行与 Agent Loop

1. 实现 `DeepTutorShowCustomMessageCardTool`。
2. 解析并校验 `card_type`。
3. 生成 `DeepTutorCaptureCardPayload`。
4. 将工具结果转换为 DeepTutor 消息卡片 block。
5. 增加等待用户附件的暂停语义。
6. 保证同一个工具调用不会重复插入卡片。

### 阶段三：消息持久化与渲染

1. 扩展 DeepTutorChat 消息 block kind。
2. 扩展 block codec。
3. 扩展 message reducer。
4. 新增 `DeepTutorCaptureCardView`。
5. 在 DeepTutor 消息 Row 中接入卡片渲染。
6. 增加历史消息重载验证。

### 阶段四：附件选择联动

1. 将卡片按钮事件传递到页面层。
2. 接入 DeepTutorChat 相机入口。
3. 接入 DeepTutorChat 相册入口。
4. 接入 DeepTutorChat fileImporter，仅 `report_photo` 可见。
5. 将选择结果写入 composer attachment draft。
6. 输入区预览展示选中的附件。

### 阶段五：体验与回归

1. 验证三种卡片均可由工具插入。
2. 验证点击按钮后附件进入输入区预览。
3. 验证取消选择不会破坏当前对话。
4. 验证发送附件后模型能基于附件继续回答。
5. 验证退出重进后卡片仍可渲染。
6. 验证 Chat 模块行为无变化。

## 15. 验收标准

### 15.1 工具验收

1. DeepTutorChat 工具列表中存在 `show_custom_message_card`。
2. 模型调用 `show_custom_message_card(report_photo)` 后，消息内出现“AI智能解读报告”卡片。
3. 模型调用 `show_custom_message_card(medicine_box_photo)` 后，消息内出现“AI智能识别药盒”卡片。
4. 模型调用 `show_custom_message_card(skin_photo)` 后，消息内出现“AI 皮肤拍照辅助”卡片。
5. 非法 `card_type` 不插入卡片，并有可追踪日志。

### 15.2 UI 验收

1. 报告卡片展示“拍照 / 上传照片 / 选择文件”三个操作。
2. 药盒卡片展示“拍照 / 上传照片”两个操作。
3. 皮肤卡片展示“拍照 / 上传照片”两个操作。
4. 卡片视觉风格与 DeepTutorChat 消息流一致。
5. 卡片在滚动列表复用、刷新、重进页面后不变形、不重复。

### 15.3 附件验收

1. 点击“拍照”后，拍摄结果进入 DeepTutorChat 输入区预览。
2. 点击“上传照片”后，相册选择结果进入 DeepTutorChat 输入区预览。
3. 点击报告卡片“选择文件”后，PDF / 图片 / 文本文件进入输入区预览。
4. 选择附件后不自动发送。
5. 用户点击发送后，附件随用户消息一起进入 DeepTutorChat 对话。

### 15.4 稳定性验收

1. 不出现 `block_decode_failed`。
2. 不出现 `duplicate_identity` 导致卡片丢失。
3. 不出现输入区因为卡片刷新而无法输入。
4. 不影响成员选择、问答、记忆、`query_member_profile` 等已有工具。
5. 不修改或破坏 Chat 模块 ToolHub 的现有行为。

## 16. 测试建议

### 16.1 单元测试

1. `DeepTutorCaptureCardType` raw value 解码测试。
2. `show_custom_message_card` schema 生成测试。
3. `DeepTutorShowCustomMessageCardTool` 合法参数测试。
4. `DeepTutorShowCustomMessageCardTool` 非法参数测试。
5. capture card payload codec roundtrip 测试。
6. 重复 `toolCallID` 去重测试。

### 16.2 集成测试

1. 模拟模型调用 `show_custom_message_card(report_photo)`，验证消息 block 插入。
2. 模拟页面重载，验证卡片可解码并渲染。
3. 模拟点击报告卡片文件按钮，验证附件进入 composer draft。
4. 模拟点击药盒/皮肤卡片，验证只出现相机和相册入口。

### 16.3 手工回归

1. 让 DeepTutorChat 回复“请上传体检报告”，验证报告卡片出现。
2. 选择 PDF 后，确认 PDF 缩略或文件 chip 出现在输入区。
3. 发送 PDF 后，确认用户消息展示附件。
4. 返回会话列表再进入，确认卡片和附件消息均正常。
5. 切换到底部其他 Tab 再回来，确认输入区未异常刷新。

## 17. 风险点

1. DeepTutorChat 当前消息 block codec 若仍存在 envelope 修复逻辑，新增 block 必须纳入统一 codec，避免历史消息加载丢块。
2. 如果卡片工具结果继续进入模型 answer loop，模型可能在用户未上传附件时继续回答，需要通过 pause request 明确终止本轮。
3. 如果直接引用 Chat Feature 的 `ChatCaptureTypeMessageCard`，会造成 Feature 间反向依赖，后续维护困难。
4. 附件选择状态如果绑定在消息 Row 内，列表刷新可能导致 picker 状态丢失；必须上提到页面或 ViewModel。
5. 文件选择进入输入区时，需要沿用 DeepTutorChat 现有附件压缩、大小限制和预览逻辑。

## 18. 推荐落地顺序

优先实现最小闭环：

```text
DeepTutorShowCustomMessageCardTool
  -> 插入 report_photo 卡片
  -> 点击“选择文件”
  -> 文件进入输入区预览
  -> 用户发送
```

确认报告卡片闭环稳定后，再补齐 `medicine_box_photo` 和 `skin_photo` 的相机/相册入口。

## 19. 完成定义

本工单完成时，DeepTutorChat 可以在模型需要用户补充材料时，独立调用 `show_custom_message_card` 插入上传/拍摄卡片。用户点击卡片后可以选择附件，附件会直接进入 DeepTutorChat 输入区域预览，并在用户发送后参与下一轮对话。整个流程不依赖 Chat 的 ToolHub，不破坏 Chat 现有工具和卡片逻辑。
