//
//  UserPointsService.swift
//  LangGo
//
//  Owns the current user's points data flow for UI consumers.
//  UI observes this service and never reads MyUserPointsCache directly.
//

import Foundation
import os

@MainActor
final class UserPointsService: ObservableObject {
    @Published private(set) var myUserPoints: MyUserPointsAttributes?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "UserPointsService")
    private let networkManager: NetworkManager
    private let cacheService: CacheService
    private var loadedLocale: String?

    init(
        networkManager: NetworkManager = .shared,
        cacheService: CacheService = .shared
    ) {
        self.networkManager = networkManager
        self.cacheService = cacheService
    }

    /// Synchronous UI read API.
    /// Returns the service-owned value only. It does not expose cache semantics to UI.
    func currentMyUserPoints(locale: String? = nil) -> MyUserPointsAttributes? {
        guard normalizedLocale(locale) == normalizedLocale(loadedLocale) else { return nil }
        return myUserPoints
    }

    /// Loads cached/stale data first for stable UI, then refreshes from backend when cache is missing or expired.
    func loadMyUserPoints(locale: String? = nil) async {
        let locale = normalizedLocale(locale)
        loadedLocale = locale

        if let cachedPoints = MyUserPointsCache.loadStale(locale: locale, using: cacheService) {
            myUserPoints = cachedPoints
        }

        guard myUserPoints == nil || MyUserPointsCache.isExpired(locale: locale, using: cacheService) else {
            return
        }

        do {
            _ = try await refreshMyUserPoints(locale: locale)
        } catch {
            logger.error("Failed to load user points: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forces a backend refresh, writes cache, and publishes the fresh value.
    @discardableResult
    func refreshMyUserPoints(locale: String? = nil) async throws -> MyUserPointsAttributes? {
        let locale = normalizedLocale(locale)
        loadedLocale = locale

        logger.debug("Fetching current user points.")
        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/my-user-points")
        if let locale, !locale.isEmpty {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        let response: MyUserPointsResponse = try await networkManager.fetchDirect(from: url)
        let attributes = response.data?.attributes

        if let attributes {
            MyUserPointsCache.store(attributes, locale: locale, using: cacheService)
        }

        myUserPoints = attributes
        NotificationCenter.default.post(name: .myUserPointsDidChange, object: nil)
        return attributes
    }

    func invalidateMyUserPoints(locale: String? = nil) {
        MyUserPointsCache.invalidate(using: cacheService)
        if normalizedLocale(locale) == normalizedLocale(loadedLocale) || locale == nil {
            myUserPoints = nil
        }
    }

    private func normalizedLocale(_ locale: String?) -> String? {
        guard let locale, !locale.isEmpty else { return nil }
        return locale
    }
}
