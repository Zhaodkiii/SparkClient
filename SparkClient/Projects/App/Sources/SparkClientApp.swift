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
        SparkApplicationDelegate.bootstrapExternalMedicalDocumentImportCoordinator = container.externalMedicalDocumentImportCoordinator
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
                .onOpenURL { url in
                    _ = container.externalMedicalDocumentImportCoordinator.tryReceive(url, source: .onOpenURL)
                }
                .task {
                    appDelegate.pushAdapter = container.pushAdapter
                    container.pushAdapter.installAsNotificationCenterDelegate()
                }
        }
    }
}
