import Foundation

@MainActor
enum NutritionNotificationPresenter {
    static func presentError(
        store: NotificationStore,
        messageKey: String,
        source: String,
        titleKey: String = "common.error"
    ) {
        let notification = NotificationMessage(
            title: L10n.text(titleKey),
            message: L10n.text(messageKey),
            level: .error,
            presentation: .banner,
            source: source,
            dedupeKey: source,
            autoDismissAfter: 2.8
        )
        store.present(notification)
        scheduleBannerDismiss(store: store, messageID: notification.id, after: 2.8)
    }

    static func presentSuccess(
        store: NotificationStore,
        message: String,
        source: String
    ) {
        let notification = NotificationMessage(
            title: nil,
            message: message,
            level: .success,
            presentation: .toast,
            source: source,
            dedupeKey: source,
            autoDismissAfter: 2.0
        )
        store.present(notification)
        scheduleToastDismiss(store: store, messageID: notification.id, after: 2.0)
    }

    private static func scheduleBannerDismiss(
        store: NotificationStore,
        messageID: UUID,
        after: TimeInterval
    ) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0.6, after) * 1_000_000_000))
            store.dismissBanner(id: messageID)
        }
    }

    private static func scheduleToastDismiss(
        store: NotificationStore,
        messageID: UUID,
        after: TimeInterval
    ) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0.4, after) * 1_000_000_000))
            store.dismissToast(id: messageID)
        }
    }
}
