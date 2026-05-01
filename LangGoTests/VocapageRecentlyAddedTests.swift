import Foundation
import Testing
@testable import LangGo

@Suite(.serialized)
struct VocapageViewModelPagingTests {

    @Test @MainActor
    func loadInitialPageUsesAllFlashcardsEndpoint() async {
        MockVocapageAPI.install()
        defer { MockVocapageAPI.uninstall() }

        MockVocapageAPI.handler = { request in
            #expect(request.url?.path == "/api/flashcards/mine")
            return .json(200, Self.flashcardsPageJSON(ids: [11, 12], page: 1, pageSize: 20, pageCount: 3, total: 45))
        }

        let viewModel = VocapageViewModel(initialPage: 1)
        await viewModel.loadInitialPage()

        #expect(viewModel.currentPage == 1)
        #expect(viewModel.totalPages == 3)
        #expect(viewModel.currentPageCards.map(\.id) == [11, 12])
    }

    @Test @MainActor
    func loadInitialPageUsesDueEndpointWhenDueOnlyEnabled() async {
        MockVocapageAPI.install()
        defer { MockVocapageAPI.uninstall() }

        MockVocapageAPI.handler = { request in
            #expect(request.url?.path == "/api/review-flashcards")
            return .json(200, Self.flashcardsPageJSON(ids: [21], page: 1, pageSize: 20, pageCount: 2, total: 21))
        }

        let viewModel = VocapageViewModel(initialPage: 1, dueOnly: true)
        await viewModel.loadInitialPage()

        #expect(viewModel.currentPage == 1)
        #expect(viewModel.totalPages == 2)
        #expect(viewModel.currentPageCards.map(\.id) == [21])
    }

    @Test @MainActor
    func goNextAndGoPreviousUpdateCurrentPage() async {
        MockVocapageAPI.install()
        defer { MockVocapageAPI.uninstall() }

        MockVocapageAPI.handler = { request in
            let page = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "pagination[page]" })?
                .value
                .flatMap(Int.init) ?? 1

            switch page {
            case 1:
                return .json(200, Self.flashcardsPageJSON(ids: [31, 32], page: 1, pageSize: 20, pageCount: 2, total: 40))
            case 2:
                return .json(200, Self.flashcardsPageJSON(ids: [41, 42], page: 2, pageSize: 20, pageCount: 2, total: 40))
            default:
                throw URLError(.badURL)
            }
        }

        let viewModel = VocapageViewModel(initialPage: 1)
        await viewModel.loadInitialPage()
        let movedNext = await viewModel.goNext()
        let movedPrevious = await viewModel.goPrevious()

        #expect(movedNext)
        #expect(movedPrevious)
        #expect(viewModel.currentPage == 1)
        #expect(viewModel.currentPageCards.map(\.id) == [31, 32])
    }

    @Test @MainActor
    func loadPageGuardsPastEndByReloadingLastPage() async {
        MockVocapageAPI.install()
        defer { MockVocapageAPI.uninstall() }

        MockVocapageAPI.handler = { request in
            let page = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "pagination[page]" })?
                .value
                .flatMap(Int.init) ?? 1

            if page == 5 {
                return .json(200, Self.flashcardsPageJSON(ids: [], page: 5, pageSize: 20, pageCount: 2, total: 40))
            }
            if page == 2 {
                return .json(200, Self.flashcardsPageJSON(ids: [51, 52], page: 2, pageSize: 20, pageCount: 2, total: 40))
            }
            throw URLError(.badURL)
        }

        let viewModel = VocapageViewModel(initialPage: 5)
        await viewModel.loadInitialPage()

        #expect(viewModel.currentPage == 2)
        #expect(viewModel.totalPages == 2)
        #expect(viewModel.currentPageCards.map(\.id) == [51, 52])
    }

    private static func flashcardsPageJSON(ids: [Int], page: Int, pageSize: Int, pageCount: Int, total: Int) -> String {
        let cards = ids.map(cardJSON).joined(separator: ",")
        return """
        {"data":[\(cards)],"meta":{"pagination":{"page":\(page),"pageSize":\(pageSize),"pageCount":\(pageCount),"total":\(total)}}}
        """
    }

    private static func cardJSON(id: Int) -> String {
        """
        {"id":\(id),"attributes":{"createdAt":"2026-05-01T05:51:56.204Z","updatedAt":"2026-05-01T05:51:56.204Z","last_reviewed_at":null,"is_remembered":false,"correct_streak":0,"wrong_streak":0,"word_definition":{"data":{"id":\(3000 + id),"attributes":{"base_text":"Base \(id)","word":{"data":{"id":\(4000 + id),"attributes":{"target_text":"Target \(id)"}}},"part_of_speech":{"data":{"id":1,"attributes":{"name":"noun"}}}}}},"review_tire":{"data":null}}}
        """
    }
}

private enum MockVocapageAPI {
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
            guard let handler = MockVocapageAPI.handler else {
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
