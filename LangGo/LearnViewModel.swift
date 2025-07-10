// LangGo/LearnViewModel.swift
import Foundation
import SwiftData
import os

// MARK: - SwiftData Models (Moved from separate files)
// These models are now defined within the same file as LearnViewModel
// to reduce file count, but remain top-level @Model classes as required by SwiftData.

@Model
final class Vocabook {
    @Attribute(.unique) var id: Int
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Vocapage.vocabook)
    var vocapages: [Vocapage]? // One-to-many relationship with Vocapage

    init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

@Model
final class Vocapage {
    @Attribute(.unique) var id: Int
    var title: String
    var order: Int
    @Relationship(deleteRule: .nullify)
    var flashcards: [Flashcard]? // One-to-many relationship with Flashcard
    var vocabook: Vocabook? // Many-to-one relationship with Vocabook

    init(id: Int, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }

    // Helper to calculate progress based on remembered flashcards
    var progress: Double {
        guard let cards = flashcards, !cards.isEmpty else { return 0.0 }
        let rememberedCount = cards.filter { $0.isRemembered || $0.correctStreak >= 11 }.count
        return Double(rememberedCount) / Double(cards.count)
    }
}


// MARK: - LearnViewModel


@Observable
class LearnViewModel {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LearnViewModel")
    private var modelContext: ModelContext

    var vocabook: Vocabook?
    var isLoadingVocabooks = false
    var expandedVocabooks: Set<Int> = [] // To keep track of expanded vocabooks
    
    var flashcards: [Flashcard] = []
    var totalFlashcards: Int = 0
    var totalPages: Int = 1
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    @MainActor
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch settings and pagination info
            let vb = try await StrapiService.shared.fetchVBSetting()
            let pageSize = vb.attributes.wordsPerPage
            // The result of this call is not directly used, but it warms the cache and syncs data.
            _ = try await StrapiService.shared.fetchFlashcards(page: 1, pageSize: pageSize, modelContext: modelContext)

            // Since fetchFlashcards now returns [Flashcard], we need to adjust how we get pagination info.
            // This part of the logic might need rethinking. For now, we'll assume a separate call or a different response structure is needed for pagination meta.
            // Let's call the network manager directly for the meta data for now.
            guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/mine?pagination[page]=1&pagination[pageSize]=\(pageSize)") else {
                return
            }
            let metaResponse: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)


            guard let pag = metaResponse.meta?.pagination else {
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
                newPage.vocabook = book // Establish relationship
                modelContext.insert(newPage)
            }
            
            // 4. Save changes and update the view model's vocabook property
            try modelContext.save()
            self.vocabook = book

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
