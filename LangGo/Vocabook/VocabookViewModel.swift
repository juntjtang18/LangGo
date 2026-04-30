// LangGo/Vocabook/VocabookViewModel.swift

import Combine
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
    private var cancellables = Set<AnyCancellable>()
    
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
        flashcardService.$flashcardStatistics
            .compactMap { $0 }
            .sink { [weak self] stats in
                Task { @MainActor in
                    self?.applyStatistics(stats)
                }
            }
            .store(in: &cancellables)

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
            applyStatistics(stats)
        } catch {
            logger.error("loadStatistics failed: \(error.localizedDescription)")
        }
    }

    private func applyStatistics(_ stats: StrapiStatistics) {
        totalCards            = stats.totalCards
        rememberedCount       = stats.remembered
        dueForReviewCount     = stats.dueForReview
        reviewedCount         = stats.reviewed ?? 0
        hardToRememberCount   = stats.hardToRemember ?? 0
        tierStats             = stats.byTier.sorted { $0.min_streak < $1.min_streak }
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
    
    /// Builds Book Mode page ids without loading every flashcard.
    ///
    /// Book Mode page content is loaded lazily by `VocapageLoader`. This method
    /// only needs the card count, so it uses flashcard statistics instead of
    /// `fetchAllMyFlashcards()` / `fetchAllReviewFlashcards()`. That prevents the
    /// first Book Mode open from blocking on a full backend pagination pass.
    /// - Parameter dueOnly: If `true`, builds page ids from due-for-review count.
    ///   Otherwise, builds page ids from total card count.
    func loadVocabookPages(dueOnly: Bool = false) async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            async let statsTask = flashcardService.fetchFlashcardStatistics()
            async let vbSettingTask = settingsService.fetchVBSetting()

            let stats = try await statsTask
            let vbSetting = try await vbSettingTask
            let pageSize = max(1, vbSetting.attributes.wordsPerPage)

            let visibleCount = dueOnly ? stats.dueForReview : stats.totalCards
            self.totalFlashcards = visibleCount

            guard visibleCount > 0 else {
                self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
                self.loadCycle += 1
                return
            }

            let pageCount = Int(ceil(Double(visibleCount) / Double(pageSize)))
            let pages = (1...pageCount).map { pageNum in
                Vocapage(id: pageNum, title: "Page \(pageNum)", order: pageNum, flashcards: nil)
            }

            self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: pages)
            self.loadCycle += 1

            logger.info("Prepared \(pageCount) vocabook page ids from statistics. dueOnly=\(dueOnly), count=\(visibleCount).")
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
