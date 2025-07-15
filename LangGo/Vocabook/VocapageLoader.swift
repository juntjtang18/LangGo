import SwiftUI
import SwiftData
import os

// MARK: - Vocapage Loader
// This ObservableObject class handles all data loading and caching for the Vocapage feature.
@MainActor
class VocapageLoader: ObservableObject {
    var modelContext: ModelContext
    let strapiService: StrapiService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageLoader")

    // State properties to hold the data and loading status for each page
    @Published var vocapages: [Int: Vocapage] = [:]
    @Published var loadingStatus: [Int: Bool] = [:]
    @Published var errorMessages: [Int: String] = [:]

    init(modelContext: ModelContext, strapiService: StrapiService) {
        self.modelContext = modelContext
        self.strapiService = strapiService
    }

    func loadPage(withId vocapageId: Int) async {
        // Don't re-load if already loading or loaded
        if loadingStatus[vocapageId] == true || vocapages[vocapageId] != nil {
            return
        }
        logger.debug("VocapageLoder::loadPage(\(vocapageId))")
        loadingStatus[vocapageId] = true
        errorMessages[vocapageId] = nil

        do {
            // 1. Fetch the Vocapage object from SwiftData
            let fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == vocapageId })
            guard let page = (try modelContext.fetch(fetchDescriptor)).first else {
                throw NSError(domain: "VocapageLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find vocapage with ID \(vocapageId)."])
            }

            // 2. Fetch the flashcards for this page from the server
            let vbSetting = try await strapiService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            let (syncedFlashcards, _) = try await strapiService.fetchFlashcards(page: page.order, pageSize: pageSize)
            
            // 3. Link flashcards to the vocapage object and save
            page.flashcards = syncedFlashcards
            try modelContext.save()
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }

        loadingStatus[vocapageId] = false
    }
}
