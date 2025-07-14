import SwiftUI

// 1. Define your style cases.
enum ViewStyle {
    case title, body, caption, primaryButton, secondaryButton, themedTextField
}

// 2. Conform exactly to ViewModifier—including @MainActor.
@MainActor
struct StyleModifier: ViewModifier {
    // 2a. Existential protocols work without the `any` keyword here.
    @Environment(\.theme) var theme: Theme
    let style: ViewStyle

    // 2b. Signature must match the protocol’s @MainActor requirement.
    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .title:
            content
                .font(.largeTitle)            // ← correct, built-in style
                .foregroundColor(theme.text)

        case .body:
            content
                .font(.body)
                .foregroundColor(theme.text)
        
        case .caption:
            content
                .font(.caption)
                .foregroundColor(theme.text.opacity(0.8))

        case .primaryButton:
            content
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(theme.primary)
                .foregroundColor(theme.text)
                .clipShape(Capsule())

        case .secondaryButton:
            content
                .foregroundColor(theme.secondary)

        case .themedTextField:
            content
                .padding()
                .background(theme.secondary.opacity(0.2))
                .cornerRadius(10)
                .foregroundColor(theme.text)
        }
    }
}

// 3. Extension remains the same.
extension View {
    func style(_ style: ViewStyle) -> some View {
        self.modifier(StyleModifier(style: style))
    }
}
