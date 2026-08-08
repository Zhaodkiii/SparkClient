# DEEPTUTORCHAT-000045 DeepTutorChat 会话绑定成员与输入框成员选择组件工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000045 |
| 工单类型 | P0 对话流程 / 会话上下文 / 成员绑定 / 工具能力 |
| 当前范围 | 创建需求工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 参考模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 创建日期 | 2026-08-08 |
| 核心目标 | DeepTutorChat 对话流程支持“会话绑定成员”；输入框内提供成员选择组件；会话持久化选择成员；工具支持检查、切换当前会话成员 |

## 1. 背景与问题

DeepTutorChat 已经有一部分“工具触发成员选择”的能力：

```text
DeepTutorMessageBlock.memberSelection
DeepTutorMemberSelectionCardView
DeepTutorMemberSelectionResumeBuilder
SendDeepTutorAIMessageUseCase.submitMemberSelection(...)
DeepTutorLocalChatRepository.updateConversationMemberBinding(...)
DeepTutorConversation.memberID
```

也就是说，当前链路里，AI 工具 `request_member_selection` 触发后，用户在消息卡片中选择成员，系统可以把结果写入 `conversation.memberID`。

但这还不等于完整的“会话绑定成员”体验。当前缺口是：

```text
1. 输入框内没有 DeepTutorChat 专属成员选择组件。
2. 用户不能在发送前主动绑定 / 切换 / 解绑当前会话成员。
3. 会话绑定成员、全局默认成员、工具临时选择成员的语义没有统一。
4. 工具侧缺少“检查当前会话是否已绑定成员”的明确能力。
5. 工具侧缺少“切换当前会话绑定成员”的明确能力。
6. 发送链路和 Prompt 中缺少稳定、可解释的 bound member context。
```

本工单要求补齐 DeepTutorChat 的会话级成员绑定闭环，并参考 Chat 的实现经验，但不要简单复制 Chat 的代码和状态结构。

## 2. Chat 参考实现分析

### 2.1 Chat 值得学习的地方

Chat 的成员绑定链路比较完整：

```text
ChatView
  -> HanlinChatComposerView
  -> HanlinChatInputView
  -> ChatComposerRuntimeTogglesRow
  -> MemberProfileBindingMenu
  -> ChatDetailViewModel.updateThreadMemberBinding
  -> chatRepository.updateThreadMemberBinding
```

关键代码事实：

```text
ChatView.swift
  -> boundMemberID: stateStore.selectedThread?.memberID
  -> onSetMemberBinding: detailViewModel.updateThreadMemberBinding(memberID, for: threadID)

HanlinChatComposerView.swift
  -> 将 boundMemberID、memberContextStore、onSetMemberBinding 继续传给输入框

HanlinChatInputView.swift
  -> ChatComposerRuntimeTogglesRow 挂在输入框底部工具栏
  -> onChange(of: boundMemberID) 后清理不匹配的 health refs

ChatComposerRuntimeTogglesRow.swift
  -> memberProfileToggle 展示成员按钮
  -> MemberProfileBindingMenu 展示成员列表与“无成员”选项

ChatDetailViewModel.swift
  -> updateThreadMemberBinding 持久化 thread.memberID
  -> 更新会话列表
  -> pruneHealthResourceRefs(matchingMemberID:)
```

可以借鉴的优秀点：

1. **会话绑定是 thread/conversation 字段**，不是只存在于 UI draft。
2. **输入框直接展示绑定状态**，用户发送前就能看见当前对话是否绑定成员。
3. **切换成员后立即持久化**，刷新页面不会丢失。
4. **切换成员会清理不匹配上下文资料**，避免把 A 成员资料带入 B 成员对话。
5. **成员选择组件小而轻**，不抢输入框主功能。
6. **绑定成员后相关入口联动**，例如 Chat 中“问报告”入口依赖 `boundMemberID`。

### 2.2 Chat 当前不完美的地方

DeepTutorChat 不能直接复制 Chat，因为 Chat 实现里也有一些容易放大的缺陷。

#### 2.2.1 全局默认成员和会话绑定成员容易混淆

Chat 的成员按钮逻辑里：

```text
boundMemberID == nil ? defaultMemberID : nil
defaultMemberID = memberContextStore.context.selectedMember?.id
```

用户点击按钮时，如果当前会话没有绑定成员，会默认绑定全局 selected member；如果已绑定，则解绑。

问题：

```text
1. 用户可能不知道点击后绑定的是哪个成员。
2. 全局 selectedMemberID 和当前 thread.memberID 的语义容易混淆。
3. 发送日志里仍有 memberContextStore.context.selectedMemberID，可能和 thread.memberID 不一致。
```

DeepTutorChat 应明确区分三类成员状态：

```text
globalSelectedMemberID   全局默认成员
conversation.memberID    当前会话绑定成员
toolSelectedMemberID     工具卡片本次临时选择/恢复成员
```

#### 2.2.2 成员展示逻辑写在通用 Toggle 内

Chat 中成员名显示有本地方法：

```text
lastTwoCharacters(of:)
```

这类展示策略写在 `ChatComposerRuntimeTogglesRow` 内，会让组件职责变重，也不利于 DeepTutorChat 使用更清晰的展示规则。

DeepTutorChat 应抽出：

```text
DeepTutorBoundMemberDisplayModel
DeepTutorBoundMemberFormatter
```

#### 2.2.3 Runtime toggles 过于集中

Chat 的 `ChatComposerRuntimeTogglesRow` 同时承载：

```text
工具开关
联网
思考
成员绑定
推理档位
```

这在 Chat 里可接受，但 DeepTutorChat 的输入框已经有：

```text
capabilityMenu
modelChip
attachmentButton
sendStopButton
```

如果直接塞一个大而全的 RuntimeTogglesRow，会让 DeepTutorChat 输入框失去清晰度。

DeepTutorChat 应建立更小的专属组件：

```text
DeepTutorBoundMemberPickerChip
DeepTutorBoundMemberMenu
DeepTutorComposerContextRow
```

#### 2.2.4 工具选择成员和会话绑定成员没有统一事件语义

Chat 的成员绑定偏 UI 操作；DeepTutorChat 还存在工具卡片成员选择：

```text
request_member_selection -> memberSelection card -> submitMemberSelection
```

如果不定义优先级，会出现：

```text
1. 输入框绑定了 A，工具又要求选择 B。
2. 工具选择 B 后自动改了会话绑定，但用户未预期。
3. 用户手动切回 A 后，pending 工具恢复仍用 B。
```

DeepTutorChat 必须统一规则：

```text
会话绑定成员是本会话的当前有效成员。
工具成员选择如果用户提交，默认写入 conversation.memberID。
用户在输入框手动切换成员，是新的会话绑定事实，后续工具必须读取新值。
pending 工具恢复时必须校验 toolCallID 所在消息和当前会话成员一致性。
```

## 3. 产品目标

### 3.1 用户侧目标

用户在 DeepTutorChat 输入框内应能：

```text
1. 看见当前会话是否绑定成员。
2. 点击成员组件选择一个家庭成员。
3. 随时切换当前会话成员。
4. 解绑当前会话成员，回到通用对话。
5. 发送消息前确认 AI 会基于哪个成员回答。
```

### 3.2 AI / 工具侧目标

DeepTutorChat 工具应能：

```text
1. 检查当前会话是否绑定成员。
2. 获取当前绑定成员的最小上下文。
3. 在需要时请求用户选择成员。
4. 在用户主动切换成员时更新会话绑定。
5. 在成员不一致时停止使用旧成员资料。
```

### 3.3 数据侧目标

会话需要持久化：

```text
conversation.memberID
memberBindingUpdatedAt
memberBindingSource
```

其中：

```text
memberBindingSource = composer_manual | tool_selection | restored | cleared
```

第一阶段如果不改 CoreData schema，可先只使用现有 `memberID` 字段；但工单要求预留 source 与 updatedAt 的迁移设计。

## 4. 非目标

本工单不做：

```text
1. 不重写成员管理模块。
2. 不接入完整医疗档案查询工具。
3. 不改 Chat 的成员绑定 UI。
4. 不把 ChatComposerRuntimeTogglesRow 直接复制到 DeepTutorChat。
5. 不把全局 selectedMemberID 当作会话绑定成员。
6. 不在普通 memory 中写入成员医疗事实。
```

## 5. DeepTutorChat 目标流程

### 5.1 新建对话

```text
用户进入 DeepTutorChat
  -> 如果从某个成员详情页进入，可携带 initialMemberID
  -> 创建 conversation 时写入 memberID
  -> 输入框展示该成员 chip
```

如果没有 initialMemberID：

```text
conversation.memberID = nil
输入框展示“选择成员”
AI 回答默认按通用上下文处理
```

### 5.2 输入框主动绑定成员

```text
用户点击输入框成员 chip
  -> 打开 DeepTutorBoundMemberMenu
  -> 选择成员
  -> viewModel.updateConversationMemberBinding(memberID, source: .composerManual)
  -> repository.updateConversationMemberBinding
  -> viewModel.conversation.memberID 更新
  -> 输入框 chip 更新
  -> 清理与旧成员不一致的上下文引用
```

### 5.3 输入框解绑成员

```text
用户点击“无成员 / 解绑”
  -> memberID = nil
  -> 持久化 conversation.memberID = nil
  -> 输入框 chip 回到“选择成员”
  -> 清理成员绑定依赖上下文
  -> 后续回答不能使用旧成员身份
```

### 5.4 工具请求成员选择

```text
AI 调用 request_member_selection
  -> 如果 conversation.memberID 已存在：
       工具返回当前已绑定成员，不再展示卡片
  -> 如果 conversation.memberID 为空：
       展示 DeepTutorMemberSelectionCardView
       用户选择成员
       submitMemberSelection 写入 conversation.memberID
       同 turn resume
```

### 5.5 工具切换成员

工具切换成员要谨慎，不应让模型静默改成员。

目标规则：

```text
1. 模型不能直接把会话成员从 A 改到 B。
2. 模型只能调用 request_member_selection 请求用户确认切换。
3. 用户选择后才更新 conversation.memberID。
4. 如果用户取消，继续沿用原绑定成员或给出通用回答。
```

未来可新增工具：

```text
get_current_member_binding
request_member_selection
clear_member_binding
```

第一阶段建议先做：

```text
get_current_member_binding
request_member_selection
```

`clear_member_binding` 只允许 UI 主动触发，不建议开放给模型直接调用。

## 6. UI 设计方案

### 6.1 组件位置

DeepTutorChat 当前输入框结构：

```text
DeepTutorComposerView
  -> DeepTutorComposerCardView
       -> DeepTutorComposerAttachmentPreviewBandView
       -> DeepTutorComposerReferenceBandView
       -> DeepTutorComposerTextView
       -> DeepTutorComposerToolbarView
            -> capabilityMenu
            -> modelChip
            -> attachmentButton
            -> sendStopButton
```

新增成员组件建议放在 `DeepTutorComposerToolbarView` 左侧上下文区：

```text
HStack:
  capabilityMenu
  modelChip
  memberChip
  Spacer
  attachmentButton
  sendStopButton
```

原因：

```text
1. 成员绑定是本轮上下文，不是附件，也不是模型。
2. 放在 capability/model 旁边，用户能理解“AI 以什么模式、什么模型、哪个成员”回答。
3. 不占用文本输入区。
```

### 6.2 DeepTutorBoundMemberPickerChip

状态一：未绑定

```text
icon: person.crop.circle.badge.plus
title: 选择成员
tint: secondary
```

状态二：已绑定

```text
icon: person.crop.circle.fill
title: 成员昵称或关系
tint: green
```

状态三：发送中

```text
disabled: true
opacity: 0.55
```

状态四：成员不存在 / 被删除

```text
icon: exclamationmark.circle
title: 成员失效
tint: orange
menu 中提供“重新选择”“解绑”
```

### 6.3 DeepTutorBoundMemberMenu

菜单内容：

```text
当前绑定：
  - 张三（本人）

可选成员：
  - 张三
  - 妈妈
  - 爸爸

操作：
  - 解绑成员
```

要求：

```text
1. 当前绑定成员显示 checkmark。
2. 无成员时“解绑成员”置灰或隐藏。
3. 成员列表为空时展示“暂无成员”，但不要阻塞普通对话。
4. 选择成员后立即持久化。
5. 菜单关闭不改变状态。
```

### 6.4 与工具成员选择卡的关系

输入框 chip 和消息内成员选择卡必须显示同一会话状态：

```text
用户在卡片选择成员
  -> conversation.memberID 更新
  -> 输入框 chip 立即显示该成员

用户在输入框切换成员
  -> 后续工具 get_current_member_binding 返回新成员
  -> 旧 pending memberSelection 卡如果仍存在，应显示“会话成员已变更，请重新提交或取消”
```

## 7. 数据模型设计

### 7.1 现有字段

当前 DeepTutorChat 已有：

```swift
struct DeepTutorConversation {
    var memberID: Int?
}
```

仓储已有：

```swift
func updateConversationMemberBinding(conversationID: UUID, memberID: Int?) async throws
```

CoreData store 已能写入：

```text
object.setValue(memberID.map { Int64($0) }, forKey: "memberID")
```

所以第一阶段不需要新增基础字段即可完成持久化。

### 7.2 建议扩展字段

后续迁移建议增加：

```swift
var memberBindingUpdatedAt: Date?
var memberBindingSource: DeepTutorMemberBindingSource?
```

枚举：

```swift
enum DeepTutorMemberBindingSource: String, Codable, Sendable {
    case composerManual
    case toolSelection
    case restored
    case cleared
}
```

用途：

```text
1. 调试时判断成员是用户主动选的，还是工具流程带来的。
2. 解决“工具选择成员是否应该覆盖用户手动选择”的争议。
3. 未来支持会话迁移、同步、审计。
```

### 7.3 Request Snapshot

每条用户消息发送时，应把当时的成员绑定写入 request snapshot：

```text
requestSnapshot.boundMemberID
requestSnapshot.boundMemberName
requestSnapshot.memberBindingSource
```

这样可以保证：

```text
1. 重试 / 重新生成时复现当时成员上下文。
2. 会话后来切换成员，不污染历史消息。
3. Debug exporter 可解释该轮使用了哪个成员。
```

## 8. ViewModel 与用例设计

### 8.1 DeepTutorChatViewModel 新增能力

新增接口：

```swift
@MainActor
func updateConversationMemberBinding(
    _ memberID: Int?,
    source: DeepTutorMemberBindingSource
) async
```

职责：

```text
1. 如果新旧 memberID 一致，直接返回。
2. 发送中不允许切换，或弹出提示“请等待当前回复完成”。
3. 调用 repository.updateConversationMemberBinding。
4. 更新 viewModel.conversation.memberID。
5. 更新会话列表 item。
6. 清理不匹配的 context references / health refs / member-dependent attachments。
7. 记录日志。
```

### 8.2 DeepTutorMemberBindingUseCase

建议新增用例：

```swift
struct UpdateDeepTutorConversationMemberBindingUseCase: Sendable {
    let repository: DeepTutorLocalChatRepository
    let logger: Logger

    func execute(
        conversationID: UUID,
        currentMemberID: Int?,
        nextMemberID: Int?,
        source: DeepTutorMemberBindingSource
    ) async throws -> DeepTutorConversation
}
```

这样可以避免把绑定逻辑散落在：

```text
DeepTutorChatViewModel
SendDeepTutorAIMessageUseCase.submitMemberSelection
未来 DeepTutor 工具
```

### 8.3 成员数据读取

DeepTutorChat 已有：

```text
DeepTutorMemberToolDataSource
memberContextStore.context.members
viewModel.availableMembers
```

要求：

```text
1. 输入框成员菜单使用同一份 `availableMembers`。
2. 如果成员列表尚未加载，打开菜单前触发加载。
3. 不在 UI 组件内直接调用医疗 API。
4. 成员失效时不崩溃，显示“成员失效”。
```

## 9. 工具设计

### 9.1 `get_current_member_binding`

新增 DeepTutorChat 原生工具：

```text
get_current_member_binding
```

用途：

```text
检查当前 DeepTutorChat 会话是否已经绑定成员。
```

schema：

```json
{
  "name": "get_current_member_binding",
  "description": "Check whether the current DeepTutorChat conversation is bound to a family member.",
  "parameters": {
    "type": "object",
    "properties": {}
  }
}
```

返回：

```json
{
  "bound": true,
  "member_id": 12,
  "member_name": "爸爸",
  "relationship": "father"
}
```

未绑定返回：

```json
{
  "bound": false,
  "instruction": "Call request_member_selection if member-specific context is required."
}
```

### 9.2 `request_member_selection`

现有工具继续保留，但语义升级：

```text
1. 如果当前无绑定成员，展示选择卡。
2. 如果当前已有绑定成员，但模型认为需要切换，必须说明 reason 并让用户选择。
3. 用户选择后，默认更新 conversation.memberID。
4. 工具恢复后必须继续原始请求。
```

### 9.3 不建议开放 `switch_member`

历史工具策略里出现过：

```text
SparkToolName.switchMember
```

DeepTutorChat 不建议第一阶段开放模型直接切换成员的工具。

原因：

```text
1. 成员身份涉及家庭健康隐私。
2. 模型不能代表用户静默切换。
3. 切换成员会影响后续健康资料上下文。
```

正确方式：

```text
模型请求切换 -> request_member_selection -> 用户确认 -> 写入会话绑定
```

## 10. Prompt 规则

DeepTutorChat system prompt / tool manifest 应加入：

```text
当前会话可能绑定了家庭成员。
如果 request snapshot 中有 boundMemberID，请默认基于该成员回答。
如果用户明确要求切换到其他成员，不要自行假设，调用 request_member_selection 让用户确认。
如果当前没有绑定成员，但问题需要个人/家庭健康上下文，先调用 get_current_member_binding；未绑定时再调用 request_member_selection。
如果问题可以通用回答，不要强制要求选择成员。
```

发送时注入上下文：

```text
Current bound member:
- member_id: 12
- display_name: 爸爸
- relationship: father
```

未绑定时：

```text
Current bound member: none
```

## 11. 状态优先级

DeepTutorChat 必须使用以下优先级：

```text
1. requestSnapshot.boundMemberID
   - 用于重试、重新生成、历史消息复现。

2. conversation.memberID
   - 当前会话有效绑定成员。

3. memberContextStore.context.selectedMemberID
   - 只作为新会话默认建议，不等于当前会话绑定。

4. toolSelectedMemberID
   - 只在工具 pending/resume 中使用；提交后才写入 conversation.memberID。
```

禁止：

```text
发送链路直接用 global selectedMemberID 覆盖 conversation.memberID。
工具静默用 global selectedMemberID 当作已绑定成员。
用户切换成员后继续使用旧 request snapshot 进行 live send。
```

## 12. 与健康资料上下文的关系

切换成员后必须处理：

```text
1. 清理不匹配的 health resource refs。
2. 清理 member-specific context references。
3. 清理本轮未发送的旧成员资料附件。
4. 已发送历史消息不重写。
5. 重试旧消息时使用旧 request snapshot。
```

Chat 已有：

```text
stateStore.pruneHealthResourceRefs(matchingMemberID: memberID, for: threadID)
```

DeepTutorChat 应实现等价但独立的：

```text
DeepTutorConversationContextPruner.pruneMemberDependentReferences(
    matchingMemberID: memberID,
    conversationID: conversationID
)
```

## 13. 实施计划

### Phase 1: 明确会话绑定成员状态

任务：

```text
1. 梳理 DeepTutorConversation.memberID 的读取和写入点。
2. 新增 DeepTutorMemberBindingSource 枚举。
3. 新增 DeepTutorBoundMemberDisplayModel。
4. ViewModel 暴露 boundMemberID / boundMemberDisplayName。
```

验收：

```text
打开会话能正确显示 conversation.memberID。
成员不存在时显示失效状态。
```

### Phase 2: 输入框成员选择组件

任务：

```text
1. 新增 DeepTutorBoundMemberPickerChip。
2. 新增 DeepTutorBoundMemberMenu。
3. 在 DeepTutorComposerToolbarView 中挂载 memberChip。
4. 将 memberID、members、onSetMemberBinding 从 DeepTutorComposerView 传入。
```

验收：

```text
未绑定显示“选择成员”。
已绑定显示成员名/关系。
点击可选择、切换、解绑。
发送中组件禁用。
```

### Phase 3: 持久化与会话列表同步

任务：

```text
1. 新增 UpdateDeepTutorConversationMemberBindingUseCase。
2. ViewModel 调用 use case 更新 memberID。
3. 更新 conversation 和 list item。
4. 记录 deeptutor.member_binding.changed 日志。
```

验收：

```text
切换后刷新页面仍保持成员。
会话列表重新加载后 memberID 不丢。
```

### Phase 4: 工具检查当前绑定成员

任务：

```text
1. 新增 DeepTutorGetCurrentMemberBindingTool。
2. 工具从 DeepTutorToolContext.boundMemberID 和 member data source 读取当前成员。
3. 工具返回 bound/unbound JSON。
4. ToolRegistry composition 中加入该工具。
```

验收：

```text
已绑定时工具返回 member_id/member_name。
未绑定时工具返回 bound=false。
不触发 UI 卡片。
```

### Phase 5: request_member_selection 语义升级

任务：

```text
1. 当前已有绑定成员时，除非模型明确说明切换原因，否则不弹卡。
2. 用户在卡片选择成员后，统一走 UpdateDeepTutorConversationMemberBindingUseCase。
3. pending 卡片恢复时校验当前会话成员是否已变化。
```

验收：

```text
工具选择成员和输入框 chip 状态一致。
工具提交后输入框即时更新。
输入框切换后后续工具读取新成员。
```

### Phase 6: Prompt / Snapshot / Debug

任务：

```text
1. requestSnapshot 增加 boundMemberID / memberName。
2. Prompt 注入当前绑定成员摘要。
3. Debug exporter 输出 boundMemberID、memberBindingSource。
4. 日志区分 composerManual/toolSelection/cleared。
```

验收：

```text
Debug 快照能解释本轮为什么使用某个成员。
重试旧消息不会被新成员污染。
```

## 14. 测试计划

### 14.1 UI 测试

```text
未绑定会话 -> 输入框显示“选择成员”
选择成员 -> chip 显示成员名
切换成员 -> chip 更新
解绑成员 -> chip 回到“选择成员”
发送中 -> chip disabled
成员失效 -> chip 显示“成员失效”
```

### 14.2 数据测试

```text
updateConversationMemberBinding(memberID: 12) 后 loadConversation 返回 12
updateConversationMemberBinding(memberID: nil) 后 loadConversation 返回 nil
重复设置同一 memberID 不重复写库
切换成员会更新 updatedAt
```

### 14.3 工具测试

```text
get_current_member_binding 已绑定返回 bound=true
get_current_member_binding 未绑定返回 bound=false
request_member_selection 未绑定返回 pause card
request_member_selection 选择后写入 conversation.memberID
request_member_selection 恢复后继续原始请求
```

### 14.4 回归测试

```text
Chat 的成员绑定按钮行为不变。
DeepTutorChat 的消息内成员选择卡行为不回归。
DeepTutorChat 发送普通消息不强制选择成员。
体检计划类请求无成员时仍可触发成员选择。
```

## 15. 验收标准

本工单完成后必须满足：

```text
1. DeepTutorChat 输入框内存在成员选择组件。
2. 当前会话是否绑定成员一眼可见。
3. 用户可主动绑定、切换、解绑成员。
4. 绑定成员持久化到 DeepTutorConversation.memberID。
5. 刷新、重进会话后成员绑定不丢失。
6. 工具可检查当前会话绑定成员。
7. 工具需要切换成员时必须通过用户确认。
8. 工具成员选择提交后，输入框成员状态同步更新。
9. 切换成员后，不再携带旧成员健康资料上下文。
10. Chat 模块现有成员绑定能力不受影响。
```

## 16. 文件级落地清单

### 16.1 Domain 层

#### 修改 `DeepTutorMessage.swift`

现状：

```swift
struct DeepTutorConversation {
    var memberID: Int?
}
```

第一阶段保持 `memberID` 字段不变，避免 CoreData 迁移放大改动。

建议新增：

```swift
enum DeepTutorMemberBindingSource: String, Codable, Sendable {
    case composerManual
    case toolSelection
    case restored
    case cleared
}
```

如果暂不落库 source，也要用于日志和 ViewModel 参数。

#### 修改 `DeepTutorMessageBlock.swift`

如果现有 `DeepTutorRequestSnapshot` 还没有成员字段，补充：

```swift
var boundMemberID: Int?
var boundMemberName: String?
var boundMemberSnapshotSource: String?
```

注意：

```text
Snapshot 是“本轮发送时”的成员事实。
conversation.memberID 是“当前会话最新”的成员事实。
二者不能互相覆盖。
```

#### 新增 `DeepTutorBoundMemberDisplayModel.swift`

路径建议：

```text
Projects/Features/DeepTutorChat/Domain/DeepTutorBoundMemberDisplayModel.swift
```

内容建议：

```swift
struct DeepTutorBoundMemberDisplayModel: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unbound
        case bound(memberID: Int, title: String, subtitle: String?)
        case missing(memberID: Int)
    }

    let state: State
    let iconName: String
    let title: String
    let accessibilityLabel: String
}
```

生成规则：

```text
memberID == nil -> unbound
memberID 存在且 members 中能找到 -> bound
memberID 存在但 members 中找不到 -> missing
```

### 16.2 Application 层

#### 新增 `UpdateDeepTutorConversationMemberBindingUseCase.swift`

路径建议：

```text
Projects/Features/DeepTutorChat/Application/UpdateDeepTutorConversationMemberBindingUseCase.swift
```

接口：

```swift
struct UpdateDeepTutorConversationMemberBindingUseCase: Sendable {
    let repository: DeepTutorLocalChatRepository
    let logger: Logger

    func execute(
        conversationID: UUID,
        currentMemberID: Int?,
        nextMemberID: Int?,
        source: DeepTutorMemberBindingSource
    ) async throws -> DeepTutorConversation
}
```

行为：

```text
1. currentMemberID == nextMemberID 时直接 loadConversation 返回。
2. nextMemberID <= 0 归一化为 nil。
3. 调 repository.updateConversationMemberBinding。
4. loadConversation 并返回最新 conversation。
5. 写日志 deeptutor.member_binding.changed。
```

#### 修改 `DeepTutorChatViewModel.swift`

新增只读派生属性：

```swift
var boundMemberID: Int? { conversation?.memberID }
var boundMemberDisplayModel: DeepTutorBoundMemberDisplayModel { ... }
```

新增方法：

```swift
@MainActor
func updateConversationMemberBinding(
    _ memberID: Int?,
    source: DeepTutorMemberBindingSource = .composerManual
) async
```

方法内要求：

```text
1. 如果 state.isStreaming == true，拒绝切换并提示。
2. 调用 UpdateDeepTutorConversationMemberBindingUseCase。
3. 更新 self.conversation。
4. 如果会话列表 item 在当前 ViewModel 内维护，同步刷新。
5. 调用 DeepTutorConversationContextPruner 清理旧成员上下文。
6. 如果存在 pending memberSelection block：
   - 不自动提交。
   - 标记需要用户重新确认，避免静默改变 pending resume。
```

#### 修改 `SendDeepTutorAIMessageUseCase.swift`

在 live send 构造 request snapshot 时写入：

```text
conversation.memberID
member display name
```

在 `submitMemberSelection(...)` 中，当前已有：

```swift
try await repository.updateConversationMemberBinding(conversationID: conversationID, memberID: memberID)
```

需要改为统一调用用例或至少统一日志/source：

```text
source = toolSelection
```

并确保 ViewModel 收到更新后输入框 chip 刷新。

#### 修改 `DeepTutorRuntimeRequestBuilder.swift`

Prompt 构造时增加成员上下文块：

```text
Current conversation member:
- bound: true
- member_id: 12
- display_name: 爸爸
```

未绑定：

```text
Current conversation member:
- bound: false
```

注意：

```text
这个上下文只来自 conversation.memberID 或 requestSnapshot。
不要从 memberContextStore.context.selectedMemberID 隐式生成。
```

### 16.3 Tools 层

#### 修改 `DeepTutorToolName.swift`

新增：

```swift
case getCurrentMemberBinding = "get_current_member_binding"
```

#### 新增 `DeepTutorGetCurrentMemberBindingTool.swift`

路径建议：

```text
Projects/Features/DeepTutorChat/Application/Tools/Builtins/DeepTutorGetCurrentMemberBindingTool.swift
```

执行伪代码：

```swift
func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
    guard let memberID = context.boundMemberID else {
        return .json([
            "bound": false,
            "instruction": "Call request_member_selection if member-specific context is required."
        ])
    }

    let member = await context.memberDataSource.member(id: memberID)
    return .json([
        "bound": true,
        "member_id": memberID,
        "member_name": member?.name ?? "",
        "member_missing": member == nil
    ])
}
```

#### 修改 `DeepTutorToolContext`

需要包含：

```swift
let conversationID: UUID
let boundMemberID: Int?
let memberDataSource: DeepTutorMemberToolDataSource
```

如当前 `DeepTutorMemberToolDataSource` 只有：

```swift
func members() async -> [Member]
```

建议增加默认扩展：

```swift
extension DeepTutorMemberToolDataSource {
    func member(id: Int) async -> Member? {
        await members().first { $0.id == id }
    }
}
```

#### 修改 `DeepTutorToolRegistry.swift`

第一阶段 composition 建议：

```text
always:
  ask_user
  write_memory
  get_current_member_binding

conditional:
  request_member_selection when boundMemberID == nil
  read_memory when hasMemory
```

如果后续支持“切换成员”，即使已绑定也可以挂载 `request_member_selection`，但 prompt 必须要求用户确认。

### 16.4 Presentation 层

#### 修改 `DeepTutorComposerView.swift`

新增入参：

```swift
let boundMember: DeepTutorBoundMemberDisplayModel
let members: [Member]
let onSetMemberBinding: (Int?) -> Void
```

继续传给：

```text
DeepTutorComposerCardView
```

#### 修改 `DeepTutorComposerCardView.swift`

新增同样入参，并传给：

```text
DeepTutorComposerToolbarView
```

#### 修改 `DeepTutorComposerToolbarView.swift`

新增：

```swift
let boundMember: DeepTutorBoundMemberDisplayModel
let members: [Member]
let onSetMemberBinding: (Int?) -> Void
```

在 toolbar 中加入：

```swift
DeepTutorBoundMemberPickerChip(
    displayModel: boundMember,
    members: members,
    isDisabled: isStreaming,
    onSelect: onSetMemberBinding
)
```

放置顺序：

```text
capabilityMenu
modelChip
memberChip
Spacer
attachmentButton
sendStopButton
```

#### 新增 `DeepTutorBoundMemberPickerChip.swift`

路径建议：

```text
Projects/Features/DeepTutorChat/Presentation/DeepTutorBoundMemberPickerChip.swift
```

组件要求：

```text
1. 使用 Menu，不使用 Sheet。
2. 宽度不能挤压发送按钮。
3. 长名字最多一行，超出截断。
4. 已绑定绿色，未绑定 secondary，失效橙色。
5. 发送中 disabled。
6. VoiceOver 能读出“当前会话成员：xxx”。
```

菜单交互：

```text
ForEach(members):
  当前 member 显示 checkmark
  点击调用 onSelect(member.id)

Divider
解绑成员:
  仅 bound 时可点
  调用 onSelect(nil)
```

### 16.5 Infrastructure 层

#### 修改 `DeepTutorLocalChatStore.swift`

现有方法已经存在：

```swift
func updateConversationMemberBinding(conversationID: UUID, memberID: Int?) async throws
```

需要确认并补齐：

```text
1. memberID nil 时 CoreData 字段能清空。
2. updatedAt 更新。
3. postChange kind 建议从 messagesUpdated 调整为 metadataUpdated / conversationUpdated。
4. affectsConversationList 如果列表要显示成员状态，应为 true；如果不显示，可保持 false。
```

#### 修改通知事件

如果 `DeepTutorConversationChangeEvent.Kind` 没有合适类型，新增：

```swift
case memberBindingUpdated
```

用于 UI 监听时不误判为消息更新。

## 17. 冲突决策表

| 场景 | 决策 |
| --- | --- |
| 会话未绑定，用户发送通用问题 | 不要求选择成员，正常回答 |
| 会话未绑定，用户发送体检/报告/用药等成员相关问题 | 工具先 `get_current_member_binding`，再 `request_member_selection` |
| 会话已绑定 A，用户输入“帮妈妈看看” | AI 不静默切换；调用 `request_member_selection` 或提示用户用 chip 切换 |
| 会话已绑定 A，用户在输入框切到 B | 立即持久化 B，后续 live send 使用 B |
| 会话已绑定 A，pending 成员选择卡提交 B | 允许提交，source=toolSelection，并同步输入框显示 B |
| 用户切换成员时正在 streaming | 禁止切换，提示等待当前回复完成 |
| 成员列表为空 | chip 显示“选择成员”，菜单提示暂无成员，普通对话不受阻塞 |
| 已绑定 memberID 在成员列表中找不到 | chip 显示“成员失效”，菜单允许重新选择或解绑 |
| 重试历史消息时当前会话已切换成员 | 使用历史 requestSnapshot 的 boundMemberID，不用当前最新成员 |
| 用户解绑成员后继续问健康计划 | 不使用旧成员资料，必要时重新请求选择 |

## 18. 日志与埋点

新增日志：

```text
deeptutor.member_binding.changed
  conversation
  oldMemberID
  newMemberID
  source

deeptutor.member_binding.change_rejected
  conversation
  reason=streaming|same_member|invalid_member

deeptutor.member_binding.snapshot_attached
  conversation
  message
  memberID

deeptutor.tool.get_current_member_binding
  conversation
  bound
  memberID
  missing
```

Debug exporter 增加：

```text
conversationMemberID
requestSnapshotBoundMemberID
boundMemberDisplayState
memberBindingSource
memberContextSource
```

## 19. 视觉与交互细节

### 19.1 Chip 文案

```text
未绑定：选择成员
已绑定：成员名优先；没有成员名时显示“成员 #12”
失效：成员失效
```

不要使用只截最后两个字作为唯一规则。可以在空间不足时用：

```text
张小明 -> 小明
爸爸 -> 爸爸
成员名过长 -> 前 4 个字符 + ...
```

### 19.2 防误触

```text
1. 已绑定时点击 chip 默认打开菜单，不直接解绑。
2. 解绑必须通过菜单项。
3. 切换成员不需要二次确认，但 pending 工具卡恢复前要校验。
4. 如果当前草稿已有成员相关健康资料引用，切换成员前提示“将移除当前成员资料引用”。
```

### 19.3 空状态

成员列表为空：

```text
Menu 中显示：
暂无家庭成员
```

如果已有成员管理入口，可提供：

```text
添加成员
```

没有入口时不要放假按钮。

## 20. 最终问答标准

当 DeepTutorChat 已绑定成员时，AI 回答标准：

```text
1. 能自然体现“本轮基于某成员上下文”，但不在每次回答里机械重复成员姓名。
2. 涉及健康、体检、报告、用药、家族史时，优先使用当前绑定成员。
3. 如果用户的问题明显指向另一个成员，应请求确认切换。
4. 如果当前没有绑定成员，但问题需要个体信息，应先请求选择成员或用 ask_user 补齐。
5. 如果问题可通用回答，不打断用户选择成员。
```

示例：

```text
用户已绑定“爸爸”，输入：帮我制定下次体检计划

AI 应：
  - 使用爸爸作为当前成员上下文
  - 如缺少年龄/病史/报告资料，可调用工具或 ask_user
  - 输出体检计划

AI 不应：
  - 重新问“你要给谁制定”
  - 静默切换到全局默认成员
  - 使用其他成员资料
```

## 21. Done Definition

```text
DeepTutorChat 的“会话绑定成员”成为一等上下文：

输入框可见
会话可存储
工具可读取
切换需用户确认
发送可注入 Prompt
历史可用 Snapshot 复现
成员切换会清理旧上下文

并且不复制 Chat 的冗余状态冲突。
```
