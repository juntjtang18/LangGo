//
//  UserSessionManager.swift
//  LangGo
//
//  Created by James Tang on 2025/8/16.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class UserSessionManager: ObservableObject {
    static let shared = UserSessionManager()

    @Published var currentUser: StrapiUser?

    private init() {}

    func login(user: StrapiUser) {
        let previousUserId = UserDefaults.standard.integer(forKey: "userId")
        let didSwitchUser = previousUserId > 0 && previousUserId != user.id

        self.currentUser = user
        UserDefaults.standard.set(user.user_profile?.baseLanguage, forKey: "selectedLanguage")
        UserDefaults.standard.set(user.username, forKey: "username")
        UserDefaults.standard.set(user.email, forKey: "email")
        UserDefaults.standard.set(user.id, forKey: "userId")

        if didSwitchUser {
            FlashcardCache.invalidateLegacyGlobalCaches(using: .shared)
            DataServices.shared.resetUserScopedRuntimeState()
        }
    }

    func logout() {
        self.currentUser = nil
        DataServices.shared.resetUserScopedRuntimeState()
        FlashcardCache.invalidateLegacyGlobalCaches(using: .shared)

        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "email")
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
    }
}
