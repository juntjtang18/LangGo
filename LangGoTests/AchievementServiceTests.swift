import Foundation
import Testing
@testable import LangGo

@Suite(.serialized)
struct AchievementServiceTests {
    @Test @MainActor
    func fetchAchievedUsesStrapiProxyEndpoint() async throws {
        let service = AchievementService()
        let url = try service.makeAchievementsURL(path: "/api/achievements-achieved", locale: "en")

        #expect(url.path == "/api/achievements-achieved")
        #expect(url.query == "locale=en")
    }

    @Test @MainActor
    func fetchNotAchievedUsesStrapiProxyEndpoint() async throws {
        let service = AchievementService()
        let url = try service.makeAchievementsURL(path: "/api/achievements-not-achieved", locale: nil)

        #expect(url.path == "/api/achievements-not-achieved")
        #expect(url.query == nil)
    }

    @Test
    func decodesPostgresTimestampWithTwoFractionDigits() throws {
        let response = try decodeAchievementResponse(achievedAt: "2026-05-04 23:31:14.68+00")

        #expect(response.data.first?.achievedAt != nil)
    }

    @Test
    func decodesPostgresTimestampWithThreeFractionDigits() throws {
        let response = try decodeAchievementResponse(achievedAt: "2026-05-07 22:29:09.739+00")

        #expect(response.data.first?.achievedAt != nil)
    }

    @Test
    func decodesNullAchievementTimestamp() throws {
        let response = try decodeAchievementResponse(achievedAt: nil)

        #expect(response.data.first?.achievedAt == nil)
    }

    private func decodeAchievementResponse(achievedAt: String?) throws -> AchievementListResponse {
        let achievedAtValue = achievedAt.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "data": [
            {
              "id": 1,
              "code": "FLASHCARD_CREATE_10",
              "event_name": "flashcard.create",
              "icon_name": "pencil",
              "points": 1,
              "goal": 10,
              "progress": 10,
              "achieved": true,
              "achieved_at": \(achievedAtValue),
              "title": "创建 10 张单词卡",
              "description": "在 LangGo 中创建 10 张单词卡。"
            }
          ]
        }
        """

        return try JSONDecoder().decode(AchievementListResponse.self, from: Data(json.utf8))
    }
}
