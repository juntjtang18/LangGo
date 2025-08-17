// LangGo/SignupView.swift
import Foundation
import SwiftUI
import KeychainAccess
import os

struct SignupView: View {
    @EnvironmentObject var languageSettings: LanguageSettings
    @Binding var currentView: LoginView.ViewState
    @Binding var authState: AuthState
    var onboardingData: OnboardingData?

    // The view now gets its service dependency directly from the singleton.
    private let strapiService = DataServices.shared.strapiService

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "SignupView")

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up for LangGo")
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            // 👇 New explicit picker row
            HStack {
                Label("Native language", systemImage: "globe")
                Spacer()
                Picker("Native language", selection: $languageSettings.selectedLanguageCode) {
                    ForEach(LanguageSettings.availableLanguages) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .pickerStyle(.menu) // simple inline menu
            }
            .padding(.horizontal)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }

            Button(action: { signup() }) {
                Text("Sign Up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { currentView = .login }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    func signup() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        Task {
            do {
                // MODIFIED: The payload now correctly sends the proficiency *key* (string).
                let payload = RegistrationPayload(
                    email: email,
                    password: password,
                    username: email,
                    baseLanguage: languageSettings.selectedLanguageCode,
                    telephone: nil,
                    proficiency: onboardingData?.proficiencyKey,
                    reminder_enabled: onboardingData?.remindersEnabled
                )

                let authResponse: AuthResponse = try await strapiService.signup(payload: payload)
                keychain["jwt"] = authResponse.jwt
                UserSessionManager.shared.login(user: authResponse.user)
                //UserDefaults.standard.set(authResponse.user.username, forKey: "username")
                //UserDefaults.standard.set(authResponse.user.email,    forKey: "email")
                //UserDefaults.standard.set(authResponse.user.id,       forKey: "userId")

                authState = .loggedIn
                logger.info("Signup successful. User: \(authResponse.user.username, privacy: .public)")
            } catch {
                let displayErrorMessage: String
                if let ns = error as NSError?, ns.domain == "NetworkManager.StrapiError" {
                    displayErrorMessage = ns.localizedDescription
                } else {
                    displayErrorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                }
                errorMessage = displayErrorMessage
                logger.error("Signup failed: \(displayErrorMessage, privacy: .public)")
            }
        }
    }
}
