import Foundation
import Testing
@testable import LangGo

struct UserSnapshotCacheTests {
    @Test
    func loadStaleReturnsExpiredSnapshotWhileLoadReturnsNil() async throws {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let locale = "test-expired-\(UUID().uuidString)"
        let expected = UserRankSnapshot(
            id: 8,
            userid: "60",
            record_date: "2026-04-26T09:00:00.000Z",
            total_points: 75,
            points_add: 12,
            word_count: 30,
            word_add: 4,
            article_count: 2,
            article_add: 1,
            level_no: 1,
            level_change: 0,
            level_title: "幼儿园小班",
            group_id: 1,
            group_no: 1,
            group_rank: 3,
            group_rank_title: "学习起步者",
            group_rank_change: 1,
            period_points: 20,
            period_points_change: 2
        )

        defer {
            cache.invalidate(tag: UserSnapshotCache.snapshotTag)
        }

        cache.saveWithPolicy(
            expected,
            key: UserSnapshotCache.snapshotKey(locale: locale),
            ttl: .seconds(0.1),
            tags: [UserSnapshotCache.snapshotTag]
        )
        try await Task.sleep(for: .milliseconds(250))

        let stale = UserSnapshotCache.loadStale(locale: locale, using: cache)
        let valid = UserSnapshotCache.load(locale: locale, using: cache)
        let isExpired = UserSnapshotCache.isExpired(locale: locale, using: cache)

        #expect(valid == nil)
        #expect(stale?.total_points == expected.total_points)
        #expect(stale?.word_add == expected.word_add)
        #expect(stale?.group_rank_title == expected.group_rank_title)
        #expect(isExpired)
    }

    @Test
    func isExpiredIsFalseForFreshSnapshot() {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let locale = "test-fresh-\(UUID().uuidString)"
        let expected = UserRankSnapshot(
            id: 8,
            userid: "60",
            record_date: "2026-04-26T09:00:00.000Z",
            total_points: 88,
            points_add: 6,
            word_count: 42,
            word_add: 3,
            article_count: 5,
            article_add: 1,
            level_no: 2,
            level_change: 1,
            level_title: "学习达人",
            group_id: 1,
            group_no: 1,
            group_rank: 2,
            group_rank_title: "学习达人",
            group_rank_change: 0,
            period_points: 12,
            period_points_change: 0
        )

        defer {
            cache.invalidate(tag: UserSnapshotCache.snapshotTag)
        }

        UserSnapshotCache.store(expected, locale: locale, using: cache)

        let valid = UserSnapshotCache.load(locale: locale, using: cache)
        let stale = UserSnapshotCache.loadStale(locale: locale, using: cache)
        let isExpired = UserSnapshotCache.isExpired(locale: locale, using: cache)

        #expect(valid?.total_points == expected.total_points)
        #expect(valid?.word_add == expected.word_add)
        #expect(valid?.group_rank_title == expected.group_rank_title)
        #expect(stale?.total_points == expected.total_points)
        #expect(stale?.word_add == expected.word_add)
        #expect(stale?.group_rank_title == expected.group_rank_title)
        #expect(isExpired == false)
    }

    @Test
    func decodesSnapshotWhenRecordDateIsNullAndPeriodFieldsExist() throws {
        let json = """
        {"data":{"latest_snapshot":{"id":14,"userid":"60","record_date":null,"total_points":5,"points_add":5,"word_count":0,"word_add":0,"article_count":0,"article_add":0,"level_no":1,"level_change":0,"level_title":"Kindgarden I","group_id":1,"group_no":1,"group_rank":1,"group_rank_title":"Starter","group_rank_change":0,"period_points":9,"period_points_change":0}}}
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(RankUserResponse.self, from: Data(json.utf8))

        #expect(response.data.latest_snapshot.record_date == nil)
        #expect(response.data.latest_snapshot.level_title == "Kindgarden I")
        #expect(response.data.latest_snapshot.period_points == 9)
        #expect(response.data.latest_snapshot.period_points_change == 0)
        #expect(response.data.latest_snapshot.rankText == "Kindgarden I")
    }
}
