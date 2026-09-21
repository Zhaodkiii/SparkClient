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

    func testRegistrationRecommendationPayloadDecodesAcronymIDsFromSnakeCase() throws {
        let hospitalID = UUID()
        let departmentID = UUID()
        let doctorID = UUID()
        let payload = ChatRegistrationRecommendationCardPayload(
            hospitalID: hospitalID,
            hospitalName: "天长市中医院",
            departmentID: departmentID,
            departmentName: "皮肤科",
            agentID: UUID(),
            doctorID: doctorID,
            doctorName: "叶宇峰",
            doctorTitle: "中医师",
            reasonSummary: "皮肤相关症状建议优先咨询皮肤科。"
        )

        let data = try JSONEncoder.chatRemote.encode(payload)
        let decoded = try JSONDecoder.chatRemote.decode(
            ChatRegistrationRecommendationCardPayload.self,
            from: data
        )

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("hospital_id"))

        let legacyJSON = """
        {
          "schemaVersion": 1,
          "hospitalID": "\(hospitalID.uuidString)",
          "hospitalName": "天长市中医院",
          "departmentID": "\(departmentID.uuidString)",
          "departmentName": "皮肤科",
          "agentID": "\(payload.agentID!.uuidString)",
          "doctorID": "\(doctorID.uuidString)",
          "doctorName": "叶宇峰",
          "doctorTitle": "中医师",
          "doctorAvatarURL": null,
          "reasonSummary": "根据症状建议咨询皮肤科。"
        }
        """
        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let legacyDecoded = try JSONDecoder.chatRemote.decode(
            ChatRegistrationRecommendationCardPayload.self,
            from: legacyData
        )
        XCTAssertEqual(legacyDecoded.hospitalID, hospitalID)
        XCTAssertEqual(legacyDecoded.departmentID, departmentID)
        XCTAssertEqual(legacyDecoded.doctorID, doctorID)
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

    func testSchemaV1PayloadDecodesWithoutQuestionGenerationMeta() throws {
        let json = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-08-21T12:00:00Z",
          "memberID": 42,
          "metricSections": [],
          "questions": [
            {
              "id": "tcm_medicine_precautions",
              "title": "使用中成药有哪些注意事项?",
              "prompt": "使用中成药有哪些注意事项?",
              "category": "popular_science"
            }
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ChatGuideCardPayload.self, from: data)
        XCTAssertNil(payload.questionGeneration)
        XCTAssertEqual(payload.effectiveQuestionGenerationState, .preset)
        XCTAssertFalse(payload.isShowingQuestionLoading)
    }

    func testSchemaV2PayloadRoundTripsWithGenerationMeta() throws {
        let payload = ChatGuideCardPreviewFixtures.generatingPayload
        let data = try JSONEncoder.default.encode(payload)
        let decoded = try JSONDecoder.default.decode(ChatGuideCardPayload.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.questionGeneration?.state, .generating)
        XCTAssertTrue(decoded.isShowingQuestionLoading)
    }
}
#endif
