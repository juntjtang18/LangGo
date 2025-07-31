import SwiftUI
import AVFoundation
import os

class ReadFlashcardViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // MARK: - Public Properties
    @Published var flashcards: [Flashcard] = []
    @Published var currentCardIndex: Int = 0
    @Published var isReading = false
    @Published var isLoading = false
    @Published var readingState: ReadingState = .idle
    
    enum ReadingState {
        case idle, readingWord, readingBaseText, paused
    }

    // MARK: - Private Properties
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ReadFlashcardViewModel")
    // REMOVED: The modelContext property is no longer needed.
    private var languageSettings: LanguageSettings
    private let strapiService: StrapiService
    private var showBaseTextBinding: Binding<Bool>?
    
    private enum ReadingStep {
        case firstWord, secondWord, baseText, finished
    }
    private var currentStep: ReadingStep = .firstWord

    // MARK: - Initialization
    // MODIFIED: The initializer no longer requires a ModelContext.
    init(languageSettings: LanguageSettings, strapiService: StrapiService) {
        self.languageSettings = languageSettings
        self.strapiService = strapiService
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods
    @MainActor
    func fetchReviewFlashcards() async {
        isLoading = true
        do {
            self.flashcards = try await strapiService.fetchAllReviewFlashcards()
            logger.info("Successfully loaded \(self.flashcards.count) cards for review session.")
        } catch {
            logger.error("Failed to fetch flashcards for review session: \(error.localizedDescription)")
            self.flashcards = [] // Ensure flashcards are empty on error
        }
        isLoading = false
    }

    @MainActor
    func startReadingSession(showBaseTextBinding: Binding<Bool>) {
        guard !flashcards.isEmpty else {
            logger.warning("No flashcards to read.")
            return
        }
        self.showBaseTextBinding = showBaseTextBinding
        isReading = true
        currentStep = .firstWord
        readCurrentCard()
    }

    func stopReading() {
        isReading = false
        synthesizer.stopSpeaking(at: .immediate)
        readingState = .idle
        showBaseTextBinding = nil
    }

    @MainActor
    func skipToNextCard() {
        synthesizer.stopSpeaking(at: .immediate)
        goToNextCard(animate: false)
    }
    
    @MainActor
    func setInitialCardIndex(_ index: Int) {
        guard index >= 0 && index < flashcards.count else {
            self.currentCardIndex = 0
            return
        }
        self.currentCardIndex = index
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            guard isReading else { return }
            
            readingState = .paused
            
            switch currentStep {
            case .firstWord:
                currentStep = .secondWord
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.readCurrentCard() }
            case .secondWord:
                if self.showBaseTextBinding?.wrappedValue ?? true {
                    currentStep = .baseText
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.readCurrentCard() }
                } else {
                    currentStep = .finished
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.goToNextCard() }
                }
            case .baseText:
                currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.goToNextCard() }
            case .finished:
                break
            }
        }
    }

    // MARK: - Private Methods
    @MainActor
    private func readCurrentCard() {
        guard isReading, let card = flashcards[safe: currentCardIndex] else {
            stopReading()
            return
        }

        let textToSpeak: String
        let languageCode: String

        switch currentStep {
        case .firstWord, .secondWord:
            textToSpeak = card.backContent
            languageCode = "en-US" // This should likely come from a config or language settings
            readingState = .readingWord
        case .baseText:
            textToSpeak = card.frontContent
            languageCode = self.languageSettings.selectedLanguageCode
            readingState = .readingBaseText
        case .finished:
            return
        }

        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        if utterance.voice == nil {
            logger.error("Error: The voice for language code '\(languageCode)' is not available on this device.")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
    
    @MainActor
    private func goToNextCard(animate: Bool = true) {
        if currentCardIndex >= flashcards.count - 1 {
            currentCardIndex = 0
        } else {
            currentCardIndex += 1
        }
        
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.currentStep = .firstWord
                self.readCurrentCard()
            }
        } else {
            self.currentStep = .firstWord
            self.readCurrentCard()
        }
    }
}
