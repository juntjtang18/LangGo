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

    static func patchCurrentUser(
        using cacheService: CacheService = .shared,
        update: @escaping (StrapiUser) -> StrapiUser
    ) async {
        let existingUser = await MainActor.run { UserSessionManager.shared.currentUser }
            ?? loadCurrentUser(using: cacheService)

        guard let existingUser else { return }

        let updatedUser = update(existingUser)
        storeCurrentUser(updatedUser, using: cacheService)

        await MainActor.run {
            UserSessionManager.shared.login(user: updatedUser)
        }
    }

    static func patchCurrentUserProfile(
        using cacheService: CacheService = .shared,
        update: @escaping (UserProfileAttributes?) -> UserProfileAttributes
    ) async {
        await patchCurrentUser(using: cacheService) { currentUser in
            StrapiUser(
                id: currentUser.id,
                username: currentUser.username,
                email: currentUser.email,
                user_profile: update(currentUser.user_profile)
            )
        }
    }

    static func mergeProfile(
        from existing: UserProfileAttributes?,
        applying payload: UserProfileUpdatePayload
    ) -> UserProfileAttributes {
        UserProfileAttributes(
            proficiency: payload.proficiency ?? existing?.proficiency,
            reminder_enabled: payload.reminder_enabled ?? existing?.reminder_enabled,
            baseLanguage: payload.baseLanguage,
            telephone: payload.telephone ?? existing?.telephone,
            bio: payload.bio ?? existing?.bio,
            avatar_img: existing?.avatar_img,
            visible_on_ladder: payload.visible_on_ladder ?? existing?.visible_on_ladder
        )
    }
}
