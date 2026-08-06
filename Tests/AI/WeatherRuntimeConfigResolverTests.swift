#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class WeatherRuntimeConfigResolverTests: XCTestCase {
    func testResolveThrowsWhenWeatherDisabled() {
        var snapshot = AISettingsSnapshot.default
        snapshot.weatherToolPreferences.useWeather = false
        snapshot.toolKeys = [makeWeatherKey(company: "OPENWEATHER", isUsing: true, key: "test-key")]

        XCTAssertThrowsError(try WeatherRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .disabled = error as? WeatherRuntimeError else {
                return XCTFail("Expected disabled, got \(error)")
            }
        }
    }

    func testResolveThrowsWhenNoActiveProvider() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [makeWeatherKey(company: "OPENWEATHER", isUsing: false, key: "test-key")]

        XCTAssertThrowsError(try WeatherRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .missingActiveProvider = error as? WeatherRuntimeError else {
                return XCTFail("Expected missingActiveProvider, got \(error)")
            }
        }
    }

    func testResolveReturnsOpenWeatherConfig() throws {
        let active = makeWeatherKey(company: "OPENWEATHER", isUsing: true, key: "owm-key")
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [active]

        let config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(config.provider, .openWeather)
        XCTAssertEqual(config.rawKeyID, active.id)
        XCTAssertEqual(config.apiKey, "owm-key")
    }

    func testResolveThrowsWhenAPIKeyMissing() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [makeWeatherKey(company: "OPENWEATHER", isUsing: true, key: "")]

        XCTAssertThrowsError(try WeatherRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .missingAPIKey = error as? WeatherRuntimeError else {
                return XCTFail("Expected missingAPIKey, got \(error)")
            }
        }
    }

    func testResolveThrowsForInvalidEndpoint() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [
            makeWeatherKey(
                company: "OPENWEATHER",
                isUsing: true,
                key: "owm-key",
                requestURL: "not-a-valid-url"
            )
        ]

        XCTAssertThrowsError(try WeatherRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .invalidEndpoint = error as? WeatherRuntimeError else {
                return XCTFail("Expected invalidEndpoint, got \(error)")
            }
        }
    }

    func testResolveReturnsOpenWeatherConfigWithHostEndpoint() throws {
        let active = makeWeatherKey(
            company: "OPENWEATHER",
            isUsing: true,
            key: "owm-key",
            requestURL: "api.openweathermap.org"
        )
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [active]

        let config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(config.provider, .openWeather)
        XCTAssertEqual(config.requestURL.host, "api.openweathermap.org")
    }

    func testResolveReturnsQWeatherConfigWithEmptyEndpoint() throws {
        let active = makeWeatherKey(
            company: "QWEATHER",
            name: "QWEATHER_KEY",
            isUsing: true,
            key: "qw-key",
            requestURL: ""
        )
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [active]

        let config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(config.provider, .qWeather)
        XCTAssertEqual(config.requestURL.host, "devapi.qweather.com")
    }

    func testResolveThrowsForQWeatherWithoutAPIKey() {
        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [
            makeWeatherKey(
                company: "QWEATHER",
                name: "QWEATHER_KEY",
                isUsing: true,
                key: "",
                requestURL: ""
            )
        ]

        XCTAssertThrowsError(try WeatherRuntimeConfigResolver.resolve(from: snapshot)) { error in
            guard case .missingAPIKey = error as? WeatherRuntimeError else {
                return XCTFail("Expected missingAPIKey, got \(error)")
            }
        }
    }

    func testResolveReturnsWeatherKitConfigWithoutAPIKey() throws {
        if #available(iOS 16.0, *) {
            let active = makeWeatherKey(
                company: "APPLEWEATHER",
                name: "APPLEWEATHER_KEY",
                isUsing: true,
                key: "",
                requestURL: ""
            )
            var snapshot = AISettingsSnapshot.default
            snapshot.toolKeys = [active]

            let config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
            XCTAssertEqual(config.provider, .weatherKit)
            XCTAssertEqual(config.apiKey, "")
            XCTAssertEqual(config.rawKeyID, active.id)
        }
    }

    func testParseAppleWeatherAlias() {
        XCTAssertEqual(WeatherProviderID.parse(company: "APPLEWEATHER"), .weatherKit)
    }

    func testActiveWeatherKeyMatchesResolverSelection() throws {
        let selected = makeWeatherKey(
            company: "OPENWEATHER",
            isUsing: true,
            key: "selected-key",
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let other = makeWeatherKey(
            company: "OPENWEATHER",
            isUsing: true,
            key: "other-key",
            timestamp: Date(timeIntervalSince1970: 100)
        )

        var snapshot = AISettingsSnapshot.default
        snapshot.toolKeys = [other, selected]

        let active = WeatherRuntimeConfigResolver.activeWeatherKey(from: snapshot)
        let config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
        XCTAssertEqual(active?.id, selected.id)
        XCTAssertEqual(config.rawKeyID, selected.id)
    }

    func testWeatherConfigRevisionIncrementsWhenToolKeyChanges() {
        var snapshot = AISettingsSnapshot.default
        let initialRevision = snapshot.weatherConfigRevision.localRevision

        snapshot.toolKeys = [makeWeatherKey(company: "OPENWEATHER", isUsing: true, key: "new-key")]
        snapshot.refreshWeatherConfigRevision(previous: AISettingsSnapshot.default)

        XCTAssertGreaterThan(snapshot.weatherConfigRevision.localRevision, initialRevision)
    }

    func testNormalizeWeatherProviderSelectionKeepsOnlyLatestActive() {
        var snapshot = AISettingsSnapshot.default
        let older = makeWeatherKey(
            company: "OPENWEATHER",
            isUsing: true,
            key: "older",
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let newer = makeWeatherKey(
            company: "OPENWEATHER",
            isUsing: true,
            key: "newer",
            timestamp: Date(timeIntervalSince1970: 300)
        )
        snapshot.toolKeys = [older, newer]

        snapshot.normalizeWeatherProviderSelection()

        XCTAssertFalse(snapshot.toolKeys.first(where: { $0.id == older.id })?.isUsing ?? true)
        XCTAssertTrue(snapshot.toolKeys.first(where: { $0.id == newer.id })?.isUsing ?? false)
    }

    private func makeWeatherKey(
        company: String,
        name: String = company,
        isUsing: Bool,
        key: String,
        requestURL: String = "api.openweathermap.org",
        timestamp: Date = Date()
    ) -> ToolKeys {
        ToolKeys(
            name: name,
            company: company,
            key: key,
            requestURL: requestURL,
            isUsing: isUsing,
            toolClass: "weather",
            help: "",
            source: .custom,
            timestamp: timestamp
        )
    }
}
#endif
