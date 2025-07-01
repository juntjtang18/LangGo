import Foundation
import SwiftUI
import KeychainAccess

struct SignupView: View {
    @Binding var currentView: LoginView.ViewState
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    let keychain = Keychain(service: Config.keychainService)

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: {
                    currentView = .login
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .padding()
                Spacer()
            }

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

            Button(action: {
                signup()
            }) {
                Text("Sign Up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            Button(action: {
                currentView = .login
            }) {
                Text("Already have an account? Log In")
                    .foregroundColor(.blue)
            }
            .padding()
        }
        .padding()
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

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else {
             errorMessage = "Invalid server URL"
             return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // In Strapi, the default setup requires username, which can be the same as the email.
        let body = ["username": email, "email": email, "password": password]
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
                
                if httpResponse.statusCode == 200 {
                    // On successful registration, Strapi returns a JWT.
                    // We can log the user in directly or send them to the login screen.
                    // Here, we just redirect to login.
                    currentView = .login
                } else {
                    // Try to parse the specific error message from Strapi
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDetails = errorJson["error"] as? [String: Any],
                       let message = errorDetails["message"] as? String {
                        self.errorMessage = message
                    } else {
                        self.errorMessage = "An unknown error occurred. Please try again."
                    }
                }
            }
        }.resume()
    }
}
