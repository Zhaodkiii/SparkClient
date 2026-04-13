#if canImport(XCTest)
import Foundation
import XCTest

final class ChatStreamingAssistantReducerTests: XCTestCase {
    func testReducerUpdatesReasoningAndDuration() {
        let reducer = ChatStreamingAssistantReducer()
        var state = ChatStreamingAssistantState.initial(kind: .text)

        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = t0.addingTimeInterval(0.25)

        let changed1 = reducer.reduce(
            state: &state,
            delta: ChatAssistantPartialDelta(
                answer: "",
                reasoning: "正在分析",
                kind: .text,
                toolName: nil,
                toolContent: nil
            ),
            now: t0
        )
        XCTAssertTrue(changed1)
        XCTAssertEqual(state.reasoningContent, "正在分析")
        XCTAssertEqual(state.reasoningStartedAt, t0)
        XCTAssertEqual(state.reasoningDurationMs, 1)

        let changed2 = reducer.reduce(
            state: &state,
            delta: ChatAssistantPartialDelta(
                answer: "最终答案",
                reasoning: "正在分析",
                kind: .text,
                toolName: nil,
                toolContent: nil
            ),
            now: t1
        )
        XCTAssertTrue(changed2)
        XCTAssertEqual(state.content, "最终答案")
        XCTAssertEqual(state.reasoningDurationMs, 250)
    }

    func testReducerNormalizesToolFields() {
        let reducer = ChatStreamingAssistantReducer()
        var state = ChatStreamingAssistantState.initial(kind: .text)

        _ = reducer.reduce(
            state: &state,
            delta: ChatAssistantPartialDelta(
                answer: "",
                reasoning: nil,
                kind: .tool,
                toolName: " query_location ",
                toolContent: " 使用工具：query_location\nargs=keyword=医院 "
            )
        )

        XCTAssertEqual(state.kind, .tool)
        XCTAssertEqual(state.toolName, "query_location")
        XCTAssertEqual(state.toolContent, "使用工具：query_location\nargs=keyword=医院")
    }
}
#endif
