#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class DeepTutorQuickStartModeTests: XCTestCase {
    func testTitleAndDraftForCheckupPlan() {
        let mode = DeepTutorQuickStartMode.checkupPlan
        XCTAssertEqual(mode.rawValue, "checkup_plan")
        XCTAssertFalse(mode.title.isEmpty)
        XCTAssertFalse(mode.initialDraft.isEmpty)
    }

    func testTitleAndDraftForReportInterpretation() {
        let mode = DeepTutorQuickStartMode.reportInterpretation
        XCTAssertEqual(mode.rawValue, "report_interpretation")
        XCTAssertFalse(mode.title.isEmpty)
        XCTAssertFalse(mode.initialDraft.isEmpty)
    }
}
#endif
