//
//  LangGoApp.swift
//  LangGo
//
//  Created by James Tang on 2025/6/24.
//

import SwiftUI

@main
struct LangGoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
