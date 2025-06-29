import SwiftUI
import KeychainAccess

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isLoading = false
    
    let keychain = Keychain(service: Config.keychainService)

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section(header: Text("USER PROFILE")) {
                        HStack {
                            Text("Username")
                            Spacer()
                            TextField("Username", text: $username)
                                .multilineTextAlignment(.trailing)
                                .autocapitalization(.none)
                        }
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(email)
                                .foregroundColor(.gray)
                        }
                    }

                    Section(header: Text("CHANGE PASSWORD")) {
                        SecureField("Current Password", text: $currentPassword)
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm New Password", text: $confirmNewPassword)
                    }
                    
                    Button("Save Changes") {
                        Task { await updateProfile() }
                    }
                    .disabled(isLoading || (username.isEmpty && newPassword.isEmpty))
                }
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
            .onAppear {
                // Load user data from UserDefaults when the view appears
                self.username = UserDefaults.standard.string(forKey: "username") ?? ""
                self.email = UserDefaults.standard.string(forKey: "email") ?? "Email not found"
            }
            .alert("Profile Update", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    func updateProfile() async {
        isLoading = true
        defer { isLoading = false }
        
        // Ensure we have the user ID and token before proceeding.
        let userId = UserDefaults.standard.integer(forKey: "userId")
        guard userId != 0 else {
            alertMessage = "Could not find user ID. Please log in again."
            showAlert = true
            return
        }
        
        guard let token = keychain["jwt"] else {
            alertMessage = "Authentication error. Please log out and log back in."
            showAlert = true
            return
        }
        
        var messages: [String] = []

        // --- Update Username if it has been changed ---
        let originalUsername = UserDefaults.standard.string(forKey: "username") ?? ""
        if !username.isEmpty && username != originalUsername {
            await updateUsername(userId: userId, token: token, messages: &messages)
        }
        
        // --- Change Password if a new password is provided ---
        if !newPassword.isEmpty {
            await changePassword(token: token, messages: &messages)
        }
        
        // Show a combined alert message with the results.
        if !messages.isEmpty {
            alertMessage = messages.joined(separator: "\n")
        } else {
            alertMessage = "No changes were made."
        }
        showAlert = true
    }
    
    /// Handles the network request to update the username.
    private func updateUsername(userId: Int, token: String, messages: inout [String]) async {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else {
            messages.append("Failed to update username: Invalid URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = ["username": username]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                messages.append("Failed to update username: Invalid server response.")
                return
            }

            if httpResponse.statusCode == 200 {
                UserDefaults.standard.set(username, forKey: "username")
                messages.append("Username updated successfully!")
            } else {
                // --- MODIFICATION START: Added detailed error logging ---
                // Try to parse the specific error message from Strapi's JSON response.
                var errorMessage = "Failed to update username. Status: \(httpResponse.statusCode)"
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDetails = errorJson["error"] as? [String: Any],
                   let message = errorDetails["message"] as? String {
                    // Append the specific message from Strapi (e.g., "Forbidden")
                    errorMessage += " - \(message)"
                }
                messages.append(errorMessage)
                // --- MODIFICATION END ---
            }
        } catch {
            messages.append("Error updating username: \(error.localizedDescription)")
        }
    }
    
    /// Handles the network request to change the password.
    private func changePassword(token: String, messages: inout [String]) async {
        guard newPassword == confirmNewPassword else {
            messages.append("Failed to change password: New passwords do not match.")
            return
        }
        
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/change-password") else {
            messages.append("Failed to change password: Invalid URL.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = [
            "currentPassword": currentPassword,
            "password": newPassword,
            "passwordConfirmation": confirmNewPassword
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                messages.append("Password changed successfully!")
                // Clear password fields after successful change
                currentPassword = ""
                newPassword = ""
                confirmNewPassword = ""
            } else {
                // Also add detailed logging here for password change failures
                var errorMessage = "Failed to change password. Check your current password."
                 if let httpResponse = response as? HTTPURLResponse {
                    errorMessage = "Failed to change password. Status: \(httpResponse.statusCode)"
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDetails = errorJson["error"] as? [String: Any],
                       let message = errorDetails["message"] as? String {
                        errorMessage += " - \(message)"
                    }
                }
                messages.append(errorMessage)
            }
        } catch {
            messages.append("Error changing password: \(error.localizedDescription)")
        }
    }
}
