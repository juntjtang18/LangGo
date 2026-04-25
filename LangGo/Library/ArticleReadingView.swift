import SwiftUI
import AVFoundation

@MainActor
final class ArticleReadingViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var article: LibraryArticle
    @Published var contextualTranslation: StoryViewModel.ContextualTranslation?
    @Published var isTranslating = false
    @Published var isSavingWord = false
    @Published var isLoadingArticle = false
    @Published var isSpeaking = false
    @Published var errorMessage: String?
    @Published var feedbackMessage: String?

    private let articleService = DataServices.shared.articleService
    private let wordService = DataServices.shared.wordService
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")

    init(article: LibraryArticle) {
        self.article = article
        super.init()
        speechSynthesizer.delegate = self
    }

    var bodyParagraphs: [String] {
        let content = article.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            return []
        }

        return content
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func loadArticleIfNeeded() async {
        guard (article.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              let backendId = article.backendId else {
            return
        }

        isLoadingArticle = true
        defer { isLoadingArticle = false }

        do {
            let fetchedArticle = try await articleService.fetchUserArticle(articleId: backendId)
            article = mapLibraryArticle(fetchedArticle, fallback: article)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func translate(word: String, sentence: String) async {
        let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        let learningLanguage = Config.learningTargetLanguageCode

        guard learningLanguage != baseLanguage else {
            contextualTranslation = .init(
                translatedWord: word,
                translatedSentence: sentence,
                partOfSpeech: ""
            )
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let response = try await wordService.translateWordInContext(
                word: word,
                sentence: sentence,
                sourceLang: learningLanguage,
                targetLang: baseLanguage
            )
            contextualTranslation = .init(
                translatedWord: response.translation,
                translatedSentence: response.sentence,
                partOfSpeech: response.partOfSpeech
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveWordToVocab(word: String) async {
        guard let translation = contextualTranslation else { return }

        let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        isSavingWord = true
        defer { isSavingWord = false }

        do {
            _ = try await wordService.saveNewWord(
                targetText: word,
                baseText: translation.translatedWord,
                partOfSpeech: translation.partOfSpeech,
                locale: baseLanguage
            )
            feedbackMessage = "Saved to Vocabook"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleReading() {
        if isSpeaking {
            stopReading()
        } else {
            startReading()
        }
    }

    func stopReading() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    private func startReading() {
        let content = bodyParagraphs.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            errorMessage = "No article content is available to read."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        speechSynthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = resolvedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speechSynthesizer.speak(utterance)
        isSpeaking = true
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if let selectedVoiceIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            return selectedVoice
        }

        return AVSpeechSynthesisVoice(language: Config.learningTargetLanguageCode)
    }

    private func mapLibraryArticle(_ article: StrapiUserArticle, fallback: LibraryArticle) -> LibraryArticle {
        let tagNames = article.attributes.articleTags?.data.compactMap {
            $0.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty } ?? fallback.tags
        let content = article.attributes.content ?? fallback.content
        let wordCount = article.attributes.wordCount ?? content?.split { $0.isWhitespace || $0.isNewline }.count ?? fallback.wordCount

        let trimmedTitle = article.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? fallback.title

        return LibraryArticle(
            id: fallback.id,
            backendId: article.id,
            title: resolvedTitle,
            content: content,
            wordCount: wordCount,
            newWords: fallback.newWords,
            progress: article.attributes.progress ?? fallback.progress,
            tag: tagNames.first ?? fallback.tag,
            tags: tagNames,
            dateLabel: fallback.dateLabel,
            sourceLabel: fallback.sourceLabel,
            level: fallback.level,
            topic: fallback.topic
        )
    }
}

struct ArticleReadingView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ArticleReadingViewModel
    @AppStorage("articleReadingFontSize") private var fontSize: Double = 18

    @State private var selectedWord = ""
    @State private var selectedParagraphIndex: Int?
    @State private var selectedWordRange: NSRange?
    @State private var wordFrame: CGRect = .zero
    @State private var showTranslationPopover = false
    @State private var showReaderSettings = false

    init(article: LibraryArticle) {
        _viewModel = StateObject(wrappedValue: ArticleReadingViewModel(article: article))
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = ArticleReadingMetrics(screenSize: proxy.size)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    topBar(metrics: metrics)

                    if viewModel.isLoadingArticle {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading article...")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.48, green: 0.50, blue: 0.57))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                                Rectangle()
                                    .fill(Color(red: 0.31, green: 0.24, blue: 1.00))
                                    .frame(height: 3)

                                metaRow(metrics: metrics)

                                Text(viewModel.article.title)
                                    .font(.system(size: fontSize * 1.2, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.23))

                                if viewModel.bodyParagraphs.isEmpty {
                                    Text("No article content is available yet.")
                                        .font(.system(size: fontSize, weight: .regular, design: .default))
                                        .foregroundStyle(Color(red: 0.48, green: 0.50, blue: 0.57))
                                } else {
                                    VStack(alignment: .leading, spacing: metrics.paragraphSpacing) {
                                        ForEach(Array(viewModel.bodyParagraphs.enumerated()), id: \.offset) { index, paragraph in
                                            SelectableTextView(
                                                text: paragraph,
                                                fontSize: fontSize,
                                                selectedWordRange: selectedParagraphIndex == index ? selectedWordRange : nil,
                                                spokenSentenceRange: nil
                                            ) { word, sentence, frame, range in
                                                selectedWord = word
                                                selectedParagraphIndex = index
                                                selectedWordRange = range
                                                wordFrame = frame
                                                showTranslationPopover = true
                                                Task {
                                                    await viewModel.translate(word: word, sentence: sentence)
                                                }
                                            }
                                        }
                                    }
                                }

                                Divider()
                                    .padding(.top, metrics.compactSpacing)

                                completionCard(metrics: metrics)
                            }
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.top, metrics.topPadding)
                            .padding(.bottom, metrics.bottomPadding)
                        }
                    }
                }
                .background(Color.white)

                feedbackToast
            }
            .background(Color.white.ignoresSafeArea())
            .overlay {
                translationPopoverOverlay(screenGeometry: proxy)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadArticleIfNeeded()
        }
        .onDisappear {
            viewModel.stopReading()
        }
        .sheet(isPresented: $showReaderSettings) {
            ArticleReaderSettingsView(fontSize: $fontSize)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .alert("Article Reader", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func topBar(metrics: ArticleReadingMetrics) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: metrics.headerIconFont, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.38, blue: 0.46))
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: metrics.compactSpacing * 1.4) {
                Button {
                    viewModel.toggleReading()
                } label: {
                    Image(systemName: viewModel.isSpeaking ? "stop.circle.fill" : "speaker.wave.2")
                }

                Button {
                    showReaderSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .font(.system(size: metrics.headerIconFont, weight: .semibold))
            .foregroundStyle(Color(red: 0.35, green: 0.38, blue: 0.46))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding * 1.4)
        .padding(.bottom, metrics.compactSpacing * 1.6)
        .frame(minHeight: 60)
    }

    private func metaRow(metrics: ArticleReadingMetrics) -> some View {
        HStack(spacing: metrics.compactSpacing) {
            if let sourceLabel = viewModel.article.sourceLabel {
                Text(sourceLabel)
            } else {
                Text("Article")
            }

            Text("•")

            Text("\(max(viewModel.article.wordCount / 180, 1)) min read")
        }
        .font(.system(size: metrics.metaFont, weight: .medium, design: .rounded))
        .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))
    }

    private func translationPopoverOverlay(screenGeometry: GeometryProxy) -> some View {
        ZStack {
            if showTranslationPopover {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showTranslationPopover = false
                        selectedParagraphIndex = nil
                        selectedWordRange = nil
                    }

                TranslationPopover(
                    originalWord: selectedWord,
                    translationData: viewModel.contextualTranslation,
                    isLoading: viewModel.isTranslating || viewModel.isSavingWord,
                    onSave: {
                        Task {
                            await viewModel.saveWordToVocab(word: selectedWord)
                            showTranslationPopover = false
                            selectedParagraphIndex = nil
                            selectedWordRange = nil
                        }
                    },
                    onPlayAudio: {
                        let utterance = AVSpeechUtterance(string: selectedWord)
                        utterance.voice = AVSpeechSynthesisVoice(language: Config.learningTargetLanguageCode)
                        AVSpeechSynthesizer().speak(utterance)
                    }
                )
                .modifier(PopoverPositioner(wordFrame: wordFrame))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
        .allowsHitTesting(showTranslationPopover)
    }

    @ViewBuilder
    private var feedbackToast: some View {
        if let feedbackMessage = viewModel.feedbackMessage {
            Text(feedbackMessage)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(radius: 5)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: feedbackMessage) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if viewModel.feedbackMessage == feedbackMessage {
                        viewModel.feedbackMessage = nil
                    }
                }
        }
    }

    private func completionCard(metrics: ArticleReadingMetrics) -> some View {
        VStack(spacing: metrics.compactSpacing) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.04, green: 0.78, blue: 0.31))
                    .frame(width: metrics.bottomEmojiSize + 8, height: metrics.bottomEmojiSize + 8)

                Image(systemName: "book")
                    .font(.system(size: metrics.bottomEmojiSize * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Tap Any Word to Translate")
                .font(.system(size: metrics.bottomTitleFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.21, blue: 0.26))

            Text("Selected words can be translated and added to your vocabook.")
                .font(.system(size: metrics.bottomSubtitleFont, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Back to Library")
                    .font(.system(size: metrics.bottomButtonFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.bottomButtonHeight)
                    .background(Color.blue)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.bottomButtonHeight / 3, style: .continuous)
                            .stroke(Color(red: 0.86, green: 0.88, blue: 0.92), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: metrics.bottomButtonHeight / 3, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, metrics.compactSpacing * 0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(metrics.bottomCardPadding)
        .background(Color(red: 0.94, green: 1.00, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: metrics.bottomCardCornerRadius, style: .continuous))
    }
}

private struct ArticleReaderSettingsView: View {
    @Binding var fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Reading Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.21, blue: 0.26))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Font Size")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(Int(fontSize))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.32, green: 0.29, blue: 0.98))
                }

                Slider(value: $fontSize, in: 14...28, step: 1)
                    .tint(Color(red: 0.32, green: 0.29, blue: 0.98))

                HStack {
                    Text("Smaller")
                    Spacer()
                    Text("Larger")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
            }

            Spacer()
        }
        .padding(24)
        .presentationBackground(Color.white)
    }
}

private struct ArticleReadingMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let compactSpacing: CGFloat
    let metaFont: CGFloat
    let titleFont: CGFloat
    let paragraphSpacing: CGFloat
    let headerIconFont: CGFloat
    let bottomCardPadding: CGFloat
    let bottomCardCornerRadius: CGFloat
    let bottomEmojiSize: CGFloat
    let bottomTitleFont: CGFloat
    let bottomSubtitleFont: CGFloat
    let bottomButtonFont: CGFloat
    let bottomButtonHeight: CGFloat

    init(screenSize: CGSize) {
        let widthScale = screenSize.width / 393
        let heightScale = screenSize.height / 852
        let resolvedScale = min(max(min(widthScale, heightScale), 0.88), 1.12)
        let compactScale: CGFloat = screenSize.height < 760 ? 0.95 : 1.0

        func scaled(_ value: CGFloat) -> CGFloat {
            value * resolvedScale * compactScale
        }

        horizontalPadding = scaled(16)
        topPadding = scaled(14)
        bottomPadding = scaled(28)
        sectionSpacing = scaled(16)
        compactSpacing = scaled(8)
        metaFont = scaled(12)
        titleFont = scaled(22)
        paragraphSpacing = scaled(18)
        headerIconFont = scaled(22)
        bottomCardPadding = scaled(16)
        bottomCardCornerRadius = scaled(14)
        bottomEmojiSize = scaled(28)
        bottomTitleFont = scaled(18)
        bottomSubtitleFont = scaled(12)
        bottomButtonFont = scaled(22)
        bottomButtonHeight = scaled(55)
    }
}
