import SwiftUI
import KeychainAccess

struct InitialLoadingView: View {
    @Binding var authState: AuthState // Binding to control the app's root view

    let keychain = Keychain(service: Config.keychainService)

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
            authState = .loggedOut
            return
        }

        // 2. If a token exists, validate it by fetching the user profile
        Task {
            do {
                guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else {
                    clearSessionAndLogout()
                    return
                }
                
                // The existing fetchUser function is perfect for this
                let user = try await NetworkManager.shared.fetchUser(from: url)
                
                // SUCCESS: Token is valid. Refresh user details.
                UserDefaults.standard.set(user.username, forKey: "username")
                UserDefaults.standard.set(user.email, forKey: "email")
                authState = .loggedIn
                
            } catch {
                // FAILURE: Token is invalid (expired, etc.).
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
