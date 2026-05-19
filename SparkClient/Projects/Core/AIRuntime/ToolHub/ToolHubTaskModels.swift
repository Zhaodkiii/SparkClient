import Foundation

struct TaskQueryToolPayload: Encodable {
    let ok: Bool
    let memberID: Int
    let queriedAt: String
    let total: Int
    let tasks: [HealthTask]
}

struct ToolQuestionAnswerPayload: Encodable {
    let responses: [Response]

    init(questions: [ToolQuestionItem], responses: [ToolQuestionResponse]) {
        self.responses = questions.map { question in
            let response = responses.first(where: { $0.questionID == question.id })
            let selectedIDs = Set(response?.selectedOptionIDs ?? [])
            return Response(
                questionID: question.id,
                question: question.question,
                selectionMode: question.selectionMode.rawValue,
                selectedOptions: question.options.filter { selectedIDs.contains($0.id) },
                otherText: response?.otherText
            )
        }
    }

    struct Response: Encodable {
        let questionID: String
        let question: String
        let selectionMode: String
        let selectedOptions: [ChatQuestionOption]
        let otherText: String?
    }
}

struct TaskNoCreateToolPayload: Encodable {
    let ok: Bool
    let action: String
    let reason: String
    let queriedFirst: Bool
    let memberID: Int?
    let extracted: TaskIntentExtraction
    let similarTasks: [TaskSimilarityItem]
}

struct TaskSimilarityItem: Encodable {
    let taskID: Int
    let title: String
    let type: Int
    let status: Int
    let updatedAt: String
}

struct TaskToolCardPayload: Encodable {
    let id: Int
    let member: Int?
    let creator: Int?
    let title: String
    let description: String
    let type: Int
    let startTime: String?
    let dueTime: String?
    let repeatType: Int
    let priority: Int
    let businessType: String
    let businessID: String
    let source: Int
    let status: Int
    let extractPayload: [String: String]
    let taskPayload: [String: String]
    let similarityPayload: [String: String]
    let ignoredReason: String
    let confirmedTask: Int?
    let createdAt: String
    let updatedAt: String
}

struct TaskIntentExtraction: Codable {
    struct TimeInfo: Codable {
        let startTime: String
        let frequency: String
        let period: String

        init(startTime: String, frequency: String, period: String) {
            self.startTime = startTime
            self.frequency = frequency
            self.period = period
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodableKey.self)
            startTime = try c.decodeIfPresent(String.self, forKey: .key("startTime")) ?? ""
            frequency = try c.decodeIfPresent(String.self, forKey: .key("frequency")) ?? ""
            period = try c.decodeIfPresent(String.self, forKey: .key("period")) ?? ""
        }
    }

    let taskType: String
    let targetMetric: String
    let timeInfo: TimeInfo
    let action: String
    let intensityOrValue: String
    let confidence: Double

    init(
        taskType: String,
        targetMetric: String,
        timeInfo: TimeInfo,
        action: String,
        intensityOrValue: String,
        confidence: Double
    ) {
        self.taskType = taskType
        self.targetMetric = targetMetric
        self.timeInfo = timeInfo
        self.action = action
        self.intensityOrValue = intensityOrValue
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        taskType = try c.decodeIfPresent(String.self, forKey: .key("taskType")) ?? "unknown"
        targetMetric = try c.decodeIfPresent(String.self, forKey: .key("targetMetric")) ?? ""
        timeInfo = try c.decodeIfPresent(TimeInfo.self, forKey: .key("timeInfo")) ?? .init(startTime: "", frequency: "", period: "")
        action = try c.decodeIfPresent(String.self, forKey: .key("action")) ?? ""
        intensityOrValue = try c.decodeIfPresent(String.self, forKey: .key("intensityOrValue")) ?? ""
        confidence = try c.decodeIfPresent(Double.self, forKey: .key("confidence")) ?? 0
    }

    func normalized() -> TaskIntentExtraction {
        TaskIntentExtraction(
            taskType: taskType.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMetric: targetMetric.trimmingCharacters(in: .whitespacesAndNewlines),
            timeInfo: .init(
                startTime: timeInfo.startTime.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: timeInfo.frequency.trimmingCharacters(in: .whitespacesAndNewlines),
                period: timeInfo.period.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            action: action.trimmingCharacters(in: .whitespacesAndNewlines),
            intensityOrValue: intensityOrValue.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence
        )
    }

    func asStringMap() -> [String: String] {
        [
            "task_type": taskType,
            "target_metric": targetMetric,
            "start_time": timeInfo.startTime,
            "frequency": timeInfo.frequency,
            "period": timeInfo.period,
            "action": action,
            "intensity_or_value": intensityOrValue,
            "confidence": String(format: "%.2f", confidence)
        ]
    }

    static func ruleBased(from input: String) -> TaskIntentExtraction {
        let text = input.lowercased()
        let type: String
        if text.contains("血糖") || text.contains("血压") || text.contains("服药") || text.contains("复诊") {
            type = "medical"
        } else if text.contains("步") || text.contains("运动") || text.contains("跑步") || text.contains("walk") {
            type = "exercise"
        } else if text.contains("饮食") || text.contains("热量") || text.contains("减脂") || text.contains("diet") {
            type = "diet"
        } else {
            type = "unknown"
        }
        return TaskIntentExtraction(
            taskType: type,
            targetMetric: extractTargetMetric(from: input),
            timeInfo: .init(
                startTime: "",
                frequency: extractFrequency(from: input),
                period: ""
            ),
            action: extractAction(from: input),
            intensityOrValue: extractIntensity(from: input),
            confidence: 0.55
        )
    }

    private static func extractTargetMetric(from text: String) -> String {
        let candidates = ["血糖", "血压", "体重", "步数", "热量", "饮食控制", "减脂"]
        return candidates.first(where: { text.contains($0) }) ?? ""
    }

    private static func extractAction(from text: String) -> String {
        let candidates = ["测量", "监测", "步行", "跑步", "运动", "控制饮食", "复诊", "服药"]
        return candidates.first(where: { text.contains($0) }) ?? ""
    }

    private static func extractFrequency(from text: String) -> String {
        if text.contains("每天") { return "daily" }
        if text.contains("每周") { return "weekly" }
        return ""
    }

    private static func extractIntensity(from text: String) -> String {
        let pattern = #"([0-9]+(\.[0-9]+)?\s*(次|步|分钟|分|km|公里|kcal|千卡))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[range])
    }
}
