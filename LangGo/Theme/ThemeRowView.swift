import SwiftUI

struct ThemeRowView: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text(theme.id)
                    .font(.headline)
                    .foregroundColor(theme.text)
                
                // Color swatches to preview the theme
                HStack(spacing: 12) {
                    Circle().fill(theme.primary).frame(width: 22, height: 22)
                    Circle().fill(theme.accent).frame(width: 22, height: 22)
                    Circle().fill(theme.text).frame(width: 22, height: 22)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(theme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(theme.background.opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.accent, lineWidth: isSelected ? 2 : 0)
        )
    }
}
