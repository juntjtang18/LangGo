import SwiftUI
import KeychainAccess
import os

struct LoginView: View {
    @Binding var authState: AuthState
    @State private var currentView: ViewState = .login
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    
    @EnvironmentObject var languageSettings: LanguageSettings

    let keychain = Keychain(service: Config.keychainService)
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LoginView")

    enum ViewState {
        case login
        case signup
    }

    var body: some View {
        NavigationStack {
            Group {
                if currentView == .login {
                    VStack(spacing: 20) {
                        Text("Welcome to LangGo")
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

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }

                        Button(action: {
                            login()
                        }) {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal)

                        Button(action: {
                            currentView = .signup
                        }) {
                            Text("Don't have an account? Sign Up")
                                .foregroundColor(.blue)
                        }
                        .padding()
                    }
                    .padding()
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Picker("Language", selection: $languageSettings.selectedLanguageCode) {
                                    ForEach(languageSettings.availableLanguages) { language in
                                        Text(language.name).tag(language.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "globe")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .onAppear {
                        logger.info("LoginView appeared. Strapi Base URL: \(Config.strapiBaseUrl, privacy: .public)")
                        logger.info("LoginView appeared. Learning Target Language Code: \(Config.learningTargetLanguageCode, privacy: .public)")
                    }
                } else if currentView == .signup {
                    SignupView(currentView: $currentView, authState: $authState)
                }
            }
        }
    }

    func login() {
        logger.info("Attempting login...")
        logger.info("Login function. Strapi Base URL: \(Config.strapiBaseUrl, privacy: .public)")
        logger.info("Login function. Learning Target Language Code: \(Config.learningTargetLanguageCode, privacy: .public)")

        Task {
            do {
                let credentials = LoginCredentials(identifier: email, password: password)
                // Use StrapiService for login
                let authResponse = try await StrapiService.shared.login(credentials: credentials)
                
                // Store the user data in Keychain and UserDefaults
                keychain["jwt"] = authResponse.jwt
                UserDefaults.standard.set(authResponse.user.username, forKey: "username")
                UserDefaults.standard.set(authResponse.user.email, forKey: "email")
                UserDefaults.standard.set(authResponse.user.id, forKey: "userId")
                
                // Set the login state to true to dismiss this view
                authState = .loggedIn
                logger.info("Login successful. User: \(authResponse.user.username, privacy: .public)")
            } catch {
                // FIX: Apply the switch statement for robust error handling
                var displayErrorMessage: String // Local variable to hold the error message
                switch error {
                case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                    displayErrorMessage = nsError.localizedDescription
                default:
                    displayErrorMessage = "Network error: \(error.localizedDescription)"
                }
                self.errorMessage = displayErrorMessage // Update @State property
                logger.error("Login failed: \(displayErrorMessage, privacy: .public)") // Pass local variable
            }
        }
    }
}
