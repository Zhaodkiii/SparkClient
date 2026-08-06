import SwiftUI

struct DeepTutorQuizCardView: View {
    let conversationID: UUID
    let messageID: UUID
    let payload: DeepTutorQuizPayload
    let onFollowUp: (String) -> Void
    let onJudge: (DeepTutorQuizQuestion, String) async -> String?
    var onInlineInputFocusChanged: ((Bool) -> Void)? = nil

    @State private var session: DeepTutorQuizSessionState

    init(
        conversationID: UUID,
        messageID: UUID,
        payload: DeepTutorQuizPayload,
        onFollowUp: @escaping (String) -> Void = { _ in },
        onJudge: @escaping (DeepTutorQuizQuestion, String) async -> String? = { _, _ in nil },
        onInlineInputFocusChanged: ((Bool) -> Void)? = nil
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.payload = payload
        self.onFollowUp = onFollowUp
        self.onJudge = onJudge
        self.onInlineInputFocusChanged = onInlineInputFocusChanged
        _session = State(
            initialValue: .empty(
                conversationID: conversationID,
                assistantMessageID: messageID,
                turnID: effectiveTurnID(payloadTurnID: payload.turnID, messageID: messageID)
            )
        )
    }

    private var resolvedTurnID: String {
        effectiveTurnID(payloadTurnID: payload.turnID, messageID: messageID)
    }

    private var questions: [DeepTutorQuizQuestion] { payload.questions }
    private var currentIndex: Int {
        min(max(0, session.currentIndex), max(questions.count - 1, 0))
    }
    private var currentQuestion: DeepTutorQuizQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if questions.isEmpty == false {
                DeepTutorQuizHeaderView(
                    total: questions.count,
                    currentIndex: currentIndex,
                    completedCount: completedCount,
                    chipStates: chipStates,
                    onPrevious: { navigate(to: currentIndex - 1) },
                    onNext: { navigate(to: currentIndex + 1) },
                    onSelectIndex: navigate(to:)
                )

                if let question = currentQuestion {
                    let answer = answerState(for: question)

                    DeepTutorQuizQuestionBodyView(
                        question: question,
                        questionIndex: currentIndex,
                        submitted: answer.submitted,
                        bookmarked: answer.bookmarked,
                        onToggleBookmark: answer.submitted ? { toggleBookmark(for: question) } : nil,
                        onFollowUp: answer.submitted ? { startFollowUp(for: question, answer: answer) } : nil
                    )

                    DeepTutorQuizAnswerInputView(
                        question: question,
                        selectedKey: answer.selectedKey,
                        typedText: answer.typedText,
                        submitted: answer.submitted,
                        onSelectKey: { key in
                            updateAnswer(for: question) { state in
                                state.selectedKey = key
                            }
                            DeepTutorChatLog.quizUIAnswerSelected(
                                conversationID: conversationID,
                                assistantMessageID: messageID,
                                turnID: resolvedTurnID,
                                questionID: question.id,
                                selectedKey: key
                            )
                        },
                        onType: { text in
                            updateAnswer(for: question) { state in
                                state.typedText = text
                            }
                            DeepTutorChatLog.quizUIAnswerTyped(
                                conversationID: conversationID,
                                assistantMessageID: messageID,
                                turnID: resolvedTurnID,
                                questionID: question.id,
                                typedLength: text.count
                            )
                        },
                        onInlineInputFocusChanged: { focused in
                            DeepTutorChatLog.quizInlineInputFocusChanged(
                                conversationID: conversationID,
                                assistantMessageID: messageID,
                                turnID: resolvedTurnID,
                                questionID: question.id,
                                focused: focused
                            )
                            onInlineInputFocusChanged?(focused)
                        }
                    )

                    actionRow(question: question, answer: answer)

                    if answer.submitted,
                       question.explanation.isEmpty == false || shouldShowReview(for: question) || answer.aiJudgment?.isEmpty == false {
                        DeepTutorQuizReviewPanelView(
                            question: question,
                            collapsed: answer.reviewCollapsed,
                            aiJudgment: answer.aiJudgment,
                            reviewViewMode: answer.reviewViewMode,
                            onToggle: {
                                var collapsed = answer.reviewCollapsed
                                collapsed.toggle()
                                updateAnswer(for: question) { state in
                                    state.reviewCollapsed = collapsed
                                }
                                DeepTutorChatLog.quizUIReviewToggle(
                                    conversationID: conversationID,
                                    assistantMessageID: messageID,
                                    turnID: resolvedTurnID,
                                    questionID: question.id,
                                    collapsed: collapsed
                                )
                            },
                            onSelectViewMode: { mode in
                                updateAnswer(for: question) { state in
                                    state.reviewViewMode = mode
                                }
                            }
                        )
                    }
                }
            }
        }
        .background(DeepTutorPalette.cardBackground, in: cardShape)
        .overlay {
            cardShape.strokeBorder(DeepTutorPalette.borderColor, lineWidth: 1)
        }
        .clipShape(cardShape)
        .padding(.vertical, 4)
        .task(id: sessionTaskID) {
            await loadSessionIfNeeded()
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var sessionTaskID: String {
        "\(conversationID.uuidString)|\(messageID.uuidString)|\(resolvedTurnID)|\(questions.count)"
    }

    private var completedCount: Int {
        session.answersByQuestionID.values.filter(\.submitted).count
    }

    private var chipStates: [DeepTutorQuizChipState] {
        questions.enumerated().map { index, question in
            let answer = answerState(for: question)
            if answer.submitted {
                if let isCorrect = answer.isCorrect {
                    return isCorrect ? .correct : .incorrect
                }
                return .submittedOpenEnded
            }
            if index == currentIndex { return .current }
            return .unanswered
        }
    }

    @ViewBuilder
    private func actionRow(question: DeepTutorQuizQuestion, answer: DeepTutorQuizPerQuestionAnswer) -> some View {
        HStack(spacing: 8) {
            if answer.submitted {
                resultBadge(isCorrect: answer.isCorrect)
                Button("重试") {
                    retry(question: question)
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.bordered)

                if DeepTutorQuizGrader.isAutoGradable(question.questionType) == false {
                    Button {
                        Task { await judge(question: question, answer: answer) }
                    } label: {
                        if answer.isJudging {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("AI 判定")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(answer.isJudging)
                }
            } else {
                Button {
                    submit(question: question)
                } label: {
                    Label("检查答案", systemImage: "eye")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(DeepTutorQuizGrader.canSubmit(
                    question: question,
                    selectedKey: answer.selectedKey,
                    typedText: answer.typedText
                ) == false)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func resultBadge(isCorrect: Bool?) -> some View {
        let title: String
        let color: Color
        switch isCorrect {
        case true:
            title = "正确"
            color = .green
        case false:
            title = "错误"
            color = .red
        case nil:
            title = "已提交"
            color = .orange
        }
        return Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func answerState(for question: DeepTutorQuizQuestion) -> DeepTutorQuizPerQuestionAnswer {
        session.answersByQuestionID[question.id] ?? .empty
    }

    private func updateAnswer(
        for question: DeepTutorQuizQuestion,
        mutate: (inout DeepTutorQuizPerQuestionAnswer) -> Void
    ) {
        var answer = answerState(for: question)
        mutate(&answer)
        session.answersByQuestionID[question.id] = answer
        persistSession()
    }

    private func navigate(to index: Int) {
        guard questions.indices.contains(index) else { return }
        session.currentIndex = index
        DeepTutorChatLog.quizUINavigate(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionIndex: index,
            total: questions.count
        )
        persistSession()
    }

    private func submit(question: DeepTutorQuizQuestion) {
        let answer = answerState(for: question)
        let isCorrect = DeepTutorQuizGrader.grade(
            question: question,
            selectedKey: answer.selectedKey,
            typedText: answer.typedText
        )
        updateAnswer(for: question) { state in
            state.submitted = true
            state.isCorrect = isCorrect
            state.submittedAt = Date()
            state.reviewCollapsed = false
            state.reviewViewMode = .reference
        }
        DeepTutorChatLog.quizUISubmit(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionID: question.id,
            questionType: question.questionType.rawValue,
            isCorrect: isCorrect
        )
    }

    private func retry(question: DeepTutorQuizQuestion) {
        session.answersByQuestionID[question.id] = .empty
        DeepTutorChatLog.quizUIRetry(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionID: question.id
        )
        persistSession()
    }

    private func toggleBookmark(for question: DeepTutorQuizQuestion) {
        let next = answerState(for: question).bookmarked == false
        updateAnswer(for: question) { state in
            state.bookmarked = next
        }
        DeepTutorChatLog.quizUIBookmarkToggle(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionID: question.id,
            bookmarked: next
        )
    }

    private func startFollowUp(for question: DeepTutorQuizQuestion, answer: DeepTutorQuizPerQuestionAnswer) {
        let userAnswer = resolvedUserAnswer(question: question, answer: answer)
        let prefill = """
        我想就这道题继续追问：

        题目：\(question.question)

        我的答案：\(userAnswer)

        解析：\(question.explanation)
        """
        DeepTutorChatLog.quizUIFollowUp(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionID: question.id
        )
        onFollowUp(prefill.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func judge(question: DeepTutorQuizQuestion, answer: DeepTutorQuizPerQuestionAnswer) async {
        let userAnswer = resolvedUserAnswer(question: question, answer: answer)
        guard userAnswer.isEmpty == false else { return }

        updateAnswer(for: question) { state in
            state.isJudging = true
        }
        let start = Date()
        DeepTutorChatLog.quizUIJudgeStart(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID,
            questionID: question.id
        )

        let judgment = await onJudge(question, userAnswer)
        updateAnswer(for: question) { state in
            state.isJudging = false
            if let judgment, judgment.isEmpty == false {
                state.aiJudgment = judgment
                state.reviewViewMode = .judgment
                state.reviewCollapsed = false
            }
        }

        if judgment?.isEmpty == false {
            DeepTutorChatLog.quizUIJudgeDone(
                conversationID: conversationID,
                assistantMessageID: messageID,
                turnID: resolvedTurnID,
                questionID: question.id,
                durationMs: Date().timeIntervalSince(start) * 1000
            )
        }
    }

    private func resolvedUserAnswer(question: DeepTutorQuizQuestion, answer: DeepTutorQuizPerQuestionAnswer) -> String {
        switch question.questionType {
        case .choice, .concept:
            return answer.selectedKey ?? ""
        case .fillInBlank, .shortAnswer, .written, .coding:
            return answer.typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func shouldShowReview(for question: DeepTutorQuizQuestion) -> Bool {
        switch question.questionType {
        case .choice, .concept:
            return question.explanation.isEmpty == false
        case .fillInBlank, .shortAnswer, .written, .coding:
            return question.correctAnswer.isEmpty == false || question.explanation.isEmpty == false
        }
    }

    private func loadSessionIfNeeded() async {
        let loaded = await DeepTutorQuizAnswerStore.shared.loadSession(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: resolvedTurnID
        )
        session = loaded
        session.turnID = resolvedTurnID
        session.assistantMessageID = messageID
    }

    private func persistSession() {
        var snapshot = session
        snapshot.turnID = resolvedTurnID
        snapshot.assistantMessageID = messageID
        snapshot.conversationID = conversationID
        Task {
            await DeepTutorQuizAnswerStore.shared.saveSession(snapshot)
        }
    }
}

private func effectiveTurnID(payloadTurnID: String?, messageID: UUID) -> String {
    DeepTutorQuizAnswerStore.normalizedTurnID(payloadTurnID)
        ?? DeepTutorQuizAnswerStore.fallbackTurnID(assistantMessageID: messageID)
}
