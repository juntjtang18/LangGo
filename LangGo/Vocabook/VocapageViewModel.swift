// LangGo/Vocabook/VocapageViewModel.swift
import Foundation
import SwiftUI

@MainActor
class VocapageViewModel: ObservableObject {
    @Published private(set) var currentPage: Int
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var currentPageCards: [Flashcard] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    let pageSize: Int = 20

    private let flashcardService: FlashcardService
    private(set) var dueOnly: Bool
    private(set) var reviewTier: String?
    private(set) var recentlyAddedLimit: Int
    private var inFlightPage: Int?

    init(
        initialPage: Int = 1,
        dueOnly: Bool = false,
        reviewTier: String? = nil,
        recentlyAddedLimit: Int = 0,
        flashcardService: FlashcardService? = nil
    ) {
        self.currentPage = max(1, initialPage)
        self.dueOnly = dueOnly
        self.reviewTier = reviewTier
        self.recentlyAddedLimit = recentlyAddedLimit
        self.flashcardService = flashcardService ?? DataServices.shared.flashcardService
    }

    func loadInitialPage() async {
        await loadPage(currentPage)
    }

    func loadPage(_ page: Int) async {
        let requestedPage = max(1, page)
        guard inFlightPage != requestedPage else { return }

        inFlightPage = requestedPage
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            inFlightPage = nil
        }

        do {
            let (cards, pagination) = try await fetchPage(page: requestedPage)
            let resolvedTotalPages = resolvedTotalPages(from: pagination)
            let resolvedPage = resolvedCurrentPage(
                requestedPage: requestedPage,
                backendPage: pagination?.page,
                totalPages: resolvedTotalPages
            )

            if resolvedPage != requestedPage {
                let (fallbackCards, fallbackPagination) = try await fetchPage(page: resolvedPage)
                applyPage(
                    cards: clampCardsToRecentLimit(fallbackCards, page: resolvedPage),
                    pagination: fallbackPagination,
                    requestedPage: resolvedPage
                )
            } else {
                applyPage(
                    cards: clampCardsToRecentLimit(cards, page: resolvedPage),
                    pagination: pagination,
                    requestedPage: resolvedPage
                )
            }
        } catch {
            errorMessage = "Failed to load page content: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func goNext() async -> Bool {
        guard currentPage < totalPages else { return false }
        await loadPage(currentPage + 1)
        return true
    }

    @discardableResult
    func goPrevious() async -> Bool {
        guard currentPage > 1 else { return false }
        await loadPage(currentPage - 1)
        return true
    }

    func updateDueOnly(_ dueOnly: Bool) async {
        guard self.dueOnly != dueOnly else { return }
        self.dueOnly = dueOnly
        currentPage = 1
        totalPages = 0
        currentPageCards = []
        await loadInitialPage()
    }

    private func fetchPage(page: Int) async throws -> ([Flashcard], StrapiPagination?) {
        if dueOnly {
            return try await flashcardService.fetchDueFlashcardsPage(page: page, pageSize: pageSize)
        }
        if recentlyAddedLimit > 0 {
            return try await flashcardService.fetchRecentFlashcardsPage(page: page, pageSize: pageSize)
        }
        if let reviewTier, !reviewTier.isEmpty {
            return try await flashcardService.fetchFlashcardsPage(page: page, pageSize: pageSize, reviewTier: reviewTier)
        }
        return try await flashcardService.fetchFlashcardsPage(page: page, pageSize: pageSize)
    }

    private func applyPage(cards: [Flashcard], pagination: StrapiPagination?, requestedPage: Int) {
        currentPageCards = cards
        totalPages = resolvedTotalPages(from: pagination)
        currentPage = resolvedCurrentPage(
            requestedPage: requestedPage,
            backendPage: pagination?.page,
            totalPages: totalPages
        )
    }

    private func resolvedTotalPages(from pagination: StrapiPagination?) -> Int {
        let pageCount = pagination?.pageCount ?? 0
        guard recentlyAddedLimit > 0 else { return pageCount }

        let cappedTotal = min(pagination?.total ?? 0, recentlyAddedLimit)
        guard cappedTotal > 0 else { return 0 }
        return Int(ceil(Double(cappedTotal) / Double(pageSize)))
    }

    private func resolvedCurrentPage(requestedPage: Int, backendPage: Int?, totalPages: Int) -> Int {
        guard totalPages > 0 else { return 1 }
        let candidate = backendPage ?? requestedPage
        return min(max(1, candidate), totalPages)
    }

    private func clampCardsToRecentLimit(_ cards: [Flashcard], page: Int) -> [Flashcard] {
        guard recentlyAddedLimit > 0 else { return cards }

        let startIndex = max(0, (page - 1) * pageSize)
        let remaining = max(0, recentlyAddedLimit - startIndex)
        guard remaining > 0 else { return [] }
        return Array(cards.prefix(remaining))
    }
}
