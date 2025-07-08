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
            
            // A card is "remembered" if the flag is true OR its streak is 11 or higher.
            let rememberedCards = allCards.filter { $0.isRemembered || $0.correctStreak >= 11 }
            
            // "Active" cards are those not remembered
            let activeCards = allCards.filter { !($0.isRemembered || $0.correctStreak >= 11) }

            self.totalCardCount = allCards.count
            self.rememberedCount = rememberedCards.count
            
            // New Cards (correct_streak is 0-3)
            self.newCardCount = activeCards.filter { (0...3).contains($0.correctStreak) }.count

            // Warm-up Cards (correct_streak is 4-6)
            self.warmUpCardCount = activeCards.filter { (4...6).contains($0.correctStreak) }.count

            // Weekly Review Cards (correct_streak is 7-8)
            self.weeklyReviewCardCount = activeCards.filter { (7...8).contains($0.correctStreak) }.count

            // Monthly Cards (correct_streak is 9-10)
            self.monthlyCardCount = activeCards.filter { (9...10).contains($0.correctStreak) }.count
            
            // Hard to remember (wrong_streak >= 3)
            self.hardToRememberCount = activeCards.filter { $0.wrongStreak >= 3 }.count
            
            logger.info("Successfully calculated statistics locally from \(allCards.count) cards.")

        } catch {
            logger.error("calculateStatisticsLocally: Failed to load cards from local store: \(error.localizedDescription)")
        }
    }

    @MainActor
    func prepareReviewSession() async {
        logger.info("Attempting to fetch review session from server.")
        do {
            try await fetchAndLoadReviewCardsFromServer()
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

    @MainActor
    private func fetchAndLoadReviewCardsFromServer() async throws {
        logger.debug("fetchAndLoadReviewCardsFromServer called.")

        do {
            // Use StrapiService to fetch review flashcards
            let fetchedData: StrapiResponse = try await StrapiService.shared.fetchReviewFlashcards()
            var processedCards: [Flashcard] = []

            for strapiCard in fetchedData.data {
                do {
                    let card = try await syncCard(strapiCard)
                    processedCards.append(card)
                } catch {
                    logger.error("Error processing card \(strapiCard.id): \(error.localizedDescription)")
                }
            }

            try modelContext.save()
            logger.info("Successfully saved/updated \(fetchedData.data.count) cards from review endpoint.")

            self.reviewCards = processedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")

        } catch {
            logger.error("fetchAndLoadReviewCardsFromServer: Failed to fetch or save data: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Review Logic

    func markReview(for card: Flashcard, result: ReviewResult) {
        Task {
            await submitReview(for: card, result: result)
            //await loadStatistics()
        }
    }

    @MainActor
    private func submitReview(for card: Flashcard, result: ReviewResult) async {
        do {
            logger.info("Submitting review for card \(card.id) with result '\(result.rawValue)'")
            
            // Use StrapiService to submit flashcard review
            let response: Relation<StrapiFlashcard> = try await StrapiService.shared.submitFlashcardReview(cardId: card.id, result: result)
            
            guard let updatedStrapiCard = response.data else {
                logger.error("Failed to submit review for card \(card.id): Server response was missing the 'data' object.")
                return
            }
            
            _ = try await self.syncCard(updatedStrapiCard)
            
            try self.modelContext.save()
            
            logger.info("Successfully synced updated card \(card.id) from server after review.")
            
        } catch {
            logger.error("Failed to submit and sync review for flashcard \(card.id): \(error.localizedDescription)")
        }
    }
    // MARK: - Data Syncing
    
    public func fetchDataFromServer(forceRefresh: Bool = false) async {
        do {
            // Use StrapiService to fetch all flashcards
            let fetchedData: StrapiResponse = try await StrapiService.shared.fetchAllFlashcardsWithContent()
            await updateLocalDatabase(with: fetchedData.data)
        } catch {
            logger.error("fetchDataFromServer: Failed to fetch or decode data: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateLocalDatabase(with strapiFlashcards: [StrapiFlashcard]) async {
        logger.debug("updateLocalDatabase called.")
        for strapiCard in strapiFlashcards {
            do {
                try await syncCard(strapiCard)
            } catch {
                 logger.error("updateLocalDatabase: Error processing card: \(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("updateLocalDatabase: Failed to save context: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    @discardableResult
    private func syncCard(_ strapiCard: StrapiFlashcard) async throws -> Flashcard {
        guard let component = strapiCard.attributes.content.first else {
            throw NSError(domain: "CardSyncError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Card \(strapiCard.id) has no content component."])
        }

        var frontContent: String?
        var backContent: String?
        var register: String?

        switch component.componentIdentifier {
        case "a.user-word-ref":
            frontContent = component.userWord?.data?.attributes.baseText
            backContent = component.userWord?.data?.attributes.targetText
        case "a.word-ref":
            frontContent = component.word?.data?.attributes.baseText
            backContent = component.word?.data?.attributes.word
            register = component.word?.data?.attributes.register
        case "a.user-sent-ref":
            frontContent = component.userSentence?.data?.attributes.baseText
            backContent = component.userSentence?.data?.attributes.targetText
        case "a.sent-ref":
            frontContent = component.sentence?.data?.attributes.baseText
            backContent = component.sentence?.data?.attributes.targetText
            register = component.sentence?.data?.attributes.register
        default:
            logger.warning("Unrecognized component type: \(component.componentIdentifier)")
        }

        let finalFront = frontContent ?? "Missing Question"
        let finalBack = backContent ?? "Missing Answer"
        let contentType = component.componentIdentifier
        let rawData = try? JSONEncoder().encode(component)
        let cardId = strapiCard.id
        
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
        fetchDescriptor.fetchLimit = 1

        if let cardToUpdate = try modelContext.fetch(fetchDescriptor).first {
            cardToUpdate.frontContent = finalFront
            cardToUpdate.backContent = finalBack
            cardToUpdate.register = register
            cardToUpdate.contentType = contentType
            cardToUpdate.rawComponentData = rawData
            cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
            cardToUpdate.isRemembered = strapiCard.attributes.isRemembered
            cardToUpdate.correctStreak = strapiCard.attributes.correctStreak ?? 0
            cardToUpdate.wrongStreak = strapiCard.attributes.wrongStreak ?? 0
            return cardToUpdate
        } else {
            let newCard = Flashcard(
                id: cardId,
                frontContent: finalFront,
                backContent: finalBack,
                register: register,
                contentType: contentType,
                rawComponentData: rawData,
                lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                correctStreak: strapiCard.attributes.correctStreak ?? 0,
                wrongStreak: strapiCard.attributes.wrongStreak ?? 0,
                isRemembered: strapiCard.attributes.isRemembered
            )
            modelContext.insert(newCard)
            return newCard
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
