// LangGo/VocabookViewModel.swift
import Foundation
import SwiftData
import os
import SwiftUI

// MARK: - SwiftData Models (Moved from separate files)
@Model
final class Vocabook {
    @Attribute(.unique) var id: Int
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Vocapage.vocabook)
    var vocapages: [Vocapage]?

    init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

// A new struct to hold the calculated weighted progress.
struct WeightedProgress {
    let progress: Double
    let isComplete: Bool
}

@Model
final class Vocapage {
    @Attribute(.unique) var id: Int
    var title: String
    var order: Int
    @Relationship(deleteRule: .nullify)
    var flashcards: [Flashcard]?
    var vocabook: Vocabook?

    init(id: Int, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }

    var progress: Double {
        guard let cards = flashcards, !cards.isEmpty else { return 0.0 }
        let rememberedCount = cards.filter { $0.isRemembered || $0.correctStreak >= 11 }.count
        return Double(rememberedCount) / Double(cards.count)
    }
    
    // This property is now a placeholder; the real calculation happens in the View.
    var weightedProgress: WeightedProgress {
        // The actual calculation requires the settings manager, so we do it in the view.
        // This just provides a default structure.
        return WeightedProgress(progress: 0.0, isComplete: false)
    }
}


// MARK: - VocabookViewModel
@Observable
class VocabookViewModel {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookViewModel")
    private let modelContext: ModelContext
    private let strapiService: StrapiService
    var loadCycle: Int = 0

    var vocabook: Vocabook?
    var isLoadingVocabooks = false
    var expandedVocabooks: Set<Int> = []
    
    var totalFlashcards: Int = 0
    var totalPages: Int = 1
    
    init(modelContext: ModelContext, strapiService: StrapiService) {
        self.modelContext = modelContext
        self.strapiService = strapiService
    }
    
    @MainActor
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch settings and pagination info in one call
            let vb = try await strapiService.fetchVBSetting()
            let pageSize = vb.attributes.wordsPerPage
            let (_, pagination) = try await strapiService.fetchFlashcards(page: 1, pageSize: pageSize)

            guard let pag = pagination else {
                totalFlashcards = 0
                totalPages = 1
                return
            }
            totalFlashcards = pag.total
            totalPages = pag.pageCount

            // 2. Find or create the main Vocabook
            let bookId = 1
            var fetchDescriptor = FetchDescriptor<Vocabook>(predicate: #Predicate { $0.id == bookId })
            fetchDescriptor.fetchLimit = 1
            
            let book: Vocabook
            if let existingBook = try modelContext.fetch(fetchDescriptor).first {
                book = existingBook
            } else {
                book = Vocabook(id: bookId, title: "All Flashcards")
                modelContext.insert(book)
            }

            // 3. Sync Vocapages
            let existingPages = book.vocapages ?? []
            let existingPageIds = Set(existingPages.map { $0.id })
            let pageNumbersToKeep = Set(1...totalPages)

            // Delete stale pages that are no longer valid
            let pagesToDelete = existingPages.filter { !pageNumbersToKeep.contains($0.id) }
            for page in pagesToDelete {
                modelContext.delete(page)
            }

            // Add new pages that don't exist yet
            let newPageNumbers = pageNumbersToKeep.subtracting(existingPageIds)
            for pageNum in newPageNumbers {
                let newPage = Vocapage(id: pageNum, title: "Page \(pageNum)", order: pageNum)
                newPage.vocabook = book
                modelContext.insert(newPage)
            }
            
            // 4. Save changes and update the view model's vocabook property
            try modelContext.save()
            self.vocabook = book
            self.loadCycle += 1

        } catch {
            logger.error("loadVocabookPages failed: \(error.localizedDescription)")
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
