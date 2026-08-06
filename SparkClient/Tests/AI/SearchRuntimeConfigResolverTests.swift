#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class SearchRuntimeConfigResolverTests: XCTestCase {
    func testResolveThrowsWhenSearchDisabled() {
        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = false
        snapshot.searchKeys = [makeSearchKey(company: "TAVILY", isUsing: true, key: "test-key")]

        XCTAssertThrowsError(try SearchRuntimeConfigResolver.resolve(from: snapshot)) { error in
            XCTAssertTrue(error is SearchRuntimeError)
            if case .disabled = error as? SearchRuntimeError {
                return
            }
            XCTFail("Expected disabled, got \(error)")
        }
    }

    func testResolvePrefersHigherPriorityProvider() throws {
        let lowPriority = makeSearchKey(
            company: "BRAVE",
            isUsing: true,
            key: "brave-key",
            priority: 1,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let highPriority = makeSearchKey(
            company: "TAVILY",
            isUsing: true,
            key: "tavily-key",
            priority: 10,
            timestamp: Date(timeIntervalSince1970: 50)
        )

        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [lowPriority, highPriority]

        let config = try SearchRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(config.provider, .tavily)
        XCTAssertEqual(config.rawKeyID, highPriority.id)
    }

    func testResolveUsesNewerTimestampWhenPriorityTied() throws {
        let older = makeSearchKey(
            company: "BRAVE",
            isUsing: true,
            key: "brave-key",
            priority: 5,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let newer = makeSearchKey(
            company: "TAVILY",
            isUsing: true,
            key: "tavily-key",
            priority: 5,
            timestamp: Date(timeIntervalSince1970: 200)
        )

        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [older, newer]

        let config = try SearchRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(config.provider, .tavily)
        XCTAssertEqual(config.rawKeyID, newer.id)
    }

    func testResolveThrowsWhenAPIKeyMissingForNonSparkProvider() {
        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [makeSearchKey(company: "TAVILY", isUsing: true, key: "")]

        XCTAssertThrowsError(try SearchRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .missingAPIKey = error as? SearchRuntimeError else {
                return XCTFail("Expected missingAPIKey, got \(error)")
            }
        }
    }

    func testResolveThrowsForUnknownCompanyInsteadOfFallingBackToSpark() {
        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [makeSearchKey(company: "DUCKDUCKGO", isUsing: true, key: "key")]

        XCTAssertThrowsError(try SearchRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .unsupportedProvider(let provider) = error as? SearchRuntimeError else {
                return XCTFail("Expected unsupportedProvider, got \(error)")
            }
            XCTAssertEqual(provider, "DUCKDUCKGO")
        }
    }

    func testResolveThrowsForSparkWithoutLocalAdapter() {
        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [makeSearchKey(company: "SPARK", isUsing: true, key: "")]

        XCTAssertThrowsError(try SearchRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .unsupportedProvider(let provider) = error as? SearchRuntimeError else {
                return XCTFail("Expected unsupportedProvider, got \(error)")
            }
            XCTAssertEqual(provider, "SPARK")
        }
    }

    func testActiveWebSearchKeyMatchesResolverSelection() throws {
        let selected = makeSearchKey(
            company: "EXA",
            isUsing: true,
            key: "exa-key",
            priority: 8,
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let other = makeSearchKey(
            company: "BRAVE",
            isUsing: true,
            key: "brave-key",
            priority: 2,
            timestamp: Date(timeIntervalSince1970: 400)
        )

        var snapshot = AISettingsSnapshot.default
        snapshot.searchToolPreferences.useSearch = true
        snapshot.searchKeys = [other, selected]

        let active = SearchRuntimeConfigResolver.activeWebSearchKey(from: snapshot)
        let config = try SearchRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(active?.id, selected.id)
        XCTAssertEqual(config.rawKeyID, selected.id)
    }

    private func makeSearchKey(
        company: String,
        isUsing: Bool,
        key: String,
        priority: Int = 0,
        timestamp: Date = Date()
    ) -> SearchKeys {
        SearchKeys(
            name: company,
            company: company,
            key: key,
            requestURL: "https://example.com/search",
            isUsing: isUsing,
            searchClass: "web",
            help: "",
            source: .custom,
            timestamp: timestamp,
            priority: priority
        )
    }
}
#endif
