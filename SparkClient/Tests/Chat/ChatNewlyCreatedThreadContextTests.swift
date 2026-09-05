#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

@MainActor
final class ChatHospitalInitialMessagesStoreTests: XCTestCase {
    func testHospitalMessagesAreTakenOnce() {
        let store = ChatStateStore()
        let threadID = UUID()
        let message = ChatMessage(threadID: threadID, role: .system, blocks: [])
        store.rememberHospitalInitialMessages([message], for: threadID)

        XCTAssertEqual(
            store.takeHospitalInitialMessages(for: threadID)?.map(\.clientMessageID),
            [message.clientMessageID]
        )
        XCTAssertNil(store.takeHospitalInitialMessages(for: threadID))
    }

    func testHospitalMessagesDoNotMarkOrdinaryNewThread() {
        let store = ChatStateStore()
        let ordinaryID = UUID()
        let hospitalID = UUID()
        store.markThreadAsNewlyCreated(ordinaryID)
        store.rememberHospitalInitialMessages(
            [ChatMessage(threadID: hospitalID, role: .system, blocks: [])],
            for: hospitalID
        )

        XCTAssertTrue(store.isThreadMarkedAsNewlyCreated(ordinaryID))
        XCTAssertFalse(store.isThreadMarkedAsNewlyCreated(hospitalID))
        XCTAssertNotNil(store.takeHospitalInitialMessages(for: hospitalID))
        XCTAssertTrue(store.isThreadMarkedAsNewlyCreated(ordinaryID))
    }
}
#endif
