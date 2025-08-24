import SwiftUI
import AVFoundation
import os

@MainActor
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
    
    // The service is now fetched directly from the DataServices singleton.
    private let flashcardService = DataServices.shared.flashcardService
    private var showBaseTextBinding: Binding<Bool>?
    
    private enum ReadingStep {
        case firstWord, secondWord, baseText, finished
    }
    private var currentStep: ReadingStep = .firstWord

    // MARK: - Initialization
    // The initializer now only takes dependencies it can't get globally.
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods
    func fetchReviewFlashcards() async {
        isLoading = true
        do {
            self.flashcards = try await flashcardService.fetchAllReviewFlashcards()
            logger.info("Successfully loaded \(self.flashcards.count) cards for review session.")
        } catch {
            logger.error("Failed to fetch flashcards for review session: \(error.localizedDescription)")
            self.flashcards = [] // Ensure flashcards are empty on error
        }
        isLoading = false
    }

    func startReadingSession(showBaseTextBinding: Binding<Bool>) {
        let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        // --- ADD THIS LOGGING BLOCK ---
        logger.debug("""
        
        --- Starting Reading Session ---
        - Target Language (from Config): '\(Config.learningTargetLanguageCode)'
        - Base Language (from UserSessionManager): '\(baseLanguage)'
        - Total flashcards: \(self.flashcards.count)
        ---------------------------------
        
        """)
        
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

    func skipToNextCard() {
        synthesizer.stopSpeaking(at: .immediate)
        goToNextCard(animate: false)
    }
    
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
    private func readCurrentCard() {
        guard isReading, let card = flashcards[safe: currentCardIndex] else {
            stopReading()
            return
        }

        let textToSpeak: String
        var languageCode: String

        switch currentStep {
        case .firstWord, .secondWord:
            textToSpeak = card.backContent
            // Use the learning target language
            languageCode = Config.learningTargetLanguageCode
            readingState = .readingWord
            logger.info("Reading TARGET text. Using language: '\(languageCode)'")

        case .baseText:
            textToSpeak = card.frontContent
            // Use the user's selected base language
            languageCode = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
            readingState = .readingBaseText
            logger.info("Reading BASE text. Using language: '\(languageCode)'")
            
        case .finished:
            return
        }
        
        // This handles cases like "fr" -> "fr-FR" for the synthesizer
        if languageCode == "fr" { languageCode = "fr-FR" }
        if languageCode == "zh-Hans" { languageCode = "zh-CN" }

        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        if utterance.voice == nil {
            logger.error("!!! VOICE NOT FOUND for language code '\(languageCode)'.")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
    
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
