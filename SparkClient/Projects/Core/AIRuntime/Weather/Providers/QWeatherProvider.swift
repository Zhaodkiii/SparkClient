import CoreLocation
import Foundation

struct QWeatherProvider: Sendable {
    let session: URLSession

    func geocode(keyword: String) async throws -> GeocodeResult {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw WeatherRuntimeError.emptyKeyword }

        return try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(trimmed) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let placemark = placemarks?.first,
                      let location = placemark.location else {
                    continuation.resume(throwing: WeatherRuntimeError.locationNotFound(trimmed))
                    return
                }
                let name = [
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: ", ")
                continuation.resume(
                    returning: GeocodeResult(
                        name: name.isEmpty ? trimmed : name,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        country: placemark.isoCountryCode,
                        state: placemark.administrativeArea
                    )
                )
            }
        }
    }

    func queryWeather(_ request: WeatherQueryRequest) async throws -> WeatherResult {
        let baseURL = request.config.requestURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedRange = WeatherEndpointNormalizer.normalizedTimeRange(request.timeRange)
        let endpoint: String
        if normalizedRange == "now" {
            endpoint = "/v7/weather/now"
        } else if normalizedRange == "tomorrow" {
            endpoint = "/v7/weather/3d"
        } else {
            endpoint = "/v7/weather/\(normalizedRange)"
        }

        let lat = request.latitude
        let lon = request.longitude
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let langParam = isChinese ? "zh" : "en"
        let urlString = "\(baseURL)\(endpoint)?location=\(lon),\(lat)&key=\(request.config.apiKey)&lang=\(langParam)&unit=m"
        guard let url = URL(string: urlString) else {
            throw WeatherRuntimeError.invalidEndpoint(urlString)
        }

        let (data, response) = try await session.data(from: url)
        try WeatherGateway.validate(response: response, data: data)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeatherRuntimeError.invalidResponse(request.config.displayName)
        }

        let locationName = request.locationName
            ?? String(format: "%.2f, %.2f", request.latitude, request.longitude)

        if normalizedRange == "now" {
            guard let now = dict["now"] as? [String: Any] else {
                throw WeatherRuntimeError.invalidResponse(request.config.displayName)
            }
            let temp = Double(now["temp"] as? String ?? "")
            let feelsLike = Double(now["feelsLike"] as? String ?? "")
            let text = now["text"] as? String ?? "未知"
            let humidity = Int(now["humidity"] as? String ?? "")
            let windSpeed = Double(now["windSpeed"] as? String ?? "")
            let windDir = now["windDir"] as? String
            let precip = now["precip"] as? String

            return WeatherResult(
                providerName: request.config.displayName,
                locationName: locationName,
                latitude: request.latitude,
                longitude: request.longitude,
                legalPageURL: nil,
                timeRange: request.timeRange,
                observedAt: Date(),
                temperatureC: temp,
                feelsLikeC: feelsLike,
                condition: windDir.map { "\(text)（\($0)）" } ?? text,
                humidityPercent: humidity,
                windSpeedMS: windSpeed.map { $0 / 3.6 },
                windDirectionDeg: nil,
                precipitationProbabilityPercent: precip.flatMap { Double($0).map { Int($0 * 10) } },
                revision: request.config.revision
            )
        }

        guard let daily = dict["daily"] as? [[String: Any]], daily.isEmpty == false else {
            throw WeatherRuntimeError.invalidResponse(request.config.displayName)
        }

        let dayIndex = normalizedRange == "tomorrow" ? 1 : 0
        let day = daily.indices.contains(dayIndex) ? daily[dayIndex] : daily[0]
        let textDay = day["textDay"] as? String ?? "未知"
        let tempMax = Double(day["tempMax"] as? String ?? "")
        let tempMin = Double(day["tempMin"] as? String ?? "")
        let precip = day["precip"] as? String
        let fxDate = day["fxDate"] as? String
        let observedAt = fxDate.flatMap {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: $0)
        }

        return WeatherResult(
            providerName: request.config.displayName,
            locationName: locationName,
            latitude: request.latitude,
            longitude: request.longitude,
            legalPageURL: nil,
            timeRange: request.timeRange,
            observedAt: observedAt,
            temperatureC: tempMax,
            feelsLikeC: tempMin,
            condition: textDay,
            humidityPercent: nil,
            windSpeedMS: nil,
            windDirectionDeg: nil,
            precipitationProbabilityPercent: precip.flatMap { Double($0).map { Int($0 * 10) } },
            revision: request.config.revision
        )
    }
}
