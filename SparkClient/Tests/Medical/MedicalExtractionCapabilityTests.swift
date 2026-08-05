#if canImport(XCTest)
import Foundation
import XCTest

final class MedicalExtractionCapabilityTests: XCTestCase {
    func testTypedMedicalDocumentExtractingDeclaresCapabilityName() {
        XCTAssertEqual(
            (TypedMedicalDocumentExtracting.self as TypedMedicalDocumentExtracting.Type).capabilityName,
            "medical_extraction"
        )
    }

    func testMedicalDocumentTypeResolvingDeclaresCapabilityName() {
        XCTAssertEqual(
            (MedicalDocumentTypeResolving.self as MedicalDocumentTypeResolving.Type).capabilityName,
            "medical_extraction"
        )
    }
}
#endif
