// LangGoApp.swift
import SwiftUI
import KeychainAccess

@MainActor
enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

// ADDED: A struct to hold the collected onboarding data.
struct OnboardingData {
    var proficiencyKey: String = ""
    var remindersEnabled: Bool = false
}


@main
struct LangGoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var authState: AuthState = .checking
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var themeManager = ThemeManager()
    
    // ADDED: State to hold onboarding data after completion.
    @State private var onboardingData: OnboardingData? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    // MODIFIED: OnboardingView now passes its data back on completion.
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
                        // MODIFIED: LoginView now receives the onboarding data.
                        LoginView(authState: $authState, onboardingData: onboardingData)
                    }
                }
            }
            .environmentObject(languageSettings)
            .environmentObject(DataServices.shared.reviewSettingsManager)
            .environment(\.theme, themeManager.currentTheme)
        }
    }
}
