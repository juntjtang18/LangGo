import SwiftUI

/// An enum defining style cases specific to the Conversation view.
enum ConversationStyle {
    case messageBubble(isUser: Bool)
    case micButton(isListening: Bool)
}

/// A view modifier that applies conversation-specific styles based on the current theme.
@MainActor
struct ConversationStyleModifier: ViewModifier {
    @Environment(\.theme) var theme: Theme
    let style: ConversationStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .messageBubble(let isUser):
            content
                .padding()
                .background(isUser ? theme.primary.opacity(0.8) : theme.secondary.opacity(0.8))
                .foregroundColor(theme.text)
                .cornerRadius(12)

        case .micButton(let isListening):
            content
                .font(.system(size: 51))
                .frame(width: 108, height: 108)
                .background(isListening ? Color.red.opacity(0.8) : theme.accent)
                .foregroundColor(.white)
                .clipShape(Circle())
                .scaleEffect(isListening ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isListening)
        }
    }
}

/// A convenience extension on `View` to easily apply conversation styles.
extension View {
    func conversationStyle(_ style: ConversationStyle) -> some View {
        self.modifier(ConversationStyleModifier(style: style))
    }
}
