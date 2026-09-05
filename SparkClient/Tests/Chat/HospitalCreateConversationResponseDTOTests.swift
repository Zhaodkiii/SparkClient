#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

final class HospitalCreateConversationResponseDTOTests: XCTestCase {
    func testLegacySnapshotDecodesWithoutThreadOrInitialMessages() throws {
        let threadID = UUID()
        let agentID = UUID()
        let json = """
        {
          "thread_id": "\(threadID.uuidString)",
          "conversation": {
            "thread_id": "\(threadID.uuidString)",
            "agent": { "id": "\(agentID.uuidString)", "name": "智能体", "publication_status": "published" },
            "member_id": 7
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.chatRemote.decode(HospitalCreateConversationResponseDTO.self, from: json)
        XCTAssertEqual(decoded.threadId, threadID)
        XCTAssertNil(decoded.thread)
        XCTAssertTrue(decoded.initialMessages.isEmpty)
        XCTAssertEqual(decoded.conversation.agent.id, agentID)
    }
}
#endif
