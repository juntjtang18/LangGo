import Foundation
import KeychainAccess
import XCTest
@testable import LangGo

final class LibraryViewModelFunctionalTests: XCTestCase {
    private let keychain = Keychain(service: Config.keychainService)

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

    func testLoadLibraryShowsFirstFetchedArticlePage() async throws {
        let snapshot = captureSessionSnapshot()
        let articleService = await MainActor.run { ArticleService() }
        let articleTagService = await MainActor.run { ArticleTagService() }
        var createdArticleID: Int?

        addTeardownBlock {
            if let createdArticleID {
                try? await articleService.deleteUserArticle(articleId: createdArticleID)
            }

            ArticleCache.invalidateAll(using: .shared)
            self.restoreSessionSnapshot(snapshot)
        }

        _ = try await loginTestUser()
        ArticleCache.invalidateAll(using: .shared)

        let seedArticle = try await articleService.createUserArticle(
            title: "Library ViewModel Regression \(UUID().uuidString.prefix(8))",
            content: "Regression coverage for the article list.",
            languageCode: nil,
            wordCount: 6,
            progress: 0,
            lastReadAt: Date(),
            tags: []
        )
        createdArticleID = seedArticle.id
        ArticleCache.invalidateAll(using: .shared)

        let viewModel = await MainActor.run {
            LibraryViewModel(
                articleService: articleService,
                articleTagService: articleTagService,
                articlePageSize: 10
            )
        }

        await viewModel.loadLibrary()

        let backendIDs = await MainActor.run {
            viewModel.libraryArticles.compactMap(\.backendId)
        }

        XCTAssertTrue(
            backendIDs.contains(seedArticle.id),
            "Expected the initial article page loaded by LibraryViewModel to include the newly created article."
        )
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
