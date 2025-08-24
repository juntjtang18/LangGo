// LangGo/Vocabook/VocapageLoader.swift
import SwiftUI
import os

// MARK: - Vocapage Loader
// This ObservableObject class now handles loading and caching Vocapage data from the network.
@MainActor
class VocapageLoader: ObservableObject {
    // The service is now fetched directly from the DataServices singleton.
    private let flashcardService = DataServices.shared.flashcardService
    private let settingsService  = DataServices.shared.settingsService
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageLoader")

    // State properties to hold the data and loading status for each page
    @Published var vocapages: [Int: Vocapage] = [:]
    @Published var loadingStatus: [Int: Bool] = [:]
    @Published var errorMessages: [Int: String] = [:]

    // The initializer is now clean and parameter-less.
    init() {}

    func loadPage(withId vocapageId: Int, dueWordsOnly: Bool = false) async {
        // Don't re-load if already loading or if the page's flashcards are already loaded.
        if loadingStatus[vocapageId] == true || (vocapages[vocapageId]?.flashcards != nil && !dueWordsOnly) {
             return
        }
        
        logger.debug("VocapageLoader::loadPage(\(vocapageId), dueWordsOnly: \(dueWordsOnly))")
        loadingStatus[vocapageId] = true
        errorMessages[vocapageId] = nil

        do {
            let vbSetting = try await settingsService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            let (fetchedFlashcards, _) = try await flashcardService.fetchFlashcards(page: vocapageId, pageSize: pageSize, dueOnly: dueWordsOnly)
            
            var page = Vocapage(id: vocapageId, title: "Page \(vocapageId)", order: vocapageId)
            page.flashcards = fetchedFlashcards
            
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }

        loadingStatus[vocapageId] = false
    }
}
