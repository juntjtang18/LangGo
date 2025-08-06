import SwiftUI

/// An enum defining style cases specific to the Story views.
enum StoryViewStyle {
    case cardTitle
    case cardSubtitle
    case cardAuthor
    case cardBrief
    case readButton
    case justifiedBody
    case translationBubble
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
                .lineLimit(3) // Increased to 3

        case .readButton:
            content
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(Capsule())
        case .justifiedBody:
            content
                .font(.body)
                .lineSpacing(5)
                
        case .translationBubble:
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

// A helper for applying corner radius to specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// This style now only applies the shadow, as corner rounding is handled directly.
struct StoryCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}

extension View {
    func storyCardStyle() -> some View {
        self.modifier(StoryCardStyle())
    }
}
