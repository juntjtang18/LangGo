import Foundation
import Testing
@testable import LangGo

struct PointGroupCacheTests {
    @Test
    func loadStaleMyPointGroupReturnsExpiredPayloadWhileLoadReturnsNil() async throws {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let userID = 101
        let locale = "test-expired-\(UUID().uuidString)"
        let expected = sampleMyPointGroup(groupID: 9, rankTitle: "Starter")

        defer {
            PointGroupCache.invalidateAll(using: cache)
        }

        cache.saveWithPolicy(
            expected,
            key: PointGroupCache.myPointGroupKey(userID: userID, locale: locale),
            ttl: .seconds(0.1),
            tags: [PointGroupCache.myPointGroupTag]
        )
        try await Task.sleep(for: .milliseconds(250))

        let stale = PointGroupCache.loadStaleMyPointGroup(userID: userID, locale: locale, using: cache)
        let valid = PointGroupCache.loadMyPointGroup(userID: userID, locale: locale, using: cache)
        let isExpired = PointGroupCache.isMyPointGroupExpired(userID: userID, locale: locale, using: cache)

        #expect(valid == nil)
        #expect(stale?.pointGroup?.id == expected.pointGroup?.id)
        #expect(stale?.myMembership.positionInGroup == expected.myMembership.positionInGroup)
        #expect(stale?.leaderboard.count == expected.leaderboard.count)
        #expect(isExpired)
    }

    @Test
    func storeMyPointGroupSeedsLeaderboardCacheForSameUserAndLocale() {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let userID = 202
        let locale = "zh-Hans"
        let pointGroup = sampleMyPointGroup(groupID: 15, rankTitle: "学习达人")

        defer {
            PointGroupCache.invalidateAll(using: cache)
        }

        PointGroupCache.storeMyPointGroup(pointGroup, userID: userID, locale: locale, using: cache)

        let leaderboard = PointGroupCache.loadLeaderboard(
            viewerUserID: userID,
            pointGroupId: 15,
            locale: locale,
            using: cache
        )

        #expect(leaderboard?.pointGroup?.id == 15)
        #expect(leaderboard?.currentUserPosition == pointGroup.myMembership.positionInGroup)
        #expect(leaderboard?.groupMemberCount == pointGroup.myMembership.groupMemberCount)
        #expect(leaderboard?.leaderboard.count == pointGroup.leaderboard.count)
        #expect(leaderboard?.leaderboard.first?.isCurrentUser == false)
        #expect(
            leaderboard?.leaderboard.first(where: { $0.isCurrentUser })?.position
                == pointGroup.myMembership.positionInGroup
        )
    }

    @Test
    func userAwareKeysKeepDifferentUsersSeparated() {
        let cache = CacheService(
            memoryStore: MemoryCacheStore(),
            diskStore: DiskCacheStore(),
            indexStore: CacheIndexStore()
        )
        let locale = "en"

        defer {
            PointGroupCache.invalidateAll(using: cache)
        }

        PointGroupCache.storeMyPointGroup(
            sampleMyPointGroup(groupID: 1, rankTitle: "Starter"),
            userID: 1,
            locale: locale,
            using: cache
        )
        PointGroupCache.storeMyPointGroup(
            sampleMyPointGroup(groupID: 2, rankTitle: "Advanced"),
            userID: 2,
            locale: locale,
            using: cache
        )

        let firstUserGroup = PointGroupCache.loadMyPointGroup(userID: 1, locale: locale, using: cache)
        let secondUserGroup = PointGroupCache.loadMyPointGroup(userID: 2, locale: locale, using: cache)

        #expect(firstUserGroup?.pointGroup?.id == 1)
        #expect(secondUserGroup?.pointGroup?.id == 2)
    }

    private func sampleMyPointGroup(groupID: Int, rankTitle: String) -> MyPointGroupData {
        MyPointGroupData(
            pointGroup: PointGroupSummary(
                id: groupID,
                groupNo: 3,
                groupRank: PointGroupRank(
                    id: 7,
                    title: rankTitle,
                    minPeriodPoints: 20
                )
            ),
            myMembership: MyPointGroupMembership(
                userPointGroupId: 88,
                periodPoints: 34,
                positionInGroup: 2,
                groupMemberCount: 3
            ),
            leaderboard: [
                PointGroupLeaderboardMember(
                    position: 1,
                    periodPoints: 40,
                    isCurrentUser: false,
                    userPointGroupId: 81,
                    user: sampleUser(id: 11, username: "alice")
                ),
                PointGroupLeaderboardMember(
                    position: 2,
                    periodPoints: 34,
                    isCurrentUser: true,
                    userPointGroupId: 88,
                    user: sampleUser(id: 22, username: "james")
                ),
                PointGroupLeaderboardMember(
                    position: 3,
                    periodPoints: 18,
                    isCurrentUser: false,
                    userPointGroupId: 93,
                    user: sampleUser(id: 33, username: "bob")
                )
            ]
        )
    }

    private func sampleUser(id: Int, username: String) -> PointGroupLeaderboardUser {
        PointGroupLeaderboardUser(
            id: id,
            username: username,
            email: "\(username)@example.com",
            honorTitle: PointGroupHonorTitle(id: 5, title: "Sharp Learner"),
            userProfile: PointGroupUserProfile(
                id: id,
                baseLanguage: "en",
                avatarImage: PointGroupAvatarImage(id: id, url: "/uploads/\(username).png")
            )
        )
    }
}
