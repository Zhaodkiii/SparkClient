#if canImport(XCTest)
import XCTest

final class PendingMemberShareTicketStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PendingMemberShareTicketStore.clearAll()
    }

    override func tearDown() {
        PendingMemberShareTicketStore.clearAll()
        super.tearDown()
    }

    func testConsumeUsesAccountNamespace() {
        PendingMemberShareTicketStore.save("ticket-a", accountID: 10)
        XCTAssertEqual(PendingMemberShareTicketStore.consume(forAccountID: 10), "ticket-a")
        XCTAssertNil(PendingMemberShareTicketStore.consume(forAccountID: 11))
    }

    func testMemoryTicketForPreLoginFlow() {
        PendingMemberShareTicketStore.save("ticket-memory", accountID: nil)
        XCTAssertEqual(PendingMemberShareTicketStore.consume(forAccountID: 42), "ticket-memory")
    }
}
#endif
