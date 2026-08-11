import CoreLocation
import Foundation

enum SparkLocationService {
    nonisolated static func authorizationStatus() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    nonisolated static func hasWhenInUsePermission() -> Bool {
        switch authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    static func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let status = authorizationStatus()
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            let manager = CLLocationManager()
            let delegate = OneShotAuthorizationDelegate { status in
                continuation.resume(returning: status)
            }
            delegate.manager = manager
            delegate.retainSelf = delegate
            manager.delegate = delegate
            manager.requestWhenInUseAuthorization()
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
            delegate.manager = manager
            delegate.retainSelf = delegate
            manager.delegate = delegate
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }
}

private final class OneShotAuthorizationDelegate: NSObject, CLLocationManagerDelegate {
    var manager: CLLocationManager?
    var retainSelf: OneShotAuthorizationDelegate?
    private let completion: (CLAuthorizationStatus) -> Void

    init(completion: @escaping (CLAuthorizationStatus) -> Void) {
        self.completion = completion
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        completion(status)
        manager.delegate = nil
        self.manager = nil
        retainSelf = nil
    }
}

private final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
    var manager: CLLocationManager?
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
        manager?.delegate = nil
        manager = nil
        retainSelf = nil
    }
}
