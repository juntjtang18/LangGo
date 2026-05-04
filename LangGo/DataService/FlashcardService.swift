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
    @Published private(set) var reviewFlashcards: [Flashcard] = []
    @Published private(set) var flashcardStatistics: StrapiStatistics?
    @Published private(set) var flashcardStatChanged: Int = 0
    @Published private(set) var nextFlashcardStatisticsFetchAt: Date?
    @Published private(set) var isLoadingFlashcards = false
    @Published private(set) var flashcardsErrorMessage: String?
    @Published private(set) var isLoadingStatistics = false
    @Published private(set) var statisticsErrorMessage: String?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardService")
    private let cacheService = CacheService.shared
    private let networkManager = NetworkManager.shared
    private var allMyFlashcardsFullLoadTask: Task<Void, Never>?
    private var flashcardStatisticsTask: Task<StrapiStatistics, Error>?
    private var flashcardMutationVersion: Int = 0

    private var currentUserId: Int? {
        let userId = UserDefaults.standard.integer(forKey: "userId")
        return userId > 0 ? userId : nil
    }
    private let reviewFlashcardStateLock = NSLock()
    private let statisticsStateLock = NSLock()

    private func withReviewFlashcardStateLock<T>(_ work: () throws -> T) rethrows -> T {
        reviewFlashcardStateLock.lock()
        defer { reviewFlashcardStateLock.unlock() }
        return try work()
    }

    private func withStatisticsStateLock<T>(_ work: () throws -> T) rethrows -> T {
        statisticsStateLock.lock()
        defer { statisticsStateLock.unlock() }
        return try work()
    }

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    func loadStatisticsIfNeeded() async {
        await setStatisticsErrorMessage(nil)
        _ = try? await fetchFlashcardStatistics()
    }

    func refreshStatistics(forceRefresh: Bool = false) async {
        _ = try? await fetchFlashcardStatistics(forceRefresh: forceRefresh)
    }

    func refreshFlashcardStat() async {
        _ = try? await fetchFlashcardStatistics(forceRefresh: true)
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
            if forceRefresh {
                let stats = try await fetchFlashcardStatisticsFromNetworkDeduped()
                await setStatisticsLoading(false)
                return stats
            }

            let stats = try await fetchFlashcardStatisticsFromNetworkDeduped()
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
        logger.debug("Fetching all review flashcards from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await fetchReviewFlashcardsPageFromNetwork(page: currentPage, pageSize: 100)
            if !cards.isEmpty {
                allCards.append(contentsOf: cards)
            }
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
            currentPage += 1
        }

        await publishReviewFlashcards(allCards)
        return allCards
    }

    func fetchFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        try await fetchFlashcardsPageFromNetwork(page: page, pageSize: pageSize)
    }

    func fetchFlashcardsPage(page: Int, pageSize: Int, reviewTier: String) async throws -> ([Flashcard], StrapiPagination?) {
        try await fetchFlashcardsPageFromNetwork(page: page, pageSize: pageSize, reviewTier: reviewTier)
    }

    func fetchRecentFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        try await fetchFlashcardsPageFromNetwork(page: page, pageSize: pageSize, sortByMostRecentCreation: true)
    }

    func fetchDueFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        try await fetchReviewFlashcardsPageFromNetwork(page: page, pageSize: pageSize)
    }

    func fetchAvailableReviewFlashcards(pageSize: Int = 100) async throws -> [Flashcard] {
        _ = pageSize
        return try await fetchAllReviewFlashcards()
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Flashcard {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await networkManager.post(to: url, body: body)

        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "FlashcardServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response missing data."])
        }

        let updatedCard = transformStrapiCard(updatedStrapiCard)
        await patchInMemoryStateAfterFlashcardReview(updatedCard)
        markFlashcardDataMutated()
        await publishFlashcardStatChanged()
        return updatedCard
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

        markFlashcardDataMutated()
        invalidateAllFlashcardCaches()

        logger.debug("✅ Successfully deleted flashcard with id: \(cardId) and invalidated caches.")
    }
    private func patchInMemoryStateAfterFlashcardReview(_ updatedCard: Flashcard) async {
        await MainActor.run {
            self.flashcards = self.flashcards.map { $0.id == updatedCard.id ? updatedCard : $0 }
            self.reviewFlashcards.removeAll { $0.id == updatedCard.id }
        }

        logger.debug("✅ Patched in-memory review state after review for card id: \(updatedCard.id).")
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
        
        return sliceFlashcards(allFlashcards, page: page, pageSize: pageSize)
    }

    func invalidateAllFlashcardCaches() {
        FlashcardCache.invalidateAfterFlashcardWrite(using: cacheService)
        FlashcardCache.invalidateLegacyGlobalCaches(using: cacheService)
        withReviewFlashcardStateLock {
            allMyFlashcardsFullLoadTask?.cancel()
            allMyFlashcardsFullLoadTask = nil
        }
        withStatisticsStateLock {
            flashcardStatisticsTask?.cancel()
            flashcardStatisticsTask = nil
        }
        Task {
            await publishReviewFlashcards([])
        }
        notifyFlashcardsDidChange()
        
        logger.debug("✏️ SUCCESS: All flashcard caches invalidated.")
    }
    /// Clears only runtime state owned by this service when the active user changes.
    /// Persistent caches are user-scoped in FlashcardCache, so they do not need to be deleted.
    func resetUserScopedRuntimeState() {
        withReviewFlashcardStateLock {
            allMyFlashcardsFullLoadTask?.cancel()
            allMyFlashcardsFullLoadTask = nil
        }

        Task { @MainActor in
            self.flashcards = []
            self.reviewFlashcards = []
            self.flashcardStatistics = nil
            self.nextFlashcardStatisticsFetchAt = nil
            self.isLoadingFlashcards = false
            self.isLoadingStatistics = false
            self.flashcardsErrorMessage = nil
            self.statisticsErrorMessage = nil
        }
    }

    func notifyFlashcardsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        }
    }

    func handleFlashcardAdded(_ flashcard: Flashcard) async {
        await MainActor.run {
            if let existingIndex = self.flashcards.firstIndex(where: { $0.id == flashcard.id }) {
                self.flashcards[existingIndex] = flashcard
            } else {
                self.flashcards.insert(flashcard, at: 0)
            }
        }
        markFlashcardDataMutated()
        await publishFlashcardStatChanged()
    }
    
    private func getOrFetchAllMyFlashcards() async throws -> [Flashcard] {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            logger.debug("✅ Returning all 'my flashcards' from cache.")
            return cached
        }

        return try await fetchAllMyFlashcardsFromNetworkAndCommit(userId: currentUserId)
    }

    /// Fast Book Mode page loading that uses the shared FlashcardService cache.
    ///
    /// For normal all-word pages, it does not wait for the full all-cards cache
    /// to rebuild. It returns the requested backend page immediately and starts
    /// one shared background full-load to refresh the user-scoped cache.
    ///
    /// Due/tier/recent modes keep the existing filtered fetch behavior.
    func fetchVocapageFlashcards(
        page: Int,
        pageSize: Int,
        dueOnly: Bool = false,
        reviewTier: String? = nil,
        recentlyAddedLimit: Int = 0
    ) async throws -> ([Flashcard], StrapiPagination?) {
        if dueOnly || recentlyAddedLimit > 0 || (reviewTier?.isEmpty == false) {
            return try await fetchFlashcards(
                page: page,
                pageSize: pageSize,
                dueOnly: dueOnly,
                reviewTier: reviewTier,
                recentlyAddedLimit: recentlyAddedLimit
            )
        }

        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            logger.debug("✅ Returning vocapage \(page) from all-cards cache.")
            return sliceFlashcards(cached, page: page, pageSize: pageSize)
        }

        logger.debug("All-cards cache is STALE for Book Mode. Fetching vocapage \(page) from network and starting/reusing background full-load.")
        ensureAllMyFlashcardsFullyLoaded()
        return try await fetchFlashcardsPageFromNetwork(page: page, pageSize: pageSize)
    }

    func ensureAllMyFlashcardsFullyLoaded() {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadAllMyFlashcards(using: cacheService) {
            Task { await publishFlashcards(cached) }
            return
        }

        let loadingUserId = currentUserId
        let didStartTask = withReviewFlashcardStateLock { () -> Bool in
            guard allMyFlashcardsFullLoadTask == nil else { return false }
            allMyFlashcardsFullLoadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.fetchAllMyFlashcardsFromNetworkAndCommit(userId: loadingUserId)
                } catch is CancellationError {
                    self.logger.debug("All-cards background full-load cancelled because active user changed.")
                } catch {
                    self.logger.error("Failed background-loading all flashcards: \(error.localizedDescription, privacy: .public)")
                }
                self.withReviewFlashcardStateLock {
                    self.allMyFlashcardsFullLoadTask = nil
                }
            }
            return true
        }

        if !didStartTask {
            logger.debug("All-cards full-load task already running. Reusing existing task.")
        }
    }

    private func fetchAllMyFlashcardsFromNetworkAndCommit(userId: Int?) async throws -> [Flashcard] {
        guard isCurrentUser(userId) else { throw CancellationError() }

        logger.debug("Cache for 'my flashcards' is stale. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            guard isCurrentUser(userId) else { throw CancellationError() }
            let (cards, pagination) = try await fetchFlashcardsPageFromNetwork(page: currentPage, pageSize: 100)
            if !cards.isEmpty { allCards.append(contentsOf: cards) }
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
            currentPage += 1
        }

        guard isCurrentUser(userId) else { throw CancellationError() }
        FlashcardCache.storeAllMyFlashcards(allCards, using: cacheService)
        await publishFlashcards(allCards)
        logger.debug("💾 Saved all 'my flashcards' to cache.")
        return allCards
    }

    private func sliceFlashcards(_ cards: [Flashcard], page: Int, pageSize: Int) -> ([Flashcard], StrapiPagination?) {
        let totalItems = cards.count
        let totalPages = (totalItems + pageSize - 1) / pageSize

        guard page > 0, page <= totalPages || totalItems == 0 else {
            return ([], StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
        }

        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, totalItems)
        let pageItems = startIndex < endIndex ? Array(cards[startIndex..<endIndex]) : []
        return (pageItems, StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
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
        try await fetchReviewFlashcardsPageFromNetwork(page: page, pageSize: pageSize)
    }

    private func fetchReviewFlashcardsPageFromNetwork(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
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

    private func isCurrentUser(_ userId: Int?) -> Bool {
        currentUserId == userId
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

    private func publishReviewFlashcards(_ cards: [Flashcard]) async {
        await MainActor.run {
            self.reviewFlashcards = cards
        }
    }

    private func publishFlashcards(_ cards: [Flashcard]) async {
        await MainActor.run {
            self.flashcards = cards
        }
    }

    private func publishStatistics(_ statistics: StrapiStatistics?) async {
        await MainActor.run {
            self.flashcardStatistics = statistics
            self.nextFlashcardStatisticsFetchAt = nil
        }
    }

    private func publishFlashcardStatChanged() async {
        await MainActor.run {
            self.flashcardStatChanged += 1
        }
        logger.debug("flashcardStatChanged published token=\(self.flashcardStatChanged, privacy: .public)")
        notifyFlashcardsDidChange()
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

    private func fetchFlashcardStatisticsFromNetworkDeduped() async throws -> StrapiStatistics {
        if let existingTask = withStatisticsStateLock({ flashcardStatisticsTask }) {
            logger.debug("Joining existing flashcard statistics network task.")
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> StrapiStatistics in
            guard let self else { throw CancellationError() }
            return try await self.fetchFlashcardStatisticsFromNetwork()
        }

        let taskState = withStatisticsStateLock { () -> (task: Task<StrapiStatistics, Error>, didStore: Bool) in
            if let existingTask = flashcardStatisticsTask {
                return (existingTask, false)
            }

            flashcardStatisticsTask = task
            return (task, true)
        }

        defer {
            if taskState.didStore {
                withStatisticsStateLock {
                    flashcardStatisticsTask = nil
                }
            }
        }

        return try await taskState.task.value
    }

    private func fetchFlashcardStatisticsFromNetwork() async throws -> StrapiStatistics {
        while true {
            let requestedVersion = currentFlashcardMutationVersion()
            logger.debug("Fetching flashcard statistics from network.")
            guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else {
                throw URLError(.badURL)
            }

            let resp: StrapiStatisticsResponse = try await networkManager.fetchDirect(from: url)
            let stats = resp.data

            if requestedVersion != currentFlashcardMutationVersion() {
                logger.debug("Discarding stale flashcard statistics response; flashcard data changed during fetch.")
                continue
            }

            await publishStatistics(stats)
            return stats
        }
    }

    private func markFlashcardDataMutated() {
        withStatisticsStateLock {
            flashcardMutationVersion += 1
        }
    }

    private func currentFlashcardMutationVersion() -> Int {
        withStatisticsStateLock { flashcardMutationVersion }
    }

}
