import Foundation

enum ArticleCache {
    private enum Policy {
        static let articleTagsTTL: CacheService.CacheTTL = .seconds(15 * 60)
        static let usedArticleTagsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let articlePageTTL: CacheService.CacheTTL = .seconds(5 * 60)
    }

    static let articleTagsTag = CacheService.CacheTag(rawValue: "article-tags")
    static let usedArticleTagsTag = CacheService.CacheTag(rawValue: "used-article-tags")
    static let userArticlesTag = CacheService.CacheTag(rawValue: "user-articles")

    static func articleTagsKey(userID: Int) -> String {
        "articleTags.user.\(userID)"
    }

    static func usedArticleTagsKey(userID: Int) -> String {
        "articleTags.used.user.\(userID)"
    }

    static func userArticlesKey(userID: Int, page: Int, pageSize: Int) -> String {
        "userArticles.user.\(userID).page.\(page).size.\(pageSize)"
    }

    static func loadArticleTags(userID: Int, using cacheService: CacheService = .shared) -> [StrapiArticleTag]? {
        cacheService.loadIfValid(type: [StrapiArticleTag].self, from: articleTagsKey(userID: userID))
    }

    static func storeArticleTags(_ tags: [StrapiArticleTag], userID: Int, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(tags, key: articleTagsKey(userID: userID), ttl: Policy.articleTagsTTL, tags: [articleTagsTag])
    }

    static func loadUsedArticleTags(userID: Int, using cacheService: CacheService = .shared) -> [StrapiArticleTag]? {
        cacheService.loadIfValid(type: [StrapiArticleTag].self, from: usedArticleTagsKey(userID: userID))
    }

    static func storeUsedArticleTags(_ tags: [StrapiArticleTag], userID: Int, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(tags, key: usedArticleTagsKey(userID: userID), ttl: Policy.usedArticleTagsTTL, tags: [usedArticleTagsTag])
    }

    static func loadUserArticlesPage(
        userID: Int,
        page: Int,
        pageSize: Int,
        using cacheService: CacheService = .shared
    ) -> StrapiListResponse<StrapiUserArticle>? {
        cacheService.loadIfValid(
            type: StrapiListResponse<StrapiUserArticle>.self,
            from: userArticlesKey(userID: userID, page: page, pageSize: pageSize)
        )
    }

    static func storeUserArticlesPage(
        _ response: StrapiListResponse<StrapiUserArticle>,
        userID: Int,
        page: Int,
        pageSize: Int,
        using cacheService: CacheService = .shared
    ) {
        cacheService.saveWithPolicy(
            response,
            key: userArticlesKey(userID: userID, page: page, pageSize: pageSize),
            ttl: Policy.articlePageTTL,
            tags: [userArticlesTag]
        )
    }

    static func invalidateAfterTagWrite(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tags: [articleTagsTag, usedArticleTagsTag, userArticlesTag])
    }

    static func invalidateAfterArticleWrite(tagsChanged: Bool, using cacheService: CacheService = .shared) {
        var tags: [CacheService.CacheTag] = [userArticlesTag]
        if tagsChanged {
            tags.append(articleTagsTag)
            tags.append(usedArticleTagsTag)
        }
        cacheService.invalidate(tags: tags)
    }
}
