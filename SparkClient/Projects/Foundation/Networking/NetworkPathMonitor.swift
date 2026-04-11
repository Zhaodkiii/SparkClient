import Combine
import Foundation
import Network

/// 使用 `NWPathMonitor` 观察网络是否可用（不引入 Alamofire）。
@MainActor
final class NetworkPathMonitor: ObservableObject {
    @Published private(set) var isSatisfied: Bool = true
    @Published private(set) var hasEvaluatedPath: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sparkclient.networkpath")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.apply(path: path)
            }
        }
        monitor.start(queue: queue)
        apply(path: monitor.currentPath)
    }

    func stop() {
        monitor.cancel()
    }

    private func apply(path: NWPath) {
        isSatisfied = path.status == .satisfied
        hasEvaluatedPath = true
    }
}
