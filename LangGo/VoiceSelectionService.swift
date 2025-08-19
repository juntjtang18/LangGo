//
//  VoiceSelectionService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/19.
//


// VoiceSelectionService.swift

import SwiftUI
import AVFoundation

// This service is the single source of truth for voice selection and TTS settings.
class VoiceSelectionService: ObservableObject {
    @Published var availableStandardVoices: [AVSpeechSynthesisVoice] = []
    
    // Use AppStorage to save the user's choice persistently across the app.
    @AppStorage("selectedVoiceIdentifier") var selectedVoiceIdentifier: String = AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let weirdVoiceNames: Set<String> = [
        "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles",
        "Cellos", "Deranged", "Good News", "Hysterical", "Pipe Organ",
        "Trinoids", "Whisper", "Zarvox", "Organ", "Jester", "Wobble"
    ]

    init() {
        fetchAvailableVoices()
    }
    
    func fetchAvailableVoices() {
        self.availableStandardVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let isTargetLanguage = voice.language.hasPrefix(Config.learningTargetLanguageCode)
                let isNotWeird = !weirdVoiceNames.contains(voice.name)
                return isTargetLanguage && isNotWeird
            }
            .sorted { (voice1, voice2) -> Bool in
                if voice1.quality.rawValue != voice2.quality.rawValue {
                    return voice1.quality.rawValue > voice2.quality.rawValue
                }
                return voice1.name < voice2.name
            }
    }

    func selectVoice(identifier: String) {
        self.selectedVoiceIdentifier = identifier
    }

    func sampleVoice(text: String, identifier: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
        speechSynthesizer.speak(utterance)
    }
}
