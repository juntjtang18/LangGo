// LangGo/Manager/SpeechManager.swift
import SwiftUI
import AVFoundation
import os

// ReadingMode now conforms to String to be saved in UserDefaults
enum ReadingMode: String {
    case inactive
    case repeatWord
    case cyclePage
    case cycleAll
}

@MainActor
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentIndex: Int = -1
    
    // --- MODIFICATION: The readingMode now saves its state to UserDefaults ---
    @Published var readingMode: ReadingMode = .cyclePage {
        didSet {
            // Save the new mode whenever it changes.
            UserDefaults.standard.set(readingMode.rawValue, forKey: "readingModeKey")
        }
    }

    private var synthesizer = AVSpeechSynthesizer()
    private var flashcards: [Flashcard] = []
    private var showBaseText: Bool = true
    
    private var interval1: TimeInterval = 1.5
    private var interval2: TimeInterval = 2.0
    private var interval3: TimeInterval = 2.0
    private let logger = Logger(subsystem: "com.langGo.swift", category: "SpeechManager")

    private enum ReadingStep {
        case firstReadTarget, secondReadTarget, readBase, finished
    }
    private var currentStep: ReadingStep = .firstReadTarget

    override init() {
        // --- MODIFICATION: Load the last saved reading mode on initialization ---
        if let savedModeRaw = UserDefaults.standard.string(forKey: "readingModeKey"),
           let savedMode = ReadingMode(rawValue: savedModeRaw) {
            self.readingMode = savedMode
        } else {
            self.readingMode = .cyclePage // Default to cyclePage if nothing is saved
        }
        
        super.init()
        self.synthesizer.delegate = self
    }

    func startReadingSession(flashcards: [Flashcard], mode: ReadingMode, showBaseText: Bool, settings: VBSettingAttributes) {
        if isSpeaking { stopReadingSession(resetMode: false) }
        
        let userLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        logger.debug("""
        
        --- Starting SpeechManager Session (Mode: \(String(describing: mode))) ---
        - Target Language (from Config): '\(Config.learningTargetLanguageCode)'
        - Base Language: '\(userLanguage)'
        - Total flashcards: \(flashcards.count)
        ------------------------------------
        
        """)

        self.flashcards = flashcards
        self.showBaseText = showBaseText
        self.readingMode = mode // This will now trigger the save to UserDefaults
        
        self.interval1 = settings.interval1
        self.interval2 = settings.interval2
        self.interval3 = settings.interval3
        
        self.isSpeaking = true
        self.currentIndex = (mode == .repeatWord && currentIndex >= 0 && currentIndex < flashcards.count) ? currentIndex : 0
        self.currentStep = .firstReadTarget
        readCurrentCard()
    }

    /// Stops speaking. Can optionally reset the mode to .inactive.
    func stopReadingSession(resetMode: Bool = true) {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentIndex = -1
        if resetMode {
            readingMode = .inactive
        }
    }
    
    func pause() {
        synthesizer.stopSpeaking(at: .word)
        isSpeaking = false
        logger.debug("--- Playback Paused at index \(self.currentIndex) ---")
    }
    
    func resume() {
        guard !isSpeaking, readingMode != .inactive, currentIndex >= 0 else { return }
        isSpeaking = true
        logger.debug("--- Playback Resumed at index \(self.currentIndex) with mode \(String(describing: self.readingMode)) ---")
        readCurrentCard()
    }

    private func readCurrentCard() {
        guard currentIndex < flashcards.count, isSpeaking else {
            if isSpeaking {
                stopReadingSession()
            }
            return
        }

        let card = flashcards[currentIndex]
        let textToSpeak: String
        var languageCode: String

        switch currentStep {
        case .firstReadTarget, .secondReadTarget:
            textToSpeak = card.backContent
            languageCode = Config.learningTargetLanguageCode
        case .readBase:
            textToSpeak = card.frontContent
            languageCode = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en-US"
        case .finished:
            goToNextCard()
            return
        }
        
        if languageCode == "fr" { languageCode = "fr-FR" }
        if languageCode == "zh-Hans" { languageCode = "zh-CN" }
        
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        if utterance.voice == nil {
            logger.error("!!! VOICE NOT FOUND for language code '\(languageCode)'.")
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
        switch readingMode {
        case .cyclePage:
            if currentIndex < flashcards.count - 1 {
                currentIndex += 1
                currentStep = .firstReadTarget
                readCurrentCard()
            } else {
                stopReadingSession()
            }
        
        case .repeatWord:
            currentStep = .firstReadTarget
            readCurrentCard()
            
        case .cycleAll:
            if currentIndex < flashcards.count - 1 {
                currentIndex += 1
                currentStep = .firstReadTarget
                readCurrentCard()
            } else {
                stopReadingSession()
            }
            
        case .inactive:
            stopReadingSession()
        }
    }
}
