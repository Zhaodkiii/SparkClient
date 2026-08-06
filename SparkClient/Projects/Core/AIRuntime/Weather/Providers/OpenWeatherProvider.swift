import Foundation

struct OpenWeatherProvider: Sendable {
    let session: URLSession

    func geocode(_ request: GeocodeQueryRequest) async throws -> GeocodeResult {
        let keyword = request.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { throw WeatherRuntimeError.emptyKeyword }

        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(base)/geo/1.0/direct")
        components?.queryItems = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "appid", value: request.config.apiKey)
        ]
        guard let url = components?.url else {
            throw WeatherRuntimeError.invalidEndpoint("\(base)/geo/1.0/direct")
        }

        let (data, response) = try await session.data(from: url)
        try WeatherGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode([GeocodeResponseItem].self, from: data)
        guard let first = decoded.first else {
            throw WeatherRuntimeError.locationNotFound(keyword)
        }
        return GeocodeResult(
            name: first.localName ?? first.name,
            latitude: first.lat,
            longitude: first.lon,
            country: first.country,
            state: first.state
        )
    }

    func queryWeather(_ request: WeatherQueryRequest) async throws -> WeatherResult {
        let normalizedRange = WeatherEndpointNormalizer.normalizedTimeRange(request.timeRange)
        switch normalizedRange {
        case "now":
            return try await queryCurrentWeather(request)
        case "tomorrow":
            return try await queryForecast(request: request, dayOffset: 1)
        case "3d", "7d", "10d", "15d", "30d":
            return try await queryDailyForecast(request: request, timeRange: normalizedRange)
        default:
            return try await queryCurrentWeather(request)
        }
    }

    private func queryCurrentWeather(_ request: WeatherQueryRequest) async throws -> WeatherResult {
        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let langParam = isChinese ? "zh_cn" : "en"
        var components = URLComponents(string: "\(base)/data/2.5/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(request.latitude)),
            URLQueryItem(name: "lon", value: String(request.longitude)),
            URLQueryItem(name: "appid", value: request.config.apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: langParam)
        ]
        guard let url = components?.url else {
            throw WeatherRuntimeError.invalidEndpoint("\(base)/data/2.5/weather")
        }

        let (data, response) = try await session.data(from: url)
        try WeatherGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(CurrentWeatherResponse.self, from: data)
        let locationName = request.locationName
            ?? decoded.name
            ?? String(format: "%.2f, %.2f", request.latitude, request.longitude)
        return WeatherResult(
            providerName: request.config.displayName,
            locationName: locationName,
            latitude: request.latitude,
            longitude: request.longitude,
            timeRange: request.timeRange,
            observedAt: decoded.dt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            temperatureC: decoded.main?.temp,
            feelsLikeC: decoded.main?.feelsLike,
            condition: decoded.weather?.first?.description ?? "未知",
            humidityPercent: decoded.main?.humidity,
            windSpeedMS: decoded.wind?.speed,
            windDirectionDeg: decoded.wind?.deg,
            precipitationProbabilityPercent: decoded.rain?.oneHour.map { Int(($0 * 10).rounded()) },
            revision: request.config.revision
        )
    }

    private func queryForecast(request: WeatherQueryRequest, dayOffset: Int) async throws -> WeatherResult {
        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let langParam = isChinese ? "zh_cn" : "en"
        var components = URLComponents(string: "\(base)/data/2.5/forecast")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(request.latitude)),
            URLQueryItem(name: "lon", value: String(request.longitude)),
            URLQueryItem(name: "appid", value: request.config.apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: langParam)
        ]
        guard let url = components?.url else {
            throw WeatherRuntimeError.invalidEndpoint("\(base)/data/2.5/forecast")
        }

        let (data, response) = try await session.data(from: url)
        try WeatherGateway.validate(response: response, data: data)
        let decoded = try JSONDecoder.default.decode(ForecastResponse.self, from: data)
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
        let targetItems = (decoded.list ?? []).filter { item in
            guard let timestamp = item.dt else { return false }
            return calendar.isDate(Date(timeIntervalSince1970: TimeInterval(timestamp)), inSameDayAs: targetDay)
        }
        guard let representative = targetItems.first ?? decoded.list?.first else {
            throw WeatherRuntimeError.invalidResponse(request.config.displayName)
        }

        let popValues = targetItems.compactMap(\.pop)
        let averagePop = popValues.isEmpty ? (representative.pop ?? 0) : popValues.reduce(0, +) / Double(popValues.count)
        let locationName = request.locationName
            ?? decoded.city?.name
            ?? String(format: "%.2f, %.2f", request.latitude, request.longitude)

        return WeatherResult(
            providerName: request.config.displayName,
            locationName: locationName,
            latitude: request.latitude,
            longitude: request.longitude,
            timeRange: request.timeRange,
            observedAt: representative.dt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            temperatureC: representative.main?.temp,
            feelsLikeC: representative.main?.feelsLike,
            condition: representative.weather?.first?.description ?? "未知",
            humidityPercent: representative.main?.humidity,
            windSpeedMS: representative.wind?.speed,
            windDirectionDeg: representative.wind?.deg,
            precipitationProbabilityPercent: Int((averagePop * 100).rounded()),
            revision: request.config.revision
        )
    }

    private func queryDailyForecast(request: WeatherQueryRequest, timeRange: String) async throws -> WeatherResult {
        let base = request.config.requestURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let langParam = isChinese ? "zh_cn" : "en"
        let cnt: Int = {
            switch timeRange {
            case "3d": return 3
            case "7d": return 7
            case "10d": return 10
            default: return 15
            }
        }()
        var components = URLComponents(string: "\(base)/data/2.5/forecast/daily")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(request.latitude)),
            URLQueryItem(name: "lon", value: String(request.longitude)),
            URLQueryItem(name: "appid", value: request.config.apiKey),
            URLQueryItem(name: "cnt", value: String(cnt)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: langParam)
        ]
        guard let url = components?.url else {
            throw WeatherRuntimeError.invalidEndpoint("\(base)/data/2.5/forecast/daily")
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw WeatherRuntimeError.badHTTPStatus(401, "subscription required")
        }
        try WeatherGateway.validate(response: response, data: data)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = dict["list"] as? [[String: Any]],
              let first = list.first else {
            throw WeatherRuntimeError.invalidResponse(request.config.displayName)
        }

        let temp = first["temp"] as? [String: Any]
        let maxT = temp?["max"] as? Double
        let minT = temp?["min"] as? Double
        let weatherArr = first["weather"] as? [[String: Any]]
        let desc = weatherArr?.first?["description"] as? String ?? "未知"
        let dt = first["dt"] as? TimeInterval
        let locationName = request.locationName
            ?? String(format: "%.2f, %.2f", request.latitude, request.longitude)

        return WeatherResult(
            providerName: request.config.displayName,
            locationName: locationName,
            latitude: request.latitude,
            longitude: request.longitude,
            timeRange: request.timeRange,
            observedAt: dt.map { Date(timeIntervalSince1970: $0) },
            temperatureC: maxT,
            feelsLikeC: minT,
            condition: desc,
            humidityPercent: nil,
            windSpeedMS: nil,
            windDirectionDeg: nil,
            precipitationProbabilityPercent: nil,
            revision: request.config.revision
        )
    }

    private struct GeocodeResponseItem: Decodable {
        let name: String
        let localName: String?
        let lat: Double
        let lon: Double
        let country: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case name
            case localName = "local_names"
            case lat
            case lon
            case country
            case state
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            lat = try container.decode(Double.self, forKey: .lat)
            lon = try container.decode(Double.self, forKey: .lon)
            country = try container.decodeIfPresent(String.self, forKey: .country)
            state = try container.decodeIfPresent(String.self, forKey: .state)
            if let zh = try? container.decodeIfPresent([String: String].self, forKey: .localName)?["zh"] {
                localName = zh
            } else if let en = try? container.decodeIfPresent([String: String].self, forKey: .localName)?["en"] {
                localName = en
            } else {
                localName = nil
            }
        }
    }

    private struct CurrentWeatherResponse: Decodable {
        let name: String?
        let dt: Int?
        let weather: [WeatherDescription]?
        let main: MainMetrics?
        let wind: WindMetrics?
        let rain: RainMetrics?
    }

    private struct ForecastResponse: Decodable {
        let city: ForecastCity?
        let list: [ForecastItem]?
    }

    private struct ForecastCity: Decodable {
        let name: String?
    }

    private struct ForecastItem: Decodable {
        let dt: Int?
        let pop: Double?
        let weather: [WeatherDescription]?
        let main: MainMetrics?
        let wind: WindMetrics?
    }

    private struct WeatherDescription: Decodable {
        let description: String?
    }

    private struct MainMetrics: Decodable {
        let temp: Double?
        let feelsLike: Double?
        let humidity: Int?

        enum CodingKeys: String, CodingKey {
            case temp
            case feelsLike = "feels_like"
            case humidity
        }
    }

    private struct WindMetrics: Decodable {
        let speed: Double?
        let deg: Int?
    }

    private struct RainMetrics: Decodable {
        let oneHour: Double?

        enum CodingKeys: String, CodingKey {
            case oneHour = "1h"
        }
    }
}
