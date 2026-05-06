import Foundation
import os

@MainActor
final class RankService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "RankService")
    private let networkManager: NetworkManager
    private var myLeaderboardTask: Task<MyLeaderboardData, Error>?

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    func fetchMyLeaderboard() async throws -> MyLeaderboardData {
        if let existingTask = myLeaderboardTask {
            logger.debug("Joining existing myleaderboard task.")
            return try await existingTask.value
        }

        let task = Task { [weak self] () throws -> MyLeaderboardData in
            guard let self else { throw CancellationError() }
            return try await self.fetchMyLeaderboardFromNetwork()
        }
        myLeaderboardTask = task
        defer { myLeaderboardTask = nil }

        return try await task.value
    }

    private func fetchMyLeaderboardFromNetwork() async throws -> MyLeaderboardData {
        logger.debug("Fetching my leaderboard.")

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/myleaderboard") else {
            throw URLError(.badURL)
        }

        let response: MyLeaderboardResponse = try await networkManager.fetchDirect(from: url)
        return response.data
    }

    func resetUserScopedRuntimeState() {
        myLeaderboardTask?.cancel()
        myLeaderboardTask = nil
    }
}
