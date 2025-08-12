import SwiftUI

struct TranslationPopover: View {
    // The original word to display
    let originalWord: String
    
    let translationData: StoryViewModel.ContextualTranslation?
    let isLoading: Bool
    let onSave: () -> Void
    let onPlayAudio: () -> Void // ADDED: A closure to handle the audio action.
    
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.primary))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
            } else if let data = translationData {
                // Displays: "originalWord (pos) translatedWord"
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(originalWord)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(theme.text)
                    
                    // ADDED: The speaker button for text-to-speech.
                    Button(action: onPlayAudio) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.headline)
                            .foregroundColor(theme.accent)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(data.partOfSpeech)
                        .font(.callout)
                        .italic()
                        .foregroundColor(theme.text.opacity(0.9))
                    
                    Text(data.translatedWord)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(theme.text)
                }

                if !data.translatedSentence.isEmpty {
                    Divider()
                        .background(theme.text.opacity(0.2))
                    Text(data.translatedSentence)
                        .font(.body)
                        .foregroundColor(theme.text)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Divider()
                    .background(theme.text.opacity(0.2))
                
                Button(action: onSave) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Save to Vocabook")
                    }
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(theme.accent)
                    .foregroundColor(theme.background)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

            } else {
                Text("Translation unavailable.")
                    .font(.headline)
                    .foregroundColor(theme.text)
            }
        }
        .padding()
        .frame(width: 300)
        .background(theme.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}
