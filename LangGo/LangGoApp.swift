// LangGoApp.swift
import SwiftUI
import KeychainAccess

@MainActor
enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

struct OnboardingData {
    var proficiencyKey: String = ""
    var remindersEnabled: Bool = false
}

@main
struct LangGoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var authState: AuthState = .checking

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var voiceService = VoiceSelectionService()

    // ✅ Add this: make the session observable at the root
    @StateObject private var userSession = UserSessionManager.shared

    @State private var onboardingData: OnboardingData? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView(onComplete: { data in
                        self.onboardingData = data
                        self.hasCompletedOnboarding = true
                    })
                } else {
                    switch authState {
                    case .checking:
                        InitialLoadingView(authState: $authState)
                    case .loggedIn:
                        MainView(authState: $authState)
                    case .loggedOut:
                        // Start on Signup after onboarding
                        LoginView(authState: $authState,
                                  onboardingData: onboardingData,
                                  startOn: .signup)
                    }
                }
            }
            // ✅ Inject both environment objects
            .environmentObject(userSession)
            .environmentObject(languageSettings)
            .environmentObject(DataServices.shared.reviewSettingsManager)
            .environment(\.theme, themeManager.currentTheme)
            .environmentObject(voiceService)
        }
    }
}
