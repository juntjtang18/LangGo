// LangGo/Conversation/SpeechSynthesizerManager.swift
import AVFoundation
import os

class SpeechSynthesizerManager {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "SpeechSynthesizerManager")

    // This method allows the ViewModel to receive speech lifecycle events.
    func setDelegate(_ delegate: AVSpeechSynthesizerDelegate?) {
        synthesizer.delegate = delegate
    }

    func speak(text: String, language: String = "en-US") {
        logger.debug("Attempting to speak text: \(text)")

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // This class no longer manages the audio session directly.
        // It relies on the ViewModel to have configured it.

        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            logger.error("Voice for language \(language) not available")
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        logger.debug("Started speaking utterance")
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            logger.debug("Speech stopped")
        }
    }
}
