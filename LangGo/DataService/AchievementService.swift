import Foundation
import os

@MainActor
final class AchievementService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "AchievementService")
    private let networkManager: NetworkManager
    private var achievedTask: Task<[AchievementDTO], Error>?
    private var notAchievedTask: Task<[AchievementDTO], Error>?

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    func fetchAchieved(locale: String? = nil) async throws -> [AchievementDTO] {
        if let existingTask = achievedTask {
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> [AchievementDTO] in
            guard let self else { throw CancellationError() }
            return try await self.fetchAchievements(path: "/api/achievements-achieved", locale: locale)
        }
        achievedTask = task
        defer { achievedTask = nil }
        return try await task.value
    }

    func fetchNotAchieved(locale: String? = nil) async throws -> [AchievementDTO] {
        if let existingTask = notAchievedTask {
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> [AchievementDTO] in
            guard let self else { throw CancellationError() }
            return try await self.fetchAchievements(path: "/api/achievements-not-achieved", locale: locale)
        }
        notAchievedTask = task
        defer { notAchievedTask = nil }
        return try await task.value
    }

    private func fetchAchievements(path: String, locale: String?) async throws -> [AchievementDTO] {
        logger.debug("Fetching achievements path=\(path, privacy: .public)")

        guard var components = URLComponents(string: "\(Config.strapiBaseUrl)\(path)") else {
            throw URLError(.badURL)
        }
        let trimmedLocale = locale?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLocale.isEmpty {
            components.queryItems = [URLQueryItem(name: "locale", value: trimmedLocale)]
        }
        guard let url = components.url else { throw URLError(.badURL) }

        let response: AchievementListResponse = try await networkManager.fetchDirect(from: url)
        return response.data
    }
}
