import Foundation

enum FlashcardCache {
    private enum Policy {
        static let statisticsTTL: CacheService.CacheTTL = .seconds(1)
        static let reviewFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let allMyFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let tierFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let recentFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
    }

    static let statisticsTag = CacheService.CacheTag(rawValue: "flashcard-statistics")
    static let reviewFlashcardsTag = CacheService.CacheTag(rawValue: "review-flashcards")
    static let allMyFlashcardsTag = CacheService.CacheTag(rawValue: "all-my-flashcards")
    static let tierFlashcardsTag = CacheService.CacheTag(rawValue: "tier-flashcards")
    static let recentFlashcardsTag = CacheService.CacheTag(rawValue: "recent-flashcards")

    static func statisticsKey() -> String {
        "flashcardStatistics"
    }

    static func reviewFlashcardsKey() -> String {
        "reviewFlashcards"
    }

    static func allMyFlashcardsKey() -> String {
        "allMyFlashcards"
    }

    static func tierFlashcardsKey(reviewTier: String) -> String {
        "allMyFlashcards.tier.\(reviewTier)"
    }

    static func recentFlashcardsKey(limit: Int) -> String {
        "recentFlashcards.limit.\(limit)"
    }

    static func loadStatistics(using cacheService: CacheService = .shared) -> StrapiStatistics? {
        cacheService.loadIfValid(type: StrapiStatistics.self, from: statisticsKey())
    }

    static func storeStatistics(_ statistics: StrapiStatistics, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            statistics,
            key: statisticsKey(),
            ttl: Policy.statisticsTTL,
            tags: [statisticsTag]
        )
    }

    static func loadReviewFlashcards(using cacheService: CacheService = .shared) -> [Flashcard]? {
        cacheService.loadIfValid(type: [Flashcard].self, from: reviewFlashcardsKey())
    }

    static func storeReviewFlashcards(_ cards: [Flashcard], using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            cards,
            key: reviewFlashcardsKey(),
            ttl: Policy.reviewFlashcardsTTL,
            tags: [reviewFlashcardsTag]
        )
    }

    static func loadAllMyFlashcards(using cacheService: CacheService = .shared) -> [Flashcard]? {
        cacheService.loadIfValid(type: [Flashcard].self, from: allMyFlashcardsKey())
    }

    static func storeAllMyFlashcards(_ cards: [Flashcard], using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            cards,
            key: allMyFlashcardsKey(),
            ttl: Policy.allMyFlashcardsTTL,
            tags: [allMyFlashcardsTag]
        )
    }

    static func loadTierFlashcards(reviewTier: String, using cacheService: CacheService = .shared) -> [Flashcard]? {
        cacheService.loadIfValid(type: [Flashcard].self, from: tierFlashcardsKey(reviewTier: reviewTier))
    }

    static func storeTierFlashcards(_ cards: [Flashcard], reviewTier: String, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            cards,
            key: tierFlashcardsKey(reviewTier: reviewTier),
            ttl: Policy.tierFlashcardsTTL,
            tags: [tierFlashcardsTag]
        )
    }

    static func loadRecentFlashcards(limit: Int, using cacheService: CacheService = .shared) -> [Flashcard]? {
        cacheService.loadIfValid(type: [Flashcard].self, from: recentFlashcardsKey(limit: limit))
    }

    static func storeRecentFlashcards(_ cards: [Flashcard], limit: Int, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            cards,
            key: recentFlashcardsKey(limit: limit),
            ttl: Policy.recentFlashcardsTTL,
            tags: [recentFlashcardsTag]
        )
    }

    static func invalidateAfterFlashcardWrite(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tags: [statisticsTag, reviewFlashcardsTag, allMyFlashcardsTag, tierFlashcardsTag, recentFlashcardsTag])
    }
}
