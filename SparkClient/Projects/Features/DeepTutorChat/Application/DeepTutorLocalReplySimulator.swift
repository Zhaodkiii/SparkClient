import Foundation

enum DeepTutorLocalReplySimulator {
    struct Step: Sendable {
        let delayNanoseconds: UInt64
        let apply: @Sendable (DeepTutorMessage) -> DeepTutorMessage
    }

    struct Simulation: Sendable {
        let steps: [Step]
    }

    static func simulate(
        userText: String,
        capability: DeepTutorCapability,
        assistantMessageID: UUID,
        conversationID: UUID
    ) -> Simulation {
        switch capability {
        case .chat where userText.lowercased().contains("ask"):
            return askUserSimulation(userText: userText)
        case .deepResearch:
            return deepResearchSimulation(userText: userText)
        case .deepQuestion:
            return quizSimulation(userText: userText)
        case .mathAnimator, .visualize:
            return placeholderSimulation(userText: userText, capability: capability)
        default:
            return echoSimulation(userText: userText)
        }
    }

    private static func echoSimulation(userText: String) -> Simulation {
        let chunks = chunk(userText)
        var steps: [Step] = []
        steps.append(
            Step(delayNanoseconds: 120_000_000) { message in
                message.replacing(
                    events: [.reasoningDelta(text: "Thinking about the request locally…", callID: "think-1", round: 1)],
                    status: .streaming
                )
            }
        )
        steps.append(
            Step(delayNanoseconds: 180_000_000) { message in
                var events = message.events
                events.append(.toolCallStarted(callID: "tool-1", toolName: "web_search", argsSummary: userText))
                return message.replacing(events: events, status: .streaming)
            }
        )
        var content = ""
        for (index, chunk) in chunks.enumerated() {
            content += chunk
            let current = content
            steps.append(
                Step(delayNanoseconds: 90_000_000) { message in
                    var events = message.events
                    if index == 0 {
                        events.append(.toolResult(
                            callID: "tool-1",
                            payload: DeepTutorToolResultPayload(kind: "web_search", title: "Local search", summary: "Fixture result")
                        ))
                    }
                    events.append(.contentDelta(text: chunk, callID: nil, round: nil))
                    return message.replacing(content: current, events: events, status: .streaming)
                }
            )
        }
        steps.append(
            Step(delayNanoseconds: 80_000_000) { message in
                var events = message.events
                events.append(.result(metadata: ["source": "local-fixture"]))
                return message.replacing(events: events, status: .streaming)
            }
        )
        return Simulation(steps: steps)
    }

    private static func askUserSimulation(userText: String) -> Simulation {
        Simulation(steps: [
            Step(delayNanoseconds: 150_000_000) { message in
                message.replacing(
                    content: "I need one detail before continuing.",
                    events: [
                        .toolCallStarted(callID: "ask-1", toolName: "ask_user", argsSummary: "Clarification"),
                        .askUser(
                            payload: DeepTutorAskUserPayload(
                                intro: "Choose how you want to continue.",
                                questions: [
                                    DeepTutorAskUserQuestion(
                                        id: "q1",
                                        header: "Preference",
                                        prompt: "Which direction should I take for \"\(userText)\"?",
                                        options: [
                                            DeepTutorAskUserOption(id: "a", label: "Explain simply", description: "Beginner-friendly summary"),
                                            DeepTutorAskUserOption(id: "b", label: "Go deeper", description: "More technical detail"),
                                        ],
                                        allowFreeText: true,
                                        placeholder: "Or type your own answer"
                                    )
                                ]
                            ),
                            toolCallID: "ask-1"
                        ),
                    ],
                    status: .streaming
                )
            }
        ])
    }

    private static func deepResearchSimulation(userText: String) -> Simulation {
        Simulation(steps: [
            Step(delayNanoseconds: 120_000_000) { message in
                message.replacing(
                    events: [
                        .toolCallStarted(callID: "research-1", toolName: "deep_research", argsSummary: userText),
                        .toolResult(
                            callID: "research-1",
                            payload: DeepTutorToolResultPayload(
                                kind: "research_outline",
                                title: "Research Outline",
                                summary: "understand|decompose|evidence|result",
                                metadata: ["sections": "understand|decompose|evidence|result"]
                            )
                        ),
                    ],
                    status: .streaming
                )
            },
            Step(delayNanoseconds: 200_000_000) { message in
                message.replacing(
                    content: "## Research Report\n\nThis is a local placeholder report for **\(userText)**.",
                    events: message.events + [.contentDelta(text: message.content, callID: nil, round: nil)],
                    status: .streaming
                )
            },
        ])
    }

    private static func quizSimulation(userText: String) -> Simulation {
        let turnID = "local-turn-\(UUID().uuidString.prefix(8))"
        let questions = fixtureQuizQuestions()
        var steps: [Step] = []

        steps.append(
            Step(delayNanoseconds: 120_000_000) { message in
                message.replacing(
                    content: "下面是根据「\(userText)」准备的 3 道健康科普小测验，请逐题作答。",
                    events: [
                        .contentDelta(
                            text: "下面是根据「\(userText)」准备的 3 道健康科普小测验，请逐题作答。",
                            callID: nil,
                            round: nil
                        ),
                    ],
                    status: .streaming
                )
            }
        )

        for (index, question) in questions.enumerated() {
            let captured = question
            steps.append(
                Step(delayNanoseconds: 120_000_000) { message in
                    var events = message.events
                    events.append(.quizQuestionEmitted(question: captured, questionIndex: index, turnID: turnID))
                    return message.replacing(events: events, status: .streaming)
                }
            )
        }

        let summaryJSON = quizSummaryJSON(questions: questions)
        steps.append(
            Step(delayNanoseconds: 80_000_000) { message in
                var events = message.events
                events.append(
                    .result(
                        metadata: [
                            "source": "local-fixture",
                            "turn_id": turnID,
                        ],
                        summaryJSON: summaryJSON
                    )
                )
                return message.replacing(events: events, status: .streaming)
            }
        )

        return Simulation(steps: steps)
    }

    private static func fixtureQuizQuestions() -> [DeepTutorQuizQuestion] {
        [
            DeepTutorQuizQuestion(
                id: "q_1",
                question: "成年人每天建议饮水量约为 1500–1700 毫升，这个说法是否正确？",
                questionType: .concept,
                options: [],
                correctAnswer: "true",
                explanation: "《中国居民膳食指南》建议成年人每日饮水约 **1500–1700 mL**（约 7–8 杯）。",
                difficulty: "easy",
                concentration: "饮水"
            ),
            DeepTutorQuizQuestion(
                id: "q_2",
                question: "下列哪项更符合成年人睡眠建议？",
                questionType: .choice,
                options: [
                    DeepTutorQuizOption(key: "A", text: "每晚 4–5 小时"),
                    DeepTutorQuizOption(key: "B", text: "每晚 7–9 小时"),
                    DeepTutorQuizOption(key: "C", text: "每晚 10–12 小时"),
                ],
                correctAnswer: "B",
                explanation: "多数成年人每晚 **7–9 小时** 睡眠有助于恢复与代谢健康。",
                difficulty: "medium",
                concentration: "睡眠"
            ),
            DeepTutorQuizQuestion(
                id: "q_3",
                question: "健康成年人每周建议进行至少 ____ 分钟中等强度有氧运动。",
                questionType: .fillInBlank,
                options: [],
                correctAnswer: "150",
                explanation: "世界卫生组织建议成年人每周至少 **150 分钟** 中等强度有氧运动。",
                difficulty: "medium",
                concentration: "运动"
            ),
        ]
    }

    private static func quizSummaryJSON(questions: [DeepTutorQuizQuestion]) -> String {
        let results: [[String: Any]] = questions.map { question in
            [
                "qa_pair": [
                    "question_id": question.id,
                    "question": question.question,
                    "question_type": question.questionType.rawValue,
                    "options": Dictionary(uniqueKeysWithValues: question.options.map { ($0.key, $0.text) }),
                    "correct_answer": question.correctAnswer,
                    "explanation": question.explanation,
                    "difficulty": question.difficulty as Any,
                    "concentration": question.concentration as Any,
                ],
            ]
        }
        let summary: [String: Any] = ["results": results]
        guard let data = try? JSONSerialization.data(withJSONObject: summary),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func placeholderSimulation(userText: String, capability: DeepTutorCapability) -> Simulation {
        Simulation(steps: [
            Step(delayNanoseconds: 150_000_000) { message in
                message.replacing(
                    content: "Prepared a local \(capability.badgeLabel) placeholder for \"\(userText)\".",
                    events: [
                        .toolCallStarted(callID: "viz-1", toolName: capability.rawValue, argsSummary: userText),
                        .toolResult(
                            callID: "viz-1",
                            payload: DeepTutorToolResultPayload(kind: capability.rawValue, title: capability.badgeLabel, summary: "Placeholder")
                        ),
                    ],
                    status: .streaming
                )
            }
        ])
    }

    private static func chunk(_ text: String) -> [String] {
        let words = text.split(separator: " ")
        guard words.isEmpty == false else { return [text] }
        var chunks: [String] = []
        var current = ""
        for word in words {
            let piece = current.isEmpty ? String(word) : current + " " + word
            if piece.count > 18 {
                if current.isEmpty == false { chunks.append(current + " ") }
                current = String(word) + " "
            } else {
                current = piece + " "
            }
        }
        if current.isEmpty == false { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }
}
