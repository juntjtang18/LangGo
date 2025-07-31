// LangGo/Vocabook/FlashcardViewModel.swift

import SwiftUI
import os

// MODIFIED: Converted to ObservableObject for iOS 16 compatibility.
class FlashcardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    private let strapiService: StrapiService
    
    // MODIFIED: All properties that should trigger UI updates are now @Published.
    @Published var userReviewLogs: [StrapiReviewLog] = []
    @Published var totalCardCount: Int = 0
    @Published var rememberedCount: Int = 0
    @Published var reviewCards: [Flashcard] = []
    @Published var newCardCount: Int = 0
    @Published var warmUpCardCount: Int = 0
    @Published var weeklyReviewCardCount: Int = 0
    @Published var monthlyCardCount: Int = 0
    @Published var hardToRememberCount: Int = 0

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    var inProgressCount: Int {
        let count = totalCardCount - rememberedCount - newCardCount
        return max(0, count)
    }

    // MODIFIED: Initializer no longer takes a ModelContext.
    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }

    @MainActor
    func loadStatistics() async {
        logger.info("Attempting to fetch statistics from server.")
        do {
            let stats = try await strapiService.fetchFlashcardStatistics()
            
            self.totalCardCount = stats.totalCards
            self.rememberedCount = stats.remembered
            self.newCardCount = stats.newCards
            self.warmUpCardCount = stats.warmUp
            self.weeklyReviewCardCount = stats.weekly
            self.monthlyCardCount = stats.monthly
            self.hardToRememberCount = stats.hardToRemember
            
            logger.info("Successfully loaded statistics from the server.")
        } catch {
            // REMOVED: The local fallback calculation is gone. If the network fails, we log the error
            // and the UI will show zeros, which is the correct state when data can't be fetched.
            logger.error("Failed to fetch statistics from server: \(error.localizedDescription).")
        }
    }

    // REMOVED: The `calculateStatisticsLocally` function was deleted as it's no longer needed.

    @MainActor
    func prepareReviewSession() async {
        logger.info("Attempting to fetch review session from server.")
        do {
            let fetchedCards = try await strapiService.fetchAllReviewFlashcards()
            self.reviewCards = fetchedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")
        } catch {
            // REMOVED: The local storage fallback is gone. If the network call fails, we log the error
            // and set the review cards to an empty array.
            logger.error("Could not fetch review session from server. Error: \(error.localizedDescription).")
            self.reviewCards = []
        }
    }
    
    // MARK: - Review Logic

    func markReview(for card: Flashcard, result: ReviewResult) {
        Task {
            await submitReview(for: card, result: result)
        }
    }

    @MainActor
    private func submitReview(for card: Flashcard, result: ReviewResult) async {
        do {
            logger.info("Submitting review for card \(card.id) with result '\(result.rawValue)'")
            _ = try await strapiService.submitFlashcardReview(cardId: card.id, result: result)
            logger.info("Successfully synced updated card \(card.id) from server after review.")
        } catch {
            logger.error("Failed to submit and sync review for flashcard \(card.id): \(error.localizedDescription)")
        }
    }

    // MARK: - New Word Logic

    @MainActor
    func saveNewUserWord(targetText: String, baseText: String, partOfSpeech: String, baseLocale: String, targetLocale: String) async throws {
        do {
            logger.info("Attempting to save new user word: '\(targetText)' with base text '\(baseText)' and part of speech '\(partOfSpeech)'")
            let _: UserWordResponse = try await strapiService.saveNewUserWord(targetText: targetText, baseText: baseText, partOfSpeech: partOfSpeech, baseLocale: baseLocale, targetLocale: targetLocale)
            logger.info("Successfully saved new user word: '\(targetText)' to Strapi.")
            await loadStatistics()
        } catch {
            logger.error("Failed to save new user word '\(targetText)': \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    func translateWord(word: String, source: String, target: String) async throws -> String {
        do {
            logger.info("Attempting to translate word '\(word)' from \(source) to \(target)")
            let response: TranslateWordResponse = try await strapiService.translateWord(word: word, source: source, target: target)
            logger.info("Successfully translated word: \(response.translatedText)")
            return response.translatedText
        } catch {
            logger.error("Failed to translate word '\(word)': \(error.localizedDescription)")
            throw error
        }
    }
}

/// Enum to provide strong typing for review results.
enum ReviewResult: String {
    case correct
    case wrong
}
