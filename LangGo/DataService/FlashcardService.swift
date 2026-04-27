//
//  FlashcardService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/23.
//


// LangGo/DataService/FlashcardService.swift

import Combine
import Foundation
import os

extension Notification.Name {
    /// Posted when flashcard data has been mutated (e.g., after a review or deletion)
    /// and views holding flashcard data should refresh themselves from the service.
    static let flashcardsDidChange = Notification.Name("com.langGo.swift.flashcardsDidChange")
}

final class FlashcardService: ObservableObject {
    @Published private(set) var flashcards: [Flashcard] = []
    @Published private(set) var flashcardStatistics: StrapiStatistics?
    @Published private(set) var nextFlashcardStatisticsFetchAt: Date?
    @Published private(set) var isLoadingFlashcards = false
    @Published private(set) var flashcardsErrorMessage: String?
    @Published private(set) var isLoadingStatistics = false
    @Published private(set) var statisticsErrorMessage: String?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardService")
    private let cacheService = CacheService.shared
    private let networkManager = NetworkManager.shared
    private let dateFormatter = ISO8601DateFormatter()
    private let flashcardStatisticsMinimumFetchInterval: TimeInterval = 2
    private var lastFlashcardStatisticsNetworkFetchAt: Date?

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    func loadStatisticsIfNeeded() async {
        await setStatisticsErrorMessage(nil)

        if let cachedStats = FlashcardCache.loadStatistics(using: cacheService) {
            logger.debug("✅ Returning flashcard statistics from cache.")
            await publishStatistics(cachedStats)
            return
        }

        await refreshStatistics(forceRefresh: false)
    }

    func refreshStatistics(forceRefresh: Bool = false) async {
        _ = try? await fetchFlashcardStatistics(forceRefresh: forceRefresh)
    }

    func loadFlashcardsIfNeeded() async {
        await setFlashcardsErrorMessage(nil)

        if let cachedCards = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            logger.debug("✅ Returning all 'my flashcards' from cache.")
            await publishFlashcards(cachedCards)
            return
        }

        await refreshFlashcards()
    }

    func refreshFlashcards() async {
        _ = try? await fetchAllMyFlashcards()
    }

    func fetchFlashcardStatistics(forceRefresh: Bool = false) async throws -> StrapiStatistics {
        await setStatisticsLoading(true)
        await setStatisticsErrorMessage(nil)

        do {
            if !forceRefresh,
               !isRefreshModeEnabled,
               let lastFetch = lastFlashcardStatisticsNetworkFetchAt,
               Date().timeIntervalSince(lastFetch) < flashcardStatisticsMinimumFetchInterval,
               let cachedStats = FlashcardCache.loadStatistics(using: cacheService) {
                logger.debug("✅ Returning flashcard statistics from cache due to short repeat-fetch guard.")
                await publishStatistics(cachedStats)
                await setStatisticsLoading(false)
                return cachedStats
            }

            logger.debug("Fetching flashcard statistics from network.")
            guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else {
                throw URLError(.badURL)
            }

            let resp: StrapiStatisticsResponse = try await networkManager.fetchDirect(from: url)
            let stats = resp.data
            lastFlashcardStatisticsNetworkFetchAt = Date()

            FlashcardCache.storeStatistics(stats, using: cacheService)
            logger.debug("💾 Saved fetched statistics to cache.")
            await publishStatistics(stats)
            await setStatisticsLoading(false)
            return stats
        } catch {
            logger.error("Failed to fetch flashcard statistics: \(error.localizedDescription, privacy: .public)")
            await setStatisticsErrorMessage(error.localizedDescription)
            await setStatisticsLoading(false)
            throw error
        }
    }

    func fetchAllReviewFlashcards() async throws -> [Flashcard] {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadReviewFlashcards(using: cacheService) {
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
        FlashcardCache.storeReviewFlashcards(allCards, using: cacheService)
        logger.debug("✅ Review cache updated.")
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
        PointGroupCache.invalidateAll(using: cacheService)
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
        await setFlashcardsLoading(true)
        await setFlashcardsErrorMessage(nil)

        do {
            let cards = try await getOrFetchAllMyFlashcards()
            await publishFlashcards(cards)
            await setFlashcardsLoading(false)
            return cards
        } catch {
            logger.error("Failed to fetch all user flashcards: \(error.localizedDescription, privacy: .public)")
            await setFlashcardsErrorMessage(error.localizedDescription)
            await setFlashcardsLoading(false)
            throw error
        }
    }

    func fetchAllMyFlashcards(reviewTier: String) async throws -> [Flashcard] {
        return try await getOrFetchAllMyFlashcards(reviewTier: reviewTier)
    }

    func fetchRecentlyAddedFlashcards(limit: Int) async throws -> [Flashcard] {
        guard limit > 0 else { return [] }

        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadRecentFlashcards(limit: limit, using: cacheService) {
            logger.debug("✅ Returning recent flashcards from cache for limit \(limit).")
            return cached
        }

        if !isRefreshModeEnabled,
           let cachedAll = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            let recent = Array(sortByMostRecentCreation(cachedAll).prefix(limit))
            FlashcardCache.storeRecentFlashcards(recent, limit: limit, using: cacheService)
            logger.debug("✅ Derived recent flashcards from all-cards cache.")
            return recent
        }

        logger.debug("Fetching recent flashcards from network with limit \(limit).")
        let (cards, _) = try await fetchFlashcardsPageFromNetwork(page: 1, pageSize: limit, sortByMostRecentCreation: true)
        let recent = Array(sortByMostRecentCreation(cards).prefix(limit))
        FlashcardCache.storeRecentFlashcards(recent, limit: limit, using: cacheService)
        return recent
    }
    
    func fetchFlashcards(page: Int, pageSize: Int, dueOnly: Bool = false, reviewTier: String? = nil, recentlyAddedLimit: Int = 0) async throws -> ([Flashcard], StrapiPagination?) {
        if dueOnly {
            return try await fetchReviewFlashcardsPage(page: page, pageSize: pageSize)
        }
        let allFlashcards: [Flashcard]
        if recentlyAddedLimit > 0 {
            allFlashcards = try await fetchRecentlyAddedFlashcards(limit: recentlyAddedLimit)
        } else if let reviewTier, !reviewTier.isEmpty {
            allFlashcards = try await getOrFetchAllMyFlashcards(reviewTier: reviewTier)
        } else {
            allFlashcards = try await getOrFetchAllMyFlashcards()
        }
        
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
        FlashcardCache.invalidateAfterFlashcardWrite(using: cacheService)
        notifyFlashcardsDidChange()
        
        logger.debug("✏️ SUCCESS: All flashcard caches invalidated.")
    }

    func notifyFlashcardsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        }
    }
    
    private func getOrFetchAllMyFlashcards() async throws -> [Flashcard] {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
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
        
        FlashcardCache.storeAllMyFlashcards(allCards, using: cacheService)
        logger.debug("💾 Saved all 'my flashcards' to cache.")
        return allCards
    }

    private func getOrFetchAllMyFlashcards(reviewTier: String) async throws -> [Flashcard] {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadTierFlashcards(reviewTier: reviewTier, using: cacheService) {
            logger.debug("✅ Returning tier flashcards from cache for tier '\(reviewTier, privacy: .public)'.")
            return cached
        }

        if !isRefreshModeEnabled,
           let cachedAll = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            let filtered = cachedAll.filter { $0.reviewTire == reviewTier }
            FlashcardCache.storeTierFlashcards(filtered, reviewTier: reviewTier, using: cacheService)
            logger.debug("✅ Derived tier flashcards for '\(reviewTier, privacy: .public)' from all-cards cache.")
            return filtered
        }

        logger.debug("Cache for tier flashcards '\(reviewTier, privacy: .public)' is stale. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await fetchFlashcardsPageFromNetwork(page: currentPage, pageSize: 100, reviewTier: reviewTier)
            if !cards.isEmpty { allCards.append(contentsOf: cards) }
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
            currentPage += 1
        }

        FlashcardCache.storeTierFlashcards(allCards, reviewTier: reviewTier, using: cacheService)
        logger.debug("💾 Saved tier flashcards to cache for tier '\(reviewTier, privacy: .public)'.")
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
    
    private func fetchFlashcardsPageFromNetwork(
        page: Int,
        pageSize: Int,
        reviewTier: String? = nil,
        sortByMostRecentCreation: Bool = false
    ) async throws -> ([Flashcard], StrapiPagination?) {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/flashcards/mine") else { throw URLError(.badURL) }
        var queryItems = [
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)"),
            URLQueryItem(name: "populate[word_definition][populate]", value: "word,partOfSpeech"),
            URLQueryItem(name: "locale", value: "all")
        ]
        if let reviewTier, !reviewTier.isEmpty {
            queryItems.append(URLQueryItem(name: "tier", value: reviewTier))
        }
        if sortByMostRecentCreation {
            queryItems.append(URLQueryItem(name: "sort[0]", value: "createdAt:desc"))
        }
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiFlashcard> = try await networkManager.fetchDirect(from: url)
        return ((response.data ?? []).map(transformStrapiCard), response.meta?.pagination)
    }

    private func transformStrapiCard(_ strapiCard: StrapiFlashcard) -> Flashcard {
        let attributes = strapiCard.attributes
        return Flashcard(
            id: strapiCard.id,
            createdAt: attributes.createdAt,
            wordDefinition: attributes.wordDefinition?.data,
            lastReviewedAt: attributes.lastReviewedAt,
            correctStreak: attributes.correctStreak ?? 0,
            wrongStreak: attributes.wrongStreak ?? 0,
            isRemembered: attributes.isRemembered,
            reviewTire: attributes.reviewTire?.data?.attributes.tier
        )
    }

    private func sortByMostRecentCreation(_ cards: [Flashcard]) -> [Flashcard] {
        cards.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            default:
                return lhs.id > rhs.id
            }
        }
    }

    private func publishFlashcards(_ cards: [Flashcard]) async {
        await MainActor.run {
            self.flashcards = cards
        }
    }

    private func publishStatistics(_ statistics: StrapiStatistics?) async {
        let nextFetchAt = nextFlashcardStatisticsFetchDate(from: statistics)
        await MainActor.run {
            self.flashcardStatistics = statistics
            self.nextFlashcardStatisticsFetchAt = nextFetchAt
        }
    }

    private func setFlashcardsLoading(_ isLoading: Bool) async {
        await MainActor.run {
            self.isLoadingFlashcards = isLoading
        }
    }

    private func setFlashcardsErrorMessage(_ message: String?) async {
        await MainActor.run {
            self.flashcardsErrorMessage = message
        }
    }

    private func setStatisticsLoading(_ isLoading: Bool) async {
        await MainActor.run {
            self.isLoadingStatistics = isLoading
        }
    }

    private func setStatisticsErrorMessage(_ message: String?) async {
        await MainActor.run {
            self.statisticsErrorMessage = message
        }
    }

    private func nextFlashcardStatisticsFetchDate(from statistics: StrapiStatistics?) -> Date? {
        guard let statistics else {
            return nil
        }

        guard statistics.dueForReview == 0 else {
            return nil
        }

        guard let nextFetchAt = statistics.nextFetchAt else {
            return nil
        }

        return dateFormatter.date(from: nextFetchAt)
    }
}
