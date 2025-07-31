import SwiftUI
import UIKit

struct StoryReadingView: View {
    @ObservedObject var viewModel: StoryViewModel
    let story: Story
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme: Theme
    
    @State private var selectedWord: String = ""
    @State private var showTranslationPopover: Bool = false
    @State private var wordFrame: CGRect = .zero

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
            ScrollView {
                // ... Your existing ScrollView content is unchanged ...
                VStack(alignment: .leading, spacing: 20) {
                    AsyncImage(url: story.attributes.coverImageURL) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 250)
                            .clipped()
                    } placeholder: {
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

                            SelectableTextView(text: content.paragraph, fontSize: fontSize) { word, frame in
                                self.selectedWord = word
                                self.wordFrame = frame
                                self.showTranslationPopover = true
                                Task {
                                    await viewModel.translate(word: word)
                                }
                            }

                            if let imageURL = content.imageURL {
                                AsyncImage(url: imageURL) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(12)
                                } placeholder: {
                                    ProgressView()
                                }
                                .padding(.vertical)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                // Add padding at the bottom to ensure content doesn't hide behind the new bottom bar
                .padding(.bottom, 60)
            }
            .overlay(
                ZStack {
                    if showTranslationPopover {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showTranslationPopover = false
                            }

                        TranslationPopover(
                            originalWord: selectedWord,
                            translation: viewModel.translationResult ?? "",
                            isLoading: viewModel.isTranslating,
                            fontSize: fontSize
                        )
                        .modifier(PopoverPositioner(wordFrame: wordFrame))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
                .allowsHitTesting(showTranslationPopover)
            )
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(story.attributes.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // --- FIX 1: The .bottomBar item has been removed ---
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
        // --- FIX 2: The bottom bar is now a safeAreaInset ---
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: {
                    if fontSize > 12 { fontSize -= 1 }
                }) {
                    Image(systemName: "minus")
                }
                
                Spacer()
                Text("Font Size").font(.caption)
                Spacer()
                
                Button(action: {
                    if fontSize < 28 { fontSize += 1 }
                }) {
                    Image(systemName: "plus")
                }
            }
            .font(.headline)
            .padding()
            .background(.thinMaterial)
        }
        .onChange(of: viewModel.selectedStory) { newStory in // iOS 16 compatible
            if let newStory = newStory, newStory.id == story.id {
                isLiked = (newStory.attributes.like_count ?? 0) > 0
            }
        }
        .onAppear {
            viewModel.selectedStory = self.story
        }
    }
}




struct SelectableTextView: View {
    let text: String
    let fontSize: Double
    let onSelectWord: (String, CGRect) -> Void

    @State private var height: CGFloat = .zero

    var body: some View {
        InternalSelectableTextView(text: text, fontSize: fontSize, onSelectWord: onSelectWord, dynamicHeight: $height)
            .frame(height: height)
    }

    struct InternalSelectableTextView: UIViewRepresentable {
        let text: String
        let fontSize: Double
        let onSelectWord: (String, CGRect) -> Void
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
            let attributedString = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: attributedString.length)
            
            attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: CGFloat(fontSize)), range: fullRange)
            attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 5
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { (substring, substringRange, _, _) in
                guard let substring = substring else { return }
                let range = NSRange(substringRange, in: text)
                let url = URL(string: "word-select://\(substring)")!
                attributedString.addAttribute(.link, value: url, range: range)
            }
            
            uiView.attributedText = attributedString
            uiView.linkTextAttributes = [:]
            context.coordinator.parent = self
            
            DispatchQueue.main.async {
                dynamicHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude)).height
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        class Coordinator: NSObject {
            var parent: InternalSelectableTextView

            init(parent: InternalSelectableTextView) {
                self.parent = parent
            }

            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let textView = gesture.view as? UITextView else { return }
                let tapLocation = gesture.location(in: textView)

                let layoutManager = textView.layoutManager
                let characterIndex = layoutManager.characterIndex(for: tapLocation, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

                guard characterIndex < textView.textStorage.length else { return }
                
                var effectiveRange = NSRange()
                guard let link = textView.attributedText.attribute(.link, at: characterIndex, effectiveRange: &effectiveRange) as? URL,
                      link.scheme == "word-select" else { return }
                
                let selectedWord = link.absoluteString.replacingOccurrences(of: "word-select://", with: "")
                
                let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
                var wordRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
                
                wordRect.origin.x += textView.textContainerInset.left
                wordRect.origin.y += textView.textContainerInset.top
                
                guard let globalRect = textView.superview?.convert(wordRect, to: nil) else { return }
                
                parent.onSelectWord(selectedWord, globalRect)
            }
        }
    }
}


struct PopoverPositioner: ViewModifier {
    let wordFrame: CGRect
    
    private let popoverHeight: CGFloat = 80
    private let popoverWidth: CGFloat = 200
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
                ? wordFrame.minY - spacing - (popoverHeight / 2)
                : wordFrame.maxY + spacing + (popoverHeight / 2)

            content
                .frame(width: popoverWidth, height: popoverHeight, alignment: .center)
                .position(x: clampedX, y: yPosition)
        }
    }
}
