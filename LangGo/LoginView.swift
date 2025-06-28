//
//  LoginView.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation
import SwiftUI
import KeychainAccess

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var currentView: ViewState = .login
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""

    // UPDATED: Uses the central Config value
    let keychain = Keychain(service: Config.keychainService)

    // ... rest of the file is unchanged
    enum ViewState {
        case login
        case signup
    }

    var body: some View {
        Group {
            if currentView == .login {
                VStack(spacing: 20) {
                    Text("Welcome to LangGo") // Changed from "Genius Parenting AI"
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
            } else if currentView == .signup {
                SignupView(isLoggedIn: $isLoggedIn, currentView: $currentView)
            }
        }
    }
    
    func login() {
        let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["identifier": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    errorMessage = "Invalid response from server"
                    return
                }
                print("Status code: \(httpResponse.statusCode)")
                if let data = data, let dataString = String(data: data, encoding: .utf8) {
                    print("Response data: \(dataString)")
                }
                guard httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let jwt = json["jwt"] as? String else {
                    errorMessage = "Invalid email or password"
                    return
                }
                keychain["jwt"] = jwt
                isLoggedIn = true
            }
        }.resume()
    }
}
