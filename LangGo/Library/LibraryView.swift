import SwiftUI

struct LibraryTabView: View {
    @Binding var isSideMenuShowing: Bool

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("")
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            withAnimation(.easeInOut) { isSideMenuShowing.toggle() }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                    }
                }
        }
    }
}

struct LibraryView: View {
    @State private var selectedMode: LibraryMode = .myLibrary
    @State private var libraryArticles = LibraryArticle.myLibraryMocks
    @State private var discoverArticles = LibraryArticle.discoverMocks
    @State private var selectedArticle: LibraryArticle?
    @State private var expandedArticleID: LibraryArticle.ID?
    @State private var isShowingAddMenu = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = LibraryMetrics(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    header(metrics: metrics)
                    modePicker(metrics: metrics)

                    if selectedMode == .myLibrary {
                        tagFilters(metrics: metrics)
                        libraryList(metrics: metrics)
                    } else {
                        discoverList(metrics: metrics)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
            .background(Color(red: 0.99, green: 0.99, blue: 1.00).ignoresSafeArea())
            .overlay {
                if isShowingAddMenu {
                    LibraryAddMenuOverlay(metrics: metrics) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingAddMenu = false
                        }
                    } onScanArticle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingAddMenu = false
                        }
                    } onImportURL: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingAddMenu = false
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReadingView(article: article)
        }
    }

    private func header(metrics: LibraryMetrics) -> some View {
        HStack {
            Text("Articles")
                .font(.system(size: metrics.titleFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))

            Spacer()

            if selectedMode == .myLibrary {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingAddMenu = true
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.addButtonCornerRadius, style: .continuous)
                            .fill(Color(red: 0.32, green: 0.29, blue: 0.98))
                            .frame(width: metrics.addButtonSize, height: metrics.addButtonSize)
                            .shadow(color: Color(red: 0.32, green: 0.29, blue: 0.98).opacity(0.20), radius: 6, y: 2)

                        Image(systemName: "plus")
                            .font(.system(size: metrics.addButtonIconFont, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modePicker(metrics: LibraryMetrics) -> some View {
        HStack(spacing: metrics.segmentSpacing) {
            ForEach(LibraryMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: metrics.segmentFont, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedMode == mode ? Color(red: 0.21, green: 0.23, blue: 0.29) : Color(red: 0.47, green: 0.49, blue: 0.56))
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.segmentHeight)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.segmentInnerCornerRadius, style: .continuous)
                                .fill(selectedMode == mode ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    if mode == .discover {
                        Text("\(discoverBadgeCount)")
                            .font(.system(size: metrics.segmentBadgeFont, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, metrics.segmentBadgeHorizontalPadding)
                            .padding(.vertical, metrics.segmentBadgeVerticalPadding)
                            .background(Capsule().fill(Color(red: 0.88, green: 0.24, blue: 0.88)))
                            .offset(x: metrics.segmentBadgeOffsetX, y: metrics.segmentBadgeOffsetY)
                    }
                }
            }
        }
        .padding(metrics.segmentOuterPadding)
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: metrics.segmentCornerRadius, style: .continuous))
    }

    private func tagFilters(metrics: LibraryMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.filterSpacing) {
            HStack(spacing: metrics.compactSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: metrics.filterIconFont, weight: .semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.79))

                Text("Filter by tags")
                    .font(.system(size: metrics.filterLabelFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.60, blue: 0.67))
            }

            FlexibleTagLayout(spacing: metrics.tagSpacing, rowSpacing: metrics.tagRowSpacing) {
                ForEach(LibraryTag.mockTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: metrics.tagFont, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.44, green: 0.47, blue: 0.55))
                        .padding(.horizontal, metrics.tagHorizontalPadding)
                        .padding(.vertical, metrics.tagVerticalPadding)
                        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func libraryList(metrics: LibraryMetrics) -> some View {
        VStack(spacing: metrics.cardSpacing) {
            ForEach(libraryArticles) { article in
                LibraryArticleCard(
                    article: article,
                    metrics: metrics,
                    isExpanded: expandedArticleID == article.id,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedArticleID = expandedArticleID == article.id ? nil : article.id
                        }
                    },
                    onStartReading: {
                        selectedArticle = article
                    }
                )
            }
        }
    }

    private func discoverList(metrics: LibraryMetrics) -> some View {
        VStack(spacing: metrics.cardSpacing) {
            ForEach(discoverArticles) { article in
                LibraryDiscoverCard(article: article, metrics: metrics) {
                    addDiscoverArticle(article)
                }
            }
        }
    }

    private var discoverBadgeCount: Int {
        min(discoverArticles.count, 3)
    }

    private func addDiscoverArticle(_ article: LibraryArticle) {
        guard let index = discoverArticles.firstIndex(where: { $0.id == article.id }) else { return }

        var moved = discoverArticles.remove(at: index)
        moved.progress = 0.0
        libraryArticles.insert(moved, at: 0)

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedMode = .myLibrary
        }
    }
}

private enum LibraryMode: CaseIterable {
    case myLibrary
    case discover

    var title: String {
        switch self {
        case .myLibrary: return "My Library"
        case .discover: return "Discover"
        }
    }
}

private enum LibraryTag {
    static let mockTags = [
        "Technology", "AI", "Science", "Environment",
        "Business", "Health"
    ]
}

private struct LibraryArticle: Identifiable, Equatable {
    let id: UUID
    let title: String
    let wordCount: Int
    let newWords: Int
    var progress: Double?
    let tag: String?
    let dateLabel: String?
    let sourceLabel: String?
    let level: String?
    let topic: String?

    init(
        id: UUID = UUID(),
        title: String,
        wordCount: Int,
        newWords: Int,
        progress: Double? = nil,
        tag: String? = nil,
        dateLabel: String? = nil,
        sourceLabel: String? = nil,
        level: String? = nil,
        topic: String? = nil
    ) {
        self.id = id
        self.title = title
        self.wordCount = wordCount
        self.newWords = newWords
        self.progress = progress
        self.tag = tag
        self.dateLabel = dateLabel
        self.sourceLabel = sourceLabel
        self.level = level
        self.topic = topic
    }

    static let myLibraryMocks: [LibraryArticle] = [
        .init(title: "Modern Business Strategies", wordCount: 1400, newWords: 52, progress: nil, tag: "Business", dateLabel: "1 week ago", sourceLabel: "URL"),
        .init(title: "Healthcare Innovation in 2026", wordCount: 1100, newWords: 41, progress: 1.00, tag: "Health", dateLabel: "4 days ago", sourceLabel: "URL"),
        .init(title: "Understanding Machine Learning Basics", wordCount: 1350, newWords: 47, progress: 0.15, tag: "AI", dateLabel: "2 days ago", sourceLabel: "URL"),
        .init(title: "The Science Behind Vaccines", wordCount: 980, newWords: 35, progress: 0.75, tag: "Science", dateLabel: "6 days ago", sourceLabel: "URL"),
        .init(title: "Sustainable Business Practices", wordCount: 1250, newWords: 44, progress: nil, tag: "Environment", dateLabel: "1 day ago", sourceLabel: "URL"),
        .init(title: "AI Ethics and Society", wordCount: 1600, newWords: 58, progress: 0.40, tag: "AI", dateLabel: "3 days ago", sourceLabel: "URL"),
        .init(title: "Global Economic Trends 2026", wordCount: 1450, newWords: 51, progress: nil, tag: "Business", dateLabel: "5 days ago", sourceLabel: "URL"),
        .init(title: "Mental Health in the Digital Age", wordCount: 1050, newWords: 39, progress: 0.90, tag: "Health", dateLabel: "2 weeks ago", sourceLabel: "URL")
    ]

    static let discoverMocks: [LibraryArticle] = [
        .init(title: "Breaking: New Renewable Energy Breakthrough", wordCount: 1500, newWords: 65, level: "Advanced", topic: "News"),
        .init(title: "Short Stories: The Lost Letter", wordCount: 950, newWords: 32, level: "Intermediate", topic: "Stories"),
        .init(title: "Everyday Conversations in English", wordCount: 720, newWords: 22, level: "Beginner", topic: "Educational"),
        .init(title: "The History of Space Exploration", wordCount: 1420, newWords: 54, level: "Intermediate", topic: "Science"),
        .init(title: "Advanced Grammar: Subjunctive Mood", wordCount: 1150, newWords: 48, level: "Advanced", topic: "Educational"),
        .init(title: "Street Food Around the World", wordCount: 890, newWords: 28, level: "Beginner", topic: "Culture"),
        .init(title: "Tech Giants and Innovation", wordCount: 1280, newWords: 51, level: "Intermediate", topic: "News"),
        .init(title: "Mystery Story: The Missing Painting", wordCount: 1650, newWords: 72, level: "Advanced", topic: "Stories")
    ]
}

private struct LibraryMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let compactSpacing: CGFloat
    let cardSpacing: CGFloat

    let titleFont: CGFloat
    let addButtonSize: CGFloat
    let addButtonIconFont: CGFloat
    let addButtonCornerRadius: CGFloat
    let segmentFont: CGFloat
    let segmentBadgeFont: CGFloat
    let filterLabelFont: CGFloat
    let filterIconFont: CGFloat
    let tagFont: CGFloat
    let cardTitleFont: CGFloat
    let cardMetaFont: CGFloat
    let progressLabelFont: CGFloat
    let progressValueFont: CGFloat
    let badgeFont: CGFloat
    let iconFont: CGFloat

    let segmentHeight: CGFloat
    let segmentOuterPadding: CGFloat
    let segmentSpacing: CGFloat
    let segmentCornerRadius: CGFloat
    let segmentInnerCornerRadius: CGFloat
    let segmentBadgeHorizontalPadding: CGFloat
    let segmentBadgeVerticalPadding: CGFloat
    let segmentBadgeOffsetX: CGFloat
    let segmentBadgeOffsetY: CGFloat

    let filterSpacing: CGFloat
    let tagSpacing: CGFloat
    let tagRowSpacing: CGFloat
    let tagHorizontalPadding: CGFloat
    let tagVerticalPadding: CGFloat

    let cardPadding: CGFloat
    let expandedCardPadding: CGFloat
    let cardCornerRadius: CGFloat
    let cardBorderWidth: CGFloat
    let cardShadowRadius: CGFloat
    let progressHeight: CGFloat
    let iconButtonSize: CGFloat
    let progressSpacing: CGFloat
    let metaSpacing: CGFloat
    let expandedSpacing: CGFloat
    let expandedMetaFont: CGFloat
    let buttonFont: CGFloat
    let buttonVerticalPadding: CGFloat
    let expandedButtonHeight: CGFloat
    let readerHeaderIconFont: CGFloat
    let readerMetaFont: CGFloat
    let readerTitleFont: CGFloat
    let readerBodyFont: CGFloat
    let readerParagraphSpacing: CGFloat
    let readerBottomCardPadding: CGFloat
    let readerBottomCardCornerRadius: CGFloat
    let readerBottomEmojiSize: CGFloat
    let readerBottomTitleFont: CGFloat
    let readerBottomSubtitleFont: CGFloat
    let readerBottomButtonFont: CGFloat
    let readerBottomButtonHeight: CGFloat
    let addMenuCardWidth: CGFloat
    let addMenuCardPadding: CGFloat
    let addMenuCornerRadius: CGFloat
    let addMenuTitleFont: CGFloat
    let addMenuBodyFont: CGFloat
    let addMenuCloseFont: CGFloat
    let addMenuOptionIconSize: CGFloat
    let addMenuOptionIconFont: CGFloat
    let addMenuOptionCornerRadius: CGFloat
    let addMenuOptionTitleFont: CGFloat
    let addMenuOptionBodyFont: CGFloat
    let addMenuOptionSpacing: CGFloat

    init(screenSize: CGSize) {
        let widthScale = screenSize.width / 393
        let heightScale = screenSize.height / 852
        let resolvedScale = min(max(min(widthScale, heightScale), 0.88), 1.12)
        let compactScale: CGFloat = screenSize.height < 760 ? 0.94 : 1.0

        func scaled(_ value: CGFloat) -> CGFloat {
            value * resolvedScale * compactScale
        }

        horizontalPadding = scaled(16)
        topPadding = scaled(14)
        bottomPadding = scaled(26)
        sectionSpacing = scaled(14)
        compactSpacing = scaled(8)
        cardSpacing = scaled(12)

        titleFont = scaled(29)
        addButtonSize = scaled(34)
        addButtonIconFont = scaled(16)
        addButtonCornerRadius = scaled(12)
        segmentFont = scaled(13.5)
        segmentBadgeFont = scaled(9)
        filterLabelFont = scaled(13.5)
        filterIconFont = scaled(13)
        tagFont = scaled(12.5)
        cardTitleFont = scaled(15.5)
        cardMetaFont = scaled(12)
        progressLabelFont = scaled(11)
        progressValueFont = scaled(11)
        badgeFont = scaled(10)
        iconFont = scaled(12)
        buttonFont = scaled(12.5)

        segmentHeight = scaled(40)
        segmentOuterPadding = scaled(4)
        segmentSpacing = scaled(6)
        segmentCornerRadius = scaled(12)
        segmentInnerCornerRadius = scaled(10)
        segmentBadgeHorizontalPadding = scaled(5)
        segmentBadgeVerticalPadding = scaled(1.5)
        segmentBadgeOffsetX = scaled(6)
        segmentBadgeOffsetY = scaled(-4)

        filterSpacing = scaled(10)
        tagSpacing = scaled(8)
        tagRowSpacing = scaled(8)
        tagHorizontalPadding = scaled(12)
        tagVerticalPadding = scaled(7)

        cardPadding = scaled(14)
        expandedCardPadding = scaled(14)
        cardCornerRadius = scaled(14)
        cardBorderWidth = max(1, scaled(1))
        cardShadowRadius = scaled(6)
        progressHeight = scaled(5)
        iconButtonSize = scaled(24)
        progressSpacing = scaled(8)
        metaSpacing = scaled(6)
        expandedSpacing = scaled(12)
        expandedMetaFont = scaled(11.5)
        buttonVerticalPadding = scaled(8)
        expandedButtonHeight = scaled(34)
        readerHeaderIconFont = scaled(14)
        readerMetaFont = scaled(12)
        readerTitleFont = scaled(17)
        readerBodyFont = scaled(16)
        readerParagraphSpacing = scaled(18)
        readerBottomCardPadding = scaled(16)
        readerBottomCardCornerRadius = scaled(14)
        readerBottomEmojiSize = scaled(28)
        readerBottomTitleFont = scaled(18)
        readerBottomSubtitleFont = scaled(12)
        readerBottomButtonFont = scaled(12.5)
        readerBottomButtonHeight = scaled(32)
        addMenuCardWidth = min(screenSize.width - scaled(36), scaled(328))
        addMenuCardPadding = scaled(20)
        addMenuCornerRadius = scaled(24)
        addMenuTitleFont = scaled(15.5)
        addMenuBodyFont = scaled(12.5)
        addMenuCloseFont = scaled(16)
        addMenuOptionIconSize = scaled(42)
        addMenuOptionIconFont = scaled(18)
        addMenuOptionCornerRadius = scaled(16)
        addMenuOptionTitleFont = scaled(14.5)
        addMenuOptionBodyFont = scaled(12.5)
        addMenuOptionSpacing = scaled(12)
    }
}

private struct LibraryArticleCard: View {
    let article: LibraryArticle
    let metrics: LibraryMetrics
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStartReading: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? metrics.expandedSpacing : metrics.metaSpacing) {
            HStack(alignment: .top, spacing: metrics.compactSpacing) {
                Text(article.title)
                    .font(.system(size: metrics.cardTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(isExpanded ? Color.black : Color(red: 0.19, green: 0.21, blue: 0.26))
                    .lineLimit(isExpanded ? 3 : 2)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: metrics.compactSpacing)

                Image(systemName: "book.pages")
                    .font(.system(size: metrics.iconFont, weight: .bold))
                    .foregroundStyle(isExpanded ? Color.black : Color(red: 0.40, green: 0.30, blue: 1.00))
            }

            HStack(spacing: metrics.compactSpacing) {
                Text("\(article.wordCount) words")
                    .font(.system(size: metrics.cardMetaFont, weight: .medium, design: .rounded))
                    .foregroundStyle(isExpanded ? Color.black.opacity(0.78) : Color(red: 0.52, green: 0.55, blue: 0.63))

                Text("+\(article.newWords) new")
                    .font(.system(size: metrics.badgeFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.61, blue: 0.34))
                    .padding(.horizontal, metrics.tagHorizontalPadding * 0.62)
                    .padding(.vertical, metrics.tagVerticalPadding * 0.5)
                    .background(Color(red: 0.88, green: 1.00, blue: 0.91))
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: metrics.expandedSpacing) {
                    if let tag = article.tag {
                        Text(tag)
                            .font(.system(size: metrics.badgeFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, metrics.tagHorizontalPadding * 0.56)
                            .padding(.vertical, metrics.tagVerticalPadding * 0.38)
                            .background(Color.white.opacity(0.82))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: metrics.compactSpacing * 0.75) {
                        if let dateLabel = article.dateLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(dateLabel)
                            }
                        }

                        if let sourceLabel = article.sourceLabel {
                            Text("•")
                            Text(sourceLabel)
                        }
                    }
                    .font(.system(size: metrics.expandedMetaFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))

                    Button(action: onStartReading) {
                        Text("Start Reading")
                            .font(.system(size: metrics.buttonFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.expandedButtonHeight)
                            .background(Color(red: 0.31, green: 0.24, blue: 1.00))
                            .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 0.72, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else if let progress = article.progress {
                VStack(alignment: .leading, spacing: metrics.progressSpacing) {
                    HStack {
                        Text("Progress")
                            .font(.system(size: metrics.progressLabelFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.59))

                        Spacer()

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: metrics.progressValueFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.59))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(red: 0.91, green: 0.92, blue: 0.95))
                            Capsule()
                                .fill(Color(red: 0.31, green: 0.24, blue: 1.00))
                                .frame(width: max(proxy.size.width * progress, metrics.progressHeight))
                        }
                    }
                    .frame(height: metrics.progressHeight)
                }
            }
        }
        .padding(isExpanded ? metrics.expandedCardPadding : metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isExpanded ? Color(red: 0.86, green: 0.87, blue: 0.90) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(
                    isExpanded ? Color(red: 0.47, green: 0.55, blue: 1.00) : Color(red: 0.90, green: 0.91, blue: 0.94),
                    lineWidth: isExpanded ? max(1.4, metrics.cardBorderWidth + 0.4) : metrics.cardBorderWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .shadow(
            color: isExpanded ? Color(red: 0.40, green: 0.46, blue: 0.86).opacity(0.10) : Color.black.opacity(0.04),
            radius: isExpanded ? metrics.cardShadowRadius + 1 : metrics.cardShadowRadius,
            y: 2
        )
        .contentShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .onTapGesture {
            onToggle()
        }
    }
}

private struct ArticleReadingView: View {
    @Environment(\.dismiss) private var dismiss
    let article: LibraryArticle

    private let bodyParagraphs: [String] = [
        "Artificial intelligence has rapidly evolved from a theoretical concept into a transformative force reshaping industries worldwide. The advent of machine learning algorithms has enabled computers to process vast amounts of data with unprecedented efficiency.",
        "In recent years, we've witnessed remarkable breakthroughs in natural language processing, computer vision, and autonomous systems. These advancements have profound implications for how we work, communicate, and solve complex problems.",
        "The integration of AI into everyday applications has become ubiquitous. From voice assistants that manage our schedules to recommendation systems that curate our content consumption, AI has seamlessly woven itself into the fabric of modern life.",
        "However, this technological revolution also presents significant challenges. Questions about ethics, privacy, and the societal impact of automation demand careful consideration. As AI systems become more sophisticated, ensuring transparency and accountability becomes increasingly critical.",
        "Looking forward, the trajectory of AI development suggests even more dramatic transformations on the horizon. Emerging paradigms in deep learning and neural architecture design promise to unlock capabilities we've only begun to imagine.",
        "The key to harnessing AI's potential lies in fostering interdisciplinary collaboration between technologists, policymakers, and ethicists. Only through collective effort can we navigate the complexities of this new era and ensure that AI serves the broader interests of humanity."
    ]

    var body: some View {
        GeometryReader { proxy in
            let metrics = LibraryMetrics(screenSize: proxy.size)

            VStack(spacing: 0) {
                topBar(metrics: metrics)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        Rectangle()
                            .fill(Color(red: 0.31, green: 0.24, blue: 1.00))
                            .frame(height: 3)

                        Text("Tech Insights • 8 min read")
                            .font(.system(size: metrics.readerMetaFont, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))

                        Text(article.title)
                            .font(.system(size: metrics.readerTitleFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.23))

                        VStack(alignment: .leading, spacing: metrics.readerParagraphSpacing) {
                            ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.system(size: metrics.readerBodyFont, weight: .regular, design: .default))
                                    .foregroundStyle(Color(red: 0.19, green: 0.21, blue: 0.26))
                                    .lineSpacing(metrics.readerBodyFont * 0.28)
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
                .background(Color.white)
            }
            .background(Color.white.ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func topBar(metrics: LibraryMetrics) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: metrics.readerHeaderIconFont, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.38, blue: 0.46))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: metrics.compactSpacing * 1.4) {
                Image(systemName: "speaker.wave.2")
                Image(systemName: "slider.horizontal.3")
                Image(systemName: "bookmark")
            }
            .font(.system(size: metrics.readerHeaderIconFont, weight: .semibold))
            .foregroundStyle(Color(red: 0.35, green: 0.38, blue: 0.46))
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding * 0.8)
        .padding(.bottom, metrics.compactSpacing)
    }

    private func completionCard(metrics: LibraryMetrics) -> some View {
        VStack(spacing: metrics.compactSpacing) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.04, green: 0.78, blue: 0.31))
                    .frame(width: metrics.readerBottomEmojiSize + 8, height: metrics.readerBottomEmojiSize + 8)

                Image(systemName: "checkmark")
                    .font(.system(size: metrics.readerBottomEmojiSize * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Article Completed!")
                .font(.system(size: metrics.readerBottomTitleFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.21, blue: 0.26))

            Text("You've finished reading this article")
                .font(.system(size: metrics.readerBottomSubtitleFont, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))

            HStack(spacing: metrics.compactSpacing) {
                Button { } label: {
                    Text("Review Words")
                        .font(.system(size: metrics.readerBottomButtonFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.readerBottomButtonHeight)
                        .background(Color(red: 0.31, green: 0.24, blue: 1.00))
                        .clipShape(RoundedRectangle(cornerRadius: metrics.readerBottomButtonHeight / 3, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Back to Library")
                        .font(.system(size: metrics.readerBottomButtonFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.41, green: 0.44, blue: 0.52))
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.readerBottomButtonHeight)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.readerBottomButtonHeight / 3, style: .continuous)
                                .stroke(Color(red: 0.86, green: 0.88, blue: 0.92), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: metrics.readerBottomButtonHeight / 3, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, metrics.compactSpacing * 0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(metrics.readerBottomCardPadding)
        .background(Color(red: 0.94, green: 1.00, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: metrics.readerBottomCardCornerRadius, style: .continuous))
    }
}

private struct LibraryDiscoverCard: View {
    let article: LibraryArticle
    let metrics: LibraryMetrics
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.metaSpacing) {
            HStack(alignment: .top, spacing: metrics.compactSpacing) {
                Text(article.title)
                    .font(.system(size: metrics.cardTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.19, green: 0.21, blue: 0.26))
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: metrics.compactSpacing)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: metrics.iconFont, weight: .bold))
                        .foregroundStyle(Color(red: 0.66, green: 0.33, blue: 0.97))
                        .frame(width: metrics.iconButtonSize, height: metrics.iconButtonSize)
                        .background(Color(red: 0.96, green: 0.90, blue: 1.00))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: metrics.compactSpacing) {
                if let level = article.level {
                    DiscoverBadge(text: level, style: .level(level), metrics: metrics)
                }
                if let topic = article.topic {
                    DiscoverBadge(text: topic, style: .topic, metrics: metrics)
                }
            }

            HStack(spacing: metrics.compactSpacing) {
                Text("\(article.wordCount) words")
                    .font(.system(size: metrics.cardMetaFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.52, green: 0.55, blue: 0.63))

                Text("+\(article.newWords) new")
                    .font(.system(size: metrics.badgeFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.81, green: 0.48, blue: 0.05))
                    .padding(.horizontal, metrics.tagHorizontalPadding * 0.62)
                    .padding(.vertical, metrics.tagVerticalPadding * 0.5)
                    .background(Color(red: 1.00, green: 0.95, blue: 0.83))
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: metrics.cardBorderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: metrics.cardShadowRadius, y: 2)
    }
}

private struct DiscoverBadge: View {
    enum Style {
        case level(String)
        case topic
    }

    let text: String
    let style: Style
    let metrics: LibraryMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.badgeFont, weight: .bold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, metrics.tagHorizontalPadding * 0.56)
            .padding(.vertical, metrics.tagVerticalPadding * 0.44)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch style {
        case .level(let level):
            switch level {
            case "Beginner":
                return Color(red: 0.19, green: 0.58, blue: 0.28)
            case "Intermediate":
                return Color(red: 0.75, green: 0.49, blue: 0.04)
            default:
                return Color(red: 0.84, green: 0.24, blue: 0.31)
            }
        case .topic:
            return Color(red: 0.54, green: 0.56, blue: 0.64)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .level(let level):
            switch level {
            case "Beginner":
                return Color(red: 0.89, green: 0.98, blue: 0.90)
            case "Intermediate":
                return Color(red: 1.00, green: 0.95, blue: 0.85)
            default:
                return Color(red: 1.00, green: 0.89, blue: 0.90)
            }
        case .topic:
            return Color(red: 0.95, green: 0.95, blue: 0.97)
        }
    }
}

private struct LibraryAddMenuOverlay: View {
    let metrics: LibraryMetrics
    let onDismiss: () -> Void
    let onScanArticle: () -> Void
    let onImportURL: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: metrics.addMenuOptionSpacing) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add Article")
                            .font(.system(size: metrics.addMenuTitleFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                        Text("Choose how you'd like to add content to your library")
                            .font(.system(size: metrics.addMenuBodyFont, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.39, green: 0.42, blue: 0.50))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: metrics.addMenuCloseFont, weight: .medium))
                            .foregroundStyle(Color(red: 0.48, green: 0.50, blue: 0.57))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                LibraryAddOptionCard(
                    icon: "viewfinder",
                    title: "Scan Article",
                    subtitle: "Use OCR to extract text from images",
                    metrics: metrics,
                    action: onScanArticle
                )

                LibraryAddOptionCard(
                    icon: "link",
                    title: "Import from URL",
                    subtitle: "Paste a link to fetch article content",
                    metrics: metrics,
                    action: onImportURL
                )
            }
            .padding(metrics.addMenuCardPadding)
            .frame(width: metrics.addMenuCardWidth)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: metrics.addMenuCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
        }
    }
}

private struct LibraryAddOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let metrics: LibraryMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.addMenuOptionSpacing) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.93, blue: 1.00))
                        .frame(width: metrics.addMenuOptionIconSize, height: metrics.addMenuOptionIconSize)

                    Image(systemName: icon)
                        .font(.system(size: metrics.addMenuOptionIconFont, weight: .bold))
                        .foregroundStyle(Color(red: 0.32, green: 0.29, blue: 0.98))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: metrics.addMenuOptionTitleFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                    Text(subtitle)
                        .font(.system(size: metrics.addMenuOptionBodyFont, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.39, green: 0.42, blue: 0.50))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.addMenuCardPadding * 0.8)
            .padding(.vertical, metrics.addMenuCardPadding * 0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: metrics.addMenuOptionCornerRadius, style: .continuous)
                    .stroke(Color(red: 0.87, green: 0.89, blue: 0.93), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.addMenuOptionCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FlexibleTagLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let width = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            let height = subviews.reduce(CGFloat.zero) { partialResult, subview in
                partialResult + subview.sizeThatFits(.unspecified).height
            }
            return CGSize(width: width, height: height)
        }

        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if cursorX + size.width > maxWidth, cursorX > 0 {
                cursorX = 0
                cursorY += rowHeight + rowSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            cursorX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: cursorY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
}
