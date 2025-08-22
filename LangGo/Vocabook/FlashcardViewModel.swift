// LangGo/Vocabook/FlashcardViewModel.swift
import SwiftUI
import os

@MainActor
class FlashcardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    private let strapiService = DataServices.shared.strapiService
    
    // Card data this VM actually owns
    @Published var myCards: [Flashcard] = []
    @Published var reviewCards: [Flashcard] = []
    @Published var userReviewLogs: [StrapiReviewLog] = []  // keep if you use it elsewhere

    init() {}

    // MARK: - Cards
    
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

    // MARK: - Review Session
    
    func prepareReviewSession() async {
        logger.info("Attempting to fetch review session from server.")
        do {
            let fetchedCards = try await strapiService.fetchAllReviewFlashcards()
            self.reviewCards = fetchedCards.sorted {
                ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast)
            }
            logger.info("prepareReviewSession: Loaded \(self.reviewCards.count) cards for review.")
        } catch {
            logger.error("Could not fetch review session from server. Error: \(error.localizedDescription)")
            self.reviewCards = []
        }
    }

    func markReview(for card: Flashcard, result: ReviewResult) {
        Task { await submitReview(for: card, result: result) }
    }

    private func submitReview(for card: Flashcard, result: ReviewResult) async {
        do {
            logger.info("Submitting review for card \(card.id) with result '\(result.rawValue)'")
            _ = try await strapiService.submitFlashcardReview(cardId: card.id, result: result)
            logger.info("Review submitted and synced for card \(card.id).")
        } catch {
            logger.error("Failed to submit/sync review for card \(card.id): \(error.localizedDescription)")
        }
    }

    // MARK: - New Word
    
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String, locale: String) async throws {
        do {
            let tgt = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = baseText.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Saving new word -> target:'\(tgt, privacy: .public)' | base:'\(base, privacy: .public)' | pos:'\(partOfSpeech, privacy: .public)' | locale:'\(locale, privacy: .public)'")
            _ = try await strapiService.saveNewWord(
                targetText: tgt,
                baseText: base,
                partOfSpeech: partOfSpeech,
                locale: locale
            )
            logger.info("Saved new word successfully.")
            // Refresh the user's cards; stats are now owned by VocabookViewModel
            await fetchAllMyCards()
        } catch {
            logger.error("Failed to save new word: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Translate / Search
    
    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        do {
            logger.info("Translating '\(word, privacy: .public)' from \(source, privacy: .public) to \(target, privacy: .public)")
            let response: TranslateWordResponse = try await strapiService.translateWord(word: word, source: source, target: target)
            return response
        } catch {
            logger.error("Translation failed: \(error.localizedDescription)")
            throw error
        }
    }

    func searchForWord(term: String, searchBase: Bool) async throws -> [SearchResult] {
        logger.info("Searching term '\(term)' (searchBase: \(searchBase))")
        if searchBase {
            let definitions = try await strapiService.searchWordDefinitions(term: term)
            return definitions.map { def in
                let a = def.attributes
                let isAlready = !(a.flashcards?.data.isEmpty ?? true)
                return SearchResult(
                    id: "def-\(def.id)",
                    wordDefinitionId: def.id,
                    baseText: a.baseText ?? "",
                    targetText: a.word?.data?.attributes.targetText ?? "",
                    partOfSpeech: a.partOfSpeech?.data?.attributes.name ?? "N/A",
                    isAlreadyAdded: isAlready
                )
            }
        } else {
            let words = try await strapiService.searchWords(term: term)
            var results: [SearchResult] = []
            for w in words {
                guard let defs = w.attributes.word_definitions?.data else { continue }
                for d in defs {
                    let a = d.attributes
                    let isAlready = !(a.flashcards?.data.isEmpty ?? true)
                    results.append(
                        SearchResult(
                            id: "word-\(w.id)-def-\(d.id)",
                            wordDefinitionId: d.id,
                            baseText: a.baseText ?? "",
                            targetText: w.attributes.targetText ?? "",
                            partOfSpeech: a.partOfSpeech?.data?.attributes.name ?? "N/A",
                            isAlreadyAdded: isAlready
                        )
                    )
                }
            }
            return results
        }
    }
}

enum ReviewResult: String { case correct, wrong }
