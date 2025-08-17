// LangGo/Manager/SpeechManager.swift
import SwiftUI
import AVFoundation
import os

enum ReadingMode: String, Codable {
    case inactive
    case repeatWord
    case cyclePage
    case cycleAll
}

@MainActor
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // UI state only; host sets currentIndex so views can highlight/scroll.
    @Published var isSpeaking: Bool = false
    @Published var currentIndex: Int = -1

    // Expose paused state for better Play/Pause UX from the host.
    var isPaused: Bool { synthesizer.isPaused }

    private let logger = Logger(subsystem: "com.langGo.swift", category: "SpeechManager")
    private var synthesizer = AVSpeechSynthesizer()

    // Per-word timing (configured by host via VBSettingAttributes each speak()).
    private var interval1: TimeInterval = 1.5
    private var interval2: TimeInterval = 2.0
    private var interval3: TimeInterval = 2.0

    private enum ReadingStep { case firstReadTarget, secondReadTarget, readBase, finished }
    private var currentStep: ReadingStep = .firstReadTarget

    private var showBaseTextForThisWord: Bool = true
    private var currentCard: Flashcard?
    private var onFinishOneWord: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak exactly one flashcard (two target reads + optional base).
    /// Host decides what to read next via completion.
    func speak(card: Flashcard, showBaseText: Bool, settings: VBSettingAttributes, onComplete: @escaping () -> Void) {
        // If we were speaking, stop immediately and start fresh for this one card.
        if isSpeaking { stop() }

        self.interval1 = settings.interval1
        self.interval2 = settings.interval2
        self.interval3 = settings.interval3
        self.showBaseTextForThisWord = showBaseText
        self.currentCard = card
        self.onFinishOneWord = onComplete
        self.currentStep = .firstReadTarget
        self.isSpeaking = true

        readCurrentStep()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentIndex = -1
        currentCard = nil
        onFinishOneWord = nil
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        isSpeaking = false
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        let resumed = synthesizer.continueSpeaking()
        if resumed { isSpeaking = true }
    }

    // MARK: - Private

    private func readCurrentStep() {
        guard let card = currentCard else {
            stop()
            return
        }
        guard isSpeaking else { return }

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
            // End of one word sequence; notify host.
            finishOneWord()
            return
        }

        // Normalize some common language codes
        if languageCode == "fr" { languageCode = "fr-FR" }
        if languageCode == "zh-Hans" { languageCode = "zh-CN" }

        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)

        if utterance.voice == nil {
            logger.error("!!! VOICE NOT FOUND for language code '\(languageCode)'. Skipping.")
            // Pretend it finished so we don't stall the loop.
            self.speechSynthesizer(synthesizer, didFinish: utterance)
            return
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    private func finishOneWord() {
        isSpeaking = false
        let completion = onFinishOneWord
        onFinishOneWord = nil
        completion?()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // If host paused/stopped between utterances
            guard self.isSpeaking || self.isPaused else { return }

            switch self.currentStep {
            case .firstReadTarget:
                self.currentStep = .secondReadTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval1) { self.readCurrentStep() }

            case .secondReadTarget:
                if self.showBaseTextForThisWord {
                    self.currentStep = .readBase
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval2) { self.readCurrentStep() }
                } else {
                    self.currentStep = .finished
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentStep() }
                }

            case .readBase:
                self.currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentStep() }

            case .finished:
                // Shouldn't reach; finishOneWord() already handles finalization.
                break
            }
        }
    }
}
