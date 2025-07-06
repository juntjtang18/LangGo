import SwiftUI
import KeychainAccess
import os // Added import for Logger

struct LoginView: View {
    @Binding var authState: AuthState
    @State private var currentView: ViewState = .login
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    
    // Access the shared language settings from the environment
    @EnvironmentObject var languageSettings: LanguageSettings

    // Use the centralized keychain service from the Config file.
    let keychain = Keychain(service: Config.keychainService)
    
    // Logger instance
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LoginView") // Added Logger

    enum ViewState {
        case login
        case signup
    }

    var body: some View {
        // A NavigationStack is added to host the toolbar for the language picker.
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
                    // An empty title is used to make the navigation bar visible without showing text.
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            // The Picker has been replaced with a Menu, using a globe icon as its label.
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
                    .onAppear { // Added onAppear to log config values
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
        // Added logging before the request
        logger.info("Attempting login...")
        logger.info("Login function. Strapi Base URL: \(Config.strapiBaseUrl, privacy: .public)")
        logger.info("Login function. Learning Target Language Code: \(Config.learningTargetLanguageCode, privacy: .public)")


        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else {
            errorMessage = "Invalid server URL"
            logger.error("Invalid server URL for login: \(Config.strapiBaseUrl, privacy: .public)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["identifier": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    logger.error("Network error during login: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    errorMessage = "Invalid response from server"
                    logger.error("Invalid HTTP response during login. Response was not HTTPURLResponse.")
                    return
                }
                
                // Log the HTTP status code and response body for debugging
                logger.info("Login HTTP Status Code: \(httpResponse.statusCode, privacy: .public)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    logger.info("Login Response Body: \(responseBody, privacy: .public)")
                }

                guard httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let jwt = json["jwt"] as? String,
                      let user = json["user"] as? [String: Any],
                      let username = user["username"] as? String,
                      let userEmail = user["email"] as? String,
                      let userId = user["id"] as? Int else {
                    // Added more detailed logging for parsing failures
                    errorMessage = "Invalid email or password"
                    logger.error("Failed to parse successful login response or status code not 200.")
                    return
                }
                
                // Store the user data in Keychain and UserDefaults
                keychain["jwt"] = jwt
                UserDefaults.standard.set(username, forKey: "username")
                UserDefaults.standard.set(userEmail, forKey: "email")
                UserDefaults.standard.set(userId, forKey: "userId")
                
                // Set the login state to true to dismiss this view
                authState = .loggedIn
                logger.info("Login successful. User: \(username, privacy: .public)")
            }
        }.resume()
    }
}
