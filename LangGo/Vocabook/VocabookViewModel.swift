// LangGo/Vocabook/VocabookViewModel.swift

import Foundation
import os
import SwiftUI

// MARK: - In-Memory Data Models

// A struct to hold the calculated weighted progress.
struct WeightedProgress {
    let progress: Double
    let isComplete: Bool
}

// MODIFIED: Vocabook is now a simple struct for in-memory use.
struct Vocabook: Identifiable {
    let id: Int
    var title: String
    var vocapages: [Vocapage]?
}

// MODIFIED: Vocapage is now a simple struct for in-memory use.
struct Vocapage: Identifiable {
    let id: Int
    var title: String
    var order: Int
    var flashcards: [Flashcard]? // This will be loaded on demand.

    // The progress calculation is now a placeholder, as flashcards are loaded separately.
    var progress: Double {
        return 0.0
    }
    
    var weightedProgress: WeightedProgress {
        return WeightedProgress(progress: 0.0, isComplete: false)
    }
}

// MARK: - VocabookViewModel

// MODIFIED: Converted to ObservableObject for iOS 16 compatibility.
@MainActor
class VocabookViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookViewModel")
    private let strapiService: StrapiService

    // MODIFIED: Properties that update the UI are now @Published.
    @Published var vocabook: Vocabook?
    @Published var isLoadingVocabooks = false
    @Published var expandedVocabooks: Set<Int> = []
    @Published var loadCycle: Int = 0
    
    @Published var totalFlashcards: Int = 0
    @Published var totalPages: Int = 1
    
    // MODIFIED: Initializer no longer requires a ModelContext.
    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }
    
    /*
    @MainActor
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch settings and pagination info from the server.
            let vb = try await strapiService.fetchVBSetting()
            let pageSize = vb.attributes.wordsPerPage
            // We only need the pagination from this call, not the flashcards themselves.
            let (_, pagination) = try await strapiService.fetchFlashcards(page: 1, pageSize: pageSize)

            guard let pag = pagination else {
                totalFlashcards = 0
                totalPages = 1
                // Create an empty vocabook if there's no data.
                self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
                return
            }
            
            self.totalFlashcards = pag.total
            self.totalPages = pag.pageCount

            // 2. Create Vocapage structs in memory based on the total page count.
            var pages: [Vocapage] = []
            for pageNum in 1...totalPages {
                let newPage = Vocapage(id: pageNum, title: "Page \(pageNum)", order: pageNum)
                pages.append(newPage)
            }
            
            // 3. Create the main Vocabook struct with the generated pages.
            let book = Vocabook(id: 1, title: "All Flashcards", vocapages: pages)
            
            // 4. Update the view model's state.
            self.vocabook = book
            self.loadCycle += 1

        } catch {
            logger.error("loadVocabookPages failed: \(error.localizedDescription)")
            // In case of an error, ensure the UI shows an empty state.
            self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
        }
    }
    */
    // --- THIS IS THE FIX ---
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch the user's page size setting first.
            let vbSetting = try await strapiService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            // 2. Fetch ALL flashcards at once. This is the crucial step
            //    that restores the original data flow.
            let allFlashcards = try await strapiService.fetchAllMyFlashcards()
            
            self.totalFlashcards = allFlashcards.count
            
            guard !allFlashcards.isEmpty else {
                self.vocabook = Vocabook(id: 1, title: "All Flashcards", vocapages: [])
                return
            }
            
            // 3. Calculate the total number of pages.
            let totalPages = Int(ceil(Double(totalFlashcards) / Double(pageSize)))

            // 4. Create Vocapage objects and populate each one with its slice of flashcards.
            var pages: [Vocapage] = []
            for pageNum in 1...totalPages {
                let startIndex = (pageNum - 1) * pageSize
                let endIndex = min(startIndex + pageSize, allFlashcards.count)
                
                // This slice contains the cards for the current page.
                let pageCards = Array(allFlashcards[startIndex..<endIndex])
                
                // Create the page and assign its `flashcards` property.
                // This is the step that fixes the bug.
                var newPage = Vocapage(id: pageNum, title: "Page \(pageNum)", order: pageNum)
                newPage.flashcards = pageCards
                pages.append(newPage)
            }
            
            // 5. Create the final Vocabook object with the fully-formed pages.
            let book = Vocabook(id: 1, title: "All Flashcards", vocapages: pages)
            
            // 6. Update the UI. Your views will now receive the correct data.
            self.vocabook = book
            self.loadCycle += 1 // Trigger your autoscroll

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
