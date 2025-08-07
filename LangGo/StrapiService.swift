// LangGo/StrapiService.swift

import Foundation
import os

// Define typealiases for Strapi data structures to improve clarity
typealias StrapiWord = StrapiData<WordAttributes>
typealias StrapiWordDefinition = StrapiData<WordDefinitionAttributes>

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
    
    // MARK: - Word Creation, Translation & Search
    
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

    func searchWords(term: String) async throws -> [StrapiWord] {
        logger.debug("StrapiService: Searching words with term: \(term).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/words/search") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: term)
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        // The custom endpoint response should match the StrapiListResponse structure
        let response: StrapiListResponse<StrapiWord> = try await NetworkManager.shared.fetchDirect(from: url)
        
        // --- ADDED: Logging for the raw response ---
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let responseData = try encoder.encode(response)
            if let jsonString = String(data: responseData, encoding: .utf8) {
                logger.info("Response from searchWords for term '\(term, privacy: .public)':\n\(jsonString, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode or log searchWords response: \(error.localizedDescription)")
        }
        // --- END ADDED ---
        
        return response.data ?? []
    }

    // --- REVISED: Using the new dedicated search endpoint for definitions ---
    func searchWordDefinitions(term: String) async throws -> [StrapiWordDefinition] {
        logger.debug("StrapiService: Searching word definitions with term: \(term).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/word-definitions/search") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: term)
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiListResponse<StrapiWordDefinition> = try await NetworkManager.shared.fetchDirect(from: url)

        // --- ADDED: Logging for the raw response ---
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let responseData = try encoder.encode(response)
            if let jsonString = String(data: responseData, encoding: .utf8) {
                logger.info("Response from searchWordDefinitions for term '\(term, privacy: .public)':\n\(jsonString, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode or log searchWordDefinitions response: \(error.localizedDescription)")
        }
        // --- END ADDED ---
        
        return response.data ?? []
    }
    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        logger.debug("StrapiService: Translating word '\(word)' from \(source) to \(target).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word") else { throw URLError(.badURL) }
        let requestBody = TranslateWordRequest(word: word, source: source, target: target)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }

    // --- NEWLY ADDED: Function to translate a word within its sentence context ---
    func translateWordInContext(word: String, sentence: String, sourceLang: String, targetLang: String) async throws -> TranslateWordInContextResponse {
        logger.debug("StrapiService: Translating word '\(word)' in context from \(sourceLang) to \(targetLang).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word-context") else { throw URLError(.badURL) }
        let requestBody = TranslateWordInContextRequest(word: word, sentence: sentence, sourceLang: sourceLang, targetLang: targetLang)
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
        // Pass the entire wordDefinition data object, not just the attributes
        let wordDefinitionData = attributes.wordDefinition?.data

        return Flashcard(
            id: strapiCard.id,
            wordDefinition: wordDefinitionData,
            lastReviewedAt: attributes.lastReviewedAt,
            correctStreak: attributes.correctStreak ?? 0,
            wrongStreak: attributes.wrongStreak ?? 0,
            isRemembered: attributes.isRemembered,
            reviewTire: attributes.reviewTire?.data?.attributes.tier
        )
    }
}
