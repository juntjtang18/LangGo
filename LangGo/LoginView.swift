import SwiftUI
import KeychainAccess

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
                } else if currentView == .signup {
                    SignupView(currentView: $currentView, authState: $authState)
                }
            }
        }
    }

    func login() {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else {
            errorMessage = "Invalid server URL"
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
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    errorMessage = "Invalid response from server"
                    return
                }
                
                guard httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let jwt = json["jwt"] as? String,
                      let user = json["user"] as? [String: Any],
                      let username = user["username"] as? String,
                      let userEmail = user["email"] as? String,
                      let userId = user["id"] as? Int else {
                    errorMessage = "Invalid email or password"
                    return
                }
                
                // Store the user data in Keychain and UserDefaults
                keychain["jwt"] = jwt
                UserDefaults.standard.set(username, forKey: "username")
                UserDefaults.standard.set(userEmail, forKey: "email")
                UserDefaults.standard.set(userId, forKey: "userId")
                
                // Set the login state to true to dismiss this view
                authState = .loggedIn
            }
        }.resume()
    }
}
