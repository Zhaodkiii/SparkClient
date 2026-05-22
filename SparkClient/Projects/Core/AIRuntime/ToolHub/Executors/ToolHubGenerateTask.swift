import Foundation

extension ToolHub {
    func runGenerateTask(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID = await resolveTargetMemberID(invocation: invocation, context: context)
        let userInput = (
            invocation.arguments["user_input"]
            ?? invocation.arguments["query"]
            ?? invocation.arguments["content"]
            ?? invocation.arguments["raw_text"]
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard userInput.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: #"{"ok":false,"error":"user_input_required"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        // 规则：生成前必须先查任务。这里在工具内部强制执行，确保流程不被模型跳过。
        let existingTasks: [HealthTask]
        if let memberID {
            do {
                existingTasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
            } catch {
                return ToolExecutionResult(
                    toolName: SparkToolName.generateTask,
                    outputText: #"{"ok":false,"error":"query_tasks_before_generate_failed"}"#,
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
        } else {
            existingTasks = []
        }

        let extracted = await extractTaskIntent(from: userInput)
        let similarTasks = findSimilarTasks(existing: existingTasks, extracted: extracted)
        if similarTasks.isEmpty == false {
            let response = TaskNoCreateToolPayload(
                ok: true,
                action: "no_create",
                reason: "similar_task_exists",
                queriedFirst: true,
                memberID: memberID,
                extracted: extracted,
                similarTasks: similarTasks.map {
                    TaskSimilarityItem(
                        taskID: $0.id,
                        title: $0.title,
                        type: $0.type.rawValue,
                        status: $0.status.rawValue,
                        updatedAt: iso8601($0.updatedAt)
                    )
                }
            )
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: encodeJSON(response) ?? #"{"ok":false,"error":"encode_failed"}"#,
                sensitive: true,
                shouldBypassModel: true
            )
        }

        let now = Date()
        let taskType = mapTaskType(extracted.taskType)
        let startAt = parseISODate(extracted.timeInfo.startTime) ?? now
        let repeatType = mapRepeatType(period: extracted.timeInfo.period, frequency: extracted.timeInfo.frequency)
        let dueAt = resolveDueDate(startAt: startAt, repeatType: repeatType)
        let priority: HealthTask.Priority = .medium

        let card = TaskToolCardPayload(
            id: -Int(now.timeIntervalSince1970),
            member: memberID,
            creator: nil,
            title: makeTaskTitle(extracted: extracted, type: taskType),
            description: makeTaskDescription(extracted: extracted, type: taskType),
            type: taskType.rawValue,
            startTime: iso8601(startAt),
            dueTime: dueAt.map(iso8601),
            repeatType: repeatType.rawValue,
            priority: priority.rawValue,
            businessType: "ai_task_generation",
            businessID: "",
            source: HealthTask.Source.ai.rawValue,
            status: TaskCard.CardStatus.pending.rawValue,
            extractPayload: extracted.asStringMap(),
            taskPayload: buildTaskPayloadStrings(memberID: memberID, type: taskType, extracted: extracted, startAt: startAt, dueAt: dueAt, repeatType: repeatType, priority: priority),
            similarityPayload: [
                "queried_first": "true",
                "similar_count": "0",
                "member_source": invocation.arguments["member_id"] == nil ? "thread_member_binding" : "explicit_member"
            ],
            ignoredReason: "",
            confirmedTask: nil,
            createdAt: iso8601(now),
            updatedAt: iso8601(now)
        )
        let taskCards = taskCardsFromToolCardPayload([card]) ?? []
        let titleLine = makeTaskTitle(extracted: extracted, type: taskType)
        let userFacing = "已根据描述生成 1 条待确认任务「\(titleLine)」。请在消息内任务卡片中确认或忽略。"
        var sideEffects: [ToolSideEffect] = []
        if taskCards.isEmpty == false,
           context.threadID != nil,
           context.assistantMessageClientID != nil {
            sideEffects = [.taskCards(taskCards)]
        }
        return ToolExecutionResult(
            toolName: SparkToolName.generateTask,
            outputText: userFacing,
            sensitive: true,
            shouldBypassModel: true,
            sideEffects: sideEffects
        )
    }

}
