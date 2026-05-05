import SwiftUI
import KeychainAccess
import os
import AVFoundation

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var languageSettings: LanguageSettings
    @EnvironmentObject private var userSession: UserSessionManager

    let showsDismissButton: Bool
    let onLogout: (() -> Void)?

    private let authService = DataServices.shared.authService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ProfileView")
    private let keychain = Keychain(service: Config.keychainService)

    @State private var username: String = ""
    @State private var email: String = ""
    @State private var fullName: String = ""
    @State private var phoneNumber: String = ""
    @State private var bio: String = ""
    @State private var proficiencyId: Int = 0
    @State private var proficiencyLevels: [ProficiencyLevel] = []
    @State private var baseLanguageCode: String = "en"
    @State private var remindersEnabled = false

    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isLoading = false
    @State private var isUpdatingReminders = false
    @State private var isUpdatingBaseLanguage = false
    @State private var isShowingEditProfile = false
    @State private var isShowingLanguageSelection = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingTermsOfService = false
    @State private var isShowingPrivacySecurity = false

    private let availableLanguages = LanguageSettings.availableLanguages

    init(showsDismissButton: Bool = true, onLogout: (() -> Void)? = nil) {
        self.showsDismissButton = showsDismissButton
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        profileHeaderCard

                        profileSection(
                            title: "ACCOUNT",
                            items: [
                                .init(
                                    title: "Privacy & Security",
                                    subtitle: "Password, data privacy",
                                    icon: "lock.fill",
                                    iconTint: Color(red: 0.35, green: 0.63, blue: 0.98),
                                    iconBackground: Color(red: 0.92, green: 0.96, blue: 1.00),
                                    action: { isShowingPrivacySecurity = true }
                                )
                            ]
                        )

                        notificationsSection

                        profileSection(
                            title: "PREFERENCES",
                            items: [
                                .init(
                                    title: "Language",
                                    subtitle: currentLanguageName,
                                    icon: "globe",
                                    iconTint: Color(red: 0.43, green: 0.39, blue: 0.99),
                                    iconBackground: Color(red: 0.94, green: 0.93, blue: 1.00),
                                    action: { isShowingLanguageSelection = true }
                                )
                            ]
                        )

                        profileSection(
                            title: "LEGAL",
                            items: [
                                .init(
                                    title: "Privacy Policy",
                                    subtitle: "How we handle your data",
                                    icon: "shield.fill",
                                    iconTint: Color(red: 0.55, green: 0.59, blue: 0.68),
                                    iconBackground: Color(red: 0.95, green: 0.96, blue: 0.97),
                                    action: { isShowingPrivacyPolicy = true }
                                ),
                                .init(
                                    title: "Terms of Service",
                                    subtitle: "User agreement",
                                    icon: "doc.text.fill",
                                    iconTint: Color(red: 0.55, green: 0.59, blue: 0.68),
                                    iconBackground: Color(red: 0.95, green: 0.96, blue: 0.97),
                                    action: { isShowingTermsOfService = true }
                                )
                            ]
                        )

                        profileSection(
                            title: "ABOUT",
                            items: [],
                            footer: "Version 1.0.0"
                        )

                        logoutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $isShowingPrivacySecurity) {
                ProfilePrivacySecurityView(
                    onAccountDeleted: {
                        keychain["jwt"] = nil
                        userSession.logout()
                        onLogout?()
                        if showsDismissButton {
                            dismiss()
                        }
                    }
                )
            }
            .navigationDestination(isPresented: $isShowingLanguageSelection) {
                ProfileBaseLanguageView(
                    availableLanguages: availableLanguages,
                    selectedLanguageCode: baseLanguageCode,
                    isSaving: isUpdatingBaseLanguage,
                    onSave: { languageCode in
                        await updateBaseLanguage(to: languageCode)
                    }
                )
            }
            .navigationDestination(isPresented: $isShowingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .navigationDestination(isPresented: $isShowingTermsOfService) {
                TermsOfServiceView()
            }
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            dismiss()
                        }
                    }
                }
            }
            .task {
                await loadUserProfile()
            }
            .sheet(isPresented: $isShowingEditProfile) {
                NavigationStack {
                    ProfileEditView(
                        fullName: $fullName,
                        username: $username,
                        email: email,
                        avatarImageURL: avatarImageURL,
                        phoneNumber: $phoneNumber,
                        bio: $bio,
                        isLoading: isLoading,
                        onSave: {
                            Task {
                                await updateProfile()
                            }
                        }
                    )
                }
            }
            .alert("Profile", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ProfileAvatarCircle(
                    imageURL: avatarImageURL,
                    initials: initialsText,
                    size: 58,
                    fontSize: 24
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.21))

                    Text(email)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.47, green: 0.50, blue: 0.56))

                    Text(joinedLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.60, green: 0.63, blue: 0.69))
                }
            }

            Button {
                isShowingEditProfile = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Edit Profile")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.09, green: 0.47, blue: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: 1)
        )
    }

    private func profileSection(title: String, items: [ProfileMenuItem], footer: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.61, green: 0.63, blue: 0.68))
                .padding(.leading, 10)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        item.action()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(item.iconBackground)
                                    .frame(width: 28, height: 28)

                                Image(systemName: item.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(item.iconTint)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.23))

                                Text(item.subtitle)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.64))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.77, green: 0.78, blue: 0.82))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                if let footer {
                    if !items.isEmpty {
                        Divider()
                    }
                    HStack {
                        Text(footer)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.60, green: 0.62, blue: 0.68))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTIFICATIONS")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.61, green: 0.63, blue: 0.68))
                .padding(.leading, 10)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.93, green: 0.99, blue: 0.94))
                        .frame(width: 42, height: 42)

                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.42, green: 0.84, blue: 0.53))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Word Review Reminders")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.23))

                    Text("Notify when words are due")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.64))
                }

                Spacer(minLength: 8)

                if isUpdatingReminders {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 51, height: 31)
                } else {
                    Toggle("", isOn: reminderToggleBinding)
                        .labelsHidden()
                        .tint(Color(red: 0.27, green: 0.75, blue: 0.37))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 74)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: 1)
            )
            .opacity(isUpdatingReminders ? 0.92 : 1)
        }
        .animation(.easeInOut(duration: 0.18), value: isUpdatingReminders)
    }

    private var logoutButton: some View {
        Button {
            keychain["jwt"] = nil
            userSession.logout()
            onLogout?()
            if showsDismissButton {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                Text("Log Out")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.red.opacity(0.75), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var currentLanguageName: String {
        availableLanguages.first(where: { $0.id == baseLanguageCode })?.name ?? "English"
    }

    private var initialsText: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "LG" : letters.uppercased()
    }

    private var avatarImageURL: URL? {
        resolvedMediaURL(from: userSession.currentUser?.user_profile?.avatar_img?.data?.attributes.url)
    }

    private var displayName: String {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return username.isEmpty ? "LangGo User" : username
    }

    private var joinedLabel: String {
        "Joined January 2026"
    }

    private var reminderToggleBinding: Binding<Bool> {
        Binding(
            get: { remindersEnabled },
            set: { newValue in
                let previousValue = remindersEnabled
                remindersEnabled = newValue
                Task {
                    await updateReminderEnabled(to: newValue, previousValue: previousValue)
                }
            }
        )
    }

    private func showPlaceholder(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func loadUserProfile() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await authService.fetchCurrentUser()
            UserSessionManager.shared.login(user: user)

            let locale = user.user_profile?.baseLanguage ?? "en"
            let levels = try await DataServices.shared.settingsService.fetchProficiencyLevels(locale: locale)

            proficiencyLevels = levels
            username = user.username
            fullName = UserDefaults.standard.string(forKey: "profileDisplayName") ?? user.username
            email = user.email
            baseLanguageCode = user.user_profile?.baseLanguage ?? "en"
            remindersEnabled = user.user_profile?.reminder_enabled ?? false
            phoneNumber = user.user_profile?.telephone ?? UserDefaults.standard.string(forKey: "profilePhoneNumber") ?? ""
            bio = user.user_profile?.bio ?? UserDefaults.standard.string(forKey: "profileBio") ?? ""

            let selectedKey = user.user_profile?.proficiency
            proficiencyId = levels.first(where: { $0.attributes.key == selectedKey })?.id ?? levels.first?.id ?? 0
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription, privacy: .public)")
            alertMessage = "Could not load your profile. Please try again."
            showAlert = true
        }
    }

    private func updateProfile() async {
        isLoading = true
        defer { isLoading = false }

        guard let currentUser = userSession.currentUser else {
            alertMessage = "No active user. Please log in again."
            showAlert = true
            return
        }

        let didSave = await updateUserProfileDetails(userId: currentUser.id)

        guard didSave else { return }

        UserDefaults.standard.set(fullName, forKey: "profileDisplayName")
        UserDefaults.standard.set(phoneNumber, forKey: "profilePhoneNumber")
        UserDefaults.standard.set(bio, forKey: "profileBio")
        isShowingEditProfile = false
    }

    private func updateUserProfileDetails(userId: Int) async -> Bool {
        guard let selectedLevel = proficiencyLevels.first(where: { $0.id == proficiencyId }) else {
            alertMessage = "Could not save proficiency, levels were not loaded correctly."
            showAlert = true
            return false
        }

        let proficiencyKeyToSave = selectedLevel.attributes.key

        do {
            let payload = UserProfileUpdatePayload(
                baseLanguage: baseLanguageCode,
                proficiency: proficiencyKeyToSave,
                reminder_enabled: remindersEnabled,
                telephone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )

            try await authService.updateUserProfile(userId: userId, payload: payload)

            if let old = userSession.currentUser {
                let updatedProfile = UserProfileAttributes(
                    proficiency: proficiencyKeyToSave,
                    reminder_enabled: remindersEnabled,
                    baseLanguage: baseLanguageCode,
                    telephone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    avatar_img: old.user_profile?.avatar_img,
                    visible_on_ladder: old.user_profile?.visible_on_ladder
                )
                let updatedUser = StrapiUser(
                    id: old.id,
                    username: old.username,
                    email: old.email,
                    user_profile: updatedProfile
                )
                userSession.currentUser = updatedUser
            }

            logger.info("User profile updated for user ID \(userId).")
            return true
        } catch {
            alertMessage = "Failed to update profile: \(error.localizedDescription)"
            showAlert = true
            let errorText = alertMessage
            logger.error("\(errorText, privacy: .public)")
            return false
        }
    }

    @MainActor
    private func updateReminderEnabled(to newValue: Bool, previousValue: Bool) async {
        guard !isUpdatingReminders else { return }
        guard let currentUser = userSession.currentUser else {
            remindersEnabled = previousValue
            alertMessage = "No active user. Please log in again."
            showAlert = true
            return
        }

        isUpdatingReminders = true
        defer { isUpdatingReminders = false }

        do {
            let currentProfile = currentUser.user_profile
            let payload = UserProfileUpdatePayload(
                baseLanguage: currentProfile?.baseLanguage ?? baseLanguageCode,
                proficiency: currentProfile?.proficiency,
                reminder_enabled: newValue,
                telephone: currentProfile?.telephone,
                bio: currentProfile?.bio,
                visible_on_ladder: currentProfile?.visible_on_ladder
            )

            try await authService.updateUserProfile(userId: currentUser.id, payload: payload)

            let updatedProfile = UserProfileAttributes(
                proficiency: currentProfile?.proficiency,
                reminder_enabled: newValue,
                baseLanguage: currentProfile?.baseLanguage ?? baseLanguageCode,
                telephone: currentProfile?.telephone,
                bio: currentProfile?.bio,
                avatar_img: currentProfile?.avatar_img,
                visible_on_ladder: currentProfile?.visible_on_ladder
            )

            userSession.currentUser = StrapiUser(
                id: currentUser.id,
                username: currentUser.username,
                email: currentUser.email,
                user_profile: updatedProfile
            )
        } catch {
            remindersEnabled = previousValue
            alertMessage = "Failed to update notifications: \(error.localizedDescription)"
            showAlert = true
            logger.error("Failed to update reminder setting: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func updateBaseLanguage(to languageCode: String) async {
        guard !isUpdatingBaseLanguage else { return }
        guard languageCode != baseLanguageCode else {
            isShowingLanguageSelection = false
            return
        }

        isUpdatingBaseLanguage = true
        defer { isUpdatingBaseLanguage = false }

        do {
            try await authService.updateBaseLanguage(languageCode: languageCode)
            baseLanguageCode = languageCode
            languageSettings.applyLocalSelection(languageCode)
            isShowingLanguageSelection = false
        } catch {
            alertMessage = "Failed to update base language: \(error.localizedDescription)"
            showAlert = true
            logger.error("Failed to update base language: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct ProfileMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let iconBackground: Color
    let action: () -> Void
}

private struct PrivacyPolicySection: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
}

private struct PrivacyPolicyView: View {
    private let sections: [PrivacyPolicySection] = [
        .init(
            title: "Overview",
            paragraphs: [
                "LangGo is a language-learning app focused on vocabulary review and article reading. This Privacy Policy explains what information the app uses and how that information supports the product."
            ]
        ),
        .init(
            title: "Information We Use",
            paragraphs: [
                "Your account information may include your email address, username, profile settings, avatar image, and language preferences.",
                "Learning data may include vocabulary entries, flashcard review progress, saved articles, article tags, and related study activity you create inside the app."
            ]
        ),
        .init(
            title: "How Information Is Used",
            paragraphs: [
                "We use account and profile information to authenticate you, keep your preferences in sync, and personalize the learning experience.",
                "We use study data to provide vocabulary review, article reading, language assistance, and progress-related features inside the app."
            ]
        ),
        .init(
            title: "Camera, Photos, and Microphone",
            paragraphs: [
                "If you choose to scan an article or update your profile photo, the app may request access to your camera or photo library.",
                "If you use speaking or pronunciation features, the app may request microphone or speech recognition access. These permissions are only used for the features you choose to use."
            ]
        ),
        .init(
            title: "Third-Party Services",
            paragraphs: [
                "The app communicates with LangGo backend services to store account data, study content, and learning progress.",
                "If the app uses platform services such as Apple system frameworks for speech, media, or notifications, those services are used only to support app functionality."
            ]
        ),
        .init(
            title: "Data Retention and Account Control",
            paragraphs: [
                "Your learning data and profile information remain associated with your account until you edit or delete them, or until you delete your account.",
                "If you delete your account from the app, the request is sent to the backend and your account data is scheduled for removal according to backend handling rules."
            ]
        ),
        .init(
            title: "Data Sharing",
            paragraphs: [
                "LangGo does not sell your personal information. Information is shared only as needed to operate the service, comply with legal obligations, or fulfill requests you initiate inside the app."
            ]
        ),
        .init(
            title: "Contact",
            paragraphs: [
                "If you have questions about privacy or data handling, contact the LangGo support team using the support channel provided in the app or on the LangGo website."
            ]
        ),
        .init(
            title: "Effective Date",
            paragraphs: [
                "Effective date: April 21, 2026."
            ]
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                policyIntroCard

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.22))

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color(red: 0.37, green: 0.39, blue: 0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var policyIntroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LangGo Privacy Policy")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.22))

            Text("This policy explains how LangGo uses account information, learning content, and device permissions when you use the app.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.39, blue: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.00),
                    Color(red: 0.98, green: 0.99, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.87, green: 0.90, blue: 0.96), lineWidth: 1)
        )
    }
}

private struct TermsSection: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
}

private struct TermsOfServiceView: View {
    private let sections: [TermsSection] = [
        .init(
            title: "Acceptance of Terms",
            paragraphs: [
                "By creating an account, accessing, or using LangGo, you agree to these Terms of Service. If you do not agree, you should stop using the app and related services."
            ]
        ),
        .init(
            title: "Eligibility and Account Responsibility",
            paragraphs: [
                "You are responsible for maintaining the confidentiality of your account credentials and for activity that occurs under your account.",
                "You agree to provide accurate account information and to keep your profile information reasonably up to date."
            ]
        ),
        .init(
            title: "Service Description",
            paragraphs: [
                "LangGo provides vocabulary learning, flashcard review, article reading, OCR-based article import, and related language-learning tools.",
                "Features may change over time. We may modify, improve, limit, or discontinue parts of the service as needed."
            ]
        ),
        .init(
            title: "User Content",
            paragraphs: [
                "You may create or upload content such as saved words, articles, tags, profile text, and images. You remain responsible for the content you submit.",
                "You represent that you have the right to upload or use the content you submit and that it does not violate applicable law or the rights of others."
            ]
        ),
        .init(
            title: "Acceptable Use",
            paragraphs: [
                "You agree not to use LangGo to upload unlawful, infringing, abusive, deceptive, or harmful content.",
                "You agree not to interfere with the service, attempt unauthorized access, abuse APIs or infrastructure, or use the app in a way that could impair service availability for others."
            ]
        ),
        .init(
            title: "Subscriptions, Payments, and Purchases",
            paragraphs: [
                "If paid plans, subscriptions, or in-app purchases are offered, billing and renewal terms will be presented at the time of purchase.",
                "Apple-managed purchases are subject to Apple’s billing rules, including renewal, cancellation, and refund handling where applicable."
            ]
        ),
        .init(
            title: "Privacy",
            paragraphs: [
                "Your use of LangGo is also governed by the Privacy Policy. Please review the Privacy Policy to understand how account data, learning data, and permissions are used."
            ]
        ),
        .init(
            title: "Termination",
            paragraphs: [
                "You may stop using the service at any time. You may also request account deletion through the app where that feature is available.",
                "We may suspend or terminate access if we reasonably believe you violated these Terms, abused the service, or created legal, operational, or security risk."
            ]
        ),
        .init(
            title: "Disclaimers",
            paragraphs: [
                "LangGo is provided on an \"as is\" and \"as available\" basis to the extent permitted by law. We do not guarantee uninterrupted availability, complete accuracy, or that the service will always be error-free.",
                "Language-learning suggestions, OCR extraction, translations, and AI-assisted outputs may be incomplete or inaccurate and should be reviewed by the user."
            ]
        ),
        .init(
            title: "Limitation of Liability",
            paragraphs: [
                "To the extent permitted by law, LangGo and its operators are not liable for indirect, incidental, special, consequential, or exemplary damages arising from your use of the service.",
                "Where liability cannot be excluded, it will be limited to the minimum extent permitted by applicable law."
            ]
        ),
        .init(
            title: "Changes to These Terms",
            paragraphs: [
                "We may update these Terms from time to time. Continued use of the service after updated terms take effect means you accept the revised Terms."
            ]
        ),
        .init(
            title: "Contact",
            paragraphs: [
                "If you have questions about these Terms, contact the LangGo support team through the support channel provided in the app or on the LangGo website."
            ]
        ),
        .init(
            title: "Effective Date",
            paragraphs: [
                "Effective date: April 21, 2026."
            ]
        )
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                introCard

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.22))

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color(red: 0.37, green: 0.39, blue: 0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LangGo Terms of Service")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.22))

            Text("These terms describe the rules for using LangGo, your account responsibilities, and the limits and conditions that apply to the service.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.39, blue: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.00),
                    Color(red: 0.99, green: 0.99, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.90, blue: 0.95), lineWidth: 1)
        )
    }
}

private struct ProfileBaseLanguageView: View {
    let availableLanguages: [Language]
    let selectedLanguageCode: String
    let isSaving: Bool
    let onSave: @MainActor (String) async -> Void

    @State private var draftLanguageCode: String

    init(
        availableLanguages: [Language],
        selectedLanguageCode: String,
        isSaving: Bool,
        onSave: @escaping @MainActor (String) async -> Void
    ) {
        self.availableLanguages = availableLanguages
        self.selectedLanguageCode = selectedLanguageCode
        self.isSaving = isSaving
        self.onSave = onSave
        _draftLanguageCode = State(initialValue: selectedLanguageCode)
    }

    var body: some View {
        List {
            Section {
                ForEach(availableLanguages) { language in
                    Button {
                        draftLanguageCode = language.id
                    } label: {
                        HStack(spacing: 12) {
                            Text(language.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primary)

                            Spacer()

                            if draftLanguageCode == language.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.09, green: 0.47, blue: 0.95))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            } footer: {
                Text("Choose the language you want LangGo to use as your native language when learning vocabulary.")
            }
        }
        .navigationTitle("Base Language")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            await onSave(draftLanguageCode)
                        }
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .disabled(draftLanguageCode == selectedLanguageCode)
                }
            }
        }
    }
}

private struct ProfilePrivacySecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSession: UserSessionManager
    @FocusState private var focusedField: PasswordField?
    let onAccountDeleted: () -> Void
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var expandedSection: SecuritySection?
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isUpdatingPassword = false
    @State private var isShowingCurrentPassword = false
    @State private var isShowingNewPassword = false
    @State private var isShowingConfirmNewPassword = false
    @State private var deleteConfirmationText = ""
    @State private var deleteAccountPassword = ""
    @State private var isShowingDeletePasswordPrompt = false
    @State private var visibleOnLadder = true
    @State private var isUpdatingVisibleOnLadder = false
    @State private var isDeletingAccount = false

    private let authService = DataServices.shared.authService

    private enum SecuritySection {
        case changePassword
        case dataPrivacy
        case deleteAccount
    }

    private enum PasswordField {
        case currentPassword
        case newPassword
        case confirmNewPassword
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    changePasswordSection

                    dataPrivacySection

                    deleteAccountSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.09, green: 0.47, blue: 0.95))
                }
            }

            ToolbarItem(placement: .principal) {
                Text("Privacy & Security")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.21))
            }
        }
        .alert("Privacy & Security", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Confirm Account Deletion", isPresented: $isShowingDeletePasswordPrompt) {
            SecureField("Current password", text: $deleteAccountPassword)
            Button("Cancel", role: .cancel) {
                deleteAccountPassword = ""
            }
            Button("Delete", role: .destructive) {
                Task {
                    await performDeleteAccount()
                }
            }
        } message: {
            Text("Enter your current password to permanently delete your account.")
        }
        .onAppear {
            visibleOnLadder = userSession.currentUser?.user_profile?.visible_on_ladder ?? true
        }
    }

    private var changePasswordSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            securityRow(
                title: "Change Password",
                subtitle: "Update your password",
                icon: "shield",
                iconTint: Color(red: 0.19, green: 0.52, blue: 0.98),
                iconBackground: Color(red: 0.92, green: 0.96, blue: 1.00),
                titleColor: Color(red: 0.18, green: 0.19, blue: 0.23),
                chevron: expandedSection == .changePassword ? "chevron.up" : "chevron.down",
                showsOuterShape: false
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedSection = expandedSection == .changePassword ? nil : .changePassword
                }
            }

            if expandedSection == .changePassword {
                Rectangle()
                    .fill(Color(red: 0.89, green: 0.90, blue: 0.93))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 16) {
                    passwordField(
                        title: "CURRENT PASSWORD",
                        placeholder: "Enter current password",
                        text: $currentPassword,
                        field: .currentPassword,
                        isRevealed: $isShowingCurrentPassword
                    )

                    passwordField(
                        title: "NEW PASSWORD",
                        placeholder: "Enter new password",
                        text: $newPassword,
                        field: .newPassword,
                        isRevealed: $isShowingNewPassword,
                        footnote: newPasswordFootnote
                    )

                    passwordField(
                        title: "CONFIRM NEW PASSWORD",
                        placeholder: "Confirm new password",
                        text: $confirmNewPassword,
                        field: .confirmNewPassword,
                        isRevealed: $isShowingConfirmNewPassword,
                        footnote: confirmPasswordFootnote,
                        footnoteColor: confirmPasswordFootnoteColor
                    )

                    Button {
                        Task {
                            await updatePassword()
                        }
                    } label: {
                        HStack {
                            if isUpdatingPassword {
                                ProgressView()
                                    .tint(Color(red: 0.50, green: 0.52, blue: 0.58))
                            } else {
                                Text("Update Password")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(Color.black)
                        .opacity(canSubmitPasswordChange ? 1 : 0.45)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(red: 0.88, green: 0.89, blue: 0.92), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmitPasswordChange || isUpdatingPassword)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.86, green: 0.88, blue: 0.92), lineWidth: 1)
        )
    }

    private var dataPrivacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            securityRow(
                title: "Data & Privacy",
                subtitle: "Manage your data",
                icon: "shield.lefthalf.filled",
                iconTint: Color(red: 0.44, green: 0.33, blue: 0.98),
                iconBackground: Color(red: 0.94, green: 0.93, blue: 1.00),
                titleColor: Color(red: 0.18, green: 0.19, blue: 0.23),
                chevron: expandedSection == .dataPrivacy ? "chevron.up" : "chevron.down",
                showsOuterShape: false
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedSection = expandedSection == .dataPrivacy ? nil : .dataPrivacy
                }
            }

            if expandedSection == .dataPrivacy {
                Rectangle()
                    .fill(Color(red: 0.89, green: 0.90, blue: 0.93))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Show me on the leaderboard")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.22))

                            Text("When enabled, your progress and rank will be visible to other users on the leaderboard")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.48, green: 0.50, blue: 0.56))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Toggle("", isOn: leaderboardVisibilityBinding)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.20, green: 0.78, blue: 0.38)))
                            .disabled(isUpdatingVisibleOnLadder)
                            .padding(.top, 2)
                    }

                    if !visibleOnLadder {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ Note")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.95, green: 0.60, blue: 0.11))

                            Text("You'll still see the leaderboard, but others won't see your rank or username.")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.30, green: 0.24, blue: 0.16))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(red: 1.00, green: 0.96, blue: 0.90))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.86, green: 0.88, blue: 0.92), lineWidth: 1)
        )
    }

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            securityRow(
                title: "Delete Account",
                subtitle: "Permanently remove your account",
                icon: "trash",
                iconTint: Color(red: 1.00, green: 0.31, blue: 0.29),
                iconBackground: Color(red: 1.00, green: 0.94, blue: 0.94),
                titleColor: Color(red: 1.00, green: 0.31, blue: 0.29),
                borderColor: Color(red: 1.00, green: 0.31, blue: 0.29),
                chevron: expandedSection == .deleteAccount ? "chevron.up" : "chevron.down",
                showsOuterShape: false
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedSection = expandedSection == .deleteAccount ? nil : .deleteAccount
                }
            }

            if expandedSection == .deleteAccount {
                Rectangle()
                    .fill(Color(red: 0.97, green: 0.82, blue: 0.82))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 16) {
                    Text("This action is permanent. Enter your current password to delete your account and sign out.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.48, green: 0.33, blue: 0.33))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ Warning")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.60, blue: 0.11))

                        Text("This action cannot be undone. All your vocabulary, progress, and account data will be permanently deleted.")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.30, green: 0.24, blue: 0.16))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(red: 1.00, green: 0.94, blue: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    deleteConfirmationField

                    Button {
                        isShowingDeletePasswordPrompt = true
                    } label: {
                        HStack {
                            if isDeletingAccount {
                                ProgressView()
                                    .tint(Color.red)
                            } else {
                                Text("Delete Account")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(Color.red)
                        .opacity(canBeginDeleteAccount ? 1 : 0.45)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.red.opacity(0.75), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canBeginDeleteAccount || isDeletingAccount)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 1.00, green: 0.31, blue: 0.29), lineWidth: 1)
        )
    }

    private var deleteConfirmationField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TYPE \"DELETE\" TO CONFIRM")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 0.67))

            TextField("DELETE", text: $deleteConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.19, green: 0.20, blue: 0.24))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.87, green: 0.88, blue: 0.91), lineWidth: 1)
                )
        }
    }

    private func securityRow(
        title: String,
        subtitle: String,
        icon: String,
        iconTint: Color,
        iconBackground: Color,
        titleColor: Color,
        borderColor: Color = Color(red: 0.86, green: 0.88, blue: 0.92),
        chevron: String = "chevron.down",
        showsOuterShape: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)

                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.64))
                }

                Spacer()

                Image(systemName: chevron)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.76, green: 0.77, blue: 0.82))
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if showsOuterShape {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func showPlaceholder(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private var canSubmitPasswordChange: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 8 &&
        !confirmNewPassword.isEmpty &&
        newPassword == confirmNewPassword
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: PasswordField,
        isRevealed: Binding<Bool>,
        footnote: String? = nil,
        footnoteColor: Color = Color(red: 0.56, green: 0.58, blue: 0.64)
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 0.67))

            HStack(spacing: 10) {
                Group {
                    if isRevealed.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.19, green: 0.20, blue: 0.24))

                Button {
                    isRevealed.wrappedValue.toggle()
                } label: {
                    Image(systemName: isRevealed.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.62, green: 0.64, blue: 0.69))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        focusedField == field
                        ? Color(red: 0.17, green: 0.51, blue: 0.98)
                        : Color(red: 0.87, green: 0.88, blue: 0.91),
                        lineWidth: focusedField == field ? 1.5 : 1
                    )
            )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(footnoteColor)
            }
        }
    }

    private var newPasswordFootnote: String {
        if newPassword.isEmpty || newPassword.count >= 8 {
            return "Must be at least 8 characters"
        }

        return "Password must be at least 8 characters"
    }

    private var confirmPasswordFootnote: String? {
        guard !confirmNewPassword.isEmpty else { return nil }
        guard newPassword != confirmNewPassword else { return nil }
        return "New password and confirmation do not match"
    }

    private var confirmPasswordFootnoteColor: Color {
        confirmPasswordFootnote == nil
        ? Color(red: 0.56, green: 0.58, blue: 0.64)
        : Color(red: 0.86, green: 0.25, blue: 0.22)
    }

    private var leaderboardVisibilityBinding: Binding<Bool> {
        Binding(
            get: { visibleOnLadder },
            set: { newValue in
                guard !isUpdatingVisibleOnLadder else { return }
                let previousValue = visibleOnLadder
                visibleOnLadder = newValue

                Task {
                    await updateVisibleOnLadder(to: newValue, previousValue: previousValue)
                }
            }
        )
    }

    private var canBeginDeleteAccount: Bool {
        deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    @MainActor
    private func updatePassword() async {
        guard newPassword.count >= 8 else {
            showPlaceholder("New password must be at least 8 characters.")
            return
        }

        guard newPassword == confirmNewPassword else {
            showPlaceholder("New password and confirmation do not match.")
            return
        }

        isUpdatingPassword = true
        defer { isUpdatingPassword = false }

        do {
            _ = try await authService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmNewPassword: confirmNewPassword
            )

            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
            focusedField = nil

            withAnimation(.easeInOut(duration: 0.18)) {
                expandedSection = nil
            }

            showPlaceholder("Password updated successfully.")
        } catch {
            showPlaceholder(error.localizedDescription)
        }
    }

    @MainActor
    private func updateVisibleOnLadder(to newValue: Bool, previousValue: Bool) async {
        guard let currentUser = userSession.currentUser else {
            visibleOnLadder = previousValue
            showPlaceholder("No active user. Please log in again.")
            return
        }

        isUpdatingVisibleOnLadder = true
        defer { isUpdatingVisibleOnLadder = false }

        do {
            let profile = currentUser.user_profile
            let payload = UserProfileUpdatePayload(
                baseLanguage: profile?.baseLanguage ?? "en",
                proficiency: profile?.proficiency,
                reminder_enabled: profile?.reminder_enabled,
                telephone: profile?.telephone,
                bio: profile?.bio,
                visible_on_ladder: newValue
            )

            try await authService.updateUserProfile(userId: currentUser.id, payload: payload)

            let updatedProfile = UserProfileAttributes(
                proficiency: profile?.proficiency,
                reminder_enabled: profile?.reminder_enabled,
                baseLanguage: profile?.baseLanguage,
                telephone: profile?.telephone,
                bio: profile?.bio,
                avatar_img: profile?.avatar_img,
                visible_on_ladder: newValue
            )

            userSession.currentUser = StrapiUser(
                id: currentUser.id,
                username: currentUser.username,
                email: currentUser.email,
                user_profile: updatedProfile
            )
        } catch {
            visibleOnLadder = previousValue
            showPlaceholder("Failed to update privacy setting: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performDeleteAccount() async {
        guard !deleteAccountPassword.isEmpty else {
            showPlaceholder("Current password is required to delete your account.")
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await authService.deleteCurrentUserAccount(currentPassword: deleteAccountPassword)
            deleteAccountPassword = ""
            deleteConfirmationText = ""
            focusedField = nil
            onAccountDeleted()
        } catch {
            deleteAccountPassword = ""
            showPlaceholder("Failed to delete account: \(error.localizedDescription)")
        }
    }
}

private struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSession: UserSessionManager
    @FocusState private var focusedField: Field?

    @Binding var fullName: String
    @Binding var username: String
    let email: String
    let avatarImageURL: URL?
    @Binding var phoneNumber: String
    @Binding var bio: String
    let isLoading: Bool
    let onSave: () -> Void
    private let authService = DataServices.shared.authService

    @State private var localAvatarImageURL: URL?
    @State private var capturedAvatarImage: UIImage?
    @State private var isShowingUploadOptions = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var isUploadingAvatar = false
    @State private var cameraAccessMessage: String?
    @State private var lastAvatarPickerSource: UIImagePickerController.SourceType = .camera

    private enum Field {
        case name
        case phone
        case bio
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatarCircle(
                                imageURL: localAvatarImageURL ?? avatarImageURL,
                                initials: initials,
                                size: 92,
                                fontSize: 36
                            )

                            Button(action: showUploadOptions) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.09, green: 0.47, blue: 0.95))
                                        .frame(width: 28, height: 28)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: 3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)

                        Button("Change Profile Photo") {
                            showUploadOptions()
                        }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.09, green: 0.47, blue: 0.95))
                            .frame(maxWidth: .infinity)
                    }

                    labeledField("USERNAME") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(username)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.54))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(Color(red: 0.95, green: 0.96, blue: 0.97))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(fieldBorder(isReadOnly: true))

                            Text("Username cannot be changed right now")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 0.67))
                                .padding(.leading, 4)
                        }
                    }

                    labeledField("EMAIL") {
                        Text(email)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.54))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color(red: 0.95, green: 0.96, blue: 0.97))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(fieldBorder(isReadOnly: true))
                    }

                    labeledField("NAME") {
                        TextField("Alex Johnson", text: $fullName)
                            .focused($focusedField, equals: .name)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(fieldBorder(for: .name))
                    }

                    labeledField("PHONE (OPTIONAL)") {
                        TextField("+1 (555) 123-4567", text: $phoneNumber)
                            .focused($focusedField, equals: .phone)
                            .keyboardType(.phonePad)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(fieldBorder(for: .phone))
                    }

                    labeledField("BIO") {
                        VStack(alignment: .trailing, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .overlay(fieldBorder(for: .bio))
                                    .frame(height: 92)

                                TextEditor(text: $bio)
                                    .focused($focusedField, equals: .bio)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(height: 76)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }

                            Text("\(min(bio.count, 150))/150")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.59, green: 0.61, blue: 0.67))
                        }
                    }

                    Button {
                        onSave()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                            Text("Save Changes")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.09, green: 0.47, blue: 0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .disabled(isLoading)
        .task {
            localAvatarImageURL = avatarImageURL
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            ProfileImagePickerView(sourceType: .camera) { image in
                capturedAvatarImage = image
                isShowingCamera = false
            } onCancel: {
                isShowingCamera = false
            }
        }
        .fullScreenCover(isPresented: $isShowingPhotoLibrary) {
            ProfileImagePickerView(sourceType: .photoLibrary) { image in
                capturedAvatarImage = image
                isShowingPhotoLibrary = false
            } onCancel: {
                isShowingPhotoLibrary = false
            }
        }
        .fullScreenCover(isPresented: isShowingPhotoReviewBinding) {
            if let capturedAvatarImage {
                ProfilePhotoReviewView(
                    image: capturedAvatarImage,
                    isProcessing: isUploadingAvatar,
                    onRetake: {
                        self.capturedAvatarImage = nil
                        reopenLastAvatarSource()
                    },
                    onConfirm: {
                        Task {
                            await uploadAvatar(capturedAvatarImage)
                        }
                    }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .alert("Profile Photo", isPresented: cameraAlertBinding) {
            Button("OK", role: .cancel) {
                cameraAccessMessage = nil
            }
        } message: {
            Text(cameraAccessMessage ?? "")
        }
        .overlay {
            if isLoading || isUploadingAvatar || isShowingUploadOptions {
                ZStack {
                    Color.black.opacity(isShowingUploadOptions ? 0.18 : 0.08)
                        .ignoresSafeArea()

                    if isShowingUploadOptions {
                        VStack {
                            Spacer()

                            ProfilePhotoOptionsSheet(
                                onClose: { isShowingUploadOptions = false },
                                onChooseFromGallery: {
                                    isShowingUploadOptions = false
                                    openPhotoLibrary()
                                },
                                onTakePhoto: {
                                    isShowingUploadOptions = false
                                    openCamera()
                                },
                                onCancel: { isShowingUploadOptions = false }
                            )
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text(isUploadingAvatar ? "Uploading Photo..." : "Saving...")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.34, green: 0.36, blue: 0.42))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                    }
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    onSave()
                }
                .disabled(isLoading)
            }
        }
    }

    private var initials: String {
        let source = fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? username : fullName
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "LG" : letters.uppercased()
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
            content()
        }
    }

    private func fieldBorder(for field: Field? = nil, isReadOnly: Bool = false) -> some View {
        let isFocused = field != nil && focusedField == field
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                isFocused ? Color(red: 0.09, green: 0.47, blue: 0.95) : (isReadOnly ? Color(red: 0.89, green: 0.90, blue: 0.93) : Color(red: 0.88, green: 0.90, blue: 0.94)),
                lineWidth: isFocused ? 1.6 : 1
            )
    }

    private func showUploadOptions() {
        isShowingUploadOptions = true
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAccessMessage = "Camera is not available on this device."
            return
        }
        lastAvatarPickerSource = .camera

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingCamera = true
                    } else {
                        cameraAccessMessage = "Please allow camera access in Settings to take a profile photo."
                    }
                }
            }
        case .denied, .restricted:
            cameraAccessMessage = "Please allow camera access in Settings to take a profile photo."
        @unknown default:
            cameraAccessMessage = "Camera access is unavailable right now."
        }
    }

    private func openPhotoLibrary() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            cameraAccessMessage = "Photo library is not available on this device."
            return
        }
        lastAvatarPickerSource = .photoLibrary
        isShowingPhotoLibrary = true
    }

    private func reopenLastAvatarSource() {
        switch lastAvatarPickerSource {
        case .camera:
            isShowingCamera = true
        case .photoLibrary, .savedPhotosAlbum:
            isShowingPhotoLibrary = true
        @unknown default:
            isShowingUploadOptions = true
        }
    }

    @MainActor
    private func uploadAvatar(_ image: UIImage) async {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        guard let imageData = image.jpegData(compressionQuality: 0.88) else {
            cameraAccessMessage = "Could not prepare the photo for upload."
            return
        }

        do {
            let previousAvatarURL = localAvatarImageURL ?? avatarImageURL
            let updatedProfile = try await authService.uploadUserAvatarImage(
                imageData,
                fileName: "avatar-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg"
            )

            if let oldUser = userSession.currentUser {
                userSession.currentUser = StrapiUser(
                    id: oldUser.id,
                    username: oldUser.username,
                    email: oldUser.email,
                    user_profile: updatedProfile
                )
            }

            let newAvatarURL = resolvedMediaURL(from: updatedProfile.avatar_img?.data?.attributes.url)
            if let previousAvatarURL {
                ImageCache.removeImage(for: previousAvatarURL)
            }
            if let newAvatarURL {
                ImageCache.removeImage(for: newAvatarURL)
            }
            localAvatarImageURL = newAvatarURL
            capturedAvatarImage = nil
        } catch {
            cameraAccessMessage = "Failed to upload profile photo: \(error.localizedDescription)"
        }
    }

    private var cameraAlertBinding: Binding<Bool> {
        Binding(
            get: { cameraAccessMessage != nil },
            set: { newValue in
                if !newValue {
                    cameraAccessMessage = nil
                }
            }
        )
    }

    private var isShowingPhotoReviewBinding: Binding<Bool> {
        Binding(
            get: { capturedAvatarImage != nil },
            set: { newValue in
                if !newValue {
                    capturedAvatarImage = nil
                }
            }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ProfileAvatarCircle: View {
    let imageURL: URL?
    let initials: String
    let size: CGFloat
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.34, blue: 0.98), Color(red: 0.56, green: 0.21, blue: 0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            if let imageURL {
                CachedAsyncImage(url: imageURL, contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct ProfilePhotoOptionsSheet: View {
    let onClose: () -> Void
    let onChooseFromGallery: () -> Void
    let onTakePhoto: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Change Profile Photo")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.55, green: 0.57, blue: 0.63))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            VStack(spacing: 14) {
                ProfilePhotoOptionCard(
                    icon: "photo",
                    iconTint: Color(red: 0.20, green: 0.56, blue: 0.98),
                    iconBackground: Color(red: 0.90, green: 0.95, blue: 1.00),
                    title: "Choose from Gallery",
                    subtitle: "Select a photo from your album",
                    action: onChooseFromGallery
                )

                ProfilePhotoOptionCard(
                    icon: "camera",
                    iconTint: Color(red: 0.25, green: 0.73, blue: 0.40),
                    iconBackground: Color(red: 0.90, green: 0.98, blue: 0.92),
                    title: "Take Photo",
                    subtitle: "Use camera to take a new photo",
                    action: onTakePhoto
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 18)

            Divider()

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.19, green: 0.20, blue: 0.24))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.86, green: 0.88, blue: 0.92), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

private struct ProfilePhotoOptionCard: View {
    let icon: String
    let iconTint: Color
    let iconBackground: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.53, green: 0.55, blue: 0.61))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private func resolvedMediaURL(from rawURL: String?) -> URL? {
    guard let rawURL, !rawURL.isEmpty else { return nil }
    if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
        return URL(string: rawURL)
    }
    return URL(string: "\(Config.strapiBaseUrl)\(rawURL)")
}

private struct ProfileImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        if sourceType == .camera {
            picker.cameraCaptureMode = .photo
        }
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onCancel()
            }
        }
    }
}

private struct ProfilePhotoReviewView: View {
    let image: UIImage
    let isProcessing: Bool
    let onRetake: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                }
                .frame(height: 52)

                Spacer(minLength: 0)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 18)

                Spacer(minLength: 18)

                HStack(spacing: 14) {
                    Button(action: onRetake) {
                        Text("Retake")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button(action: onConfirm) {
                        Text(isProcessing ? "Uploading..." : "Use Photo")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }
}
