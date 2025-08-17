//
//  UserSessionManager.swift
//  LangGo
//
//  Created by James Tang on 2025/8/16.
//


// UserSessionManager.swift
import Foundation
import SwiftUI
import Combine

@MainActor
class UserSessionManager: ObservableObject {
    static let shared = UserSessionManager()

    @Published var currentUser: StrapiUser?

    private init() {}

    func login(user: StrapiUser) {
        self.currentUser = user
        // Persist essential info like base language for quick access
        UserDefaults.standard.set(user.user_profile?.baseLanguage, forKey: "selectedLanguage")
        UserDefaults.standard.set(user.username, forKey: "username")
        UserDefaults.standard.set(user.email,    forKey: "email")
        UserDefaults.standard.set(user.id,       forKey: "userId")
        UserDefaults.standard.set(user.user_profile?.baseLanguage, forKey: "selectedLanguage")
    }

    func logout() {
        self.currentUser = nil
        // Clear any other persisted user data if necessary
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "email")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
    }
}
