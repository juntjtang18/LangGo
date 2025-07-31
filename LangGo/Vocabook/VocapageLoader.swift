import SwiftUI
import os

// MARK: - Vocapage Loader
// This ObservableObject class now handles loading and caching Vocapage data from the network.
@MainActor
class VocapageLoader: ObservableObject {
    private let strapiService: StrapiService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageLoader")

    // State properties to hold the data and loading status for each page
    @Published var vocapages: [Int: Vocapage] = [:]
    @Published var loadingStatus: [Int: Bool] = [:]
    @Published var errorMessages: [Int: String] = [:]

    // MODIFIED: The initializer no longer requires a ModelContext.
    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }

    func loadPage(withId vocapageId: Int) async {
        // Don't re-load if already loading or if the page's flashcards are already loaded.
        if loadingStatus[vocapageId] == true || (vocapages[vocapageId]?.flashcards != nil) {
            return
        }
        
        logger.debug("VocapageLoader::loadPage(\(vocapageId))")
        loadingStatus[vocapageId] = true
        errorMessages[vocapageId] = nil

        do {
            // 1. Fetch the settings to determine the page size.
            let vbSetting = try await strapiService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            // 2. Fetch the flashcards for the specific page number from the server.
            let (fetchedFlashcards, _) = try await strapiService.fetchFlashcards(page: vocapageId, pageSize: pageSize)
            
            // 3. Create a new Vocapage object containing the fetched flashcards.
            var page = Vocapage(id: vocapageId, title: "Page \(vocapageId)", order: vocapageId)
            page.flashcards = fetchedFlashcards
            
            // 4. Store the fully loaded page in our local cache.
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }

        loadingStatus[vocapageId] = false
    }
}
