// LangGoApp.swift
import SwiftUI
import SwiftData
import KeychainAccess

// A new class to hold our services, making them available to the entire app.
@MainActor
class AppEnvironment: ObservableObject {
    let strapiService: StrapiService
    let conversationService: ConversationService
    let reviewSettingsManager = ReviewSettingsManager()
    let storyService: StoryService // Added the new service

    init(modelContainer: ModelContainer) {
        self.strapiService = StrapiService(modelContext: modelContainer.mainContext)
        self.conversationService = ConversationService()
        self.storyService = StoryService() // Initialized the new service
    }
}

// Define the possible authentication states for the app
enum AuthState {
    case checking
    case loggedIn
    case loggedOut
}

@main
struct LangGoApp: App {
    @State private var authState: AuthState = .checking
    @StateObject private var languageSettings = LanguageSettings()

    // The single instance of our environment object and the model container.
    @StateObject private var appEnvironment: AppEnvironment
    private let modelContainer: ModelContainer

    init() {
        // 1. Create the model container once.
        let container = try! ModelContainer(for: Flashcard.self, Vocabook.self, Vocapage.self)
        self.modelContainer = container
        
        // 2. Create the environment object that holds the service, injecting the container.
        _appEnvironment = StateObject(wrappedValue: AppEnvironment(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            // 3. Switch the view based on the authentication state
            switch authState {
            case .checking:
                InitialLoadingView(authState: $authState)
            case .loggedIn:
                MainView(authState: $authState)
            case .loggedOut:
                LoginView(authState: $authState)
            }
        }
        .modelContainer(modelContainer) // Use the container created in the initializer.
        .environmentObject(languageSettings)
        .environmentObject(appEnvironment) // 4. Inject the AppEnvironment into the SwiftUI Environment.
        .environmentObject(appEnvironment.reviewSettingsManager) // Inject the new manager
    }
}
