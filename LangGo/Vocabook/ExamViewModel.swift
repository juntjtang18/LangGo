// LangGo/Vocabook/ExamViewModel.swift

import SwiftUI
// import SwiftData // REMOVED: No longer needed.

// Enum to define the direction of the exam
enum ExamDirection {
    case baseToTarget, targetToBase
}

// MODIFIED: Changed from @Observable to conform to ObservableObject for iOS 16 compatibility.
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
        // Filter for cards that have exam data for BOTH directions
        self.flashcards = flashcards.filter { card in
            let wordAttrs = card.wordAttributes
            let userWordAttrs = card.userWordAttributes
            
            let hasWordExam = (wordAttrs?.examBase != nil && !wordAttrs!.examBase!.isEmpty) && (wordAttrs?.examTarget != nil && !wordAttrs!.examTarget!.isEmpty)
            let hasUserWordExam = (userWordAttrs?.examBase != nil && !userWordAttrs!.examBase!.isEmpty) && (userWordAttrs?.examTarget != nil && !userWordAttrs!.examTarget!.isEmpty)
            
            return hasWordExam || hasUserWordExam
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
        guard let card = currentCard else { return nil }
        let options = direction == .baseToTarget ? card.wordAttributes?.examBase ?? card.userWordAttributes?.examBase : card.wordAttributes?.examTarget ?? card.userWordAttributes?.examTarget
        return options
    }

    var correctAnswer: String? {
        return examOptions?.first(where: { $0.isCorrect })?.text
    }

    func selectOption(_ option: ExamOption) {
        guard !isAnswerSubmitted else { return }
        selectedOption = option
        isAnswerSubmitted = true
        
        // --- ADDED: Submit review to Strapi ---
        guard let card = currentCard else { return }
        let result: ReviewResult = option.isCorrect ? .correct : .wrong
        
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
        if option.isCorrect {
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
