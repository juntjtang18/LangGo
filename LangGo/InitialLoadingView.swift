import SwiftUI
import KeychainAccess
import os

struct InitialLoadingView: View {
    @Binding var authState: AuthState
    @EnvironmentObject var appEnvironment: AppEnvironment

    let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "InitialLoadingView")

    var body: some View {
        VStack {
            ProgressView()
            Text("Verifying Session...")
        }
        .onAppear {
            verifyToken()
        }
    }

    private func verifyToken() {
        // 1. Check if a token even exists
        guard keychain["jwt"] != nil else {
            logger.info("No JWT found. Setting authState to loggedOut.")
            authState = .loggedOut
            return
        }

        // 2. If a token exists, validate it by fetching the user profile
        Task {
            do {
                // Use the injected StrapiService instance
                let user = try await appEnvironment.strapiService.fetchCurrentUser()
                // SUCCESS: Token is valid. Refresh user details.
                UserDefaults.standard.set(user.username, forKey: "username")
                UserDefaults.standard.set(user.email, forKey: "email")
                UserDefaults.standard.set(user.id, forKey: "userId") // Ensure user ID is also saved
                
                // Load critical app settings after validation
                await appEnvironment.reviewSettingsManager.loadSettings(strapiService: appEnvironment.strapiService)
                
                authState = .loggedIn
                logger.info("JWT validated. User \(user.username, privacy: .public) logged in.")
                
            } catch {
                // FAILURE: Token is invalid (expired, etc.).
                logger.error("JWT validation failed: \(error.localizedDescription, privacy: .public). Clearing session.")
                clearSessionAndLogout()
            }
        }
    }

    /// A helper to clear all session data and force a logout.
    private func clearSessionAndLogout() {
        keychain["jwt"] = nil
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "email")
        authState = .loggedOut
    }
}
