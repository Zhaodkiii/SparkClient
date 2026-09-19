import Foundation

extension ToolHub {
    /// 动态症状采集工具：字段、问题与选项由模型声明；会话状态与完成条件由客户端维护。
    func runCollectSymptoms(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let coordinator = toolInteractionCoordinator else {
            return ToolExecutionResult(
                toolName: SparkToolName.collectSymptoms,
                outputText: "【系统】当前界面无法展示症状采集卡，请继续用自然语言询问。",
                sensitive: true,
                shouldBypassModel: true
            )
        }

        let action = CollectSymptomsAction(rawValue: invocation.arguments["action"] ?? "start") ?? .start
        let incomingComplaint = nonEmpty(invocation.arguments["primary_complaint"])
        let incomingRequiredFields = decodeStringArray(invocation.arguments["required_fields"])
            .filter { isReviewArtifactField($0) == false }
        let providedSnapshot = decodeSnapshot(invocation.arguments["snapshot_json"])
        let storedSnapshot = await symptomCollectionSessionStore.activeSnapshot(threadID: context.threadID)

        var snapshot = initialSymptomSnapshot(
            action: action,
            stored: storedSnapshot,
            provided: providedSnapshot,
            requestedCollectionID: invocation.arguments["collection_id"],
            primaryComplaint: incomingComplaint
        )
        snapshot = removingReviewArtifacts(from: snapshot)
        snapshot.primaryComplaint = snapshot.primaryComplaint ?? incomingComplaint
        snapshot.requiredFields = stableUnion(snapshot.requiredFields, incomingRequiredFields)
        if let analysisSummary = nonEmpty(invocation.arguments["analysis_summary"]) {
            snapshot.analysisSummary = analysisSummary
        }

        let parsedQuestions = parseSymptomQuestions(invocation.arguments["questions"])
        snapshot.requiredFields = stableUnion(snapshot.requiredFields, parsedQuestions.compactMap(\.fieldKey))
        if snapshot.requiredFields.isEmpty {
            snapshot.requiredFields = ["symptom_details"]
        }

        // 模型偶尔会自行生成“请确认以上信息”的普通问题。确认是客户端
        // 可确定处理的状态转换，不能被模型自定义字段污染或卡在 reviewing。
        // 当资料已齐且本轮没有有效补充题时，直接展示固定 review 卡片。
        let isReviewAllowed = snapshot.isComplete && (action == .review || parsedQuestions.isEmpty)
        let finalQuestions: [ToolQuestionItem]
        if isReviewAllowed {
            snapshot.status = .reviewing
            finalQuestions = [reviewQuestion()]
        } else {
            snapshot.status = .collecting
            let missing = Set(missingFields(in: snapshot))
            let relevantQuestions = missing.isEmpty
                ? parsedQuestions
                : parsedQuestions.filter { question in
                    guard let fieldKey = nonEmpty(question.fieldKey) else { return true }
                    return missing.contains(fieldKey)
                }
            finalQuestions = relevantQuestions.isEmpty
                ? fallbackQuestions(for: Array(missing).sorted())
                : Array(relevantQuestions.prefix(1))
        }

        for question in finalQuestions where question.id != Self.symptomReviewQuestionID {
            guard let fieldKey = nonEmpty(question.fieldKey) else { continue }
            snapshot.fieldLabels[fieldKey] = symptomFieldLabel(
                question: question.question,
                fieldKey: fieldKey
            )
        }

        await symptomCollectionSessionStore.save(snapshot, threadID: context.threadID)
        let prompt = ToolQuestionPrompt(
            toolName: SparkToolName.collectSymptoms.rawValue,
            questions: finalQuestions,
            symptomCollectionID: snapshot.collectionID,
            symptomSnapshot: snapshot,
            isSymptomReview: isReviewAllowed
        )
        let answerResult = await coordinator.requestQuestionAnswer(
            threadID: context.threadID,
            prompt: prompt,
            toolCallID: context.pendingToolCallID
        )
        guard case .success(let answer) = answerResult else {
            snapshot.status = .cancelled
            snapshot.revision += 1
            await symptomCollectionSessionStore.save(snapshot, threadID: context.threadID)
            return ToolExecutionResult(
                toolName: SparkToolName.collectSymptoms,
                outputText: "【症状采集】用户取消了本轮采集，已保留未完成的症状卡片。",
                sensitive: true,
                shouldBypassModel: true,
                isAwaitingUserInput: true
            )
        }

        var addedAnswers: [String] = []
        for response in answer.responses {
            guard let question = finalQuestions.first(where: { $0.id == response.questionID }) else { continue }
            guard question.id != Self.symptomReviewQuestionID else { continue }
            let selected = question.options
                .filter { response.selectedOptionIDs.contains($0.id) }
                .map(\.text)
            let other = nonEmpty(response.otherText).map { String($0.prefix(200)) }
            let parts = selected + (other.map { [$0] } ?? [])
            guard parts.isEmpty == false else { continue }

            let fieldKey = question.fieldKey ?? question.id
            let value = parts.joined(separator: "、")
            snapshot.values[fieldKey] = value
            addedAnswers.append("\(fieldKey)：\(value)")
            if isAssociatedSymptomsField(fieldKey) {
                snapshot.associatedSymptoms = parts.filter { !isNoneAnswer($0) }
            }
        }

        let confirmed = isReviewAllowed && answer.responses.contains {
            $0.questionID == Self.symptomReviewQuestionID && $0.selectedOptionIDs.contains(Self.symptomReviewConfirmID)
        }
        let requestedEdit = isReviewAllowed && answer.responses.contains {
            $0.questionID == Self.symptomReviewQuestionID && $0.selectedOptionIDs.contains(Self.symptomReviewEditID)
        }
        snapshot.revision += 1
        if confirmed {
            snapshot.status = .completed
        } else if requestedEdit {
            snapshot.status = .collecting
        } else {
            snapshot.status = snapshot.isComplete ? .reviewing : .collecting
        }
        await symptomCollectionSessionStore.save(snapshot, threadID: context.threadID)

        let missing = missingFields(in: snapshot)
        let result = SymptomCollectionToolResult(
            action: action,
            collectionID: snapshot.collectionID,
            snapshot: snapshot,
            addedAnswers: addedAnswers,
            missingFields: missing,
            confirmed: confirmed,
            requiresContinuation: confirmed == false,
            nextAction: requestedEdit ? "ask" : (snapshot.isComplete ? "review" : "ask"),
            modelInstruction: confirmed
                ? "症状采集已由用户确认。立即结束本轮，不输出诊断、风险判断、建议、解释或任何普通文本。"
                : requestedEdit
                    ? "用户要求修改症状信息。必须调用 collect_symptoms(action: ask) 生成修改问题；禁止在普通文本中提问。"
                    : "症状采集尚未完成。必须立即再次调用 collect_symptoms，action 使用 next_action；禁止在普通文本中提问。"
        )
        let output = (try? String(data: JSONEncoder().encode(result), encoding: .utf8)) ?? "{}"
        return ToolExecutionResult(
            toolName: SparkToolName.collectSymptoms,
            outputText: output,
            sensitive: true,
            shouldBypassModel: false
        )
    }

    private static let symptomReviewQuestionID = "symptom_review"
    private static let symptomReviewConfirmID = "confirm"
    private static let symptomReviewEditID = "edit"

    private func initialSymptomSnapshot(
        action: CollectSymptomsAction,
        stored: SymptomCollectionSnapshot?,
        provided: SymptomCollectionSnapshot?,
        requestedCollectionID: String?,
        primaryComplaint: String?
    ) -> SymptomCollectionSnapshot {
        if action != .start, let stored {
            return mergingSymptomSnapshots(current: stored, incoming: provided)
        }
        if action == .start,
           let stored,
           stored.status != .completed,
           stored.status != .cancelled,
           stored.status != .expired,
           (primaryComplaint == nil || stored.primaryComplaint == primaryComplaint) {
            return mergingSymptomSnapshots(current: stored, incoming: provided)
        }
        if let provided { return provided }
        return SymptomCollectionSnapshot(
            collectionID: UUID(uuidString: requestedCollectionID ?? "") ?? UUID(),
            primaryComplaint: primaryComplaint
        )
    }

    private func mergingSymptomSnapshots(
        current: SymptomCollectionSnapshot,
        incoming: SymptomCollectionSnapshot?
    ) -> SymptomCollectionSnapshot {
        guard let incoming else { return current }
        var merged = removingReviewArtifacts(from: current)
        merged.primaryComplaint = merged.primaryComplaint ?? incoming.primaryComplaint
        merged.requiredFields = stableUnion(
            merged.requiredFields,
            incoming.requiredFields.filter { isReviewArtifactField($0) == false }
        )
        for (key, value) in incoming.values
        where isReviewArtifactField(key) == false && merged.values[key] == nil {
            merged.values[key] = value
        }
        for (key, value) in incoming.fieldLabels
        where isReviewArtifactField(key) == false && merged.fieldLabels[key] == nil {
            merged.fieldLabels[key] = value
        }
        if merged.associatedSymptoms.isEmpty {
            merged.associatedSymptoms = incoming.associatedSymptoms
        }
        merged.analysisSummary = incoming.analysisSummary ?? merged.analysisSummary
        return merged
    }

    private func decodeSnapshot(_ raw: String?) -> SymptomCollectionSnapshot? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SymptomCollectionSnapshot.self, from: data)
    }

    private func decodeStringArray(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return value.compactMap(nonEmpty)
    }

    private func parseSymptomQuestions(_ raw: String?) -> [ToolQuestionItem] {
        guard let raw, let data = raw.data(using: .utf8),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        // 协议只允许模型每轮生成一题。这里仍解析有限数量的候选项，
        // 便于在模型误返回多题且第一题已经完成时选中首个未完成字段；
        // 最终展示层始终只会取一题。
        let questions = objects.prefix(8).compactMap { object -> ToolQuestionItem? in
            let id = nonEmpty((object["id"] as? String) ?? (object["value"] as? String)) ?? UUID().uuidString
            guard let question = nonEmpty(object["question"] as? String) else { return nil }
            let fieldKey = nonEmpty(object["field_key"] as? String)
            // review / confirm 只能使用下方固定问题，避免被当作必填症状字段。
            guard isReviewArtifactField(fieldKey ?? id) == false,
                  isModelConfirmationQuestion(question) == false else { return nil }
            let options = normalizedOptions(object["options"]).prefix(8)
            guard options.count >= 2 else { return nil }
            let mode = ChatQuestionSelectionMode(rawValue: object["selection_mode"] as? String ?? "single") ?? .single
            return ToolQuestionItem(
                id: id,
                question: question,
                options: Array(options),
                allowsOther: object["allows_other"] as? Bool ?? true,
                selectionMode: mode,
                fieldKey: fieldKey
            )
        }
        if objects.isEmpty == false, questions.isEmpty {
            logger.warning("症状采集问题参数无法解析，将按缺失字段生成安全兜底问题。", module: .aiConfig)
        }
        return questions
    }

    private func normalizedOptions(_ raw: Any?) -> [ChatQuestionOption] {
        var labels: [(id: String?, text: String)] = []

        func collect(_ value: Any?) {
            switch value {
            case let text as String:
                if let text = nonEmpty(text) { labels.append((nil, text)) }
            case let object as [String: Any]:
                let explicitID = (object["id"] as? String) ?? (object["value"] as? String)
                let explicitText = (object["text"] as? String) ?? (object["label"] as? String)
                if let explicitText = nonEmpty(explicitText) {
                    labels.append((nonEmpty(explicitID), explicitText))
                } else {
                    for key in object.keys.sorted() {
                        collect(key)
                        collect(object[key])
                    }
                }
            case let array as [Any]:
                array.forEach(collect)
            default:
                break
            }
        }

        collect(raw)
        var seen = Set<String>()
        return labels.compactMap { candidate in
            let text = String(candidate.text.prefix(80))
            guard seen.insert(text).inserted else { return nil }
            let id = candidate.id ?? "option_\(seen.count)"
            return ChatQuestionOption(id: id, text: text)
        }
    }

    private func reviewQuestion() -> ToolQuestionItem {
        ToolQuestionItem(
            id: Self.symptomReviewQuestionID,
            question: "以上症状信息是否准确？确认后将结束本次采集。",
            options: [
                ChatQuestionOption(id: Self.symptomReviewConfirmID, text: "确认并完成"),
                ChatQuestionOption(id: Self.symptomReviewEditID, text: "返回修改")
            ],
            allowsOther: false,
            selectionMode: .single,
            fieldKey: "review_confirmation"
        )
    }

    private func fallbackQuestions(for missingFields: [String]) -> [ToolQuestionItem] {
        let fields = missingFields.isEmpty ? ["symptom_details"] : Array(missingFields.prefix(1))
        return fields.map { field in
            let descriptor = fallbackDescriptor(for: field)
            return ToolQuestionItem(
                id: "fallback_\(field)",
                question: descriptor.question,
                options: descriptor.options.enumerated().map {
                    ChatQuestionOption(id: "\(field)_\($0.offset)", text: $0.element)
                },
                allowsOther: true,
                selectionMode: descriptor.multiple ? .multiple : .single,
                fieldKey: field
            )
        }
    }

    private func fallbackDescriptor(for field: String) -> (question: String, options: [String], multiple: Bool) {
        let lower = field.lowercased()
        if lower.contains("onset") || lower.contains("start") || field.contains("起病") {
            return ("症状大约是什么时候开始的？", ["今天刚出现", "昨天开始", "已经好几天", "断断续续一段时间"], false)
        }
        if lower.contains("duration") || field.contains("持续") {
            return ("这次不适持续了多久？", ["不到1小时", "1至3小时", "超过3小时", "反复出现"], false)
        }
        if lower.contains("severity") || field.contains("程度") {
            return ("目前不适的严重程度如何？", ["轻微", "中度", "较重", "严重"], false)
        }
        if lower.contains("position") || lower.contains("posture") || field.contains("体位") {
            return ("不适是否与起身、躺下或转动身体有关？", ["起身时明显", "躺下时明显", "转动身体时明显", "没有明显关系"], false)
        }
        if isAssociatedSymptomsField(field) {
            return ("同时还有哪些相关不适？", ["恶心或呕吐", "心慌或胸闷", "视物模糊", "手脚麻木或无力", "以上都没有"], true)
        }
        return ("请补充这项症状信息。", ["有相关情况", "没有", "不确定"], false)
    }

    private func missingFields(in snapshot: SymptomCollectionSnapshot) -> [String] {
        snapshot.requiredFields.filter {
            snapshot.values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    private func stableUnion(_ current: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        return (current + incoming).compactMap { value in
            guard let value = nonEmpty(value), seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private func removingReviewArtifacts(from snapshot: SymptomCollectionSnapshot) -> SymptomCollectionSnapshot {
        var sanitized = snapshot
        let invalidKeys = Set(
            (sanitized.requiredFields + Array(sanitized.values.keys) + Array(sanitized.fieldLabels.keys))
                .filter(isReviewArtifactField)
        )
        sanitized.requiredFields.removeAll { invalidKeys.contains($0) }
        invalidKeys.forEach {
            sanitized.values.removeValue(forKey: $0)
            sanitized.fieldLabels.removeValue(forKey: $0)
        }
        return sanitized
    }

    private func isReviewArtifactField(_ field: String) -> Bool {
        let normalized = field.lowercased().replacingOccurrences(of: "_", with: "")
        return normalized.contains("confirm") || normalized.contains("review") || field.contains("确认")
    }

    private func isModelConfirmationQuestion(_ question: String) -> Bool {
        let normalized = question.replacingOccurrences(of: " ", with: "")
        return normalized.contains("确认") &&
            (normalized.contains("症状") || normalized.contains("信息") || normalized.contains("以上"))
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isAssociatedSymptomsField(_ field: String) -> Bool {
        let lower = field.lowercased()
        return lower.contains("accompan") || lower.contains("associated") || field.contains("伴随")
    }

    private func isNoneAnswer(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: " ", with: "")
        return normalized == "无" || normalized.contains("没有") || normalized.contains("以上都没有")
    }

    private func symptomFieldLabel(question: String, fieldKey: String) -> String {
        let lower = fieldKey.lowercased()
        if lower.contains("dizziness") && lower.contains("type") { return "头晕感觉" }
        if lower.contains("onset") || lower.contains("start") { return "开始时间" }
        if lower.contains("duration") { return "持续时间" }
        if lower.contains("severity") { return "严重程度" }
        if isAssociatedSymptomsField(fieldKey) { return "伴随症状" }
        if lower.contains("frequency") { return "发生频率" }
        if lower.contains("trigger") { return "诱发因素" }

        let cleaned = question
            .replacingOccurrences(of: "（可多选）", with: "")
            .replacingOccurrences(of: "(可多选)", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "？?。 "))
        return cleaned.isEmpty ? fieldKey.replacingOccurrences(of: "_", with: " ") : cleaned
    }
}

private struct SymptomCollectionToolResult: Codable, Sendable {
    let action: CollectSymptomsAction
    let collectionID: UUID
    let snapshot: SymptomCollectionSnapshot
    let addedAnswers: [String]
    let missingFields: [String]
    let confirmed: Bool
    let requiresContinuation: Bool
    let nextAction: String
    let modelInstruction: String
}
