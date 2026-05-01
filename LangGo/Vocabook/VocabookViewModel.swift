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
    
    private let flashcardService = DataServices.shared.flashcardService
    private let wordService = DataServices.shared.wordService
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isLoadingStatistics = false
    @Published var expandedVocabooks: Set<Int> = []
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
            await loadStatistics()
        }
    }
    
    func loadStatistics() async {
        isLoadingStatistics = true
        defer { isLoadingStatistics = false }

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
            try await flashcardService.deleteFlashcard(cardId: cardId)
            await loadStatistics()
        } catch {
            logger.error("Failed to delete card and refresh: \(error.localizedDescription)")
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
