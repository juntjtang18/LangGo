//
//  UserSnapshotService.swift
//  LangGo
//
//  Owns the current user's rank snapshot data flow for UI consumers.
//  UI observes this service and never reads UserSnapshotCache directly.
//

import Foundation
import os

@MainActor
final class UserSnapshotService: ObservableObject {
    @Published private(set) var latestSnapshot: UserRankSnapshot?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "UserSnapshotService")
    private let networkManager: NetworkManager
    private let cacheService: CacheService
    private var loadedLocale: String?
    private var snapshotTasks: [String: Task<UserRankSnapshot?, Error>] = [:]

    init(
        networkManager: NetworkManager = .shared,
        cacheService: CacheService = .shared
    ) {
        self.networkManager = networkManager
        self.cacheService = cacheService
    }

    /// Synchronous UI read API.
    /// Returns the service-owned value only. It does not expose cache semantics to UI.
    func currentSnapshot(locale: String? = nil) -> UserRankSnapshot? {
        guard normalizedLocale(locale) == normalizedLocale(loadedLocale) else { return nil }
        return latestSnapshot
    }

    /// Loads cached/stale data first for stable UI, then refreshes from backend when cache is missing or expired.
    func loadSnapshot(locale: String? = nil) async {
        let locale = normalizedLocale(locale)
        loadedLocale = locale

        if let cached = UserSnapshotCache.loadStale(locale: locale, using: cacheService) {
            latestSnapshot = cached
        }

        guard latestSnapshot == nil || UserSnapshotCache.isExpired(locale: locale, using: cacheService) else {
            logger.debug("loadSnapshot fresh cache is valid; skip network locale=\(locale ?? "nil", privacy: .public)")
            return
        }

        do {
            _ = try await refreshSnapshot(locale: locale)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                logger.debug("Rank snapshot refresh cancelled; keeping cached snapshot.")
                return
            }

            logger.error("Failed to load rank snapshot: \(error.localizedDescription, privacy: .public)")

        }
    }

    /// Forces a backend refresh, writes cache, and publishes the fresh value.
    @discardableResult
    func refreshSnapshot(locale: String? = nil) async throws -> UserRankSnapshot? {
        let locale = normalizedLocale(locale)
        loadedLocale = locale
        let taskKey = snapshotTaskKey(locale)

        if let existingTask = snapshotTasks[taskKey] {
            logger.debug("Joining existing rank snapshot task for locale \(taskKey, privacy: .public).")
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> UserRankSnapshot? in
            guard let self else { throw CancellationError() }
            return try await self.fetchSnapshotFromNetwork(locale: locale)
        }
        snapshotTasks[taskKey] = task
        defer { snapshotTasks[taskKey] = nil }

        let snapshot = try await task.value
        if let snapshot {
            UserSnapshotCache.store(snapshot, locale: locale, using: cacheService)
        } else {
            UserSnapshotCache.invalidate(using: cacheService)
        }
        latestSnapshot = snapshot
        return snapshot
    }

    @discardableResult
    func refreshUserSnapshot(locale: String? = nil) async throws -> UserRankSnapshot? {
        try await refreshSnapshot(locale: locale)
    }

    func invalidateSnapshot(locale: String? = nil) {
        UserSnapshotCache.invalidate(using: cacheService)
        if normalizedLocale(locale) == normalizedLocale(loadedLocale) || locale == nil {
            latestSnapshot = nil
        }
    }

    private func normalizedLocale(_ locale: String?) -> String? {
        guard let locale, !locale.isEmpty else { return nil }
        return locale
    }

    private func snapshotTaskKey(_ locale: String?) -> String {
        locale ?? "default"
    }

    private func fetchSnapshotFromNetwork(locale: String?) async throws -> UserRankSnapshot? {
        logger.debug("Fetching rank snapshot for current user.")

        var components = URLComponents(string: "\(Config.strapiBaseUrl)/api/rank/me")
        if let locale {
            components?.queryItems = [URLQueryItem(name: "locale", value: locale)]
        }

        guard let url = components?.url else { throw URLError(.badURL) }

        let response: RankUserResponse = try await networkManager.fetchDirect(from: url)
        return response.data.latest_snapshot
    }
}
