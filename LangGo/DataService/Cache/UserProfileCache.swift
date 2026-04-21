import Foundation

enum UserProfileCache {
    private enum Policy {
        static let currentUserTTL: CacheService.CacheTTL = .seconds(7 * 24 * 60 * 60)
    }

    static let currentUserTag = CacheService.CacheTag(rawValue: "current-user-profile")

    private static let currentUserKey = "currentUserProfile"

    static func loadCurrentUser(using cacheService: CacheService = .shared) -> StrapiUser? {
        cacheService.loadIfValid(type: StrapiUser.self, from: currentUserKey)
    }

    static func storeCurrentUser(_ user: StrapiUser, using cacheService: CacheService = .shared) {
        cacheService.saveWithPolicy(
            user,
            key: currentUserKey,
            ttl: Policy.currentUserTTL,
            tags: [currentUserTag]
        )
    }

    static func invalidate(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tag: currentUserTag)
    }
}
