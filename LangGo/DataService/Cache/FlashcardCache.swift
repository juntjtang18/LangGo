import Foundation

enum FlashcardCache {
    private enum Policy {
        static let allMyFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let tierFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
        static let recentFlashcardsTTL: CacheService.CacheTTL = .seconds(5 * 60)
    }
    private static var currentUserId: Int? {
        let userId = UserDefaults.standard.integer(forKey: "userId")
        return userId > 0 ? userId : nil
    }

    static var currentUserCacheScope: String {
        if let userId = currentUserId { return "user.\(userId)" }
        return "anonymous"
    }

    static func scopedKey(_ key: String, userId: Int? = nil) -> String {
        if let userId, userId > 0 {
            return "flashcards.user.\(userId).\(key)"
        }
        return "flashcards.\(currentUserCacheScope).\(key)"
    }

    private static func scopedTag(_ tag: String) -> CacheService.CacheTag {
        CacheService.CacheTag(rawValue: "flashcards.\(currentUserCacheScope).\(tag)")
    }

    static var statisticsTag: CacheService.CacheTag { scopedTag("statistics") }
    static var reviewFlashcardsTag: CacheService.CacheTag { scopedTag("review-flashcards") }
    static var allMyFlashcardsTag: CacheService.CacheTag { scopedTag("all-my-flashcards") }
    static var tierFlashcardsTag: CacheService.CacheTag { scopedTag("tier-flashcards") }
    static var recentFlashcardsTag: CacheService.CacheTag { scopedTag("recent-flashcards") }

    static let legacyStatisticsKey = "flashcardStatistics"
    static let legacyReviewFlashcardsKey = "reviewFlashcards"
    static let legacyAllMyFlashcardsKey = "allMyFlashcards"

    /// Removes cache entries created by older builds that used global, non-user-scoped keys.
    /// New user-scoped caches are intentionally preserved.
    static func invalidateLegacyGlobalCaches(using cacheService: CacheService = .shared) {
        cacheService.delete(key: legacyStatisticsKey)
        cacheService.delete(key: legacyReviewFlashcardsKey)
        cacheService.delete(key: legacyAllMyFlashcardsKey)

        for key in cacheService.keys(for: CacheService.CacheTag(rawValue: "flashcard-statistics")) { cacheService.delete(key: key) }
        for key in cacheService.keys(for: CacheService.CacheTag(rawValue: "review-flashcards")) { cacheService.delete(key: key) }
        for key in cacheService.keys(for: CacheService.CacheTag(rawValue: "all-my-flashcards")) { cacheService.delete(key: key) }
        for key in cacheService.keys(for: CacheService.CacheTag(rawValue: "tier-flashcards")) { cacheService.delete(key: key) }
        for key in cacheService.keys(for: CacheService.CacheTag(rawValue: "recent-flashcards")) { cacheService.delete(key: key) }
    }

    static func statisticsKey() -> String {
        scopedKey("flashcardStatistics")
    }

    static func reviewFlashcardsKey() -> String {
        scopedKey("reviewFlashcards")
    }

    static func allMyFlashcardsKey() -> String {
        scopedKey("allMyFlashcards")
    }

    static func tierFlashcardsKey(reviewTier: String) -> String {
        scopedKey("allMyFlashcards.tier.\(reviewTier)")
    }

    static func recentFlashcardsKeyPrefix() -> String {
        scopedKey("recentFlashcards.limit.")
    }

    static func recentFlashcardsKey(limit: Int) -> String {
        "\(recentFlashcardsKeyPrefix())\(limit)"
    }

    static func loadStatistics(using cacheService: CacheService = .shared) -> StrapiStatistics? {
        cacheService.load(type: StrapiStatistics.self, from: statisticsKey())
    }

    static func storeStatistics(_ statistics: StrapiStatistics, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            statistics,
            key: statisticsKey(),
            ttl: nil,
            tags: [statisticsTag]
        )
    }

    static func loadReviewFlashcards(using cacheService: CacheService = .shared) -> [Flashcard]? {
        cacheService.load(type: [Flashcard].self, from: reviewFlashcardsKey())
    }

    static func storeReviewFlashcards(_ cards: [Flashcard], using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            cards,
            key: reviewFlashcardsKey(),
            ttl: nil,
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

    static func invalidateDueReviewCaches(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tags: [statisticsTag, reviewFlashcardsTag])
    }

    static func patchAfterFlashcardReview(updatedCard: Flashcard, using cacheService: CacheService = .shared) {
        // A review only changes one card and the aggregate statistics. Keep the large
        // flashcard caches usable instead of deleting everything.
        cacheService.invalidate(tags: [statisticsTag, tierFlashcardsTag])
        patchAllMyFlashcardsAfterReview(updatedCard: updatedCard, using: cacheService)
        patchReviewFlashcardsAfterReview(updatedCard: updatedCard, using: cacheService)
        patchRecentFlashcardsAfterReview(updatedCard: updatedCard, using: cacheService)
    }

    private static func patchAllMyFlashcardsAfterReview(updatedCard: Flashcard, using cacheService: CacheService) {
        guard var cards = loadAllMyFlashcards(using: cacheService) else { return }
        guard let index = cards.firstIndex(where: { $0.id == updatedCard.id }) else { return }
        cards[index] = updatedCard
        storeAllMyFlashcards(cards, using: cacheService)
    }

    private static func patchReviewFlashcardsAfterReview(updatedCard: Flashcard, using cacheService: CacheService) {
        guard var cards = loadReviewFlashcards(using: cacheService) else { return }
        cards.removeAll { $0.id == updatedCard.id }
        storeReviewFlashcards(cards, using: cacheService)
    }

    private static func patchRecentFlashcardsAfterReview(updatedCard: Flashcard, using cacheService: CacheService) {
        let prefix = recentFlashcardsKeyPrefix()
        let keys = cacheService.keys(for: recentFlashcardsTag)

        for key in keys where key.hasPrefix(prefix) {
            guard var cards = cacheService.loadIfValid(type: [Flashcard].self, from: key),
                  let index = cards.firstIndex(where: { $0.id == updatedCard.id }) else { continue }

            cards[index] = updatedCard
            cacheService.saveWithPolicy(
                cards,
                key: key,
                ttl: Policy.recentFlashcardsTTL,
                tags: [recentFlashcardsTag]
            )
        }
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
        let prefix = recentFlashcardsKeyPrefix()
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
