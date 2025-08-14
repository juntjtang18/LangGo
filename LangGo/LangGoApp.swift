import SwiftUI
import KeychainAccess

@MainActor

enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

@main
struct LangGoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var authState: AuthState = .checking
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    switch authState {
                    case .checking:
                        InitialLoadingView(authState: $authState)
                    case .loggedIn:
                        MainView(authState: $authState)
                    case .loggedOut:
                        LoginView(authState: $authState)
                    }
                }
            }
            .environmentObject(languageSettings)
            .environmentObject(DataServices.shared.reviewSettingsManager)
            .environment(\.theme, themeManager.currentTheme)
        }
    }
}
