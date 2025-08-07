import SwiftUI

struct TranslationPopover: View {
    // ADDED: The original word to display
    let originalWord: String
    
    let translationData: StoryViewModel.ContextualTranslation?
    let isLoading: Bool
    let onSave: () -> Void
    
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.background))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
            } else if let data = translationData {
                // Displays: "originalWord (pos) translatedWord"
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(originalWord)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(theme.background)
                    
                    Text(data.partOfSpeech)
                        .font(.callout)
                        .italic()
                        .foregroundColor(theme.background.opacity(0.9))
                    
                    Text(data.translatedWord)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(theme.background)
                }

                if !data.translatedSentence.isEmpty {
                    Divider()
                        .background(theme.background.opacity(0.5))
                    Text(data.translatedSentence)
                        .font(.body)
                        .foregroundColor(theme.background)
                        .lineLimit(4)
                }
                
                Divider()
                    .background(theme.background.opacity(0.5))
                
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Save to Vocabook")
                    }
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(theme.background.opacity(0.2))
                    .foregroundColor(theme.background)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

            } else {
                Text("Translation unavailable.")
                    .font(.headline)
                    .foregroundColor(theme.background)
            }
        }
        .storyStyle(.translationBubble)
    }
}
