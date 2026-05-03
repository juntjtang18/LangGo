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
            title: "Leaderboard",
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

    private var cancellables = Set<AnyCancellable>()
    private var latestLeaderboard: MyLeaderboardData?

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

        bindServices()
        syncPublishedState()
    }

    func load() async {
        async let snapshotTask: Void = loadSnapshot()
        async let flashcardStatTask: Void = flashcardService.loadStatisticsIfNeeded()
        async let articleTask: Void = articleService.loadSharedUserArticlesIfNeeded()
        async let leaderboardTask: Void = loadLeaderboard()
        _ = await (snapshotTask, flashcardStatTask, articleTask, leaderboardTask)
        syncPublishedState()
    }

    func refresh() async {
        async let snapshotTask: Void = refreshUserSnapshot()
        async let flashcardStatTask: Void = flashcardService.refreshFlashcardStat()
        async let articleTask: Void = articleService.refreshArticleState()
        async let leaderboardTask: Void = refreshLeaderboard()
        _ = await (snapshotTask, flashcardStatTask, articleTask, leaderboardTask)
        syncPublishedState()
    }

    private func bindServices() {
        userSnapshotService.$latestSnapshot
            .sink { [weak self] _ in
                self?.syncPublishedState()
            }
            .store(in: &cancellables)

        flashcardService.$flashcardStatistics
            .sink { [weak self] _ in
                self?.syncPublishedState()
            }
            .store(in: &cancellables)

        articleService.$userArticlesTotalCount
            .sink { [weak self] _ in
                self?.syncPublishedState()
            }
            .store(in: &cancellables)

        articleService.$userArticles
            .sink { [weak self] _ in
                self?.syncPublishedState()
            }
            .store(in: &cancellables)

        flashcardService.$flashcardStatChanged
            .dropFirst()
            .sink { [weak self] changeToken in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleFlashcardStatChanged(changeToken: changeToken)
                }
            }
            .store(in: &cancellables)

        articleService.$articleChanged
            .dropFirst()
            .sink { [weak self] changeToken in
                guard let self else { return }
                Task { @MainActor in
                    self.logger.debug("reacting to articleChanged token=\(changeToken, privacy: .public)")
                    await self.articleService.refreshArticleState()
                }
            }
            .store(in: &cancellables)
    }

    private func loadSnapshot() async {
        isLoadingSnapshot = true
        syncPublishedState()
        defer {
            isLoadingSnapshot = false
            syncPublishedState()
        }

        await userSnapshotService.loadSnapshot(locale: currentLocale())
    }

    private func refreshUserSnapshot() async {
        isLoadingSnapshot = true
        syncPublishedState()
        defer {
            isLoadingSnapshot = false
            syncPublishedState()
        }

        do {
            _ = try await userSnapshotService.refreshUserSnapshot(locale: currentLocale())
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                return
            }
            logger.error("refreshUserSnapshot failed locale=\(self.currentLocale(), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleFlashcardStatChanged(changeToken: Int) async {
        logger.debug("reacting to flashcardStatChanged token=\(changeToken, privacy: .public)")
        async let statTask: Void = flashcardService.refreshFlashcardStat()
        async let snapshotTask: Void = refreshUserSnapshot()
        async let leaderboardTask: Void = refreshLeaderboard()
        _ = await (statTask, snapshotTask, leaderboardTask)
    }

    private func syncPublishedState() {
        let snapshot = userSnapshotService.currentSnapshot(locale: currentLocale())
        rankPointsState = makeRankPointsCardState(snapshot: snapshot)
        reviewCardState = makeReviewCardState(statistics: flashcardService.flashcardStatistics)
        leaderboardBannerState = makeLeaderboardBannerState(leaderboard: latestLeaderboard)
        leaderboardSheetState = makeLeaderboardSheetState(leaderboard: latestLeaderboard)
        articleLibraryCount = articleService.userArticlesTotalCount
        articleLibraryPreviews = makeArticleLibraryPreviewStates()
    }

    private func loadLeaderboard() async {
        do {
            latestLeaderboard = try await rankService.fetchMyLeaderboard()
        } catch {
            logger.error("loadLeaderboard failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshLeaderboard() async {
        do {
            latestLeaderboard = try await rankService.fetchMyLeaderboard()
        } catch {
            logger.error("refreshLeaderboard failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeArticleLibraryPreviewStates() -> [ArticleLibraryPreviewState] {
        articleService.userArticles
            .prefix(3)
            .map(makeArticleLibraryPreviewState)
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

        let rankText = trimmed(snapshot.level_title).flatMap { !$0.isEmpty ? $0 : nil }
            ?? trimmed(snapshot.rankText).flatMap { !$0.isEmpty ? $0 : nil }
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

    private func makeLeaderboardBannerState(leaderboard: MyLeaderboardData?) -> LeaderboardBannerState {
        guard let leaderboard else {
            return LeaderboardBannerState(
                title: isLoadingSnapshot ? "Loading..." : "Leaderboard",
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
                username: member.username,
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
            return "Group \(group.group_no)"
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

    private func normalizedPosition(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
