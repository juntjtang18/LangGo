import Combine
import Foundation
import os

/// Service layer for user-created library articles and article tags.
@MainActor
final class ArticleService: ObservableObject {
    struct UserArticlesPageKey: Hashable {
        let page: Int
        let pageSize: Int
    }

    private enum Policy {
        static let sharedLibraryPage = 1
        static let sharedLibraryPageSize = 10
    }

    @Published private(set) var userArticlePages: [UserArticlesPageKey: StrapiListResponse<StrapiUserArticle>] = [:]
    @Published private(set) var userArticles: [StrapiUserArticle] = []
    @Published private(set) var userArticlesTotalCount: Int?
    @Published private(set) var articleChanged: Int = 0
    @Published private(set) var isLoadingUserArticles = false
    @Published private(set) var articlesErrorMessage: String?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "ArticleService")
    private let networkManager: NetworkManager
    private let authService: AuthService
    private let cacheService: CacheService
    private let articleTagService: ArticleTagService
    private var cachedCurrentUserID: Int?
    private var userArticlesPageTasks: [UserArticlesPageKey: Task<StrapiListResponse<StrapiUserArticle>, Error>] = [:]
    private var activeUserArticlesRequestCount = 0

    init(
        networkManager: NetworkManager = .shared,
        authService: AuthService = AuthService(),
        cacheService: CacheService = .shared,
        articleTagService: ArticleTagService? = nil
    ) {
        self.networkManager = networkManager
        self.authService = authService
        self.cacheService = cacheService
        self.articleTagService = articleTagService ?? ArticleTagService(
            networkManager: networkManager,
            authService: authService,
            cacheService: cacheService
        )
    }

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    func currentUserArticlesPage(page: Int, pageSize: Int) -> StrapiListResponse<StrapiUserArticle>? {
        userArticlePages[UserArticlesPageKey(page: page, pageSize: pageSize)]
    }

    func loadSharedUserArticlesIfNeeded() async {
        _ = try? await fetchUserArticles(
            page: Policy.sharedLibraryPage,
            pageSize: Policy.sharedLibraryPageSize,
            forceRefresh: false
        )
    }

    func refreshSharedUserArticles() async {
        _ = try? await fetchUserArticles(
            page: Policy.sharedLibraryPage,
            pageSize: Policy.sharedLibraryPageSize,
            forceRefresh: true
        )
    }

    func refreshArticleState() async {
        await refreshSharedUserArticles()
    }

    func loadUserArticlesPageIfNeeded(page: Int, pageSize: Int) async {
        _ = try? await fetchUserArticles(page: page, pageSize: pageSize, forceRefresh: false)
    }

    func refreshUserArticles(page: Int, pageSize: Int) async {
        _ = try? await fetchUserArticles(page: page, pageSize: pageSize, forceRefresh: true)
    }

    func fetchArticleTags(usedOnly: Bool = false, forceRefresh: Bool = false) async throws -> [StrapiArticleTag] {
        try await articleTagService.fetchArticleTags(usedOnly: usedOnly, forceRefresh: forceRefresh)
    }

    func fetchMyArticleTags() async throws -> [StrapiArticleTag] {
        try await fetchArticleTags(usedOnly: false, forceRefresh: false)
    }

    func fetchMyUsedArticleTags() async throws -> [StrapiArticleTag] {
        try await fetchArticleTags(usedOnly: true, forceRefresh: false)
    }

    func createArticleTag(tag: String) async throws -> StrapiArticleTag {
        try await articleTagService.createArticleTag(tag: tag)
    }

    func updateArticleTag(tagId: Int, tag: String) async throws -> StrapiArticleTag {
        try await articleTagService.updateArticleTag(tagId: tagId, tag: tag)
    }

    func deleteArticleTag(tagId: Int) async throws {
        try await articleTagService.deleteArticleTag(tagId: tagId)
    }

    func findOrCreateArticleTag(tag: String) async throws -> StrapiArticleTag {
        try await articleTagService.findOrCreateArticleTag(tag: tag)
    }

    func findOrCreateArticleTags(tags: [String]) async throws -> [StrapiArticleTag] {
        try await articleTagService.findOrCreateArticleTags(tags: tags)
    }

    func fetchMyUserArticles() async throws -> [StrapiUserArticle] {
        let response = try await fetchUserArticles(page: 1, pageSize: 100)
        return response.data ?? []
    }

    func fetchMyUserArticles(page: Int, pageSize: Int) async throws -> StrapiListResponse<StrapiUserArticle> {
        try await fetchUserArticles(page: page, pageSize: pageSize)
    }

    func fetchUserArticles(
        page: Int,
        pageSize: Int,
        forceRefresh: Bool = false
    ) async throws -> StrapiListResponse<StrapiUserArticle> {
        let currentUserID = try await currentUserID()
        let pageKey = UserArticlesPageKey(page: page, pageSize: pageSize)

        if !forceRefresh && !isRefreshModeEnabled {
            if let staleResponse = ArticleCache.loadUserArticlesPageStale(
                userID: currentUserID,
                page: page,
                pageSize: pageSize,
                using: cacheService
            ) {
                publishUserArticlesPage(staleResponse, key: pageKey)
            }

            if let cachedResponse = ArticleCache.loadUserArticlesPage(
                userID: currentUserID,
                page: page,
                pageSize: pageSize,
                using: cacheService
            ) {
                logger.debug("✅ Returning page \(page) of user articles from cache for user \(currentUserID).")
                publishUserArticlesPage(cachedResponse, key: pageKey)
                return cachedResponse
            }
        }

        if let existingTask = userArticlesPageTasks[pageKey] {
            logger.debug("Joining existing user articles task for page \(page) size \(pageSize).")
            return try await existingTask.value
        }

        activeUserArticlesRequestCount += 1
        isLoadingUserArticles = true
        articlesErrorMessage = nil

        let task = Task { [weak self] () throws -> StrapiListResponse<StrapiUserArticle> in
            guard let self else { throw CancellationError() }
            return try await self.fetchUserArticlesPageFromNetwork(
                userID: currentUserID,
                page: page,
                pageSize: pageSize
            )
        }
        userArticlesPageTasks[pageKey] = task
        defer {
            userArticlesPageTasks[pageKey] = nil
            activeUserArticlesRequestCount = max(activeUserArticlesRequestCount - 1, 0)
            isLoadingUserArticles = activeUserArticlesRequestCount > 0
        }

        do {
            let response = try await task.value
            ArticleCache.storeUserArticlesPage(
                response,
                userID: currentUserID,
                page: page,
                pageSize: pageSize,
                using: cacheService
            )
            publishUserArticlesPage(response, key: pageKey)
            return response
        } catch {
            let isCancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled

            if isCancelled {
                logger.debug("User article fetch cancelled; falling back to stale cache if available.")

                if let staleResponse = ArticleCache.loadUserArticlesPageStale(
                    userID: currentUserID,
                    page: page,
                    pageSize: pageSize,
                    using: cacheService
                ) {
                    publishUserArticlesPage(staleResponse, key: pageKey)
                    return staleResponse
                }

                throw error
            }

            logger.error("Failed to fetch user articles: \(error.localizedDescription, privacy: .public)")
            articlesErrorMessage = error.localizedDescription

            if let staleResponse = ArticleCache.loadUserArticlesPageStale(
                userID: currentUserID,
                page: page,
                pageSize: pageSize,
                using: cacheService
            ) {
                publishUserArticlesPage(staleResponse, key: pageKey)
                return staleResponse
            }

            throw error
        }
    }

    func fetchUserArticle(articleId: Int, forceRefresh: Bool = false) async throws -> StrapiUserArticle {
        let currentUserID = try await currentUserID()

        if !forceRefresh && !isRefreshModeEnabled,
           let cachedArticle = ArticleCache.loadUserArticleDetail(
            userID: currentUserID,
            articleID: articleId,
            using: cacheService
           ) {
            logger.debug("✅ Returning user article detail from cache for article \(articleId).")
            return cachedArticle
        }

        do {
            let article = try await fetchUserArticleFromNetwork(articleId: articleId, userID: currentUserID)
            ArticleCache.storeUserArticleDetail(article, userID: currentUserID, using: cacheService)
            return article
        } catch {
            if let staleArticle = ArticleCache.loadUserArticleDetailStale(
                userID: currentUserID,
                articleID: articleId,
                using: cacheService
            ) {
                return staleArticle
            }

            throw error
        }
    }

    func createUserArticle(
        title: String,
        content: String,
        languageCode: String?,
        wordCount: Int?,
        progress: Double? = nil,
        lastReadAt: Date? = nil,
        tags: [String]
    ) async throws -> StrapiUserArticle {
        let resolvedTags = try await articleTagService.findOrCreateArticleTags(tags: tags)
        return try await createUserArticle(
            title: title,
            content: content,
            languageCode: languageCode,
            wordCount: wordCount,
            progress: progress,
            lastReadAt: lastReadAt,
            articleTagIds: resolvedTags.map(\.id)
        )
    }

    func createUserArticle(
        title: String,
        content: String,
        languageCode: String?,
        wordCount: Int?,
        progress: Double? = nil,
        lastReadAt: Date? = nil,
        articleTagIds: [Int] = []
    ) async throws -> StrapiUserArticle {
        let currentUserID = try await currentUserID()

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-articles") else {
            throw URLError(.badURL)
        }

        let request = SaveUserArticleRequest(
            data: SaveUserArticlePayload(
                title: title,
                content: content,
                languageCode: languageCode,
                wordCount: wordCount,
                user: currentUserID,
                progress: progress,
                lastReadAt: lastReadAt,
                articleTags: articleTagIds
            )
        )

        logger.debug("Creating user article titled '\(title, privacy: .public)' for user \(currentUserID).")
        return try await CacheMutation.perform(
            remoteWrite: {
                let response: StrapiSingleResponse<StrapiUserArticle> = try await self.networkManager.post(to: url, body: request)
                return try await self.fetchUserArticleFromNetwork(articleId: response.data.id, userID: currentUserID)
            },
            applyLocalSuccess: { createdArticle in
                ArticleCache.patchUserArticle(
                    createdArticle,
                    userID: currentUserID,
                    prependToFirstPage: true,
                    using: self.cacheService
                )
                self.publishPatchedUserArticle(createdArticle, prependToFirstPage: true)
                self.articleChanged += 1
                self.logger.debug("articleChanged published token=\(self.articleChanged, privacy: .public) articleId=\(createdArticle.id, privacy: .public)")
                await self.articleTagService.refreshLoadedTagCollectionsAfterArticleWrite()
            }
        )
    }

    func updateUserArticle(
        articleId: Int,
        title: String,
        content: String,
        languageCode: String?,
        wordCount: Int?,
        progress: Double? = nil,
        lastReadAt: Date? = nil,
        tags: [String]
    ) async throws -> StrapiUserArticle {
        let resolvedTags = try await articleTagService.findOrCreateArticleTags(tags: tags)
        return try await updateUserArticle(
            articleId: articleId,
            title: title,
            content: content,
            languageCode: languageCode,
            wordCount: wordCount,
            progress: progress,
            lastReadAt: lastReadAt,
            articleTagIds: resolvedTags.map(\.id)
        )
    }

    func updateUserArticle(
        articleId: Int,
        title: String,
        content: String,
        languageCode: String?,
        wordCount: Int?,
        progress: Double? = nil,
        lastReadAt: Date? = nil,
        articleTagIds: [Int] = []
    ) async throws -> StrapiUserArticle {
        let currentUserID = try await currentUserID()

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-articles/\(articleId)") else {
            throw URLError(.badURL)
        }

        let request = SaveUserArticleRequest(
            data: SaveUserArticlePayload(
                title: title,
                content: content,
                languageCode: languageCode,
                wordCount: wordCount,
                user: currentUserID,
                progress: progress,
                lastReadAt: lastReadAt,
                articleTags: articleTagIds
            )
        )

        logger.debug("Updating user article \(articleId) for user \(currentUserID).")
        return try await CacheMutation.perform(
            remoteWrite: {
                let _: StrapiSingleResponse<StrapiUserArticle> = try await self.networkManager.put(to: url, body: request)
                return try await self.fetchUserArticleFromNetwork(articleId: articleId, userID: currentUserID)
            },
            applyLocalSuccess: { updatedArticle in
                ArticleCache.patchUserArticle(
                    updatedArticle,
                    userID: currentUserID,
                    prependToFirstPage: false,
                    using: self.cacheService
                )
                self.publishPatchedUserArticle(updatedArticle, prependToFirstPage: false)
                await self.articleTagService.refreshLoadedTagCollectionsAfterArticleWrite()
            }
        )
    }

    func deleteUserArticle(articleId: Int) async throws {
        let currentUserID = try await currentUserID()

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-articles/\(articleId)") else {
            throw URLError(.badURL)
        }

        logger.debug("Deleting user article \(articleId) for user \(currentUserID).")
        try await CacheMutation.perform(
            remoteWrite: {
                try await self.networkManager.delete(at: url)
            },
            applyLocalSuccess: {
                ArticleCache.removeUserArticle(articleId, userID: currentUserID, using: self.cacheService)
                self.publishRemovedUserArticle(articleId)
                await self.articleTagService.refreshLoadedTagCollectionsAfterArticleWrite()
            }
        )
    }

    private func fetchUserArticlesPageFromNetwork(
        userID: Int,
        page: Int,
        pageSize: Int
    ) async throws -> StrapiListResponse<StrapiUserArticle> {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/user-articles") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "filters[user][id][$eq]", value: "\(userID)"),
            URLQueryItem(name: "fields[0]", value: "title"),
            URLQueryItem(name: "fields[1]", value: "content"),
            URLQueryItem(name: "fields[2]", value: "language_code"),
            URLQueryItem(name: "fields[3]", value: "word_count"),
            URLQueryItem(name: "fields[4]", value: "progress"),
            URLQueryItem(name: "fields[5]", value: "last_read_at"),
            URLQueryItem(name: "populate[article_tags][fields][0]", value: "tag"),
            URLQueryItem(name: "sort", value: "updatedAt:desc"),
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)")
        ]

        guard let url = urlComponents.url else { throw URLError(.badURL) }

        logger.debug("Fetching page \(page) of user articles for user \(userID).")
        return try await networkManager.fetchDirect(from: url)
    }

    private func fetchUserArticleFromNetwork(articleId: Int, userID: Int) async throws -> StrapiUserArticle {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/user-articles/\(articleId)") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "fields[0]", value: "title"),
            URLQueryItem(name: "fields[1]", value: "content"),
            URLQueryItem(name: "fields[2]", value: "language_code"),
            URLQueryItem(name: "fields[3]", value: "word_count"),
            URLQueryItem(name: "fields[4]", value: "progress"),
            URLQueryItem(name: "fields[5]", value: "last_read_at"),
            URLQueryItem(name: "populate[article_tags][fields][0]", value: "tag")
        ]

        guard let url = urlComponents.url else { throw URLError(.badURL) }

        logger.debug("Fetching detail for article \(articleId) and user \(userID).")
        let response: StrapiSingleResponse<StrapiUserArticle> = try await networkManager.fetchDirect(from: url)
        return response.data
    }

    private func publishUserArticlesPage(
        _ response: StrapiListResponse<StrapiUserArticle>,
        key: UserArticlesPageKey
    ) {
        userArticlePages[key] = response
        syncPublishedUserArticles()
    }

    private func publishPatchedUserArticle(_ article: StrapiUserArticle, prependToFirstPage: Bool) {
        for (key, page) in userArticlePages {
            var articles = page.data ?? []
            let originalCount = articles.count

            if let existingIndex = articles.firstIndex(where: { $0.id == article.id }) {
                articles[existingIndex] = article
            } else if prependToFirstPage && key.page == 1 {
                articles.insert(article, at: 0)

                if let pageSize = page.meta?.pagination?.pageSize, articles.count > pageSize {
                    articles.removeLast(articles.count - pageSize)
                }
            } else {
                continue
            }

            let updatedPagination = page.meta?.pagination.map {
                StrapiPagination(
                    page: $0.page,
                    pageSize: $0.pageSize,
                    pageCount: $0.pageCount,
                    total: max($0.total + (prependToFirstPage && originalCount == articles.count - 1 ? 1 : 0), articles.count)
                )
            }

            userArticlePages[key] = StrapiListResponse(
                data: articles,
                meta: updatedPagination.map { StrapiMeta(pagination: $0) }
            )
        }

        syncPublishedUserArticles()
    }

    private func publishRemovedUserArticle(_ articleId: Int) {
        for (key, page) in userArticlePages {
            var articles = page.data ?? []
            let originalCount = articles.count
            articles.removeAll { $0.id == articleId }

            guard articles.count != originalCount else { continue }

            let updatedPagination = page.meta?.pagination.map {
                StrapiPagination(
                    page: $0.page,
                    pageSize: $0.pageSize,
                    pageCount: $0.pageCount,
                    total: max($0.total - (originalCount - articles.count), articles.count)
                )
            }

            userArticlePages[key] = StrapiListResponse(
                data: articles,
                meta: updatedPagination.map { StrapiMeta(pagination: $0) }
            )
        }

        syncPublishedUserArticles()
    }

    private func syncPublishedUserArticles() {
        let sortedKeys = userArticlePages.keys.sorted { lhs, rhs in
            if lhs.page == rhs.page {
                return lhs.pageSize > rhs.pageSize
            }
            return lhs.page < rhs.page
        }

        var seenArticleIDs = Set<Int>()
        userArticles = sortedKeys
            .flatMap { userArticlePages[$0]?.data ?? [] }
            .filter { seenArticleIDs.insert($0.id).inserted }

        if let totalFromPagination = userArticlePages.values
            .compactMap({ $0.meta?.pagination?.total })
            .max() {
            userArticlesTotalCount = totalFromPagination
            return
        }

        let knownArticleIDs = Set(userArticlePages.values
            .flatMap { $0.data ?? [] }
            .map(\.id))
        userArticlesTotalCount = knownArticleIDs.isEmpty ? nil : knownArticleIDs.count
    }

    private func currentUserID() async throws -> Int {
        if let sessionUserID = UserSessionManager.shared.currentUser?.id {
            syncCurrentUserState(userID: sessionUserID)
            return sessionUserID
        }

        let persistedUserID = UserDefaults.standard.integer(forKey: "userId")
        if persistedUserID > 0 {
            syncCurrentUserState(userID: persistedUserID)
            return persistedUserID
        }

        if let cachedCurrentUserID {
            return cachedCurrentUserID
        }

        let currentUser = try await authService.fetchCurrentUser()
        syncCurrentUserState(userID: currentUser.id)
        return currentUser.id
    }

    private func syncCurrentUserState(userID: Int) {
        guard cachedCurrentUserID != userID else { return }

        cachedCurrentUserID = userID
        userArticlesPageTasks.values.forEach { $0.cancel() }
        userArticlesPageTasks.removeAll()
        activeUserArticlesRequestCount = 0
        userArticlePages = [:]
        userArticles = []
        userArticlesTotalCount = nil
        isLoadingUserArticles = false
        articlesErrorMessage = nil
    }

    func resetUserScopedRuntimeState() {
        cachedCurrentUserID = nil
        userArticlesPageTasks.values.forEach { $0.cancel() }
        userArticlesPageTasks.removeAll()
        activeUserArticlesRequestCount = 0
        userArticlePages = [:]
        userArticles = []
        userArticlesTotalCount = nil
        isLoadingUserArticles = false
        articlesErrorMessage = nil
    }
}
