import SwiftUI

struct ContentView: View {
    let dependencies: AppContentDependencies

    var body: some View {
        NotificationHostView(store: dependencies.notificationStore) {
            AppCoordinatorView(dependencies: dependencies.coordinator)
        }
        .task {
            dependencies.routeCoordinator.startSystemEventRouting()
            await dependencies.notificationDeliveryCoordinator.refreshDashboard()
        }
        .onOpenURL { url in
            if dependencies.externalMedicalDocumentImportCoordinator.tryReceive(url, source: .onOpenURL) {
                return
            }
            dependencies.routeCoordinator.handleDeepLink(url)
        }
    }
}
