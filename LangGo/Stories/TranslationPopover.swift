import SwiftUI

struct TranslationPopover: View {
    let originalWord: String
    let translation: String
    let isLoading: Bool
    
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The original word is now larger
            Text(originalWord)
                .font(.body) // Enlarged font
                .fontWeight(.bold)
                .foregroundColor(theme.background.opacity(0.8))
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.background))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
            } else {
                Text(translation)
                    .font(.headline)
                    .foregroundColor(theme.background) // Use theme color
            }
        }
        .storyStyle(.translationBubble) // Apply the new custom style
    }
}
