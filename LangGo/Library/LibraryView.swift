import SwiftUI
import AVFoundation
import UIKit
import Vision

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
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedMode: LibraryMode = .myLibrary
    @State private var selectedArticle: LibraryArticle?
    @State private var expandedArticleID: LibraryArticle.ID?
    @State private var isShowingAddMenu = false
    @State private var isShowingArticleScanFlow = false
    @State private var articleEditorDraft: ArticleDraft?
    @State private var tagPageIndex = 0
    @State private var cameraAccessMessage: String?

    var body: some View {
        GeometryReader { proxy in
            let metrics = LibraryMetrics(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    header(metrics: metrics)
                    modePicker(metrics: metrics)

                    if selectedMode == .myLibrary {
                        tagFilters(metrics: metrics, availableWidth: proxy.size.width - (metrics.horizontalPadding * 2))
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
                        openCameraForArticleScan()
                    } onManualInput: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingAddMenu = false
                        }
                        articleEditorDraft = ArticleDraft(
                            articleId: nil,
                            title: "",
                            content: "",
                            tags: [],
                            sourceLabel: "Manual"
                        )
                    }
                    .transition(.opacity)
                }
            }
            .overlay {
                if viewModel.isLoadingLibrary && viewModel.libraryArticles.isEmpty {
                    loadingOverlay(
                        title: "Loading Library...",
                        message: "Fetching your tags and saved articles."
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReadingView(article: article)
        }
        .fullScreenCover(isPresented: $isShowingArticleScanFlow) {
            ArticleScanFlowView(
                availableTags: viewModel.availableTags,
                onCancel: {
                    isShowingArticleScanFlow = false
                },
                onSave: { draft in
                    try await viewModel.saveDraftAsArticle(draft)
                    expandedArticleID = nil
                    selectedMode = .myLibrary
                    isShowingArticleScanFlow = false
                }
            )
        }
        .fullScreenCover(item: $articleEditorDraft) { draft in
            ArticleEditorView(
                draft: draft,
                availableTags: viewModel.availableTags,
                onCancel: {
                    articleEditorDraft = nil
                },
                onSave: { draft in
                    try await viewModel.saveDraftAsArticle(draft, sourceLabel: draft.sourceLabel ?? "Manual")
                    expandedArticleID = nil
                    selectedMode = .myLibrary
                    articleEditorDraft = nil
                }
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Camera Access Needed", isPresented: cameraAccessAlertBinding) {
            Button("OK", role: .cancel) {
                cameraAccessMessage = nil
            }
        } message: {
            Text(cameraAccessMessage ?? "")
        }
        .alert("Article Error", isPresented: articleErrorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.dismissArticleError()
            }
        } message: {
            Text(viewModel.articleErrorMessage ?? "")
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

    private func tagFilters(metrics: LibraryMetrics, availableWidth: CGFloat) -> some View {
        let pages = buildTagPages(tags: viewModel.filterTags, availableWidth: availableWidth, metrics: metrics)
        let resolvedPageIndex = min(tagPageIndex, max(pages.count - 1, 0))
        let currentRows = pages.isEmpty ? [] : pages[resolvedPageIndex]

        return VStack(alignment: .leading, spacing: metrics.filterSpacing) {
            HStack(spacing: metrics.compactSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: metrics.filterIconFont, weight: .semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.79))

                Text("Filter by tags")
                    .font(.system(size: metrics.filterLabelFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.60, blue: 0.67))
            }

            if currentRows.isEmpty {
                Text("No tags yet")
                    .font(.system(size: metrics.tagFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.60, blue: 0.67))
            } else {
                VStack(alignment: .leading, spacing: metrics.tagRowSpacing) {
                    ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: metrics.tagSpacing) {
                            ForEach(row, id: \.self) { tag in
                                tagChip(tag, metrics: metrics, isSelected: viewModel.selectedFilterTags.contains(tag))
                                    .onTapGesture {
                                        viewModel.toggleFilterTag(tag)
                                    }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                if pages.count > 1 {
                    HStack(spacing: metrics.compactSpacing) {
                        Spacer()

                        Button {
                            tagPageIndex = max(0, resolvedPageIndex - 1)
                        } label: {
                            Text("<")
                                .font(.system(size: metrics.tagFont, weight: .bold, design: .rounded))
                                .foregroundStyle(resolvedPageIndex > 0 ? Color(red: 0.32, green: 0.29, blue: 0.98) : Color(red: 0.77, green: 0.78, blue: 0.82))
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvedPageIndex == 0)

                        Text("\(resolvedPageIndex + 1)/\(pages.count)")
                            .font(.system(size: metrics.progressLabelFont, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.58, green: 0.60, blue: 0.67))

                        Button {
                            tagPageIndex = min(pages.count - 1, resolvedPageIndex + 1)
                        } label: {
                            Text(">")
                                .font(.system(size: metrics.tagFont, weight: .bold, design: .rounded))
                                .foregroundStyle(resolvedPageIndex < pages.count - 1 ? Color(red: 0.32, green: 0.29, blue: 0.98) : Color(red: 0.77, green: 0.78, blue: 0.82))
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvedPageIndex >= pages.count - 1)
                    }
                }
            }
        }
    }

    private func libraryList(metrics: LibraryMetrics) -> some View {
        LazyVStack(spacing: metrics.cardSpacing) {
            if viewModel.isLoadingPreviousArticlePage && !viewModel.displayedLibraryArticles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.compactSpacing)
            }

            if viewModel.isLoadingLibrary && viewModel.displayedLibraryArticles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.cardPadding * 2)
            } else if viewModel.displayedLibraryArticles.isEmpty {
                emptyLibraryCard(metrics: metrics)
            }

            ForEach(viewModel.displayedLibraryArticles) { article in
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
                    },
                    onEdit: {
                        beginEditing(article)
                    }
                )
                .onAppear {
                    guard selectedMode == .myLibrary else { return }
                    Task {
                        await viewModel.handleArticleAppearance(article)
                    }
                }
            }

            if viewModel.isLoadingNextArticlePage && !viewModel.displayedLibraryArticles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.compactSpacing)
            }
        }
    }

    private func discoverList(metrics: LibraryMetrics) -> some View {
        VStack(spacing: metrics.cardSpacing) {
            ForEach(viewModel.discoverArticles) { article in
                LibraryDiscoverCard(article: article, metrics: metrics) {
                    viewModel.addDiscoverArticle(article)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = .myLibrary
                    }
                }
            }
        }
    }

    private var discoverBadgeCount: Int {
        min(viewModel.discoverArticles.count, 3)
    }

    private var cameraAccessAlertBinding: Binding<Bool> {
        Binding(
            get: { cameraAccessMessage != nil },
            set: { newValue in
                if !newValue {
                    cameraAccessMessage = nil
                }
            }
        )
    }

    private var articleErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.articleErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissArticleError()
                }
            }
        )
    }

    private func openCameraForArticleScan() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAccessMessage = "Camera is not available on this device."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingArticleScanFlow = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingArticleScanFlow = true
                    } else {
                        cameraAccessMessage = "Please enable camera access in Settings to scan an article."
                    }
                }
            }
        case .denied, .restricted:
            cameraAccessMessage = "Please enable camera access in Settings to scan an article."
        @unknown default:
            cameraAccessMessage = "Camera access is unavailable right now."
        }
    }

    private func tagChip(_ tag: String, metrics: LibraryMetrics, isSelected: Bool) -> some View {
        Text(tag)
            .font(.system(size: metrics.tagFont, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.white : Color(red: 0.44, green: 0.47, blue: 0.55))
            .padding(.horizontal, metrics.tagHorizontalPadding)
            .padding(.vertical, metrics.tagVerticalPadding)
            .background(isSelected ? Color(red: 0.32, green: 0.29, blue: 0.98) : Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(Capsule())
    }

    private func buildTagPages(tags: [String], availableWidth: CGFloat, metrics: LibraryMetrics) -> [[[String]]] {
        guard !tags.isEmpty else { return [] }

        let font = UIFont.systemFont(ofSize: metrics.tagFont, weight: .semibold)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentRowWidth: CGFloat = 0

        for tag in tags {
            let textWidth = (tag as NSString).size(withAttributes: [.font: font]).width
            let chipWidth = textWidth + (metrics.tagHorizontalPadding * 2)
            let candidateWidth = currentRow.isEmpty ? chipWidth : currentRowWidth + metrics.tagSpacing + chipWidth

            if candidateWidth <= availableWidth || currentRow.isEmpty {
                currentRow.append(tag)
                currentRowWidth = candidateWidth
            } else {
                rows.append(currentRow)
                currentRow = [tag]
                currentRowWidth = chipWidth
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        var pages: [[[String]]] = []
        var rowIndex = 0
        while rowIndex < rows.count {
            pages.append(Array(rows[rowIndex..<min(rowIndex + 2, rows.count)]))
            rowIndex += 2
        }

        return pages
    }

    private func beginEditing(_ article: LibraryArticle) {
        articleEditorDraft = ArticleDraft(
            articleId: article.backendId,
            title: article.title,
            content: article.content ?? "",
            tags: article.tags,
            sourceLabel: article.sourceLabel ?? "Manual"
        )
    }

    private func emptyLibraryCard(metrics: LibraryMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.metaSpacing) {
            Text("No saved articles yet")
                .font(.system(size: metrics.cardTitleFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.19, green: 0.21, blue: 0.26))

            Text("Use Scan Article or Manual Input to create your first article.")
                .font(.system(size: metrics.cardMetaFont, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.59))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.cardPadding)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(Color(red: 0.90, green: 0.91, blue: 0.94), lineWidth: metrics.cardBorderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }

    private func loadingOverlay(title: String, message: String) -> some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.32, green: 0.29, blue: 0.98))

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 36)
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

struct LibraryArticle: Identifiable, Equatable {
    let id: UUID
    let backendId: Int?
    let title: String
    let content: String?
    let wordCount: Int
    let newWords: Int
    var progress: Double?
    let tag: String?
    let tags: [String]
    let dateLabel: String?
    let sourceLabel: String?
    let level: String?
    let topic: String?

    init(
        id: UUID = UUID(),
        backendId: Int? = nil,
        title: String,
        content: String? = nil,
        wordCount: Int,
        newWords: Int,
        progress: Double? = nil,
        tag: String? = nil,
        tags: [String] = [],
        dateLabel: String? = nil,
        sourceLabel: String? = nil,
        level: String? = nil,
        topic: String? = nil
    ) {
        self.id = id
        self.backendId = backendId
        self.title = title
        self.content = content
        self.wordCount = wordCount
        self.newWords = newWords
        self.progress = progress
        self.tag = tag
        self.tags = tags
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

struct ArticleDraft: Identifiable {
    let id = UUID()
    var articleId: Int?
    var title: String
    var content: String
    var tags: [String]
    var sourceLabel: String?
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
        topPadding = scaled(16)
        bottomPadding = scaled(26)
        sectionSpacing = scaled(16)
        compactSpacing = scaled(8)
        cardSpacing = scaled(12)

        titleFont = scaled(30)
        addButtonSize = scaled(34)
        addButtonIconFont = scaled(20)
        addButtonCornerRadius = scaled(16)
        segmentFont = scaled(18)
        segmentBadgeFont = scaled(16)
        filterLabelFont = scaled(18)
        filterIconFont = scaled(18)
        tagFont = scaled(16)
        cardTitleFont = scaled(22)
        cardMetaFont = scaled(20)
        progressLabelFont = scaled(20)
        progressValueFont = scaled(20)
        badgeFont = scaled(18)
        iconFont = scaled(22)
        buttonFont = scaled(20)

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
        expandedSpacing = scaled(16)
        expandedMetaFont = scaled(14)
        buttonVerticalPadding = scaled(1)
        expandedButtonHeight = scaled(40)
        readerHeaderIconFont = scaled(16)
        readerMetaFont = scaled(16)
        readerTitleFont = scaled(18)
        readerBodyFont = scaled(18)
        readerParagraphSpacing = scaled(20)
        readerBottomCardPadding = scaled(18)
        readerBottomCardCornerRadius = scaled(16)
        readerBottomEmojiSize = scaled(28)
        readerBottomTitleFont = scaled(22)
        readerBottomSubtitleFont = scaled(20)
        readerBottomButtonFont = scaled(20)
        readerBottomButtonHeight = scaled(32)
        addMenuCardWidth = min(screenSize.width - scaled(36), scaled(328))
        addMenuCardPadding = scaled(22)
        addMenuCornerRadius = scaled(26)
        addMenuTitleFont = scaled(24)
        addMenuBodyFont = scaled(20)
        addMenuCloseFont = scaled(24)
        addMenuOptionIconSize = scaled(42)
        addMenuOptionIconFont = scaled(26)
        addMenuOptionCornerRadius = scaled(24)
        addMenuOptionTitleFont = scaled(22)
        addMenuOptionBodyFont = scaled(20)
        addMenuOptionSpacing = scaled(20)
    }
}

private struct LibraryArticleCard: View {
    let article: LibraryArticle
    let metrics: LibraryMetrics
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStartReading: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? metrics.expandedSpacing : metrics.metaSpacing) {
            HStack(alignment: .top, spacing: metrics.compactSpacing) {
                Text(article.title)
                    .font(.system(size: metrics.cardTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(isExpanded ? Color.black : Color(red: 0.19, green: 0.21, blue: 0.26))
                    .lineLimit(isExpanded ? 3 : 2)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: metrics.compactSpacing)

                Image(systemName: "book")
                    .font(.system(size: metrics.iconFont, weight: .bold))
                    .foregroundStyle(isExpanded ? Color.black : Color(red: 0.40, green: 0.30, blue: 1.00))
            }

            HStack(spacing: metrics.compactSpacing) {
                Text("\(article.wordCount) words")
                    .font(.system(size: metrics.cardMetaFont, weight: .medium, design: .rounded))
                    .foregroundStyle(isExpanded ? Color.black.opacity(0.78) : Color(red: 0.52, green: 0.55, blue: 0.63))
                /*
                Text("+\(article.newWords) new")
                    .font(.system(size: metrics.badgeFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.61, blue: 0.34))
                    .padding(.horizontal, metrics.tagHorizontalPadding * 0.62)
                    .padding(.vertical, metrics.tagVerticalPadding * 0.5)
                    .background(Color(red: 0.88, green: 1.00, blue: 0.91))
                    .clipShape(Capsule())
                 */
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

                    Button(action: onEdit) {
                        Text("Edit Article")
                            .font(.system(size: metrics.buttonFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.23, green: 0.25, blue: 0.31))
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.expandedButtonHeight)
                            .background(Color.white.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 0.72, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
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
    let onManualInput: () -> Void

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
                    icon: "square.and.pencil",
                    title: "Manual Input",
                    subtitle: "Type or paste article content yourself",
                    metrics: metrics,
                    action: onManualInput
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

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onCancel()
            }
        }
    }
}

struct UserArticleScanFlowView: View {
    @StateObject private var viewModel: UserArticleScanFlowViewModel

    let onCancel: () -> Void
    let onSaved: () -> Void

    @MainActor
    init(
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: UserArticleScanFlowViewModel())
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    init(
        viewModel: UserArticleScanFlowViewModel,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    var body: some View {
        ArticleScanFlowView(
            availableTags: viewModel.availableTags,
            onCancel: onCancel,
            onSave: { draft in
                try await viewModel.saveDraftAsArticle(draft, sourceLabel: draft.sourceLabel ?? "OCR")
                await MainActor.run {
                    onSaved()
                }
            }
        )
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Article Error", isPresented: articleErrorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.dismissArticleError()
            }
        } message: {
            Text(viewModel.articleErrorMessage ?? "")
        }
    }

    private var articleErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.articleErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissArticleError()
                }
            }
        )
    }
}

private struct ArticleScanFlowView: View {
    @State private var stage: ArticleScanStage = .review
    @State private var isShowingCamera = true
    @State private var scannedImage: UIImage?
    @State private var articleDraft: ArticleDraft?
    @State private var isProcessing = false

    let availableTags: [String]
    let onCancel: () -> Void
    let onSave: (ArticleDraft) async throws -> Void

    var body: some View {
        Group {
            switch stage {
            case .review:
                if let scannedImage {
                    ScanPhotoReviewView(
                        image: scannedImage,
                        isProcessing: isProcessing,
                        onRetake: {
                            self.scannedImage = nil
                            isShowingCamera = true
                        },
                        onConfirm: {
                            beginOCRProcessing(for: scannedImage)
                        }
                    )
                } else {
                    Color.black.ignoresSafeArea()
                }
            case .processing:
                OCRProcessingView()
            case .editor:
                if let articleDraft {
                    ArticleEditorView(
                        draft: articleDraft,
                        availableTags: availableTags,
                        onCancel: onCancel,
                        onSave: onSave
                    )
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if scannedImage == nil {
                isShowingCamera = true
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                scannedImage = image
                stage = .review
                isShowingCamera = false
            } onCancel: {
                if scannedImage == nil {
                    onCancel()
                } else {
                    isShowingCamera = false
                }
            }
        }
    }

    private func beginOCRProcessing(for image: UIImage) {
        guard !isProcessing else { return }
        isProcessing = true
        stage = .processing

        Task {
            let extractedText = await OCRService.recognizeText(from: image)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"

            let draft = ArticleDraft(
                articleId: nil,
                title: "Article \(formatter.string(from: Date()))",
                content: extractedText,
                tags: [],
                sourceLabel: "OCR"
            )

            await MainActor.run {
                articleDraft = draft
                isProcessing = false
                stage = .editor
            }
        }
    }
}

private enum ArticleScanStage {
    case review
    case processing
    case editor
}

private struct ScanPhotoReviewView: View {
    let image: UIImage
    let isProcessing: Bool
    let onRetake: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)

            VStack(spacing: 12) {
                Text("Use this photo for OCR?")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                HStack(spacing: 12) {
                    Button(action: onRetake) {
                        Text("Retake")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button(action: onConfirm) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isProcessing ? "Processing..." : "Use Photo")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.19, green: 0.48, blue: 0.98))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

private struct ArticleEditorView: View {
    @State private var draft: ArticleDraft
    @State private var isShowingTagSheet = false
    @State private var customTagInput = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @FocusState private var isCustomTagFocused: Bool

    let availableTags: [String]
    let onCancel: () -> Void
    let onSave: (ArticleDraft) async throws -> Void

    init(
        draft: ArticleDraft,
        availableTags: [String],
        onCancel: @escaping () -> Void,
        onSave: @escaping (ArticleDraft) async throws -> Void
    ) {
        _draft = State(initialValue: draft)
        self.availableTags = availableTags
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
            }

            if isShowingTagSheet {
                tagSheetOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isSaving {
                saveProgressOverlay
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isShowingTagSheet)
        .alert("Unable to Save", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.98))

            Spacer()

            Text(draft.articleId == nil ? "New Article" : "Edit Article")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

            Spacer()

            Button("Save") {
                performSave()
            }
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(canSave ? Color(red: 0.10, green: 0.45, blue: 0.98) : Color(red: 0.78, green: 0.79, blue: 0.83))
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TAGS")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.51, green: 0.53, blue: 0.59))

                    Spacer()

                    Button {
                        isShowingTagSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Tags")
                        }
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.98))
                    }
                    .buttonStyle(.plain)
                }

                if draft.tags.isEmpty {
                    Text("No tags added yet")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.78))
                } else {
                    FlexibleTagLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(draft.tags, id: \.self) { tag in
                            editorSelectedTag(tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color(red: 0.90, green: 0.91, blue: 0.94))
                .frame(height: 1)

            ZStack(alignment: .leading) {
                if draft.title.isEmpty {
                    Text("Article Title")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.75, green: 0.76, blue: 0.80))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }

                TextField("", text: $draft.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }

            Rectangle()
                .fill(Color(red: 0.90, green: 0.91, blue: 0.94))
                .frame(height: 1)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.content)
                    .font(.system(size: 21, weight: .regular, design: .default))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                if draft.content.isEmpty {
                    Text("Start writing or paste your article content here...")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(red: 0.74, green: 0.75, blue: 0.79))
                        .padding(.horizontal, 21)
                        .padding(.top, 20)
                }
            }
        }
    }

    private func editorSelectedTag(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Text(tag)
            Button {
                draft.tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(red: 0.10, green: 0.45, blue: 0.98)))
    }

    private var tagSheetOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowingTagSheet = false
                    isCustomTagFocused = false
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Select Tags")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                    Spacer()

                    Button {
                        isShowingTagSheet = false
                        isCustomTagFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color(red: 0.52, green: 0.54, blue: 0.60))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(Color(red: 0.92, green: 0.93, blue: 0.96))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    Text("CUSTOM TAG")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.51, green: 0.53, blue: 0.59))

                    HStack(spacing: 10) {
                        TextField("Enter tag name", text: $customTagInput)
                            .font(.system(size: 21, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isCustomTagFocused ? Color(red: 0.10, green: 0.45, blue: 0.98) : Color.clear, lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .focused($isCustomTagFocused)

                        Button("Add") {
                            addCustomTag()
                        }
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 58, height: 44)
                        .background(Color(red: 0.10, green: 0.45, blue: 0.98))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(customTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(customTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    }

                    Text("QUICK SELECT")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.51, green: 0.53, blue: 0.59))
                        .padding(.top, 2)

                    FlexibleTagLayout(spacing: 10, rowSpacing: 10) {
                        ForEach(resolvedAvailableTags, id: \.self) { tag in
                            Button {
                                toggleTag(tag)
                            } label: {
                                Text(tag)
                                    .font(.system(size: 19, weight: .medium, design: .rounded))
                                    .foregroundStyle(draft.tags.contains(tag) ? Color.white : Color(red: 0.15, green: 0.17, blue: 0.22))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(draft.tags.contains(tag) ? Color(red: 0.10, green: 0.45, blue: 0.98) : Color(red: 0.95, green: 0.95, blue: 0.97))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !draft.tags.isEmpty {
                        Rectangle()
                            .fill(Color(red: 0.92, green: 0.93, blue: 0.96))
                            .frame(height: 1)
                            .padding(.top, 4)

                        Text("SELECTED (\(draft.tags.count))")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.51, green: 0.53, blue: 0.59))

                        FlexibleTagLayout(spacing: 10, rowSpacing: 10) {
                            ForEach(draft.tags, id: \.self) { tag in
                                editorSelectedTag(tag)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

                Rectangle()
                    .fill(Color(red: 0.92, green: 0.93, blue: 0.96))
                    .frame(height: 1)

                Button {
                    isShowingTagSheet = false
                    isCustomTagFocused = false
                } label: {
                    Text("Done")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.10, green: 0.45, blue: 0.98))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedAvailableTags: [String] {
        let tags = availableTags.isEmpty ? LibraryTag.mockTags : availableTags
        return Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private var saveProgressOverlay: some View {
        ZStack {
            Color.white.opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.10, green: 0.45, blue: 0.98))

                Text("Saving Article...")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                Text("Updating your article and tags.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
            .padding(.horizontal, 32)
        }
    }

    private func performSave() {
        guard !isSaving else { return }

        Task {
            isSaving = true
            do {
                try await onSave(draft)
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func addCustomTag() {
        let trimmed = customTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !draft.tags.contains(trimmed) {
            draft.tags.append(trimmed)
        }
        customTagInput = ""
        isCustomTagFocused = false
    }

    private func toggleTag(_ tag: String) {
        if draft.tags.contains(tag) {
            draft.tags.removeAll { $0 == tag }
        } else {
            draft.tags.append(tag)
        }
    }
}

private struct OCRProcessingView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.10, green: 0.45, blue: 0.98))

                Text("Processing OCR...")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                Text("Extracting article text from your photo.")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}

private enum OCRService {
    static func recognizeText(from image: UIImage) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, _ in
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n\n") ?? ""
                    continuation.resume(returning: text)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                do {
                    let handler = try makeImageHandler(from: image)
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private static func makeImageHandler(from image: UIImage) throws -> VNImageRequestHandler {
        if let cgImage = image.cgImage {
            return VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
        }

        if let ciImage = image.ciImage {
            return VNImageRequestHandler(
                ciImage: ciImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
        }

        throw OCRFailure.invalidImage
    }
}

private enum OCRFailure: Error {
    case invalidImage
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
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
