import Foundation

enum SettingsCache {
    private enum Policy {
        static let proficiencyLevelsTTL: CacheService.CacheTTL = .seconds(7 * 24 * 60 * 60)
    }

    static let proficiencyLevelsTag = CacheService.CacheTag(rawValue: "proficiency-levels")

    static func proficiencyLevelsKey(locale: String) -> String {
        "proficiencyLevels.locale.\(locale)"
    }

    static func loadProficiencyLevels(
        locale: String,
        using cacheService: CacheService = .shared
    ) -> [ProficiencyLevel]? {
        cacheService.loadIfValid(type: [ProficiencyLevel].self, from: proficiencyLevelsKey(locale: locale))
    }

    static func storeProficiencyLevels(
        _ levels: [ProficiencyLevel],
        locale: String,
        using cacheService: CacheService = .shared
    ) {
        cacheService.saveWithPolicy(
            levels,
            key: proficiencyLevelsKey(locale: locale),
            ttl: Policy.proficiencyLevelsTTL,
            tags: [proficiencyLevelsTag]
        )
    }

    static func invalidateProficiencyLevels(using cacheService: CacheService = .shared) {
        cacheService.invalidate(tag: proficiencyLevelsTag)
    }
}
