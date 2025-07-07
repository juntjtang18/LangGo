import Foundation
import SwiftUI
import KeychainAccess

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
    @State private var errorMessage = ""

    let keychain = Keychain(service: Config.keychainService)

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

    // --- SIGNUP FUNCTION MODIFIED ---
    func signup() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        // 1. Use the new custom endpoint URL
        // Changed to /api/auth/local/register to hit the custom Strapi registration logic
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else {
             errorMessage = "Invalid server URL"
             return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 2. Create the new request body including `baseLanguage`
        // Note: The custom Strapi endpoint expects 'username', 'email', and 'password'.
        // 'baseLanguage' from your app's payload is not directly consumed by the default /auth/local/register endpoint,
        // but it can remain in the payload if your server-side customization handles it.
        // Based on the provided strapi-server.js, `baseLanguage` is not being used.
        // It's generally better to send only what the API expects for that specific endpoint.
        // However, if `username` is set to `email` as a default, that's fine.
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "username": email, // Strapi still needs a username; email is a safe default.
            "baseLanguage": languageSettings.selectedLanguageCode // Get language from our settings object
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                    errorMessage = "Invalid response from server"
                    return
                }
                
                // 3. Handle the new success response
                if httpResponse.statusCode == 200 {
                    // On success, the new endpoint returns a JWT and user info.
                    // We can log the user in directly.
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let jwt = json["jwt"] as? String,
                          let user = json["user"] as? [String: Any],
                          let username = user["username"] as? String,
                          let userEmail = user["email"] as? String,
                          let userId = user["id"] as? Int else {
                        errorMessage = "Registration succeeded, but failed to parse response."
                        return
                    }
                    
                    // Store credentials and set app state to logged in
                    keychain["jwt"] = jwt
                    UserDefaults.standard.set(username, forKey: "username")
                    UserDefaults.standard.set(userEmail, forKey: "email")
                    UserDefaults.standard.set(userId, forKey: "userId")
                    
                    // This will switch the root view to MainView
                    authState = .loggedIn
                    
                } else {
                    // Handle errors from Strapi
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDetails = errorJson["error"] as? [String: Any],
                       let message = errorDetails["message"] as? String {
                        self.errorMessage = message
                    } else {
                        self.errorMessage = "An unknown error occurred. Status: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }
}
