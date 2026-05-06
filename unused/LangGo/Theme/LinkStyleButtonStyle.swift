import SwiftUI

struct LinkStyleButtonStyle: ButtonStyle {
    @Environment(\.theme) var theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 1. Use the secondary color for a "link" look
            .foregroundColor(theme.text)
            // 2. Add a subtle press effect
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
