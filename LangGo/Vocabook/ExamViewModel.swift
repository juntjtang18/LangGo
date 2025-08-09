// LangGo/Vocabook/ExamViewModel.swift

import SwiftUI

// Enum to define the direction of the exam
enum ExamDirection {
    case baseToTarget, targetToBase
}

@MainActor
class ExamViewModel: ObservableObject {
    var flashcards: [Flashcard]
    
    // The service is now fetched directly from the DataServices singleton.
    private let strapiService = DataServices.shared.strapiService

    @Published var currentCardIndex: Int = 0
    @Published var selectedOption: ExamOption?
    @Published var isAnswerSubmitted = false
    @Published var direction: ExamDirection = .baseToTarget
    
    // The initializer now only takes the data it needs to display.
    init(flashcards: [Flashcard]) {
        self.flashcards = flashcards.filter { card in
            // CORRECTED: Access attributes directly from the wordDefinition.
            guard let def = card.wordDefinition?.attributes else { return false }

            let hasExamBase = def.examBase != nil && !def.examBase!.isEmpty
            let hasExamTarget = def.examTarget != nil && !def.examTarget!.isEmpty
            
            return hasExamBase && hasExamTarget
        }
    }

    var currentCard: Flashcard? {
        guard !flashcards.isEmpty else { return nil }
        return flashcards[safe: currentCardIndex]
    }
    
    var questionText: String? {
        guard let card = currentCard else { return nil }
        return direction == .baseToTarget ? card.frontContent : card.backContent
    }

    var examOptions: [ExamOption]? {
        // CORRECTED: Access attributes directly from the wordDefinition.
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
                _ = try await strapiService.submitFlashcardReview(cardId: card.id, result: result)
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
