import SwiftUI
import CoreData
import KeychainAccess

@main
struct LangGoApp: App {
    let persistenceController = PersistenceController.shared
    
    // Declare the StateObjects here, but we will initialize them in init()
    @StateObject private var appEnvironment: AppEnvironment
    @StateObject private var reviewSettingsManager: ReviewSettingsManager
    
    // These have no dependencies, so they can be initialized directly
    @StateObject private var languageSettings = LanguageSettings()
    
    @State private var authState: AuthState
    
    init() {
        // 1. Create the single StrapiService instance
        let strapiService = StrapiService(managedObjectContext: persistenceController.container.viewContext)
        
        // 2. Initialize the objects that depend on the service
        _appEnvironment = StateObject(wrappedValue: AppEnvironment(strapiService: strapiService))
        _reviewSettingsManager = StateObject(wrappedValue: ReviewSettingsManager(strapiService: strapiService))
        
        // 3. Initialize authState from the keychain
        let keychain = Keychain(service: Config.keychainService)
        if keychain["jwt"] != nil {
            _authState = State(initialValue: .loggedIn)
        } else {
            _authState = State(initialValue: .loggedOut)
        }
    }

    var body: some Scene {
        WindowGroup {
            // The view hierarchy remains the same and will now have all required objects
            if authState == .loggedIn {
                InitialLoadingView(authState: $authState)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(appEnvironment)
                    .environmentObject(languageSettings)
                    .environmentObject(reviewSettingsManager)
            } else {
                LoginView(authState: $authState)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(appEnvironment)
                    .environmentObject(languageSettings)
                    .environmentObject(reviewSettingsManager)
            }
        }
    }
}

enum AuthState {
    case loggedIn, loggedOut
}
