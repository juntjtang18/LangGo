// LangGo/Vocabook/VocabookViewModel.swift

import Foundation
import os
import SwiftUI

// MARK: - In-Memory Data Models

struct WeightedProgress {
    let progress: Double
    let isComplete: Bool
}

struct Vocabook: Identifiable {
    let id: Int
    var title: String
    var vocapages: [Vocapage]?
}

struct Vocapage: Identifiable {
    let id: Int
    var title: String
    var order: Int
    var flashcards: [Flashcard]?

    var progress: Double {
        return 0.0
    }
    
    var weightedProgress: WeightedProgress {
        return WeightedProgress(progress: 0.0, isComplete: false)
    }
}

// MARK: - VocabookViewModel
@MainActor
class VocabookViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookViewModel")
    
    // The service is now fetched directly from the DataServices singleton.
    private let settingsService = DataServices.shared.settingsService
    private let flashcardService = DataServices.shared.flashcardService
    private let wordService = DataServices.shared.wordService
    
    @Published var vocabook: Vocabook?
    @Published var isLoadingVocabooks = false
    @Published var expandedVocabooks: Set<Int> = []
    @Published var loadCycle: Int = 0
    
    @Published var totalFlashcards: Int = 0
    @Published var totalPages: Int = 1
    @Published var totalCards: Int = 0
    @Published var rememberedCount: Int = 0
    @Published var dueForReviewCount: Int = 0
    @Published var reviewedCount: Int = 0
    @Published var hardToRememberCount: Int = 0
    @Published var tierStats: [StrapiTierStat] = []
    
    // MODIFIED: The initializer now registers an observer for our custom notification.
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshData),
            name: .flashcardsDidChange,
            object: nil
        )
    }
    
    // NEW: A deinitializer is added to remove the observer and prevent memory leaks.
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // NEW: This is the function called by the notification. It's marked @objc.
    @objc private func refreshData() {
        logger.info("📢 Received notification that flashcards changed. Refreshing data...")
        Task {
            // Check user's current filter setting to refresh the view correctly.
            let dueOnly = UserDefaults.standard.bool(forKey: "isShowingDueWordsOnly")
            await loadVocabookPages(dueOnly: dueOnly)
            await loadStatistics()
        }
    }
    
    func loadStatistics() async {
        do {
            let stats = try await flashcardService.fetchFlashcardStatistics()
            totalCards            = stats.totalCards
            rememberedCount       = stats.remembered
            dueForReviewCount     = stats.dueForReview
            reviewedCount         = stats.reviewed
            hardToRememberCount   = stats.hardToRemember
            tierStats             = stats.byTier.sorted { $0.min_streak < $1.min_streak }
        } catch {
            logger.error("loadStatistics failed: \(error.localizedDescription)")
        }
    }
    @MainActor
    func deleteCardAndRefresh(cardId: Int) async {
        do {
            // The service deletes the card and invalidates the cache
            try await flashcardService.deleteFlashcard(cardId: cardId)
            
            // Reload the pages with the current filter setting.
            // This will fetch fresh data because the cache is now stale.
            // This effectively "reconstructs" the vocapage as requested.
            let dueOnly = UserDefaults.standard.bool(forKey: "isShowingDueWordsOnly")
            await loadVocabookPages(dueOnly: dueOnly)
            
            // Also refresh the statistics panel
            await loadStatistics()
            
        } catch {
            // Handle the error appropriately, e.g., show an error message to the user
            logger.error("Failed to delete card and refresh: \(error.localizedDescription)")
        }
    }
    // MARK: - Refactored Vocabook Loading
    
    /// Fetches and paginates flashcards, either all cards or only those due for review.
    /// This is now the single source of truth for the vocabook view's data.
    /// - Parameter dueOnly: If `true`, fetches only review flashcards. Otherwise, fetches all flashcards.
    func loadVocabookPages(dueOnly: Bool = false) async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch the appropriate full list of cards from the network
            let allFlashcards: [Flashcard]
            if dueOnly {
                allFlashcards = try await flashcardService.fetchAllReviewFlashcards()
                logger.info("Fetched \(allFlashcards.count) due flashcards for vocabook.")
            } else {
                allFlashcards = try await flashcardService.fetchAllMyFlashcards()
                 logger.info("Fetched \(allFlashcards.count) total flashcards for vocabook.")
            }

            // Keep this as the visible dataset count if you need it elsewhere,
            // but DO NOT touch `totalCards` here (that comes from statistics).
            self.totalFlashcards = allFlashcards.count
            
            // 2. Get pagination settings
            let vbSetting = try await settingsService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            // 3. Paginate the fetched list in memory
            guard !allFlashcards.isEmpty else {
                self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
                return
            }
            
            let totalPages = Int(ceil(Double(allFlashcards.count) / Double(pageSize)))

            var pages: [Vocapage] = []
            for pageNum in 1...totalPages {
                let startIndex = (pageNum - 1) * pageSize
                let endIndex = min(startIndex + pageSize, allFlashcards.count)
                
                let pageCards = Array(allFlashcards[startIndex..<endIndex])
                
                var newPage = Vocapage(id: pageNum, title: "Page \(pageNum)", order: pageNum)
                newPage.flashcards = pageCards
                pages.append(newPage)
            }
            
            let book = Vocabook(id: 1, title: "All Flashcards", vocapages: pages)
            
            self.vocabook = book
            self.loadCycle += 1

        } catch {
            logger.error("loadVocabookPages(dueOnly: \(dueOnly)) failed: \(error.localizedDescription)")
            self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
        }
    }

    func toggleVocabookExpansion(vocabookId: Int) {
        if expandedVocabooks.contains(vocabookId) {
            expandedVocabooks.remove(vocabookId)
        } else {
            expandedVocabooks.insert(vocabookId)
        }
    }
    
    // MARK: - Search (target language or base if desired)
    func searchForWord(query: String, searchBase: Bool = false) async throws -> [StrapiWordDefinition] {
        try await wordService.searchWordDefinitions(term: query)
    }
}
