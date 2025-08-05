import SwiftUI
import os

class FlashcardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    private let strapiService: StrapiService
    
    // This property holds all of the user's flashcards.
    @Published var myCards: [Flashcard] = []
    
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

    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }
    
    // MARK: - Card Management
    @MainActor
    func fetchAllMyCards() async {
        logger.info("Fetching all user flashcards.")
        do {
            self.myCards = try await strapiService.fetchAllMyFlashcards()
            logger.info("Successfully fetched \(self.myCards.count) user flashcards.")
        } catch {
            logger.error("Failed to fetch user flashcards: \(error.localizedDescription)")
            self.myCards = []
        }
    }

    // MARK: - Statistics
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
            logger.error("Failed to fetch statistics from server: \(error.localizedDescription).")
        }
    }

    // MARK: - Review Session
    @MainActor
    func prepareReviewSession() async {
        logger.info("Attempting to fetch review session from server.")
        do {
            let fetchedCards = try await strapiService.fetchAllReviewFlashcards()
            self.reviewCards = fetchedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")
        } catch {
            logger.error("Could not fetch review session from server. Error: \(error.localizedDescription).")
            self.reviewCards = []
        }
    }
    
    // MARK: - Review Logic
    func markReview(for card: Flashcard, result: ReviewResult) {
        Task { await submitReview(for: card, result: result) }
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
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String) async throws {
        do {
            let tgt = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = baseText.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Saving new word -> target:'\(tgt, privacy: .public)' | base:'\(base, privacy: .public)' | pos:'\(partOfSpeech, privacy: .public)'")
            _ = try await strapiService.saveNewWord(
                targetText: tgt,
                baseText: base,
                partOfSpeech: partOfSpeech
            )
            logger.info("Saved new word successfully.")
            // Refresh user's cards and stats after saving a new one
            await fetchAllMyCards()
            await loadStatistics()
        } catch {
            logger.error("Failed to save new word: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Translation
    @MainActor
    func translateWord(word: String, source: String, target: String) async throws -> String {
        do {
            logger.info("Attempting to translate word '\(word, privacy: .public)' from \(source, privacy: .public) to \(target, privacy: .public)")
            let response: TranslateWordResponse = try await strapiService.translateWord(word: word, source: source, target: target)
            logger.info("Successfully translated word: \(response.translatedText, privacy: .public)")
            return response.translatedText
        } catch {
            logger.error("Failed to translate word '\(word, privacy: .public)': \(error.localizedDescription)")
            throw error
        }
    }
    
    @MainActor
    func searchForWord(term: String, searchBase: Bool) async throws -> [SearchResult] {
        logger.info("Searching for term '\(term)', searchBase: \(searchBase)")
        
        if searchBase {
            // Search by BASE language
            let definitions = try await strapiService.searchWordDefinitions(term: term)
            let results = definitions.map { definitionData -> SearchResult in
                let attributes = definitionData.attributes
                // SIMPLIFIED LOGIC: Check if the now-standard flashcards array is empty.
                let isAlreadyAdded = !(attributes.flashcards?.data.isEmpty ?? true)
                
                return SearchResult(
                    id: "def-\(definitionData.id)",
                    wordDefinitionId: definitionData.id,
                    baseText: attributes.baseText ?? "",
                    targetText: attributes.word?.data?.attributes.targetText ?? "",
                    partOfSpeech: attributes.partOfSpeech?.data?.attributes.name ?? "N/A",
                    isAlreadyAdded: isAlreadyAdded
                )
            }
            logger.debug("searchForWord (base) is returning \(results.count) results for term '\(term)'.")
            return results
        } else {
            // Search by TARGET language
            let words = try await strapiService.searchWords(term: term)
            var results: [SearchResult] = []
            
            for wordData in words {
                guard let definitions = wordData.attributes.word_definitions?.data else { continue }
                
                for definitionData in definitions {
                    let defAttributes = definitionData.attributes
                    // SIMPLIFIED LOGIC: Check if the now-standard flashcards array is empty.
                    let isAlreadyAdded = !(defAttributes.flashcards?.data.isEmpty ?? true)
                    
                    results.append(SearchResult(
                        id: "word-\(wordData.id)-def-\(definitionData.id)",
                        wordDefinitionId: definitionData.id,
                        baseText: defAttributes.baseText ?? "",
                        targetText: wordData.attributes.targetText ?? "",
                        partOfSpeech: defAttributes.partOfSpeech?.data?.attributes.name ?? "N/A",
                        isAlreadyAdded: isAlreadyAdded
                    ))
                }
            }
            logger.debug("searchForWord (target) is returning \(results.count) results for term '\(term)'.")
            return results
        }
    }
}

enum ReviewResult: String {
    case correct
    case wrong
}
