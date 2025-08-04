// LangGo/StrapiService.swift

import Foundation
import os

class StrapiService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "StrapiService")

    init() {
    }

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
        return try await NetworkManager.shared.fetchDirect(from: url)
    }
    
    func updateUsername(userId: Int, username: String) async throws -> StrapiUser {
        logger.debug("StrapiService: Updating username for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else { throw URLError(.badURL) }
        let body = ["username": username]
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
        return try await NetworkManager.shared.post(to: url, body: body)
    }

    // MARK: - Flashcard & Review

    func fetchFlashcardStatistics() async throws -> StrapiStatistics {
        logger.debug("StrapiService: Fetching flashcard statistics.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchSingle(from: url)
    }
    
    func fetchReviewTireSettings() async throws -> [StrapiReviewTire] {
        logger.debug("StrapiService: Fetching review tire settings.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/review-tires") else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiReviewTire> = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data ?? []
    }

    private func fetchReviewFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        logger.debug("StrapiService: Fetching review flashcards page \(page), size \(pageSize).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/review-flashcards") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)"),
            URLQueryItem(name: "populate[word_definition][populate]", value: "word")
        ]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }

        let response: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)
        
        let flashcards = (response.data ?? []).map(transformStrapiCard)
        return (flashcards, response.meta?.pagination)
    }
    
    func fetchAllReviewFlashcards() async throws -> [Flashcard] {
        var allCards: [Flashcard] = []
        var currentPage = 1
        let pageSize = 100
        var hasMorePages = true

        logger.debug("StrapiService: Fetching all pages of review flashcards from /api/review-flashcards.")

        while hasMorePages {
            let (cards, pagination) = try await self.fetchReviewFlashcardsPage(page: currentPage, pageSize: pageSize)
            
            if !cards.isEmpty {
                allCards.append(contentsOf: cards)
            }
            
            if let pag = pagination {
                hasMorePages = pag.page < pag.pageCount
                currentPage += 1
            } else {
                hasMorePages = false
            }
        }
        return allCards
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Flashcard {
        logger.debug("StrapiService: Submitting review for card ID: \(cardId) with result: \(result.rawValue).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await NetworkManager.shared.post(to: url, body: body)
        
        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "StrapiServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response was missing the 'data' object."])
        }
        
        let flashcard = transformStrapiCard(updatedStrapiCard)
        return flashcard
    }

    func fetchAllMyFlashcards() async throws -> [Flashcard] {
        var allCards: [Flashcard] = []
        var currentPage = 1
        let pageSize = 100
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await self.fetchFlashcards(page: currentPage, pageSize: pageSize)
            
            allCards.append(contentsOf: cards)
            
            if let pag = pagination, pag.page < pag.pageCount {
                currentPage += 1
            } else {
                hasMorePages = false
            }
        }
        
        return allCards
    }
    
    // MARK: - Flashcards Pagination
    func fetchFlashcards(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        logger.debug("StrapiService: Fetching flashcards page \(page), size \(pageSize) from /api/flashcards/mine.")
        guard let url = URL(string:
            "\(Config.strapiBaseUrl)/api/flashcards/mine?pagination[page]=\(page)&pagination[pageSize]=\(pageSize)&populate[word_definition][populate]=word")
        else {
            throw URLError(.badURL)
        }
        let response: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)

        let flashcards = (response.data ?? []).map(transformStrapiCard)
        return (flashcards, response.meta?.pagination)
    }
    
    // MARK: - Word Creation & Translation
    
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String) async throws -> WordDefinitionResponse {
        logger.debug("StrapiService: Saving new word and definition.")
        
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/word-definitions") else { throw URLError(.badURL) }
        
        let payload = WordDefinitionCreationPayload(
            targetText: targetText,
            baseText: baseText,
            partOfSpeech: partOfSpeech
        )
        let requestBody = CreateWordDefinitionRequest(data: payload)
        
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }

    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        logger.debug("StrapiService: Translating word '\(word)' from \(source) to \(target).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word") else { throw URLError(.badURL) }
        let requestBody = TranslateWordRequest(word: word, source: source, target: target)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }
    
    // MARK: - VBSetting Endpoints
    func fetchVBSetting() async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let response: VBSettingSingleResponse = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data
    }

    func updateVBSetting(wordsPerPage: Int, interval1: Double, interval2: Double, interval3: Double) async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let payload = VBSettingUpdatePayload(data: .init(wordsPerPage: wordsPerPage, interval1: interval1, interval2: interval2, interval3: interval3))
        let response: VBSettingSingleResponse = try await NetworkManager.shared.put(to: url, body: payload)
        return response.data
    }
    
    // MARK: - Private Transformation Logic
    private func transformStrapiCard(_ strapiCard: StrapiFlashcard) -> Flashcard {
        let attributes = strapiCard.attributes
        let definition = attributes.wordDefinition?.data?.attributes

        return Flashcard(
            id: strapiCard.id,
            definition: definition,
            lastReviewedAt: attributes.lastReviewedAt,
            correctStreak: attributes.correctStreak ?? 0,
            wrongStreak: attributes.wrongStreak ?? 0,
            isRemembered: attributes.isRemembered,
            reviewTire: attributes.reviewTire?.data?.attributes.tier
        )
    }
}
