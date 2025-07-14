import SwiftUI

struct ThemedTextFieldStyle: TextFieldStyle {
    @Environment(\.theme) var theme: Theme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.background) // Use background color
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.secondary, lineWidth: 1) // Use a border color
            )
            .foregroundColor(theme.text) // Set the text color
    }
}
