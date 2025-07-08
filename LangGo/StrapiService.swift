// LangGo/StrapiService.swift
//
//  StrapiService.swift
//  LangGo
//
//  Created by James Tang on 2025/7/7. // Or actual current date
//

import Foundation
import os

/// A service layer for interacting with the Strapi backend API.
/// This class abstracts away the specific Strapi endpoints and request/response structures.
class StrapiService {
    static let shared = StrapiService()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "StrapiService")

    private init() {}

    // MARK: - Authentication & User Management

    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        logger.debug("StrapiService: Attempting login.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.post(to: url, body: credentials)
    }

    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        logger.debug("StrapiService: Attempting signup.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.post(to: url, body: payload)
    }

    func fetchCurrentUser() async throws -> StrapiUser {
        logger.debug("StrapiService: Fetching current user profile.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        // Note: fetchDirect is used here because /api/users/me returns the user object directly, not wrapped in a 'data' key.
        return try await NetworkManager.shared.fetchDirect(from: url)
    }
    
    func updateUsername(userId: Int, username: String) async throws -> StrapiUser {
        logger.debug("StrapiService: Updating username for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else { throw URLError(.badURL) }
        let body = ["username": username]
        // Note: fetchDirect is used as /api/users/:id returns the updated user object directly.
        return try await NetworkManager.shared.put(to: url, body: body)
    }

    func changePassword(currentPassword: String, newPassword: String, confirmNewPassword: String) async throws -> EmptyResponse {
        logger.debug("StrapiService: Changing password.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/change-password") else { throw URLError(.badURL) }
        let body = [
            "currentPassword": currentPassword,
            "password": newPassword,
            "passwordConfirmation": confirmNewPassword
        ]
        // Now EmptyResponse is accessible globally from StrapiModels.swift
        return try await NetworkManager.shared.post(to: url, body: body)
    }

    // MARK: - Flashcard & Review

    func fetchFlashcardStatistics() async throws -> StrapiStatistics {
        logger.debug("StrapiService: Fetching flashcard statistics.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchSingle(from: url)
    }

    func fetchReviewFlashcards() async throws -> StrapiResponse {
        logger.debug("StrapiService: Fetching review flashcards.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/review-flashcards") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchDirect(from: url)
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Relation<StrapiFlashcard> {
        logger.debug("StrapiService: Submitting review for card ID: \(cardId) with result: \(result.rawValue).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        // Note: Relation<StrapiFlashcard> is used as the response is wrapped in a 'data' key.
        return try await NetworkManager.shared.post(to: url, body: body)
    }

    func fetchAllFlashcardsWithContent() async throws -> StrapiResponse {
        logger.debug("StrapiService: Fetching all flashcards with content population.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards?populate=content") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchDirect(from: url)
    }

    // MARK: - User Words & Translation

    func saveNewUserWord(targetText: String, baseText: String, partOfSpeech: String, baseLocale: String, targetLocale: String) async throws -> UserWordResponse {
        logger.debug("StrapiService: Saving new user word.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-words") else { throw URLError(.badURL) }
        let newWordData = UserWordData(target_text: targetText, base_text: baseText, part_of_speech: partOfSpeech, base_locale: baseLocale, target_locale: targetLocale)
        let requestBody = CreateUserWordRequest(data: newWordData)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }

    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        logger.debug("StrapiService: Translating word '\(word)' from \(source) to \(target).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word") else { throw URLError(.badURL) }
        let requestBody = TranslateWordRequest(word: word, source: source, target: target)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }
    
    // MARK: - NEW: Vocabook & Vocapage API Calls (Modified to fetch all pages and filter by user)

    func fetchUserVocabooks() async throws -> [StrapiVocabook] {
        logger.debug("StrapiService: Fetching user vocabooks with populated vocapages.")
        // Get current user ID from UserDefaults
        let userId = UserDefaults.standard.integer(forKey: "userId")
        guard userId != 0 else {
            logger.error("User ID not found when fetching vocabooks.")
            throw NSError(domain: "StrapiServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not logged in or ID missing."])
        }

        // Add filter for user ID and populate relations
        guard let baseURL = URL(string: "\(Config.strapiBaseUrl)/api/vocabooks?filters[user][id][$eq]=\(userId)&populate[vocapages][populate][flashcards]=true") else { throw URLError(.badURL) }
        let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let allVocabooks: [StrapiVocabook] = try await NetworkManager.shared.fetchAllPages(baseURLComponents: components)
        return allVocabooks
    }

    func fetchVocapages(forVocabookId vocabookId: Int) async throws -> [StrapiVocapage] {
        logger.debug("StrapiService: Fetching vocapages for vocabook ID: \(vocabookId) with populated flashcards.")
        // Use fetchAllPages to get all vocapages for a vocabook, handling pagination
        guard let baseURL = URL(string: "\(Config.strapiBaseUrl)/api/vocapages?filters[vocabook][id][$eq]=\(vocabookId)&populate[flashcards]=true&sort[0]=order:asc") else { throw URLError(.badURL) }
        let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let allVocapages: [StrapiVocapage] = try await NetworkManager.shared.fetchAllPages(baseURLComponents: components)
        return allVocapages
    }

    // MARK: - Other (Example for future use)

    // Example for fetching a list of courses (if you add this endpoint)
    // func getCourseList(page: Int = 1, pageSize: Int = 25) async throws -> StrapiListResponse<Course> {
    //     logger.debug("StrapiService: Fetching course list.")
    //     var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/courses")!
    //     // Add any specific filters or populations needed for courses
    //     return try await NetworkManager.shared.fetchPage(baseURLComponents: components, page: page, pageSize: pageSize)
    // }
}
