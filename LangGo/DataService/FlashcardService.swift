//
//  FlashcardService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/23.
//


// LangGo/DataService/FlashcardService.swift

import Foundation
import os

extension Notification.Name {
    /// Posted when flashcard data has been mutated (e.g., after a review or deletion)
    /// and views holding flashcard data should refresh themselves from the service.
    static let flashcardsDidChange = Notification.Name("com.langGo.swift.flashcardsDidChange")
}

class FlashcardService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardService")
    private let cacheService = CacheService.shared
    private let networkManager = NetworkManager.shared
    
    private var isAllMyFlashcardsCacheStale = true
    private var isReviewFlashcardsCacheStale = true
    
    private let allMyFlashcardsCacheKey = "allMyFlashcards"
    private let reviewFlashcardsCacheKey = "allMyReviewFlashcards"
    private let flashcardStatisticsCacheKey = "flashcardStatistics"

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }
    
    func fetchFlashcardStatistics() async throws -> StrapiStatistics {
        if !isRefreshModeEnabled, let cachedStats = cacheService.load(type: StrapiStatistics.self, from: flashcardStatisticsCacheKey) {
            logger.debug("✅ Returning flashcard statistics from cache.")
            return cachedStats
        }

        logger.debug("Fetching flashcard statistics from network.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else { throw URLError(.badURL) }

        let resp: StrapiStatisticsResponse = try await networkManager.fetchDirect(from: url)
        let stats = resp.data

        cacheService.save(stats, key: flashcardStatisticsCacheKey)
        logger.debug("💾 Saved fetched statistics to cache.")
        return stats
    }

    func fetchAllReviewFlashcards() async throws -> [Flashcard] {
        if !isReviewFlashcardsCacheStale, let cached = cacheService.load(type: [Flashcard].self, from: reviewFlashcardsCacheKey) {
            logger.debug("✅ Review cache is FRESH. Returning \(cached.count) cards.")
            return cached
        }

        logger.debug("➡️ Review cache is STALE. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await fetchReviewFlashcardsPage(page: currentPage, pageSize: 100)
            if !cards.isEmpty { allCards.append(contentsOf: cards) }
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
            currentPage += 1
        }
        
        logger.debug("✅ Fetched \(allCards.count) review flashcards.")
        cacheService.save(allCards, key: reviewFlashcardsCacheKey)
        isReviewFlashcardsCacheStale = false
        logger.debug("✅ Review cache updated. Flag set to FALSE.")
        return allCards
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Flashcard {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await networkManager.post(to: url, body: body)

        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "FlashcardServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response missing data."])
        }

        invalidateAllFlashcardCaches()
        return transformStrapiCard(updatedStrapiCard)
    }
    
    func deleteFlashcard(cardId: Int) async throws {
        logger.debug("➡️ Attempting to delete flashcard with id: \(cardId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/remove") else {
            throw URLError(.badURL)
        }

        // The endpoint uses POST and doesn't require a request body.
        // We define a placeholder for the generic `post` method's body parameter.
        struct EmptyBody: Encodable {}

        // We define a struct to decode the success response from the server,
        // confirming the deletion.
        struct DeleteResponse: Decodable {
            struct Data: Decodable {
                struct Attributes: Decodable {
                    let message: String
                }
                let attributes: Attributes
            }
            let data: Data
        }

        let _: DeleteResponse = try await networkManager.post(to: url, body: EmptyBody())

        invalidateAllFlashcardCaches()

        logger.debug("✅ Successfully deleted flashcard with id: \(cardId) and invalidated caches.")
    }

    func fetchAllMyFlashcards() async throws -> [Flashcard] {
        return try await getOrFetchAllMyFlashcards()
    }
    
    func fetchFlashcards(page: Int, pageSize: Int, dueOnly: Bool = false) async throws -> ([Flashcard], StrapiPagination?) {
        if dueOnly {
            return try await fetchReviewFlashcardsPage(page: page, pageSize: pageSize)
        }
        let allFlashcards = try await getOrFetchAllMyFlashcards()
        
        let totalItems = allFlashcards.count
        let totalPages = (totalItems + pageSize - 1) / pageSize
        
        guard page > 0, page <= totalPages || totalItems == 0 else {
            return ([], StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
        }
        
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, totalItems)
        let pageItems = Array(allFlashcards[startIndex..<endIndex])
        
        return (pageItems, StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
    }

    func invalidateAllFlashcardCaches() {
        cacheService.delete(key: allMyFlashcardsCacheKey)
        cacheService.delete(key: reviewFlashcardsCacheKey)
        cacheService.delete(key: flashcardStatisticsCacheKey)
        
        isAllMyFlashcardsCacheStale = true
        isReviewFlashcardsCacheStale = true
        
        // MODIFIED: After invalidating the cache, post the notification on the main
        // thread. This tells any listening part of the app to re-fetch its data.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        }
        
        logger.debug("✏️ SUCCESS: All flashcard caches invalidated. Stale flags set to TRUE.")
    }
    
    private func getOrFetchAllMyFlashcards() async throws -> [Flashcard] {
        if !isAllMyFlashcardsCacheStale, let cached = cacheService.load(type: [Flashcard].self, from: allMyFlashcardsCacheKey) {
            logger.debug("✅ Returning all 'my flashcards' from cache.")
            return cached
        }

        logger.debug("Cache for 'my flashcards' is stale. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await fetchFlashcardsPageFromNetwork(page: currentPage, pageSize: 100)
            if !cards.isEmpty { allCards.append(contentsOf: cards) }
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
            currentPage += 1
        }
        
        cacheService.save(allCards, key: allMyFlashcardsCacheKey)
        isAllMyFlashcardsCacheStale = false
        logger.debug("💾 Saved all 'my flashcards' to cache.")
        return allCards
    }

    private func fetchReviewFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/review-flashcards") else { throw URLError(.badURL) }
        urlComponents.queryItems = [
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)"),
            URLQueryItem(name: "populate[word_definition][populate]", value: "word,partOfSpeech"),
            URLQueryItem(name: "locale", value: "all")
        ]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiFlashcard> = try await networkManager.fetchDirect(from: url)
        return ((response.data ?? []).map(transformStrapiCard), response.meta?.pagination)
    }
    
    private func fetchFlashcardsPageFromNetwork(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/flashcards/mine") else { throw URLError(.badURL) }
        urlComponents.queryItems = [
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)"),
            URLQueryItem(name: "populate[word_definition][populate]", value: "word,partOfSpeech"),
            URLQueryItem(name: "locale", value: "all")
        ]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiFlashcard> = try await networkManager.fetchDirect(from: url)
        return ((response.data ?? []).map(transformStrapiCard), response.meta?.pagination)
    }

    private func transformStrapiCard(_ strapiCard: StrapiFlashcard) -> Flashcard {
        let attributes = strapiCard.attributes
        return Flashcard(
            id: strapiCard.id,
            wordDefinition: attributes.wordDefinition?.data,
            lastReviewedAt: attributes.lastReviewedAt,
            correctStreak: attributes.correctStreak ?? 0,
            wrongStreak: attributes.wrongStreak ?? 0,
            isRemembered: attributes.isRemembered,
            reviewTire: attributes.reviewTire?.data?.attributes.tier
        )
    }
}
