import SwiftUI
import KeychainAccess
import os

struct InitialLoadingView: View {
    @Binding var authState: AuthState
    
    // The services are now accessed directly from the singleton
    private let authService = DataServices.shared.authService
    private let reviewSettingsManager = DataServices.shared.reviewSettingsManager
    
    private let keychain = Keychain(service: Config.keychainService)
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
                // Use the service from the singleton
                let user = try await authService.fetchCurrentUser()
                UserSessionManager.shared.login(user: user)
                await reviewSettingsManager.loadSettings()
                
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
