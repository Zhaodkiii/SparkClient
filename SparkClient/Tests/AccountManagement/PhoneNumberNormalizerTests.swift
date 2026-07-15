#if canImport(XCTest)
import XCTest

final class PhoneNumberNormalizerTests: XCTestCase {
    private let dials = ["+86", "+852", "+886", "+1", "+81", "+44"]

    func testNormalizeLocalCNNumber() {
        let result = PhoneNumberNormalizer.normalize(rawInput: "15385056020", defaultDial: "+86")
        XCTAssertEqual(result.e164, "+8615385056020")
        XCTAssertEqual(result.nationalDigits, "15385056020")
    }

    func testNormalizePlusPrefixedInternational() {
        let result = PhoneNumberNormalizer.normalize(rawInput: "+8615385056020", defaultDial: "+86")
        XCTAssertEqual(result.e164, "+8615385056020")
        XCTAssertEqual(result.nationalDigits, "15385056020")
    }

    func testNormalizeZeroZeroPrefixedInternational() {
        let result = PhoneNumberNormalizer.normalize(rawInput: "008615385056020", defaultDial: "+86")
        XCTAssertEqual(result.e164, "+8615385056020")
        XCTAssertEqual(result.nationalDigits, "15385056020")
    }

    func testNormalizeBareCountryCodePrefix() {
        let result = PhoneNumberNormalizer.normalize(rawInput: "8615385056020", defaultDial: "+86")
        XCTAssertEqual(result.e164, "+8615385056020")
        XCTAssertEqual(result.nationalDigits, "15385056020")
    }

    func testDetectRegionFromPlusPrefixed() {
        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: "+8615385056020",
            supportedDials: dials
        )
        XCTAssertEqual(detected?.dial, "+86")
        XCTAssertEqual(detected?.nationalDigits, "15385056020")
    }

    func testDetectRegionFromZeroZeroPrefixed() {
        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: "008615385056020",
            supportedDials: dials
        )
        XCTAssertEqual(detected?.dial, "+86")
        XCTAssertEqual(detected?.nationalDigits, "15385056020")
    }

    func testDetectRegionFromBareCountryCode() {
        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: "8615385056020",
            supportedDials: dials
        )
        XCTAssertEqual(detected?.dial, "+86")
        XCTAssertEqual(detected?.nationalDigits, "15385056020")
    }

    func testDetectRegionPrefersLongestDial() {
        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: "+85291234567",
            supportedDials: dials
        )
        XCTAssertEqual(detected?.dial, "+852")
        XCTAssertEqual(detected?.nationalDigits, "91234567")
    }

    func testDetectRegionHandlesFormattedInput() {
        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: "+86 153 8505 6020",
            supportedDials: dials
        )
        XCTAssertEqual(detected?.dial, "+86")
        XCTAssertEqual(detected?.nationalDigits, "15385056020")
    }

    func testLockedPhoneTargetMaskedDisplay() {
        let locked = LockedPhoneTarget(
            countryCode: "+86",
            nationalNumber: "15385056020",
            e164: "+8615385056020"
        )
        XCTAssertEqual(locked.maskedDisplayValue, "+86 153****20")
        XCTAssertEqual(locked.displayValue, "+86 15385056020")
    }

    func testTargetSnapshotUsesFrozenE164() {
        let locked = LockedPhoneTarget(
            countryCode: "+86",
            nationalNumber: "15385056020",
            e164: "+8615385056020"
        )
        let snapshot = AccountIdentityTargetSnapshot.phone(locked)
        XCTAssertEqual(snapshot.rawTarget, "+8615385056020")
        XCTAssertEqual(snapshot.displayValue, "+86 153****20")
    }
}
#endif
