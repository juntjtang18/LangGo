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

    static func patchAfterWordAdded(
        flashcard: Flashcard,
        reviewTier: String,
        using cacheService: CacheService = .shared
    ) {
        patchStatisticsAfterWordAdded(reviewTier: reviewTier, using: cacheService)
        patchAllMyFlashcardsAfterWordAdded(flashcard: flashcard, using: cacheService)
        patchReviewFlashcardsAfterWordAdded(flashcard: flashcard, using: cacheService)
        patchTierFlashcardsAfterWordAdded(flashcard: flashcard, reviewTier: reviewTier, using: cacheService)
        patchRecentFlashcardsAfterWordAdded(flashcard: flashcard, using: cacheService)
    }

    private static func patchStatisticsAfterWordAdded(reviewTier: String, using cacheService: CacheService) {
        guard var statistics = loadStatistics(using: cacheService) else { return }

        let normalizedTier = reviewTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let updatedByTier = statistics.byTier.map { tierStat in
            guard tierStat.tier == normalizedTier else { return tierStat }
            return StrapiTierStat(
                id: tierStat.id,
                tier: tierStat.tier,
                displayName: tierStat.displayName,
                min_streak: tierStat.min_streak,
                max_streak: tierStat.max_streak,
                cooldown_hours: tierStat.cooldown_hours,
                count: tierStat.count + 1,
                dueCount: tierStat.dueCount + 1,
                hardToRememberCount: tierStat.hardToRememberCount
            )
        }

        statistics = StrapiStatistics(
            totalCards: statistics.totalCards + 1,
            remembered: statistics.remembered,
            dueForReview: statistics.dueForReview + 1,
            reviewed: statistics.reviewed,
            hardToRemember: statistics.hardToRemember,
            byTier: updatedByTier,
            nextFetchAt: nil,
            batchWindowMinutes: statistics.batchWindowMinutes
        )

        storeStatistics(statistics, using: cacheService)
    }

    private static func patchAllMyFlashcardsAfterWordAdded(flashcard: Flashcard, using cacheService: CacheService) {
        guard var cards = loadAllMyFlashcards(using: cacheService) else { return }
        guard !cards.contains(where: { $0.id == flashcard.id }) else { return }
        cards.append(flashcard)
        storeAllMyFlashcards(cards, using: cacheService)
    }

    private static func patchReviewFlashcardsAfterWordAdded(flashcard: Flashcard, using cacheService: CacheService) {
        guard var cards = loadReviewFlashcards(using: cacheService) else { return }
        guard !cards.contains(where: { $0.id == flashcard.id }) else { return }
        cards.append(flashcard)
        storeReviewFlashcards(cards, using: cacheService)
    }

    private static func patchTierFlashcardsAfterWordAdded(flashcard: Flashcard, reviewTier: String, using cacheService: CacheService) {
        guard var cards = loadTierFlashcards(reviewTier: reviewTier, using: cacheService) else { return }
        guard !cards.contains(where: { $0.id == flashcard.id }) else { return }
        cards.append(flashcard)
        storeTierFlashcards(cards, reviewTier: reviewTier, using: cacheService)
    }

    private static func patchRecentFlashcardsAfterWordAdded(flashcard: Flashcard, using cacheService: CacheService) {
        let prefix = "recentFlashcards.limit."
        let keys = cacheService.keys(for: recentFlashcardsTag)

        for key in keys where key.hasPrefix(prefix) {
            guard let limit = Int(key.replacingOccurrences(of: prefix, with: "")),
                  limit > 0,
                  var cards = cacheService.loadIfValid(type: [Flashcard].self, from: key) else { continue }

            cards.removeAll { $0.id == flashcard.id }
            cards.insert(flashcard, at: 0)
            if cards.count > limit {
                cards = Array(cards.prefix(limit))
            }

            cacheService.saveWithPolicy(
                cards,
                key: key,
                ttl: Policy.recentFlashcardsTTL,
                tags: [recentFlashcardsTag]
            )
        }
    }
}
