// LangGo/Conversation/ConversationViewModel.swift
import SwiftUI
import AVFoundation

@MainActor
class ConversationViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var messages: [ConversationMessage] = []
    @Published var newMessageText: String = ""
    @Published var isSendingMessage = false
    @Published var errorMessage: String?
    @Published var isListening = false
    @Published var isMouthAnimating = false
    
    private let conversationService: ConversationService
    private let speechManager = SpeechSynthesizerManager()
    private let speechRecognizer = SpeechRecognizer()
    private var currentTopic: String?
    private var sessionId: String?
    
    private let audioSession = AVAudioSession.sharedInstance()

    init(conversationService: ConversationService) {
        self.conversationService = conversationService
        super.init() // Required for NSObject subclasses
        
        self.speechManager.delegate = self
        
        speechRecognizer.requestPermissions()
        speechRecognizer.$transcript.assign(to: &$newMessageText)
        speechRecognizer.$isListening.assign(to: &$isListening)
    }

    // MARK: - Audio Session Management
    
    private func prepareSessionForPlayback() {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to prepare session for playback: \(error.localizedDescription)"
        }
    }
    
    // UPDATED: This method now also sets the session active.
    private func prepareSessionForRecording() {
         do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to prepare session for recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Conversation Logic

    func startConversation() {
        guard messages.isEmpty else { return }

        Task {
            do {
                let response = try await conversationService.startConversation()
                self.sessionId = response.sessionId
                let assistantMessage = response.next_prompt
                messages.append(ConversationMessage(role: "assistant", content: assistantMessage))
                self.currentTopic = response.suggested_topic
                
                prepareSessionForPlayback()
                speechManager.speak(text: assistantMessage)
            } catch {
                errorMessage = "Failed to start conversation: \(error.localizedDescription)"
            }
        }
    }

    func sendMessage() {
        guard let sessionId = sessionId, !newMessageText.isEmpty, !isSendingMessage else { return }

        let userMessageContent = newMessageText
        let userMessage = ConversationMessage(role: "user", content: userMessageContent)
        messages.append(userMessage)
        newMessageText = ""
        isSendingMessage = true
        errorMessage = nil

        Task {
            do {
                let history = self.messages
                let response = try await conversationService.getNextPrompt(history: history, topic: currentTopic, sessionId: sessionId)
                let assistantMessage = response.next_prompt
                messages.append(ConversationMessage(role: "assistant", content: assistantMessage))
                
                prepareSessionForPlayback()
                speechManager.speak(text: assistantMessage)
            } catch {
                errorMessage = "Failed to get response: \(error.localizedDescription)"
                if let lastMessage = messages.last, lastMessage.role == "user" {
                     messages.removeLast()
                }
            }
            isSendingMessage = false
        }
    }

    // UPDATED: This function now orchestrates the audio session handoff.
    func startListening() {
        // 1. Immediately stop any ongoing speech.
        speechManager.stop()
    
        // 2. Explicitly prepare the audio session for recording.
        // This is the crucial step that prevents the crash.
        prepareSessionForRecording()
    
        // 3. Start the recognizer, which now assumes the session is ready.
        speechRecognizer.start()
    }


    func stopListening() {
        speechRecognizer.stop()
        if !newMessageText.isEmpty {
            sendMessage()
        }
    }
    
    func stopSpeaking() {
        speechManager.stop()
        isMouthAnimating = false
    }
    
    func cleanupAudioOnDisappear() {
        speechManager.stop()
        speechRecognizer.stop()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session on disappear: \(error.localizedDescription)")
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Open the mouth for each word
            isMouthAnimating = true
            
            // Schedule the mouth to close after a short duration
            // This creates the rhythmic open/close effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Check if we are still supposed to be animating before closing
                if self.isMouthAnimating {
                    self.isMouthAnimating = false
                }
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Ensure mouth is closed and audio session is ready for recording
            self.isMouthAnimating = false
            self.prepareSessionForRecording()
        }
    }
}
