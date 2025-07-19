import SwiftUI

@MainActor
class ConversationViewModel: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    @Published var newMessageText: String = ""
    @Published var isSendingMessage = false
    @Published var errorMessage: String?

    private let conversationService: ConversationService
    private var currentTopic: String? // To hold the topic if any

    init(conversationService: ConversationService) {
        self.conversationService = conversationService
    }

    func startConversation() {
        guard messages.isEmpty else { return }

        Task {
            do {
                let response = try await conversationService.startConversation()
                messages.append(ConversationMessage(role: "assistant", content: response.next_prompt))
                self.currentTopic = response.suggested_topic
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
                messages.append(ConversationMessage(role: "assistant", content: response.next_prompt))
            } catch {
                errorMessage = "Failed to get response: \(error.localizedDescription)"
                // Optional: remove the user's message if the API call fails
                 if let lastMessage = messages.last, lastMessage.role == "user" {
                     messages.removeLast()
                 }
            }
            isSendingMessage = false
        }
    }
}
