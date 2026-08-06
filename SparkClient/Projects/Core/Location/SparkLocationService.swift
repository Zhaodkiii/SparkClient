import CoreLocation
import Foundation

enum SparkLocationService {
    nonisolated static func hasWhenInUsePermission() -> Bool {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    static func currentCoordinate() async throws -> (latitude: Double, longitude: Double) {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            throw WeatherRuntimeError.invalidResponse("尚未获得定位授权，请先询问用户城市或使用 query_location。")
        default:
            throw WeatherRuntimeError.invalidResponse("定位权限未开启，请改为询问用户城市。")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = OneShotLocationDelegate { result in
                continuation.resume(with: result)
            }
            delegate.retainSelf = delegate
            manager.delegate = delegate
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }
}

private final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    var retainSelf: OneShotLocationDelegate?
    private let completion: (Result<(latitude: Double, longitude: Double), Error>) -> Void

    init(completion: @escaping (Result<(latitude: Double, longitude: Double), Error>) -> Void) {
        self.completion = completion
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherRuntimeError.invalidResponse("未能获取当前位置。")))
            return
        }
        finish(.success((latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<(latitude: Double, longitude: Double), Error>) {
        completion(result)
        retainSelf = nil
    }
}
