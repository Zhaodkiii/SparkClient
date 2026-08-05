# CHAT-000010 P2 能力显式化与 ToolHub 瘦身需求工单

## 工单状态

已实现（2026-08-05）。

## 1. 背景

CHAT-000009 已建立 `ChatCapabilityStrategy` 与 ToolHub 边界门禁，但仍有偏差：

1. 问报告 / 健康抽取 / 知识处理尚未在代码中显式携带 capability 身份。
2. `ToolHub.swift` 单文件 900+ 行，schema / 路由 / consent / audit 混装。
3. 调试 slash 命令早退路径未 apply `ToolSideEffect`，与模型 tool loop 不一致。

## 2. 目标

1. 问报告显式为 `ReportInterpretationCapabilityStrategy`。
2. 健康抽取 / 知识处理显式 `capabilityName`（静态标识，无 Registry）。
3. ToolHub 按职责拆分为同类型 extension 文件。
4. 修复 slash 早退路径副作用丢失。
5. 补齐测试与总领文档。

## 3. 改动范围

### 3.1 问报告 capability

- `ChatCapabilityStrategyInput.hasHealthResourceContext`
- `ReportInterpretationCapabilityStrategy`（`plan()` 与标准聊天等价）
- `ChatCapabilityStrategyResolver.resolve(smallTask:hasHealthResourceContext:)`
- `SendChatMessageUseCase` 传入 `healthContextForAI?.isEmpty == false`

### 3.2 健康抽取 / 知识处理 capability 标记

- `TypedMedicalDocumentExtracting` / `MedicalDocumentTypeResolving` 协议扩展 `capabilityName = "medical_extraction"`
- `KnowledgeProcessingCapability` 协议；三个文本处理 UseCase 遵循

### 3.3 ToolHub 瘦身

- `ToolHub+Schema.swift` / `ToolHub+Routing.swift` / `ToolHub+Consent.swift` / `ToolHub+Audit.swift`
- `ToolHub.swift` 仅保留 DI 与共享 helper

### 3.4 副作用一致性

- `ChatOrchestrator` slash 早退分支 apply `result.sideEffects` → `MessageRunActor`

## 4. 不做的事

- 不把问报告切到 `AIScenario.reportInterpretation`。
- 不引入 `CapabilityRegistry` 或动态派发。
- 不把 ToolHub 拆成多个 DI 对象。
- 不改 `MessageRunActor` / `ToolSideEffectBlockMapper` 内部实现。

## 5. 验收方式

1. `ChatCapabilityStrategyTests` 覆盖问报告策略与 resolver 优先级。
2. `MedicalExtractionCapabilityTests` / `KnowledgeProcessingCapabilityTests` 通过。
3. `ChatOrchestratorDebugToolSideEffectTests` 通过。
4. `AIRuntimeArchitectureGateTests` 扫描 `ToolHub/**`（含拆分文件）无 capability 类型引用。
5. `xcodebuild` 编译通过。

## 6. 实施记录

### 实施日期

2026-08-05

### 已完成项

1. **问报告 capability**：新增 `ReportInterpretationCapabilityStrategy`；resolver 支持 `hasHealthResourceContext`；`SendChatMessageUseCase` 接入。
2. **健康抽取标记**：`TypedMedicalDocumentExtracting` / `MedicalDocumentTypeResolving` 协议扩展 `capabilityName`；抽取/类型解析日志携带 capability 名。
3. **知识处理标记**：`KnowledgeProcessingCapability` 协议；润色/翻译/自动填充三个 UseCase 遵循。
4. **ToolHub 拆分**：`ToolHub+Schema/Routing/Consent/Audit.swift`；主文件仅 DI。
5. **副作用修复**：`ChatOrchestrator` slash 早退路径 apply `ToolSideEffect`。
6. **测试**：扩展 `ChatCapabilityStrategyTests`；新增 `MedicalExtractionCapabilityTests`、`KnowledgeProcessingCapabilityTests`、`ChatOrchestratorDebugToolSideEffectTests`。
7. **文档**：更新两份总领文档 capability 全景表与 ToolHub 目录结构。

### 变更文件清单

| 操作 | 文件 |
| --- | --- |
| 修改 | `Projects/Core/AIRuntime/ChatCapabilityStrategy.swift` |
| 修改 | `Projects/Features/Chat/Application/SendChatMessageUseCase.swift` |
| 修改 | `Projects/Features/MedicalDocumentUpload/Domain/MedicalDocumentUploadProtocols.swift` |
| 修改 | `Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultTypedMedicalDocumentExtractor.swift` |
| 修改 | `Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultMedicalDocumentTypeResolver.swift` |
| 修改 | `Projects/Features/Knowledge/Application/KnowledgeTextProcessingUseCases.swift` |
| 修改 | `Projects/Core/AIRuntime/ChatOrchestrator.swift` |
| 修改 | `Projects/Core/AIRuntime/ToolHub/ToolHub.swift` |
| 新增 | `Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift` |
| 新增 | `Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift` |
| 新增 | `Projects/Core/AIRuntime/ToolHub/ToolHub+Consent.swift` |
| 新增 | `Projects/Core/AIRuntime/ToolHub/ToolHub+Audit.swift` |
| 修改 | `Tests/Chat/ChatCapabilityStrategyTests.swift` |
| 新增 | `Tests/Medical/MedicalExtractionCapabilityTests.swift` |
| 新增 | `Tests/Knowledge/KnowledgeProcessingCapabilityTests.swift` |
| 新增 | `Tests/Chat/ChatOrchestratorDebugToolSideEffectTests.swift` |
| 修改 | `总领文档/对话、AI Runtime 与工具调用/AI Runtime 推理编排需求.md` |
| 修改 | `总领文档/对话、AI Runtime 与工具调用/工具调用与审计需求.md` |
