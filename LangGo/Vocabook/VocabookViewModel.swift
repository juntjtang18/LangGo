// LangGo/Vocabook/VocabookViewModel.swift
import Foundation
import CoreData // Use CoreData instead of SwiftData
import os
import SwiftUI

// This is no longer a @Model class, but an ObservableObject
class VocabookViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookViewModel")
    // Use NSManagedObjectContext for Core Data
    private let managedObjectContext: NSManagedObjectContext
    private let strapiService: StrapiService
    
    // Use @Published for properties that should trigger UI updates
    @Published var loadCycle: Int = 0
    @Published var vocabook: Vocabook?
    @Published var isLoadingVocabooks = false
    @Published var expandedVocabooks: Set<Int> = []
    @Published var totalFlashcards: Int = 0
    @Published var totalPages: Int = 1
    
    init(managedObjectContext: NSManagedObjectContext, strapiService: StrapiService) {
        self.managedObjectContext = managedObjectContext
        self.strapiService = strapiService
    }
    
    @MainActor
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch settings and pagination info
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

            // 2. Find or create the main Vocabook using NSFetchRequest
            let bookId = 1
            let fetchRequest = NSFetchRequest<Vocabook>(entityName: "Vocabook")
            fetchRequest.predicate = NSPredicate(format: "id == %ld", bookId)
            fetchRequest.fetchLimit = 1
            
            let book: Vocabook
            if let existingBook = try managedObjectContext.fetch(fetchRequest).first {
                book = existingBook
            } else {
                book = Vocabook(context: managedObjectContext)
                book.id = Int64(bookId)
                book.title = "All Flashcards"
            }

            // 3. Sync Vocapages
            let existingPages = book.vocapages?.allObjects as? [Vocapage] ?? []
            let existingPageIds = Set(existingPages.map { Int($0.id) })
            let pageNumbersToKeep = Set(1...totalPages)

            // Delete stale pages
            let pagesToDelete = existingPages.filter { !pageNumbersToKeep.contains(Int($0.id)) }
            for page in pagesToDelete {
                managedObjectContext.delete(page)
            }

            // Add new pages
            let newPageNumbers = pageNumbersToKeep.subtracting(existingPageIds)
            for pageNum in newPageNumbers {
                let newPage = Vocapage(context: managedObjectContext)
                newPage.id = Int64(pageNum)
                newPage.title = "Page \(pageNum)"
                newPage.order = Int32(pageNum)
                newPage.vocabook = book
            }
            
            // 4. Save changes and update properties
            if managedObjectContext.hasChanges {
                try managedObjectContext.save()
            }
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
