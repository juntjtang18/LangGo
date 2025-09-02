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
    
    @Published var vocapagesAll: [Int: Vocapage] = [:]
    @Published var vocapagesDue: [Int: Vocapage] = [:]
    @Published var loadingAll: Set<Int> = []
    @Published var loadingDue: Set<Int> = []
    @Published var errorAll: [Int: String] = [:]
    @Published var errorDue: [Int: String] = [:]

    // The initializer is now clean and parameter-less.
    init() {}

    func loadPage(withId vocapageId: Int, dueWordsOnly: Bool = false) async {
        // Choose the right buckets based on filter
        var store: [Int: Vocapage]
        var loadingSet: Set<Int>
        var errors: [Int: String]
        
        if dueWordsOnly {
            store = vocapagesDue
            loadingSet = loadingDue
            errors = errorDue
        } else {
            store = vocapagesAll
            loadingSet = loadingAll
            errors = errorAll
        }

        // Already loading or already cached? bail.
        if loadingSet.contains(vocapageId) || (store[vocapageId]?.flashcards != nil) { return }

        logger.debug("VocapageLoader::loadPage(\(vocapageId), dueWordsOnly: \(dueWordsOnly))")
        loadingSet.insert(vocapageId)
        errors[vocapageId] = nil

        do {
            let vbSetting = try await settingsService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            let (fetchedFlashcards, _) = try await flashcardService.fetchFlashcards(page: vocapageId, pageSize: pageSize, dueOnly: dueWordsOnly)
            
            var page = Vocapage(id: vocapageId, title: "Page \(vocapageId)", order: vocapageId)
            page.flashcards = fetchedFlashcards
            
            store[vocapageId] = page
            
        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errors[vocapageId] = error.localizedDescription
        }

        loadingSet.remove(vocapageId)

        // Write back the mutated locals
        if dueWordsOnly {
            vocapagesDue = store; loadingDue = loadingSet; errorDue = errors
        } else {
            vocapagesAll = store; loadingAll = loadingSet; errorAll = errors
        }
     }
    
    // Accessor to read the correct variant without exposing internals
    func page(id: Int, dueOnly: Bool) -> Vocapage? {
        dueOnly ? vocapagesDue[id] : vocapagesAll[id]
    }
    
    // 👇 ADD THIS FUNCTION
    /// Removes a page from the cache and then re-triggers a load from the network.
    func forceReloadPage(withId id: Int, dueWordsOnly: Bool) async {
        if dueWordsOnly {
            vocapagesDue.removeValue(forKey: id)
        } else {
            vocapagesAll.removeValue(forKey: id)
        }
        await loadPage(withId: id, dueWordsOnly: dueWordsOnly)
    }
}
