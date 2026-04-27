import Combine
import Foundation
import os

@MainActor
final class ArticleTagService: ObservableObject {
    @Published private(set) var articleTags: [StrapiArticleTag] = []
    @Published private(set) var usedArticleTags: [StrapiArticleTag] = []
    @Published private(set) var isLoadingTags = false
    @Published private(set) var tagsErrorMessage: String?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "ArticleTagService")
    private let networkManager: NetworkManager
    private let authService: AuthService
    private let cacheService: CacheService
    private var cachedCurrentUserID: Int?
    private var hasLoadedArticleTags = false
    private var hasLoadedUsedArticleTags = false

    init(
        networkManager: NetworkManager = .shared,
        authService: AuthService = AuthService(),
        cacheService: CacheService = .shared
    ) {
        self.networkManager = networkManager
        self.authService = authService
        self.cacheService = cacheService
    }

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    func currentArticleTags(usedOnly: Bool = false) -> [StrapiArticleTag] {
        usedOnly ? usedArticleTags : articleTags
    }

    func loadArticleTagsIfNeeded(usedOnly: Bool = false) async {
        _ = try? await fetchArticleTags(usedOnly: usedOnly, forceRefresh: false)
    }

    func refreshArticleTags(usedOnly: Bool = false) async {
        _ = try? await fetchArticleTags(usedOnly: usedOnly, forceRefresh: true)
    }

    @discardableResult
    func fetchArticleTags(
        usedOnly: Bool = false,
        forceRefresh: Bool = false
    ) async throws -> [StrapiArticleTag] {
        let currentUserID = try await currentUserID()

        isLoadingTags = true
        tagsErrorMessage = nil

        defer {
            isLoadingTags = false
        }

        if !forceRefresh && !isRefreshModeEnabled {
            if let staleTags = loadStaleTags(userID: currentUserID, usedOnly: usedOnly) {
                publishTags(staleTags, usedOnly: usedOnly)
            }

            if let cachedTags = loadValidTags(userID: currentUserID, usedOnly: usedOnly) {
                logger.debug("✅ Returning article tags from cache for user \(currentUserID).")
                publishTags(cachedTags, usedOnly: usedOnly)
                return cachedTags
            }
        }

        do {
            let tags = try await fetchTagsFromNetwork(userID: currentUserID, usedOnly: usedOnly)
            storeTags(tags, userID: currentUserID, usedOnly: usedOnly)
            publishTags(tags, usedOnly: usedOnly)
            return tags
        } catch {
            logger.error("Failed to fetch article tags: \(error.localizedDescription, privacy: .public)")
            tagsErrorMessage = error.localizedDescription

            if let staleTags = loadStaleTags(userID: currentUserID, usedOnly: usedOnly) {
                return staleTags
            }

            throw error
        }
    }

    func createArticleTag(tag: String) async throws -> StrapiArticleTag {
        let currentUserID = try await currentUserID()
        return try await createArticleTag(tag: tag, userID: currentUserID)
    }

    func updateArticleTag(tagId: Int, tag: String) async throws -> StrapiArticleTag {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else {
            throw NSError(
                domain: "ArticleTagService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Tag cannot be empty."]
            )
        }

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/article-tags/\(tagId)") else {
            throw URLError(.badURL)
        }

        let request = UpdateArticleTagRequest(data: UpdateArticleTagPayload(tag: trimmedTag))
        logger.debug("Updating article tag \(tagId) to '\(trimmedTag, privacy: .public)'.")
        let response: StrapiSingleResponse<StrapiArticleTag> = try await networkManager.put(to: url, body: request)
        ArticleCache.invalidateAfterTagWrite(using: cacheService)
        await refreshLoadedTagCollectionsAfterMutation()
        return response.data
    }

    func deleteArticleTag(tagId: Int) async throws {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/article-tags/\(tagId)") else {
            throw URLError(.badURL)
        }

        logger.debug("Deleting article tag \(tagId).")
        try await networkManager.delete(at: url)
        ArticleCache.invalidateAfterTagWrite(using: cacheService)
        await refreshLoadedTagCollectionsAfterMutation()
    }

    func findOrCreateArticleTag(tag: String) async throws -> StrapiArticleTag {
        guard let resolvedTag = try await findOrCreateArticleTags(tags: [tag]).first else {
            throw NSError(
                domain: "ArticleTagService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to resolve tag."]
            )
        }

        return resolvedTag
    }

    func findOrCreateArticleTags(tags: [String]) async throws -> [StrapiArticleTag] {
        let normalizedTags = Array(NSOrderedSet(array: tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })) as? [String] ?? []

        guard !normalizedTags.isEmpty else { return [] }

        let currentUserID = try await currentUserID()
        let existingTags = try await fetchArticleTags(usedOnly: false, forceRefresh: false)
        var tagsByName: [String: StrapiArticleTag] = [:]

        for tag in existingTags {
            if let name = tag.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                tagsByName[name] = tag
            }
        }

        var resolvedTags: [StrapiArticleTag] = []
        for tag in normalizedTags {
            if let existing = tagsByName[tag] {
                resolvedTags.append(existing)
                continue
            }

            let created = try await createArticleTag(tag: tag, userID: currentUserID)
            tagsByName[tag] = created
            resolvedTags.append(created)
        }

        return resolvedTags
    }

    func refreshLoadedTagCollectionsAfterArticleWrite() async {
        if hasLoadedArticleTags {
            _ = try? await fetchArticleTags(usedOnly: false, forceRefresh: true)
        }

        if hasLoadedUsedArticleTags {
            _ = try? await fetchArticleTags(usedOnly: true, forceRefresh: true)
        }
    }

    private func createArticleTag(tag: String, userID: Int) async throws -> StrapiArticleTag {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else {
            throw NSError(
                domain: "ArticleTagService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Tag cannot be empty."]
            )
        }

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/article-tags") else {
            throw URLError(.badURL)
        }

        let request = CreateArticleTagRequest(data: CreateArticleTagPayload(tag: trimmedTag, user: userID))
        logger.debug("Creating article tag '\(trimmedTag, privacy: .public)' for user \(userID).")
        let response: StrapiSingleResponse<StrapiArticleTag> = try await networkManager.post(to: url, body: request)
        ArticleCache.invalidateAfterTagWrite(using: cacheService)
        return response.data
    }

    private func fetchTagsFromNetwork(userID: Int, usedOnly: Bool) async throws -> [StrapiArticleTag] {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/article-tags") else {
            throw URLError(.badURL)
        }

        var queryItems = [
            URLQueryItem(name: "filters[user][id][$eq]", value: "\(userID)"),
            URLQueryItem(name: "sort", value: "tag:asc"),
            URLQueryItem(name: "fields[0]", value: "tag")
        ]

        if usedOnly {
            queryItems.append(URLQueryItem(name: "filters[user_articles][id][$notNull]", value: "true"))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw URLError(.badURL) }

        logger.debug("Fetching \(usedOnly ? "used " : "")article tags for user \(userID).")
        let response: StrapiListResponse<StrapiArticleTag> = try await networkManager.fetchDirect(from: url)
        return response.data ?? []
    }

    private func loadValidTags(userID: Int, usedOnly: Bool) -> [StrapiArticleTag]? {
        if usedOnly {
            return ArticleCache.loadUsedArticleTags(userID: userID, using: cacheService)
        }

        return ArticleCache.loadArticleTags(userID: userID, using: cacheService)
    }

    private func loadStaleTags(userID: Int, usedOnly: Bool) -> [StrapiArticleTag]? {
        if usedOnly {
            return ArticleCache.loadUsedArticleTagsStale(userID: userID, using: cacheService)
        }

        return ArticleCache.loadArticleTagsStale(userID: userID, using: cacheService)
    }

    private func storeTags(_ tags: [StrapiArticleTag], userID: Int, usedOnly: Bool) {
        if usedOnly {
            ArticleCache.storeUsedArticleTags(tags, userID: userID, using: cacheService)
        } else {
            ArticleCache.storeArticleTags(tags, userID: userID, using: cacheService)
        }
    }

    private func publishTags(_ tags: [StrapiArticleTag], usedOnly: Bool) {
        if usedOnly {
            usedArticleTags = tags
            hasLoadedUsedArticleTags = true
        } else {
            articleTags = tags
            hasLoadedArticleTags = true
        }
    }

    private func refreshLoadedTagCollectionsAfterMutation() async {
        if hasLoadedArticleTags {
            _ = try? await fetchArticleTags(usedOnly: false, forceRefresh: true)
        }

        if hasLoadedUsedArticleTags {
            _ = try? await fetchArticleTags(usedOnly: true, forceRefresh: true)
        }
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
        articleTags = []
        usedArticleTags = []
        tagsErrorMessage = nil
        hasLoadedArticleTags = false
        hasLoadedUsedArticleTags = false
    }
}
