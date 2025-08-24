//
//  AuthService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/23.
//


// LangGo/DataService/AuthService.swift

import Foundation
import os

class AuthService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "AuthService")
    private let networkManager = NetworkManager.shared
    private let flashcardService = FlashcardService()
    
    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting login.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: credentials)
        flashcardService.invalidateAllFlashcardCaches()
        return response
    }
    
    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting signup.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: payload)
        flashcardService.invalidateAllFlashcardCaches()
        return response
    }
    
    func fetchCurrentUser() async throws -> StrapiUser {
        logger.debug("AuthService: Fetching current user profile.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        return try await networkManager.fetchDirect(from: url)
    }
    
    func updateUsername(userId: Int, username: String) async throws -> StrapiUser {
        logger.debug("AuthService: Updating username for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else { throw URLError(.badURL) }
        let body = ["username": username]
        return try await networkManager.put(to: url, body: body)
    }
    
    func updateBaseLanguage(languageCode: String) async throws {
        logger.debug("AuthService: Updating base language to \(languageCode).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }
        let payload = UserProfileUpdatePayload(baseLanguage: languageCode, proficiency: nil, reminder_enabled: nil)
        let body = UserProfileUpdatePayloadWrapper(data: payload)
        let _: EmptyResponse = try await networkManager.put(to: url, body: body)
    }
    
    func updateUserProfile(userId: Int, payload: UserProfileUpdatePayload) async throws {
        logger.debug("AuthService: Updating user profile for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }
        let body = UserProfileUpdatePayloadWrapper(data: payload)
        let _: EmptyResponse = try await networkManager.put(to: url, body: body)
    }
    
    func changePassword(currentPassword: String, newPassword: String, confirmNewPassword: String) async throws -> EmptyResponse {
        logger.debug("AuthService: Changing password.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/change-password") else { throw URLError(.badURL) }
        let body = [
            "currentPassword": currentPassword,
            "password": newPassword,
            "passwordConfirmation": confirmNewPassword
        ]
        return try await networkManager.post(to: url, body: body)
    }
    
}
