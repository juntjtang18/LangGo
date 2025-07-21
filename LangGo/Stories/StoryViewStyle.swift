import SwiftUI

/// An enum defining style cases specific to the Story views.
enum StoryViewStyle {
    case cardTitle
    case cardSubtitle
    case cardAuthor
    case cardBrief
    case readButton
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
        }
    }
}

/// A convenience extension on `View` to easily apply story styles.
extension View {
    func storyStyle(_ style: StoryViewStyle) -> some View {
        self.modifier(StoryStyleModifier(style: style))
    }
}
