import Foundation
import KeychainAccess
import XCTest
@testable import LangGo

final class ArticleServiceCacheFunctionalTests: XCTestCase {
    private let keychain = Keychain(service: Config.keychainService)
    private let articleTagsCacheTag: CacheService.CacheTag = "article-tags"
    private let usedArticleTagsCacheTag: CacheService.CacheTag = "used-article-tags"
    private let userArticlesCacheTag: CacheService.CacheTag = "user-articles"

    private struct SessionSnapshot {
        let jwt: String?
        let userId: Any?
        let username: Any?
        let email: Any?
        let selectedLanguage: Any?
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testArticleTagReadUsesCacheWithoutJwtAndWriteInvalidatesCache() async throws {
        let snapshot = captureSessionSnapshot()
        defer {
            restoreSessionSnapshot(snapshot)
            clearArticleCaches()
        }

        let authResponse = try await loginTestUser()
        let service = await MainActor.run { ArticleService() }
        clearArticleCaches()

        let firstTags = try await service.fetchMyArticleTags()
        XCTAssertFalse(firstTags.isEmpty, "Expected the test user to have at least one article tag to cache.")

        try keychain.remove("jwt")

        let cachedTags = try await service.fetchMyArticleTags()
        XCTAssertEqual(
            firstTags.compactMap { $0.attributes.tag },
            cachedTags.compactMap { $0.attributes.tag },
            "Expected article tag fetch to succeed from cache after removing the JWT."
        )

        keychain["jwt"] = authResponse.jwt
        let uniqueTag = "ct-\(UUID().uuidString.prefix(8))"
        _ = try await service.createArticleTag(tag: uniqueTag)

        try keychain.remove("jwt")

        do {
            _ = try await service.fetchMyArticleTags()
            XCTFail("Expected article tag fetch to fail after cache invalidation and JWT removal.")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testUserArticlePageReadUsesCacheWithoutJwt() async throws {
        let snapshot = captureSessionSnapshot()
        defer {
            restoreSessionSnapshot(snapshot)
            clearArticleCaches()
        }

        _ = try await loginTestUser()
        let service = await MainActor.run { ArticleService() }
        clearArticleCaches()

        let firstResponse = try await service.fetchMyUserArticles(page: 1, pageSize: 10)
        let firstIDs = (firstResponse.data ?? []).map(\.id)

        try keychain.remove("jwt")

        let cachedResponse = try await service.fetchMyUserArticles(page: 1, pageSize: 10)
        let cachedIDs = (cachedResponse.data ?? []).map(\.id)

        XCTAssertEqual(firstIDs, cachedIDs, "Expected article page fetch to come from cache after removing the JWT.")
    }

    private func loginTestUser() async throws -> AuthResponse {
        let email = ProcessInfo.processInfo.environment["LANGGO_TEST_EMAIL"] ?? "chinese2@langgo.ca"
        let password = ProcessInfo.processInfo.environment["LANGGO_TEST_PASSWORD"] ?? "Passw0rd"
        let authService = AuthService()
        let response = try await authService.login(credentials: LoginCredentials(identifier: email, password: password))

        keychain["jwt"] = response.jwt
        await MainActor.run {
            UserSessionManager.shared.login(user: response.user)
        }

        return response
    }

    private func clearArticleCaches() {
        CacheService.shared.invalidate(tags: [articleTagsCacheTag, usedArticleTagsCacheTag, userArticlesCacheTag])
    }

    private func captureSessionSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            jwt: keychain["jwt"],
            userId: UserDefaults.standard.object(forKey: "userId"),
            username: UserDefaults.standard.object(forKey: "username"),
            email: UserDefaults.standard.object(forKey: "email"),
            selectedLanguage: UserDefaults.standard.object(forKey: "selectedLanguage")
        )
    }

    private func restoreSessionSnapshot(_ snapshot: SessionSnapshot) {
        if let jwt = snapshot.jwt {
            keychain["jwt"] = jwt
        } else {
            try? keychain.remove("jwt")
        }

        restoreUserDefault(snapshot.userId, forKey: "userId")
        restoreUserDefault(snapshot.username, forKey: "username")
        restoreUserDefault(snapshot.email, forKey: "email")
        restoreUserDefault(snapshot.selectedLanguage, forKey: "selectedLanguage")

        Task { @MainActor in
            UserSessionManager.shared.logout()
        }
    }

    private func restoreUserDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
