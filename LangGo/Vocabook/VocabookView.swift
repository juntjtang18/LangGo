import SwiftUI
import os

private enum MemoryTier: String, CaseIterable {
    case remembered
    case monthly
    case weekly
    case warmup
    case new

    var title: String {
        switch self {
        case .remembered: return "Remembered"
        case .monthly: return "Almost Remembered"
        case .weekly: return "Well Practiced"
        case .warmup: return "Getting Familiar"
        case .new: return "New Word"
        }
    }

    var accent: Color {
        switch self {
        case .remembered: return Color(red: 0.00, green: 0.80, blue: 0.38)
        case .monthly: return Color(red: 0.22, green: 0.49, blue: 1.00)
        case .weekly: return Color(red: 0.67, green: 0.33, blue: 1.00)
        case .warmup: return Color(red: 1.00, green: 0.59, blue: 0.04)
        case .new: return Color(red: 0.56, green: 0.58, blue: 0.64)
        }
    }

    static func canonicalKey(for rawTier: String?) -> String {
        let normalized = (rawTier ?? "new")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "remembered", "mastered":
            return MemoryTier.remembered.rawValue
        case "monthly", "almostremembered":
            return MemoryTier.monthly.rawValue
        case "weekly", "wellpracticed", "wellpractised":
            return MemoryTier.weekly.rawValue
        case "warmup", "gettingfamiliar":
            return MemoryTier.warmup.rawValue
        case "", "new", "newword", "newwords":
            return MemoryTier.new.rawValue
        default:
            return normalized
        }
    }

    static func from(rawTier: String?) -> MemoryTier {
        MemoryTier(rawValue: canonicalKey(for: rawTier)) ?? .new
    }
}

struct VocabookView: View {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocabookView")

    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @ObservedObject var vocabookViewModel: VocabookViewModel

    @State private var isReviewing = false
    @State private var isAddingNewWord = false
    @State private var isQuizzing = false
    @State private var isShowingSearch = false
    @State private var isShowingBookMode = false
    @State private var isPreparingBookMode = false
    @State private var infoMessage: String?
    @State private var recentAddedCount: Int = 0
    @State private var recentFlashcards: [Flashcard] = []
    @State private var selectedRecentCard: Flashcard?
    @State private var presentedBookModeConfig: BookModeConfig?
    @State private var presentedBookModeTier: String?
    @State private var recentlyAddedBookModeLimit = 0

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
        // VocabookViewModel already observes .flashcardsDidChange and refreshes
        // vocabook pages/statistics. Do not also refresh here, or one flashcard
        // review can trigger duplicate /api/flashcard-stat requests.
        .onReceive(NotificationCenter.default.publisher(for: .userSnapshotDidChange)) { _ in
            Task {
                await syncRecentAddedCount()
                await refreshRecentlyAddedCards()
            }
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
        .fullScreenCover(isPresented: $isShowingBookMode, onDismiss: {
            presentedBookModeConfig = nil
            presentedBookModeTier = nil
            recentlyAddedBookModeLimit = 0
        }) {
            NavigationStack {
                if let config = bookModeConfig {
                    VocapageHostView(
                        allVocapageIds: config.allPageIds,
                        selectedVocapageId: config.selectedPageId,
                        flashcardViewModel: flashcardViewModel,
                        isShowingDueWordsOnly: $isShowingDueWordsOnly,
                        reviewTier: presentedBookModeTier,
                        allowsDueFilter: presentedBookModeTier == nil && recentlyAddedBookModeLimit == 0,
                        recentlyAddedLimit: recentlyAddedBookModeLimit,
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
        .sheet(item: $selectedRecentCard) { card in
            WordDetailSheet(
                cards: recentFlashcards,
                initialIndex: recentFlashcards.firstIndex(where: { $0.id == card.id }) ?? 0,
                showBaseText: true,
                showNavRow: false
            )
            .presentationDetents([.fraction(0.67)])
            .presentationDragIndicator(.visible)
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

            HStack(alignment: .lastTextBaseline, spacing: metrics.compactSpacing) {
                Text("\(totalVocabularyCount) words")
                    .font(.system(size: metrics.heroNumberFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                Text(newAddedWordsText)
                    .font(.system(size: metrics.heroSubNumberFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.71, green: 1.00, blue: 0.77))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text("Your complete vocabulary library")
                .font(.system(size: metrics.heroSubtitleFont, weight: .light, design: .rounded))
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
                    MemoryLevelRow(item: item, metrics: metrics) {
                        openBookMode(for: item.tier)
                    }
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
                    openRecentlyAddedBookMode()
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
                        RecentWordCard(card: card, metrics: metrics) {
                            selectedRecentCard = card
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String, metrics: VocabookMetrics) -> some View {
        Text(text)
            .font(.system(size: metrics.sectionLabelFont, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.56))
    }

    private var totalVocabularyCount: Int {
        vocabookViewModel.totalCards
    }

    private var newAddedWordsText: String {
        formatDelta(recentAddedCount)
    }

    private var recentlyAddedCards: [Flashcard] {
        recentFlashcards
    }

    private var memoryLevelRows: [MemoryLevelItem] {
        MemoryTier.allCases.map { tier in
            let count = countForTier(tier)
            return MemoryLevelItem(
                tier: tier,
                title: tier.title,
                subtitle: "\(count) words",
                count: count,
                accent: tier.accent
            )
        }
    }

    private var tierCountMap: [String: Int] {
        vocabookViewModel.tierStats.reduce(into: [:]) { partialResult, stat in
            let key = MemoryTier.canonicalKey(for: stat.tier)
            partialResult[key, default: 0] += stat.count
        }
    }

    private func countForTier(_ tier: MemoryTier) -> Int {
        tierCountMap[tier.rawValue] ?? 0
    }

    private var isInitialLoading: Bool {
        vocabookViewModel.isLoadingVocabooks && vocabookViewModel.vocabook?.vocapages == nil
    }

    private var bookModeConfig: BookModeConfig? {
        presentedBookModeConfig
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
        //await vocabookViewModel.loadStatistics()
        if flashcardViewModel.reviewCards.isEmpty {
            await flashcardViewModel.prepareReviewSession()
        }

        await syncRecentAddedCount()
        await refreshRecentlyAddedCards()
    }

    private var baseLanguageLocale: String {
        UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
    }
    /*
    private func refreshRecentAddedCount() async {
        do {
            let snapshot = try await DataServices.shared.userSnapshotService.refreshSnapshot(locale: baseLanguageLocale)
            recentAddedCount = snapshot?.word_add ?? 0
        } catch {
            logger.error("Failed to fetch recent added count for vocabook: \(error.localizedDescription, privacy: .public)")
            recentAddedCount = 0
        }
    }
     */
    private func syncRecentAddedCount() async {
        await DataServices.shared.userSnapshotService.loadSnapshot(locale: baseLanguageLocale)
        recentAddedCount = DataServices.shared.userSnapshotService.currentSnapshot(locale: baseLanguageLocale)?.word_add ?? 0
    }

    private func refreshRecentlyAddedCards() async {
        let recentCount = recentAddedCount
        guard recentCount > 0 else {
            recentFlashcards = []
            return
        }

        do {
            recentFlashcards = try await DataServices.shared.flashcardService.fetchRecentlyAddedFlashcards(limit: recentCount)
        } catch {
            logger.error("Failed to fetch recent flashcards for vocabook: \(error.localizedDescription, privacy: .public)")
            recentFlashcards = []
        }
    }

    private func formatDelta(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private func openBookMode() {
        guard !isPreparingBookMode else { return }
        isPreparingBookMode = true

        Task {
            await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
            isPreparingBookMode = false

            if let config = defaultBookModeConfig() {
                presentedBookModeTier = nil
                presentedBookModeConfig = config
                isShowingBookMode = true
            } else {
                infoMessage = "No words are available in book mode yet."
            }
        }
    }

    private func openRecentlyAddedBookMode() {
        guard !isPreparingBookMode else { return }
        let limit = max(recentAddedCount, recentFlashcards.count)
        guard limit > 0 else {
            infoMessage = "No recently added words yet."
            return
        }
        isPreparingBookMode = true

        Task {
            do {
                let vbSetting = try await DataServices.shared.settingsService.fetchVBSetting()
                let pageSize = vbSetting.attributes.wordsPerPage
                let cards = try await DataServices.shared.flashcardService.fetchRecentlyAddedFlashcards(limit: limit)
                let pageCount = cards.isEmpty ? 0 : Int(ceil(Double(cards.count) / Double(pageSize)))

                isPreparingBookMode = false

                if pageCount > 0 {
                    recentlyAddedBookModeLimit = limit
                    presentedBookModeTier = nil
                    presentedBookModeConfig = BookModeConfig(allPageIds: Array(1...pageCount), selectedPageId: 1)
                    isShowingBookMode = true
                } else {
                    infoMessage = "No recently added words yet."
                }
            } catch {
                isPreparingBookMode = false
                logger.error("Failed to open recently added book mode: \(error.localizedDescription, privacy: .public)")
                infoMessage = "Failed to open recently added."
            }
        }
    }

    private func openBookMode(for tier: MemoryTier) {
        guard !isPreparingBookMode else { return }
        guard countForTier(tier) > 0 else {
            infoMessage = "No words are available for \(tier.title) yet."
            return
        }

        isPreparingBookMode = true

        Task {
            do {
                let vbSetting = try await DataServices.shared.settingsService.fetchVBSetting()
                let pageSize = max(1, vbSetting.attributes.wordsPerPage)
                let tierCount = countForTier(tier)
                let pageCount = tierCount == 0 ? 0 : Int(ceil(Double(tierCount) / Double(pageSize)))

                if pageCount > 0 {
                    presentedBookModeTier = tier.rawValue
                    presentedBookModeConfig = BookModeConfig(
                        allPageIds: Array(1...pageCount),
                        selectedPageId: 1
                    )
                    isShowingBookMode = true
                } else {
                    infoMessage = "No words are available for \(tier.title) yet."
                }
            } catch {
                logger.error("Failed to open tier book mode: \(error.localizedDescription, privacy: .public)")
                infoMessage = "Failed to open \(tier.title)."
            }

            isPreparingBookMode = false
        }
    }

    private func defaultBookModeConfig() -> BookModeConfig? {
        let allPageIds = (vocabookViewModel.vocabook?.vocapages ?? []).map(\.id).sorted()
        guard !allPageIds.isEmpty else { return nil }
        let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
        let selectedPageId = (lastViewedID != 0 && allPageIds.contains(lastViewedID)) ? lastViewedID : (allPageIds.first ?? 1)
        return BookModeConfig(allPageIds: allPageIds, selectedPageId: selectedPageId)
    }
}

private struct BookModeConfig {
    let allPageIds: [Int]
    let selectedPageId: Int
}

private struct MemoryLevelItem: Identifiable {
    let id = UUID()
    let tier: MemoryTier
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
    let heroSubNumberFont: CGFloat
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

        horizontalPadding = scaled(20)
        topPadding = scaled(20)
        bottomPadding = scaled(26)
        sectionSpacing = scaled(20)
        compactSectionSpacing = scaled(15)
        compactSpacing = scaled(12)
        headerSpacing = scaled(6)
        cardTextSpacing = scaled(8)

        titleFont = scaled(30)
        subtitleFont = scaled(20)
        sectionLabelFont = scaled(20)
        bodyFont = scaled(26)
        linkFont = scaled(26)
        smallLabelFont = scaled(22)
        heroNumberFont = scaled(36)
        heroSubNumberFont = scaled(26)
        heroSubtitleFont = scaled(20)

        searchHeight = scaled(38)
        searchHorizontalPadding = scaled(15)
        searchFont = scaled(22)
        searchIconFont = scaled(22)

        cardPadding = scaled(14)
        cardCornerRadius = scaled(14)
        largeCardCornerRadius = scaled(16)

        actionIconCircle = scaled(28)
        actionIconFont = scaled(28)
        actionTitleFont = scaled(22)
        actionSubtitleFont = scaled(18)
        actionHeight = scaled(60)

        memoryRowLeadingBarWidth = max(2, scaled(3))
        memoryRowCountFont = scaled(24)
        memoryRowTitleFont = scaled(24)
        memoryRowSubtitleFont = scaled(20)
        recentWordTitleFont = scaled(22)
        recentWordSubtitleFont = scaled(20)
        recentBadgeFont = scaled(20)
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
            HStack(alignment: .center, spacing: metrics.compactSpacing) {
                
                ZStack {
                    Circle()
                        .fill(isFilled ? Color.white.opacity(0.18) : Color(red: 0.95, green: 0.96, blue: 1.00))
                        .frame(width: metrics.actionIconCircle, height: metrics.actionIconCircle)

                    Image(systemName: icon)
                        .font(.system(size: metrics.actionIconFont, weight: .bold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) { // tight spacing
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

                Spacer(minLength: 0)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.compactSpacing) {
                RoundedRectangle(cornerRadius: metrics.memoryRowLeadingBarWidth, style: .continuous)
                    .fill(item.accent)
                    .frame(width: metrics.memoryRowLeadingBarWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: metrics.memoryRowTitleFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.24))
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
        .buttonStyle(.plain)
    }
}

private struct RecentWordCard: View {
    let card: Flashcard
    let metrics: VocabookMetrics
    let action: () -> Void

    private var titleText: String {
        card.wordDefinition?.attributes.word?.data?.attributes.targetText ?? card.backContent
    }

    private var subtitleText: String {
        if let base = card.wordDefinition?.attributes.baseText, !base.isEmpty {
            return "\(base)"
        }
        return "Saved in your vocabook"
    }

    private var tierTitle: String {
        MemoryTier.from(rawTier: card.reviewTire).title
    }

    private var tierColor: Color {
        MemoryTier.from(rawTier: card.reviewTire).accent
    }

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }
}
