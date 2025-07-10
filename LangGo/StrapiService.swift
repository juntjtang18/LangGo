// LangGo/StrapiService.swift
import Foundation
import os
import SwiftData

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

    @MainActor
    func fetchReviewFlashcards(modelContext: ModelContext) async throws -> [Flashcard] {
        logger.debug("StrapiService: Fetching and syncing review flashcards.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/review-flashcards") else { throw URLError(.badURL) }
        let response: StrapiResponse = try await NetworkManager.shared.fetchDirect(from: url)
        
        var syncedFlashcards: [Flashcard] = []
        for strapiCard in response.data {
            let syncedCard = try await syncCard(strapiCard, modelContext: modelContext)
            syncedFlashcards.append(syncedCard)
        }
        try modelContext.save()
        return syncedFlashcards
    }

    @MainActor
    func submitFlashcardReview(cardId: Int, result: ReviewResult, modelContext: ModelContext) async throws -> Flashcard {
        logger.debug("StrapiService: Submitting review for card ID: \(cardId) with result: \(result.rawValue).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await NetworkManager.shared.post(to: url, body: body)
        
        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "StrapiServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response was missing the 'data' object."])
        }
        
        let syncedCard = try await syncCard(updatedStrapiCard, modelContext: modelContext)
        try modelContext.save()
        return syncedCard
    }

    // MARK: - Flashcards Pagination
    
    @MainActor
    func fetchFlashcards(page: Int, pageSize: Int, modelContext: ModelContext) async throws -> [Flashcard] {
        logger.debug("StrapiService: Fetching flashcards page \(page), size \(pageSize).")
        guard let url = URL(string:
            "\(Config.strapiBaseUrl)/api/flashcards/mine?pagination[page]=\(page)&pagination[pageSize]=\(pageSize)&populate=content,review_tire")
        else {
            throw URLError(.badURL)
        }
        let response: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)

        var syncedFlashcards: [Flashcard] = []
        if let strapiFlashcards = response.data {
            for strapiCard in strapiFlashcards {
                let syncedCard = try await syncCard(strapiCard, modelContext: modelContext)
                syncedFlashcards.append(syncedCard)
            }
        }
        return syncedFlashcards
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
    
    // MARK: - VBSetting Endpoints

    /// Fetch the current user's vbsetting.
    func fetchVBSetting() async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let response: VBSettingSingleResponse = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data
    }

    /// Update the current user's vbsetting.
    func updateVBSetting(
        wordsPerPage: Int,
        interval1: Double,
        interval2: Double,
        interval3: Double
    ) async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let payload = VBSettingUpdatePayload(
            data: .init(
                wordsPerPage: wordsPerPage,
                interval1: interval1,
                interval2: interval2,
                interval3: interval3
            )
        )
        let response: VBSettingSingleResponse = try await NetworkManager.shared.put(to: url, body: payload)
        return response.data
    }
    
    // MARK: - Private Syncing Logic
    
    @MainActor
    @discardableResult
    private func syncCard(_ strapiCard: StrapiFlashcard, modelContext: ModelContext) async throws -> Flashcard {
        let cardId = strapiCard.id
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
        fetchDescriptor.fetchLimit = 1
        
        let cardToUpdate: Flashcard
        if let existingCard = try modelContext.fetch(fetchDescriptor).first {
            cardToUpdate = existingCard
        } else {
            cardToUpdate = Flashcard(id: cardId, frontContent: "", backContent: "", register: nil, contentType: "", rawComponentData: nil, lastReviewedAt: nil, correctStreak: 0, wrongStreak: 0, isRemembered: false, reviewTire: nil)
            modelContext.insert(cardToUpdate)
        }
        
        let attributes = strapiCard.attributes
        let contentComponent = attributes.content?.first
        
        switch contentComponent?.componentIdentifier {
        case "a.user-word-ref":
            cardToUpdate.frontContent = contentComponent?.userWord?.data?.attributes.baseText ?? "Missing Question"
            cardToUpdate.backContent = contentComponent?.userWord?.data?.attributes.targetText ?? "Missing Answer"
        case "a.word-ref":
            cardToUpdate.frontContent = contentComponent?.word?.data?.attributes.baseText ?? "Missing Question"
            cardToUpdate.backContent = contentComponent?.word?.data?.attributes.word ?? "Missing Answer"
            cardToUpdate.register = contentComponent?.word?.data?.attributes.register
        case "a.user-sent-ref":
            cardToUpdate.frontContent = contentComponent?.userSentence?.data?.attributes.baseText ?? "Missing Question"
            cardToUpdate.backContent = contentComponent?.userSentence?.data?.attributes.targetText ?? "Missing Answer"
        case "a.sent-ref":
            cardToUpdate.frontContent = contentComponent?.sentence?.data?.attributes.baseText ?? "Missing Question"
            cardToUpdate.backContent = contentComponent?.sentence?.data?.attributes.targetText ?? "Missing Answer"
            cardToUpdate.register = contentComponent?.sentence?.data?.attributes.register
        default:
            cardToUpdate.frontContent = "Unknown Content (Front)"
            cardToUpdate.backContent = "Unknown Content (Back)"
        }

        cardToUpdate.contentType = contentComponent?.componentIdentifier ?? ""
        cardToUpdate.rawComponentData = try? JSONEncoder().encode(contentComponent)
        cardToUpdate.lastReviewedAt = attributes.lastReviewedAt
        cardToUpdate.isRemembered = attributes.isRemembered
        cardToUpdate.correctStreak = attributes.correctStreak ?? 0
        cardToUpdate.wrongStreak = attributes.wrongStreak ?? 0
        cardToUpdate.reviewTire = attributes.reviewTire?.data?.attributes.tier
        
        return cardToUpdate
    }
}
