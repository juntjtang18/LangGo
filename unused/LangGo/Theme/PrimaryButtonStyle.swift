import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) var theme: Theme // 1. Read the current theme from the environment

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            // 2. Use theme colors
            .background(theme.primary)
            .foregroundColor(theme.text)
            .clipShape(Capsule())
            // 3. Add a subtle effect for when the button is pressed
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
