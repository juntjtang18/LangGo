import SwiftUI
import KeychainAccess
import os

struct LoginView: View {
    @Binding var authState: AuthState
    var onboardingData: OnboardingData?

    @State private var currentView: ViewState = .login
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @EnvironmentObject var languageSettings: LanguageSettings

    private let strapiService = DataServices.shared.strapiService
    
    private let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LoginView")

    enum ViewState {
        case login
        case signup
    }
    
    // ⬇️ NEW: initializer to control the starting tab
    init(authState: Binding<AuthState>, onboardingData: OnboardingData?, startOn: ViewState = .login) {
        self._authState = authState
        self.onboardingData = onboardingData
        self._currentView = State(initialValue: startOn)
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
                            .disabled(isLoading)

                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .disabled(isLoading)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }

                        Button(action: login) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Login")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.horizontal)
                        .disabled(isLoading)

                        Button(action: {
                            currentView = .signup
                        }) {
                            Text("Don't have an account? Sign Up")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .disabled(isLoading)
                    }
                    .padding()
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .onAppear {
                        logger.info("LoginView appeared. Strapi Base URL: \(Config.strapiBaseUrl, privacy: .public)")
                        logger.info("LoginView appeared. Learning Target Language Code: \(Config.learningTargetLanguageCode, privacy: .public)")
                    }
                } else if currentView == .signup {
                    SignupView(
                        currentView: $currentView,
                        authState: $authState,
                        onboardingData: onboardingData
                    )
                }
            }
        }
    }

    func login() {
        isLoading = true
        errorMessage = "" // Clear previous errors
        
        logger.info("Attempting login...")
        logger.info("Login function. Strapi Base URL: \(Config.strapiBaseUrl, privacy: .public)")
        logger.info("Login function. Learning Target Language Code: \(Config.learningTargetLanguageCode, privacy: .public)")

        Task {
            do {
                let credentials = LoginCredentials(identifier: email, password: password)
                let authResponse = try await strapiService.login(credentials: credentials)
                UserSessionManager.shared.login(user: authResponse.user)
                keychain["jwt"] = authResponse.jwt
                languageSettings.selectedLanguageCode = authResponse.user.user_profile?.baseLanguage ?? "en"
                
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
            
            isLoading = false
        }
    }
}
