import SwiftUI
import CoreData // Use CoreData instead of SwiftData
import os

// 1. Conform to ObservableObject instead of using @Observable
class FlashcardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    private let strapiService: StrapiService
    // 2. Use NSManagedObjectContext
    private let managedObjectContext: NSManagedObjectContext
    
    // 3. Use @Published to notify views of changes
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

    // 4. The initializer now accepts the Core Data context
    init(managedObjectContext: NSManagedObjectContext, strapiService: StrapiService) {
        self.managedObjectContext = managedObjectContext
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
            logger.error("Failed to fetch statistics from server: \(error.localizedDescription). Falling back to local calculation.")
            await calculateStatisticsLocally()
        }
    }

    @MainActor
    private func calculateStatisticsLocally() async {
        logger.info("Calculating statistics from local data as a fallback.")
        do {
            // 5. Use NSFetchRequest to fetch local data
            let request = NSFetchRequest<Flashcard>(entityName: "Flashcard")
            let allCards = try managedObjectContext.fetch(request)

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
            let fetchedCards = try await strapiService.fetchAllReviewFlashcards()
            self.reviewCards = fetchedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")
        } catch {
            logger.warning("Could not fetch review session from server. Error: \(error.localizedDescription). Falling back to local data.")
            do {
                // 6. Use NSFetchRequest for the local fallback
                let request = NSFetchRequest<Flashcard>(entityName: "Flashcard")
                request.predicate = NSPredicate(format: "isRemembered == NO")
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Flashcard.lastReviewedAt, ascending: true)]
                
                self.reviewCards = try managedObjectContext.fetch(request)
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
            _ = try await strapiService.submitFlashcardReview(cardId: Int(card.id), result: result)
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
    // Corrected to match StrapiService enum if it exists, otherwise keep as is.
    case correct
    case wrong
}
