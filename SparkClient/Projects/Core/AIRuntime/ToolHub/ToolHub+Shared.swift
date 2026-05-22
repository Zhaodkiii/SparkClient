import Foundation

// MARK: - ToolHub shared helpers (parsing, member resolution, rich merge, tasks)

extension ToolHub {
    func resolveHealthRange(arguments: [String: String], fallbackDays: Int = 0) -> (start: Date, end: Date) {
        let now = Date()
        let end = min(parseDate(arguments["end_date"]) ?? now, now)
        let start = parseDate(arguments["start_date"])
            ?? Calendar.current.date(byAdding: .day, value: -fallbackDays, to: end)
            ?? end
        if start > end {
            return (end, end)
        }
        return (start, end)
    }


    func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = Calendar.current.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: value)
    }

    func healthNoDataDiagnosticIfNeeded(
        _ output: String,
        range: (start: Date, end: Date)
    ) -> String {
        let noMatching = L10n.text("health.tool.error.no_matching_health")
        let noWorkouts = L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found.")
        guard output == noMatching || output == noWorkouts else {
            return output
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return """
        \(output)
        查询区间：\(formatter.string(from: range.start)) 至 \(formatter.string(from: range.end))。
        可能原因：HealthKit 在该区间没有样本、未授权读取步数/能量/运动数据，或当前设备/模拟器没有 Apple 健康数据。
        """
    }


    func parseDoubleValue(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }


    func parseStringList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

//    func buildSleepModel(from startDate: Date, to endDate: Date) -> ChatHealthSleepModel {
//        let calendar = Calendar.current
//        let dayStart = calendar.startOfDay(for: startDate)
//        let dayEnd = calendar.startOfDay(for: endDate)
//        let daysCount = max(1, (calendar.dateComponents([.day], from: dayStart, to: dayEnd).day ?? 0) + 1)
//        let formatter = DateFormatter()
//        formatter.locale = Locale(identifier: "en_US_POSIX")
//        formatter.timeZone = calendar.timeZone
//        formatter.dateFormat = "yyyy-MM-dd"
//
//        var days: [ChatHealthSleepModel.Day] = []
//        for offset in 0..<min(daysCount, 7) {
//            guard let baseDay = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
//            guard let sleepStart = calendar.date(bySettingHour: 23, minute: 10, second: 0, of: baseDay),
//                  let sleepEnd = calendar.date(byAdding: .hour, value: 7, to: sleepStart)
//            else { continue }
//
//            let total = Int(sleepEnd.timeIntervalSince(sleepStart) / 60)
//            let deep = Int(Double(total) * 0.22)
//            let rem = Int(Double(total) * 0.19)
//            let awake = 24
//            let core = max(0, total - deep - rem - awake)
//
//            let timeline = buildSleepTimeline(
//                sleepStart: sleepStart,
//                totalMinutes: total,
//                deepMinutes: deep,
//                coreMinutes: core,
//                remMinutes: rem,
//                awakeMinutes: awake
//            )
//
//            let summary = ChatHealthSleepModel.Summary(
//                totalSleepMinutes: total,
//                start: Int64(sleepStart.timeIntervalSince1970),
//                end: Int64(sleepEnd.timeIntervalSince1970),
//                startText: nil,
//                endText: nil
//            )
//            let stages = ChatHealthSleepModel.StageBreakdown(
//                deep: deep,
//                core: core,
//                rem: rem,
//                awake: awake,
//                unspecified: 0
//            )
//            days.append(
//                ChatHealthSleepModel.Day(
//                    date: formatter.string(from: baseDay),
//                    summary: summary,
//                    timeline: timeline,
//                    stages: stages
//                )
//            )
//        }
//
//        return ChatHealthSleepModel(
//            generatedAt: Int64(Date().timeIntervalSince1970),
//            days: days
//        )
//    }

//    func buildSleepTimeline(
//        sleepStart: Date,
//        totalMinutes: Int,
//        deepMinutes: Int,
//        coreMinutes: Int,
//        remMinutes: Int,
//        awakeMinutes: Int
//    ) -> [ChatHealthSleepModel.Segment] {
//        let blocks: [(ChatHealthSleepModel.Stage, Int)] = [
//            (.core, Int(Double(coreMinutes) * 0.45)),
//            (.deep, Int(Double(deepMinutes) * 0.5)),
//            (.core, Int(Double(coreMinutes) * 0.35)),
//            (.rem, Int(Double(remMinutes) * 0.6)),
//            (.awake, awakeMinutes),
//            (.core, max(0, coreMinutes - Int(Double(coreMinutes) * 0.8))),
//            (.deep, max(0, deepMinutes - Int(Double(deepMinutes) * 0.5))),
//            (.rem, max(0, remMinutes - Int(Double(remMinutes) * 0.6)))
//        ].filter { $0.1 > 0 }
//
//        var cursor = Int64(sleepStart.timeIntervalSince1970)
//        let totalSeconds = max(1, totalMinutes * 60)
//        var segments: [ChatHealthSleepModel.Segment] = []
//        for (stage, minute) in blocks {
//            let duration = Int64(minute * 60)
//            let start = cursor
//            let end = cursor + duration
//            let startPercent = Double(start - Int64(sleepStart.timeIntervalSince1970)) / Double(totalSeconds)
//            let widthPercent = Double(duration) / Double(totalSeconds)
//            segments.append(
//                ChatHealthSleepModel.Segment(
//                    stage: stage,
//                    start: start,
//                    end: end,
//                    startPercent: max(0, startPercent),
//                    widthPercent: max(0, widthPercent),
//                    startText: nil,
//                    endText: nil
//                )
//            )
//            cursor = end
//        }
//        return segments
//    }

    /// 在本地知识库中按标题、正文和切块检索知识片段；知识卡预览由协调器异步写入，不经 `ChatToolEventInterpreter`。

    func memberSelectionCompletedResult(toolName: String, memberID: Int) -> ToolExecutionResult {
        let output = [
            td("tool.result.request_member_selection.completed"),
            #"{"selection_completed":true,"member_id":\#(memberID),"instruction":"continue_conversation"}"#
        ].joined(separator: "\n")
        return ToolExecutionResult(
            toolName: toolName,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true,
            resolvedMemberID: memberID
        )
    }

    /// 会话或参数已能解析 member_id 时短路，不弹成员选择 Sheet。
    func memberSelectionAlreadyResolvedResult(memberID: Int) -> ToolExecutionResult {
        let output = [
            "【系统】成员已绑定，无需再次选择。",
            #"{"selection_completed":true,"member_id":\#(memberID),"already_resolved":true,"instruction":"continue_conversation"}"#
        ].joined(separator: "\n")
        return ToolExecutionResult(
            toolName: SparkToolName.requestMemberSelection.rawValue,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true,
            resolvedMemberID: memberID
        )
    }


    func memberSelectionTimeoutResult(toolName: String) -> ToolExecutionResult {
        let output = [
            td("tool.result.request_member_selection.timeout"),
            #"{"selection_completed":false,"reason":"user_not_selected","instruction":"continue_without_member_or_ask_again"}"#
        ].joined(separator: "\n")
        return ToolExecutionResult(
            toolName: toolName,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 按名称与/或关系模糊筛选成员（与 HealthClient `find_member` 参数对齐）。

    func parseQuestionItems(arguments: [String: String]) -> [ToolQuestionItem] {
        if let raw = arguments["questions"],
           let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return Array(array.prefix(5)).enumerated().compactMap { index, object in
                let question = (object["question"] as? String ?? object["title"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rawOptions = object["options"] as? [String] ?? []
                let selectionMode = ChatQuestionSelectionMode(
                    rawValue: (object["selection_mode"] as? String ?? "single").lowercased()
                ) ?? .single
                let allowsOther = object["allows_other"] as? Bool ?? false
                return makeQuestionItem(
                    index: index,
                    question: question,
                    rawOptions: rawOptions,
                    selectionMode: selectionMode,
                    allowsOther: allowsOther
                )
            }
        }

        let question = (arguments["question"] ?? arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectionMode = ChatQuestionSelectionMode(
            rawValue: (arguments["selection_mode"] ?? "single")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .single
        return makeQuestionItem(
            index: 0,
            question: question,
            rawOptions: parseStringList(arguments["options"]),
            selectionMode: selectionMode,
            allowsOther: parseBool(arguments["allows_other"], defaultValue: false)
        ).map { [$0] } ?? []
    }


    func makeQuestionItem(
        index: Int,
        question: String,
        rawOptions: [String],
        selectionMode: ChatQuestionSelectionMode,
        allowsOther: Bool
    ) -> ToolQuestionItem? {
        guard question.isEmpty == false, (2...5).contains(rawOptions.count) else { return nil }
        let questionID = "q\(index + 1)"
        let options = Array(rawOptions.prefix(5)).enumerated().map { optionIndex, text in
            ChatQuestionOption(id: "\(questionID)_option_\(optionIndex + 1)", text: text)
        }
        return ToolQuestionItem(
            id: questionID,
            question: question,
            options: options,
            allowsOther: allowsOther,
            selectionMode: selectionMode
        )
    }


    func formatQuestionAnswerText(
        questions: [ToolQuestionItem],
        responses: [ToolQuestionResponse]
    ) -> String {
        var lines = [td("tool.result.ask_user_question.submitted")]
        for (index, question) in questions.enumerated() {
            let response = responses.first { $0.questionID == question.id }
            let selectedIDs = Set(response?.selectedOptionIDs ?? [])
            let selectedTexts = question.options
                .filter { selectedIDs.contains($0.id) }
                .map(\.text)
            let otherText = response?.otherText?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            lines.append(toolFormat("tool.result.ask_user_question.item", index + 1, question.question))
            if selectedTexts.isEmpty {
                lines.append(td("tool.result.ask_user_question.no_fixed_selection"))
            } else {
                lines.append(toolFormat(
                    "tool.result.ask_user_question.selected",
                    selectedTexts.joined(separator: td("tool.result.separator.list"))
                ))
            }
            if let otherText, otherText.isEmpty == false {
                lines.append(toolFormat("tool.result.ask_user_question.other", otherText))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 任务查询工具：按成员维度返回主任务与子任务信息，供后续任务生成去重。

    func formatTaskQueryText(memberID: Int, tasks: [HealthTask], queriedAt: Date) -> String {
        var lines = [
            toolFormat("tool.result.query_tasks_by_member.header", memberID),
            toolFormat("tool.result.query_tasks_by_member.queried_at", iso8601(queriedAt)),
            toolFormat("tool.result.query_tasks_by_member.total", tasks.count)
        ]
        guard tasks.isEmpty == false else {
            lines.append(td("tool.result.query_tasks_by_member.empty"))
            return lines.joined(separator: "\n")
        }

        lines.append(td("tool.result.query_tasks_by_member.list_title"))
        for (index, task) in tasks.enumerated() {
            lines.append(toolFormat("tool.result.query_tasks_by_member.task_item", index + 1, task.title))
            lines.append(toolFormat(
                "tool.result.query_tasks_by_member.task_meta",
                taskTypeText(task.type),
                taskStatusText(task.status),
                taskRepeatText(task.repeatType),
                taskPriorityText(task.priority)
            ))
            if let startTime = task.startTime {
                lines.append(toolFormat("tool.result.query_tasks_by_member.start_time", iso8601(startTime)))
            }
            if let dueTime = task.dueTime {
                lines.append(toolFormat("tool.result.query_tasks_by_member.due_time", iso8601(dueTime)))
            }
            let description = compactText(task.description)
            if description.isEmpty == false {
                lines.append(toolFormat("tool.result.query_tasks_by_member.description", description))
            }
            lines.append(toolFormat("tool.result.query_tasks_by_member.updated_at", iso8601(task.updatedAt)))
        }
        return lines.joined(separator: "\n")
    }

    /// 任务生成工具：先查询任务，再执行抽取与相似度判断；成功时在消息内异步合并任务卡 block，向模型只返回简短可读说明。

    func extractTaskIntent(from input: String) async -> TaskIntentExtraction {
        let prompt = PromptLocalizer(locale: .current).taskExtractionPrompt(userInput: input)
        do {
            let stream = try await runtimeService.generateTextStream(
                request: AIRuntimeTextRequest(
                    scenario: .medicalStructuredExtraction,
                    messages: [AIRuntimeMessage(role: .user, content: prompt)],
                    reasoning: .disabled
                )
            )
            let raw = try await collectStreamText(from: stream)
            let normalizer = MedicalDocumentModelJSONNormalizer()
            let normalized = normalizer.normalizedModelJSONText(raw)
            if let data = normalized.data(using: .utf8),
               let decoded = try? JSONDecoder.default.decode(TaskIntentExtraction.self, from: data) {
                return decoded.normalized()
            }
        } catch {
            logger.warning("任务抽取模型失败，降级到规则抽取", module: .aiConfig)
        }
        return TaskIntentExtraction.ruleBased(from: input)
    }


    func collectStreamText(from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>) async throws -> String {
        var text = ""
        var completedText = ""
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text.append(delta)
            case .completed(let response):
                completedText = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }
        return text.isEmpty ? completedText : text
    }


    func findSimilarTasks(existing: [HealthTask], extracted: TaskIntentExtraction) -> [HealthTask] {
        let type = mapTaskType(extracted.taskType)
        let target = extracted.targetMetric.lowercased()
        let action = extracted.action.lowercased()
        return existing.filter { task in
            guard task.type == type, task.status == .pending else { return false }
            let titleText = task.title.lowercased()
            let descText = task.description.lowercased()
            let targetHit = target.isEmpty == false && (titleText.contains(target) || descText.contains(target))
            let actionHit = action.isEmpty == false && (titleText.contains(action) || descText.contains(action))
            let repeatHit = extracted.timeInfo.period.isEmpty == false && mapRepeatType(period: extracted.timeInfo.period, frequency: extracted.timeInfo.frequency) == task.repeatType
            return targetHit || actionHit || repeatHit
        }
    }


    func makeTaskTitle(extracted: TaskIntentExtraction, type: HealthTask.TaskType) -> String {
        if extracted.targetMetric.isEmpty == false {
            return extracted.targetMetric
        }
        switch type {
        case .medical: return "健康指标任务"
        case .exercise: return "运动任务"
        case .diet: return "饮食任务"
        }
    }


    func makeTaskDescription(extracted: TaskIntentExtraction, type: HealthTask.TaskType) -> String {
        let action = extracted.action.isEmpty ? defaultAction(for: type) : extracted.action
        let metric = extracted.targetMetric.isEmpty ? defaultMetric(for: type) : extracted.targetMetric
        let intensity = extracted.intensityOrValue.isEmpty ? defaultIntensity(for: type) : extracted.intensityOrValue
        let frequency = extracted.timeInfo.frequency.isEmpty ? defaultFrequency(for: type) : extracted.timeInfo.frequency
        return "目标：\(metric)\n动作：\(action)\n计划：\(frequency)\n强度：\(intensity)"
    }


    func defaultMetric(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "健康指标稳定"
        case .exercise: return "活动量提升"
        case .diet: return "饮食控制"
        }
    }


    func defaultAction(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "定时监测"
        case .exercise: return "中等强度运动"
        case .diet: return "控制高糖高脂摄入"
        }
    }


    func defaultIntensity(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "每天 2 次"
        case .exercise: return "30 分钟"
        case .diet: return "每日热量控制"
        }
    }


    func defaultFrequency(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical, .exercise, .diet:
            return "daily"
        }
    }


    func resolveDueDate(startAt: Date, repeatType: HealthTask.RepeatType) -> Date? {
        switch repeatType {
        case .none:
            return Calendar.current.date(byAdding: .day, value: 1, to: startAt)
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: startAt)
        case .weekly:
            return Calendar.current.date(byAdding: .day, value: 7, to: startAt)
        }
    }


    func mapTaskType(_ value: String) -> HealthTask.TaskType {
        switch value.lowercased() {
        case "medical": return .medical
        case "exercise": return .exercise
        case "diet": return .diet
        default: return .medical
        }
    }


    func mapRepeatType(period: String, frequency: String) -> HealthTask.RepeatType {
        let p = period.lowercased()
        let f = frequency.lowercased()
        if p.contains("week") || f.contains("每周") || f.contains("weekly") {
            return .weekly
        }
        if p.contains("day") || f.contains("每天") || f.contains("daily") {
            return .daily
        }
        return .none
    }


    func taskTypeText(_ type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return td("tool.result.task.type.medical")
        case .exercise: return td("tool.result.task.type.exercise")
        case .diet: return td("tool.result.task.type.diet")
        }
    }


    func taskStatusText(_ status: HealthTask.TaskStatus) -> String {
        switch status {
        case .pending: return td("tool.result.task.status.pending")
        case .completed: return td("tool.result.task.status.completed")
        case .canceled: return td("tool.result.task.status.canceled")
        }
    }


    func taskRepeatText(_ repeatType: HealthTask.RepeatType) -> String {
        switch repeatType {
        case .none: return td("tool.result.task.repeat.none")
        case .daily: return td("tool.result.task.repeat.daily")
        case .weekly: return td("tool.result.task.repeat.weekly")
        }
    }


    func taskPriorityText(_ priority: HealthTask.Priority) -> String {
        switch priority {
        case .high: return td("tool.result.task.priority.high")
        case .medium: return td("tool.result.task.priority.medium")
        case .low: return td("tool.result.task.priority.low")
        }
    }


    func compactText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: td("tool.result.separator.sentence"))
    }


    func buildTaskPayloadStrings(
        memberID: Int?,
        type: HealthTask.TaskType,
        extracted: TaskIntentExtraction,
        startAt: Date,
        dueAt: Date?,
        repeatType: HealthTask.RepeatType,
        priority: HealthTask.Priority
    ) -> [String: String] {
        var base: [String: Any] = [
            "creator_id": "current_user",
            "type": type.rawValue,
            "status": HealthTask.TaskStatus.pending.rawValue,
            "repeat_type": repeatType.rawValue,
            "priority": priority.rawValue,
            "source": HealthTask.Source.ai.rawValue,
            "start_time": iso8601(startAt),
            "due_time": dueAt.map(iso8601) ?? ""
        ]
        if let memberID {
            base["member_id"] = memberID
        }
        var payload: [String: String] = [
            "task": jsonString(from: base) ?? "{}"
        ]
        let reminder = reminderTimeString(from: extracted, fallback: startAt)
        switch type {
        case .medical:
            payload["task_medical"] = jsonString(from: [
                "medical_task_type": extracted.targetMetric.isEmpty ? "health_monitoring" : extracted.targetMetric,
                "description": extracted.action.isEmpty ? defaultAction(for: .medical) : extracted.action,
                "reminder_time": reminder
            ]) ?? "{}"
        case .exercise:
            let durationMin = parseIntValue(extracted.intensityOrValue) ?? 30
            payload["task_exercise"] = jsonString(from: [
                "exercise_type": extracted.action.isEmpty ? defaultAction(for: .exercise) : extracted.action,
                "duration_min": durationMin,
                "intensity": "medium",
                "description": extracted.targetMetric.isEmpty ? defaultMetric(for: .exercise) : extracted.targetMetric
            ]) ?? "{}"
        case .diet:
            let calorieTarget = parseIntValue(extracted.intensityOrValue) ?? 1800
            payload["task_diet"] = jsonString(from: [
                "meal_type": "dinner",
                "calorie_target": calorieTarget,
                "description": extracted.action.isEmpty ? defaultAction(for: .diet) : extracted.action,
                "food_recommend": extracted.targetMetric.isEmpty ? defaultMetric(for: .diet) : extracted.targetMetric,
                "reminder_time": reminder
            ]) ?? "{}"
        }
        return payload
    }


    func reminderTimeString(from extracted: TaskIntentExtraction, fallback: Date) -> String {
        if let parsed = parseISODate(extracted.timeInfo.startTime) {
            return iso8601Minute(parsed)
        }
        return iso8601Minute(fallback)
    }


    func parseIntValue(_ text: String) -> Int? {
        let pattern = #"[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return Int(text[range])
    }


    func jsonString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }


    func parseISODate(_ text: String) -> Date? {
        guard text.isEmpty == false else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }


    func parseBool(_ text: String?, defaultValue: Bool) -> Bool {
        guard let text else { return defaultValue }
        switch text.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return defaultValue
        }
    }


    func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }


    func iso8601Minute(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// 解析任务归属成员：优先显式 member_id，其次当前会话绑定成员；未绑定时不隐式结合任何成员。

    func resolveTargetMemberID(invocation: ToolInvocation, context: ToolExecutionContext) async -> Int? {
        if let value = invocation.arguments["member_id"], let explicit = Int(value) {
            return explicit
        }
        if let current = context.memberID {
            return current
        }
        if let threadID = context.threadID,
           let thread = await chatRepository.loadThread(id: threadID),
           let threadMemberID = thread.memberID,
           threadMemberID > 0 {
            return threadMemberID
        }
        return nil
    }


    func awaitMemberSelection(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        reason: String
    ) async -> Int? {
        guard let toolInteractionCoordinator else { return nil }
        var arguments = invocation.arguments
        if let memberID = context.memberID {
            arguments["member_id"] = String(memberID)
        }
        let prompt = ToolMemberSelectionPrompt(
            id: UUID(),
            toolName: invocation.name,
            reason: reason,
            arguments: arguments
        )
        switch await toolInteractionCoordinator.requestMemberSelection(threadID: context.threadID, prompt: prompt) {
        case .success(let memberID):
            return memberID
        case .cancelled, .conflict:
            return nil
        }
    }

    func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder.default
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return nil
    }

    /// 从参数截取短标题（最多 18 字）作为会话标题建议。

    func returnWithRichBlockSideEffects(
        context: ToolExecutionContext,
        result: ToolExecutionResult,
        richBlocks: [ChatMessageBlock]
    ) -> ToolExecutionResult {
        guard richBlocks.isEmpty == false,
              context.threadID != nil,
              context.assistantMessageClientID != nil
        else {
            return result
        }
        return ToolExecutionResult(
            toolName: result.toolName,
            outputText: result.outputText,
            sensitive: result.sensitive,
            shouldBypassModel: result.shouldBypassModel,
            isAwaitingUserInput: result.isAwaitingUserInput,
            resolvedMemberID: result.resolvedMemberID,
            toolCallID: result.toolCallID,
            anchorToolCallID: result.anchorToolCallID,
            arguments: result.arguments,
            sideEffects: result.sideEffects + [.externalConnectorRichBlocks(richBlocks)]
        )
    }

    /// 从 `ToolInvocation.arguments` 构建地图/日历/HTML 等富 UI blocks。

    func makeExternalConnectorRichBlocks(
        invocation: ToolInvocation,
        toolOutputForWebPreview: String,
        toolCallID: String?
    ) -> [ChatMessageBlock] {
        let a = invocation.arguments
        var blocks: [ChatMessageBlock] = []
        let l10n = AIPromptL10n(locale: .current)
        let locDefault = l10n.tool("tool.ui.rich.location.default_name", fallback: "Location")
        let eventDefault = l10n.tool("tool.ui.rich.event.default_title", fallback: "Event")

        if let tool = SparkToolName(rawValue: invocation.name) {
            switch tool {
            case .queryLocation, .getCurrentLocation, .searchNearbyLocations, .getRoute:
                if let lat = Double(a["latitude"] ?? ""),
                   let lon = Double(a["longitude"] ?? "") {
                    let loc = [
                        ChatMapLocationPayload(
                            name: a["keyword"] ?? a["query"] ?? locDefault,
                            latitude: lat,
                            longitude: lon
                        )
                    ]
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .mapRoute,
                            toolCallID: toolCallID,
                            locations: loc,
                            routes: []
                        )
                    )
                }
                if let sLat = Double(a["start.latitude"] ?? ""),
                   let sLng = Double(a["start.longitude"] ?? ""),
                   let eLat = Double(a["end.latitude"] ?? ""),
                   let eLng = Double(a["end.longitude"] ?? "") {
                    let loc = [
                        ChatMapLocationPayload(name: "Start", latitude: sLat, longitude: sLng),
                        ChatMapLocationPayload(name: "End", latitude: eLat, longitude: eLng)
                    ]
                    let routes = [ChatRoutePayload(
                        summary: "Route",
                        distance: a["distance"],
                        duration: a["duration"],
                        mode: a["mode"]
                    )]
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .mapRoute,
                            toolCallID: toolCallID,
                            locations: loc,
                            routes: routes
                        )
                    )
                }
            case .searchCalendarAndReminders, .writeSystemEvent:
                let events = [ChatEventPayload(
                    type: a["event_type"] ?? a["type"] ?? "calendar",
                    title: a["title"] ?? a["keyword"] ?? eventDefault,
                    dateText: a["start_date"] ?? a["due_date"] ?? a["end_date"],
                    location: a["location"],
                    notes: a["notes"]
                )]
                blocks.append(
                    ChatMessageBlock(
                        anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                        kind: .events,
                        toolCallID: toolCallID,
                        events: events
                    )
                )
            case .readWebPage:
                if toolOutputForWebPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .html,
                            text: toolOutputForWebPreview,
                            toolCallID: toolCallID
                        )
                    )
                }
            default:
                break
            }
        }

        return blocks
    }

    /// 将工具内 `TaskToolCardPayload` 与消息内 `TaskCard` 对齐（与 `block(from: .taskCards)` 解码路径一致）。

    func taskCardsFromToolCardPayload(_ cards: [TaskToolCardPayload]) -> [TaskCard]? {
        guard cards.isEmpty == false,
              let data = try? JSONEncoder.default.encode(cards),
              let raw = String(data: data, encoding: .utf8)?.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder.default
        decoder.dateDecodingStrategy = .iso8601
        guard let out = try? decoder.decode([TaskCard].self, from: raw), out.isEmpty == false else { return nil }
        return out
    }

    /// 联网/网页读取优先走本地搜索网关；地图/天气/日历等外部工具暂按 `toolKeys` 返回路由说明。

    func mergedBilingualSearchIfNeeded(
        primary: WebSearchResponse,
        query: String,
        config: SearchRuntimeConfig
    ) async throws -> WebSearchResponse {
        guard config.bilingualSearch else { return primary }
        let secondaryQuery: String
        do {
            secondaryQuery = try await translateSearchQueryForBilingualSearch(query)
        } catch {
            logger.warning("双语搜索翻译失败，使用原始搜索结果：\(error.localizedDescription)", module: .aiConfig)
            return primary
        }
        guard secondaryQuery.isEmpty == false, secondaryQuery.caseInsensitiveCompare(query) != .orderedSame else {
            return primary
        }
        let secondary = try await webSearchGateway.search(query: secondaryQuery, config: config)
        var seen = Set<String>()
        let mergedItems = (primary.items + secondary.items).filter { item in
            let key = normalizedSearchResultKey(item)
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
        return WebSearchResponse(
            providerName: primary.providerName,
            query: "\(primary.query) / \(secondary.query)",
            items: Array(mergedItems.prefix(max(config.searchCount, config.searchCount * 2))),
            totalEstimatedMatches: primary.totalEstimatedMatches ?? secondary.totalEstimatedMatches,
            revision: primary.revision
        )
    }


    func translateSearchQueryForBilingualSearch(_ query: String) async throws -> String {
        let prompt = """
        请直接翻译以下搜索查询，保留原意并适合用于搜索引擎。
        如果输入是中文，翻译为英文；如果输入是其他语言，翻译为中文。
        只输出翻译后的查询，不要解释，不要加引号。

        \(query)
        """
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: .optimizationText,
                messages: [
                    AIRuntimeMessage(
                        role: .system,
                        content: "You translate search queries for bilingual web search. Chinese queries must become English; non-Chinese queries must become Chinese. Return only the translated query."
                    ),
                    AIRuntimeMessage(role: .user, content: prompt)
                ],
                tools: [],
                toolChoice: .none,
                reasoning: .disabled,
                temperature: 0.2,
                maxTokens: 120
            )
        )
        return try await collectStreamText(from: stream)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`"))
    }


    func normalizedSearchResultKey(_ item: WebSearchResultItem) -> String {
        let raw = item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.title
            : item.url
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }


    func resolveEndpoint(for toolName: String, toolKeys: [ToolKeys]) -> String? {
        let toolClass: String
        guard let tool = SparkToolName(rawValue: toolName) else {
            toolClass = "tool"
            return toolKeys.first(where: { $0.toolClass == toolClass && $0.isUsing })?.requestURL
                ?? toolKeys.first(where: { $0.toolClass == toolClass })?.requestURL
        }

        switch tool {
        case .queryWeather:
            toolClass = "weather"
        case .queryLocation,
             .getCurrentLocation,
             .searchNearbyLocations,
             .getRoute:
            toolClass = "map"
        case .searchCalendarAndReminders,
             .writeSystemEvent:
            toolClass = "calendar"
        case .searchArxivPapers:
            toolClass = "code"
        default:
            toolClass = "tool"
        }

        return toolKeys.first(where: { $0.toolClass == toolClass && $0.isUsing })?.requestURL
            ?? toolKeys.first(where: { $0.toolClass == toolClass })?.requestURL
    }

    /// 数据源未接时的统一占位返回。

    func normalizedToolCallID(from context: ToolExecutionContext) -> String? {
        let trimmed = context.pendingToolCallID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}
