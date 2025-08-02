import SwiftUI
import KeychainAccess

@MainActor
class AppEnvironment: ObservableObject {
    let strapiService = StrapiService()
    let conversationService = ConversationService()
    let reviewSettingsManager = ReviewSettingsManager()
    let storyService = StoryService()
}

enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

@main // ✅ Make this available from iOS 16
struct LangGoApp: App {
    @State private var authState: AuthState = .checking
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            Group {
                switch authState {
                case .checking:
                    InitialLoadingView(authState: $authState)
                case .loggedIn:
                    MainView(authState: $authState)
                case .loggedOut:
                    LoginView(authState: $authState)
                }
            }
            // ✅ Inject required global dependencies
            .environmentObject(languageSettings)
            .environmentObject(appEnvironment)
            .environmentObject(appEnvironment.reviewSettingsManager)
            .environment(\.theme, themeManager.currentTheme)
        }
    }
}
