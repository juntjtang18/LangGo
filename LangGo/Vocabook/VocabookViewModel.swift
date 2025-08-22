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
    private let strapiService = DataServices.shared.strapiService

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
    //@Published var newCardCount: Int = 0
    @Published var tierStats: [StrapiTierStat] = []
    
    // The initializer is now clean and parameter-less.
    init() {}
    // Add this method anywhere inside the class:
    func loadStatistics() async {
        do {
            let stats = try await strapiService.fetchFlashcardStatistics()
            totalCards            = stats.totalCards
            rememberedCount       = stats.remembered
            dueForReviewCount     = stats.dueForReview
            reviewedCount         = stats.reviewed
            hardToRememberCount   = stats.hardToRemember
            //newCardCount          = stats.newCardCount ?? stats.byTier.first(where: { $0.tier == "new" })?.count ?? 0
            tierStats             = stats.byTier.sorted { $0.min_streak < $1.min_streak }
        } catch {
            Logger(subsystem: "com.langGo.swift", category: "VocabookViewModel")
                .error("loadStatistics failed: \(error.localizedDescription)")
        }
    }
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            let vbSetting = try await strapiService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            let allFlashcards = try await strapiService.fetchAllMyFlashcards()
            
            self.totalFlashcards = allFlashcards.count
            
            guard !allFlashcards.isEmpty else {
                self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
                return
            }
            
            let totalPages = Int(ceil(Double(totalFlashcards) / Double(pageSize)))

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
            logger.error("loadVocabookPages failed: \(error.localizedDescription)")
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
}
