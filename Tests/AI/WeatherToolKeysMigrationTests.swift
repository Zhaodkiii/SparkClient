#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class WeatherToolKeysMigrationTests: XCTestCase {
    func testReconcileBackfillsMissingQWeatherAndAppleWeather() {
        let legacy = [
            makeToolKey(company: "OPENWEATHER", name: "OpenWeatherMap", key: "saved-key", requestURL: "api.openweathermap.org", isUsing: true)
        ]

        let reconciled = WeatherToolKeysMigration.reconcile(toolKeys: legacy)
        let weather = reconciled.filter { $0.toolClass == "weather" }

        XCTAssertEqual(weather.count, 3)
        XCTAssertEqual(Set(weather.map(\.company)), Set(["OPENWEATHER", "QWEATHER", "APPLEWEATHER"]))
        XCTAssertEqual(weather.first(where: { $0.company == "OPENWEATHER" })?.key, "saved-key")
        XCTAssertTrue(weather.first(where: { $0.company == "QWEATHER" })?.isUsing == false)
        XCTAssertTrue(weather.first(where: { $0.company == "APPLEWEATHER" })?.isUsing == false)
    }

    func testReconcileMergesWeatherKitIntoAppleWeatherWithoutLosingKey() {
        let legacy = [
            makeToolKey(company: "WEATHERKIT", name: "Apple Weather", key: "", requestURL: "", isUsing: true),
            makeToolKey(company: "APPLEWEATHER", name: "APPLEWEATHER_KEY", key: "", requestURL: "", isUsing: false)
        ]

        let reconciled = WeatherToolKeysMigration.reconcile(toolKeys: legacy)
        let appleRows = reconciled.filter { WeatherToolKeysMigration.canonicalCompany($0.company) == "APPLEWEATHER" }

        XCTAssertEqual(appleRows.count, 1)
        XCTAssertEqual(appleRows.first?.company, "APPLEWEATHER")
    }

    func testReconcileDoesNotOverwriteExistingOpenWeatherCredentials() {
        let legacy = [
            makeToolKey(
                company: "OPENWEATHER",
                name: "OPENWEATHER_KEY",
                key: "user-key",
                requestURL: "https://api.openweathermap.org/data/2.5/weather",
                isUsing: false
            )
        ]

        let reconciled = WeatherToolKeysMigration.reconcile(toolKeys: legacy)
        let openWeather = reconciled.first { $0.company == "OPENWEATHER" }

        XCTAssertEqual(openWeather?.key, "user-key")
        XCTAssertEqual(openWeather?.requestURL, "https://api.openweathermap.org/data/2.5/weather")
    }

    func testCanonicalCompanyAliases() {
        XCTAssertEqual(WeatherToolKeysMigration.canonicalCompany("WEATHERKIT"), "APPLEWEATHER")
        XCTAssertEqual(WeatherToolKeysMigration.canonicalCompany("OpenWeatherMap"), "OPENWEATHER")
        XCTAssertEqual(WeatherToolKeysMigration.canonicalCompany("QWEATHER_KEY"), "QWEATHER")
    }

    private func makeToolKey(
        company: String,
        name: String,
        key: String,
        requestURL: String,
        isUsing: Bool
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
            timestamp: Date()
        )
    }
}
#endif
