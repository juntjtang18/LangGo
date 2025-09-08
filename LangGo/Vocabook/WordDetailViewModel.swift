// LangGo/Vocabook/WordDetailViewModel.swift

import SwiftUI
import AVFoundation

@MainActor
class WordDetailViewModel: ObservableObject {
    // Services
    private let flashcardService = DataServices.shared.flashcardService
    private let speechSynthesizer = AVSpeechSynthesizer() // A simple speech synthesizer

    // Data
    private let cards: [Flashcard]
    
    // UI State
    @Published var currentIndex: Int
    @Published var showDeleteConfirmation = false
    @Published var isDeleting = false
    @Published var showRecorder = false // For the mic button
    @AppStorage("repeatReadingEnabled") var repeatReadingEnabled: Bool = false
    
    // Computed Properties
    var currentCard: Flashcard { cards[currentIndex] }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < cards.count - 1 }

    init(cards: [Flashcard], initialIndex: Int) {
        self.cards = cards
        self.currentIndex = initialIndex
    }

    // MARK: - Actions
    
    func deleteCurrentCard() {
        Task {
            isDeleting = true
            // The service call will trigger the Notification, and the parent
            // VocabookViewModel will refresh itself automatically.
            try? await flashcardService.deleteFlashcard(cardId: currentCard.id)
            isDeleting = false
            showDeleteConfirmation = false
            // The parent view is responsible for dismissing the sheet
        }
    }

    func speakCurrentCard() {
        let utterance = AVSpeechUtterance(string: currentCard.backContent)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // Or your target language
        speechSynthesizer.speak(utterance)
    }
    
    func recordTapped() {
        // Placeholder for your recording logic
        print("Record tapped")
        showRecorder = true
    }

    func goToNext() {
        if canGoNext { currentIndex += 1 }
    }

    func goToPrevious() {
        if canGoPrevious { currentIndex -= 1 }
    }
}