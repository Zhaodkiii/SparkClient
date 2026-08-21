#if canImport(XCTest)
import Foundation
import XCTest

/// 引导卡片 payload 编解码测试：
/// 覆盖 `ChatMessageBlockCodec`（Core Data payloadData）与 `chatRemote` 同步编解码两条链路。
final class ChatGuideCardPayloadCodableTests: XCTestCase {
    func testGuideCardBlockRoundTripsThroughBlockCodec() throws {
        let payload = ChatGuideCardPreviewFixtures.fullPayload
        let message = ChatGuideSystemMessageFactory.make(
            threadID: UUID(),
            payload: payload,
            createdAt: Date(timeIntervalSince1970: 1_787_300_000)
        )
        let block = try XCTUnwrap(message.blocks.first)

        let data = try ChatMessageBlockCodec.encode(block)
        let decoded = try XCTUnwrap(ChatMessageBlockCodec.decode(data))

        XCTAssertEqual(decoded.id, block.id)
        XCTAssertEqual(decoded.kind, .chatGuideCard)
        XCTAssertEqual(decoded.orderKey, block.orderKey)
        if case .chatGuideCard(let decodedPayload) = decoded.payload {
            XCTAssertEqual(decodedPayload, payload)
        } else {
            XCTFail("Expected chatGuideCard payload after codec round-trip")
        }
    }

    func testGuideCardPayloadRoundTripsThroughChatRemoteCoders() throws {
        let payload = ChatGuideCardPreviewFixtures.fullPayload
        let block = ChatMessageBlock.fromPayload(
            .chatGuideCard(payload),
            id: ChatStableBlockID.rich(messageID: UUID(), kind: .chatGuideCard),
            orderKey: 0,
            createdAt: payload.generatedAt,
            updatedAt: payload.generatedAt
        )

        let data = try JSONEncoder.chatRemote.encode(block)
        let decoded = try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)

        XCTAssertEqual(decoded.kind, .chatGuideCard)
        if case .chatGuideCard(let decodedPayload) = decoded.payload {
            XCTAssertEqual(decodedPayload.metricSections.count, 4)
            XCTAssertEqual(decodedPayload.questions.count, 3)
            XCTAssertEqual(decodedPayload.questions, payload.questions)
            XCTAssertEqual(decodedPayload.metricSections.map(\.state), payload.metricSections.map(\.state))
        } else {
            XCTFail("Expected chatGuideCard payload after chatRemote round-trip")
        }
    }

    func testMiniChartNormalization() {
        XCTAssertNil(ChatGuideMiniChart.normalized(from: [1]))
        XCTAssertNil(ChatGuideMiniChart.normalized(from: []))

        // 等值序列：无趋势，全部落在中位
        let flat = ChatGuideMiniChart.normalized(from: [5, 5, 5])
        XCTAssertEqual(flat?.normalizedValues, [0.5, 0.5, 0.5])

        // 常规序列：min → 0，max → 1
        let chart = ChatGuideMiniChart.normalized(from: [0, 5, 10])
        let values = chart?.normalizedValues ?? []
        guard values.count == 3 else {
            XCTFail("Expected 3 normalized values")
            return
        }
        XCTAssertEqual(values[0], 0, accuracy: 0.0001)
        XCTAssertEqual(values[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(values[2], 1, accuracy: 0.0001)
    }

    func testGuideQuestionPayloadKeepsPromptSeparateFromTitle() {
        for question in ChatGuideQuestionPreset.phaseOne {
            XCTAssertFalse(question.id.isEmpty)
            XCTAssertFalse(question.title.isEmpty)
            XCTAssertFalse(question.prompt.isEmpty)
            XCTAssertGreaterThan(question.prompt.count, question.title.count)
        }
    }
}
#endif
