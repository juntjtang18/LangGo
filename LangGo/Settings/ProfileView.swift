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
    
    // State for new profile fields
    @State private var proficiencyId: Int = 0
    @State private var proficiencyLevels: [ProficiencyLevel] = []
    
    @State private var remindersEnabled: Bool = false
    
    // State for UI and feedback
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isLoading = false
    
    private let keychain = Keychain(service: Config.keychainService)
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
                    
                    Section(header: Text("LEARNING PREFERENCES")) {
                        if proficiencyLevels.isEmpty {
                            Text("Proficiency levels could not be loaded.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Proficiency", selection: $proficiencyId) {
                                ForEach(proficiencyLevels) { level in
                                    Text(level.attributes.displayName).tag(level.id)
                                }
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
    
    private func loadUserProfile() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let userTask = strapiService.fetchCurrentUser()
            async let levelsTask = strapiService.fetchProficiencyLevels(locale: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")
            
            let (user, levels) = try await (userTask, levelsTask)
            
            self.proficiencyLevels = levels
            self.username = user.username
            self.email = user.email
            
            // CORRECTED: This logic is now crash-proof and correctly handles the string key.
            // 1. Get the proficiency key (string) from the user data.
            let userProficiencyKey = user.user_profile?.proficiency
            
            // 2. Find the corresponding ProficiencyLevel object in the levels array.
            let selectedLevel = levels.first { $0.attributes.key == userProficiencyKey }
            
            // 3. Set the proficiencyId state from the found level's ID.
            //    If no level is found or the levels array is empty, it safely defaults to 0.
            self.proficiencyId = selectedLevel?.id ?? levels.first?.id ?? 0
            
            self.remindersEnabled = user.user_profile?.reminder_enabled ?? false
            
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            alertMessage = "Could not load your profile. Please try again."
            showAlert = true
        }
    }
    
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
    
    private func updateLearningPreferences(userId: Int, messages: inout [String]) async {
        // CORRECTED: Find the selected proficiency object based on the `proficiencyId`.
        guard let selectedProficiency = proficiencyLevels.first(where: { $0.id == self.proficiencyId }) else {
            messages.append("Could not save proficiency, levels were not loaded correctly.")
            return
        }
        
        // Get the string `key` from the selected object.
        let proficiencyKeyToSave = selectedProficiency.attributes.key
        
        do {
            // Pass the correct string `key` to the service.
            try await strapiService.updateUserProfile(
                userId: userId,
                proficiencyKey: proficiencyKeyToSave,
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
