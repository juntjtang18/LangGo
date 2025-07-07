import SwiftUI
import KeychainAccess
import os

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
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ProfileView")

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
        
        // Ensure we have the user ID before proceeding.
        let userId = UserDefaults.standard.integer(forKey: "userId")
        guard userId != 0 else {
            alertMessage = "Could not find user ID. Please log in again."
            showAlert = true
            return
        }
        
        var messages: [String] = []

        // --- Update Username if it has been changed ---
        let originalUsername = UserDefaults.standard.string(forKey: "username") ?? ""
        if !username.isEmpty && username != originalUsername {
            await updateUsername(userId: userId, messages: &messages)
        }
        
        // --- Change Password if a new password is provided ---
        if !newPassword.isEmpty {
            await changePassword(messages: &messages)
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
    private func updateUsername(userId: Int, messages: inout [String]) async {
        do {
            // Use StrapiService to update username
            let updatedUser = try await StrapiService.shared.updateUsername(userId: userId, username: username)
            UserDefaults.standard.set(updatedUser.username, forKey: "username")
            messages.append("Username updated successfully!")
            logger.info("Username updated to \(updatedUser.username, privacy: .public)")
        } catch {
            // FIX: Create a local variable to hold the error text to avoid capturing 'inout messages'
            var currentErrorText: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                currentErrorText = nsError.localizedDescription
            default:
                currentErrorText = "Failed to update username: \(error.localizedDescription)"
            }
            messages.append(currentErrorText) // Append to inout messages
            logger.error("Failed to update username: \(currentErrorText, privacy: .public)") // Pass local variable
        }
    }
    
    /// Handles the network request to change the password.
    private func changePassword(messages: inout [String]) async {
        guard newPassword == confirmNewPassword else {
            messages.append("Failed to change password: New passwords do not match.")
            return
        }
        
        do {
            // Use StrapiService to change password
            let _: EmptyResponse = try await StrapiService.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword, confirmNewPassword: confirmNewPassword)
            messages.append("Password changed successfully!")
            // Clear password fields after successful change
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
            logger.info("Password changed successfully.")
        } catch {
            // FIX: Create a local variable to hold the error text to avoid capturing 'inout messages'
            var currentErrorText: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                currentErrorText = nsError.localizedDescription
            default:
                currentErrorText = "Failed to change password: \(error.localizedDescription)"
            }
            messages.append(currentErrorText) // Append to inout messages
            logger.error("Failed to change password: \(currentErrorText, privacy: .public)") // Pass local variable
        }
    }
}
