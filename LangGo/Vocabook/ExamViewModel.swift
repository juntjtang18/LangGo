// LangGo/Vocabook/ExamViewModel.swift

import Combine
import SwiftUI

// Enum to define the direction of the exam
enum ExamDirection {
    case baseToTarget, targetToBase
}

@MainActor
class ExamViewModel: ObservableObject {
    private let flashcardService = DataServices.shared.flashcardService
    private let pageSize = 20
    private let prefetchThreshold = 5

    @Published var flashcards: [Flashcard] = []
    @Published var currentCardIndex: Int = 0
    @Published var selectedOption: ExamOption?
    @Published var isAnswerSubmitted = false
    @Published var direction: ExamDirection = .baseToTarget
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMorePages: Bool = true
    @Published var isAutoLoadingRemainingPages: Bool = false

    private var currentPage = 0
    private var loadedCardIds = Set<Int>()
    private var cancellables = Set<AnyCancellable>()

    var currentCard: Flashcard? {
        guard currentCardIndex >= 0 && currentCardIndex < flashcards.count else { return nil }
        return flashcards[currentCardIndex]
    }

    init() {
        flashcardService.$reviewFlashcards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cards in
                self?.mergeReviewFlashcards(cards)
            }
            .store(in: &cancellables)

        flashcardService.$isLoadingAllReviewFlashcards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.isAutoLoadingRemainingPages = isLoading
            }
            .store(in: &cancellables)
    }

    func loadExamCards() async {
        guard !isLoading else { return }

        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        hasMorePages = true
        currentPage = 0
        currentCardIndex = 0
        loadedCardIds.removeAll()
        flashcards.removeAll()
        resetForNewCard()

        mergeReviewFlashcards(flashcardService.reviewFlashcards)
        await loadNextPageIfNeeded(force: true)
        isLoading = false

        flashcardService.ensureReviewFlashcardsFullyLoaded(pageSize: pageSize)
    }

    func loadMoreIfNeeded() async {
        // This is only a UI safety net. The shared background loading task lives
        // in FlashcardService, so multiple ExamViewModel instances do not start
        // duplicate backend pagination loops.
        guard flashcards.count - currentCardIndex <= prefetchThreshold else { return }
        await loadNextPageIfNeeded(force: false)
    }

    private func loadNextPageIfNeeded(force: Bool) async {
        guard hasMorePages else { return }
        guard force || !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let (cards, pagination) = try await flashcardService.fetchFlashcards(
                page: nextPage,
                pageSize: pageSize,
                dueOnly: true
            )

            appendExamReadyCards(cards)

            currentPage = pagination?.page ?? nextPage
            hasMorePages = currentPage < (pagination?.pageCount ?? currentPage)

            if flashcards.isEmpty && hasMorePages {
                await loadNextPageIfNeeded(force: true)
            }
        } catch {
            errorMessage = error.localizedDescription
            hasMorePages = false
        }
    }

    private func mergeReviewFlashcards(_ cards: [Flashcard]) {
        guard !cards.isEmpty else { return }
        appendExamReadyCards(cards)
    }

    private func appendExamReadyCards(_ cards: [Flashcard]) {
        let examReadyCards = cards.filter(isExamReady)
        let newCards = examReadyCards.filter { loadedCardIds.insert($0.id).inserted }

        if !newCards.isEmpty {
            flashcards.append(contentsOf: newCards)
        }
    }

    private func isExamReady(_ card: Flashcard) -> Bool {
        guard let def = card.wordDefinition?.attributes else { return false }
        let hasExamBase = def.examBase?.isEmpty == false
        let hasExamTarget = def.examTarget?.isEmpty == false
        return hasExamBase && hasExamTarget
    }

    var questionText: String? {
        guard let card = currentCard else { return nil }
        return direction == .baseToTarget ? card.frontContent : card.backContent
    }

    var examOptions: [ExamOption]? {
        guard let def = currentCard?.wordDefinition?.attributes else { return nil }

        if direction == .baseToTarget {
            return def.examTarget
        } else {
            return def.examBase
        }
    }

    var correctAnswer: String? {
        return examOptions?.first(where: { $0.isCorrect == true })?.text
    }

    func selectOption(_ option: ExamOption) {
        guard !isAnswerSubmitted else { return }
        selectedOption = option
        isAnswerSubmitted = true

        guard let card = currentCard else { return }
        let result: ReviewResult = option.isCorrect == true ? .correct : .wrong

        Task {
            do {
                _ = try await flashcardService.submitFlashcardReview(cardId: card.id, result: result)
                print("Successfully submitted review for card \(card.id) with result: \(result.rawValue)")
            } catch {
                print("Error submitting review from ExamView: \(error.localizedDescription)")
            }
        }

        if option.isCorrect == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.goToNextCard()
            }
        }
    }

    func swapDirection() {
        direction = (direction == .baseToTarget) ? .targetToBase : .baseToTarget
        resetForNewCard()
    }

    func goToNextCard() {
        if currentCardIndex < flashcards.count - 1 {
            currentCardIndex += 1
            resetForNewCard()
        }
    }

    func goToPreviousCard() {
        if currentCardIndex > 0 {
            currentCardIndex -= 1
            resetForNewCard()
        }
    }

    private func resetForNewCard() {
        selectedOption = nil
        isAnswerSubmitted = false
    }
}
