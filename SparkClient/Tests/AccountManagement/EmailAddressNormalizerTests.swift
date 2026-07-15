#if canImport(XCTest)
import XCTest

final class EmailAddressNormalizerTests: XCTestCase {
    private let knownDomains = ["@qq.com", "@163.com", "@gmail.com", "@icloud.com"]

    func testParseKnownDomainEmail() {
        let parsed = EmailAddressNormalizer.parseFullEmail("hua@qq.com", knownDomains: knownDomains)
        XCTAssertEqual(parsed?.localPart, "hua")
        XCTAssertEqual(parsed?.domain, "@qq.com")
        XCTAssertEqual(parsed?.normalizedEmail, "hua@qq.com")
        XCTAssertEqual(parsed?.isKnownDomain, true)
    }

    func testParseCustomDomainEmail() {
        let parsed = EmailAddressNormalizer.parseFullEmail("hua@company.com", knownDomains: knownDomains)
        XCTAssertEqual(parsed?.localPart, "hua")
        XCTAssertEqual(parsed?.domain, "@company.com")
        XCTAssertEqual(parsed?.normalizedEmail, "hua@company.com")
        XCTAssertEqual(parsed?.isKnownDomain, false)
    }

    func testParseFullEmailTrimsWhitespaceAndNormalizesCase() {
        let parsed = EmailAddressNormalizer.parseFullEmail(" Hua＠QQ.COM ", knownDomains: knownDomains)
        XCTAssertEqual(parsed?.localPart, "hua")
        XCTAssertEqual(parsed?.domain, "@qq.com")
        XCTAssertEqual(parsed?.normalizedEmail, "hua@qq.com")
    }

    func testNormalizeDomainAddsAtSignAndLowercases() {
        XCTAssertEqual(EmailAddressNormalizer.normalizeDomain("QQ.COM"), "@qq.com")
        XCTAssertEqual(EmailAddressNormalizer.normalizeDomain("@ICLOUD.COM"), "@icloud.com")
    }

    func testValidateRequiresLocalPart() {
        XCTAssertEqual(
            EmailAddressNormalizer.validate(localPart: "", domain: "@qq.com"),
            .localRequired
        )
    }

    func testValidateRequiresDomain() {
        XCTAssertEqual(
            EmailAddressNormalizer.validate(localPart: "hua", domain: ""),
            .domainRequired
        )
    }

    func testValidateRejectsInvalidDomain() {
        XCTAssertEqual(
            EmailAddressNormalizer.validate(localPart: "hua", domain: "@qq"),
            .domainInvalid
        )
    }

    func testNormalizeBuildsLowercasedEmail() {
        XCTAssertEqual(
            EmailAddressNormalizer.normalize(localPart: "Hua", domain: "@QQ.COM"),
            "hua@qq.com"
        )
    }

    func testLockedEmailTargetSnapshotUsesFrozenEmail() {
        let locked = LockedEmailTarget(email: "hua@qq.com")
        let snapshot = AccountIdentityTargetSnapshot.email(locked)
        XCTAssertEqual(snapshot.rawTarget, "hua@qq.com")
        XCTAssertEqual(snapshot.displayValue, "hua@qq.com")
    }
}
#endif
