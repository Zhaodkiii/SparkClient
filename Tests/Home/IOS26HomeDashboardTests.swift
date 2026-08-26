#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class ChatQuickStartModeTests: XCTestCase {
    func testTitleAndDraftForCheckupPlan() {
        let mode = ChatQuickStartMode.checkupPlan
        XCTAssertEqual(mode.rawValue, "checkup_plan")
        XCTAssertFalse(mode.title.isEmpty)
        XCTAssertFalse(mode.initialDraft.isEmpty)
    }

    func testTitleAndDraftForReportInterpretation() {
        let mode = ChatQuickStartMode.reportInterpretation
        XCTAssertEqual(mode.rawValue, "report_interpretation")
        XCTAssertFalse(mode.title.isEmpty)
        XCTAssertFalse(mode.initialDraft.isEmpty)
    }
}

final class HomeQuickStartConversationTargetTests: XCTestCase {
    @MainActor
    func testLegacyStoredRawValueFallsBackToChat() {
        let suite = "HomeQuickStartConversationTargetTests.legacy"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("deepTutorChat", forKey: "home.quick_start_conversation_target")
        let store = HomeQuickStartConversationPreferenceStore(defaults: defaults)
        XCTAssertEqual(store.target, .chat)
    }

    @MainActor
    func testMissingValueDefaultsToChat() {
        let suite = "HomeQuickStartConversationTargetTests.missing"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HomeQuickStartConversationPreferenceStore(defaults: defaults)
        XCTAssertEqual(store.target, .chat)
    }
}
#endif