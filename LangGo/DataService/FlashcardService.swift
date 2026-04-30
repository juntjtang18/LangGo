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
    @Published private(set) var isLoadingAllReviewFlashcards = false
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
    private var reviewFlashcardNetworkPageBuffer: [Int: [Flashcard]] = [:]
    private var reviewFlashcardNetworkPagination: StrapiPagination?
    private var reviewFlashcardNetworkPagePaginations: [Int: StrapiPagination] = [:]
    private var reviewFlashcardPageTasks: [Int: Task<([Flashcard], StrapiPagination?), Error>] = [:]
    private var reviewFlashcardsFullLoadTask: Task<Void, Never>?
    private var allMyFlashcardsFullLoadTask: Task<Void, Never>?
    private var reviewFlashcardNetworkExpectedPageCount: Int?
    private var reviewFlashcardNetworkExpectedTotal: Int?
    private var reviewFlashcardNetworkOwnerUserId: Int?

    private var currentUserId: Int? {
        let userId = UserDefaults.standard.integer(forKey: "userId")
        return userId > 0 ? userId : nil
    }
    private let reviewFlashcardStateLock = NSLock()

    private func withReviewFlashcardStateLock<T>(_ work: () throws -> T) rethrows -> T {
        reviewFlashcardStateLock.lock()
        defer { reviewFlashcardStateLock.unlock() }
        return try work()
    }

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
        return try await fetchAvailableReviewFlashcards(pageSize: 100)
    }

    /// Returns the best currently available review-card set without blocking the UI
    /// on a full refresh.
    ///
    /// Behavior:
    /// - Fresh persistent cache: return the full cached set.
    /// - Full refresh already running: return all buffered/published cards immediately.
    /// - No cache and no refresh running: fetch the first page, publish it, then let
    ///   the service-owned background loader finish the full set.
    ///
    /// The persistent review cache is still only marked valid by
    /// `fetchAllReviewFlashcardsFromNetworkAndCommit` after every expected backend
    /// page has been loaded.
    func fetchAvailableReviewFlashcards(pageSize: Int = 100) async throws -> [Flashcard] {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadReviewFlashcards(using: cacheService) {
            logger.debug("✅ Review cache is FRESH. Returning \(cached.count) cards.")
            await publishReviewFlashcards(cached)
            return cached
        }

        let available = await currentAvailableReviewFlashcards()
        if isReviewFlashcardsFullLoadRunning(), !available.isEmpty {
            logger.debug("Review full-load is running. Returning \(available.count) available review cards immediately.")
            await publishReviewFlashcards(available)
            return available
        }

        logger.debug("Review cache is STALE. Fetching first review page and starting/reusing background full-load.")
        let (firstPageCards, _) = try await fetchReviewFlashcardsPage(page: 1, pageSize: pageSize)
        ensureReviewFlashcardsFullyLoaded(pageSize: pageSize)

        let refreshedAvailable = await currentAvailableReviewFlashcards()
        if !refreshedAvailable.isEmpty {
            return refreshedAvailable
        }

        return firstPageCards
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Flashcard {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await networkManager.post(to: url, body: body)

        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "FlashcardServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response missing data."])
        }

        let updatedCard = transformStrapiCard(updatedStrapiCard)
        patchLocalCachesAfterFlashcardReview(updatedCard)
        UserSnapshotCache.invalidate(using: cacheService)
        notifyFlashcardsDidChange()
        await refreshStatistics(forceRefresh: true)
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

        invalidateAllFlashcardCaches()

        logger.debug("✅ Successfully deleted flashcard with id: \(cardId) and invalidated caches.")
    }
    private func patchLocalCachesAfterFlashcardReview(_ updatedCard: Flashcard) {
        FlashcardCache.patchAfterFlashcardReview(updatedCard: updatedCard, using: cacheService)

        Task { @MainActor in
            self.flashcards = self.flashcards.map { $0.id == updatedCard.id ? updatedCard : $0 }
            self.reviewFlashcards.removeAll { $0.id == updatedCard.id }
        }

        logger.debug("✅ Patched flashcard caches after review for card id: \(updatedCard.id).")
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
            reviewFlashcardsFullLoadTask?.cancel()
            reviewFlashcardsFullLoadTask = nil
            allMyFlashcardsFullLoadTask?.cancel()
            allMyFlashcardsFullLoadTask = nil
            reviewFlashcardPageTasks.values.forEach { $0.cancel() }
            reviewFlashcardPageTasks.removeAll()
            resetReviewFlashcardNetworkBufferLocked()
        }
        Task {
            await publishReviewFlashcards([])
            await setReviewFlashcardsFullLoadActive(false)
        }
        notifyFlashcardsDidChange()
        
        logger.debug("✏️ SUCCESS: All flashcard caches invalidated.")
    }
    /// Clears only runtime state owned by this service when the active user changes.
    /// Persistent caches are user-scoped in FlashcardCache, so they do not need to be deleted.
    func resetUserScopedRuntimeState() {
        withReviewFlashcardStateLock {
            reviewFlashcardsFullLoadTask?.cancel()
            reviewFlashcardsFullLoadTask = nil
            allMyFlashcardsFullLoadTask?.cancel()
            allMyFlashcardsFullLoadTask = nil
            reviewFlashcardPageTasks.values.forEach { $0.cancel() }
            reviewFlashcardPageTasks.removeAll()
            resetReviewFlashcardNetworkBufferLocked()
        }

        lastFlashcardStatisticsNetworkFetchAt = nil

        Task { @MainActor in
            self.flashcards = []
            self.reviewFlashcards = []
            self.flashcardStatistics = nil
            self.nextFlashcardStatisticsFetchAt = nil
            self.isLoadingFlashcards = false
            self.isLoadingAllReviewFlashcards = false
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

    func ensureReviewFlashcardsFullyLoaded(pageSize firstPageSize: Int = 100) {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadReviewFlashcards(using: cacheService) {
            Task { await publishReviewFlashcards(cached) }
            return
        }

        let loadingUserId = currentUserId
        let didStartTask = withReviewFlashcardStateLock { () -> Bool in
            guard reviewFlashcardsFullLoadTask == nil else {
                return false
            }

            reviewFlashcardsFullLoadTask = Task { [weak self] in
                await self?.loadAllReviewFlashcardsInBackground(firstPageSize: firstPageSize, userId: loadingUserId)
            }
            return true
        }

        if !didStartTask {
            logger.debug("Review full-load task already running. Reusing existing task.")
        }
    }

    private func isReviewFlashcardsFullLoadRunning() -> Bool {
        withReviewFlashcardStateLock {
            reviewFlashcardsFullLoadTask != nil
        }
    }

    private func currentAvailableReviewFlashcards() async -> [Flashcard] {
        let bufferedCards = reviewFlashcardNetworkBufferSnapshot().cards
        if !bufferedCards.isEmpty {
            return bufferedCards
        }

        return await MainActor.run {
            self.reviewFlashcards
        }
    }

    private func loadAllReviewFlashcardsInBackground(firstPageSize: Int, userId: Int?) async {
        guard isCurrentUser(userId) else {
            logger.debug("Skipping review full-load because active user changed before the task started.")
            return
        }

        await setReviewFlashcardsFullLoadActive(true)
        defer {
            withReviewFlashcardStateLock {
                reviewFlashcardsFullLoadTask = nil
            }
            Task { await setReviewFlashcardsFullLoadActive(false) }
        }

        do {
            _ = try await fetchAllReviewFlashcardsFromNetworkAndCommit(firstPageSize: firstPageSize, userId: userId)
        } catch is CancellationError {
            logger.debug("Review full-load task was cancelled. Leaving review cache invalid/stale.")
        } catch {
            logger.error("Failed background-loading review flashcards: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchAllReviewFlashcardsFromNetworkAndCommit(firstPageSize: Int, userId: Int? = nil) async throws -> [Flashcard] {
        let ownerUserId = userId ?? currentUserId
        guard isCurrentUser(ownerUserId) else { throw CancellationError() }

        let firstPage: ([Flashcard], StrapiPagination?)

        if let bufferedFirstPage = bufferedReviewFlashcardsPage(page: 1) {
            logger.debug("Using already buffered review first page before paged full-load.")
            firstPage = bufferedFirstPage
        } else {
            resetReviewFlashcardNetworkBuffer(ownerUserId: ownerUserId)
            firstPage = try await fetchReviewFlashcardsPageFromNetworkDeduped(page: 1, pageSize: firstPageSize)
            guard isCurrentUser(ownerUserId) else { throw CancellationError() }
            await bufferReviewFlashcardsPage(firstPage.0, page: 1, pagination: firstPage.1, ownerUserId: ownerUserId)
        }

        try Task.checkCancellation()
        guard isCurrentUser(ownerUserId) else { throw CancellationError() }

        guard let firstPagination = firstPage.1 else {
            throw URLError(.badServerResponse)
        }

        let expectedPageCount = firstPagination.pageCount
        let expectedTotal = firstPagination.total

        if expectedTotal == 0 {
            guard isCurrentUser(ownerUserId) else { throw CancellationError() }
            FlashcardCache.storeReviewFlashcards([], using: cacheService)
            await publishReviewFlashcards([])
            logger.debug("✅ Review cache committed with 0 cards.")
            return []
        }

        guard expectedPageCount > 0 else {
            throw ReviewFlashcardCacheCommitError.incomplete
        }

        if expectedPageCount > 1 {
            logger.debug("Fetching remaining review flashcards using normal page/pageSize loop: pages 2...\(expectedPageCount).")

            for page in 2...expectedPageCount {
                try Task.checkCancellation()

                if isReviewFlashcardsPageBuffered(page) {
                    continue
                }

                let pageResult = try await fetchReviewFlashcardsPageFromNetworkDeduped(page: page, pageSize: firstPagination.pageSize)
                guard isCurrentUser(ownerUserId) else { throw CancellationError() }
                await bufferReviewFlashcardsPage(pageResult.0, page: page, pagination: pageResult.1, ownerUserId: ownerUserId)
            }
        }

        try Task.checkCancellation()

        guard isCurrentUser(ownerUserId) else { throw CancellationError() }
        let allCards = try commitReviewFlashcardsCacheIfComplete(ownerUserId: ownerUserId)
        await publishReviewFlashcards(allCards)
        logger.debug("✅ Review cache committed after normal paged full-load with \(allCards.count) cards.")
        return allCards
    }

    private func fetchReviewFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        if !isRefreshModeEnabled,
           let cached = FlashcardCache.loadReviewFlashcards(using: cacheService) {
            logger.debug("Review cache is FRESH. Returning review page \(page) from cache.")
            await publishReviewFlashcards(cached)
            return pageSlice(from: cached, page: page, pageSize: pageSize)
        }

        if let bufferedPage = bufferedReviewFlashcardsPage(page: page) {
            logger.debug("Review cache is STALE, but page \(page) is already loaded in memory. Returning buffered page.")
            return bufferedPage
        }

        logger.debug("Review cache is STALE. Fetching review page \(page) from network or shared page task.")
        let (cards, pagination) = try await fetchReviewFlashcardsPageFromNetworkDeduped(page: page, pageSize: pageSize)
        await patchReviewFlashcardsCache(with: cards, page: page, pagination: pagination, ownerUserId: currentUserId)
        return (cards, pagination)
    }

    private func fetchReviewFlashcardsPageFromNetworkDeduped(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        if let existingTask = withReviewFlashcardStateLock({ reviewFlashcardPageTasks[page] }) {
            logger.debug("Joining existing review page \(page) network task.")
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> ([Flashcard], StrapiPagination?) in
            guard let self else { throw CancellationError() }
            return try await self.fetchReviewFlashcardsPageFromNetwork(page: page, pageSize: pageSize)
        }

        let taskState = withReviewFlashcardStateLock { () -> (task: Task<([Flashcard], StrapiPagination?), Error>, didStore: Bool) in
            if let existingTask = reviewFlashcardPageTasks[page] {
                return (existingTask, false)
            }
            reviewFlashcardPageTasks[page] = task
            return (task, true)
        }

        defer {
            if taskState.didStore {
                withReviewFlashcardStateLock {
                    reviewFlashcardPageTasks[page] = nil
                }
            }
        }

        return try await taskState.task.value
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

    private func pageSlice(from cards: [Flashcard], page: Int, pageSize: Int) -> ([Flashcard], StrapiPagination?) {
        let totalItems = cards.count
        let totalPages = pageSize > 0 ? (totalItems + pageSize - 1) / pageSize : 0

        guard page > 0, pageSize > 0, page <= totalPages || totalItems == 0 else {
            return ([], StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
        }

        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, totalItems)
        let pageItems = startIndex < endIndex ? Array(cards[startIndex..<endIndex]) : []
        return (pageItems, StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems))
    }

    private func patchReviewFlashcardsCache(with cards: [Flashcard], page: Int, pagination: StrapiPagination?, ownerUserId: Int?) async {
        guard isCurrentUser(ownerUserId) else { return }
        await bufferReviewFlashcardsPage(cards, page: page, pagination: pagination, ownerUserId: ownerUserId)

        do {
            let allCards = try commitReviewFlashcardsCacheIfComplete(ownerUserId: ownerUserId)
            await publishReviewFlashcards(allCards)
            logger.debug("Review cache patched and committed with \(allCards.count) cards after all pages loaded.")
        } catch ReviewFlashcardCacheCommitError.incomplete {
            let snapshot = reviewFlashcardNetworkBufferSnapshot()
            await publishReviewFlashcards(snapshot.cards)
            logger.debug("Review cache patch is incomplete. Cached \(snapshot.pageCount) / \(snapshot.expectedPageCount) pages in memory only; persistent cache remains stale.")
        } catch is CancellationError {
            logger.debug("Review cache patch skipped because active user changed.")
        } catch {
            logger.error("Review cache patch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func bufferReviewFlashcardsPage(_ cards: [Flashcard], page: Int, pagination: StrapiPagination?, ownerUserId: Int?) async {
        guard let pagination, isCurrentUser(ownerUserId) else { return }

        let bufferedCards = withReviewFlashcardStateLock { () -> [Flashcard] in
            if reviewFlashcardNetworkOwnerUserId != ownerUserId || page == 1 {
                resetReviewFlashcardNetworkBufferLocked()
                reviewFlashcardNetworkOwnerUserId = ownerUserId
            }

            reviewFlashcardNetworkPageBuffer[page] = cards
            reviewFlashcardNetworkPagePaginations[page] = pagination
            reviewFlashcardNetworkPagination = pagination
            reviewFlashcardNetworkExpectedPageCount = pagination.pageCount
            reviewFlashcardNetworkExpectedTotal = pagination.total

            return reviewFlashcardNetworkPageBuffer.keys.sorted().flatMap { reviewFlashcardNetworkPageBuffer[$0] ?? [] }
        }

        await publishReviewFlashcards(bufferedCards)
    }

    private func commitReviewFlashcardsCacheIfComplete(ownerUserId: Int?) throws -> [Flashcard] {
        guard isCurrentUser(ownerUserId) else { throw CancellationError() }

        let allCards = try withReviewFlashcardStateLock { () throws -> [Flashcard] in
            guard reviewFlashcardNetworkOwnerUserId == ownerUserId else {
                throw ReviewFlashcardCacheCommitError.incomplete
            }
            guard let expectedPageCount = reviewFlashcardNetworkExpectedPageCount,
                  let expectedTotal = reviewFlashcardNetworkExpectedTotal else {
                throw ReviewFlashcardCacheCommitError.incomplete
            }

            guard expectedPageCount > 0 else {
                return []
            }

            let hasEveryPage = (1...expectedPageCount).allSatisfy { reviewFlashcardNetworkPageBuffer[$0] != nil }
            guard hasEveryPage else {
                throw ReviewFlashcardCacheCommitError.incomplete
            }

            let allCards = (1...expectedPageCount).flatMap { reviewFlashcardNetworkPageBuffer[$0] ?? [] }
            guard allCards.count == expectedTotal else {
                logger.debug("Review cache not committed because buffered count \(allCards.count) does not match expected total \(expectedTotal).")
                throw ReviewFlashcardCacheCommitError.incomplete
            }

            return allCards
        }

        guard isCurrentUser(ownerUserId) else { throw CancellationError() }
        FlashcardCache.storeReviewFlashcards(allCards, using: cacheService)
        return allCards
    }

    private func resetReviewFlashcardNetworkBuffer(ownerUserId: Int? = nil) {
        withReviewFlashcardStateLock {
            resetReviewFlashcardNetworkBufferLocked()
            reviewFlashcardNetworkOwnerUserId = ownerUserId
        }
    }

    private func resetReviewFlashcardNetworkBufferLocked() {
        reviewFlashcardNetworkPageBuffer.removeAll()
        reviewFlashcardNetworkPagePaginations.removeAll()
        reviewFlashcardNetworkPagination = nil
        reviewFlashcardNetworkExpectedPageCount = nil
        reviewFlashcardNetworkExpectedTotal = nil
        reviewFlashcardNetworkOwnerUserId = nil
    }

    private func bufferedReviewFlashcardsPage(page: Int) -> ([Flashcard], StrapiPagination?)? {
        withReviewFlashcardStateLock {
            guard reviewFlashcardNetworkOwnerUserId == currentUserId,
                  let bufferedCards = reviewFlashcardNetworkPageBuffer[page] else { return nil }
            let pagination = reviewFlashcardNetworkPagePaginations[page] ?? reviewFlashcardNetworkPagination
            return (bufferedCards, pagination)
        }
    }

    private func isReviewFlashcardsPageBuffered(_ page: Int) -> Bool {
        withReviewFlashcardStateLock {
            reviewFlashcardNetworkOwnerUserId == currentUserId && reviewFlashcardNetworkPageBuffer[page] != nil
        }
    }

    private func reviewFlashcardNetworkBufferSnapshot() -> (cards: [Flashcard], pageCount: Int, expectedPageCount: Int) {
        withReviewFlashcardStateLock {
            guard reviewFlashcardNetworkOwnerUserId == currentUserId else {
                return ([], 0, 0)
            }
            let cards = reviewFlashcardNetworkPageBuffer.keys.sorted().flatMap { reviewFlashcardNetworkPageBuffer[$0] ?? [] }
            return (cards, reviewFlashcardNetworkPageBuffer.count, reviewFlashcardNetworkExpectedPageCount ?? 0)
        }
    }

    private func isCurrentUser(_ userId: Int?) -> Bool {
        currentUserId == userId
    }

    private enum ReviewFlashcardCacheCommitError: Error {
        case incomplete
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

    private func setReviewFlashcardsFullLoadActive(_ isActive: Bool) async {
        await MainActor.run {
            self.isLoadingAllReviewFlashcards = isActive
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
