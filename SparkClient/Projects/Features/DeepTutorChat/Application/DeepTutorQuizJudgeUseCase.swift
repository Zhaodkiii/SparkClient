import Foundation

struct DeepTutorQuizJudgeUseCase: Sendable {
    let orchestrator: ChatOrchestrator
    let aiConfigCenter: AIConfigCenter

    struct Request: Sendable {
        let conversationID: UUID
        let question: DeepTutorQuizQuestion
        let userAnswer: String
        let preferredModelName: String?
    }

    func callAsFunction(_ request: Request) async throws -> String {
        let resolvedConfig = try await aiConfigCenter.resolve(
            for: .chat,
            preferredModelName: request.preferredModelName
        )

        let systemPrompt = """
        You are an educational quiz grader. Judge the student's answer against the reference answer and explanation.
        Respond in the same language as the question.
        Output plain text only with this structure:
        1) Verdict: 正确 / 部分正确 / 错误
        2) Brief rationale in 2-4 sentences.
        Do not use markdown headings.
        """

        let referenceAnswer: String
        switch request.question.questionType {
        case .choice:
            let key = DeepTutorQuizGrader.resolveChoiceAnswerKey(
                correctAnswer: request.question.correctAnswer,
                options: request.question.options
            )
            if let option = request.question.options.first(where: { $0.key.uppercased() == key.uppercased() }) {
                referenceAnswer = "\(option.key). \(option.text)"
            } else {
                referenceAnswer = request.question.correctAnswer
            }
        case .concept:
            referenceAnswer = DeepTutorQuizGrader.resolveConceptAnswer(request.question.correctAnswer) == "true" ? "对" : "错"
        default:
            referenceAnswer = request.question.correctAnswer
        }

        let userPrompt = """
        Question type: \(request.question.questionType.rawValue)
        Question:
        \(request.question.question)

        Student answer:
        \(request.userAnswer)

        Reference answer:
        \(referenceAnswer)

        Explanation:
        \(request.question.explanation)
        """

        let inference = ChatOrchestratorInferenceOptions(
            useTools: false,
            useKnowledgeBag: false,
            useWebSearch: false,
            reasoningEnabled: false,
            reasoningEffortTier: 0,
            allowedToolNames: nil
        )

        let output = try await orchestrator.generateReply(
            userInput: userPrompt,
            history: [],
            memberContextSummary: "",
            memberID: nil,
            threadID: request.conversationID,
            inference: inference,
            systemPrompt: systemPrompt,
            preferredModelName: request.preferredModelName ?? resolvedConfig.model,
            temperature: 0.2,
            maxTokens: 400
        )

        let judgment = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard judgment.isEmpty == false else {
            throw AIRuntimeError.emptyOutput
        }
        return judgment
    }
}
