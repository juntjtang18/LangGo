import Foundation
import Testing
@testable import LangGo

@Suite(.serialized)
struct FlashcardReviewFlowServiceTests {
    @Test
    func fetchAvailableReviewFlashcardsLoadsFirstPageIntoMemory() async throws {
        MockFlashcardAPI.install()
        defer { MockFlashcardAPI.uninstall() }

        MockFlashcardAPI.handler = { request in
            switch request.url?.path {
            case "/api/review-flashcards":
                return .json(200, Self.reviewListResponseJSON(ids: [11, 12], page: 1, pageSize: 2, pageCount: 2, total: 4))
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let service = FlashcardService()
        let cards = try await service.fetchAvailableReviewFlashcards(pageSize: 2)

        #expect(cards.map(\.id) == [11, 12])
        #expect(service.reviewFlashcards.map(\.id) == [11, 12])
    }

    @Test
    func loadMoreReviewFlashcardsAppendsNextPageInMemory() async throws {
        MockFlashcardAPI.install()
        defer { MockFlashcardAPI.uninstall() }

        var requestedPages: [Int] = []
        MockFlashcardAPI.handler = { request in
            switch request.url?.path {
            case "/api/review-flashcards":
                let page = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "pagination[page]" })?
                    .value
                    .flatMap(Int.init) ?? 1
                requestedPages.append(page)
                if page == 1 {
                    return .json(200, Self.reviewListResponseJSON(ids: [21, 22], page: 1, pageSize: 2, pageCount: 2, total: 4))
                }
                if page == 2 {
                    return .json(200, Self.reviewListResponseJSON(ids: [23, 24], page: 2, pageSize: 2, pageCount: 2, total: 4))
                }
                throw URLError(.unsupportedURL)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let service = FlashcardService()
        _ = try await service.fetchAvailableReviewFlashcards(pageSize: 2)
        await service.loadMoreReviewFlashcardsIfNeeded(currentIndex: 1, pageSize: 2, threshold: 1)

        #expect(requestedPages == [1, 2])
        #expect(service.reviewFlashcards.map(\.id) == [21, 22, 23, 24])
    }

    @Test
    func submitReviewRemovesCardFromInMemoryReviewState() async throws {
        MockFlashcardAPI.install()
        defer { MockFlashcardAPI.uninstall() }

        MockFlashcardAPI.handler = { request in
            switch request.url?.path {
            case "/api/review-flashcards":
                return .json(200, Self.reviewListResponseJSON(ids: [31, 32], page: 1, pageSize: 2, pageCount: 1, total: 2))
            case "/api/flashcards/31/review":
                return .json(200, Self.reviewResponseJSON(cardId: 31))
            case "/api/flashcard-stat":
                Issue.record("submitFlashcardReview should not call /api/flashcard-stat")
                throw URLError(.badURL)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let service = FlashcardService()
        _ = try await service.fetchAvailableReviewFlashcards(pageSize: 2)
        _ = try await service.submitFlashcardReview(cardId: 31, result: .correct)

        #expect(service.reviewFlashcards.map(\.id) == [32])
    }

    @Test
    func fetchFlashcardStatisticsAlwaysHitsNetworkAndDedupesInflightRequests() async throws {
        MockFlashcardAPI.install()
        defer { MockFlashcardAPI.uninstall() }

        let lock = NSLock()
        var statsRequestCount = 0

        MockFlashcardAPI.handler = { request in
            switch request.url?.path {
            case "/api/flashcard-stat":
                lock.lock()
                statsRequestCount += 1
                lock.unlock()
                try await Task.sleep(nanoseconds: 100_000_000)
                return .json(200, Self.statisticsResponseJSON())
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let service = FlashcardService()
        async let first = service.fetchFlashcardStatistics()
        async let second = service.fetchFlashcardStatistics()
        let (stats1, stats2) = try await (first, second)

        #expect(stats1.totalCards == 6)
        #expect(stats2.totalCards == 6)
        #expect(statsRequestCount == 1)

        _ = try await service.fetchFlashcardStatistics()
        #expect(statsRequestCount == 2)
    }

    private static func statisticsResponseJSON() -> String {
        """
        {"data":{"totalCards":6,"remembered":0,"dueForReview":2,"reviewed":0,"hardToRemember":0,"byTier":[],"nextFetchAt":null,"batchWindowMinutes":20}}
        """
    }

    private static func reviewListResponseJSON(ids: [Int], page: Int, pageSize: Int, pageCount: Int, total: Int) -> String {
        let cards = ids.map(reviewCardJSON).joined(separator: ",")
        return """
        {"data":[\(cards)],"meta":{"pagination":{"page":\(page),"pageSize":\(pageSize),"pageCount":\(pageCount),"total":\(total)}}}
        """
    }

    private static func reviewResponseJSON(cardId: Int) -> String {
        """
        {"data":\(reviewCardJSON(id: cardId))}
        """
    }

    private static func reviewCardJSON(id: Int) -> String {
        """
        {"id":\(id),"attributes":{"createdAt":"2026-05-01T05:51:56.204Z","updatedAt":"2026-05-01T05:51:56.204Z","last_reviewed_at":null,"is_remembered":false,"correct_streak":0,"wrong_streak":0,"word_definition":{"data":{"id":\(3000 + id),"attributes":{"base_text":"Base \(id)","exam_base":[{"text":"Wrong","isCorrect":false},{"text":"Base \(id)","isCorrect":true}],"exam_target":[{"text":"Wrong","isCorrect":false},{"text":"Target \(id)","isCorrect":true}],"word":{"data":{"id":\(4000 + id),"attributes":{"target_text":"Target \(id)"}}},"part_of_speech":{"data":{"id":1,"attributes":{"name":"noun"}}}}}},"review_tire":{"data":null}}}
        """
    }
}

private enum MockFlashcardAPI {
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
            guard let handler = MockFlashcardAPI.handler else {
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
