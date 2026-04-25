import Foundation

enum ArticleCache {
    private enum Policy {
        static let articleTagsTTL: CacheService.CacheTTL = .seconds(15 * 60)
        static let usedArticleTagsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let articlePageTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let articleDetailTTL: CacheService.CacheTTL = .seconds(5 * 60)
    }

    static let articleTagsTag = CacheService.CacheTag(rawValue: "article-tags")
    static let usedArticleTagsTag = CacheService.CacheTag(rawValue: "used-article-tags")
    static let userArticlesTag = CacheService.CacheTag(rawValue: "user-articles")
    static let userArticleDetailTag = CacheService.CacheTag(rawValue: "user-article-detail")

    static func articleTagsKey(userID: Int) -> String {
        "articleTags.user.\(userID)"
    }

    static func usedArticleTagsKey(userID: Int) -> String {
        "articleTags.used.user.\(userID)"
    }

    static func userArticlesKey(userID: Int, page: Int, pageSize: Int) -> String {
        "userArticles.user.\(userID).page.\(page).size.\(pageSize)"
    }

    static func userArticleDetailKey(userID: Int, articleID: Int) -> String {
        "userArticle.detail.user.\(userID).id.\(articleID)"
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

    static func loadUserArticleDetail(
        userID: Int,
        articleID: Int,
        using cacheService: CacheService = .shared
    ) -> StrapiUserArticle? {
        cacheService.loadIfValid(
            type: StrapiUserArticle.self,
            from: userArticleDetailKey(userID: userID, articleID: articleID)
        )
    }

    static func storeUserArticleDetail(
        _ article: StrapiUserArticle,
        userID: Int,
        using cacheService: CacheService = .shared
    ) {
        cacheService.saveWithPolicy(
            article,
            key: userArticleDetailKey(userID: userID, articleID: article.id),
            ttl: Policy.articleDetailTTL,
            tags: [userArticleDetailTag]
        )
    }

    static func patchUserArticle(
        _ article: StrapiUserArticle,
        userID: Int,
        prependToFirstPage: Bool,
        using cacheService: CacheService = .shared
    ) {
        storeUserArticleDetail(article, userID: userID, using: cacheService)

        let pageKeys = cacheService.keys(for: userArticlesTag)
            .filter { $0.hasPrefix("userArticles.user.\(userID).page.") }

        for key in pageKeys {
            guard var page: StrapiListResponse<StrapiUserArticle> = cacheService.load(
                type: StrapiListResponse<StrapiUserArticle>.self,
                from: key
            ) else {
                continue
            }

            var articles = page.data ?? []
            let originalCount = articles.count

            if let existingIndex = articles.firstIndex(where: { $0.id == article.id }) {
                articles[existingIndex] = article
            } else if prependToFirstPage && key.contains(".page.1.") {
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

            page = StrapiListResponse(
                data: articles,
                meta: updatedPagination.map { StrapiMeta(pagination: $0) }
            )
            cacheService.saveWithPolicy(
                page,
                key: key,
                ttl: Policy.articlePageTTL,
                tags: [userArticlesTag]
            )
        }
    }

    static func invalidateAfterTagWrite(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tags: [articleTagsTag, usedArticleTagsTag, userArticlesTag])
    }

    static func invalidateAfterArticleWrite(tagsChanged: Bool, using cacheService: CacheService = .shared) {
        var tags: [CacheService.CacheTag] = [userArticlesTag, userArticleDetailTag]
        if tagsChanged {
            tags.append(articleTagsTag)
            tags.append(usedArticleTagsTag)
        }
        cacheService.invalidate(tags: tags)
    }
}
