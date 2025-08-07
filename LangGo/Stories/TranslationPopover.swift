import SwiftUI

struct TranslationPopover: View {
    let translationData: StoryViewModel.ContextualTranslation?
    let isLoading: Bool
    
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.background))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
            } else if let data = translationData {
                Text(data.translatedWord)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(theme.background)

                Text(data.partOfSpeech)
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(theme.background.opacity(0.9))

                if !data.translatedSentence.isEmpty {
                    Divider()
                        .background(theme.background.opacity(0.5))
                    Text(data.translatedSentence)
                        .font(.body)
                        .foregroundColor(theme.background)
                        .lineLimit(4)
                }
            } else {
                Text("Translation unavailable.")
                    .font(.headline)
                    .foregroundColor(theme.background)
            }
        }
        .storyStyle(.translationBubble)
    }
}
