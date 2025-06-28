//
//  LangGoApp.swift
//  LangGo
//
//  Created by James Tang on 2025/6/25.
//

import SwiftUI
import SwiftData
import KeychainAccess

@main
struct LangGoApp: App {
    // 1. The top-level state for the entire app now lives here.
    @State private var isLoggedIn: Bool

    // Create an instance of Keychain to check for the JWT
    let keychain = Keychain(service: "com.geniusparentingai.GeniusParentingAISwift")

    init() {
        // 2. The logic to check for an existing session is moved here.
        if keychain["jwt"] != nil {
            // Use _isLoggedIn to set the initial value of a @State property
            _isLoggedIn = State(initialValue: true)
        } else {
            _isLoggedIn = State(initialValue: false)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            // 3. The app's body now decides which view to show.
            if isLoggedIn {
                // If logged in, show MainView and pass the binding.
                MainView(isLoggedIn: $isLoggedIn)
            } else {
                // If not logged in, show LoginView and pass the binding.
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .modelContainer(for: Flashcard.self)
    }
}
