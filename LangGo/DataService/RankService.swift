import Foundation
import os

@MainActor
final class RankService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "RankService")
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    func fetchMyLeaderboard() async throws -> MyLeaderboardData {
        logger.debug("Fetching my leaderboard.")

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/myleaderboard") else {
            throw URLError(.badURL)
        }

        let response: MyLeaderboardResponse = try await networkManager.fetchDirect(from: url)
        return response.data
    }
}
