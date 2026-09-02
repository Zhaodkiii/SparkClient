#if canImport(XCTest)
import Foundation
import XCTest

final class HospitalDoctorIntroCardPayloadCodableTests: XCTestCase {
    func testIntroCardBlockRoundTripsThroughChatRemoteCoders() throws {
        let agentID = UUID()
        let payload = HospitalDoctorIntroCardPayload(
            doctor: .init(
                displayName: "李医生",
                title: "主任医师",
                hospitalName: "测试医院",
                departmentName: "心内科",
                avatarUrl: "https://cdn.example.test/doctors/li.png"
            ),
            agent: .init(
                agentId: agentID,
                agentName: "李医生智能体",
                serviceBoundary: "提供健康信息，不构成诊断。"
            ),
            professionalDirections: ["胸痛评估", "高血压管理"],
            introductionExcerpt: "从事心血管内科临床工作多年。",
            detailRoute: .init(agentId: agentID)
        )
        let block = ChatMessageBlock.fromPayload(
            .hospitalDoctorIntroCard(payload),
            id: ChatStableBlockID.rich(messageID: UUID(), kind: .hospitalDoctorIntroCard),
            orderKey: 0,
            createdAt: Date(timeIntervalSince1970: 1_788_300_000),
            updatedAt: Date(timeIntervalSince1970: 1_788_300_000)
        )

        let data = try JSONEncoder.chatRemote.encode(block)
        let decoded = try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)

        XCTAssertEqual(decoded.kind, .hospitalDoctorIntroCard)
        if case .hospitalDoctorIntroCard(let decodedPayload) = decoded.payload {
            XCTAssertEqual(decodedPayload, payload)
        } else {
            XCTFail("Expected hospitalDoctorIntroCard payload after chatRemote round-trip")
        }
    }

    func testBackendSnapshotJSONDecodesIntoIntroCardPayload() throws {
        let agentID = UUID()
        let json = """
        {
          "doctor": {
            "display_name": "李医生",
            "title": "主任医师",
            "hospital_name": "测试医院",
            "department_name": "心内科",
            "avatar_url": ""
          },
          "agent": {
            "agent_id": "\(agentID.uuidString)",
            "agent_name": "李医生智能体",
            "service_boundary": "仅提供健康信息"
          },
          "professional_directions": ["胸痛评估"],
          "introduction_excerpt": "从事心血管内科临床工作多年。",
          "detail_route": { "agent_id": "\(agentID.uuidString)" }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder.chatRemote.decode(HospitalDoctorIntroCardPayload.self, from: data)
        XCTAssertEqual(decoded.doctor.displayName, "李医生")
        XCTAssertEqual(decoded.agent.agentId, agentID)
        XCTAssertEqual(decoded.professionalDirections, ["胸痛评估"])
        XCTAssertEqual(decoded.detailRoute.agentId, agentID)
    }
}
#endif
