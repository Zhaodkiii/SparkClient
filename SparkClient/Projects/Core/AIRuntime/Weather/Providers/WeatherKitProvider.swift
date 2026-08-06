import CoreLocation
import Foundation

#if canImport(WeatherKit)
import WeatherKit
#endif

struct WeatherKitProvider: Sendable {
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
        #if canImport(WeatherKit)
        if #available(iOS 16.0, *) {
            return try await queryWeatherKit(request)
        }
        #endif
        throw WeatherRuntimeError.unsupportedProvider(request.config.displayName)
    }

    #if canImport(WeatherKit)
    @available(iOS 16.0, *)
    private func queryWeatherKit(_ request: WeatherQueryRequest) async throws -> WeatherResult {
        let location = CLLocation(latitude: request.latitude, longitude: request.longitude)
        let weather = try await WeatherService.shared.weather(for: location)
        let normalizedRange = WeatherEndpointNormalizer.normalizedTimeRange(request.timeRange)
        let locationName = request.locationName
            ?? String(format: "%.2f, %.2f", request.latitude, request.longitude)

        if normalizedRange == "tomorrow" {
            guard let day = weather.dailyForecast.forecast.dropFirst().first else {
                throw WeatherRuntimeError.invalidResponse(request.config.displayName)
            }
            return WeatherResult(
                providerName: request.config.displayName,
                locationName: locationName,
                latitude: request.latitude,
                longitude: request.longitude,
                timeRange: request.timeRange,
                observedAt: day.date,
                temperatureC: day.highTemperature.value,
                feelsLikeC: nil,
                condition: day.condition.description,
                humidityPercent: nil,
                windSpeedMS: day.wind.speed.value,
                windDirectionDeg: Int(day.wind.direction.value),
                precipitationProbabilityPercent: Int((day.precipitationChance * 100).rounded()),
                revision: request.config.revision
            )
        }

        let current = weather.currentWeather
        return WeatherResult(
            providerName: request.config.displayName,
            locationName: locationName,
            latitude: request.latitude,
            longitude: request.longitude,
            timeRange: request.timeRange,
            observedAt: weather.currentWeather.date,
            temperatureC: current.temperature.value,
            feelsLikeC: current.apparentTemperature.value,
            condition: current.condition.description,
            humidityPercent: Int((current.humidity * 100).rounded()),
            windSpeedMS: current.wind.speed.value,
            windDirectionDeg: Int(current.wind.direction.value),
            precipitationProbabilityPercent: nil,
            revision: request.config.revision
        )
    }
    #endif
}
