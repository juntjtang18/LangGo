// LangGo/FlashcardViewModel.swift
import SwiftUI
import SwiftData
import os

@Observable
class FlashcardViewModel {
    var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    var userReviewLogs: [StrapiReviewLog] = []

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    var totalCardCount: Int = 0
    var rememberedCount: Int = 0
    var reviewCards: [Flashcard] = []
    // Add new properties to hold the categorized card counts
    var newCardCount: Int = 0
    var warmUpCardCount: Int = 0
    var weeklyReviewCardCount: Int = 0
    var monthlyCardCount: Int = 0
    var hardToRememberCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @MainActor
    func loadStatistics() async {
        logger.info("Attempting to fetch statistics from server.")
        do {
            // Use StrapiService to fetch statistics
            let stats = try await StrapiService.shared.fetchFlashcardStatistics()
            
            self.totalCardCount = stats.totalCards
            self.rememberedCount = stats.remembered
            self.newCardCount = stats.newCards
            self.warmUpCardCount = stats.warmUp
            self.weeklyReviewCardCount = stats.weekly
            self.monthlyCardCount = stats.monthly
            self.hardToRememberCount = stats.hardToRemember
            
            logger.info("Successfully loaded statistics from the server.")
        } catch {
            logger.error("Failed to fetch statistics from server: \(error.localizedDescription). Falling back to local calculation.")
            await calculateStatisticsLocally()
        }
    }

    @MainActor
    private func calculateStatisticsLocally() async {
        logger.info("Calculating statistics from local data as a fallback.")
        do {
            let descriptor = FetchDescriptor<Flashcard>()
            let allCards = try modelContext.fetch(descriptor)

            self.totalCardCount = allCards.count
            self.rememberedCount = allCards.filter { $0.reviewTire == "remembered" }.count
            self.newCardCount = allCards.filter { $0.reviewTire == "new" }.count
            self.warmUpCardCount = allCards.filter { $0.reviewTire == "warmup" }.count
            self.weeklyReviewCardCount = allCards.filter { $0.reviewTire == "weekly" }.count
            self.monthlyCardCount = allCards.filter { $0.reviewTire == "monthly" }.count
            self.hardToRememberCount = allCards.filter { $0.wrongStreak >= 3 }.count

            logger.info("Successfully calculated statistics locally from \(allCards.count) cards.")

        } catch {
            logger.error("calculateStatisticsLocally: Failed to load cards from local store: \(error.localizedDescription)")
        }
    }

    @MainActor
    func prepareReviewSession() async {
        logger.info("Attempting to fetch review session from server.")
        do {
            let fetchedCards = try await StrapiService.shared.fetchReviewFlashcards(modelContext: modelContext)
            self.reviewCards = fetchedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")
        } catch {
            logger.warning("Could not fetch review session from server. Error: \(error.localizedDescription). Falling back to local data.")
            do {
                let descriptor = FetchDescriptor<Flashcard>(
                    predicate: #Predicate { !$0.isRemembered },
                    sortBy: [SortDescriptor(\.lastReviewedAt, order: .forward)]
                )
                self.reviewCards = try modelContext.fetch(descriptor)
                logger.info("Successfully loaded \(self.reviewCards.count) cards for review from local storage as a fallback.")
            } catch {
                logger.error("Fallback failed: Could not fetch cards from local storage either: \(error.localizedDescription)")
                self.reviewCards = []
            }
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
            _ = try await StrapiService.shared.submitFlashcardReview(cardId: card.id, result: result, modelContext: modelContext)
            logger.info("Successfully synced updated card \(card.id) from server after review.")
        } catch {
            logger.error("Failed to submit and sync review for flashcard \(card.id): \(error.localizedDescription)")
        }
    }

    // MARK: - New Word Logic

    /// Saves a new user-created word to Strapi.
    /// - Parameters:
    ///   - word: The target word (e.g., "run").
    ///   - baseText: The base form or definition (e.g., "to run").
    ///   - partOfSpeech: The part of speech (e.g., "verb").
    @MainActor
    func saveNewUserWord(targetText: String, baseText: String, partOfSpeech: String, baseLocale: String, targetLocale: String) async throws {
        do {
            logger.info("Attempting to save new user word: '\(targetText)' with base text '\(baseText)' and part of speech '\(partOfSpeech)'")
            
            // Use StrapiService to save new user word
            let _: UserWordResponse = try await StrapiService.shared.saveNewUserWord(targetText: targetText, baseText: baseText, partOfSpeech: partOfSpeech, baseLocale: baseLocale, targetLocale: targetLocale)
            
            logger.info("Successfully saved new user word: '\(targetText)' to Strapi.")
            
            // After saving, refresh statistics to reflect the new word count
            await loadStatistics()
            
        } catch {
            logger.error("Failed to save new user word '\(targetText)': \(error.localizedDescription)")
            throw error // Re-throw to be handled by the UI
        }
    }

    /// Translates a word using the /api/translate-word endpoint.
    /// - Parameters:
    ///   - word: The word to translate.
    ///   - source: The source language code (e.g., "en").
    ///   - target: The target language code (e.g., "zh-CN").
    /// - Returns: The translated word.
    @MainActor
    func translateWord(word: String, source: String, target: String) async throws -> String {
        do {
            logger.info("Attempting to translate word '\(word)' from \(source) to \(target)")
            // Use StrapiService to translate word
            let response: TranslateWordResponse = try await StrapiService.shared.translateWord(word: word, source: source, target: target)
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
