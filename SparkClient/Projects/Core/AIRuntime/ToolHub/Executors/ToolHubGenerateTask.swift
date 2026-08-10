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
        let explicitTaskType = invocation.arguments["task_type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let businessType = (
            invocation.arguments["business_type"]
            ?? invocation.arguments["businessType"]
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let businessID = (
            invocation.arguments["business_id"]
            ?? invocation.arguments["businessID"]
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedTaskType = resolveRequestedTaskType(
            explicitTaskType: explicitTaskType,
            businessType: businessType,
            extracted: extracted
        )
        let similarTasks = findSimilarTasks(
            existing: existingTasks,
            extracted: extracted,
            taskTypeOverride: requestedTaskType,
            businessType: businessType,
            businessID: businessID
        )
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
        let taskType = requestedTaskType
        let startAt = parseISODate(extracted.timeInfo.startTime) ?? now
        let repeatType = mapRepeatType(period: extracted.timeInfo.period, frequency: extracted.timeInfo.frequency)
        let dueAt = resolveDueDate(startAt: startAt, repeatType: repeatType)
        let priority: HealthTask.Priority = .medium
        let resolvedTitle = nonEmptyTaskToolText(invocation.arguments["title"])
            ?? makeTaskTitle(extracted: extracted, type: taskType)
        let resolvedDescription = nonEmptyTaskToolText(invocation.arguments["description"])
            ?? makeTaskDescription(extracted: extracted, type: taskType)
        let resolvedBusinessType = businessType.isEmpty ? "ai_task_generation" : businessType
        let resolvedBusinessID = businessID

        let card = TaskToolCardPayload(
            id: -Int(now.timeIntervalSince1970),
            member: memberID,
            creator: nil,
            title: resolvedTitle,
            description: resolvedDescription,
            type: taskType.rawValue,
            startTime: iso8601(startAt),
            dueTime: dueAt.map(iso8601),
            repeatType: repeatType.rawValue,
            priority: priority.rawValue,
            businessType: resolvedBusinessType,
            businessID: resolvedBusinessID,
            source: HealthTask.Source.ai.rawValue,
            status: TaskCard.CardStatus.pending.rawValue,
            extractPayload: extracted.asStringMap(),
            taskPayload: buildTaskPayloadStrings(
                memberID: memberID,
                type: taskType,
                extracted: extracted,
                startAt: startAt,
                dueAt: dueAt,
                repeatType: repeatType,
                priority: priority,
                title: resolvedTitle,
                description: resolvedDescription,
                businessType: resolvedBusinessType,
                businessID: resolvedBusinessID
            ),
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
        let response = TaskGeneratedToolPayload(
            ok: true,
            action: "pending_confirm",
            queriedFirst: true,
            task: .init(
                title: resolvedTitle,
                type: taskType.rawValue,
                businessType: resolvedBusinessType,
                businessId: resolvedBusinessID
            )
        )
        var sideEffects: [ToolSideEffect] = []
        if taskCards.isEmpty == false,
           context.threadID != nil,
           context.assistantMessageClientID != nil {
            sideEffects = [.taskCards(taskCards)]
        }
        return ToolExecutionResult(
            toolName: SparkToolName.generateTask,
            outputText: encodeJSON(response) ?? #"{"ok":false,"error":"encode_failed"}"#,
            sensitive: true,
            shouldBypassModel: true,
            sideEffects: sideEffects
        )
    }

}

private struct TaskGeneratedToolPayload: Encodable {
    struct Task: Encodable {
        let title: String
        let type: Int
        let businessType: String
        let businessId: String
    }

    let ok: Bool
    let action: String
    let queriedFirst: Bool
    let task: Task
}

private func nonEmptyTaskToolText(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
}
