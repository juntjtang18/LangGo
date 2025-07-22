import SwiftUI

/// An enum defining style cases specific to the Story views.
enum StoryViewStyle {
    case cardTitle
    case cardSubtitle
    case cardAuthor
    case cardBrief
    case readButton
    case justifiedBody // ADDED: New style for justified text
    case translationBubble // ADD THIS
}

/// A view modifier that applies story-specific styles based on the current theme.
@MainActor
struct StoryStyleModifier: ViewModifier {
    @Environment(\.theme) var theme: Theme
    let style: StoryViewStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .cardTitle:
            content
                .font(.title2.bold())
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(.trailing, 8)

        case .cardSubtitle:
            content
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.9))

        case .cardAuthor:
            content
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

        case .cardBrief:
            content
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

        case .readButton:
            content
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(Capsule())
        case .justifiedBody: // ADDED: Definition for the new style
            content
                .font(.body)
                .lineSpacing(5)
                //.multilineTextAlignment(.justified)
        case .translationBubble: // ADD THIS
            content
                .padding()
                .background(theme.accent.opacity(0.95))
                .foregroundColor(theme.background)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.secondary, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        
        
    }
}

/// A convenience extension on `View` to easily apply story styles.
extension View {
    func storyStyle(_ style: StoryViewStyle) -> some View {
        self.modifier(StoryStyleModifier(style: style))
    }
}
