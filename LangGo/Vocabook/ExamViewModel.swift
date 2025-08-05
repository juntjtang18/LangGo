// LangGo/Vocabook/ExamViewModel.swift

import SwiftUI

// Enum to define the direction of the exam
enum ExamDirection {
    case baseToTarget, targetToBase
}

class ExamViewModel: ObservableObject {
    // These properties are not marked @Published because they are set once at initialization.
    var flashcards: [Flashcard]
    private let strapiService: StrapiService

    // MODIFIED: Properties that change and should update the UI are marked with @Published.
    @Published var currentCardIndex: Int = 0
    @Published var selectedOption: ExamOption?
    @Published var isAnswerSubmitted = false
    @Published var direction: ExamDirection = .baseToTarget // Default direction
    
    init(flashcards: [Flashcard], strapiService: StrapiService) {
        // MODIFIED: Filter for cards that have exam data via the new 'definition' property.
        self.flashcards = flashcards.filter { card in
            guard let def = card.wordDefinition?.attributes else { return false }

            let hasExamBase = def.examBase != nil && !def.examBase!.isEmpty
            let hasExamTarget = def.examTarget != nil && !def.examTarget!.isEmpty
            
            return hasExamBase && hasExamTarget
        }
        self.strapiService = strapiService
    }

    // Computed properties do not need to be @Published.
    // They will automatically update when their dependent @Published properties change.
    var currentCard: Flashcard? {
        guard !flashcards.isEmpty else { return nil }
        return flashcards[safe: currentCardIndex]
    }
    
    var questionText: String? {
        guard let card = currentCard else { return nil }
        return direction == .baseToTarget ? card.backContent : card.frontContent
    }

    var examOptions: [ExamOption]? {
        // MODIFIED: Get options from the 'definition' property.
        guard let def = currentCard?.wordDefinition?.attributes else { return nil }

        if direction == .baseToTarget {
            return def.examBase
        } else {
            return def.examTarget
        }
    }

    var correctAnswer: String? {
        // MODIFIED: Compare optional Bool to true
        return examOptions?.first(where: { $0.isCorrect == true })?.text
    }

    func selectOption(_ option: ExamOption) {
        guard !isAnswerSubmitted else { return }
        selectedOption = option
        isAnswerSubmitted = true
        
        // --- ADDED: Submit review to Strapi ---
        guard let card = currentCard else { return }
        // MODIFIED: Compare optional Bool to true
        let result: ReviewResult = option.isCorrect == true ? .correct : .wrong
        
        Task {
            do {
                _ = try await strapiService.submitFlashcardReview(cardId: card.id, result: result)
                print("Successfully submitted review for card \(card.id) with result: \(result.rawValue)")
            } catch {
                print("Error submitting review from ExamView: \(error.localizedDescription)")
            }
        }
        // --- END ADDED ---

        // If the answer is correct, wait one second then move to the next card.
        // MODIFIED: Compare optional Bool to true
        if option.isCorrect == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.goToNextCard()
            }
        }
    }
    
    // Toggles the exam direction and resets the state
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
