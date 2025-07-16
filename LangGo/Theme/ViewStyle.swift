import SwiftUI

// 1. Define your style cases.
enum ViewStyle {
    case title, body, caption, primaryButton, secondaryButton, themedTextField, registerTag, correctButton, wrongButton
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
        
        case .registerTag:
            content
                .font(.footnote)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.gray)
                .cornerRadius(8)

        case .correctButton:
            content
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)

        case .wrongButton:
            content
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }
}

// 3. Extension remains the same.
extension View {
    func style(_ style: ViewStyle) -> some View {
        self.modifier(StyleModifier(style: style))
    }
}
