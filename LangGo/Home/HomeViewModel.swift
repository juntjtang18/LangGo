import Combine
import Foundation
import os

@MainActor
final class HomeViewModel: ObservableObject {
    struct RankPointsCardState: Equatable {
        let rankText: String
        let points: Int?
        let pointsDelta: Int?
        let isLoading: Bool

        static let empty = RankPointsCardState(
            rankText: "Unranked",
            points: nil,
            pointsDelta: nil,
            isLoading: false
        )
    }

    struct ReviewCardState: Equatable {
        let totalCards: Int
        let dueForReview: Int
        let remembered: Int

        static let empty = ReviewCardState(
            totalCards: 0,
            dueForReview: 0,
            remembered: 0
        )
    }

    struct LeaderboardBannerState: Equatable {
        let title: String
        let currentUserPosition: Int?
        let groupRankChange: Int?
        let isEnabled: Bool

        static let empty = LeaderboardBannerState(
            title: "Leaderboard",
            currentUserPosition: nil,
            groupRankChange: nil,
            isEnabled: false
        )
    }

    struct LeaderboardSheetState: Equatable {
        let title: String
        let rankTitle: String?
        let groupNo: Int?
        let currentUserPosition: Int?
        let currentUserPoints: Int
        let currentUserPointsDelta: Int
        let currentUserGroupRankChange: Int

        static let empty = LeaderboardSheetState(
            title: "Leaderboard",
            rankTitle: nil,
            groupNo: nil,
            currentUserPosition: nil,
            currentUserPoints: 0,
            currentUserPointsDelta: 0,
            currentUserGroupRankChange: 0
        )
    }

    struct ArticleLibraryPreviewState: Identifiable, Equatable {
        let id: Int
        let backendId: Int
        let title: String
        let content: String?
        let wordCount: Int
        let newWords: Int
        let progress: Double
        let primaryTag: String?
        let tags: [String]
        let dateLabel: String?
        let sourceLabel: String?
        let displayedTags: [String]
        let progressFraction: Double
        let progressText: String
    }

    @Published private(set) var rankPointsState = RankPointsCardState.empty
    @Published private(set) var reviewCardState = ReviewCardState.empty
    @Published private(set) var leaderboardBannerState = LeaderboardBannerState.empty
    @Published private(set) var leaderboardSheetState = LeaderboardSheetState.empty
    @Published private(set) var articleLibraryCount: Int?
    @Published private(set) var articleLibraryPreviews: [ArticleLibraryPreviewState] = []
    @Published private(set) var isLoadingSnapshot = false
    @Published private(set) var nextFlashcardStatisticsFetchAt: Date?

    private let userSnapshotService: UserSnapshotService
    private let flashcardService: FlashcardService
    private let articleService: ArticleService
    private let localeProvider: () -> String
    private let articlePreviewPageSize: Int

    private var cancellables = Set<AnyCancellable>()
    private var hasLoadedSnapshot = false
    private var hasLoadedFlashcardStatistics = false
    private var hasLoadedArticleLibrary = false

    init(
        userSnapshotService: UserSnapshotService? = nil,
        flashcardService: FlashcardService? = nil,
        articleService: ArticleService? = nil,
        articlePreviewPageSize: Int = 3,
        localeProvider: (() -> String)? = nil
    ) {
        let services = DataServices.shared
        self.userSnapshotService = userSnapshotService ?? services.userSnapshotService
        self.flashcardService = flashcardService ?? services.flashcardService
        self.articleService = articleService ?? services.articleService
        self.articlePreviewPageSize = articlePreviewPageSize
        self.localeProvider = localeProvider ?? {
            UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        }

        bindServices()
        syncPublishedState()
    }

    func loadIfNeeded() async {
        await loadSnapshotIfNeeded()
        await loadFlashcardStatisticsIfNeeded()
        await loadArticleLibraryIfNeeded()
    }

    func handlePullToRefresh() async {
        await refreshFlashcardStatistics(forceRefresh: true)
        await ensureSnapshotLoadedFromCache()
        await refreshArticleLibrary()
    }

    func handleScheduledFlashcardStatisticsRefresh() async {
        await refreshFlashcardStatistics(forceRefresh: true)
    }

    func handleFlashcardsDidChange() async {
        await refreshFlashcardStatistics(forceRefresh: true)
    }

    func handleSceneDidBecomeActive() async {
        await refreshVisibleContent()
    }

    func handleHomeTabSelected() async {
        await refreshVisibleContent()
    }

    func handlePresentedFlowDismissed() async {
        await refreshVisibleContent()
    }

    private func bindServices() {
        userSnapshotService.$latestSnapshot
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        flashcardService.$flashcardStatistics
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        flashcardService.$nextFlashcardStatisticsFetchAt
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        articleService.$userArticlesTotalCount
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        articleService.$userArticlePages
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshVisibleContent() async {
        await refreshFlashcardStatistics()
        await ensureSnapshotLoadedFromCache()
        await refreshArticleLibrary()
    }

    private func loadSnapshotIfNeeded() async {
        guard !hasLoadedSnapshot else { return }
        await ensureSnapshotLoadedFromCache()
    }

    private func ensureSnapshotLoadedFromCache() async {
        hasLoadedSnapshot = true
        isLoadingSnapshot = true
        syncPublishedState()
        defer {
            isLoadingSnapshot = false
            syncPublishedState()
        }

        await userSnapshotService.loadSnapshot(locale: currentLocale())
    }

    private func loadFlashcardStatisticsIfNeeded() async {
        guard !hasLoadedFlashcardStatistics else { return }
        hasLoadedFlashcardStatistics = true
        await flashcardService.loadStatisticsIfNeeded()
    }

    private func refreshFlashcardStatistics(forceRefresh: Bool = false) async {
        await flashcardService.refreshStatistics(forceRefresh: forceRefresh)
    }

    private func loadArticleLibraryIfNeeded() async {
        guard !hasLoadedArticleLibrary else { return }
        hasLoadedArticleLibrary = true
        await articleService.loadUserArticlesPageIfNeeded(page: 1, pageSize: articlePreviewPageSize)
    }

    private func refreshArticleLibrary() async {
        await articleService.refreshUserArticles(page: 1, pageSize: articlePreviewPageSize)
    }

    private func syncPublishedState() {
        let snapshot = userSnapshotService.currentSnapshot(locale: currentLocale())

        rankPointsState = makeRankPointsCardState(snapshot: snapshot)
        reviewCardState = makeReviewCardState(statistics: flashcardService.flashcardStatistics)
        leaderboardBannerState = makeLeaderboardBannerState(snapshot: snapshot)
        leaderboardSheetState = makeLeaderboardSheetState(snapshot: snapshot)
        nextFlashcardStatisticsFetchAt = flashcardService.nextFlashcardStatisticsFetchAt
        articleLibraryCount = articleService.userArticlesTotalCount
        articleLibraryPreviews = makeArticleLibraryPreviewStates()
    }

    private func makeArticleLibraryPreviewStates() -> [ArticleLibraryPreviewState] {
        guard let response = resolvedArticlePreviewResponse() else { return [] }

        return (response.data ?? [])
            .prefix(articlePreviewPageSize)
            .map(makeArticleLibraryPreviewState)
    }

    private func resolvedArticlePreviewResponse() -> StrapiListResponse<StrapiUserArticle>? {
        articleService.userArticlePages
            .filter { $0.key.page == 1 }
            .sorted { lhs, rhs in
                lhs.key.pageSize > rhs.key.pageSize
            }
            .first?
            .value
    }

    private func makeArticleLibraryPreviewState(from article: StrapiUserArticle) -> ArticleLibraryPreviewState {
        let trimmedTitle = article.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? "Untitled Article"
        let content = article.attributes.content
        let tagNames = article.attributes.articleTags?.data.compactMap {
            $0.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty } ?? []
        let wordCount = article.attributes.wordCount
            ?? content?.split { $0.isWhitespace || $0.isNewline }.count
            ?? 0
        let progressFraction = min(max(article.attributes.progress ?? 0, 0), 1)
        let displayedTags = Array(tagNames.prefix(2)).isEmpty ? ["My Article"] : Array(tagNames.prefix(2))
        let newWords = max(8, min(max(wordCount / 28, 0), 60))
        let dateLabel = relativeDateLabel(for: article.attributes.lastReadAt)

        return ArticleLibraryPreviewState(
            id: article.id,
            backendId: article.id,
            title: resolvedTitle,
            content: content,
            wordCount: wordCount,
            newWords: newWords,
            progress: progressFraction,
            primaryTag: tagNames.first,
            tags: tagNames,
            dateLabel: dateLabel,
            sourceLabel: "My Article",
            displayedTags: displayedTags,
            progressFraction: progressFraction,
            progressText: "\(Int((progressFraction * 100).rounded()))%"
        )
    }

    private func relativeDateLabel(for date: Date?) -> String {
        guard let date else { return "Saved" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func makeRankPointsCardState(snapshot: UserRankSnapshot?) -> RankPointsCardState {
        guard let snapshot else {
            return RankPointsCardState(
                rankText: isLoadingSnapshot ? "Loading..." : "Unranked",
                points: nil,
                pointsDelta: nil,
                isLoading: isLoadingSnapshot
            )
        }

        let rankText = trimmed(snapshot.rankText).flatMap { !$0.isEmpty ? $0 : nil }
            ?? (snapshot.group_rank > 0 ? "#\(snapshot.group_rank)" : "Unranked")

        return RankPointsCardState(
            rankText: rankText,
            points: snapshot.total_points,
            pointsDelta: snapshot.points_add,
            isLoading: isLoadingSnapshot
        )
    }

    private func makeReviewCardState(statistics: StrapiStatistics?) -> ReviewCardState {
        guard let statistics else { return .empty }

        return ReviewCardState(
            totalCards: statistics.totalCards,
            dueForReview: statistics.dueForReview,
            remembered: statistics.remembered
        )
    }

    private func makeLeaderboardBannerState(snapshot: UserRankSnapshot?) -> LeaderboardBannerState {
        guard let snapshot else {
            return LeaderboardBannerState(
                title: isLoadingSnapshot ? "Loading..." : "Leaderboard",
                currentUserPosition: nil,
                groupRankChange: nil,
                isEnabled: false
            )
        }

        return LeaderboardBannerState(
            title: leaderboardTitle(for: snapshot),
            currentUserPosition: snapshot.group_rank > 0 ? snapshot.group_rank : nil,
            groupRankChange: snapshot.group_rank_change == 0 ? nil : snapshot.group_rank_change,
            isEnabled: true
        )
    }

    private func makeLeaderboardSheetState(snapshot: UserRankSnapshot?) -> LeaderboardSheetState {
        guard let snapshot else { return .empty }

        return LeaderboardSheetState(
            title: leaderboardTitle(for: snapshot),
            rankTitle: trimmed(snapshot.rankText),
            groupNo: snapshot.group_no > 0 ? snapshot.group_no : nil,
            currentUserPosition: snapshot.group_rank > 0 ? snapshot.group_rank : nil,
            currentUserPoints: snapshot.total_points,
            currentUserPointsDelta: snapshot.points_add,
            currentUserGroupRankChange: snapshot.group_rank_change
        )
    }

    private func leaderboardTitle(for snapshot: UserRankSnapshot) -> String {
        if snapshot.group_no > 0 {
            return "Group \(snapshot.group_no)"
        }

        if let rankText = trimmed(snapshot.rankText), !rankText.isEmpty {
            return rankText
        }

        return "Leaderboard"
    }

    private func currentLocale() -> String {
        let locale = localeProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        return locale.isEmpty ? "en" : locale
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
