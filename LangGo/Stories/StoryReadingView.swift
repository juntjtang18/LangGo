import SwiftUI
import UIKit

struct StoryReadingView: View {
    @ObservedObject var viewModel: StoryViewModel
    let story: Story
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme: Theme
    
    // --- State for translation popover ---
    @State private var selectedWord: String = ""
    @State private var showTranslationPopover: Bool = false
    @State private var wordFrame: CGRect = .zero
    @State private var selectedWordRange: NSRange?

    // --- State for user feedback (toast messages) ---
    @State private var showSaveSuccess: Bool = false
    @State private var showSaveError: Bool = false
    @State private var feedbackMessage: String = ""
    
    @AppStorage("storyFontSize") private var fontSize: Double = 17.0

    private var storyContent: [(paragraph: String, imageURL: URL?)] {
        guard let storyText = story.attributes.text else { return [] }
        let paragraphs = storyText.split(separator: "\n").map(String.init)
        var illustrationsDict: [Int: URL] = [:]
        if let illustrationComponents = story.attributes.illustrations {
            for ill in illustrationComponents {
                if let p = ill.paragraph, let urlString = ill.media?.data?.attributes.url, let url = URL(string: urlString) {
                    illustrationsDict[p - 1] = url
                }
            }
        }
        return paragraphs.enumerated().map { (index, text) in
            return (paragraph: text, imageURL: illustrationsDict[index])
        }
    }

    @State private var isLiked: Bool = false

    init(story: Story, viewModel: StoryViewModel) {
        self.story = story
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { screenGeometry in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let url = story.attributes.coverImageURL {
                            CachedAsyncImage(url: url, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else {
                            Rectangle()
                                .fill(theme.secondary.opacity(0.2))
                                .frame(height: 250)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(story.attributes.title)
                                .font(.largeTitle).bold()
                            Text("by \(story.attributes.author)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Divider()

                            ForEach(storyContent.indices, id: \.self) { index in
                                let content = storyContent[index]
                                SelectableTextView(
                                    text: content.paragraph,
                                    fontSize: fontSize,
                                    selectedWordRange: selectedWordRange
                                ) { word, sentence, frame, range in
                                    self.selectedWord = word
                                    self.wordFrame = frame
                                    self.selectedWordRange = range
                                    self.showTranslationPopover = true
                                    Task {
                                        await viewModel.translateInContext(word: word, sentence: sentence)
                                    }
                                }
                                if let imageURL = content.imageURL {
                                    CachedAsyncImage(url: imageURL, contentMode: .fit)
                                        .cornerRadius(12)
                                        .padding(.vertical)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                }
                .overlay(
                    ZStack {
                        if showTranslationPopover {
                            Color.black.opacity(0.001)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showTranslationPopover = false
                                    selectedWordRange = nil
                                }

                            TranslationPopover(
                                originalWord: selectedWord,
                                translationData: viewModel.contextualTranslation,
                                isLoading: viewModel.isTranslating,
                                onSave: saveToVocabook
                            )
                            .modifier(PopoverPositioner(wordFrame: wordFrame))
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
                    .allowsHitTesting(showTranslationPopover)
                )

                if showSaveSuccess || showSaveError {
                    Text(feedbackMessage)
                        .padding()
                        .background(showSaveSuccess ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 50)
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(story.attributes.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isLiked.toggle()
                    Task { await viewModel.toggleLike(for: story) }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : nil)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: { if fontSize > 12 { fontSize -= 1 } }) { Image(systemName: "minus") }
                Text("Font Size").font(.caption)
                Button(action: { if fontSize < 28 { fontSize += 1 } }) { Image(systemName: "plus") }
            }
        }
        .onChange(of: viewModel.selectedStory) { newStory in
            if let newStory = newStory, newStory.id == story.id {
                isLiked = (newStory.attributes.like_count ?? 0) > 0
            }
        }
        .onAppear {
            viewModel.selectedStory = self.story
        }
    }
    
    private func saveToVocabook() {
        guard let translation = viewModel.contextualTranslation else { return }
        let targetText = selectedWord
        let baseText = translation.translatedWord
        let pos = translation.partOfSpeech

        Task {
            do {
                try await viewModel.saveWordToVocabook(
                    targetText: targetText,
                    baseText: baseText,
                    partOfSpeech: pos
                )
                showFeedback(message: "Saved to Vocabook!", isError: false)
            } catch {
                showFeedback(message: "Already in Vocabook or failed to save.", isError: true)
            }
            showTranslationPopover = false
            selectedWordRange = nil
        }
    }

    private func showFeedback(message: String, isError: Bool) {
        feedbackMessage = message
        if isError {
            withAnimation { showSaveError = true }
        } else {
            withAnimation { showSaveSuccess = true }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showSaveSuccess = false
                showSaveError = false
            }
        }
    }
}


struct SelectableTextView: View {
    let text: String
    let fontSize: Double
    let selectedWordRange: NSRange?
    let onSelectWord: (String, String, CGRect, NSRange) -> Void

    @State private var height: CGFloat = .zero

    var body: some View {
        InternalSelectableTextView(
            text: text,
            fontSize: fontSize,
            selectedWordRange: selectedWordRange,
            onSelectWord: onSelectWord,
            dynamicHeight: $height
        )
        .frame(height: height)
    }

    struct InternalSelectableTextView: UIViewRepresentable {
        let text: String
        let fontSize: Double
        let selectedWordRange: NSRange?
        let onSelectWord: (String, String, CGRect, NSRange) -> Void
        @Binding var dynamicHeight: CGFloat

        func makeUIView(context: Context) -> UITextView {
            let textView = UITextView()
            textView.isEditable = false
            textView.isSelectable = false
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            textView.addGestureRecognizer(tapGesture)
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return textView
        }

        func updateUIView(_ uiView: UITextView, context: Context) {
            context.coordinator.parent = self
            Task {
                let attributedString = createAttributedString()
                
                await MainActor.run {
                    uiView.attributedText = attributedString
                    uiView.linkTextAttributes = [:]
                    
                    let newHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)).height
                    if abs(dynamicHeight - newHeight) > 1 {
                        dynamicHeight = newHeight
                    }
                }
            }
        }
        
        private func createAttributedString() -> NSAttributedString {
            let font = UIFont.systemFont(ofSize: CGFloat(fontSize))
            let attributedString = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 5
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributedString.length))
            
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { (substring, substringRange, _, _) in
                guard let substring = substring else { return }
                attributedString.addAttribute(.link, value: URL(string: "word-select://\(substring)")!, range: NSRange(substringRange, in: text))
            }
            
            if let range = selectedWordRange {
                // FIXED: Add a safety check to prevent applying an out-of-bounds range.
                let stringRange = NSRange(location: 0, length: attributedString.length)
                if NSIntersectionRange(stringRange, range).length == range.length {
                    attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.4), range: range)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.black, range: range)
                }
            }
            
            return attributedString
        }

        func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

        class Coordinator: NSObject {
            var parent: InternalSelectableTextView
            init(parent: InternalSelectableTextView) { self.parent = parent }

            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let textView = gesture.view as? UITextView else { return }
                let tapLocation = gesture.location(in: textView)
                let characterIndex = textView.layoutManager.characterIndex(for: tapLocation, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
                guard characterIndex < textView.textStorage.length else { return }
                
                var effectiveRange = NSRange()
                guard let link = textView.attributedText.attribute(.link, at: characterIndex, effectiveRange: &effectiveRange) as? URL,
                      link.scheme == "word-select" else { return }
                
                let selectedWord = link.absoluteString.replacingOccurrences(of: "word-select://", with: "")
                
                let paragraphText = parent.text
                var containingSentence = ""
                paragraphText.enumerateSubstrings(in: paragraphText.startIndex..<paragraphText.endIndex, options: .bySentences) { (sentence, sentenceRange, _, stop) in
                    guard let sentence = sentence else { return }
                    let nsSentenceRange = NSRange(sentenceRange, in: paragraphText)
                    if NSIntersectionRange(nsSentenceRange, effectiveRange).length == effectiveRange.length {
                        containingSentence = sentence
                        stop = true
                    }
                }
                if containingSentence.isEmpty { containingSentence = paragraphText }

                let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
                var wordRect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
                wordRect.origin.x += textView.textContainerInset.left
                wordRect.origin.y += textView.textContainerInset.top
                
                guard let globalRect = textView.superview?.convert(wordRect, to: nil) else { return }
                
                parent.onSelectWord(selectedWord, containingSentence, globalRect, effectiveRange)
            }
        }
    }
}


struct PopoverPositioner: ViewModifier {
    let wordFrame: CGRect
    
    private let popoverHeight: CGFloat = 180
    private let popoverWidth: CGFloat = 300
    private let spacing: CGFloat = 10

    func body(content: Content) -> some View {
        GeometryReader { screenGeometry in
            let screenWidth = screenGeometry.size.width
            
            let clampedX = max(
                (popoverWidth / 2) + screenGeometry.safeAreaInsets.leading + 10,
                min(
                    wordFrame.midX,
                    screenWidth - (popoverWidth / 2) - screenGeometry.safeAreaInsets.trailing - 10
                )
            )
            let hasRoomAbove = (wordFrame.minY - popoverHeight - spacing) > screenGeometry.safeAreaInsets.top
            let yPosition = hasRoomAbove
                ? wordFrame.minY - spacing
                : wordFrame.maxY + spacing

            content
                .frame(width: popoverWidth)
                .position(x: clampedX, y: yPosition)
                .alignmentGuide(.top) { d in
                    hasRoomAbove ? d[.bottom] - popoverHeight : d[.top]
                }
        }
    }
}
