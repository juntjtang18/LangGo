import SwiftUI
import KeychainAccess
import os

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss

    // ✅ Use the session (single source of truth) instead of UserDefaults
    @EnvironmentObject var userSession: UserSessionManager

    private let authService = DataServices.shared.authService

    // State for existing fields
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""

    // State for new profile fields
    @State private var proficiencyId: Int = 0
    @State private var proficiencyLevels: [ProficiencyLevel] = []

    // Base language
    @State private var baseLanguageCode: String = "en"
    private let availableLanguages = LanguageSettings.availableLanguages

    @State private var remindersEnabled: Bool = false

    // UI state
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
                        Picker("Base Language", selection: $baseLanguageCode) {
                            ForEach(availableLanguages) { lang in
                                Text(lang.name).tag(lang.id)
                            }
                        }

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
                    ProgressView().scaleEffect(1.5)
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

    // MARK: - Data loading

    private func loadUserProfile() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Always fetch fresh and reflect into session
            let user = try await authService.fetchCurrentUser()
            UserSessionManager.shared.login(user: user) // keeps session in sync

            // Use user's baseLanguage (fallback to "en") to fetch levels
            let locale = user.user_profile?.baseLanguage ?? "en"
            let levels = try await DataServices.shared.settingsService.fetchProficiencyLevels(locale: locale)

            // Fill UI state
            self.proficiencyLevels = levels
            self.username = user.username
            self.email = user.email
            self.baseLanguageCode = user.user_profile?.baseLanguage ?? "en"
            self.remindersEnabled = user.user_profile?.reminder_enabled ?? false

            let selectedKey = user.user_profile?.proficiency
            self.proficiencyId = levels.first(where: { $0.attributes.key == selectedKey })?.id
                ?? levels.first?.id ?? 0

        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            alertMessage = "Could not load your profile. Please try again."
            showAlert = true
        }
    }

    // MARK: - Save

    private func updateProfile() async {
        isLoading = true
        defer { isLoading = false }

        guard let currentUser = userSession.currentUser else {
            alertMessage = "No active user. Please log in again."
            showAlert = true
            return
        }

        var messages: [String] = []

        await updateLearningPreferences(userId: currentUser.id, messages: &messages)

        // Only call username update if actually changed
        if !username.isEmpty && username != currentUser.username {
            await updateUsername(userId: currentUser.id, messages: &messages)
        }

        if !newPassword.isEmpty {
            await changePassword(messages: &messages)
        }

        alertMessage = messages.isEmpty ? "No changes were made." : messages.joined(separator: "\n")
        showAlert = true
    }

    private func updateLearningPreferences(userId: Int, messages: inout [String]) async {
        guard let selectedLevel = proficiencyLevels.first(where: { $0.id == self.proficiencyId }) else {
            messages.append("Could not save proficiency, levels were not loaded correctly.")
            return
        }

        let proficiencyKeyToSave = selectedLevel.attributes.key

        do {
            let payload = UserProfileUpdatePayload(
                baseLanguage: baseLanguageCode,
                proficiency: proficiencyKeyToSave,
                reminder_enabled: remindersEnabled
            )

            try await authService.updateUserProfile(userId: userId, payload: payload)

            // ✅ Reflect changes into the in-memory session user (so UI stays consistent)
            if let old = userSession.currentUser {
                let updatedProfile = UserProfileAttributes(
                    proficiency: proficiencyKeyToSave,
                    reminder_enabled: remindersEnabled,
                    baseLanguage: baseLanguageCode,
                    telephone: old.user_profile?.telephone
                )
                let updatedUser = StrapiUser(
                    id: old.id,
                    username: old.username,
                    email: old.email,
                    user_profile: updatedProfile
                )
                userSession.currentUser = updatedUser
            }

            messages.append("Learning preferences updated.")
            logger.info("User preferences updated for user ID \(userId).")
        } catch {
            let errorText = "Failed to update preferences: \(error.localizedDescription)"
            messages.append(errorText)
            logger.error("\(errorText, privacy: .public)")
        }
    }

    private func updateUsername(userId: Int, messages: inout [String]) async {
        do {
            let updatedUser = try await authService.updateUsername(userId: userId, username: username)

            // ✅ Update the in-memory session user
            userSession.currentUser = updatedUser

            messages.append("Username updated successfully!")
            logger.info("Username updated to \(updatedUser.username, privacy: .public)")
        } catch {
            let msg: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                msg = nsError.localizedDescription
            default:
                msg = "Failed to update username: \(error.localizedDescription)"
            }
            messages.append(msg)
            logger.error("Failed to update username: \(msg, privacy: .public)")
        }
    }

    private func changePassword(messages: inout [String]) async {
        guard newPassword == confirmNewPassword else {
            messages.append("Failed to change password: New passwords do not match.")
            return
        }

        do {
            let _: EmptyResponse = try await authService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmNewPassword: confirmNewPassword
            )
            messages.append("Password changed successfully!")
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
            logger.info("Password changed successfully.")
        } catch {
            let msg: String
            switch error {
            case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                msg = nsError.localizedDescription
            default:
                msg = "Failed to change password: \(error.localizedDescription)"
            }
            messages.append(msg)
            logger.error("Failed to change password: \(msg, privacy: .public)")
        }
    }
}
