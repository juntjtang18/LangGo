import SwiftUI
import SwiftData
import KeychainAccess

// Define the possible authentication states for the app
enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

@main
struct LangGoApp: App {
    // 1. Use an enum for a more robust state management
    @State private var authState: AuthState = .checking
    @StateObject private var languageSettings = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            // 2. Switch the view based on the authentication state
            switch authState {
            case .checking:
                // Show a loading view while verifying the token
                InitialLoadingView(authState: $authState)
            case .loggedIn:
                // Pass a binding to allow logout
                MainView(authState: $authState)
            case .loggedOut:
                // Pass a binding to allow login
                LoginView(authState: $authState)
            }
        }
        .modelContainer(for: Flashcard.self)
        // Make the language settings available to all child views.
        .environmentObject(languageSettings)
        // Set the app's locale from the published property.
        // The UI will automatically update when this value changes.
        .environment(\.locale, .init(identifier: languageSettings.selectedLanguageCode))
    }
}
