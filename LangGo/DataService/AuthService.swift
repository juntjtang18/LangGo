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
    private let cacheService = CacheService.shared
    
    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting login.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: credentials)
        FlashcardCache.invalidateLegacyGlobalCaches(using: cacheService)
        UserSnapshotCache.invalidate(using: cacheService)
        ArticleCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
        return response
    }
    
    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting signup.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: payload)
        FlashcardCache.invalidateLegacyGlobalCaches(using: cacheService)
        UserSnapshotCache.invalidate(using: cacheService)
        ArticleCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
        return response
    }
    
    func fetchCurrentUser(forceRefresh: Bool = false) async throws -> StrapiUser {
        if !forceRefresh {
            if let sessionUser = await MainActor.run(body: { UserSessionManager.shared.currentUser }) {
                return sessionUser
            }

            if let cachedUser = UserProfileCache.loadCurrentUser(using: cacheService) {
                return cachedUser
            }
        }

        logger.debug("AuthService: Fetching current user profile.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        let user: StrapiUser = try await networkManager.fetchDirect(from: url)
        UserProfileCache.storeCurrentUser(user, using: cacheService)
        return user
    }
    
    func updateUsername(userId: Int, username: String) async throws -> StrapiUser {
        logger.debug("AuthService: Updating username for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else { throw URLError(.badURL) }
        let body = ["username": username]
        let updatedUser: StrapiUser = try await networkManager.put(to: url, body: body)
        UserProfileCache.storeCurrentUser(updatedUser, using: cacheService)
        return updatedUser
    }
    
    func updateBaseLanguage(languageCode: String) async throws {
        logger.debug("AuthService: Updating base language to \(languageCode).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }
        let payload = UserProfileUpdatePayload(baseLanguage: languageCode, proficiency: nil, reminder_enabled: nil)
        let body = UserProfileUpdatePayloadWrapper(data: payload)
        try await CacheMutation.perform(
            remoteWrite: {
                let _: EmptyResponse = try await self.networkManager.put(to: url, body: body)
            },
            applyLocalSuccess: {
                await UserProfileCache.patchCurrentUserProfile(using: self.cacheService) { existingProfile in
                    UserProfileCache.mergeProfile(from: existingProfile, applying: payload)
                }
            }
        )
    }
    
    func updateUserProfile(userId: Int, payload: UserProfileUpdatePayload) async throws {
        logger.debug("AuthService: Updating user profile for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }
        let body = UserProfileUpdatePayloadWrapper(data: payload)
        try await CacheMutation.perform(
            remoteWrite: {
                let _: EmptyResponse = try await self.networkManager.put(to: url, body: body)
            },
            applyLocalSuccess: {
                await UserProfileCache.patchCurrentUserProfile(using: self.cacheService) { existingProfile in
                    UserProfileCache.mergeProfile(from: existingProfile, applying: payload)
                }
            }
        )
    }

    func updateUserAvatarImage(mediaId: Int) async throws {
        logger.debug("AuthService: Updating avatar image.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }
        let body = UserAvatarUpdatePayloadWrapper(data: UserAvatarUpdatePayload(avatarImageId: mediaId))
        try await CacheMutation.perform(
            remoteWrite: {
                let _: EmptyResponse = try await self.networkManager.put(to: url, body: body)
            },
            applyLocalSuccess: {
                UserProfileCache.invalidate(using: self.cacheService)
            }
        )
    }

    func uploadUserAvatarImage(
        _ imageData: Data,
        fileName: String = "avatar.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> UserProfileAttributes {
        logger.debug("AuthService: Uploading avatar image.")
        guard let uploadURL = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine/avatar") else { throw URLError(.badURL) }

        let response: StrapiSingleResponse<StrapiData<UserProfileAttributes>> = try await CacheMutation.perform(
            remoteWrite: {
                try await self.networkManager.uploadMultipart(
                    to: uploadURL,
                    fileData: imageData,
                    fieldName: "avatar",
                    fileName: fileName,
                    mimeType: mimeType
                ) as StrapiSingleResponse<StrapiData<UserProfileAttributes>>
            },
            applyLocalSuccess: { response in
                await UserProfileCache.patchCurrentUserProfile(using: self.cacheService) { _ in
                    response.data.attributes
                }
            }
        )
        return response.data.attributes
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

    func deleteCurrentUserAccount(currentPassword: String) async throws {
        logger.debug("AuthService: Deleting current user account.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        try await networkManager.delete(
            at: url,
            headers: ["X-Account-Delete-Password": currentPassword]
        )
        FlashcardCache.invalidateLegacyGlobalCaches(using: cacheService)
        UserSnapshotCache.invalidate(using: cacheService)
        ArticleCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
    }

    func fetchSnapshot(locale: String? = nil) async throws -> UserRankSnapshot? {
        if let cachedSnapshot = UserSnapshotCache.load(locale: locale, using: cacheService) {
            return cachedSnapshot
        }

        let userId = await MainActor.run { UserSessionManager.shared.currentUser?.id }
        guard let userId else { return nil }

        logger.debug("AuthService: Fetching rank snapshot for user \(userId).")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/rank/users/\(userId)")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        let response: RankUserResponse = try await networkManager.fetchDirect(from: url)
        let snapshot = response.data.latest_snapshot
        UserSnapshotCache.store(snapshot, locale: locale, using: cacheService)
        return snapshot
    }

    func cachedSnapshot(locale: String? = nil) -> UserRankSnapshot? {
        UserSnapshotCache.load(locale: locale, using: cacheService)
    }

}
