import CoreData
import SwiftUI
import UIKit

@main
struct SparkClientApp: App {
    private let container: AppContainer
    @UIApplicationDelegateAdaptor(SparkApplicationDelegate.self) private var appDelegate

    init() {
        let container = AppContainer.live()
        self.container = container
        SparkApplicationDelegate.bootstrapPushAdapter = container.pushAdapter
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
                .task {
                    appDelegate.pushAdapter = container.pushAdapter
                    container.pushAdapter.installAsNotificationCenterDelegate()
                }
        }
    }
}
