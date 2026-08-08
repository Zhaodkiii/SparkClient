# DEEPTUTORCHAT-CHANGELOG-000044 本次变更说明

## 变更日期

2026-08-08

## 变更范围

本次变更同时覆盖 DeepTutorChat 对话运行时编排、模型/智能体上下文解析、工具调用链路可观测性、iOS 26 首页独立拆分与主导航入口调整。

## DeepTutorChat 对话编排

- 新增 `DeepTutorTurnCoordinator`，将发送、重试、重新生成统一抽象为 `DeepTutorTurnPlan`，收口 capability、模型、工具策略、prompt、snapshot 与本轮 turnID。
- 新增 `DeepTutorTurnEventBus`，记录并回放本轮流式事件，支持工具调用、AskUser、成员选择等关键事件进入调试导出链路。
- `SendDeepTutorAIMessageUseCase` 改为基于 TurnPlan 执行，发送、重试、重新生成复用同一条执行入口，减少临时 snapshot 构造分散的问题。
- AskUser 回答与成员选择恢复流程补充事件发布，并在恢复流中沿用原用户消息的 requestSnapshot，保证模型、工具和 prompt 语义可复现。

## 模型与智能体上下文

- 新增 `DeepTutorModelContextResolver`，统一解析当前会话模型、智能体 identity、base model、系统提示词、工具白名单、多模态能力、温度与 token 参数。
- 新增 `DeepTutorPromptMerger`，将智能体/会话人设与 DeepTutor capability 协议合并，避免智能体提示词被默认 capability prompt 覆盖。
- `DeepTutorRuntimeRequestBuilder` 增加 finalization 流程，统一输出最终 systemPrompt、inference、允许工具集合、生成参数与合并原因。
- DeepTutor 聊天页增加模型选择器状态与会话级模型持久化，模型配置变化时自动校验当前选择并回落到 chat 场景默认模型。

## 工具与调试

- 日志补充模型上下文解析、生成参数、工具策略合并、prompt/schema mismatch 等关键节点。
- `DeepTutorChatDebugExporter` 增加 TurnPlan 与事件回放信息，便于定位工具调用、暂停恢复、Quiz/AskUser 中断恢复问题。
- message block 与本地 store 补充 requestSnapshot/turn 相关字段存储能力，保证历史消息可用于回放和重新生成。

## iOS 26 首页与导航

- 新增 `IOS26HomeView` 作为 iOS 26 首页独立 root，承载首页工作台、sheet/fullScreenCover、Launch Intent、上传页、成员详情等宿主能力。
- `HomeView` 回归旧版首页实现，不再混入 iOS 26 dashboard 分支，降低首页双实现耦合。
- `IOS26TabBarView` 增加设置 Tab，并把 iOS 26 首页入口切换到 `IOS26HomeView`。
- 首页动作卡相关 `.onChange(of:perform:)` 迁移到 iOS 新签名，处理弃用警告。

## 测试补充

- 新增 `DeepTutorModelContextResolverTests`，覆盖智能体 prompt source、工具白名单禁用/交集、重放优先 snapshot 模型、智能体生成参数等规则。
- 新增 `DeepTutorTurnCoordinatorTests`，覆盖 capability stage pipeline、turn envelope 写入与 resume mode Codable。

## 对应工单

- `DEEPTUTORCHAT-000037`：体检报告制定计划智能体需求。
- `DEEPTUTORCHAT-000038`：DeepTutorChat 模型智能体提示词与工具选择对齐。
- `DEEPTUTORCHAT-000039`：DeepTutorChat 与 DeepTutor-main-agent-native 分层编排差距优化。
- `DEEPTUTORCHAT-000040`：DeepTutorChat 与 Chat 工具交互模式隔离优化。
- `DEEPTUTORCHAT-000041`：工具调用与 Quiz 卡片流程对齐优化。
- `DEEPTUTORCHAT-000042`：健康体检计划流程意外停止与暂停边界修复。
- `DEEPTUTORCHAT-000043`：独立工具架构对齐 DeepTutor-main。
- `IOS26-TABBAR-000004`：iOS 26 首页从 HomeView 独立拆分。
- `IOS26-TABBAR-000005`：iOS 26 首页动作卡直达首页与 onChange 弃用治理。
