# CHAT-000020 Chat 工具交互消息卡片本地化补齐需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000020 |
| 工单类型 | P1 Chat / 工具交互卡片 / 本地化 / 文案治理 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标文件 | `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ToolInteraction/ChatToolInteractionMessageCards.swift` |
| 创建日期 | 2026-08-14 |
| 关联工单 | `CHAT-000012`、`AISETTINGS-000002`、`AISETTINGS-000003` |
| 明确非目标 | 不调整卡片交互流程；不改变工具调用状态机；不改变授权策略；不改 DeepTutorChat 独立工具卡片 |

## 1. 背景与问题

`ChatToolInteractionMessageCards.swift` 承载 Chat 会话内的工具交互卡片，包括工具提问、成员选择、健康资料候选选择、模型出境授权、位置权限请求等用户可见 UI。当前文件内存在大量中文硬编码文案，没有进入 `Localizable.strings`。

这会导致：

1. 英文系统语言下，工具交互卡片仍显示简体中文。
2. 繁体中文环境缺少对应文案。
3. 工具交互卡片属于阻塞式流程，文案不本地化会影响用户是否理解下一步操作。
4. 授权、位置权限、健康资料选择等敏感流程无法统一审校和合规调整。

本工单目标是把该文件中的用户可见文案全部纳入本地化资源，并建立稳定 key 命名规则。

## 2. 当前代码范围

目标文件：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ToolInteraction/ChatToolInteractionMessageCards.swift
```

当前涉及的卡片类型：

| View | 功能 |
| --- | --- |
| `ChatToolQuestionMessageCardView` | 工具向用户发起补充问题 |
| `ChatToolMemberSelectionMessageCardView` | 工具请求选择家庭成员 |
| `ChatHealthResourceCandidateMessageCardView` | 问报告 / 健康资料候选选择 |
| `ChatToolConsentMessageCardView` | 工具结果发送给 AI 的模型出境授权 |
| `ChatLocationPermissionMessageCardView` | 当前位置权限请求 / 跳转设置 |

## 3. 未本地化检查结果

### 3.1 工具提问卡片

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 74 | `请作答以继续` | 标题 | 提取 key |
| 77 | `该工具需要你的补充选择。` | 副标题 | 提取 key |
| 104 | `输入自定义回复` | TextField placeholder | 提取 key |
| 151 | `提交后工具会继续执行。` | footer | 提取 key |
| 157 | `提交` | 按钮 | 提取 key |
| 192 | `已提交回答` | 状态 | 提取 key |
| 194 | `已取消回答` | 状态 | 提取 key |
| 196 | `本次等待已失效` | 状态 | 提取通用 key，可被多卡片复用 |
| 198 | `等待回答` | 状态 | 提取 key |
| 215 | `工具等待已经结束。` | fallback 结果 | 提取 key |
| 261 | `已跳过：%@` / `%@：%@` / `，` | 动态格式 | 提取 format key；列表分隔符按 locale 处理 |

### 3.2 成员选择卡片

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 348 | `未选择成员将无法继续使用该工具。` | footer | 提取 key |
| 363 | `请选择成员` | 标题 | 提取 key |
| 366 | `该工具需要确认要查询哪位家庭成员。` | 副标题 | 提取 key |
| 421 | `已选择：%@` | 动态格式 | 提取 format key |
| 425 | `工具会继续使用该成员完成本次查询。` | fallback 结果 | 提取 key |
| 434 | `已选择成员` | 状态 | 提取 key |
| 436 | `已取消选择` | 状态 | 提取 key |
| 438 | `本次等待已失效` | 状态 | 复用通用 expired key |
| 440 | `等待选择成员` / `已选择成员，正在继续` | 状态 | 提取 key |
| 455 | `暂无可选择的成员档案` | 空状态标题 | 提取 key |
| 459 | `请先创建家庭成员后，再继续使用健康数据工具。` | 空状态说明 | 提取 key |
| 481 | `%d岁` | 年龄格式 | 提取 format key；英文应使用 `%d years old` 或更自然表达 |
| 486 | ` · ` | 元信息分隔符 | 不建议硬编码，需按 locale 或本地化 separator key |

### 3.3 健康资料候选卡片

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 540 | `选择健康资料以继续` | 标题 | 提取 key |
| 543 | `AI 找到多份可能相关的资料，你可以选择本次解读范围。` | 副标题 | 提取 key |
| 557 | `还有 %d 份资料可选` | 动态格式 | 提取 plural-aware key |
| 596 | `选择或跳过后，AI 会继续回答。` | footer | 提取 key |
| 602 | `跳过` | 按钮 | 提取 key |
| 612 | `选择资料` | 按钮 | 提取 key |
| 637 | `已跳过资料选择。` | fallback 结果 | 提取 key |
| 654 | `已选择健康资料` | 状态 | 提取 key |
| 656 | `已跳过资料选择` | 状态 | 提取 key |
| 658 | `本次等待已失效` | 状态 | 复用通用 expired key |
| 660 | `等待选择健康资料` | 状态 | 提取 key |
| 666 | `AI 将在未限定资料范围的情况下继续。` | resolved subtitle | 提取 key |
| 668 | `AI 将基于已选资料继续。` | resolved subtitle | 提取 key |

### 3.4 模型出境授权卡片

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 735 | `将工具结果发送至 AI` | 标题 | 与 `AISETTINGS-000003` 授权文案命名空间协调 |
| 738 | `工具已在本地完成，继续前需要确认是否发送结果给模型。` | 副标题 | 提取 key |
| 766 | `拒绝` | 按钮 | 提取 key |
| 776 | `查看详情` | 按钮 | 提取 key |
| 786 | `始终允许` | 按钮 | 提取 key；需确认与设置页 `始终运行` 术语是否统一 |
| 813 | `已始终允许` / `已允许发送` | 状态 | 提取 key |
| 815 | `已拒绝发送` | 状态 | 提取 key |

说明：该卡片与 AI 设置授权管理页属于同一产品语义，但 UI 场景不同。实现时建议复用 `ai_settings.tool_consent` 下的通用按钮和模式文案，卡片专属状态放到 `chat.tool_interaction.consent.*`。

### 3.5 位置权限卡片

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 903 | `需要位置权限` | 标题 | 提取 key |
| 905 | `无法获取当前位置` | 标题 | 提取 key |
| 912 | `授权后将重新获取当前位置并继续回复。` | 副标题 | 提取 key |
| 914 | `你可以前往系统设置开启位置权限。` | 副标题 | 提取 key |
| 921 | `AI 需要你的当前位置来完成本次查询。点击授权后，系统会弹出位置权限确认。` | 正文 | 提取 key |
| 923 | `当前应用没有位置权限，因此本次无法读取当前位置。AI 会基于无权限状态继续回答。` | 正文 | 提取 key |
| 930 | `允许位置` | 按钮 | 提取 key |
| 932 | `打开设置` | 按钮 | 提取 key |
| 941 | `已允许位置权限` / `未允许位置权限` | 状态 | 提取 key |
| 945 | `用户已允许位置权限。` / `用户未允许位置权限。` | 结果说明 | 提取 key |

## 4. 需求目标

1. `ChatToolInteractionMessageCards.swift` 中用户可见中文文案全部替换为本地化读取。
2. 补齐 `zh-Hans`、`en`、`zh-Hant` 三套文案。
3. 动态文案使用格式化 key，不在代码中拼接中文标点和中文语序。
4. 复用通用状态文案，例如“本次等待已失效”不要在多处重复定义不同 key。
5. 与 `AISETTINGS-000003` 的授权管理本地化保持术语一致，尤其是“始终允许 / 始终运行”的产品词需要统一。
6. 保持现有交互行为不变：提交、选择成员、跳过资料、授权、位置权限请求等逻辑不做调整。

## 5. 建议 key 命名空间

建议使用：

```text
chat.tool_interaction.*
```

推荐分层：

| key 前缀 | 用途 |
| --- | --- |
| `chat.tool_interaction.common.*` | 通用状态、通用按钮、通用分隔符 |
| `chat.tool_interaction.question.*` | 工具提问卡片 |
| `chat.tool_interaction.member_selection.*` | 成员选择卡片 |
| `chat.tool_interaction.health_resource.*` | 健康资料候选卡片 |
| `chat.tool_interaction.consent.*` | 工具结果发送给 AI 授权卡片 |
| `chat.tool_interaction.location_permission.*` | 位置权限卡片 |

可复用的全局 action key：

```text
common.submit
common.skip
common.open_settings
common.view_details
common.deny
```

如果项目已有统一 `common.*` key，应优先复用，避免新增重复 key。

## 6. 推荐文案 key 清单

### 6.1 通用

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `chat.tool_interaction.common.expired` | 本次等待已失效 | This request has expired | 本次等待已失效 |
| `chat.tool_interaction.common.separator` |  ·  |  ·  |  ·  |
| `chat.tool_interaction.common.submit` | 提交 | Submit | 提交 |
| `chat.tool_interaction.common.skip` | 跳过 | Skip | 跳過 |
| `chat.tool_interaction.common.view_details` | 查看详情 | View Details | 查看詳情 |
| `chat.tool_interaction.common.open_settings` | 打开设置 | Open Settings | 開啟設定 |
| `chat.tool_interaction.common.deny` | 拒绝 | Deny | 拒絕 |

### 6.2 工具提问

| key | zh-Hans |
| --- | --- |
| `chat.tool_interaction.question.title` | 请作答以继续 |
| `chat.tool_interaction.question.subtitle` | 该工具需要你的补充选择。 |
| `chat.tool_interaction.question.other_placeholder` | 输入自定义回复 |
| `chat.tool_interaction.question.footer` | 提交后工具会继续执行。 |
| `chat.tool_interaction.question.submitted` | 已提交回答 |
| `chat.tool_interaction.question.cancelled` | 已取消回答 |
| `chat.tool_interaction.question.pending` | 等待回答 |
| `chat.tool_interaction.question.finished_fallback` | 工具等待已经结束。 |
| `chat.tool_interaction.question.skipped_format` | 已跳过：%@ |
| `chat.tool_interaction.question.answer_format` | %@：%@ |

### 6.3 成员选择

| key | zh-Hans |
| --- | --- |
| `chat.tool_interaction.member_selection.title` | 请选择成员 |
| `chat.tool_interaction.member_selection.subtitle` | 该工具需要确认要查询哪位家庭成员。 |
| `chat.tool_interaction.member_selection.footer` | 未选择成员将无法继续使用该工具。 |
| `chat.tool_interaction.member_selection.selected_format` | 已选择：%@ |
| `chat.tool_interaction.member_selection.continue_with_member` | 工具会继续使用该成员完成本次查询。 |
| `chat.tool_interaction.member_selection.submitted` | 已选择成员 |
| `chat.tool_interaction.member_selection.cancelled` | 已取消选择 |
| `chat.tool_interaction.member_selection.pending` | 等待选择成员 |
| `chat.tool_interaction.member_selection.continuing` | 已选择成员，正在继续 |
| `chat.tool_interaction.member_selection.empty_title` | 暂无可选择的成员档案 |
| `chat.tool_interaction.member_selection.empty_message` | 请先创建家庭成员后，再继续使用健康数据工具。 |
| `chat.tool_interaction.member_selection.age_years_format` | %d岁 |

### 6.4 健康资料候选

| key | zh-Hans |
| --- | --- |
| `chat.tool_interaction.health_resource.title` | 选择健康资料以继续 |
| `chat.tool_interaction.health_resource.subtitle` | AI 找到多份可能相关的资料，你可以选择本次解读范围。 |
| `chat.tool_interaction.health_resource.remaining_format` | 还有 %d 份资料可选 |
| `chat.tool_interaction.health_resource.footer` | 选择或跳过后，AI 会继续回答。 |
| `chat.tool_interaction.health_resource.choose_action` | 选择资料 |
| `chat.tool_interaction.health_resource.skipped_fallback` | 已跳过资料选择。 |
| `chat.tool_interaction.health_resource.submitted` | 已选择健康资料 |
| `chat.tool_interaction.health_resource.cancelled` | 已跳过资料选择 |
| `chat.tool_interaction.health_resource.pending` | 等待选择健康资料 |
| `chat.tool_interaction.health_resource.continue_without_scope` | AI 将在未限定资料范围的情况下继续。 |
| `chat.tool_interaction.health_resource.continue_with_selection` | AI 将基于已选资料继续。 |

英文实现时需注意 `remaining_format` 应支持单复数，避免 `1 resources`。

### 6.5 模型出境授权

| key | zh-Hans |
| --- | --- |
| `chat.tool_interaction.consent.title` | 将工具结果发送至 AI |
| `chat.tool_interaction.consent.subtitle` | 工具已在本地完成，继续前需要确认是否发送结果给模型。 |
| `chat.tool_interaction.consent.allow_always` | 始终允许 |
| `chat.tool_interaction.consent.remembered` | 已始终允许 |
| `chat.tool_interaction.consent.allowed` | 已允许发送 |
| `chat.tool_interaction.consent.denied` | 已拒绝发送 |

术语待确认：

| 场景 | 当前词 | 建议统一 |
| --- | --- | --- |
| 设置页策略 | 始终运行 | 始终运行 |
| 运行时授权按钮 | 始终允许 | 始终允许此工具 |
| resolved 状态 | 已始终允许 | 已始终允许 |

如果产品要求术语完全一致，则运行时按钮也应改为“始终运行”。如果保留“始终允许”，需要在工单实现阶段明确两者语义对应。

### 6.6 位置权限

| key | zh-Hans |
| --- | --- |
| `chat.tool_interaction.location_permission.request_title` | 需要位置权限 |
| `chat.tool_interaction.location_permission.open_settings_title` | 无法获取当前位置 |
| `chat.tool_interaction.location_permission.request_subtitle` | 授权后将重新获取当前位置并继续回复。 |
| `chat.tool_interaction.location_permission.open_settings_subtitle` | 你可以前往系统设置开启位置权限。 |
| `chat.tool_interaction.location_permission.request_body` | AI 需要你的当前位置来完成本次查询。点击授权后，系统会弹出位置权限确认。 |
| `chat.tool_interaction.location_permission.open_settings_body` | 当前应用没有位置权限，因此本次无法读取当前位置。AI 会基于无权限状态继续回答。 |
| `chat.tool_interaction.location_permission.allow_action` | 允许位置 |
| `chat.tool_interaction.location_permission.authorized_title` | 已允许位置权限 |
| `chat.tool_interaction.location_permission.denied_title` | 未允许位置权限 |
| `chat.tool_interaction.location_permission.authorized_result` | 用户已允许位置权限。 |
| `chat.tool_interaction.location_permission.denied_result` | 用户未允许位置权限。 |

## 7. 实现要求

1. 文案读取使用项目现有 `L10n.text` / `L10n.format` 能力。
2. 对动态字符串使用 format key，例如 `selected_format`、`remaining_format`、`age_years_format`。
3. 列表拼接不要固定中文逗号。选项答案拼接建议使用本地化 separator 或 `ListFormatter`。
4. 年龄格式不要固定中文“岁”。英文环境应展示为自然英文。
5. 按钮文案要检查短文本在小屏宽度下是否换行或溢出，尤其是 `查看详情`、`始终允许`、`选择资料`。
6. `card.prompt`、`candidate.title`、`candidate.matchReason`、`member.name` 等服务端或用户数据不属于本工单本地化范围，只处理客户端固定文案。
7. `card.resultText` 可能来自运行时或持久化数据，不能在展示层强行翻译；只本地化 fallback 文案。
8. 繁体中文资源需要补齐。如果 `zh-Hant.lproj/Localizable.strings` 不存在，实现阶段需要新增并确认 target 收录。

## 8. 验收标准

1. `ChatToolInteractionMessageCards.swift` 中不再存在新增中文硬编码 UI 文案。
2. `zh-Hans`、`en`、`zh-Hant` 三套资源均包含本工单列出的 key。
3. 英文系统语言下，工具提问、成员选择、健康资料候选、出境授权、位置权限卡片均显示英文固定文案。
4. 繁体中文系统语言下，不回退到简体中文。
5. 动态文案格式正确：成员选择、年龄、剩余资料数量、问题回答摘要均符合当前语言语序。
6. 交互行为保持不变：提交、选择、跳过、拒绝、查看详情、始终允许、允许位置、打开设置均能正常触发原回调。
7. 小屏宽度下按钮不发生不可读截断或互相挤压。
8. 至少完成一次 Debug 构建验证，并进行英文 / 简体中文 UI smoke check。

## 9. 回归检查建议

1. 触发 `ask_user_question`，检查工具提问卡片的标题、输入框 placeholder、提交按钮、提交后状态。
2. 触发 `request_member_selection`，检查成员选择卡片、空成员状态、已选择状态和年龄显示。
3. 触发健康资料候选选择，检查候选数量超过 3 时的剩余数量文案。
4. 触发工具结果发送给 AI 授权，检查拒绝、查看详情、始终允许按钮和 resolved 状态。
5. 触发当前位置权限请求，检查系统权限前、权限拒绝后、打开设置模式下的标题与按钮。

## 10. 风险与注意事项

1. 该文件部分文案是阻塞式工具流程的关键指引，本地化不能只做直译，需要保证用户知道下一步会发生什么。
2. `ChatToolConsentMessageCardView` 与 `AISETTINGS-000003` 的授权管理文案存在术语交叉，实现时需要统一“发送至 AI”“发送给 AI”“始终允许”“始终运行”等词。
3. `card.resultText` 如果由模型或工具运行时生成，可能已经是中文；本工单不处理历史运行结果语言问题。
4. 英文复数和年龄表达不能只靠中文格式直接替换，必要时应使用 `.stringsdict` 或最小化 format 分支。
