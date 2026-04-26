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
    private let cacheService = CacheService.shared
    
    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting login.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: credentials)
        flashcardService.invalidateAllFlashcardCaches()
        MyUserPointsCache.invalidate(using: cacheService)
        PointGroupCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
        return response
    }
    
    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        logger.debug("AuthService: Attempting signup.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else { throw URLError(.badURL) }
        let response: AuthResponse = try await networkManager.post(to: url, body: payload)
        flashcardService.invalidateAllFlashcardCaches()
        MyUserPointsCache.invalidate(using: cacheService)
        PointGroupCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
        return response
    }
    
    func fetchCurrentUser() async throws -> StrapiUser {
        if let sessionUser = await MainActor.run(body: { UserSessionManager.shared.currentUser }) {
            return sessionUser
        }

        if let cachedUser = UserProfileCache.loadCurrentUser(using: cacheService) {
            return cachedUser
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
        flashcardService.invalidateAllFlashcardCaches()
        MyUserPointsCache.invalidate(using: cacheService)
        PointGroupCache.invalidateAll(using: cacheService)
        UserProfileCache.invalidate(using: cacheService)
    }

    func fetchMyUserPoints(locale: String? = nil) async throws -> MyUserPointsAttributes? {
        if let cachedPoints = MyUserPointsCache.load(locale: locale, using: cacheService) {
            return cachedPoints
        }

        logger.debug("AuthService: Fetching current user points.")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/my-user-points")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        let response: MyUserPointsResponse = try await networkManager.fetchDirect(from: url)
        let attributes = response.data?.attributes
        if let attributes {
            MyUserPointsCache.store(attributes, locale: locale, using: cacheService)
        }
        return attributes
    }

    func cachedMyUserPoints(locale: String? = nil) -> MyUserPointsAttributes? {
        MyUserPointsCache.load(locale: locale, using: cacheService)
    }

    func fetchMyPointGroup(locale: String? = nil) async throws -> MyPointGroupData {
        logger.debug("AuthService: Fetching current user's point group.")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/my-point-group")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        let response: MyPointGroupResponse = try await networkManager.fetchDirect(from: url)
        return response.data
    }

    func fetchPointGroupLeaderboard(pointGroupId: Int, locale: String? = nil) async throws -> PointGroupLeaderboardData {
        logger.debug("AuthService: Fetching point group leaderboard for group ID \(pointGroupId).")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/point-groups/\(pointGroupId)/leaderboard")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        let response: PointGroupLeaderboardResponse = try await networkManager.fetchDirect(from: url)
        return response.data
    }

}
