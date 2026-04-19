import SwiftUI

struct VocabookView: View {
    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @ObservedObject var vocabookViewModel: VocabookViewModel

    @State private var isReviewing = false
    @State private var isAddingNewWord = false
    @State private var isQuizzing = false
    @State private var isShowingSearch = false
    @State private var isShowingBookMode = false
    @State private var isPreparingBookMode = false
    @State private var infoMessage: String?

    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = VocabookMetrics(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    header(metrics: metrics)
                    searchBar(metrics: metrics)
                    totalVocabularyCard(metrics: metrics)
                    quickActions(metrics: metrics)
                    memoryLevels(metrics: metrics)
                    recentlyAdded(metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
            .background(Color(red: 0.99, green: 0.99, blue: 1.00).ignoresSafeArea())
            .overlay {
                if isInitialLoading || isPreparingBookMode {
                    ZStack {
                        Color.black.opacity(0.16).ignoresSafeArea()
                        ProgressView(isPreparingBookMode ? "Opening Book..." : "Loading...")
                            .progressViewStyle(.circular)
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            await loadDashboardData()
        }
        .refreshable {
            await loadDashboardData()
        }
        .fullScreenCover(isPresented: $isReviewing, onDismiss: {
            Task { await loadDashboardData() }
        }) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isAddingNewWord, onDismiss: {
            Task { await loadDashboardData() }
        }) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isShowingSearch) {
            WordSearchView(vocabookVM: vocabookViewModel)
        }
        .fullScreenCover(isPresented: $isQuizzing, onDismiss: {
            Task { await loadDashboardData() }
        }) {
            ExamView()
        }
        .fullScreenCover(isPresented: $isShowingBookMode) {
            NavigationStack {
                if let config = bookModeConfig {
                    VocapageHostView(
                        allVocapageIds: config.allPageIds,
                        selectedVocapageId: config.selectedPageId,
                        flashcardViewModel: flashcardViewModel,
                        isShowingDueWordsOnly: $isShowingDueWordsOnly,
                        onFilterChange: {
                            Task {
                                await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
                            }
                        }
                    )
                } else {
                    ZStack {
                        Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
                        ProgressView("Loading Book...")
                    }
                }
            }
        }
        .alert("Notice", isPresented: infoAlertBinding) {
            Button("OK", role: .cancel) { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
        }
    }

    private func header(metrics: VocabookMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            Text("Vocabook")
                .font(.system(size: metrics.titleFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))

            Text("Browse & manage your vocabulary")
                .font(.system(size: metrics.subtitleFont, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.52, green: 0.55, blue: 0.63))
        }
    }

    private func searchBar(metrics: VocabookMetrics) -> some View {
        Button {
            isShowingSearch = true
        } label: {
            HStack(spacing: metrics.compactSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: metrics.searchIconFont, weight: .semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.79))

                Text("Search vocabulary...")
                    .font(.system(size: metrics.searchFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.67, green: 0.69, blue: 0.76))

                Spacer()
            }
            .padding(.horizontal, metrics.searchHorizontalPadding)
            .frame(height: metrics.searchHeight)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func totalVocabularyCard(metrics: VocabookMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.cardTextSpacing) {
            Text("Total Vocabulary")
                .font(.system(size: metrics.smallLabelFont, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Text("\(totalVocabularyCount) words")
                .font(.system(size: metrics.heroNumberFont, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)

            Text("Your complete vocabulary library")
                .font(.system(size: metrics.heroSubtitleFont, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.cardPadding)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.40, green: 0.20, blue: 1.00),
                    Color(red: 0.72, green: 0.20, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.largeCardCornerRadius, style: .continuous))
    }

    private func quickActions(metrics: VocabookMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.compactSectionSpacing) {
            sectionTitle("QUICK ACTIONS", metrics: metrics)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: metrics.compactSpacing),
                GridItem(.flexible(), spacing: metrics.compactSpacing)
            ], spacing: metrics.compactSpacing) {
                VocabookActionCard(
                    title: "Card Review",
                    subtitle: "Flashcard mode",
                    icon: "square.stack.3d.up.fill",
                    fill: LinearGradient(
                        colors: [Color(red: 0.05, green: 0.78, blue: 0.39), Color(red: 0.00, green: 0.63, blue: 0.37)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    metrics: metrics,
                    isFilled: true
                ) {
                    isReviewing = true
                }

                VocabookActionCard(
                    title: "Quiz Review",
                    subtitle: "Multiple choice",
                    icon: "checkmark.square",
                    fill: nil,
                    borderColor: Color(red: 0.87, green: 0.77, blue: 1.00),
                    iconColor: Color(red: 0.70, green: 0.43, blue: 0.98),
                    textColor: Color(red: 0.17, green: 0.18, blue: 0.24),
                    subtitleColor: Color(red: 0.52, green: 0.55, blue: 0.63),
                    metrics: metrics
                ) {
                    isQuizzing = true
                }

                VocabookActionCard(
                    title: "Book Mode",
                    subtitle: "Read & listen",
                    icon: "book.closed",
                    fill: nil,
                    borderColor: Color(red: 0.74, green: 0.84, blue: 1.00),
                    iconColor: Color(red: 0.30, green: 0.46, blue: 0.98),
                    textColor: Color(red: 0.17, green: 0.18, blue: 0.24),
                    subtitleColor: Color(red: 0.52, green: 0.55, blue: 0.63),
                    metrics: metrics
                ) {
                    openBookMode()
                }

                VocabookActionCard(
                    title: "Add Word",
                    subtitle: "New vocabulary",
                    icon: "plus",
                    fill: LinearGradient(
                        colors: [Color(red: 1.00, green: 0.61, blue: 0.12), Color(red: 1.00, green: 0.41, blue: 0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    metrics: metrics,
                    isFilled: true
                ) {
                    isAddingNewWord = true
                }
            }
        }
    }

    private func memoryLevels(metrics: VocabookMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.compactSectionSpacing) {
            sectionTitle("BY MEMORY LEVEL", metrics: metrics)

            VStack(spacing: metrics.compactSpacing) {
                ForEach(memoryLevelRows) { item in
                    MemoryLevelRow(item: item, metrics: metrics)
                }
            }
        }
    }

    private func recentlyAdded(metrics: VocabookMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.compactSectionSpacing) {
            HStack {
                sectionTitle("RECENTLY ADDED", metrics: metrics)
                Spacer()
                Button {
                    openBookMode()
                } label: {
                    Text("View All")
                        .font(.system(size: metrics.linkFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.98))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: metrics.compactSpacing) {
                if recentlyAddedCards.isEmpty {
                    Text("Your latest words will appear here.")
                        .font(.system(size: metrics.bodyFont, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(metrics.cardPadding)
                        .background(Color(red: 0.95, green: 0.97, blue: 1.00))
                        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
                } else {
                    ForEach(recentlyAddedCards, id: \.id) { card in
                        RecentWordCard(card: card, metrics: metrics)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String, metrics: VocabookMetrics) -> some View {
        Text(text)
            .font(.system(size: metrics.sectionLabelFont, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.56))
    }

    private var allFlashcards: [Flashcard] {
        vocabookViewModel.vocabook?.vocapages?.flatMap { $0.flashcards ?? [] } ?? []
    }

    private var totalVocabularyCount: Int {
        max(vocabookViewModel.totalCards, allFlashcards.count)
    }

    private var recentlyAddedCards: [Flashcard] {
        Array(allFlashcards.sorted { $0.id > $1.id }.prefix(4))
    }

    private var memoryLevelRows: [MemoryLevelItem] {
        [
            MemoryLevelItem(title: "Remembered", subtitle: "\(countForTier("remembered")) words", count: countForTier("remembered"), accent: Color(red: 0.00, green: 0.80, blue: 0.38)),
            MemoryLevelItem(title: "Almost Remembered", subtitle: "\(countForTier("monthly")) words", count: countForTier("monthly"), accent: Color(red: 0.22, green: 0.49, blue: 1.00)),
            MemoryLevelItem(title: "Well Practiced", subtitle: "\(countForTier("weekly")) words", count: countForTier("weekly"), accent: Color(red: 0.67, green: 0.33, blue: 1.00)),
            MemoryLevelItem(title: "Getting Familiar", subtitle: "\(countForTier("warmup")) words", count: countForTier("warmup"), accent: Color(red: 1.00, green: 0.59, blue: 0.04)),
            MemoryLevelItem(title: "New Word", subtitle: "\(countForTier("new")) words", count: countForTier("new"), accent: Color(red: 0.56, green: 0.58, blue: 0.64))
        ]
    }

    private var tierCountMap: [String: Int] {
        if !vocabookViewModel.tierStats.isEmpty {
            return Dictionary(uniqueKeysWithValues: vocabookViewModel.tierStats.map { ($0.tier, $0.count) })
        }

        let grouped = Dictionary(grouping: allFlashcards) { ($0.reviewTire?.isEmpty == false ? $0.reviewTire! : "new") }
        return grouped.mapValues(\.count)
    }

    private func countForTier(_ tier: String) -> Int {
        tierCountMap[tier] ?? 0
    }

    private var isInitialLoading: Bool {
        vocabookViewModel.isLoadingVocabooks && vocabookViewModel.vocabook?.vocapages == nil
    }

    private var bookModeConfig: BookModeConfig? {
        let allPageIds = (vocabookViewModel.vocabook?.vocapages ?? []).map(\.id).sorted()
        guard !allPageIds.isEmpty else { return nil }
        let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
        let selectedPageId = (lastViewedID != 0 && allPageIds.contains(lastViewedID)) ? lastViewedID : (allPageIds.first ?? 1)
        return BookModeConfig(allPageIds: allPageIds, selectedPageId: selectedPageId)
    }

    private var infoAlertBinding: Binding<Bool> {
        Binding(
            get: { infoMessage != nil },
            set: { newValue in
                if !newValue { infoMessage = nil }
            }
        )
    }

    private func loadDashboardData() async {
        await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
        await vocabookViewModel.loadStatistics()
        if flashcardViewModel.reviewCards.isEmpty {
            await flashcardViewModel.prepareReviewSession()
        }
    }

    private func openBookMode() {
        guard !isPreparingBookMode else { return }
        isPreparingBookMode = true

        Task {
            await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
            isPreparingBookMode = false

            if bookModeConfig != nil {
                isShowingBookMode = true
            } else {
                infoMessage = "No words are available in book mode yet."
            }
        }
    }
}

private struct BookModeConfig {
    let allPageIds: [Int]
    let selectedPageId: Int
}

private struct MemoryLevelItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let count: Int
    let accent: Color
}

private struct VocabookMetrics {
    let scale: CGFloat
    let compactHeightScale: CGFloat

    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let compactSectionSpacing: CGFloat
    let compactSpacing: CGFloat
    let headerSpacing: CGFloat
    let cardTextSpacing: CGFloat

    let titleFont: CGFloat
    let subtitleFont: CGFloat
    let sectionLabelFont: CGFloat
    let bodyFont: CGFloat
    let linkFont: CGFloat
    let smallLabelFont: CGFloat
    let heroNumberFont: CGFloat
    let heroSubtitleFont: CGFloat

    let searchHeight: CGFloat
    let searchHorizontalPadding: CGFloat
    let searchFont: CGFloat
    let searchIconFont: CGFloat

    let cardPadding: CGFloat
    let cardCornerRadius: CGFloat
    let largeCardCornerRadius: CGFloat

    let actionIconCircle: CGFloat
    let actionIconFont: CGFloat
    let actionTitleFont: CGFloat
    let actionSubtitleFont: CGFloat
    let actionHeight: CGFloat

    let memoryRowLeadingBarWidth: CGFloat
    let memoryRowCountFont: CGFloat
    let memoryRowTitleFont: CGFloat
    let memoryRowSubtitleFont: CGFloat
    let recentWordTitleFont: CGFloat
    let recentWordSubtitleFont: CGFloat
    let recentBadgeFont: CGFloat

    init(screenSize: CGSize) {
        let widthScale = screenSize.width / 393
        let heightScale = screenSize.height / 852
        let resolvedScale = min(max(min(widthScale, heightScale), 0.84), 1.08)
        let compactScale: CGFloat = screenSize.height < 760 ? 0.92 : 1.0

        func scaled(_ value: CGFloat) -> CGFloat {
            value * resolvedScale * compactScale
        }

        scale = resolvedScale
        compactHeightScale = compactScale

        horizontalPadding = scaled(16)
        topPadding = scaled(14)
        bottomPadding = scaled(22)
        sectionSpacing = scaled(18)
        compactSectionSpacing = scaled(10)
        compactSpacing = scaled(8)
        headerSpacing = scaled(3)
        cardTextSpacing = scaled(4)

        titleFont = scaled(30)
        subtitleFont = scaled(14.5)
        sectionLabelFont = scaled(13.5)
        bodyFont = scaled(16.5)
        linkFont = scaled(13.5)
        smallLabelFont = scaled(13)
        heroNumberFont = scaled(31)
        heroSubtitleFont = scaled(13.5)

        searchHeight = scaled(34)
        searchHorizontalPadding = scaled(12)
        searchFont = scaled(14.5)
        searchIconFont = scaled(14)

        cardPadding = scaled(12)
        cardCornerRadius = scaled(12)
        largeCardCornerRadius = scaled(14)

        actionIconCircle = scaled(22)
        actionIconFont = scaled(10)
        actionTitleFont = scaled(14.5)
        actionSubtitleFont = scaled(12)
        actionHeight = scaled(58)

        memoryRowLeadingBarWidth = max(2, scaled(3))
        memoryRowCountFont = scaled(14.5)
        memoryRowTitleFont = scaled(15.5)
        memoryRowSubtitleFont = scaled(12)
        recentWordTitleFont = scaled(15.5)
        recentWordSubtitleFont = scaled(12)
        recentBadgeFont = scaled(10)
    }
}

private struct VocabookActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let fill: LinearGradient?
    var borderColor: Color = .clear
    var iconColor: Color = .white
    var textColor: Color = .white
    var subtitleColor: Color = .white.opacity(0.9)
    let metrics: VocabookMetrics
    var isFilled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: metrics.cardTextSpacing) {
                HStack(spacing: metrics.compactSpacing) {
                    ZStack {
                        Circle()
                            .fill(isFilled ? Color.white.opacity(0.18) : Color(red: 0.95, green: 0.96, blue: 1.00))
                            .frame(width: metrics.actionIconCircle, height: metrics.actionIconCircle)
                        Image(systemName: icon)
                            .font(.system(size: metrics.actionIconFont, weight: .bold))
                            .foregroundStyle(iconColor)
                    }

                    Spacer()
                }

                Text(title)
                    .font(.system(size: metrics.actionTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.system(size: metrics.actionSubtitleFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: metrics.actionHeight, alignment: .leading)
            .padding(metrics.cardPadding)
            .background(
                Group {
                    if isFilled, let fill {
                        fill
                    } else {
                        Color.white
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MemoryLevelRow: View {
    let item: MemoryLevelItem
    let metrics: VocabookMetrics

    var body: some View {
        HStack(spacing: metrics.compactSpacing) {
            RoundedRectangle(cornerRadius: metrics.memoryRowLeadingBarWidth, style: .continuous)
                .fill(item.accent)
                .frame(width: metrics.memoryRowLeadingBarWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: metrics.memoryRowTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.24))

                Text(item.subtitle)
                    .font(.system(size: metrics.memoryRowSubtitleFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.58))
            }

            Spacer()

            Text("\(item.count)")
                .font(.system(size: metrics.memoryRowCountFont, weight: .heavy, design: .rounded))
                .foregroundStyle(item.accent)
                .padding(.horizontal, metrics.cardPadding * 0.7)
                .padding(.vertical, metrics.cardPadding * 0.35)
                .background(Capsule().fill(item.accent.opacity(0.10)))

            Image(systemName: "chevron.right")
                .font(.system(size: metrics.recentBadgeFont, weight: .bold))
                .foregroundStyle(Color(red: 0.74, green: 0.75, blue: 0.80))
        }
        .padding(metrics.cardPadding)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct RecentWordCard: View {
    let card: Flashcard
    let metrics: VocabookMetrics

    private var titleText: String {
        card.wordDefinition?.attributes.word?.data?.attributes.targetText ?? card.backContent
    }

    private var subtitleText: String {
        if let base = card.wordDefinition?.attributes.baseText, !base.isEmpty {
            return "Meaning: \(base)"
        }
        return "Saved in your vocabook"
    }

    private var tierTitle: String {
        switch card.reviewTire {
        case "remembered": return "Remembered"
        case "monthly": return "Almost Remembered"
        case "weekly": return "Well Practiced"
        case "warmup": return "Getting Familiar"
        default: return "New Word"
        }
    }

    private var tierColor: Color {
        switch card.reviewTire {
        case "remembered": return Color.green
        case "monthly": return Color.blue
        case "weekly": return Color.purple
        case "warmup": return Color.orange
        default: return Color.indigo
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.compactSpacing) {
            Image(systemName: "doc.text")
                .font(.system(size: metrics.actionIconFont, weight: .bold))
                .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.98))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: metrics.compactSpacing) {
                    Text(titleText)
                        .font(.system(size: metrics.recentWordTitleFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: metrics.compactSpacing)

                    Text(tierTitle)
                        .font(.system(size: metrics.recentBadgeFont, weight: .bold, design: .rounded))
                        .foregroundStyle(tierColor)
                        .padding(.horizontal, metrics.cardPadding * 0.55)
                        .padding(.vertical, metrics.cardPadding * 0.25)
                        .background(Capsule().fill(tierColor.opacity(0.12)))
                }

                Text(subtitleText)
                    .font(.system(size: metrics.recentWordSubtitleFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.cardPadding)
        .background(Color(red: 0.92, green: 0.95, blue: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }
}
