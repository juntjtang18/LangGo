import SwiftUI
import SwiftData

enum ExamDirection {
    case baseToTarget, targetToBase
}

@MainActor
final class ExamViewModel: ObservableObject {
    @Published var flashcards: [Flashcard]
    @Published var currentCardIndex: Int = 0
    @Published var selectedOption: ExamOption?
    @Published var isAnswerSubmitted: Bool = false
    @Published var direction: ExamDirection = .baseToTarget

    private let strapiService: StrapiService

    init(flashcards: [Flashcard], strapiService: StrapiService) {
        // Keep your existing filtering logic
        self.flashcards = flashcards.filter { card in
            let wordAttrs = card.wordAttributes
            let userWordAttrs = card.userWordAttributes

            let hasWordExam =
                (wordAttrs?.examBase != nil && !(wordAttrs!.examBase!.isEmpty)) &&
                (wordAttrs?.examTarget != nil && !(wordAttrs!.examTarget!.isEmpty))

            let hasUserWordExam =
                (userWordAttrs?.examBase != nil && !(userWordAttrs!.examBase!.isEmpty)) &&
                (userWordAttrs?.examTarget != nil && !(userWordAttrs!.examTarget!.isEmpty))

            return hasWordExam || hasUserWordExam
        }
        self.strapiService = strapiService
    }

    var currentCard: Flashcard? {
        guard !flashcards.isEmpty else { return nil }
        return flashcards[safe: currentCardIndex]
    }

    var questionText: String? {
        guard let card = currentCard else { return nil }
        return direction == .baseToTarget ? card.backContent : card.frontContent
    }

    var examOptions: [ExamOption]? {
        guard let card = currentCard else { return nil }
        return direction == .baseToTarget
            ? (card.wordAttributes?.examBase ?? card.userWordAttributes?.examBase)
            : (card.wordAttributes?.examTarget ?? card.userWordAttributes?.examTarget)
    }

    var correctAnswer: String? {
        examOptions?.first(where: { $0.isCorrect })?.text
    }

    func selectOption(_ option: ExamOption) {
        guard !isAnswerSubmitted else { return }
        selectedOption = option
        isAnswerSubmitted = true

        // Submit review asynchronously
        guard let card = currentCard else { return }
        let result: ReviewResult = option.isCorrect ? .correct : .wrong

        Task {
            do {
                _ = try await strapiService.submitFlashcardReview(cardId: card.id, result: result)
                print("Submitted review for card \(card.id): \(result.rawValue)")
            } catch {
                print("Error submitting review from ExamView: \(error.localizedDescription)")
            }
        }

        if option.isCorrect {
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
