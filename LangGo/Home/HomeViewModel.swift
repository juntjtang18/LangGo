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
            rankText: String(localized: "Unranked"),
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
            title: String(localized: "Leaderboard"),
            currentUserPosition: nil,
            groupRankChange: nil,
            isEnabled: false
        )
    }

    struct LeaderboardSheetState: Equatable {
        struct MemberState: Identifiable, Equatable {
            let id: String
            let username: String
            let periodPoints: Int
            let orderInGroup: Int
            let isCurrentUser: Bool
        }

        let title: String
        let rankTitle: String?
        let groupNo: Int?
        let currentUserPosition: Int?
        let currentUserPoints: Int
        let currentUserPointsDelta: Int
        let currentUserGroupRankChange: Int
        let members: [MemberState]

        static let empty = LeaderboardSheetState(
            title: String(localized: "Leaderboard"),
            rankTitle: nil,
            groupNo: nil,
            currentUserPosition: nil,
            currentUserPoints: 0,
            currentUserPointsDelta: 0,
            currentUserGroupRankChange: 0,
            members: []
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

    private let userSnapshotService: UserSnapshotService
    private let flashcardService: FlashcardService
    private let articleService: ArticleService
    private let rankService: RankService
    private let localeProvider: () -> String
    private let logger = Logger(subsystem: "com.langGo.swift", category: "HomeViewModel")

    private var latestLeaderboard: MyLeaderboardData?
    private var reloadGeneration: Int = 0
    private var reloadTask: Task<Void, Never>?

    init(
        userSnapshotService: UserSnapshotService? = nil,
        flashcardService: FlashcardService? = nil,
        articleService: ArticleService? = nil,
        rankService: RankService? = nil,
        localeProvider: (() -> String)? = nil
    ) {
        let services = DataServices.shared
        self.userSnapshotService = userSnapshotService ?? services.userSnapshotService
        self.flashcardService = flashcardService ?? services.flashcardService
        self.articleService = articleService ?? services.articleService
        self.rankService = rankService ?? services.rankService
        self.localeProvider = localeProvider ?? {
            UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        }

        applyPublishedState(
            snapshot: nil,
            statistics: nil,
            leaderboard: nil
        )
    }

    func load() async {
        await runReloadJoiningInflight()
    }

    func refresh() async {
        await runReloadJoiningInflight()
    }

    private func runReloadJoiningInflight() async {
        if let existingTask = reloadTask {
            await existingTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.reloadHomeState()
        }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    private func reloadHomeState() async {
        let generation = nextReloadGeneration()
        isLoadingSnapshot = true
        applyPublishedState(
            snapshot: userSnapshotService.currentSnapshot(locale: currentLocale()),
            statistics: flashcardService.flashcardStatistics,
            leaderboard: latestLeaderboard
        )

        async let snapshotTask = fetchLatestSnapshot()
        async let statisticsTask = fetchLatestStatistics()
        async let articleTask = refreshArticles()
        async let leaderboardTask = fetchLatestLeaderboard()

        let snapshot = await snapshotTask
        let statistics = await statisticsTask
        _ = await articleTask
        let leaderboard = await leaderboardTask

        guard generation == reloadGeneration else { return }

        latestLeaderboard = leaderboard
        isLoadingSnapshot = false
        applyPublishedState(
            snapshot: snapshot,
            statistics: statistics,
            leaderboard: leaderboard
        )
    }

    private func fetchLatestSnapshot() async -> UserRankSnapshot? {
        do {
            return try await userSnapshotService.refreshUserSnapshot(locale: currentLocale())
        } catch {
            if !Task.isCancelled, (error as? URLError)?.code != .cancelled {
                logger.error("refreshUserSnapshot failed locale=\(self.currentLocale(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return userSnapshotService.currentSnapshot(locale: currentLocale())
        }
    }

    private func fetchLatestStatistics() async -> StrapiStatistics? {
        do {
            return try await flashcardService.fetchFlashcardStatistics(forceRefresh: true)
        } catch {
            return flashcardService.flashcardStatistics
        }
    }

    private func refreshArticles() async {
        await articleService.refreshArticleState()
    }

    private func fetchLatestLeaderboard() async -> MyLeaderboardData? {
        do {
            return try await rankService.fetchMyLeaderboard()
        } catch {
            logger.error("loadLeaderboard failed: \(error.localizedDescription, privacy: .public)")
            return latestLeaderboard
        }
    }

    private func applyPublishedState(
        snapshot: UserRankSnapshot?,
        statistics: StrapiStatistics?,
        leaderboard: MyLeaderboardData?
    ) {
        rankPointsState = makeRankPointsCardState(snapshot: snapshot)
        reviewCardState = makeReviewCardState(statistics: statistics)
        leaderboardBannerState = makeLeaderboardBannerState(leaderboard: leaderboard)
        leaderboardSheetState = makeLeaderboardSheetState(leaderboard: leaderboard)
        articleLibraryCount = articleService.userArticlesTotalCount
        articleLibraryPreviews = makeArticleLibraryPreviewStates()
    }

    private func nextReloadGeneration() -> Int {
        reloadGeneration += 1
        return reloadGeneration
    }

    private func makeArticleLibraryPreviewStates() -> [ArticleLibraryPreviewState] {
        articleService.userArticles
            .prefix(3)
            .map(makeArticleLibraryPreviewState)
    }

    private func makeArticleLibraryPreviewState(from article: StrapiUserArticle) -> ArticleLibraryPreviewState {
        let trimmedTitle = article.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? String(localized: "Untitled Article")
        let content = article.attributes.content
        let tagNames = article.attributes.articleTags?.data.compactMap {
            $0.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty } ?? []
        let wordCount = article.attributes.wordCount
            ?? content?.split { $0.isWhitespace || $0.isNewline }.count
            ?? 0
        let progressFraction = min(max(article.attributes.progress ?? 0, 0), 1)
        let displayedTags = Array(tagNames.prefix(2)).isEmpty ? [String(localized: "My Article")] : Array(tagNames.prefix(2))
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
            sourceLabel: String(localized: "My Article"),
            displayedTags: displayedTags,
            progressFraction: progressFraction,
            progressText: "\(Int((progressFraction * 100).rounded()))%"
        )
    }

    private func relativeDateLabel(for date: Date?) -> String {
        guard let date else { return String(localized: "Saved") }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func makeRankPointsCardState(snapshot: UserRankSnapshot?) -> RankPointsCardState {
        guard let snapshot else {
            return RankPointsCardState(
                rankText: isLoadingSnapshot ? String(localized: "Loading...") : String(localized: "Unranked"),
                points: nil,
                pointsDelta: nil,
                isLoading: isLoadingSnapshot
            )
        }

        let rankText = trimmed(snapshot.level_title).flatMap { !$0.isEmpty ? $0 : nil }
            ?? trimmed(snapshot.rankText).flatMap { !$0.isEmpty ? $0 : nil }
            ?? (snapshot.group_rank > 0 ? "#\(snapshot.group_rank)" : String(localized: "Unranked"))

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

    private func makeLeaderboardBannerState(leaderboard: MyLeaderboardData?) -> LeaderboardBannerState {
        guard let leaderboard else {
            return LeaderboardBannerState(
                title: isLoadingSnapshot ? String(localized: "Loading...") : String(localized: "Leaderboard"),
                currentUserPosition: nil,
                groupRankChange: nil,
                isEnabled: false
            )
        }

        return LeaderboardBannerState(
            title: leaderboardTitle(for: leaderboard.group),
            currentUserPosition: leaderboard.members.first(where: { $0.isCurrentUser })?.order_in_group ?? normalizedPosition(leaderboard.group.group_rank),
            groupRankChange: nil,
            isEnabled: leaderboard.group.member_count > 0
        )
    }

    private func makeLeaderboardSheetState(leaderboard: MyLeaderboardData?) -> LeaderboardSheetState {
        guard let leaderboard else { return .empty }

        let members = leaderboard.members.map { member in
            LeaderboardSheetState.MemberState(
                id: member.userid,
                username: displayName(for: member),
                periodPoints: member.period_points,
                orderInGroup: member.order_in_group,
                isCurrentUser: member.isCurrentUser
            )
        }

        let currentMember = members.first(where: { $0.isCurrentUser })

        return LeaderboardSheetState(
            title: leaderboardTitle(for: leaderboard.group),
            rankTitle: trimmed(leaderboard.group.group_rank_title),
            groupNo: normalizedPosition(leaderboard.group.group_no),
            currentUserPosition: currentMember?.orderInGroup ?? normalizedPosition(leaderboard.group.group_rank),
            currentUserPoints: currentMember?.periodPoints ?? 0,
            currentUserPointsDelta: 0,
            currentUserGroupRankChange: 0,
            members: members
        )
    }

    private func leaderboardTitle(for group: MyLeaderboardGroup) -> String {
        if group.group_no > 0 {
            let format = String(localized: "Group %lld")
            return String.localizedStringWithFormat(format, group.group_no)
        }
        return String(localized: "Leaderboard")
    }

    private func currentLocale() -> String {
        let locale = localeProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        return locale.isEmpty ? "en" : locale
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedPosition(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func displayName(for member: MyLeaderboardMember) -> String {
        let trimmedName = member.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }
        if member.isCurrentUser {
            return String(localized: "You")
        }
        let format = String(localized: "User %lld")
        return String.localizedStringWithFormat(format, Int64(member.userid) ?? 0)
    }
}
