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

    // The view now gets the service it needs directly from the singleton
    private let strapiService = DataServices.shared.strapiService
    
    private let keychain = Keychain(service: Config.keychainService)
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
                // Use the service resolved at the top of the struct
                let authResponse = try await strapiService.login(credentials: credentials)
                
                keychain["jwt"] = authResponse.jwt
                UserDefaults.standard.set(authResponse.user.username, forKey: "username")
                UserDefaults.standard.set(authResponse.user.email,    forKey: "email")
                UserDefaults.standard.set(authResponse.user.id,       forKey: "userId")

                // Use the service resolved at the top of the struct
                let vbSetting = try await strapiService.fetchVBSetting()
                UserDefaults.standard.set(Double(vbSetting.attributes.wordsPerPage), forKey: "wordCountPerPage")
                UserDefaults.standard.set(vbSetting.attributes.interval1, forKey: "interval1")
                UserDefaults.standard.set(vbSetting.attributes.interval2, forKey: "interval2")
                UserDefaults.standard.set(vbSetting.attributes.interval3, forKey: "interval3")

                authState = .loggedIn
                logger.info("Login + VBSetting load successful for user: \(authResponse.user.username, privacy: .public)")
            } catch {
                var displayErrorMessage: String
                switch error {
                case let nsError as NSError where nsError.domain == "NetworkManager.StrapiError":
                    displayErrorMessage = nsError.localizedDescription
                default:
                    displayErrorMessage = "Network error: \(error.localizedDescription)"
                }
                self.errorMessage = displayErrorMessage
                logger.error("Login failed: \(displayErrorMessage, privacy: .public)")
            }
        }
    }
}
