import Foundation
import os

@MainActor
final class PointGroupService: ObservableObject {
    @Published private(set) var myPointGroup: MyPointGroupData?
    @Published private(set) var pointGroupLeaderboard: PointGroupLeaderboardData?

    private struct MyPointGroupContext: Equatable {
        let userID: Int
        let locale: String?
    }

    private struct LeaderboardContext: Equatable {
        let userID: Int
        let pointGroupId: Int
        let locale: String?
    }

    private let logger = Logger(subsystem: "com.langGo.swift", category: "PointGroupService")
    private let networkManager: NetworkManager
    private let cacheService: CacheService

    private var loadedMyPointGroupContext: MyPointGroupContext?
    private var loadedLeaderboardContext: LeaderboardContext?

    init(
        networkManager: NetworkManager = .shared,
        cacheService: CacheService = .shared
    ) {
        self.networkManager = networkManager
        self.cacheService = cacheService
    }

    func currentMyPointGroup(locale: String? = nil) -> MyPointGroupData? {
        guard let context = makeMyPointGroupContext(locale: locale),
              loadedMyPointGroupContext == context else {
            return nil
        }

        return myPointGroup
    }

    func currentPointGroupLeaderboard(pointGroupId: Int, locale: String? = nil) -> PointGroupLeaderboardData? {
        guard let context = makeLeaderboardContext(pointGroupId: pointGroupId, locale: locale),
              loadedLeaderboardContext == context else {
            return nil
        }

        return pointGroupLeaderboard
    }

    func loadMyPointGroup(locale: String? = nil) async {
        let locale = normalizedLocale(locale)
        guard let context = makeMyPointGroupContext(locale: locale) else {
            clearPublishedState()
            return
        }

        if loadedMyPointGroupContext != context {
            myPointGroup = nil
            pointGroupLeaderboard = nil
            loadedLeaderboardContext = nil
        }
        loadedMyPointGroupContext = context

        if let cached = PointGroupCache.loadStaleMyPointGroup(
            userID: context.userID,
            locale: locale,
            using: cacheService
        ) {
            myPointGroup = cached
            syncLeaderboardFromMyPointGroup(cached, context: context)
        }

        guard myPointGroup == nil
                || PointGroupCache.isMyPointGroupExpired(
                    userID: context.userID,
                    locale: locale,
                    using: cacheService
                ) else {
            return
        }

        do {
            _ = try await refreshMyPointGroup(locale: locale)
        } catch {
            logger.error("Failed to load point group: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func refreshMyPointGroup(locale: String? = nil) async throws -> MyPointGroupData {
        let locale = normalizedLocale(locale)
        guard let context = makeMyPointGroupContext(locale: locale) else {
            throw URLError(.userAuthenticationRequired)
        }

        logger.debug("Fetching current user's point group.")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/my-point-group")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let response: MyPointGroupResponse = try await networkManager.fetchDirect(from: url)
        let data = response.data

        PointGroupCache.storeMyPointGroup(data, userID: context.userID, locale: locale, using: cacheService)
        loadedMyPointGroupContext = context
        myPointGroup = data
        syncLeaderboardFromMyPointGroup(data, context: context)
        return data
    }

    func loadPointGroupLeaderboard(pointGroupId: Int, locale: String? = nil) async {
        let locale = normalizedLocale(locale)
        guard let context = makeLeaderboardContext(pointGroupId: pointGroupId, locale: locale) else {
            pointGroupLeaderboard = nil
            loadedLeaderboardContext = nil
            return
        }

        if loadedLeaderboardContext != context {
            pointGroupLeaderboard = nil
        }
        loadedLeaderboardContext = context

        if let cached = PointGroupCache.loadStaleLeaderboard(
            viewerUserID: context.userID,
            pointGroupId: pointGroupId,
            locale: locale,
            using: cacheService
        ) {
            pointGroupLeaderboard = cached
        }

        guard pointGroupLeaderboard == nil
                || PointGroupCache.isLeaderboardExpired(
                    viewerUserID: context.userID,
                    pointGroupId: pointGroupId,
                    locale: locale,
                    using: cacheService
                ) else {
            return
        }

        do {
            _ = try await refreshPointGroupLeaderboard(pointGroupId: pointGroupId, locale: locale)
        } catch {
            logger.error("Failed to load point group leaderboard: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func refreshPointGroupLeaderboard(pointGroupId: Int, locale: String? = nil) async throws -> PointGroupLeaderboardData {
        let locale = normalizedLocale(locale)
        guard let context = makeLeaderboardContext(pointGroupId: pointGroupId, locale: locale) else {
            throw URLError(.userAuthenticationRequired)
        }

        logger.debug("Fetching point group leaderboard for group ID \(pointGroupId).")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/point-groups/\(pointGroupId)/leaderboard")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let response: PointGroupLeaderboardResponse = try await networkManager.fetchDirect(from: url)
        let data = response.data

        PointGroupCache.storeLeaderboard(
            data,
            viewerUserID: context.userID,
            pointGroupId: pointGroupId,
            locale: locale,
            using: cacheService
        )
        loadedLeaderboardContext = context
        pointGroupLeaderboard = data
        return data
    }

    func invalidateAllPointGroupData() {
        PointGroupCache.invalidateAll(using: cacheService)
        clearPublishedState()
    }

    private func syncLeaderboardFromMyPointGroup(_ pointGroup: MyPointGroupData, context: MyPointGroupContext) {
        guard let pointGroupId = pointGroup.pointGroup?.id else {
            pointGroupLeaderboard = nil
            loadedLeaderboardContext = nil
            return
        }

        let leaderboardContext = LeaderboardContext(
            userID: context.userID,
            pointGroupId: pointGroupId,
            locale: context.locale
        )
        loadedLeaderboardContext = leaderboardContext
        pointGroupLeaderboard = PointGroupCache.leaderboard(from: pointGroup)
    }

    private func makeMyPointGroupContext(locale: String?) -> MyPointGroupContext? {
        guard let userID = currentUserID() else { return nil }
        return MyPointGroupContext(userID: userID, locale: normalizedLocale(locale))
    }

    private func makeLeaderboardContext(pointGroupId: Int, locale: String?) -> LeaderboardContext? {
        guard let userID = currentUserID() else { return nil }
        return LeaderboardContext(
            userID: userID,
            pointGroupId: pointGroupId,
            locale: normalizedLocale(locale)
        )
    }

    private func currentUserID() -> Int? {
        if let sessionUserID = UserSessionManager.shared.currentUser?.id {
            return sessionUserID
        }

        let persistedUserID = UserDefaults.standard.integer(forKey: "userId")
        return persistedUserID > 0 ? persistedUserID : nil
    }

    private func clearPublishedState() {
        myPointGroup = nil
        pointGroupLeaderboard = nil
        loadedMyPointGroupContext = nil
        loadedLeaderboardContext = nil
    }

    private func normalizedLocale(_ locale: String?) -> String? {
        guard let locale, !locale.isEmpty else { return nil }
        return locale
    }
}
