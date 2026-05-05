// LangGo/Vocabook/ExamViewModel.swift

import SwiftUI

// Enum to define the direction of the exam
enum ExamDirection {
    case baseToTarget, targetToBase
}

@MainActor
class ExamViewModel: ObservableObject {
    private let flashcardService = DataServices.shared.flashcardService

    @Published var flashcards: [Flashcard] = []
    @Published var currentCardIndex: Int = 0
    @Published var selectedOption: ExamOption?
    @Published var isAnswerSubmitted = false
    @Published var direction: ExamDirection = .baseToTarget
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private var loadedCardIds = Set<Int>()

    var currentCard: Flashcard? {
        guard currentCardIndex >= 0 && currentCardIndex < flashcards.count else { return nil }
        return flashcards[currentCardIndex]
    }

    var canGoNext: Bool {
        currentCardIndex < flashcards.count - 1
    }

    init() {}

    func loadExamCards() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        currentCardIndex = 0
        loadedCardIds.removeAll()
        flashcards.removeAll()
        resetForNewCard()

        do {
            let availableCards = try await flashcardService.fetchAllReviewFlashcards()
            mergeReviewFlashcards(availableCards)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
                if result == .correct {
                    await MainActor.run {
                        advanceAfterCorrectReviewIfNeeded()
                    }
                }
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

    private func advanceAfterCorrectReviewIfNeeded() {
        guard canGoNext else { return }
        currentCardIndex += 1
        resetForNewCard()
    }
}
