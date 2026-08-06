import Foundation

final class WeatherGateway: @unchecked Sendable {
    private let openWeatherProvider: OpenWeatherProvider
    private let qWeatherProvider: QWeatherProvider
    private let weatherKitProvider: WeatherKitProvider
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.openWeatherProvider = OpenWeatherProvider(session: session)
        self.qWeatherProvider = QWeatherProvider(session: session)
        self.weatherKitProvider = WeatherKitProvider()
    }

    func geocode(keyword: String, config: WeatherRuntimeConfig) async throws -> GeocodeResult {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw WeatherRuntimeError.emptyKeyword }
        switch config.provider {
        case .openWeather:
            return try await openWeatherProvider.geocode(GeocodeQueryRequest(keyword: trimmed, config: config))
        case .qWeather:
            return try await qWeatherProvider.geocode(keyword: trimmed)
        case .weatherKit:
            return try await weatherKitProvider.geocode(keyword: trimmed)
        }
    }

    func queryWeather(
        latitude: Double,
        longitude: Double,
        timeRange: String,
        locationName: String?,
        config: WeatherRuntimeConfig
    ) async throws -> WeatherResult {
        guard latitude.isFinite, longitude.isFinite else {
            throw WeatherRuntimeError.missingCoordinates
        }
        let request = WeatherQueryRequest(
            latitude: latitude,
            longitude: longitude,
            timeRange: timeRange,
            locationName: locationName,
            config: config
        )
        switch config.provider {
        case .openWeather:
            return try await openWeatherProvider.queryWeather(request)
        case .qWeather:
            return try await qWeatherProvider.queryWeather(request)
        case .weatherKit:
            return try await weatherKitProvider.queryWeather(request)
        }
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw WeatherRuntimeError.badHTTPStatus(http.statusCode, body)
        }
    }
}
