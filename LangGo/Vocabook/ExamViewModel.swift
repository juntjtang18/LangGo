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

    var currentCard: Flashcard? {
        guard currentCardIndex >= 0 && currentCardIndex < flashcards.count else { return nil }
        return flashcards[currentCardIndex]
    }
    
    init() {}

    func loadExamCards() async {
        isLoading = true
        errorMessage = nil
        do {
            let dueCards = try await flashcardService.fetchAllReviewFlashcards()
            
            // Filter for cards that are valid for an exam
            let examReadyCards = dueCards.filter { card in
                 guard let def = card.wordDefinition?.attributes else { return false }
                 let hasExamBase = def.examBase != nil && !def.examBase!.isEmpty
                 let hasExamTarget = def.examTarget != nil && !def.examTarget!.isEmpty
                 return hasExamBase && hasExamTarget
            }

            self.flashcards = examReadyCards
            self.currentCardIndex = 0
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
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
