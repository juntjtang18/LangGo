// LangGoApp.swift (refactored routing)
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
    // Tracks if the user finished the onboarding flow on this device
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Tracks if the user has ever successfully signed up on this device/account
    @AppStorage("hasSignedUp") private var hasSignedUp = false

    @State private var authState: AuthState = .checking

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var voiceService = VoiceSelectionService()
    // Make the session observable at the root
    @StateObject private var userSession = UserSessionManager.shared

    @State private var onboardingData: OnboardingData? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                // 1) If onboarding hasn't completed yet, always show it first
                if !hasCompletedOnboarding {
                    OnboardingView(onComplete: { data in
                        self.onboardingData = data
                        self.hasCompletedOnboarding = true
                        // After this flag flips, the next render will go through auth routing below
                    })
                } else {
                    // 2) After onboarding, check auth status
                    switch authState {
                    case .checking:
                        // InitialLoadingView sets authState to .loggedIn if JWT exists/valid, else .loggedOut
                        InitialLoadingView(authState: $authState)

                    case .loggedIn:
                        // 3) Valid session → main app
                        MainView(authState: $authState)

                    case .loggedOut:
                        // 4) No JWT. If they've signed up before → start on login; otherwise → start on signup
                        LoginView(
                            authState: $authState,
                            onboardingData: onboardingData,
                            startOn: hasSignedUp ? .login : .signup
                        )
                    }
                }
            }
            // Inject environment objects
            .environmentObject(userSession)
            .environmentObject(languageSettings)
            .environmentObject(DataServices.shared.reviewSettingsManager)
            .environment(\.theme, themeManager.currentTheme)
            .environmentObject(voiceService)
        }
    }
}
