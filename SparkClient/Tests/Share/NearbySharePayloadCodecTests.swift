#if canImport(XCTest)
import XCTest

final class NearbySharePayloadCodecTests: XCTestCase {
    func testEncodeDecodeBeacon() throws {
        let beacon = NearbyShareBeacon(
            v: 1,
            mode: NearbyShareBLE.receiveMode,
            sessionId: "abcd1234",
            displayName: "Test Phone"
        )
        let data = try NearbySharePayloadCodec.encodeBeacon(beacon)
        let decoded = try NearbySharePayloadCodec.decodeBeacon(data)
        XCTAssertEqual(decoded, beacon)
    }

    func testDecodeInboundRequiresTicket() {
        let json = """
        {"v":1,"type":"member_share","ticket":"","member":{"id":1,"name":"A","gender":"male"},"inviter":{"display_name":"B"}}
        """
        XCTAssertThrowsError(try NearbySharePayloadCodec.decodeInbound(Data(json.utf8)))
    }

    func testOutboundPayloadRespectsSizeLimit() throws {
        let member = Member(id: 1, name: String(repeating: "张", count: 400), gender: "male")
        let outbound = NearbySharePayloadCodec.makeOutboundPayload(
            ticket: String(repeating: "x", count: 900),
            member: member,
            inviterDisplayName: "Inviter"
        )
        XCTAssertThrowsError(try NearbySharePayloadCodec.encodeOutbound(outbound))
    }

    func testMakeOutboundPayloadRoundTrip() throws {
        let member = Member(id: 12, name: "张三", gender: "male", birthDate: nil)
        let outbound = NearbySharePayloadCodec.makeOutboundPayload(
            ticket: "signed.ticket",
            member: member,
            inviterDisplayName: "华"
        )
        let data = try NearbySharePayloadCodec.encodeOutbound(outbound)
        let inbound = try NearbySharePayloadCodec.decodeInbound(data)
        XCTAssertEqual(inbound.ticket, "signed.ticket")
        XCTAssertEqual(inbound.member.name, "张三")
        XCTAssertEqual(inbound.inviter.displayName, "华")
    }
}
#endif
