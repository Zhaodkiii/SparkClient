import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    private let extractDraftUseCase: ExtractMedicalDraftFromDocumentUseCase
    private let confirmDraftUseCase: ConfirmMedicalDraftUseCase
    private let loadLatestDraftUseCase: LoadLatestMedicalDraftUseCase
    private let auditStore: ToolAuditStore
    private let medicalDataRepository: any MedicalDataRepository
    private let healthMetricsRepository: any HealthMetricsRepository
    private let aiSettingsRepository: any AISettingsRepository
    private let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    private var canvasStore: [String: String] = [:]

    init(
        extractDraftUseCase: ExtractMedicalDraftFromDocumentUseCase,
        confirmDraftUseCase: ConfirmMedicalDraftUseCase,
        loadLatestDraftUseCase: LoadLatestMedicalDraftUseCase,
        auditStore: ToolAuditStore,
        medicalDataRepository: any MedicalDataRepository,
        healthMetricsRepository: any HealthMetricsRepository,
        aiSettingsRepository: any AISettingsRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.extractDraftUseCase = extractDraftUseCase
        self.confirmDraftUseCase = confirmDraftUseCase
        self.loadLatestDraftUseCase = loadLatestDraftUseCase
        self.auditStore = auditStore
        self.medicalDataRepository = medicalDataRepository
        self.healthMetricsRepository = healthMetricsRepository
        self.aiSettingsRepository = aiSettingsRepository
        self.logger = logger
    }

    /// 若输入为审计命令、遗留 `/ocr` `/confirm_draft`、或已注册工具调用，则执行并返回 `.executed`；否则 `.none` 交由上层走模型。
    func runIfNeeded(userInput: String, patientID: UUID?) async -> ToolHubResult {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .none }
        logger.debug(
            "工具路由检查开始，patient=\(shortID(patientID)), inputLength=\(trimmed.count)",
            category: "tool_hub"
        )

        if trimmed == "/audit_tools" {
            logger.info("工具路由命中 /audit_tools", category: "tool_hub")
            return await handleAuditTools()
        }

        if let legacy = await handleLegacyCommands(trimmed: trimmed, patientID: patientID) {
            logger.info("工具路由命中 legacy，tool=\(legacy.toolName)", category: "tool_hub")
            return .executed(legacy)
        }

        guard let invocation = parseToolInvocation(from: trimmed) else {
            logger.debug("工具路由未命中，转入 AI 推理", category: "tool_hub")
            return .none
        }

        let context = ToolExecutionContext(patientID: patientID, locale: .current)
        let result = await execute(invocation: invocation, context: context)
        await appendAudit(invocation: invocation, context: context, result: result)
        return .executed(result)
    }

    /// `/audit_tools`：打印最近审计事件摘要。
    private func handleAuditTools() async -> ToolHubResult {
        let events = await auditStore.recent(limit: 20)
        if events.isEmpty {
            return .executed(
                ToolExecutionResult(
                    toolName: "audit_tools",
                    outputText: "最近没有工具调用审计记录。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            )
        }

        let lines = events.map { event in
            "[\(event.createdAt.formatted(date: .abbreviated, time: .shortened))] \(event.toolName) - \(event.status.rawValue)"
        }
        return .executed(
            ToolExecutionResult(
                toolName: "audit_tools",
                outputText: lines.joined(separator: "\n"),
                sensitive: false,
                shouldBypassModel: true
            )
        )
    }

    /// 兼容旧版斜杠：`/ocr <路径>` 抽病历草稿，`/confirm_draft` 写入正式病历；自行写审计，不走统一 `appendAudit`。
    private func handleLegacyCommands(trimmed: String, patientID: UUID?) async -> ToolExecutionResult? {
        if trimmed.hasPrefix("/ocr ") {
            guard let patientID else {
                return ToolExecutionResult(
                    toolName: "ocr_extract_draft",
                    outputText: "当前未选择成员，无法生成病历草稿。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            let path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let draft = try await extractDraftUseCase.execute(patientID: patientID, filePath: path)
                let output = """
                已生成病历草稿：
                标题：\(draft.title)
                摘要：\(draft.summary)
                诊断：\(draft.diagnosis ?? "待补充")

                如需写入正式病历，请发送 /confirm_draft
                """
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "ocr_extract_draft",
                        patientID: patientID,
                        inputSummary: path,
                        outputSummary: String(output.prefix(120)),
                        status: .success
                    )
                )
                return ToolExecutionResult(
                    toolName: "ocr_extract_draft",
                    outputText: output,
                    sensitive: true,
                    shouldBypassModel: true
                )
            } catch {
                let message = "病历草稿抽取失败：\(error.localizedDescription)"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "ocr_extract_draft",
                        patientID: patientID,
                        inputSummary: path,
                        outputSummary: message,
                        status: .failed
                    )
                )
                return ToolExecutionResult(
                    toolName: "ocr_extract_draft",
                    outputText: message,
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
        }

        if trimmed == "/confirm_draft" {
            guard let patientID else {
                return ToolExecutionResult(
                    toolName: "confirm_draft",
                    outputText: "当前未选择成员，无法确认草稿。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            guard let latestDraft = await loadLatestDraftUseCase.execute(patientID: patientID) else {
                return ToolExecutionResult(
                    toolName: "confirm_draft",
                    outputText: "未找到可确认的草稿，请先发送 /ocr <文件路径>。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            do {
                let record = try await confirmDraftUseCase.execute(patientID: patientID)
                let output = "草稿确认成功，已写入病历：\(record.title)（\(record.occurredAt.formatted(date: .abbreviated, time: .omitted))）"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "confirm_draft",
                        patientID: patientID,
                        inputSummary: latestDraft.title,
                        outputSummary: output,
                        status: .success
                    )
                )
                return ToolExecutionResult(
                    toolName: "confirm_draft",
                    outputText: output,
                    sensitive: true,
                    shouldBypassModel: true
                )
            } catch {
                let output = "草稿确认失败：\(error.localizedDescription)"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "confirm_draft",
                        patientID: patientID,
                        inputSummary: latestDraft.title,
                        outputSummary: output,
                        status: .failed
                    )
                )
                return ToolExecutionResult(
                    toolName: "confirm_draft",
                    outputText: output,
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
        }

        return nil
    }

    /// 将用户输入解析为 `ToolInvocation`：`/tool list`、`/tool <name> <args>`，或 `/` + 白名单工具名。
    private func parseToolInvocation(from input: String) -> ToolInvocation? {
        if input == "/tool list" {
            return ToolInvocation(name: "tool_list", arguments: [:])
        }

        if input.hasPrefix("/tool ") {
            let remainder = String(input.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard remainder.isEmpty == false else { return nil }
            let components = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = components.first else { return nil }
            let name = String(first)
            var arguments: [String: String] = [:]
            if components.count > 1 {
                arguments = parseArguments(String(components[1]))
            }
            return ToolInvocation(name: name, arguments: arguments)
        }

        if input.hasPrefix("/") {
            let remainder = String(input.dropFirst())
            let components = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = components.first else { return nil }
            let name = String(first)
            guard SparkToolName.all.contains(name) else { return nil }
            let arguments = components.count > 1 ? parseArguments(String(components[1])) : [:]
            return ToolInvocation(name: name, arguments: arguments)
        }

        return nil
    }

    /// 参数字符串：支持 JSON 对象，或 `key=value` 空格分隔；若都解析不到则把整段同时填入 query/content 等默认键。
    private func parseArguments(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [:] }

        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var args: [String: String] = [:]
            for (key, value) in object {
                args[key] = String(describing: value)
            }
            return args
        }

        var args: [String: String] = [:]
        let parts = trimmed.split(separator: " ")
        for part in parts {
            let item = String(part)
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if pair.count == 2 {
                args[String(pair[0])] = String(pair[1])
            }
        }
        if args.isEmpty {
            args["query"] = trimmed
            args["content"] = trimmed
            args["title"] = String(trimmed.prefix(20))
            args["raw_text"] = trimmed
        }
        return args
    }

    /// 按工具名分发到具体 `run*` 实现；多数结果 `shouldBypassModel: true` 由聊天层直接展示。
    private func execute(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        switch invocation.name {
        case "tool_list":
            return ToolExecutionResult(
                toolName: "tool_list",
                outputText: "已接入工具（\(SparkToolName.all.count)）：\n\(SparkToolName.all.joined(separator: "\n"))",
                sensitive: false,
                shouldBypassModel: true
            )

        case SparkToolName.fetchStepDetails:
            return await runFetchSteps(context: context)
        case SparkToolName.fetchSleepDetails:
            return await runFetchSleep(context: context)
        case SparkToolName.fetchEnergyDetails,
             SparkToolName.fetchNutritionDetails,
             SparkToolName.fetchWorkoutDetails,
             SparkToolName.makeNutritionData:
            return placeholder(
                tool: invocation.name,
                text: "当前仓库尚无该类原始数据源，工具入口已接通。"
            )

        case SparkToolName.searchKnowledgeBag:
            return await runSearchKnowledgeBag(invocation: invocation)
        case SparkToolName.createKnowledgeDocument:
            return await runCreateKnowledgeDocument(invocation: invocation)

        case SparkToolName.saveMemory:
            return await runSaveMemory(invocation: invocation)
        case SparkToolName.retrieveMemory:
            return await runRetrieveMemory(invocation: invocation)
        case SparkToolName.updateMemory:
            return await runUpdateMemory(invocation: invocation)

        case SparkToolName.getCurrentMember:
            return await runGetCurrentMember(context: context)
        case SparkToolName.switchMember, SparkToolName.findMember:
            return await runFindMember(invocation: invocation)
        case SparkToolName.queryMemberProfile:
            return await runQueryMemberProfile(invocation: invocation, context: context)

        case SparkToolName.generateStructuredHealthCard:
            return await runGenerateStructuredHealthCard(invocation: invocation, context: context)
        case SparkToolName.generateChatTitle:
            return runGenerateChatTitle(invocation: invocation)

        case SparkToolName.createCanvas:
            return runCreateCanvas(invocation: invocation)
        case SparkToolName.editCanvas:
            return runEditCanvas(invocation: invocation)

        case SparkToolName.showCustomMessageCard:
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "已展示上传/拍照卡片入口，请继续引导用户上传材料。",
                sensitive: false,
                shouldBypassModel: true
            )

        case SparkToolName.searchOnline,
             SparkToolName.readWebPage,
             SparkToolName.searchArxivPapers,
             SparkToolName.extractRemoteFileContent,
             SparkToolName.queryLocation,
             SparkToolName.getCurrentLocation,
             SparkToolName.searchNearbyLocations,
             SparkToolName.getRoute,
             SparkToolName.queryWeather,
             SparkToolName.searchCalendarAndReminders,
             SparkToolName.writeSystemEvent:
            return await runExternalConnectorTool(invocation: invocation)

        default:
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "未识别工具：\(invocation.name)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 从健康指标仓库汇总最近步数记录。
    private func runFetchSteps(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let patientID = context.patientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: "未选择成员，无法查询步数。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let metrics = try await healthMetricsRepository.fetchRecentMetrics(for: patientID, limit: 100)
            let steps = metrics.filter { $0.type == .steps }
            if steps.isEmpty {
                return ToolExecutionResult(
                    toolName: SparkToolName.fetchStepDetails,
                    outputText: "暂无步数数据。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            let total = steps.reduce(0.0) { $0 + $1.value }
            let avg = total / Double(steps.count)
            let output = "最近\(steps.count)条步数记录，总计\(Int(total))步，均值\(Int(avg))步。"
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: output,
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: "步数查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 从健康指标仓库汇总最近睡眠时长记录。
    private func runFetchSleep(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let patientID = context.patientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "未选择成员，无法查询睡眠。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let metrics = try await healthMetricsRepository.fetchRecentMetrics(for: patientID, limit: 60)
            let sleep = metrics.filter { $0.type == .sleep }
            if sleep.isEmpty {
                return ToolExecutionResult(
                    toolName: SparkToolName.fetchSleepDetails,
                    outputText: "暂无睡眠数据。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            let avg = sleep.reduce(0.0) { $0 + $1.value } / Double(sleep.count)
            let output = "最近\(sleep.count)条睡眠记录，平均睡眠\(String(format: "%.1f", avg))小时。"
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: output,
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "睡眠查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 在本地 AI 设置快照的 `promptRepo` 中按标题/正文模糊搜索知识片段。
    private func runSearchKnowledgeBag(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = invocation.arguments["query"] ?? invocation.arguments["content"] ?? ""
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let records = snapshot.promptRepo.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
        }

        if records.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: "知识库未匹配到相关文档。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = records.prefix(5).map { "- \($0.title)：\(String($0.content.prefix(120)))" }
        return ToolExecutionResult(
            toolName: SparkToolName.searchKnowledgeBag,
            outputText: lines.joined(separator: "\n"),
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 向 `promptRepo` 追加一条用户知识文档并持久化。
    private func runCreateKnowledgeDocument(invocation: ToolInvocation) async -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "未命名文档").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档创建失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        var snapshot = await aiSettingsRepository.loadSnapshot()
        snapshot.promptRepo.append(
            PromptRepo(title: title.isEmpty ? "未命名文档" : title, content: content, isSystem: false, timestamp: Date())
        )

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档已创建：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档保存失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 将内容追加到 `memoryArchive` 并保存。
    private func runSaveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        var snapshot = await aiSettingsRepository.loadSnapshot()
        let title = String(content.prefix(20))
        snapshot.memoryArchive.append(
            MemoryArchive(title: title.isEmpty ? "新记忆" : title, content: content, pinned: false, timestamp: Date())
        )

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆已保存：\(title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 无 query 时取最近几条记忆；有 query 时在 `memoryArchive` 中筛选。
    private func runRetrieveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let hits: [MemoryArchive]
        if query.isEmpty {
            hits = Array(snapshot.memoryArchive.suffix(5))
        } else {
            hits = snapshot.memoryArchive.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
            }
        }

        if hits.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: "未检索到相关记忆。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = hits.suffix(5).map { "- \($0.title)：\(String($0.content.prefix(100)))" }
        return ToolExecutionResult(
            toolName: SparkToolName.retrieveMemory,
            outputText: lines.joined(separator: "\n"),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 按原文或标题匹配一条记忆并替换正文、更新时间。
    private func runUpdateMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let original = (invocation.arguments["originalContent"] ?? invocation.arguments["original"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = (invocation.arguments["updatedContent"] ?? invocation.arguments["updated"] ?? invocation.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard original.isEmpty == false, updated.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：需要 originalContent 与 updatedContent。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        var snapshot = await aiSettingsRepository.loadSnapshot()
        guard let index = snapshot.memoryArchive.firstIndex(where: { $0.content == original || $0.title == original }) else {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：未找到原始内容。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        snapshot.memoryArchive[index].content = updated
        snapshot.memoryArchive[index].timestamp = Date()

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆已更新：\(snapshot.memoryArchive[index].title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 根据上下文 `patientID` 在医疗数据中解析当前成员简介。
    private func runGetCurrentMember(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let patientID = context.patientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前未选择成员。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let snapshot = await medicalDataRepository.loadSnapshot()
        guard let member = snapshot.members.first(where: { $0.id == patientID }) else {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前成员不存在或未同步。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let output = "当前成员：\(member.name)，关系：\(member.relationship)，年龄：\(member.age)。"
        return ToolExecutionResult(
            toolName: SparkToolName.getCurrentMember,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 按名称模糊筛选成员列表（`switchMember` / `findMember` 共用）。
    private func runFindMember(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = await medicalDataRepository.loadSnapshot()
        let members: [Member]
        if query.isEmpty {
            members = snapshot.members
        } else {
            members = snapshot.members.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        if members.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.findMember,
                outputText: "未找到匹配成员。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = members.prefix(8).map { "- \($0.name)（关系：\($0.relationship)）" }
        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: lines.joined(separator: "\n"),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 汇总指定或当前成员的病例/报告/处方等数量统计。
    private func runQueryMemberProfile(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let snapshot = await medicalDataRepository.loadSnapshot()
        let targetMemberID: UUID? = {
            if let value = invocation.arguments["member_id"], let id = UUID(uuidString: value) {
                return id
            }
            return context.patientID
        }()

        guard let memberID = targetMemberID,
              let member = snapshot.members.first(where: { $0.id == memberID }) else {
            return ToolExecutionResult(
                toolName: SparkToolName.queryMemberProfile,
                outputText: "未找到成员档案。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let caseCount = snapshot.medicalCases.filter { $0.memberID == memberID }.count
        let examCount = snapshot.examinationReports.filter { $0.memberID == memberID }.count
        let reportCount = snapshot.medicalReports.filter { $0.memberID == memberID }.count
        let prescriptionCount = snapshot.prescriptions.filter { $0.memberID == memberID }.count

        let output = """
        成员：\(member.name)
        年龄：\(member.age)
        关系：\(member.relationship)
        病例数：\(caseCount)
        检查报告数：\(examCount)
        医疗报告数：\(reportCount)
        处方数：\(prescriptionCount)
        """

        return ToolExecutionResult(
            toolName: SparkToolName.queryMemberProfile,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 占位：根据 `raw_text` 等参数生成结构化健康卡片描述（未接真实结构化管线）。
    private func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let patientID = context.patientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: "未选择成员，无法生成结构化健康卡片。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let reportType = (invocation.arguments["report_type"] ?? "medical_case").lowercased()
        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: "生成失败：raw_text 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let title = "\(reportType)_\(Date().formatted(date: .abbreviated, time: .omitted))"
        let summary = String(rawText.prefix(120))
        let output = "已生成结构化卡片：type=\(reportType), title=\(title), member=\(patientID.uuidString.prefix(8))..., summary=\(summary)"

        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 从参数截取短标题（最多 18 字）作为会话标题建议。
    private func runGenerateChatTitle(invocation: ToolInvocation) -> ToolExecutionResult {
        let source = invocation.arguments["content"] ?? invocation.arguments["query"] ?? "新对话"
        let title = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        return ToolExecutionResult(
            toolName: SparkToolName.generateChatTitle,
            outputText: title.isEmpty ? "新对话" : title,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 在内存 `canvasStore` 中新建画布条目。
    private func runCreateCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = invocation.arguments["content"] ?? ""
        canvasStore[title] = content
        return ToolExecutionResult(
            toolName: SparkToolName.createCanvas,
            outputText: "画布已创建：\(title)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 更新已存在画布的正文。
    private func runEditCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = invocation.arguments["content"] ?? ""
        guard canvasStore[title] != nil else {
            return ToolExecutionResult(
                toolName: SparkToolName.editCanvas,
                outputText: "画布不存在：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
        canvasStore[title] = content
        return ToolExecutionResult(
            toolName: SparkToolName.editCanvas,
            outputText: "画布已更新：\(title)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 联网/地图/日历等外部工具：根据 `toolKeys` 解析 endpoint，当前仅返回路由占位说明。
    private func runExternalConnectorTool(invocation: ToolInvocation) async -> ToolExecutionResult {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let endpoint = resolveEndpoint(for: invocation.name, toolKeys: snapshot.toolKeys)
        let payloadSummary = invocation.arguments
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        let output = """
        工具 \(invocation.name) 已接入 SparkClient 路由。
        endpoint=\(endpoint ?? "未配置")
        args=\(payloadSummary.isEmpty ? "<empty>" : payloadSummary)
        当前为本地执行占位；如需真实联网调用，请在对应 toolClass 网关实现 HTTP 适配。
        """

        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 将工具名映射到配置里的 `toolClass`（weather/map/calendar/code/tool），再取可用 `requestURL`。
    private func resolveEndpoint(for toolName: String, toolKeys: [ToolKeys]) -> String? {
        let toolClass: String
        switch toolName {
        case SparkToolName.queryWeather:
            toolClass = "weather"
        case SparkToolName.queryLocation,
             SparkToolName.getCurrentLocation,
             SparkToolName.searchNearbyLocations,
             SparkToolName.getRoute:
            toolClass = "map"
        case SparkToolName.searchCalendarAndReminders,
             SparkToolName.writeSystemEvent:
            toolClass = "calendar"
        case SparkToolName.searchArxivPapers:
            toolClass = "code"
        default:
            toolClass = "tool"
        }

        return toolKeys.first(where: { $0.toolClass == toolClass && $0.isUsing })?.requestURL
            ?? toolKeys.first(where: { $0.toolClass == toolClass })?.requestURL
    }

    /// 数据源未接时的统一占位返回。
    private func placeholder(tool: String, text: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: tool,
            outputText: "[\(tool)] \(text)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 将本次工具调用写入审计存储，并按输出是否含「失败」粗判状态。
    private func appendAudit(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async {
        let status: ToolAuditStatus = result.outputText.localizedCaseInsensitiveContains("失败") ? .failed : .success
        await auditStore.append(
            ToolAuditEvent(
                toolName: invocation.name,
                patientID: context.patientID,
                inputSummary: String(invocation.arguments.description.prefix(200)),
                outputSummary: String(result.outputText.prefix(200)),
                status: status
            )
        )
        logger.info(
            "工具执行完成，tool=\(invocation.name), status=\(status.rawValue), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive)",
            category: "tool_hub"
        )
    }

    private func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }
}
