import Foundation
import Testing
@testable import LangGo

@Suite(.serialized)
struct RankServiceTests {
    @Test
    func decodesMyLeaderboardResponse() throws {
        let response = try JSONDecoder().decode(
            MyLeaderboardResponse.self,
            from: Data(Self.myLeaderboardJSON.utf8)
        )

        #expect(response.data.group.group_id == 1)
        #expect(response.data.group.member_count == 1)
        #expect(response.data.members.count == 1)
        #expect(response.data.members.first?.userid == "60")
        #expect(response.data.members.first?.period_points == 9)
    }

    @Test
    func decodesMyLeaderboardResponseWithNullUsername() throws {
        let response = try JSONDecoder().decode(
            MyLeaderboardResponse.self,
            from: Data(Self.myLeaderboardJSONWithNullUsername.utf8)
        )

        #expect(response.data.group.member_count == 2)
        #expect(response.data.members.count == 2)
        #expect(response.data.members[0].username == "chinese2")
        #expect(response.data.members[1].username == nil)
        #expect(response.data.members[1].userid == "7")
    }

    @Test @MainActor
    func fetchMyLeaderboardReturnsParsedData() async throws {
        MockRankAPI.install()
        defer { MockRankAPI.uninstall() }

        MockRankAPI.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/myleaderboard")
            return .json(200, Self.myLeaderboardJSON)
        }

        let service = RankService()
        let leaderboard = try await service.fetchMyLeaderboard()

        #expect(leaderboard.group.group_no == 1)
        #expect(leaderboard.group.group_rank_title == "Starter")
        #expect(leaderboard.members.count == 1)
        #expect(leaderboard.members.first?.username == "chinese2")
        #expect(leaderboard.members.first?.order_in_group == 1)
    }

    @Test @MainActor
    func concurrentFetchesJoinSingleNetworkRequest() async throws {
        MockRankAPI.install()
        defer { MockRankAPI.uninstall() }

        let counter = RankRequestCounter()
        MockRankAPI.handler = { request in
            #expect(request.url?.path == "/api/myleaderboard")
            await counter.increment()
            try await Task.sleep(nanoseconds: 200_000_000)
            return .json(200, Self.myLeaderboardJSON)
        }

        let service = RankService()

        async let first = service.fetchMyLeaderboard()
        async let second = service.fetchMyLeaderboard()
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult.group.group_no == 1)
        #expect(secondResult.group.group_no == 1)
        #expect(await counter.value() == 1)
    }

    private static let myLeaderboardJSON = """
    {
      "data": {
        "group": {
          "group_id": 1,
          "group_no": 1,
          "group_rank": 1,
          "group_rank_title": "Starter",
          "member_count": 1
        },
        "members": [
          {
            "userid": "60",
            "username": "chinese2",
            "period_points": 9,
            "order_in_group": 1
          }
        ]
      }
    }
    """

    private static let myLeaderboardJSONWithNullUsername = """
    {
      "data": {
        "group": {
          "group_id": 1,
          "group_no": 1,
          "group_rank": 1,
          "group_rank_title": "Starter",
          "member_count": 2
        },
        "members": [
          {
            "userid": "60",
            "username": "chinese2",
            "period_points": 9,
            "order_in_group": 1
          },
          {
            "userid": "7",
            "username": null,
            "period_points": 0,
            "order_in_group": 2
          }
        ]
      }
    }
    """
}

private actor RankRequestCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private enum MockRankAPI {
    struct Response {
        let statusCode: Int
        let body: Data

        static func json(_ statusCode: Int, _ string: String) -> Response {
            Response(statusCode: statusCode, body: Data(string.utf8))
        }
    }

    static var handler: ((URLRequest) async throws -> Response)?

    static func install() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    static func uninstall() {
        handler = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }

    final class MockURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "localhost" && request.url?.port == 1338
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = MockRankAPI.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            Task {
                do {
                    let response = try await handler(request)
                    let httpResponse = HTTPURLResponse(
                        url: request.url!,
                        statusCode: response.statusCode,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: response.body)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }
        }

        override func stopLoading() {}
    }
}
