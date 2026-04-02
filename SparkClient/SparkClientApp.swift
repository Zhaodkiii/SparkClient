//
//  SparkClientApp.swift
//  SparkClient
//
//  Created by 話 on 2026/4/2.
//

import SwiftUI
import CoreData

@main
struct SparkClientApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
