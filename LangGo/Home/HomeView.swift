import SwiftUI
import AVFoundation

struct HomeView: View {
    @Binding var selectedTab: Int
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var flashcardViewModel = FlashcardViewModel()
    @StateObject private var vocabookViewModel = VocabookViewModel()
    @StateObject private var viewModel: HomeViewModel

    @State private var isShowingLeaderboard = false
    @State private var isShowingReview = false
    @State private var isShowingQuizReview = false
    @State private var isShowingBookMode = false
    @State private var isShowingAddWord = false
    @State private var isShowingArticleScanFlow = false
    @State private var isPreparingBookMode = false
    @State private var placeholderMessage: String?
    @State private var cameraAccessMessage: String?

    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly = false

    @MainActor
    init(
        selectedTab: Binding<Int>,
        viewModel: HomeViewModel? = nil
    ) {
        self._selectedTab = selectedTab
        self._viewModel = StateObject(wrappedValue: viewModel ?? HomeViewModel())
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = HomeMetrics(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(greetingText)
                        .font(.system(size: metrics.greetingFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.15, blue: 0.23))

                    Spacer()
                        .frame(height: metrics.afterGreetingSpacing)

                    summaryCardsView(metrics: metrics)

                    Spacer()
                        .frame(height: metrics.afterSummarySpacing)

                    Spacer()
                        .frame(height: metrics.beforeReviewSectionSpacing)

                    sectionLabel("READY TO REVIEW", metrics: metrics)

                    Spacer()
                        .frame(height: metrics.afterSectionLabelSpacing)

                    reviewCard(metrics: metrics)

                    Spacer()
                        .frame(height: metrics.afterReviewCardSpacing)

                    actionRow(
                        metrics: metrics,
                        items: [
                            .init(title: "Quiz Review", icon: "list.bullet", iconColor: .white, iconBackground: Color(red: 0.32, green: 0.81, blue: 0.05), background: Color(red: 0.73, green: 0.94, blue: 0.69), border: Color(red: 0.68, green: 0.89, blue: 0.64), textColor: Color(red: 0.22, green: 0.39, blue: 0.16), action: { isShowingQuizReview = true }),
                            .init(title: "Book Mode", icon: "book.closed", iconColor: .white, iconBackground: Color(red: 0.32, green: 0.81, blue: 0.05), background: Color(red: 0.73, green: 0.94, blue: 0.69), border: Color(red: 0.68, green: 0.89, blue: 0.64), textColor: Color(red: 0.22, green: 0.39, blue: 0.16), action: { openBookMode() })
                        ]
                    )

                    Spacer()
                        .frame(height: metrics.beforeAddContentSpacing)

                    sectionLabel("ADD CONTENT", metrics: metrics)

                    Spacer()
                        .frame(height: metrics.afterSectionLabelSpacing)

                    actionRow(
                        metrics: metrics,
                        items: [
                            .init(title: "Scan Article", icon: "camera", iconColor: .white, iconBackground: Color(red: 0.17, green: 0.63, blue: 0.97), background: Color(red: 0.72, green: 0.89, blue: 1.00), border: Color(red: 0.67, green: 0.85, blue: 0.99), textColor: Color(red: 0.23, green: 0.33, blue: 0.45), action: {
                                openArticleScan()
                            }),
                            .init(title: "Import Text", icon: "doc.text", iconColor: .white, iconBackground: Color(red: 0.17, green: 0.63, blue: 0.97), background: Color(red: 0.72, green: 0.89, blue: 1.00), border: Color(red: 0.67, green: 0.85, blue: 0.99), textColor: Color(red: 0.23, green: 0.33, blue: 0.45), action: {
                                placeholderMessage = "Text article import will be backed by the new article input flow."
                            }),
                            .init(title: "Add Word", icon: "plus", iconColor: .white, iconBackground: Color(red: 0.99, green: 0.57, blue: 0.05), background: Color(red: 0.72, green: 0.89, blue: 1.00), border: Color(red: 0.67, green: 0.85, blue: 0.99), textColor: Color(red: 0.23, green: 0.33, blue: 0.45), action: { isShowingAddWord = true })
                        ]
                    )

                    Spacer()
                        .frame(height: metrics.beforeLibrarySpacing)

                    articleLibrary(metrics: metrics)
                }
                .padding(.horizontal, metrics.screenHorizontalPadding)
                .padding(.top, metrics.screenTopPadding)
                .padding(.bottom, metrics.screenBottomPadding)
            }
            .background(Color.white)
            .refreshable {
                await viewModel.handlePullToRefresh()
            }
        }
        .background(Color.white.ignoresSafeArea())
        .fullScreenCover(isPresented: $isShowingReview) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isShowingQuizReview) {
            ExamView()
        }
        .fullScreenCover(isPresented: $isShowingBookMode) {
            NavigationStack {
                if let bookModeConfig {
                    VocapageHostView(
                        allVocapageIds: bookModeConfig.allPageIds,
                        selectedVocapageId: bookModeConfig.selectedPageId,
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
        .fullScreenCover(isPresented: $isShowingAddWord) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isShowingArticleScanFlow) {
            UserArticleScanFlowView(
                onCancel: {
                    isShowingArticleScanFlow = false
                },
                onSaved: {
                    isShowingArticleScanFlow = false
                    selectedTab = 2
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingLeaderboard) {
            LeaderboardSheet(state: viewModel.leaderboardSheetState)
        }
        .alert("Camera Access Needed", isPresented: cameraAccessAlertBinding) {
            Button("OK", role: .cancel) {
                cameraAccessMessage = nil
            }
        } message: {
            Text(cameraAccessMessage ?? "")
        }
        .alert("Coming Soon", isPresented: placeholderAlertBinding) {
            Button("OK", role: .cancel) {
                placeholderMessage = nil
            }
        } message: {
            Text(placeholderMessage ?? "")
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flashcardsDidChange)) { _ in
            Task {
                await viewModel.handleFlashcardsDidChange()
            }
        }
        .task(id: viewModel.nextFlashcardStatisticsFetchAt) {
            guard let nextFetchAt = viewModel.nextFlashcardStatisticsFetchAt else { return }

            let delay = nextFetchAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            guard scenePhase == .active else { return }

            await viewModel.handleScheduledFlashcardStatisticsRefresh()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.handleSceneDidBecomeActive()
            }
        }
        .onChange(of: selectedTab) { newTab in
            guard newTab == 0 else { return }
            Task {
                await viewModel.handleHomeTabSelected()
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private func sectionLabel(_ text: String, metrics: HomeMetrics) -> some View {
        Text(text)
            .font(.system(size: metrics.sectionLabelFont, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.43, green: 0.47, blue: 0.55))
            .tracking(0.2)
    }

    private func summaryCardsView(metrics: HomeMetrics) -> some View {
        HStack(spacing: metrics.summaryCardGap) {
            HomeRankPointsCard(
                metrics: metrics,
                state: viewModel.rankPointsState
            )
                .frame(maxWidth: .infinity)

            HomeLeaderboardCard(
                metrics: metrics,
                state: viewModel.leaderboardBannerState,
                action: openLeaderboard
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func reviewCard(metrics: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.reviewContentGap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: metrics.reviewTitleGap) {
                    Text("Total Words")
                        .font(.system(size: metrics.reviewLabelFont, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text(formatNumber(viewModel.reviewCardState.totalCards))
                        .font(.system(size: metrics.reviewCountFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.26))
                        .frame(width: metrics.reviewIconCircle, height: metrics.reviewIconCircle)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: metrics.reviewIconFont, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }

            VStack(spacing: metrics.reviewRowsGap) {
                ReviewStatusRow(label: "Due", value: formatNumber(viewModel.reviewCardState.dueForReview), icon: nil, metrics: metrics)
                ReviewStatusRow(label: "Remembered", value: formatNumber(viewModel.reviewCardState.remembered), icon: nil, metrics: metrics)
            }
            .padding(.horizontal, metrics.reviewPanelHorizontalPadding)
            .padding(.vertical, metrics.reviewPanelVerticalPadding)
            .background(Color(red: 0.89, green: 0.89, blue: 0.91))
            .clipShape(RoundedRectangle(cornerRadius: metrics.reviewPanelCornerRadius, style: .continuous))

            Spacer()
                .frame(height: metrics.reviewButtonTopSpacing)

            Button {
                isShowingReview = true
            } label: {
                Text("Start Card Review")
                    .font(.system(size: metrics.reviewButtonFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.reviewButtonHeight)
                    .background(Color(red: 1.00, green: 0.66, blue: 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.reviewButtonCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
                .frame(height: metrics.reviewButtonTopSpacing)
        }
        .padding(.horizontal, metrics.reviewCardHorizontalPadding)
        .padding(.vertical, metrics.reviewCardVerticalPadding)
        .background(Color(red: 0.30, green: 0.80, blue: 0.00))
        .clipShape(RoundedRectangle(cornerRadius: metrics.reviewCardCornerRadius, style: .continuous))
        .shadow(color: Color(red: 0.34, green: 0.74, blue: 0.05).opacity(0.18), radius: metrics.reviewShadowRadius, y: metrics.reviewShadowY)
    }

    private func actionRow(metrics: HomeMetrics, items: [HomeActionItem]) -> some View {
        HStack(spacing: metrics.actionCardGap) {
            ForEach(items) { item in
                ActionButton(item: item, metrics: metrics)
            }
        }
    }

    private func articleLibrary(metrics: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("ARTICLE LIBRARY", metrics: metrics)

                Spacer()

                Button {
                    selectedTab = 2
                } label: {
                    Text("View All (12)")
                        .font(.system(size: metrics.libraryLinkFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.27, blue: 0.98))
                }
                .buttonStyle(.plain)
            }

            Spacer()
                .frame(height: metrics.afterSectionLabelSpacing)

            Button {
                selectedTab = 2
            } label: {
                VStack(alignment: .leading, spacing: metrics.libraryCardContentGap) {
                    HStack(spacing: metrics.libraryTopRowGap) {
                        ZStack {
                            RoundedRectangle(cornerRadius: metrics.libraryIconCornerRadius, style: .continuous)
                                .fill(Color(red: 0.72, green: 0.33, blue: 0.98))
                                .frame(width: metrics.libraryIconBox, height: metrics.libraryIconBox)

                            Image(systemName: "book.pages")
                                .font(.system(size: metrics.libraryIconFont, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }

                        VStack(alignment: .leading, spacing: metrics.libraryTitleGap) {
                            Text("The Future of AI Technology")
                                .font(.system(size: metrics.libraryTitleFont, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.21, green: 0.23, blue: 0.31))
                                .lineLimit(2)

                            HStack(spacing: metrics.libraryTagGap) {
                                ArticleTag(text: "Technology", metrics: metrics)
                                ArticleTag(text: "AI", metrics: metrics)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: metrics.libraryChevronFont, weight: .bold))
                            .foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.74))
                    }

                    HStack {
                        Text("Progress")
                            .font(.system(size: metrics.libraryMetaFont, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.49, green: 0.49, blue: 0.60))
                        Spacer()
                        Text("60%")
                            .font(.system(size: metrics.libraryMetaFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.49, green: 0.49, blue: 0.60))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(red: 0.89, green: 0.84, blue: 0.98))
                            Capsule()
                                .fill(Color(red: 0.70, green: 0.17, blue: 0.98))
                                .frame(width: proxy.size.width * 0.60)
                        }
                    }
                    .frame(height: metrics.libraryProgressHeight)
                }
                .padding(.horizontal, metrics.libraryCardHorizontalPadding)
                .padding(.vertical, metrics.libraryCardVerticalPadding)
                .background(Color(red: 0.97, green: 0.92, blue: 1.00))
                .clipShape(RoundedRectangle(cornerRadius: metrics.libraryCardCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func openLeaderboard() {
        isShowingLeaderboard = true

        Task {
            await viewModel.loadLeaderboard()
        }
    }

    private var placeholderAlertBinding: Binding<Bool> {
        Binding(
            get: { placeholderMessage != nil },
            set: { newValue in
                if !newValue {
                    placeholderMessage = nil
                }
            }
        )
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

    private var bookModeConfig: BookModeConfig? {
        let allPageIds = (vocabookViewModel.vocabook?.vocapages ?? []).map(\.id).sorted()
        guard !allPageIds.isEmpty else { return nil }

        let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
        let selectedPageId = (lastViewedID != 0 && allPageIds.contains(lastViewedID)) ? lastViewedID : (allPageIds.first ?? 1)

        return BookModeConfig(allPageIds: allPageIds, selectedPageId: selectedPageId)
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
                placeholderMessage = "No words are available in book mode yet."
            }
        }
    }

    private func openArticleScan() {
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

}

private struct HomeMetrics {
    private let widthScale: CGFloat
    private let heightScale: CGFloat
    let compactScale: CGFloat

    let screenHorizontalPadding: CGFloat
    let screenTopPadding: CGFloat
    let screenBottomPadding: CGFloat

    let greetingFont: CGFloat
    let sectionLabelFont: CGFloat

    let afterGreetingSpacing: CGFloat
    let afterSummarySpacing: CGFloat
    let beforeReviewSectionSpacing: CGFloat
    let afterSectionLabelSpacing: CGFloat
    let afterReviewCardSpacing: CGFloat
    let beforeAddContentSpacing: CGFloat
    let beforeLibrarySpacing: CGFloat

    let summaryCardGap: CGFloat
    let summaryCardCornerRadius: CGFloat
    let summaryCardHorizontalPadding: CGFloat
    let summaryCardVerticalPadding: CGFloat
    let summaryTitleFont: CGFloat
    let summaryIconFont: CGFloat
    let summaryValueFont: CGFloat
    let summaryDeltaFont: CGFloat
    let summarySubtitleFont: CGFloat
    let summaryTopGap: CGFloat
    let summaryValueGap: CGFloat
    let articleSummaryWidth: CGFloat

    let bannerHeight: CGFloat
    let bannerCornerRadius: CGFloat
    let bannerHorizontalPadding: CGFloat
    let bannerInnerGap: CGFloat
    let bannerIconCircle: CGFloat
    let bannerLeadingIconFont: CGFloat
    let bannerTextFont: CGFloat
    let bannerLinkFont: CGFloat
    let bannerPositionFont: CGFloat
    let bannerTitleGap: CGFloat
    let bannerChipFont: CGFloat
    let bannerChipHorizontalPadding: CGFloat
    let bannerChipVerticalPadding: CGFloat
    let bannerChevronFont: CGFloat
    let bannerMiddleSpacer: CGFloat
    let bannerTextGap: CGFloat
    let bannerStatusGap: CGFloat
    let bannerShadowRadius: CGFloat
    let bannerShadowY: CGFloat

    let reviewCardCornerRadius: CGFloat
    let reviewCardHorizontalPadding: CGFloat
    let reviewCardVerticalPadding: CGFloat
    let reviewContentGap: CGFloat
    let reviewTitleGap: CGFloat
    let reviewLabelFont: CGFloat
    let reviewCountFont: CGFloat
    let reviewIconCircle: CGFloat
    let reviewIconFont: CGFloat
    let reviewPanelHorizontalPadding: CGFloat
    let reviewPanelVerticalPadding: CGFloat
    let reviewPanelCornerRadius: CGFloat
    let reviewRowsGap: CGFloat
    let reviewRowFont: CGFloat
    let reviewRowIconFont: CGFloat
    let reviewButtonTopSpacing: CGFloat
    let reviewButtonHeight: CGFloat
    let reviewButtonCornerRadius: CGFloat
    let reviewButtonFont: CGFloat
    let reviewShadowRadius: CGFloat
    let reviewShadowY: CGFloat

    let actionCardGap: CGFloat
    let actionCardHeight: CGFloat
    let actionCardCornerRadius: CGFloat
    let actionCardHorizontalPadding: CGFloat
    let actionCardVerticalPadding: CGFloat
    let actionIconCircle: CGFloat
    let actionIconFont: CGFloat
    let actionTitleFont: CGFloat
    let actionContentGap: CGFloat

    let libraryLinkFont: CGFloat
    let libraryCardCornerRadius: CGFloat
    let libraryCardHorizontalPadding: CGFloat
    let libraryCardVerticalPadding: CGFloat
    let libraryCardContentGap: CGFloat
    let libraryTopRowGap: CGFloat
    let libraryIconBox: CGFloat
    let libraryIconCornerRadius: CGFloat
    let libraryIconFont: CGFloat
    let libraryTitleGap: CGFloat
    let libraryTitleFont: CGFloat
    let libraryTagGap: CGFloat
    let libraryTagFont: CGFloat
    let libraryTagHorizontalPadding: CGFloat
    let libraryTagVerticalPadding: CGFloat
    let libraryMetaFont: CGFloat
    let libraryChevronFont: CGFloat
    let libraryProgressHeight: CGFloat

    init(screenSize: CGSize) {
        let resolvedWidthScale = screenSize.width / 393
        let resolvedHeightScale = screenSize.height / 852
        let resolvedCompactScale: CGFloat = screenSize.height < 760 ? 0.93 : 1.0

        func sx(_ value: CGFloat) -> CGFloat {
            value * min(max(resolvedWidthScale, 0.88), 1.08)
        }

        func sy(_ value: CGFloat) -> CGFloat {
            value * min(max(resolvedHeightScale, 0.90), 1.08) * resolvedCompactScale
        }

        widthScale = resolvedWidthScale
        heightScale = resolvedHeightScale
        compactScale = resolvedCompactScale

        screenHorizontalPadding = sx(18)
        screenTopPadding = sy(18)
        screenBottomPadding = sy(22)

        greetingFont = min(sx(28), sy(28))
        sectionLabelFont = min(sx(13), sy(13))

        afterGreetingSpacing = sy(18)
        afterSummarySpacing = sy(18)
        beforeReviewSectionSpacing = sy(24)
        afterSectionLabelSpacing = sy(15)
        afterReviewCardSpacing = sy(18)
        beforeAddContentSpacing = sy(22)
        beforeLibrarySpacing = sy(20)

        summaryCardGap = sx(8)
        summaryCardCornerRadius = sx(12)
        summaryCardHorizontalPadding = sx(10)
        summaryCardVerticalPadding = sy(11)
        summaryTitleFont = min(sx(20), sy(20))
        summaryIconFont = min(sx(20), sy(20))
        summaryValueFont = min(sx(28), sy(29))
        summaryDeltaFont = summaryTitleFont
        summarySubtitleFont = summaryTitleFont
        summaryTopGap = sy(7)
        summaryValueGap = sx(2)
        articleSummaryWidth = sx(118)

        bannerHeight = sy(50)
        bannerCornerRadius = sx(17)
        bannerHorizontalPadding = sx(16)
        bannerInnerGap = sx(9)
        bannerIconCircle = sx(0)
        bannerLeadingIconFont = min(sx(15), sy(15)) + 2
        bannerTextFont = min(sx(14), sy(14)) + 2
        bannerLinkFont = min(sx(13), sy(13)) + 1
        bannerPositionFont = min(sx(15), sy(15)) + 1
        bannerTitleGap = sx(8)
        bannerChipFont = min(sx(11), sy(11)) + 1
        bannerChipHorizontalPadding = sx(10)
        bannerChipVerticalPadding = sy(4)
        bannerChevronFont = min(sx(11), sy(11)) + 1
        bannerMiddleSpacer = sx(10)
        bannerTextGap = sy(0)
        bannerStatusGap = sy(0)
        bannerShadowRadius = sx(5)
        bannerShadowY = sy(2)

        reviewCardCornerRadius = sx(13)
        reviewCardHorizontalPadding = sx(16)
        reviewCardVerticalPadding = sy(16)
        reviewContentGap = sy(16)
        reviewTitleGap = sy(2)
        reviewLabelFont = min(sx(14), sy(14))
        reviewCountFont = min(sx(28), sy(30))
        reviewIconCircle = sx(38)
        reviewIconFont = min(sx(18), sy(18)) + 2
        reviewPanelHorizontalPadding = sx(14)
        reviewPanelVerticalPadding = sy(12)
        reviewPanelCornerRadius = sx(10)
        reviewRowsGap = sy(10)
        reviewRowFont = min(sx(15), sy(15)) + 2
        reviewRowIconFont = min(sx(12), sy(12)) + 2
        reviewButtonTopSpacing = sy(10)
        reviewButtonHeight = sy(58)
        reviewButtonCornerRadius = sx(10)
        reviewButtonFont = min(sx(17), sy(17)) + 5
        reviewShadowRadius = sx(8)
        reviewShadowY = sy(4)

        actionCardGap = sx(8)
        actionCardHeight = sy(58)
        actionCardCornerRadius = sx(11)
        actionCardHorizontalPadding = sx(8)
        actionCardVerticalPadding = sy(8)
        actionIconCircle = sx(28)
        actionIconFont = min(sx(14), sy(14)) + 2
        actionTitleFont = min(sx(13), sy(13.5)) + 2
        actionContentGap = sy(7)

        libraryLinkFont = min(sx(13), sy(13)) + 2
        libraryCardCornerRadius = sx(12)
        libraryCardHorizontalPadding = sx(11)
        libraryCardVerticalPadding = sy(11)
        libraryCardContentGap = sy(10)
        libraryTopRowGap = sx(9)
        libraryIconBox = sx(26)
        libraryIconCornerRadius = sx(8)
        libraryIconFont = min(sx(14), sy(14)) + 2
        libraryTitleGap = sy(6)
        libraryTitleFont = min(sx(14), sy(14.5)) + 2
        libraryTagGap = sx(5)
        libraryTagFont = min(sx(10), sy(10.5)) + 2
        libraryTagHorizontalPadding = sx(7)
        libraryTagVerticalPadding = sy(2)
        libraryMetaFont = min(sx(12), sy(12)) + 2
        libraryChevronFont = min(sx(12), sy(12)) + 2
        libraryProgressHeight = max(5, sy(5))
    }
}

private struct HomeActionItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let background: Color
    let border: Color
    let textColor: Color
    let action: () -> Void
}

private struct BookModeConfig {
    let allPageIds: [Int]
    let selectedPageId: Int
}

private struct HomeRankPointsCard: View {
    let metrics: HomeMetrics
    let state: HomeViewModel.RankPointsCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: metrics.summaryIconFont, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.57, blue: 0.11))

                Text(state.rankText)
                    .font(.system(size: metrics.summaryTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.57, blue: 0.11))
            }

            Spacer()
                .frame(height: metrics.summaryTopGap)

            if state.isLoading && state.points == nil {
                ProgressView()
                    .tint(Color(red: 0.95, green: 0.57, blue: 0.11))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let points = state.points {
                HStack(alignment: .lastTextBaseline, spacing: metrics.summaryValueGap) {
                    Text(formatNumber(points))
                        .font(.system(size: metrics.summaryValueFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.22, green: 0.24, blue: 0.32))

                    if let pointsDelta = state.pointsDelta {
                        Text(formatDelta(pointsDelta))
                            .font(.system(size: metrics.summaryDeltaFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.15, green: 0.69, blue: 0.31))
                    }
                }
            } else {
                Text("Unavailable")
                    .font(.system(size: metrics.summarySubtitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.50, blue: 0.58))
            }
            /*
            Spacer()
                .frame(height: 3)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: metrics.summaryIconFont, weight: .bold))
                    .foregroundStyle(Color(red: 0.21, green: 0.42, blue: 0.94))

                Text(wordsText)
                    .font(.system(size: metrics.summarySubtitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.21, green: 0.42, blue: 0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(wordsDeltaText)
                    .font(.system(size: metrics.summarySubtitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.69, blue: 0.31))
                    .lineLimit(1)
            }
             */
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.summaryCardHorizontalPadding)
        .padding(.vertical, metrics.summaryCardVerticalPadding)
        .background(Color(red: 1.00, green: 0.95, blue: 0.84))
        .clipShape(RoundedRectangle(cornerRadius: metrics.summaryCardCornerRadius, style: .continuous))
    }
}

private struct HomeLeaderboardCard: View {
    let metrics: HomeMetrics
    let state: HomeViewModel.LeaderboardBannerState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "medal.fill")
                            .font(.system(size: metrics.summaryIconFont, weight: .bold))
                            .foregroundStyle(Color.orange)
                        Text(state.title)
                            .font(.system(size: metrics.summaryTitleFont, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.summaryIconFont - 1, weight: .bold))
                }
                .foregroundStyle(
                    state.isEnabled
                    ? Color(red: 0.26, green: 0.24, blue: 0.88)
                    : Color(red: 0.54, green: 0.56, blue: 0.64)
                )

                Spacer()
                    .frame(height: metrics.summaryTopGap)

                HStack(alignment: .lastTextBaseline, spacing: metrics.summaryValueGap) {
                    //Spacer().frame(height:3)
                    Text(positionText)
                        .font(.system(size: metrics.summaryValueFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.22, green: 0.21, blue: 0.62))

                    if let changeText {
                        Text(changeText)
                            .font(.system(size: metrics.summaryDeltaFont, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(changeBackground))
                    }
                }
                /*
                Spacer()
                    .frame(height: 3)

                Text("Group Position")
                    .font(.system(size: metrics.summarySubtitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.26, green: 0.24, blue: 0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                 */
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.summaryCardHorizontalPadding)
            .padding(.vertical, metrics.summaryCardVerticalPadding)
            .background(
                state.isEnabled
                ? Color(red: 0.94, green: 0.94, blue: 1.00)
                : Color(red: 0.95, green: 0.95, blue: 0.97)
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.summaryCardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.summaryCardCornerRadius, style: .continuous)
                    .stroke(
                        state.isEnabled
                        ? Color(red: 0.76, green: 0.79, blue: 1.00)
                        : Color(red: 0.86, green: 0.87, blue: 0.91),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
    }

    private var positionText: String {
        if let position = state.currentUserPosition {
            return "#\(position)"
        }
        return "#—"
    }

    private var changeText: String? {
        guard let change = state.groupRankChange else { return nil }
        if change > 0 {
            return "↑ \(change)"
        }
        if change < 0 {
            return "↓ \(abs(change))"
        }
        return nil
    }

    private var changeBackground: Color {
        guard let change = state.groupRankChange else {
            return Color(red: 0.66, green: 0.67, blue: 0.72)
        }
        if change > 0 {
            return Color(red: 0.22, green: 0.79, blue: 0.37)
        }
        if change < 0 {
            return Color(red: 0.91, green: 0.32, blue: 0.25)
        }
        return Color(red: 0.66, green: 0.67, blue: 0.72)
    }
}

private func formatNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatDelta(_ value: Int) -> String {
    value >= 0 ? "+\(value)" : "\(value)"
}

private struct ReviewStatusRow: View {
    let label: String
    let value: String
    let icon: String?
    let metrics: HomeMetrics

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: metrics.reviewRowIconFont, weight: .bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.05))
                }

                Text(label)
                    .font(.system(size: metrics.reviewRowFont, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))
            }

            Spacer()

            Text(value)
                .font(.system(size: metrics.reviewRowFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.84))
        }
    }
}

private struct ActionButton: View {
    let item: HomeActionItem
    let metrics: HomeMetrics

    var body: some View {
        Button(action: item.action) {
            VStack(spacing: metrics.actionContentGap) {
                Circle()
                    .fill(item.iconBackground)
                    .frame(width: metrics.actionIconCircle, height: metrics.actionIconCircle)
                    .overlay {
                        Image(systemName: item.icon)
                            .font(.system(size: metrics.actionIconFont, weight: .bold))
                            .foregroundStyle(item.iconColor)
                    }

                Text(item.title)
                    .font(.system(size: metrics.actionTitleFont, weight: .bold, design: .rounded))
                    .foregroundStyle(item.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.actionCardHeight)
            .padding(.horizontal, metrics.actionCardHorizontalPadding)
            .padding(.vertical, metrics.actionCardVerticalPadding)
            .background(item.background)
            .clipShape(RoundedRectangle(cornerRadius: metrics.actionCardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.actionCardCornerRadius, style: .continuous)
                    .stroke(item.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ArticleTag: View {
    let text: String
    let metrics: HomeMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.libraryTagFont, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.59, green: 0.29, blue: 0.95))
            .padding(.horizontal, metrics.libraryTagHorizontalPadding)
            .padding(.vertical, metrics.libraryTagVerticalPadding)
            .background(Capsule().fill(Color(red: 0.92, green: 0.85, blue: 1.00)))
    }
}

private struct LeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: HomeViewModel.LeaderboardSheetState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaderboard")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                        Text(groupSubtitle)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(red: 0.48, green: 0.49, blue: 0.58))
                            .frame(width: 36, height: 36)
                            .background(Color(red: 0.97, green: 0.97, blue: 0.99))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.groupTitle)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.53, green: 0.48, blue: 0.33))

                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(formatNumber(state.currentUserPoints))
                                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.22))
                                Text(formatDelta(state.currentUserPointsDelta))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.10, green: 0.67, blue: 0.30))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "medal.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.orange)
                                Text(positionText)
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                            }

                            Text(movementText)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(movementColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(movementBackground))
                        }
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.97, blue: 0.91),
                                Color(red: 1.00, green: 0.96, blue: 0.86)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                    Divider()
                        .overlay(Color(red: 0.95, green: 0.83, blue: 0.48))

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(state.members) { member in
                                LeaderboardRow(member: member)
                            }
                        }
                    }
                }
            }
            .background(Color.white)
        }
    }

    private var groupSubtitle: String {
        let memberCount = state.groupMemberCount
        if let groupNo = state.groupNo {
            return "Group \(groupNo) • \(memberCount) learners"
        }
        return "\(memberCount) learners"
    }

    private var positionText: String {
        if let position = state.currentUserPosition {
            return "#\(position)"
        }
        return "—"
    }

    private var movementText: String {
        if state.currentUserGroupRankChange > 0 {
            return "Up \(state.currentUserGroupRankChange) spots"
        }
        if state.currentUserGroupRankChange < 0 {
            return "Down \(abs(state.currentUserGroupRankChange)) spots"
        }
        return "No change"
    }

    private var movementColor: Color {
        if state.currentUserGroupRankChange > 0 {
            return Color(red: 0.10, green: 0.67, blue: 0.30)
        }
        if state.currentUserGroupRankChange < 0 {
            return Color(red: 0.82, green: 0.28, blue: 0.24)
        }
        return Color(red: 0.58, green: 0.50, blue: 0.24)
    }

    private var movementBackground: Color {
        if state.currentUserGroupRankChange > 0 {
            return Color(red: 0.89, green: 1.00, blue: 0.90)
        }
        if state.currentUserGroupRankChange < 0 {
            return Color(red: 1.00, green: 0.92, blue: 0.92)
        }
        return Color(red: 0.99, green: 0.94, blue: 0.81)
    }
}

private struct LeaderboardRow: View {
    let member: HomeViewModel.LeaderboardMemberState

    var body: some View {
        HStack(spacing: 12) {
            if let medal = medalText {
                Text(medal)
                    .font(.system(size: 24))
                    .frame(width: 30)
            } else {
                Text("\(member.position)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.53))
                    .frame(width: 30, height: 30)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .clipShape(Circle())
            }

            Text(displayName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.27, green: 0.29, blue: 0.36))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(member.isCurrentUser ? Color.orange : Color(red: 0.63, green: 0.65, blue: 0.72))
                Text(formatNumber(member.periodPoints))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(member.isCurrentUser ? Color(red: 0.84, green: 0.45, blue: 0.12) : Color(red: 0.33, green: 0.36, blue: 0.44))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(member.isCurrentUser ? Color(red: 1.00, green: 0.98, blue: 0.90) : Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(member.isCurrentUser ? Color(red: 0.95, green: 0.83, blue: 0.48) : Color.black.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var displayName: String {
        member.displayName
    }

    private var medalText: String? {
        switch member.position {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }
}
