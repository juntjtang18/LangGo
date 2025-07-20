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
    
    private let conversationService: ConversationService
    private let speechManager = SpeechSynthesizerManager()
    private let speechRecognizer = SpeechRecognizer()
    private var currentTopic: String?
    
    private let audioSession = AVAudioSession.sharedInstance()

    init(conversationService: ConversationService) {
        self.conversationService = conversationService
        super.init() // Required for NSObject subclasses
        
        // Set the ViewModel as the delegate to receive speech events.
        self.speechManager.setDelegate(self)
        
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
    
    private func prepareSessionForRecording() {
         do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            // The recognizer will call setActive(true)
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
        guard !newMessageText.isEmpty, !isSendingMessage else { return }

        let userMessageContent = newMessageText
        let userMessage = ConversationMessage(role: "user", content: userMessageContent)
        messages.append(userMessage)
        newMessageText = ""
        isSendingMessage = true
        errorMessage = nil

        Task {
            do {
                let history = self.messages
                let response = try await conversationService.getNextPrompt(history: history, topic: currentTopic)
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

    func startListening() {
        speechManager.stop()
        // No need to prepare the session here, the recognizer does it.
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
    }
    
    func cleanupAudioOnDisappear() {
        speechManager.stop()
        speechRecognizer.stop()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Don't show an error, just log it.
            print("Failed to deactivate audio session on disappear: \(error.localizedDescription)")
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // This is the key fix. When speech finishes, we don't deactivate the session.
        // We immediately prepare it for the user to start recording.
        // This must be dispatched back to the main thread.
        Task { @MainActor in
            self.prepareSessionForRecording()
        }
    }
}
