import Foundation

enum SparkWebSocketEvent: Sendable {
    case connected
    case text(String)
    case disconnected(String?)
}

actor SparkWebSocketClient {
    typealias EventHandler = @Sendable (SparkWebSocketEvent) -> Void

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var eventHandler: EventHandler?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(request: URLRequest, eventHandler: @escaping EventHandler) {
        disconnectInternal(reason: nil)

        self.eventHandler = eventHandler
        let socketTask = session.webSocketTask(with: request)
        self.task = socketTask

        socketTask.resume()
        eventHandler(.connected)
        startReceiveLoop(task: socketTask)
        startPingLoop(task: socketTask)
    }

    func send(text: String) async {
        guard let task else { return }
        do {
            try await task.send(.string(text))
        } catch {
            disconnectInternal(reason: error.localizedDescription)
        }
    }

    func disconnect() {
        disconnectInternal(reason: nil)
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task {
            while Task.isCancelled == false {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        eventHandler?(.text(text))
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            eventHandler?(.text(text))
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    disconnectInternal(reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func startPingLoop(task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task {
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        task.sendPing { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    disconnectInternal(reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func disconnectInternal(reason: String?) {
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil

        if let reason {
            eventHandler?(.disconnected(reason))
        }

        eventHandler = nil
    }
}
