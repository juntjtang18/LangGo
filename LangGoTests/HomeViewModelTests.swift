import Foundation
import Testing
@testable import LangGo

@Suite(.serialized)
struct HomeViewModelTests {
    @Test @MainActor
    func loadFetchesAndPublishesHomeState() async throws {
        MockHomeAPI.install()
        defer { MockHomeAPI.uninstall() }

        let counters = RequestCounter()
        MockHomeAPI.handler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/api/flashcard-stat"):
                await counters.increment("flashcard-stat")
                return .json(200, Self.flashcardStatsJSON(totalCards: 39, dueForReview: 24, remembered: 7))
            case ("GET", "/api/rank/me"):
                await counters.increment("rank-me")
                return .json(200, Self.rankSnapshotJSON(points: 120, pointsDelta: 9, groupRank: 3))
            case ("GET", "/api/myleaderboard"):
                await counters.increment("myleaderboard")
                return .json(200, Self.myLeaderboardJSON(orderInGroup: 1, periodPoints: 9))
            case ("GET", "/api/user-articles"):
                await counters.increment("user-articles")
                return .json(200, Self.userArticlesPageJSON(ids: [501], total: 1))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let homeViewModel = Self.makeHomeViewModel()
        await homeViewModel.load()

        try await Self.eventually {
            homeViewModel.reviewCardState.totalCards == 39 &&
            homeViewModel.rankPointsState.points == 120 &&
            homeViewModel.articleLibraryPreviews.count == 1
        }

        #expect(homeViewModel.reviewCardState.dueForReview == 24)
        #expect(homeViewModel.rankPointsState.pointsDelta == 9)
        #expect(homeViewModel.rankPointsState.rankText == "Kindgarden I")
        #expect(homeViewModel.leaderboardBannerState.title == "Group 1")
        #expect(homeViewModel.leaderboardBannerState.currentUserPosition == 1)
        #expect(homeViewModel.articleLibraryCount == 1)
        #expect(homeViewModel.articleLibraryPreviews.first?.backendId == 501)
        #expect(await counters.value(for: "flashcard-stat") == 1)
        #expect(await counters.value(for: "rank-me") == 1)
        #expect(await counters.value(for: "myleaderboard") == 1)
        #expect(await counters.value(for: "user-articles") == 1)
    }

    @Test @MainActor
    func loadPublishesReviewCardStateWhenStatsFinishAfterSnapshot() async throws {
        MockHomeAPI.install()
        defer { MockHomeAPI.uninstall() }

        MockHomeAPI.handler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/api/flashcard-stat"):
                try await Task.sleep(nanoseconds: 250_000_000)
                return .json(200, Self.flashcardStatsJSON(totalCards: 39, dueForReview: 24, remembered: 7))
            case ("GET", "/api/rank/me"):
                return .json(200, Self.rankSnapshotJSON(points: 120, pointsDelta: 9, groupRank: 3))
            case ("GET", "/api/myleaderboard"):
                return .json(200, Self.myLeaderboardJSON(orderInGroup: 1, periodPoints: 9))
            case ("GET", "/api/user-articles"):
                return .json(200, Self.userArticlesPageJSON(ids: [501], total: 1))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let homeViewModel = Self.makeHomeViewModel()
        await homeViewModel.load()

        #expect(homeViewModel.reviewCardState.totalCards == 39)
        #expect(homeViewModel.reviewCardState.dueForReview == 24)
    }

    @Test @MainActor
    func refreshFetchesLatestHomeState() async throws {
        MockHomeAPI.install()
        defer { MockHomeAPI.uninstall() }

        let counters = RequestCounter()
        let state = MutableHomeState(
            stats: (totalCards: 39, dueForReview: 24, remembered: 7),
            snapshot: (points: 120, pointsDelta: 9, groupRank: 3),
            leaderboard: (orderInGroup: 1, periodPoints: 9)
        )

        MockHomeAPI.handler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/api/flashcard-stat"):
                await counters.increment("flashcard-stat")
                let stats = await state.stats
                return .json(200, Self.flashcardStatsJSON(totalCards: stats.totalCards, dueForReview: stats.dueForReview, remembered: stats.remembered))
            case ("GET", "/api/rank/me"):
                await counters.increment("rank-me")
                let snapshot = await state.snapshot
                return .json(200, Self.rankSnapshotJSON(points: snapshot.points, pointsDelta: snapshot.pointsDelta, groupRank: snapshot.groupRank))
            case ("GET", "/api/myleaderboard"):
                await counters.increment("myleaderboard")
                let leaderboard = await state.leaderboard
                return .json(200, Self.myLeaderboardJSON(orderInGroup: leaderboard.orderInGroup, periodPoints: leaderboard.periodPoints))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let homeViewModel = Self.makeHomeViewModel()
        await homeViewModel.load()
        await state.setStats(totalCards: 40, dueForReview: 23, remembered: 8)
        await state.setSnapshot(points: 131, pointsDelta: 10, groupRank: 2)
        await state.setLeaderboard(orderInGroup: 2, periodPoints: 10)
        await homeViewModel.refresh()

        #expect(homeViewModel.reviewCardState.totalCards == 40)
        #expect(homeViewModel.reviewCardState.dueForReview == 23)
        #expect(homeViewModel.rankPointsState.points == 131)
        #expect(homeViewModel.leaderboardBannerState.currentUserPosition == 2)

        #expect(await counters.value(for: "flashcard-stat") == 2)
        #expect(await counters.value(for: "rank-me") == 2)
        #expect(await counters.value(for: "myleaderboard") == 2)
    }

    @Test @MainActor
    func articleCreateDoesNotAutoRefreshUntilHomeRefreshes() async throws {
        MockHomeAPI.install()
        defer { MockHomeAPI.uninstall() }

        let counters = RequestCounter()
        let articleState = MutableArticleState(ids: [])

        MockHomeAPI.handler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("POST", "/api/user-articles"):
                await counters.increment("article-post")
                await articleState.setIds([501])
                return .json(200, #"{"data":{"id":501}}"#)
            case ("GET", "/api/user-articles/501"):
                await counters.increment("article-detail")
                return .json(200, Self.singleArticleJSON(id: 501))
            case ("GET", "/api/user-articles"):
                await counters.increment("article-list")
                let ids = await articleState.ids
                return .json(200, Self.userArticlesPageJSON(ids: ids, total: ids.count))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let services = Self.makeServices()
        let homeViewModel = HomeViewModel(
            userSnapshotService: services.snapshotService,
            flashcardService: services.flashcardService,
            articleService: services.articleService,
            rankService: services.rankService,
            localeProvider: { "en" }
        )

        await homeViewModel.load()
        _ = try await services.articleService.createUserArticle(
            title: "My First Article",
            content: "This is article content.",
            languageCode: "en",
            wordCount: 120,
            articleTagIds: []
        )

        #expect(homeViewModel.articleLibraryCount == 0)
        #expect(homeViewModel.articleLibraryPreviews.isEmpty)

        await homeViewModel.refresh()

        try await Self.eventually {
            homeViewModel.articleLibraryCount == 1 &&
            homeViewModel.articleLibraryPreviews.first?.backendId == 501
        }

        #expect(await counters.value(for: "article-post") == 1)
        #expect(await counters.value(for: "article-detail") == 1)
        #expect(await counters.value(for: "article-list") == 2)
    }

    @Test @MainActor
    func ascentLeaderboardRefreshKeepsHomeSnapshotLocaleAligned() async throws {
        MockHomeAPI.install()
        defer { MockHomeAPI.uninstall() }

        MockHomeAPI.handler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/api/flashcard-stat"):
                return .json(200, Self.flashcardStatsJSON(totalCards: 39, dueForReview: 24, remembered: 7))
            case ("GET", "/api/rank/me"):
                return .json(200, Self.rankSnapshotJSON(points: 120, pointsDelta: 9, groupRank: 3))
            case ("GET", "/api/myleaderboard"):
                return .json(200, Self.myLeaderboardJSON(orderInGroup: 1, periodPoints: 9))
            case ("GET", "/api/user-articles"):
                return .json(200, Self.userArticlesPageJSON(ids: [501], total: 1))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let services = Self.makeServices()
        let homeViewModel = HomeViewModel(
            userSnapshotService: services.snapshotService,
            flashcardService: services.flashcardService,
            articleService: services.articleService,
            rankService: services.rankService,
            localeProvider: { "en" }
        )

        await homeViewModel.load()
        #expect(homeViewModel.rankPointsState.rankText == "Kindgarden I")

        let ascentViewModel = AscentLeaderboardViewModel(
            rankService: services.rankService,
            userSnapshotService: services.snapshotService,
            localeProvider: { "en" }
        )
        await ascentViewModel.load()

        #expect(homeViewModel.rankPointsState.rankText == "Kindgarden I")
        #expect(homeViewModel.rankPointsState.points == 120)
    }

    @MainActor
    private static func makeHomeViewModel() -> HomeViewModel {
        let services = makeServices()
        return HomeViewModel(
            userSnapshotService: services.snapshotService,
            flashcardService: services.flashcardService,
            articleService: services.articleService,
            rankService: services.rankService,
            localeProvider: { "en" }
        )
    }

    @MainActor
    private static func makeServices() -> (flashcardService: FlashcardService, articleService: ArticleService, snapshotService: UserSnapshotService, rankService: RankService) {
        UserDefaults.standard.set(true, forKey: "isRefreshModeEnabled")
        UserDefaults.standard.set(60, forKey: "userId")

        let snapshotService = UserSnapshotService()
        snapshotService.invalidateSnapshot(locale: "en")
        let flashcardService = FlashcardService()
        let articleService = ArticleService()
        let rankService = RankService()
        return (flashcardService, articleService, snapshotService, rankService)
    }

    private static func eventually(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        Issue.record("Timed out waiting for condition.")
        throw URLError(.timedOut)
    }

    private static func flashcardStatsJSON(totalCards: Int, dueForReview: Int, remembered: Int) -> String {
        """
        {"data":{"totalCards":\(totalCards),"remembered":\(remembered),"dueForReview":\(dueForReview),"reviewed":0,"hardToRemember":0,"byTier":[],"nextFetchAt":null,"batchWindowMinutes":20}}
        """
    }

    private static func rankSnapshotJSON(points: Int, pointsDelta: Int, groupRank: Int) -> String {
        """
        {"data":{"latest_snapshot":{"id":1,"userid":"60","record_date":null,"total_points":\(points),"points_add":\(pointsDelta),"word_count":39,"word_add":1,"article_count":0,"article_add":0,"level_no":1,"level_change":0,"level_title":"Kindgarden I","group_id":1,"group_no":1,"group_rank":\(groupRank),"group_rank_title":"Top Learner","group_rank_change":1,"period_points":9,"period_points_change":0}}}
        """
    }

    private static func myLeaderboardJSON(orderInGroup: Int, periodPoints: Int) -> String {
        """
        {"data":{"group":{"group_id":1,"group_no":1,"group_rank":1,"group_rank_title":"Starter","member_count":1},"members":[{"userid":"60","username":"chinese2","period_points":\(periodPoints),"order_in_group":\(orderInGroup)}]}}
        """
    }

    private static func flashcardReviewResponseJSON(cardId: Int) -> String {
        """
        {"data":{"id":\(cardId),"attributes":{"createdAt":"2026-05-01T05:51:56.204Z","updatedAt":"2026-05-01T05:51:56.204Z","last_reviewed_at":null,"is_remembered":false,"correct_streak":1,"wrong_streak":0,"word_definition":{"data":{"id":3381,"attributes":{"base_text":"药剂师","createdAt":"2026-05-01T05:51:55.903Z","updatedAt":"2026-05-01T05:51:59.580Z","locale":"zh-Hans","gender":null,"article":null,"example_sentence":"Example","exam_base":[],"exam_target":[],"register":null,"word":{"data":{"id":4011,"attributes":{"target_text":"pharmacist","createdAt":"2026-05-01T05:51:55.515Z","updatedAt":"2026-05-01T05:51:55.515Z"}}},"part_of_speech":{"data":{"id":1,"attributes":{"name":"noun","createdAt":"2025-08-03T20:58:45.536Z","updatedAt":"2025-08-03T20:58:45.536Z"}}},"tags":null,"verb_meta":null}},"review_tire":{"data":null}}}}
        """
    }

    private static func userArticlesPageJSON(ids: [Int], total: Int) -> String {
        let articles = ids.map(singleArticleDataJSON).joined(separator: ",")
        return """
        {"data":[\(articles)],"meta":{"pagination":{"page":1,"pageSize":10,"pageCount":1,"total":\(total)}}}
        """
    }

    private static func singleArticleJSON(id: Int) -> String {
        """
        {"data":\(singleArticleDataJSON(id: id))}
        """
    }

    private static func singleArticleDataJSON(id: Int) -> String {
        """
        {"id":\(id),"attributes":{"title":"My First Article","content":"This is article content.","language_code":"en","word_count":120,"progress":0.5,"last_read_at":"2026-05-01T05:51:56.204Z","article_tags":{"data":[{"id":71,"attributes":{"tag":"Travel"}}]}}}
        """
    }
}

actor MutableHomeState {
    private(set) var stats: (totalCards: Int, dueForReview: Int, remembered: Int)
    private(set) var snapshot: (points: Int, pointsDelta: Int, groupRank: Int)
    private(set) var leaderboard: (orderInGroup: Int, periodPoints: Int)

    init(
        stats: (totalCards: Int, dueForReview: Int, remembered: Int),
        snapshot: (points: Int, pointsDelta: Int, groupRank: Int),
        leaderboard: (orderInGroup: Int, periodPoints: Int)
    ) {
        self.stats = stats
        self.snapshot = snapshot
        self.leaderboard = leaderboard
    }

    func setStats(totalCards: Int, dueForReview: Int, remembered: Int) {
        stats = (totalCards, dueForReview, remembered)
    }

    func setSnapshot(points: Int, pointsDelta: Int, groupRank: Int) {
        snapshot = (points, pointsDelta, groupRank)
    }

    func setLeaderboard(orderInGroup: Int, periodPoints: Int) {
        leaderboard = (orderInGroup, periodPoints)
    }
}

actor MutableArticleState {
    private(set) var ids: [Int]

    init(ids: [Int]) {
        self.ids = ids
    }

    func setIds(_ ids: [Int]) {
        self.ids = ids
    }
}

actor RequestCounter {
    private var values: [String: Int] = [:]

    func increment(_ key: String) {
        values[key, default: 0] += 1
    }

    func value(for key: String) -> Int {
        values[key, default: 0]
    }
}

private enum MockHomeAPI {
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
        UserDefaults.standard.removeObject(forKey: "isRefreshModeEnabled")
        UserDefaults.standard.removeObject(forKey: "userId")
    }

    final class MockURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "localhost" && request.url?.port == 1338
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = MockHomeAPI.handler else {
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
