#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class ChatConsultationCardPayloadCodableTests: XCTestCase {
    func testConsultationCardRoundTripThroughChatRemotePayload() throws {
        let payload = HospitalConsultationDTO(
            consultationId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            consultNo: "C202509060001",
            threadId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            hospital: HospitalPublicDTO(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                code: "H001",
                name: "示例医院",
                shortName: "示例",
                introduction: nil,
                status: "active"
            ),
            department: HospitalDepartmentPublicDTO(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "心内科",
                sortOrder: 1
            ),
            doctor: HospitalDoctorPublicDTO(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                displayName: "张医生",
                title: "主任医师",
                specialties: ["心血管"],
                introduction: nil,
                avatarUrl: nil
            ),
            agent: HospitalConversationAgentDTO(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                name: "张医生智能体",
                publicationStatus: "published"
            ),
            memberId: 42,
            chiefComplaint: "最近胸口闷",
            orderItems: ["复诊开药"],
            pastHistory: "高血压",
            familyHistory: nil,
            allergyHistory: "青霉素",
            serviceStatus: "pending_doctor",
            submittedAt: Date(timeIntervalSince1970: 1_725_600_000),
            attachmentCount: 2,
            attachments: [
                ChatAttachment(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    type: .image,
                    url: URL(string: "https://cdn.example.test/chest.jpg"),
                    fileId: 12,
                    fullCacheKey: "77777777-7777-7777-7777-777777777777/chest.jpg"
                ),
                ChatAttachment(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    type: .pdf,
                    url: URL(string: "https://cdn.example.test/report.pdf"),
                    fileId: 13,
                    fullCacheKey: "88888888-8888-8888-8888-888888888888/report.pdf"
                ),
            ]
        )

        let block = ChatMessageBlock.fromPayload(
            .consultationCard(payload),
            id: ChatStableBlockID.rich(messageID: UUID(), kind: .consultationCard),
            orderKey: 1000
        )

        let data = try JSONEncoder.chatRemote.encode(block)
        let decoded = try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)

        XCTAssertEqual(decoded.kind, .consultationCard)
        if case .consultationCard(let decodedPayload) = decoded.payload {
            XCTAssertEqual(decodedPayload.consultNo, payload.consultNo)
            XCTAssertEqual(decodedPayload.chiefComplaint, payload.chiefComplaint)
            XCTAssertEqual(decodedPayload.attachmentCount, payload.attachmentCount)
            XCTAssertEqual(decodedPayload.imageAttachments.count, 1)
            XCTAssertEqual(decodedPayload.fileAttachments.count, 1)
        } else {
            XCTFail("Expected consultationCard payload after chatRemote round-trip")
        }
    }
}
#endif
