#if canImport(XCTest)
import Foundation
import XCTest

final class ChatHospitalSystemMessageSupportTests: XCTestCase {
    func testShouldRenderCenteredTipForDoctorTakeoverText() {
        let message = makeSystemTextMessage("夏文生已接管本次会话")
        XCTAssertTrue(ChatHospitalSystemMessageSupport.shouldRenderCenteredTip(for: message))
        XCTAssertEqual(
            ChatHospitalSystemMessageSupport.displayText(for: message),
            "系统提示：夏文生已接管本次会话"
        )
    }

    func testShouldNotRenderCenteredTipForIntroCardOnlySystemMessage() {
        let message = ChatMessage(
            threadID: UUID(),
            role: .system,
            blocks: [
                ChatMessageBlock.fromPayload(
                    .hospitalDoctorIntroCard(makeIntroPayload()),
                    id: UUID(),
                    orderKey: 0
                )
            ],
            clientMessageID: UUID(),
            deliveryState: .sent,
            createdAt: Date(),
            sender: ChatMessageSender(actorType: .system)
        )
        XCTAssertFalse(ChatHospitalSystemMessageSupport.shouldRenderCenteredTip(for: message))
    }

    func testShouldNotRenderCenteredTipForGuideCardSystemMessage() {
        let message = ChatGuideSystemMessageFactory.make(
            threadID: UUID(),
            payload: ChatGuideCardPreviewFixtures.emptyPayload
        )
        XCTAssertFalse(ChatHospitalSystemMessageSupport.shouldRenderCenteredTip(for: message))
    }

    func testDisplayTextDoesNotDuplicatePrefix() {
        let message = makeSystemTextMessage("系统提示：医生已取消接管")
        XCTAssertEqual(
            ChatHospitalSystemMessageSupport.displayText(for: message),
            "系统提示：医生已取消接管"
        )
    }

    private func makeSystemTextMessage(_ text: String) -> ChatMessage {
        let messageID = UUID()
        let block = ChatMessageBlock.fromPayload(
            .text(text),
            id: UUID(),
            orderKey: 0
        )
        return ChatMessage(
            threadID: UUID(),
            role: .system,
            blocks: [block],
            clientMessageID: messageID,
            deliveryState: .sent,
            createdAt: Date(),
            sender: ChatMessageSender(actorType: .system, displayName: "系统")
        )
    }

    private func makeIntroPayload() -> HospitalDoctorIntroCardPayload {
        HospitalDoctorIntroCardPayload(
            doctor: .init(
                displayName: "夏文生",
                title: "主任医师",
                hospitalName: "示例医院",
                departmentName: "内科",
                avatarUrl: ""
            ),
            agent: .init(
                agentId: UUID(),
                agentName: "夏文生智能体",
                serviceBoundary: "仅健康咨询"
            ),
            professionalDirections: ["慢病管理"],
            introductionExcerpt: "简介",
            detailRoute: .init(agentId: UUID())
        )
    }
}
#endif
