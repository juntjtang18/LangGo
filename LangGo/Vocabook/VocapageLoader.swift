import Foundation
import CoreData // Use CoreData instead of SwiftData
import os

// MARK: - Vocapage Loader
@MainActor
class VocapageLoader: ObservableObject {
    // 1. Use NSManagedObjectContext for Core Data
    private let managedObjectContext: NSManagedObjectContext
    let strapiService: StrapiService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageLoader")

    // State properties remain the same
    @Published var vocapages: [Int: Vocapage] = [:]
    @Published var loadingStatus: [Int: Bool] = [:]
    @Published var errorMessages: [Int: String] = [:]

    // 2. The initializer now accepts the Core Data context
    init(managedObjectContext: NSManagedObjectContext, strapiService: StrapiService) {
        self.managedObjectContext = managedObjectContext
        self.strapiService = strapiService
    }

    func loadPage(withId vocapageId: Int) async {
        if loadingStatus[vocapageId] == true || vocapages[vocapageId] != nil {
            return
        }
        logger.debug("VocapageLoder::loadPage(\(vocapageId))")
        loadingStatus[vocapageId] = true
        errorMessages[vocapageId] = nil

        defer { loadingStatus[vocapageId] = false }

        do {
            // 3. Fetch the Vocapage using NSFetchRequest and NSPredicate
            let fetchRequest = NSFetchRequest<Vocapage>(entityName: "Vocapage")
            fetchRequest.predicate = NSPredicate(format: "id == %ld", vocapageId)
            fetchRequest.fetchLimit = 1
            
            guard let page = try managedObjectContext.fetch(fetchRequest).first else {
                throw NSError(domain: "VocapageLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find vocapage with ID \(vocapageId)."])
            }

            // 4. Fetch flashcards for the page from the server (this logic is the same)
            let vbSetting = try await strapiService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            let (syncedFlashcards, _) = try await strapiService.fetchFlashcards(page: Int(page.order), pageSize: pageSize) // Cast page.order to Int
            
            // 5. Link flashcards using NSSet and save the context
            page.flashcards = NSSet(array: syncedFlashcards)
            
            if managedObjectContext.hasChanges {
                try managedObjectContext.save()
            }
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }
    }
}
