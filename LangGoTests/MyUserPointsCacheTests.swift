import Foundation
import Testing
@testable import LangGo

struct MyUserPointsCacheTests {
    @Test
    func loadStaleReturnsExpiredPayloadWhileLoadReturnsNil() async throws {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let locale = "test-expired-\(UUID().uuidString)"
        let expected = MyUserPointsAttributes(
            record_date: "2026-04-26T09:00:00.000Z",
            points: 75,
            points_add: 12,
            word_count: 30,
            word_add: 4,
            article_count: 2,
            article_add: 1,
            group_rank_change: 1,
            rank: 3,
            rank_change: 1,
            rank_text: "学习起步者"
        )

        defer {
            cache.invalidate(tag: MyUserPointsCache.userPointsTag)
        }

        cache.saveWithPolicy(
            expected,
            key: MyUserPointsCache.userPointsKey(locale: locale),
            ttl: .seconds(0.1),
            tags: [MyUserPointsCache.userPointsTag]
        )
        try await Task.sleep(for: .milliseconds(250))

        let stale = MyUserPointsCache.loadStale(locale: locale, using: cache)
        let valid = MyUserPointsCache.load(locale: locale, using: cache)
        let isExpired = MyUserPointsCache.isExpired(locale: locale, using: cache)

        #expect(valid == nil)
        #expect(stale?.points == expected.points)
        #expect(stale?.word_add == expected.word_add)
        #expect(stale?.rank_text == expected.rank_text)
        #expect(isExpired)
    }

    @Test
    func isExpiredIsFalseForFreshPayload() {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let locale = "test-fresh-\(UUID().uuidString)"
        let expected = MyUserPointsAttributes(
            record_date: "2026-04-26T09:00:00.000Z",
            points: 88,
            points_add: 6,
            word_count: 42,
            word_add: 3,
            article_count: 5,
            article_add: 1,
            group_rank_change: 0,
            rank: 2,
            rank_change: 0,
            rank_text: "学习达人"
        )

        defer {
            cache.invalidate(tag: MyUserPointsCache.userPointsTag)
        }

        MyUserPointsCache.store(expected, locale: locale, using: cache)

        let valid = MyUserPointsCache.load(locale: locale, using: cache)
        let stale = MyUserPointsCache.loadStale(locale: locale, using: cache)
        let isExpired = MyUserPointsCache.isExpired(locale: locale, using: cache)

        #expect(valid?.points == expected.points)
        #expect(valid?.word_add == expected.word_add)
        #expect(valid?.rank_text == expected.rank_text)
        #expect(stale?.points == expected.points)
        #expect(stale?.word_add == expected.word_add)
        #expect(stale?.rank_text == expected.rank_text)
        #expect(isExpired == false)
    }
}
