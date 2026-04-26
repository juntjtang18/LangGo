import Foundation

enum PointGroupCache {
    private enum Policy {
        static let myPointGroupTTL: CacheService.CacheTTL = .seconds(60)
        static let leaderboardTTL: CacheService.CacheTTL = .seconds(60)
    }

    static let myPointGroupTag = CacheService.CacheTag(rawValue: "my-point-group")
    static let leaderboardTag = CacheService.CacheTag(rawValue: "point-group-leaderboard")

    static func myPointGroupKey(userID: Int, locale: String?) -> String {
        "myPointGroup.user.\(userID).locale.\(normalized(locale) ?? "default")"
    }

    static func leaderboardKey(viewerUserID: Int, pointGroupId: Int, locale: String?) -> String {
        "\(leaderboardKeyPrefix(viewerUserID: viewerUserID, locale: locale)).group.\(pointGroupId)"
    }

    static func loadMyPointGroup(
        userID: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> MyPointGroupData? {
        cacheService.loadIfValid(type: MyPointGroupData.self, from: myPointGroupKey(userID: userID, locale: locale))
    }

    static func loadStaleMyPointGroup(
        userID: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> MyPointGroupData? {
        cacheService.load(type: MyPointGroupData.self, from: myPointGroupKey(userID: userID, locale: locale))
    }

    static func isMyPointGroupExpired(
        userID: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> Bool {
        cacheService.isExpired(for: myPointGroupKey(userID: userID, locale: locale))
    }

    static func storeMyPointGroup(
        _ pointGroup: MyPointGroupData,
        userID: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) {
        cacheService.saveWithPolicy(
            pointGroup,
            key: myPointGroupKey(userID: userID, locale: locale),
            ttl: Policy.myPointGroupTTL,
            tags: [myPointGroupTag]
        )

        removeLeaderboardEntries(viewerUserID: userID, locale: locale, using: cacheService)

        guard let pointGroupId = pointGroup.pointGroup?.id else { return }
        storeLeaderboard(
            leaderboard(from: pointGroup),
            viewerUserID: userID,
            pointGroupId: pointGroupId,
            locale: locale,
            using: cacheService
        )
    }

    static func loadLeaderboard(
        viewerUserID: Int,
        pointGroupId: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> PointGroupLeaderboardData? {
        cacheService.loadIfValid(
            type: PointGroupLeaderboardData.self,
            from: leaderboardKey(viewerUserID: viewerUserID, pointGroupId: pointGroupId, locale: locale)
        )
    }

    static func loadStaleLeaderboard(
        viewerUserID: Int,
        pointGroupId: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> PointGroupLeaderboardData? {
        cacheService.load(
            type: PointGroupLeaderboardData.self,
            from: leaderboardKey(viewerUserID: viewerUserID, pointGroupId: pointGroupId, locale: locale)
        )
    }

    static func isLeaderboardExpired(
        viewerUserID: Int,
        pointGroupId: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) -> Bool {
        cacheService.isExpired(
            for: leaderboardKey(viewerUserID: viewerUserID, pointGroupId: pointGroupId, locale: locale)
        )
    }

    static func storeLeaderboard(
        _ leaderboard: PointGroupLeaderboardData,
        viewerUserID: Int,
        pointGroupId: Int,
        locale: String?,
        using cacheService: CacheService = .shared
    ) {
        cacheService.saveWithPolicy(
            leaderboard,
            key: leaderboardKey(viewerUserID: viewerUserID, pointGroupId: pointGroupId, locale: locale),
            ttl: Policy.leaderboardTTL,
            tags: [leaderboardTag]
        )
    }

    static func invalidateAll(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tags: [myPointGroupTag, leaderboardTag])
    }

    static func leaderboard(from pointGroup: MyPointGroupData) -> PointGroupLeaderboardData {
        PointGroupLeaderboardData(
            pointGroup: pointGroup.pointGroup,
            currentUserPosition: pointGroup.myMembership.positionInGroup,
            groupMemberCount: pointGroup.myMembership.groupMemberCount,
            leaderboard: pointGroup.leaderboard
        )
    }

    private static func removeLeaderboardEntries(
        viewerUserID: Int,
        locale: String?,
        using cacheService: CacheService
    ) {
        let prefix = leaderboardKeyPrefix(viewerUserID: viewerUserID, locale: locale)
        let keys = cacheService.keys(for: leaderboardTag).filter { $0.hasPrefix(prefix) }

        for key in keys {
            cacheService.delete(key: key)
        }
    }

    private static func leaderboardKeyPrefix(viewerUserID: Int, locale: String?) -> String {
        "pointGroupLeaderboard.user.\(viewerUserID).locale.\(normalized(locale) ?? "default")"
    }

    private static func normalized(_ locale: String?) -> String? {
        guard let locale else { return nil }
        let trimmed = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
