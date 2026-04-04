import Combine
import Foundation

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var currentToast: NotificationMessage?
    @Published private(set) var currentBanner: NotificationMessage?
    @Published private(set) var currentAlert: NotificationMessage?
    @Published private(set) var inboxItems: [NotificationInboxItem] = []
    @Published private(set) var metricsSnapshot: NotificationMetricsSnapshot = .zero

    private var alertDismissContinuation: CheckedContinuation<Void, Never>?
    private var activeAlertID: UUID?

    func present(_ message: NotificationMessage) {
        switch message.presentation {
        case .toast:
            currentToast = message
        case .banner:
            currentBanner = message
        case .alert:
            currentAlert = message
            activeAlertID = message.id
        }
    }

    func dismissToast(id: UUID?) {
        guard currentToast?.id == id || id == nil else { return }
        currentToast = nil
    }

    func dismissBanner(id: UUID?) {
        guard currentBanner?.id == id || id == nil else { return }
        currentBanner = nil
    }

    func dismissAlert(id: UUID?) {
        guard currentAlert?.id == id || id == nil else { return }
        currentAlert = nil
        activeAlertID = nil
        alertDismissContinuation?.resume()
        alertDismissContinuation = nil
    }

    func waitForAlertDismissal(id: UUID) async {
        if activeAlertID != id {
            return
        }
        await withCheckedContinuation { continuation in
            self.alertDismissContinuation = continuation
        }
    }

    func replaceInboxItems(_ items: [NotificationInboxItem]) {
        inboxItems = items
    }

    func replaceMetrics(_ snapshot: NotificationMetricsSnapshot) {
        metricsSnapshot = snapshot
    }
}
