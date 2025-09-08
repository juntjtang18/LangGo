// LangGo/Vocabook/FlashcardViewModel.swift
import SwiftUI
import os

@MainActor
class FlashcardViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    private let wordService = DataServices.shared.wordService
    private let flashcardService = DataServices.shared.flashcardService
    // Card data this VM actually owns
    @Published var myCards: [Flashcard] = []
    @Published var reviewCards: [Flashcard] = []
    @Published var userReviewLogs: [StrapiReviewLog] = []  // keep if you use it elsewhere

    init() {}

    // MARK: - Cards
    
    func fetchAllMyCards() async {
        logger.info("Fetching all user flashcards.")
        do {
            self.myCards = try await flashcardService.fetchAllMyFlashcards()
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
            let fetchedCards = try await flashcardService.fetchAllReviewFlashcards()
            self.reviewCards = fetchedCards.sorted {
                ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast)
            }
            logger.info("prepareReviewSession: Loaded \(self.reviewCards.count) cards for review.")
        } catch {
            logger.error("Could not fetch review session from server. Error: \(error.localizedDescription)")
            self.reviewCards = []
        }
    }

    // Keep the old optimistic path
    func submitReviewOptimistic(for card: Flashcard, result: ReviewResult) {
        Task.detached(priority: .utility) { [flashcardService, logger] in
            do {
                _ = try await flashcardService.submitFlashcardReview(cardId: card.id, result: result)
                logger.info("Review submitted and synced for card \(card.id).")
            } catch {
                logger.error("Failed to submit/sync review for card \(card.id): \(error.localizedDescription)")
            }
        }
    }

    // New function to be used for the last card
    func submitReviewAndWait(for card: Flashcard, result: ReviewResult) async {
        do {
            logger.info("Submitting FINAL review for card \(card.id) with result '\(result.rawValue)'")
            _ = try await flashcardService.submitFlashcardReview(cardId: card.id, result: result)
            logger.info("Final review submitted and synced for card \(card.id).")
            // Optionally, re-fetch data after the last card is submitted.
            // This ensures the statistics screen is accurate when loaded.
            await self.fetchAllMyCards()
        } catch {
            logger.error("Failed to submit/sync FINAL review for card \(card.id): \(error.localizedDescription)")
        }
    }
    
    // Keep the old submit path if you ever need strict awaits elsewhere.
    private func submitReview(for card: Flashcard, result: ReviewResult) async {
        await submitReviewOptimistic(for: card, result: result)
    }

    
    // MARK: - New Word
    
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String, locale: String) async throws {
        do {
            let tgt = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = baseText.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("Saving new word -> target:'\(tgt, privacy: .public)' | base:'\(base, privacy: .public)' | pos:'\(partOfSpeech, privacy: .public)' | locale:'\(locale, privacy: .public)'")
            _ = try await wordService.saveNewWord(
                targetText: tgt,
                baseText: base,
                partOfSpeech: partOfSpeech,
                locale: locale
            )
            logger.info("Saved new word successfully.")
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
            let response: TranslateWordResponse = try await wordService.translateWord(word: word, source: source, target: target)
            return response
        } catch {
            logger.error("Translation failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Translate / Search

    func searchForWord(term: String, searchBase: Bool) async throws -> [StrapiWordDefinition] {
        logger.info("Searching term '\(term, privacy: .public)' (searchBase: \(searchBase))")

        if searchBase {
            // Search by BASE language → API already returns WordDefinitions
            return try await wordService.searchWordDefinitions(term: term)
        } else {
            // Search by TARGET language → flatten words -> definitions
            let words = try await wordService.searchWords(term: term)
            var out: [StrapiWordDefinition] = []
            var seen = Set<Int>() // dedupe by definition id

            for w in words {
                guard let defs = w.attributes.word_definitions?.data else { continue }
                for d in defs where !seen.contains(d.id) {
                    out.append(d)
                    seen.insert(d.id)
                }
            }
            return out
        }
    }

}

enum ReviewResult: String { case correct, wrong }
