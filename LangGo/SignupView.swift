//
//  SignupView.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation
import SwiftUI
import KeychainAccess

struct SignupView: View {
    @Binding var isLoggedIn: Bool
    @Binding var currentView: LoginView.ViewState
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    let keychain = Keychain(service: "com.geniusparentingai.GeniusParentingAISwift")

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

            Text("Sign Up for Genius Parenting AI")
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

        let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["username": email, "email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                // Ensure we have a valid response and data
                guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                    errorMessage = "Invalid response from server"
                    return
                }

                // --- START: Refactored Error Handling ---
                
                // Check if the registration was successful
                if httpResponse.statusCode == 200 {
                    // Success Path
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let jwt = json["jwt"] as? String else {
                        errorMessage = "Failed to parse success response."
                        return
                    }
                    keychain["jwt"] = jwt
                    currentView = .login
                } else {
                    // Error Path: Parse the specific error message from Strapi
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorDetails = errorJson["error"] as? [String: Any],
                       let message = errorDetails["message"] as? String {
                        // We found the specific message, so display it.
                        self.errorMessage = message
                    } else {
                        // Fallback if the error format is unexpected.
                        self.errorMessage = "An unknown error occurred. Please try again."
                    }
                }
                // --- END: Refactored Error Handling ---
            }
        }.resume()
    }
}

struct SignupView_Previews: PreviewProvider {
    static var previews: some View {
        SignupView(isLoggedIn: .constant(false), currentView: .constant(.login))
    }
}
