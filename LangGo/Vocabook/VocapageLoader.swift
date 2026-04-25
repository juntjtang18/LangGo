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
    
    @Published var vocapagesAll: [String: Vocapage] = [:]
    @Published var vocapagesDue: [String: Vocapage] = [:]
    @Published var loadingAll: Set<String> = []
    @Published var loadingDue: Set<String> = []
    @Published var errorAll: [String: String] = [:]
    @Published var errorDue: [String: String] = [:]

    // The initializer is now clean and parameter-less.
    init() {}

    func loadPage(withId vocapageId: Int, dueWordsOnly: Bool = false, reviewTier: String? = nil) async {
        let pageKey = cacheKey(id: vocapageId, reviewTier: reviewTier)
        // Choose the right buckets based on filter
        var store: [String: Vocapage]
        var loadingSet: Set<String>
        var errors: [String: String]
        
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
        if loadingSet.contains(pageKey) || (store[pageKey]?.flashcards != nil) { return }

        logger.debug("VocapageLoader::loadPage(\(vocapageId), dueWordsOnly: \(dueWordsOnly), reviewTier: \(reviewTier ?? "nil", privacy: .public))")
        loadingSet.insert(pageKey)
        errors[pageKey] = nil

        do {
            let vbSetting = try await settingsService.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            
            let (fetchedFlashcards, _) = try await flashcardService.fetchFlashcards(
                page: vocapageId,
                pageSize: pageSize,
                dueOnly: dueWordsOnly,
                reviewTier: reviewTier
            )
            
            var page = Vocapage(id: vocapageId, title: "Page \(vocapageId)", order: vocapageId)
            page.flashcards = fetchedFlashcards
            
            store[pageKey] = page
            
        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errors[pageKey] = error.localizedDescription
        }

        loadingSet.remove(pageKey)

        // Write back the mutated locals
        if dueWordsOnly {
            vocapagesDue = store; loadingDue = loadingSet; errorDue = errors
        } else {
            vocapagesAll = store; loadingAll = loadingSet; errorAll = errors
        }
     }
    
    // Accessor to read the correct variant without exposing internals
    func page(id: Int, dueOnly: Bool, reviewTier: String? = nil) -> Vocapage? {
        let pageKey = cacheKey(id: id, reviewTier: reviewTier)
        return dueOnly ? vocapagesDue[pageKey] : vocapagesAll[pageKey]
    }
    
    // 👇 ADD THIS FUNCTION
    /// Removes a page from the cache and then re-triggers a load from the network.
    func forceReloadPage(withId id: Int, dueWordsOnly: Bool, reviewTier: String? = nil) async {
        let pageKey = cacheKey(id: id, reviewTier: reviewTier)
        if dueWordsOnly {
            vocapagesDue.removeValue(forKey: pageKey)
        } else {
            vocapagesAll.removeValue(forKey: pageKey)
        }
        await loadPage(withId: id, dueWordsOnly: dueWordsOnly, reviewTier: reviewTier)
    }

    private func cacheKey(id: Int, reviewTier: String?) -> String {
        if let reviewTier, !reviewTier.isEmpty {
            return "tier.\(reviewTier).page.\(id)"
        }
        return "page.\(id)"
    }
}
