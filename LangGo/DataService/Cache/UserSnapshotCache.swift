import Foundation

extension Notification.Name {
    static let userSnapshotDidChange = Notification.Name("com.langGo.swift.userSnapshotDidChange")
}

enum UserSnapshotCache {
    private enum Policy {
        static let snapshotTTL: CacheService.CacheTTL = .seconds(60)
        static let pointsPerWordAdded = 1
    }

    static let snapshotTag = CacheService.CacheTag(rawValue: "user-snapshot")

    static func snapshotKey(locale: String?) -> String {
        let normalizedLocale = normalized(locale) ?? "default"
        return "userSnapshot.locale.\(normalizedLocale)"
    }

    static func load(locale: String?, using cacheService: CacheService = .shared) -> UserRankSnapshot? {
        cacheService.loadIfValid(type: UserRankSnapshot.self, from: snapshotKey(locale: locale))
    }

    static func loadStale(locale: String?, using cacheService: CacheService = .shared) -> UserRankSnapshot? {
        cacheService.load(type: UserRankSnapshot.self, from: snapshotKey(locale: locale))
    }

    static func isExpired(locale: String?, using cacheService: CacheService = .shared) -> Bool {
        cacheService.isExpired(for: snapshotKey(locale: locale))
    }

    static func store(_ snapshot: UserRankSnapshot, locale: String?, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            snapshot,
            key: snapshotKey(locale: locale),
            ttl: Policy.snapshotTTL,
            tags: [snapshotTag]
        )
        NotificationCenter.default.post(name: .userSnapshotDidChange, object: normalized(locale))
    }

    static func invalidate(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tag: snapshotTag)
    }

    static func patch(
        locale: String?,
        using cacheService: CacheService = .shared,
        update: (UserRankSnapshot) -> UserRankSnapshot
    ) {
        guard let existing = load(locale: locale, using: cacheService) else { return }
        store(update(existing), locale: locale, using: cacheService)
    }

    static func patchAfterWordAdded(locales: [String?], using cacheService: CacheService = .shared) {
        let deduplicatedLocales = uniqueLocales(from: locales)
        for locale in deduplicatedLocales {
            patch(locale: locale, using: cacheService) { existing in
                UserRankSnapshot(
                    id: existing.id,
                    userid: existing.userid,
                    record_date: existing.record_date,
                    total_points: existing.total_points + Policy.pointsPerWordAdded,
                    points_add: existing.points_add + Policy.pointsPerWordAdded,
                    word_count: existing.word_count + 1,
                    word_add: existing.word_add + 1,
                    article_count: existing.article_count,
                    article_add: existing.article_add,
                    level_no: existing.level_no,
                    level_change: existing.level_change,
                    level_title: existing.level_title,
                    group_id: existing.group_id,
                    group_no: existing.group_no,
                    group_rank: existing.group_rank,
                    group_rank_title: existing.group_rank_title,
                    group_rank_change: existing.group_rank_change
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
