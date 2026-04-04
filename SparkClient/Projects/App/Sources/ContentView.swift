import SwiftUI

struct ContentView: View {
    let container: AppContainer

    var body: some View {
        NotificationHostView(store: container.notificationStore) {
            AppCoordinatorView(container: container)
        }
        .task {
            await container.notificationDeliveryCoordinator.refreshDashboard()
        }
    }
}
