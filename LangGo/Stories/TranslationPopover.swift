import SwiftUI

struct TranslationPopover: View {
    let originalWord: String
    let translation: String
    let isLoading: Bool
    let fontSize: Double // MODIFIED: Changed to Double
    
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(originalWord)
                // Cast to CGFloat when creating the font
                .font(.system(size: CGFloat(fontSize)))
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
                    .foregroundColor(theme.background)
            }
        }
        .storyStyle(.translationBubble)
    }
}
