// ProfileView.swift

import SwiftUI
import KeychainAccess
import os

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    
    private let strapiService = DataServices.shared.strapiService
    
    // State for existing fields
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    
    // ADDED: State for new profile fields
    @State private var proficiency: String = ""
    @State private var remindersEnabled: Bool = false
    
    // State for UI and feedback
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isLoading = false
    
    private let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ProfileView")
    
    // ADDED: List of proficiency levels for the Picker
    let proficiencyLevels = ["I'm just starting", "I know some basics", "I'm conversational", "I'm fluent but want to improve more"]

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
                    
                    // ADDED: New section for learning preferences
                    Section(header: Text("LEARNING PREFERENCES")) {
                        Picker("Proficiency", selection: $proficiency) {
                            ForEach(proficiencyLevels, id: \.self) { level in
                                Text(level)
                            }
                        }
                        Toggle("Review Reminders", isOn: $remindersEnabled)
                    }

                    Section(header: Text("CHANGE PASSWORD")) {
                        SecureField("Current Password", text: $currentPassword)
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm New Password", text: $confirmNewPassword)
                    }
                    
                    Button("Save Changes") {
                        Task { await updateProfile() }
                    }
                    .disabled(isLoading)
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
            // MODIFIED: Use .task to load the full profile asynchronously.
            .task {
                await loadUserProfile()
            }
            .alert("Profile Update", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // ADDED: Fetches the complete user profile from the server.
    private func loadUserProfile() async {
        do {
            let user = try await strapiService.fetchCurrentUser()
            self.username = user.username
            self.email = user.email
            self.proficiency = user.user_profile?.proficiency ?? proficiencyLevels.first!
            self.remindersEnabled = user.user_profile?.reminder_enabled ?? false
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            alertMessage = "Could not load your profile. Please try again."
            showAlert = true
        }
    }
    
    // MODIFIED: Orchestrates all updates.
    func updateProfile() async {
        isLoading = true
        defer { isLoading = false }
        
        let userId = UserDefaults.standard.integer(forKey: "userId")
        guard userId != 0 else {
            alertMessage = "Could not find user ID. Please log in again."
            showAlert = true
            return
        }
        
        var messages: [String] = []
        
        // This now calls the more general profile update endpoint.
        await updateLearningPreferences(userId: userId, messages: &messages)

        let originalUsername = UserDefaults.standard.string(forKey: "username") ?? ""
        if !username.isEmpty && username != originalUsername {
            await updateUsername(userId: userId, messages: &messages)
        }
        
        if !newPassword.isEmpty {
            await changePassword(messages: &messages)
        }
        
        if !messages.isEmpty {
            alertMessage = messages.joined(separator: "\n")
        } else {
            alertMessage = "No changes were made."
        }
        showAlert = true
    }
    
    // ADDED: Handles updating proficiency and reminders.
    private func updateLearningPreferences(userId: Int, messages: inout [String]) async {
        do {
            try await strapiService.updateUserProfile(
                userId: userId,
                proficiency: proficiency,
                remindersEnabled: remindersEnabled
            )
            messages.append("Learning preferences updated.")
            logger.info("User preferences updated for user ID \(userId).")
        } catch {
            let errorText = "Failed to update preferences: \(error.localizedDescription)"
            messages.append(errorText)
            logger.error("\(errorText, privacy: .public)")
        }
    }
    
    /// Handles the network request to update the username.
    private func updateUsername(userId: Int, messages: inout [String]) async {
        do {
            // Use the internally resolved service
            let updatedUser = try await strapiService.updateUsername(userId: userId, username: username)
            UserDefaults.standard.set(updatedUser.username, forKey: "username")
            messages.append("Username updated successfully!")
            logger.info("Username updated to \(updatedUser.username, privacy: .public)")
        } catch {
            var currentErrorText: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                currentErrorText = nsError.localizedDescription
            default:
                currentErrorText = "Failed to update username: \(error.localizedDescription)"
            }
            messages.append(currentErrorText)
            logger.error("Failed to update username: \(currentErrorText, privacy: .public)")
        }
    }
    
    /// Handles the network request to change the password.
    private func changePassword(messages: inout [String]) async {
        guard newPassword == confirmNewPassword else {
            messages.append("Failed to change password: New passwords do not match.")
            return
        }
        
        do {
            // Use the internally resolved service
            let _: EmptyResponse = try await strapiService.changePassword(currentPassword: currentPassword, newPassword: newPassword, confirmNewPassword: confirmNewPassword)
            messages.append("Password changed successfully!")
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
            logger.info("Password changed successfully.")
        } catch {
            var currentErrorText: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                currentErrorText = nsError.localizedDescription
            default:
                currentErrorText = "Failed to change password: \(error.localizedDescription)"
            }
            messages.append(currentErrorText)
            logger.error("Failed to change password: \(currentErrorText, privacy: .public)")
        }
    }
}
