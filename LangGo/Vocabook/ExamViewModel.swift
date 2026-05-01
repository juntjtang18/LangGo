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

    private var loadedCardIds = Set<Int>()
    private var cancellables = Set<AnyCancellable>()

    var currentCard: Flashcard? {
        guard currentCardIndex >= 0 && currentCardIndex < flashcards.count else { return nil }
        return flashcards[currentCardIndex]
    }

    var canGoNext: Bool {
        currentCardIndex < flashcards.count - 1
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
        currentCardIndex = 0
        loadedCardIds.removeAll()
        flashcards.removeAll()
        resetForNewCard()

        do {
            let availableCards = try await flashcardService.fetchAvailableReviewFlashcards(pageSize: pageSize)
            mergeReviewFlashcards(availableCards)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded() async {
        await flashcardService.loadMoreReviewFlashcardsIfNeeded(
            currentIndex: currentCardIndex,
            pageSize: pageSize
        )
    }

    private func loadFirstPage() async {
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let (cards, pagination) = try await flashcardService.fetchFlashcards(
                page: 1,
                pageSize: pageSize,
                dueOnly: true
            )

            appendExamReadyCards(cards)
            hasMorePages = (pagination?.page ?? 1) < (pagination?.pageCount ?? 1)
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
        let examReadyCards = cards.filter(hasAnyExamOptions)
        let newCards = examReadyCards.filter { loadedCardIds.insert($0.id).inserted }

        if !newCards.isEmpty {
            flashcards.append(contentsOf: newCards)
        }
    }

    private func hasAnyExamOptions(_ card: Flashcard) -> Bool {
        guard let def = card.wordDefinition?.attributes else { return false }
        let hasExamBase = !(def.examBase?.isEmpty ?? true)
        let hasExamTarget = !(def.examTarget?.isEmpty ?? true)
        return hasExamBase || hasExamTarget
    }

    var questionText: String? {
        guard let card = currentCard else { return nil }
        switch resolvedDirection(for: card) {
        case .baseToTarget:
            return card.frontContent
        case .targetToBase:
            return card.backContent
        case nil:
            return nil
        }
    }

    var examOptions: [ExamOption]? {
        guard let def = currentCard?.wordDefinition?.attributes else { return nil }

        switch resolvedDirection(for: currentCard) {
        case .baseToTarget:
            return def.examTarget
        case .targetToBase:
            return def.examBase
        case nil:
            return nil
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
                removeReviewedCard(card.id)
            } catch {
                print("Error submitting review from ExamView: \(error.localizedDescription)")
            }
        }
    }

    func swapDirection() {
        guard let card = currentCard,
              let def = card.wordDefinition?.attributes else {
            direction = (direction == .baseToTarget) ? .targetToBase : .baseToTarget
            resetForNewCard()
            return
        }

        let hasExamBase = !(def.examBase?.isEmpty ?? true)
        let hasExamTarget = !(def.examTarget?.isEmpty ?? true)

        if hasExamBase && hasExamTarget {
            direction = (direction == .baseToTarget) ? .targetToBase : .baseToTarget
        } else if hasExamTarget {
            direction = .baseToTarget
        } else if hasExamBase {
            direction = .targetToBase
        }

        resetForNewCard()
    }

    func goToNextCard() {
        guard canGoNext else { return }
        currentCardIndex += 1
        resetForNewCard()
        Task {
            await loadMoreIfNeeded()
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

        if let resolvedDirection = resolvedDirection(for: currentCard) {
            direction = resolvedDirection
        }
    }

    private func resolvedDirection(for card: Flashcard?) -> ExamDirection? {
        guard let def = card?.wordDefinition?.attributes else { return nil }

        let hasExamBase = !(def.examBase?.isEmpty ?? true)
        let hasExamTarget = !(def.examTarget?.isEmpty ?? true)

        switch (hasExamBase, hasExamTarget) {
        case (true, true):
            return direction
        case (false, true):
            return .baseToTarget
        case (true, false):
            return .targetToBase
        case (false, false):
            return nil
        }
    }

    private func removeReviewedCard(_ cardId: Int) {
        let originalCount = flashcards.count
        flashcards.removeAll { $0.id == cardId }
        loadedCardIds.remove(cardId)

        guard flashcards.count != originalCount else { return }

        if flashcards.isEmpty {
            currentCardIndex = 0
        } else if currentCardIndex >= flashcards.count {
            currentCardIndex = flashcards.count - 1
        }

        resetForNewCard()

        Task {
            await loadMoreIfNeeded()
        }
    }
}
