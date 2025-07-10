import SwiftUI
import AVFoundation
import os

// MARK: - Speech Manager for VocapageView
@MainActor
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentIndex: Int = -1

    private var synthesizer = AVSpeechSynthesizer()
    private var flashcards: [Flashcard] = []
    private var languageSettings: LanguageSettings?
    private var showBaseText: Bool = true
    
    private var interval1: TimeInterval = 1.5
    private var interval2: TimeInterval = 2.0
    private var interval3: TimeInterval = 2.0
    
    private enum ReadingStep {
        case firstReadTarget, secondReadTarget, readBase, finished
    }
    private var currentStep: ReadingStep = .firstReadTarget

    override init() {
        super.init()
        self.synthesizer.delegate = self
    }

    func startReadingSession(flashcards: [Flashcard], showBaseText: Bool, languageSettings: LanguageSettings, settings: VBSettingAttributes) {
        self.flashcards = flashcards
        self.languageSettings = languageSettings
        self.showBaseText = showBaseText
        
        self.interval1 = settings.interval1
        self.interval2 = settings.interval2
        self.interval3 = settings.interval3
        
        self.isSpeaking = true
        self.currentIndex = 0
        self.currentStep = .firstReadTarget
        readCurrentCard()
    }

    func stopReadingSession() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentIndex = -1
    }

    private func readCurrentCard() {
        guard currentIndex < flashcards.count, isSpeaking else {
            stopReadingSession()
            return
        }

        let card = flashcards[currentIndex]
        let textToSpeak: String
        let languageCode: String

        switch currentStep {
        case .firstReadTarget, .secondReadTarget:
            textToSpeak = card.backContent
            languageCode = Config.learningTargetLanguageCode
        case .readBase:
            textToSpeak = card.frontContent
            languageCode = languageSettings?.selectedLanguageCode ?? "en-US"
        case .finished:
            goToNextCard()
            return
        }
        
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        if utterance.voice == nil {
            print("Error: Voice for language code '\(languageCode)' not available.")
            speechSynthesizer(synthesizer, didFinish: utterance)
            return
        }
        
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isSpeaking else { return }

            switch self.currentStep {
            case .firstReadTarget:
                self.currentStep = .secondReadTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval1) { self.readCurrentCard() }
            
            case .secondReadTarget:
                if self.showBaseText {
                    self.currentStep = .readBase
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval2) { self.readCurrentCard() }
                } else {
                    self.currentStep = .finished
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentCard() }
                }
            
            case .readBase:
                self.currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentCard() }

            case .finished:
                break
            }
        }
    }
    
    private func goToNextCard() {
        if currentIndex < flashcards.count - 1 {
            currentIndex += 1
            currentStep = .firstReadTarget
            readCurrentCard()
        } else {
            stopReadingSession()
        }
    }
}
