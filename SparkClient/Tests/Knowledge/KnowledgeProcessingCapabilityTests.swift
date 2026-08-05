#if canImport(XCTest)
import Foundation
import XCTest

final class KnowledgeProcessingCapabilityTests: XCTestCase {
    func testPolishKnowledgeTextUseCaseDeclaresCapabilityName() {
        XCTAssertEqual(PolishKnowledgeTextUseCase.capabilityName, "knowledge_processing")
    }

    func testTranslateKnowledgeTextUseCaseDeclaresCapabilityName() {
        XCTAssertEqual(TranslateKnowledgeTextUseCase.capabilityName, "knowledge_processing")
    }

    func testAutoFillAgentPromptUseCaseDeclaresCapabilityName() {
        XCTAssertEqual(AutoFillAgentPromptUseCase.capabilityName, "knowledge_processing")
    }

    func testOCRKnowledgeImageUseCaseDoesNotDeclareKnowledgeProcessingCapability() {
        XCTAssertFalse(OCRKnowledgeImageUseCase.self is KnowledgeProcessingCapability.Type)
    }
}
#endif
