#if canImport(XCTest)
import Foundation
import XCTest

final class ChatGuideQuestionGenerationUseCaseTests: XCTestCase {
    func testGenerateReturnsParsedQuestions() async throws {
        let runtime = StubGuideQuestionRuntime(responseText: """
        [
          {"id":"q1","title":"问题一?","prompt":"问题一完整?","category":"popular_science"},
          {"id":"q2","title":"问题二?","prompt":"问题二完整?","category":"popular_science"},
          {"id":"q3","title":"问题三?","prompt":"问题三完整?","category":"popular_science"}
        ]
        """)
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 42,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        let output = try await useCase.generate(
            input: ChatGuideQuestionGenerationInput(
                threadID: UUID(),
                messageID: UUID(),
                blockID: UUID(),
                memberID: 42,
                localeIdentifier: "zh-Hans",
                modelName: "test-model",
                metricSections: []
            )
        )
        XCTAssertEqual(output.questions.count, 3)
        XCTAssertEqual(output.memberID, 42)
        XCTAssertFalse(output.memberProfileDigest.isEmpty)
    }

    func testGenerateParsesNumericIDWithoutRepair() async throws {
        let runtime = StubGuideQuestionRuntime(responseText: """
        [
          {"id":1,"title":"久坐程序员怎么护颈椎腰椎?","prompt":"完整问题一?","category":"popular_science"},
          {"id":2,"title":"甲状腺囊肿日常要注意什么?","prompt":"完整问题二?","category":"popular_science"},
          {"id":3,"title":"日常怎么科学控制体重?","prompt":"完整问题三?","category":"popular_science"}
        ]
        """)
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 42,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        let output = try await useCase.generate(
            input: ChatGuideQuestionGenerationInput(
                threadID: UUID(),
                messageID: UUID(),
                blockID: UUID(),
                memberID: 42,
                localeIdentifier: "zh-Hans",
                modelName: nil,
                metricSections: []
            )
        )
        XCTAssertEqual(output.questions.count, 3)
        XCTAssertEqual(runtime.callCount, 1)
        XCTAssertTrue(output.questions.allSatisfy { $0.id.hasPrefix("guide_") })
    }

    func testGenerateThrowsWhenProfileUnavailable() async {
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: StubGuideQuestionRuntime(responseText: "[]"),
            medicalReader: StubGuideMedicalReader(completeData: nil)
        )
        do {
            _ = try await useCase.generate(
                input: ChatGuideQuestionGenerationInput(
                    threadID: UUID(),
                    messageID: UUID(),
                    blockID: UUID(),
                    memberID: 42,
                    localeIdentifier: "zh-Hans",
                    modelName: nil,
                    metricSections: []
                )
            )
            XCTFail("Expected memberProfileUnavailable")
        } catch {
            XCTAssertEqual(error as? ChatGuideQuestionGenerationUseCaseError, .memberProfileUnavailable)
        }
    }

    func testGenerateRetriesRepairPromptAfterInvalidJSON() async throws {
        let runtime = StubGuideQuestionRuntime(
            responses: [
                "not-json",
                """
                [
                  {"id":"q1","title":"问题一?","prompt":"问题一完整?","category":"popular_science"},
                  {"id":"q2","title":"问题二?","prompt":"问题二完整?","category":"popular_science"},
                  {"id":"q3","title":"问题三?","prompt":"问题三完整?","category":"popular_science"}
                ]
                """
            ]
        )
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 42,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        let output = try await useCase.generate(
            input: ChatGuideQuestionGenerationInput(
                threadID: UUID(),
                messageID: UUID(),
                blockID: UUID(),
                memberID: 42,
                localeIdentifier: "zh-Hans",
                modelName: nil,
                metricSections: []
            )
        )
        XCTAssertEqual(output.questions.count, 3)
        XCTAssertEqual(runtime.callCount, 2)
    }

    func testGenerateThrowsCancelledWhenStreamCancelled() async {
        let runtime = StubGuideQuestionRuntime(mode: .cancelled)
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 42,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        do {
            _ = try await useCase.generate(
                input: ChatGuideQuestionGenerationInput(
                    threadID: UUID(),
                    messageID: UUID(),
                    blockID: UUID(),
                    memberID: 42,
                    localeIdentifier: "zh-Hans",
                    modelName: nil,
                    metricSections: []
                )
            )
            XCTFail("Expected cancelled")
        } catch {
            XCTAssertEqual(error as? ChatGuideQuestionGenerationUseCaseError, .cancelled)
        }
    }

    func testGenerateSucceedsFromBufferedTextWithoutCompletedEvent() async throws {
        let runtime = StubGuideQuestionRuntime(
            mode: .deltasOnly(
                """
                [
                  {"id":"q1","title":"问题一?","prompt":"问题一完整?","category":"popular_science"},
                  {"id":"q2","title":"问题二?","prompt":"问题二完整?","category":"popular_science"},
                  {"id":"q3","title":"问题三?","prompt":"问题三完整?","category":"popular_science"}
                ]
                """
            )
        )
        let useCase = ChatGuideQuestionGenerationUseCase(
            runtime: runtime,
            medicalReader: StubGuideMedicalReader(
                completeData: StubGuideMedicalReader.makeCompleteData(
                    memberID: 42,
                    caseCount: 1,
                    activePlanCount: 0
                )
            )
        )
        let output = try await useCase.generate(
            input: ChatGuideQuestionGenerationInput(
                threadID: UUID(),
                messageID: UUID(),
                blockID: UUID(),
                memberID: 42,
                localeIdentifier: "zh-Hans",
                modelName: nil,
                metricSections: []
            )
        )
        XCTAssertEqual(output.questions.count, 3)
    }
}

private final class StubGuideQuestionRuntime: AIRuntimeServing, @unchecked Sendable {
    enum Mode {
        case completed(String)
        case deltasOnly(String)
        case cancelled
    }

    var responses: [String]
    private(set) var callCount = 0
    private let mode: Mode

    init(responseText: String) {
        self.responses = [responseText]
        self.mode = .completed(responseText)
    }

    init(responses: [String]) {
        self.responses = responses
        self.mode = .completed(responses.last ?? "")
    }

    init(mode: Mode) {
        self.responses = []
        self.mode = mode
    }

    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        callCount += 1
        switch mode {
        case .cancelled:
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CancellationError())
            }
        case .deltasOnly(let text):
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta(text))
                continuation.finish()
            }
        case .completed:
            let index = min(callCount - 1, responses.count - 1)
            let text = responses[index]
            return AsyncThrowingStream { continuation in
                continuation.yield(
                    .completed(
                        AIRuntimeTextResponse(
                            text: text,
                            model: "stub",
                            promptTokens: nil,
                            completionTokens: nil,
                            toolCalls: [],
                            finishReason: "stop"
                        )
                    )
                )
                continuation.finish()
            }
        }
    }
}
#endif
