#if canImport(XCTest)
import XCTest

final class MemberShareDeepLinkParserTests: XCTestCase {
    func testTicketFromSparkDeepLink() {
        let url = URL(string: "spark://member-share?ticket=abc.signed.payload")!
        XCTAssertEqual(MemberShareDeepLinkParser.ticket(from: url), "abc.signed.payload")
    }

    func testTicketFromRawDeepLinkText() {
        let raw = "spark://member-share?ticket=ticket-value-123"
        XCTAssertEqual(MemberShareDeepLinkParser.ticket(fromRaw: raw), "ticket-value-123")
    }

    func testTicketFromSignedPrefix() {
        let raw = "spark_member_share.eyJ0ZXN0In0"
        XCTAssertEqual(MemberShareDeepLinkParser.ticket(fromRaw: raw), raw)
    }

    func testRejectsGenericLongString() {
        let raw = String(repeating: "x", count: 32)
        XCTAssertNil(MemberShareDeepLinkParser.ticket(fromRaw: raw))
    }

    func testRejectsNonSparkURL() {
        let raw = "https://example.com/member-share?ticket=abc"
        XCTAssertNil(MemberShareDeepLinkParser.ticket(fromRaw: raw))
    }
}
#endif
