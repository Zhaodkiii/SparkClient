import XCTest
@testable import SparkClient

final class DeepTutorQuizPipelineTests: XCTestCase {
    func testQuizContentParserStripsFenceAndBuildsResultEvent() {
        let intro = "这里是一份健康小测验，请逐题作答。"
        let json = """
        {"results":[{"qa_pair":{"question_id":"q_1","question":"成年人每天建议饮水量约为？","question_type":"choice","options":{"A":"500ml","B":"1500-1700ml","C":"3000ml","D":"5000ml"},"correct_answer":"B","explanation":"参考膳食指南。","difficulty":"easy","concentration":"饮水"}}]}
        """
        let content = """
        \(intro)

        ```quiz_json
        \(json)
        ```
        """

        let outcome = DeepTutorQuizContentParser.parse(content: content)
        XCTAssertTrue(outcome.foundStructuredPayload)
        XCTAssertFalse(outcome.parseFailed)
        XCTAssertEqual(outcome.strippedContent, intro)
        XCTAssertNotNil(outcome.summaryJSON)

        let message = DeepTutorQuizContentParser.apply(
            to: DeepTutorMessage(
                conversationID: UUID(),
                role: .assistant,
                content: content,
                capability: .deepQuestion,
                events: [.result(metadata: ["source": "ai-runtime"])],
                status: .ready
            )
        )

        XCTAssertEqual(message.content, intro)
        XCTAssertTrue(message.events.contains { event in
            if case let .result(metadata, summaryJSON) = event {
                return metadata["source"] == "quiz_content_parser" && summaryJSON?.contains("q_1") == true
            }
            return false
        })

        let blocks = DeepTutorMessageReducer.blocks(for: message)
        XCTAssertTrue(blocks.contains { $0.kind == .quiz })
    }

    func testQuizContentParserRepairsMalformedQuizJsonFence() {
        let intro = "下面是 3 道健康知识小测验，帮你快速检查日常健康常识。"
        let malformed = """
        ```quiz_json

          "results":

              "qa_pair":
                "question_id": "q_1",
                "question": "一般情况下，健康成年人每天适宜的饮水量大约是多少？",
                "question_type": "choice",
                "options":
                  "A": "500 毫升以下",
                  "B": "1500—1700 毫升",
                  "C": "3000—4000 毫升",
                  "D": "完全不渴就不用喝"
                },
                "correct_answer": "B",
                "explanation": "参考指南。",
                "difficulty": "easy",
                "concentration": "饮水"
        ```
        """
        let content = "\(intro)\n\n\(malformed)"
        let outcome = DeepTutorQuizContentParser.parse(content: content)

        XCTAssertTrue(outcome.foundStructuredPayload)
        XCTAssertFalse(outcome.parseFailed)
        XCTAssertNotNil(outcome.summaryJSON)
        XCTAssertEqual(outcome.strippedContent, intro)

        let message = DeepTutorQuizContentParser.apply(
            to: DeepTutorMessage(
                conversationID: UUID(),
                role: .assistant,
                content: content,
                capability: .deepQuestion,
                status: .ready
            )
        )
        let blocks = DeepTutorMessageReducer.blocks(for: message)
        XCTAssertTrue(blocks.contains { $0.kind == .quiz })
        XCTAssertFalse(blocks.contains { $0.kind == .quizParseError })
    }

    func testQuizContentParserShowsParseErrorBlockWhenRepairFails() {
        let content = """
        以下是几个关于睡眠健康的小测验
        "question": "test"
        "question_type": "choice"
        "correct_answer": "B"
        """
        let message = DeepTutorQuizContentParser.apply(
            to: DeepTutorMessage(
                conversationID: UUID(),
                role: .assistant,
                content: content,
                capability: .deepQuestion,
                status: .ready
            )
        )
        XCTAssertFalse(message.content.localizedCaseInsensitiveContains("\"question_type\""))
        let blocks = DeepTutorMessageReducer.blocks(for: message)
        XCTAssertTrue(blocks.contains { $0.kind == .quizParseError })
    }

    func testQuizExtractorUsesEarlierParserSummaryEventWhenFinalResultHasNoSummary() {
        let summaryJSON = """
        {"results":[{"qa_pair":{"question_id":"q_1","question":"成年人每天建议饮水量约为？","question_type":"choice","options":{"A":"500ml","B":"1500-1700ml","C":"3000ml","D":"5000ml"},"correct_answer":"B","explanation":"参考膳食指南。","difficulty":"easy","concentration":"饮水"}}]}
        """
        let message = DeepTutorMessage(
            conversationID: UUID(),
            role: .assistant,
            content: "这里是一份健康小测验。",
            capability: .deepQuestion,
            events: [
                .result(metadata: ["source": "quiz_content_parser"], summaryJSON: summaryJSON),
                .result(metadata: ["model": "doubao-seed-evolving", "finishReason": "stop", "source": "ai-runtime"]),
            ],
            status: .ready
        )

        let extracted = DeepTutorQuizExtractor.extract(from: message)
        XCTAssertNotNil(extracted.payload)
        XCTAssertEqual(extracted.questionCount, 1)
        XCTAssertEqual(extracted.source, .contentParser)

        let blocks = DeepTutorMessageReducer.blocks(for: message)
        XCTAssertTrue(blocks.contains { $0.kind == .quiz })
        XCTAssertFalse(blocks.contains { $0.kind == .quizParseError })
    }

    func testQuizAndParseErrorBlocksRoundTripThroughCodec() {
        let quiz = DeepTutorQuizPayload(
            title: "Quick Check",
            turnID: "turn-1",
            questions: [
                DeepTutorQuizQuestion(
                    id: "q_1",
                    question: "成年人每天建议饮水量约为？",
                    questionType: .choice,
                    options: [
                        DeepTutorQuizOption(key: "A", text: "500ml"),
                        DeepTutorQuizOption(key: "B", text: "1500-1700ml"),
                    ],
                    correctAnswer: "B",
                    explanation: "参考膳食指南。"
                ),
            ],
            source: .contentParser
        )
        XCTAssertTrue(DeepTutorMessageCodec.validateRoundTrip(.quiz(quiz), kind: "deepTutorQuiz"))

        let parseError = DeepTutorQuizParseErrorPayload(
            reason: "missing_results_array",
            messageID: UUID()
        )
        XCTAssertTrue(
            DeepTutorMessageCodec.validateRoundTrip(.quizParseError(parseError), kind: "deepTutorQuizParseError")
        )
    }

    func testReloadMergerPrefersMemoryWhenDatabaseLosesQuizBlock() {
        let conversationID = UUID()
        let messageID = UUID()
        let quiz = DeepTutorQuizPayload(
            title: "Quick Check",
            turnID: "turn-1",
            questions: [
                DeepTutorQuizQuestion(
                    id: "q_1",
                    question: "Q?",
                    questionType: .concept,
                    correctAnswer: "true"
                ),
            ],
            source: .contentParser
        )
        let quizBlock = DeepTutorMessageBlock(
            id: DeepTutorMessageCodec.stableBlockID(messageID: messageID, suffix: "quiz"),
            kind: .quiz,
            payload: .quiz(quiz),
            orderKey: 100
        )

        var memory = DeepTutorMessage(
            id: messageID,
            conversationID: conversationID,
            role: .assistant,
            content: "intro",
            capability: .deepQuestion,
            status: .ready
        )
        memory = memory.replacing(blocks: memory.blocks + [quizBlock])

        var db = DeepTutorMessage(
            id: messageID,
            conversationID: conversationID,
            role: .assistant,
            content: "intro",
            capability: .deepQuestion,
            status: .ready
        )
        db = db.replacing(blocks: db.blocks.filter { $0.kind != .quiz })

        let merged = DeepTutorMessageReloadMerger.merge(
            reloaded: [db],
            cached: [memory],
            conversationID: conversationID
        )
        XCTAssertTrue(merged.first?.blocks.contains { $0.kind == .quiz } == true)
    }

    func testQuizQuestionTypePromotesShortAnswerWithOptionsToChoice() {
        let resolved = DeepTutorQuizQuestionType.resolve(
            raw: "short_answer",
            options: [
                DeepTutorQuizOption(key: "A", text: "1"),
                DeepTutorQuizOption(key: "B", text: "2"),
                DeepTutorQuizOption(key: "C", text: "3"),
                DeepTutorQuizOption(key: "D", text: "4"),
            ],
            questionID: "q_1"
        )
        XCTAssertEqual(resolved, .choice)
    }

    func testQuizAnswerStoreSessionKeyPrefersTurnID() {
        let conversationID = UUID()
        let messageID = UUID()
        let key = DeepTutorQuizAnswerStore.sessionKey(
            conversationID: conversationID,
            assistantMessageID: messageID,
            turnID: "turn-abc"
        )
        XCTAssertEqual(key, "\(conversationID.uuidString)|turn-abc")
        XCTAssertFalse(key.contains(messageID.uuidString))
    }

    func testQuizAnswerStoreFallbackTurnIDIsStable() {
        let messageID = UUID()
        XCTAssertEqual(
            DeepTutorQuizAnswerStore.fallbackTurnID(assistantMessageID: messageID),
            "msg-\(messageID.uuidString)"
        )
    }

    func testDeepQuestionToolPolicyUsesManifestDefaults() {
        var context = makeContext(userInput: "健康知识给我来一些", capability: .deepQuestion)
        context.snapshotRequestedTools = DeepTutorCapabilityToolManifest.manifest(for: .deepQuestion).defaultTools
        let policy = DeepTutorToolPolicyResolver.resolve(context)

        XCTAssertTrue(policy.requestedCanonicalTools.contains(DeepTutorCanonicalToolName.webSearch.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.searchOnline.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.fetchStepDetails.rawValue))
    }

    private func makeContext(
        userInput: String,
        capability: DeepTutorCapability
    ) -> DeepTutorToolMountContext {
        DeepTutorToolMountContext.default(
            capability: capability,
            userInput: userInput,
            conversationID: UUID(),
            conversationTitle: "Test"
        )
    }
}
