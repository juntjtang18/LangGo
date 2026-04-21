import Foundation
import os

/// Service layer for user-created library articles and article tags.
class ArticleService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ArticleService")
    private let networkManager = NetworkManager.shared
    private let authService = AuthService()
    private let cacheService = CacheService.shared
    private var cachedCurrentUserID: Int?

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    private func currentUserID() async throws -> Int {
        if let cachedCurrentUserID {
            return cachedCurrentUserID
        }

        let sessionUserID = await MainActor.run { UserSessionManager.shared.currentUser?.id }
        if let sessionUserID {
            cachedCurrentUserID = sessionUserID
            return sessionUserID
        }

        let persistedUserID = UserDefaults.standard.integer(forKey: "userId")
        if persistedUserID > 0 {
            cachedCurrentUserID = persistedUserID
            return persistedUserID
        }

        let currentUser = try await authService.fetchCurrentUser()
        cachedCurrentUserID = currentUser.id
        return currentUser.id
    }

    func fetchMyArticleTags() async throws -> [StrapiArticleTag] {
        let currentUserID = try await currentUserID()

        if !isRefreshModeEnabled,
           let cachedTags = ArticleCache.loadArticleTags(userID: currentUserID, using: cacheService) {
            logger.debug("✅ Returning article tags from cache for user \(currentUserID).")
            return cachedTags
        }

        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/article-tags") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "filters[user][id][$eq]", value: "\(currentUserID)"),
            URLQueryItem(name: "sort", value: "tag:asc"),
            URLQueryItem(name: "fields[0]", value: "tag")
        ]

        guard let url = urlComponents.url else { throw URLError(.badURL) }

        logger.debug("ArticleService: Fetching article tags for user \(currentUserID).")
        let response: StrapiListResponse<StrapiArticleTag> = try await networkManager.fetchDirect(from: url)
        let tags = response.data ?? []
        ArticleCache.storeArticleTags(tags, userID: currentUserID, using: cacheService)
        return tags
    }

    func fetchMyUsedArticleTags() async throws -> [StrapiArticleTag] {
        let currentUserID = try await currentUserID()

        if !isRefreshModeEnabled,
           let cachedTags = ArticleCache.loadUsedArticleTags(userID: currentUserID, using: cacheService) {
            logger.debug("✅ Returning used article tags from cache for user \(currentUserID).")
            return cachedTags
        }

        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/article-tags") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "filters[user][id][$eq]", value: "\(currentUserID)"),
            URLQueryItem(name: "filters[user_articles][id][$notNull]", value: "true"),
            URLQueryItem(name: "sort", value: "tag:asc"),
            URLQueryItem(name: "fields[0]", value: "tag")
        ]

        guard let url = urlComponents.url else { throw URLError(.badURL) }

        logger.debug("ArticleService: Fetching used article tags for user \(currentUserID).")
        let response: StrapiListResponse<StrapiArticleTag> = try await networkManager.fetchDirect(from: url)
        let tags = response.data ?? []
        ArticleCache.storeUsedArticleTags(tags, userID: currentUserID, using: cacheService)
        return tags
    }

    func createArticleTag(tag: String) async throws -> StrapiArticleTag {
        let currentUserID = try await currentUserID()
        return try await createArticleTag(tag: tag, userID: currentUserID)
    }

    private func createArticleTag(tag: String, userID: Int) async throws -> StrapiArticleTag {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else {
            throw NSError(domain: "ArticleService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tag cannot be empty."])
        }

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/article-tags") else {
            throw URLError(.badURL)
        }

        let request = CreateArticleTagRequest(data: CreateArticleTagPayload(tag: trimmedTag, user: userID))
        logger.debug("ArticleService: Creating article tag '\(trimmedTag, privacy: .public)' for user \(userID).")
        let response: StrapiSingleResponse<StrapiArticleTag> = try await networkManager.post(to: url, body: request)
        ArticleCache.invalidateAfterTagWrite(using: cacheService)
        return response.data
    }

    func updateArticleTag(tagId: Int, tag: String) async throws -> StrapiArticleTag {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else {
            throw NSError(domain: "ArticleService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tag cannot be empty."])
        }

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/article-tags/\(tagId)") else {
            throw URLError(.badURL)
        }

        let request = UpdateArticleTagRequest(data: UpdateArticleTagPayload(tag: trimmedTag))
        logger.debug("ArticleService: Updating article tag \(tagId) to '\(trimmedTag, privacy: .public)'.")
        let response: StrapiSingleResponse<StrapiArticleTag> = try await networkManager.put(to: url, body: request)
        ArticleCache.invalidateAfterTagWrite(using: cacheService)
        return response.data
    }

    func findOrCreateArticleTag(tag: String) async throws -> StrapiArticleTag {
        guard let resolvedTag = try await findOrCreateArticleTags(tags: [tag]).first else {
            throw NSError(domain: "ArticleService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve tag."])
        }

        return resolvedTag
    }

    func findOrCreateArticleTags(tags: [String]) async throws -> [StrapiArticleTag] {
        let normalizedTags = Array(NSOrderedSet(array: tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })) as? [String] ?? []

        guard !normalizedTags.isEmpty else { return [] }

        let currentUserID = try await currentUserID()
        let existingTags = try await fetchMyArticleTags()
        var tagsByName: [String: StrapiArticleTag] = [:]

        for tag in existingTags {
            if let name = tag.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
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
    func fetchMyUserArticles() async throws -> [StrapiUserArticle] {
        let response = try await fetchMyUserArticles(page: 1, pageSize: 100)
        return response.data ?? []
    }

    func fetchMyUserArticles(page: Int, pageSize: Int) async throws -> StrapiListResponse<StrapiUserArticle> {
        let currentUserID = try await currentUserID()

        if !isRefreshModeEnabled,
           let cachedResponse = ArticleCache.loadUserArticlesPage(
            userID: currentUserID,
            page: page,
            pageSize: pageSize,
            using: cacheService
           ) {
            logger.debug("✅ Returning page \(page) of user articles from cache for user \(currentUserID).")
            return cachedResponse
        }

        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/user-articles") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "filters[user][id][$eq]", value: "\(currentUserID)"),
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

        logger.debug("ArticleService: Fetching page \(page) of user articles for user \(currentUserID).")
        let response: StrapiListResponse<StrapiUserArticle> = try await networkManager.fetchDirect(from: url)
        ArticleCache.storeUserArticlesPage(response, userID: currentUserID, page: page, pageSize: pageSize, using: cacheService)
        return response
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

        logger.debug("ArticleService: Creating user article titled '\(title, privacy: .public)' for user \(currentUserID).")
        let response: StrapiSingleResponse<StrapiUserArticle> = try await networkManager.post(to: url, body: request)
        ArticleCache.invalidateAfterArticleWrite(tagsChanged: !articleTagIds.isEmpty, using: cacheService)
        return response.data
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

        logger.debug("ArticleService: Updating user article \(articleId) for user \(currentUserID).")
        let response: StrapiSingleResponse<StrapiUserArticle> = try await networkManager.put(to: url, body: request)
        ArticleCache.invalidateAfterArticleWrite(tagsChanged: true, using: cacheService)
        return response.data
    }
}
