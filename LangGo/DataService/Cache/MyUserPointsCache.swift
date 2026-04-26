import Foundation

extension Notification.Name {
    static let myUserPointsDidChange = Notification.Name("com.langGo.swift.myUserPointsDidChange")
}

enum MyUserPointsCache {
    private enum Policy {
        static let userPointsTTL: CacheService.CacheTTL = .seconds(60)
        static let pointsPerWordAdded = 1
    }

    static let userPointsTag = CacheService.CacheTag(rawValue: "my-user-points")

    static func userPointsKey(locale: String?) -> String {
        let normalizedLocale = normalized(locale) ?? "default"
        return "myUserPoints.locale.\(normalizedLocale)"
    }

    static func load(locale: String?, using cacheService: CacheService = .shared) -> MyUserPointsAttributes? {
        cacheService.loadIfValid(type: MyUserPointsAttributes.self, from: userPointsKey(locale: locale))
    }

    static func loadStale(locale: String?, using cacheService: CacheService = .shared) -> MyUserPointsAttributes? {
        cacheService.load(type: MyUserPointsAttributes.self, from: userPointsKey(locale: locale))
    }

    static func isExpired(locale: String?, using cacheService: CacheService = .shared) -> Bool {
        cacheService.isExpired(for: userPointsKey(locale: locale))
    }

    static func store(_ points: MyUserPointsAttributes, locale: String?, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            points,
            key: userPointsKey(locale: locale),
            ttl: Policy.userPointsTTL,
            tags: [userPointsTag]
        )
        NotificationCenter.default.post(name: .myUserPointsDidChange, object: normalized(locale))
    }

    static func invalidate(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tag: userPointsTag)
    }

    static func patch(
        locale: String?,
        using cacheService: CacheService = .shared,
        update: (MyUserPointsAttributes) -> MyUserPointsAttributes
    ) {
        guard let existing = load(locale: locale, using: cacheService) else { return }
        store(update(existing), locale: locale, using: cacheService)
    }

    static func patchAfterWordAdded(locales: [String?], using cacheService: CacheService = .shared) {
        let deduplicatedLocales = uniqueLocales(from: locales)
        for locale in deduplicatedLocales {
            patch(locale: locale, using: cacheService) { existing in
                MyUserPointsAttributes(
                    record_date: existing.record_date,
                    points: existing.points + Policy.pointsPerWordAdded,
                    points_add: existing.points_add + Policy.pointsPerWordAdded,
                    word_count: existing.word_count + 1,
                    word_add: existing.word_add + 1,
                    article_count: existing.article_count,
                    article_add: existing.article_add,
                    group_rank_change: existing.group_rank_change,
                    rank: existing.rank,
                    rank_change: existing.rank_change,
                    rank_text: existing.rank_text
                )
            }
        }
    }

    private static func uniqueLocales(from locales: [String?]) -> [String?] {
        var seen = Set<String>()
        var result: [String?] = []

        for locale in locales {
            let key = normalized(locale) ?? "default"
            guard seen.insert(key).inserted else { continue }
            result.append(normalized(locale))
        }

        if !seen.contains("default") {
            result.append(nil)
        }

        return result
    }

    private static func normalized(_ locale: String?) -> String? {
        guard let locale else { return nil }
        let trimmed = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
