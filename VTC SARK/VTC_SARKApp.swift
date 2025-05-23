//
//  VTC_SARKApp.swift
//  VTC SARK
//
//  Created by Raoul Brahim on 23-05-2025.
//

import SwiftUI

@main
struct VTC_SARKApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
