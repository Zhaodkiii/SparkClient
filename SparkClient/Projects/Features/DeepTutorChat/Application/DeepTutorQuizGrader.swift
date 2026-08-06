import Foundation

enum DeepTutorQuizGrader: Sendable {
    nonisolated static func isAutoGradable(_ type: DeepTutorQuizQuestionType) -> Bool {
        switch type {
        case .choice, .concept, .fillInBlank:
            return true
        case .shortAnswer, .written, .coding:
            return false
        }
    }

    nonisolated static func canSubmit(question: DeepTutorQuizQuestion, selectedKey: String?, typedText: String) -> Bool {
        switch question.questionType {
        case .choice, .concept:
            return selectedKey?.isEmpty == false
        case .fillInBlank, .shortAnswer, .written, .coding:
            return typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    nonisolated static func grade(
        question: DeepTutorQuizQuestion,
        selectedKey: String?,
        typedText: String
    ) -> Bool? {
        guard isAutoGradable(question.questionType) else { return nil }

        switch question.questionType {
        case .choice:
            let resolved = resolveChoiceAnswerKey(
                correctAnswer: question.correctAnswer,
                options: question.options
            )
            guard resolved.isEmpty == false else { return false }
            let selected = selectedKey?.uppercased() ?? ""
            let correct = question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            return selected == resolved.uppercased()
                || selected == correct.uppercased()
                || selected == correct.prefix(1).uppercased()
        case .concept:
            let correct = resolveConceptAnswer(question.correctAnswer)
            let selected = resolveConceptAnswer(selectedKey ?? typedText)
            guard correct.isEmpty == false, selected.isEmpty == false else { return false }
            return correct == selected
        case .fillInBlank:
            return normalizeFillBlank(typedText) == normalizeFillBlank(question.correctAnswer)
        case .shortAnswer, .written, .coding:
            return nil
        }
    }

    nonisolated static func resolveChoiceAnswerKey(
        correctAnswer: String,
        options: [DeepTutorQuizOption]
    ) -> String {
        let correct = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard correct.isEmpty == false else { return "" }

        let directKey = correct.uppercased()
        if options.contains(where: { $0.key.uppercased() == directKey }) {
            return directKey
        }

        let normalizedAnswer = correct.lowercased()
        for option in options {
            if normalizedAnswer == option.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                return option.key.uppercased()
            }
        }
        return directKey
    }

    nonisolated static func resolveConceptAnswer(_ raw: String?) -> String {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "true", "t", "yes", "y", "对", "正确", "a", "correct":
            return "true"
        case "false", "f", "no", "n", "错", "错误", "b", "incorrect":
            return "false"
        default:
            return ""
        }
    }

    nonisolated private static func normalizeFillBlank(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
