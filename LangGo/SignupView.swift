import Foundation
import SwiftUI
import KeychainAccess
import os

struct SignupView: View {
    // Access the shared language settings from the environment.
    @EnvironmentObject var languageSettings: LanguageSettings
    
    // This binding allows us to switch back to the login view.
    @Binding var currentView: LoginView.ViewState
    // This binding allows us to change the global authentication state.
    @Binding var authState: AuthState
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = "" // This is a @State property

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
        // The toolbar now contains both the back button and the new icon-based language picker.
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { currentView = .login }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Language", selection: $languageSettings.selectedLanguageCode) { //
                        ForEach(languageSettings.availableLanguages) { language in
                            Text(language.name).tag(language.id) //
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide the default back button
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
                let payload = RegistrationPayload(
                    email: email,
                    password: password,
                    username: email, // Strapi still needs a username; email is a safe default.
                    baseLanguage: languageSettings.selectedLanguageCode
                )
                
                // Use StrapiService for signup
                let authResponse = try await StrapiService.shared.signup(payload: payload)
                
                // Store credentials and set app state to logged in
                keychain["jwt"] = authResponse.jwt
                UserDefaults.standard.set(authResponse.user.username, forKey: "username")
                UserDefaults.standard.set(authResponse.user.email, forKey: "email")
                UserDefaults.standard.set(authResponse.user.id, forKey: "userId")
                
                // This will switch the root view to MainView
                authState = .loggedIn
                logger.info("Signup successful. User: \(authResponse.user.username, privacy: .public)")
                
            } catch {
                // FIX: Create a local variable to hold the error text to avoid capturing '@State errorMessage'
                var displayErrorMessage: String
                switch error {
                case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                    displayErrorMessage = nsError.localizedDescription
                default:
                    displayErrorMessage = "An unexpected error occurred during registration: \(error.localizedDescription)"
                }
                self.errorMessage = displayErrorMessage // Update @State property
                logger.error("Signup failed: \(displayErrorMessage, privacy: .public)") // Pass local variable
            }
        }
    }
}
