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
            title: "No Group Yet",
            currentUserPosition: nil,
            groupRankChange: nil,
            isEnabled: false
        )
    }

    struct LeaderboardSheetState: Equatable {
        let groupTitle: String
        let groupNo: Int?
        let groupMemberCount: Int
        let currentUserPosition: Int?
        let currentUserPoints: Int
        let currentUserPointsDelta: Int
        let currentUserGroupRankChange: Int
        let members: [LeaderboardMemberState]

        static let empty = LeaderboardSheetState(
            groupTitle: "Your Group",
            groupNo: nil,
            groupMemberCount: 0,
            currentUserPosition: nil,
            currentUserPoints: 0,
            currentUserPointsDelta: 0,
            currentUserGroupRankChange: 0,
            members: []
        )
    }

    struct LeaderboardMemberState: Identifiable, Equatable {
        let id: Int
        let position: Int
        let periodPoints: Int
        let isCurrentUser: Bool
        let displayName: String
        let honorTitle: String?
    }

    @Published private(set) var rankPointsState = RankPointsCardState.empty
    @Published private(set) var reviewCardState = ReviewCardState.empty
    @Published private(set) var leaderboardBannerState = LeaderboardBannerState.empty
    @Published private(set) var leaderboardSheetState = LeaderboardSheetState.empty
    @Published private(set) var isLoadingUserPoints = false
    @Published private(set) var nextFlashcardStatisticsFetchAt: Date?

    private let logger = Logger(subsystem: "com.langGo.swift", category: "HomeViewModel")
    private let userPointsService: UserPointsService
    private let pointGroupService: PointGroupService
    private let flashcardService: FlashcardService
    private let localeProvider: () -> String
    private let dateFormatter = ISO8601DateFormatter()

    private var cancellables = Set<AnyCancellable>()
    private var flashcardStatistics: StrapiStatistics?
    private var hasLoadedUserPoints = false
    private var hasLoadedFlashcardStatistics = false
    private var hasLoadedPointGroup = false

    init(
        userPointsService: UserPointsService? = nil,
        pointGroupService: PointGroupService? = nil,
        flashcardService: FlashcardService? = nil,
        localeProvider: (() -> String)? = nil
    ) {
        let services = DataServices.shared
        self.userPointsService = userPointsService ?? services.userPointsService
        self.pointGroupService = pointGroupService ?? services.pointGroupService
        self.flashcardService = flashcardService ?? services.flashcardService
        self.localeProvider = localeProvider ?? {
            UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        }

        bindServices()
        syncPublishedState()
    }

    func loadIfNeeded() async {
        await loadUserPointsIfNeeded()
        await loadFlashcardStatisticsIfNeeded()
        await loadPointGroupIfNeeded()
    }

    func handlePullToRefresh() async {
        await refreshFlashcardStatistics()
    }

    func handleScheduledFlashcardStatisticsRefresh() async {
        await refreshFlashcardStatistics(forceRefresh: true)
    }

    func handleFlashcardsDidChange() async {
        await refreshFlashcardStatistics(forceRefresh: true)
        await refreshPointGroup()
    }

    func handleSceneDidBecomeActive() async {
        await refreshVisibleContent()
    }

    func handleHomeTabSelected() async {
        await refreshVisibleContent()
    }

    func loadLeaderboard() async {
        guard let pointGroupId = currentPointGroupId() else { return }
        await pointGroupService.loadPointGroupLeaderboard(
            pointGroupId: pointGroupId,
            locale: currentLocale()
        )
    }

    private func bindServices() {
        userPointsService.$myUserPoints
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        pointGroupService.$myPointGroup
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)

        pointGroupService.$pointGroupLeaderboard
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPublishedState()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshVisibleContent() async {
        await refreshFlashcardStatistics()
        await refreshUserPoints()
        await refreshPointGroup()
    }

    private func loadUserPointsIfNeeded() async {
        guard !hasLoadedUserPoints else { return }
        hasLoadedUserPoints = true

        isLoadingUserPoints = true
        syncPublishedState()
        defer {
            isLoadingUserPoints = false
            syncPublishedState()
        }

        await userPointsService.loadMyUserPoints(locale: currentLocale())
    }

    private func refreshUserPoints() async {
        isLoadingUserPoints = true
        syncPublishedState()
        defer {
            isLoadingUserPoints = false
            syncPublishedState()
        }

        do {
            _ = try await userPointsService.refreshMyUserPoints(locale: currentLocale())
        } catch {
            logger.error("Failed to fetch user points: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFlashcardStatisticsIfNeeded() async {
        guard !hasLoadedFlashcardStatistics else { return }
        hasLoadedFlashcardStatistics = true
        await refreshFlashcardStatistics()
    }

    private func refreshFlashcardStatistics(forceRefresh: Bool = false) async {
        do {
            let statistics = try await flashcardService.fetchFlashcardStatistics(forceRefresh: forceRefresh)
            flashcardStatistics = statistics
            reviewCardState = makeReviewCardState(statistics: statistics)
            nextFlashcardStatisticsFetchAt = nextFlashcardStatisticsFetchDate(from: statistics)
        } catch {
            logger.error("Failed to fetch flashcard statistics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPointGroupIfNeeded() async {
        guard !hasLoadedPointGroup else { return }
        hasLoadedPointGroup = true
        await pointGroupService.loadMyPointGroup(locale: currentLocale())
    }

    private func refreshPointGroup() async {
        do {
            _ = try await pointGroupService.refreshMyPointGroup(locale: currentLocale())
        } catch {
            logger.error("Failed to fetch point group: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncPublishedState() {
        let locale = currentLocale()
        let userPoints = userPointsService.currentMyUserPoints(locale: locale)
        let pointGroup = pointGroupService.currentMyPointGroup(locale: locale)
        let leaderboard = resolvedLeaderboard(locale: locale, pointGroup: pointGroup)

        rankPointsState = makeRankPointsCardState(userPoints: userPoints)
        reviewCardState = makeReviewCardState(statistics: flashcardStatistics)
        leaderboardBannerState = makeLeaderboardBannerState(
            userPoints: userPoints,
            leaderboard: leaderboard
        )
        leaderboardSheetState = makeLeaderboardSheetState(
            userPoints: userPoints,
            leaderboard: leaderboard
        )
    }

    private func resolvedLeaderboard(
        locale: String,
        pointGroup: MyPointGroupData?
    ) -> PointGroupLeaderboardData? {
        guard let pointGroup else { return nil }

        if let pointGroupId = pointGroup.pointGroup?.id,
           let leaderboard = pointGroupService.currentPointGroupLeaderboard(
            pointGroupId: pointGroupId,
            locale: locale
           ) {
            return leaderboard
        }

        return PointGroupLeaderboardData(
            pointGroup: pointGroup.pointGroup,
            currentUserPosition: pointGroup.myMembership.positionInGroup,
            groupMemberCount: pointGroup.myMembership.groupMemberCount,
            leaderboard: pointGroup.leaderboard
        )
    }

    private func makeRankPointsCardState(
        userPoints: MyUserPointsAttributes?
    ) -> RankPointsCardState {
        guard let userPoints else {
            return RankPointsCardState(
                rankText: isLoadingUserPoints ? "Loading..." : "Unranked",
                points: nil,
                pointsDelta: nil,
                isLoading: isLoadingUserPoints
            )
        }

        let rankText = trimmed(userPoints.rankText).flatMap { !$0.isEmpty ? $0 : nil }
            ?? (userPoints.rank > 0 ? "#\(userPoints.rank)" : "Unranked")

        return RankPointsCardState(
            rankText: rankText,
            points: userPoints.points,
            pointsDelta: userPoints.points_add,
            isLoading: isLoadingUserPoints
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

    private func makeLeaderboardBannerState(
        userPoints: MyUserPointsAttributes?,
        leaderboard: PointGroupLeaderboardData?
    ) -> LeaderboardBannerState {
        let title: String
        if let groupRankTitle = trimmed(leaderboard?.pointGroup?.groupRank?.title), !groupRankTitle.isEmpty {
            title = groupRankTitle
        } else {
            title = "No Group Yet"
        }

        return LeaderboardBannerState(
            title: title,
            currentUserPosition: leaderboard?.currentUserPosition,
            groupRankChange: userPoints?.group_rank_change,
            isEnabled: leaderboard?.pointGroup?.id != nil && !isLoadingUserPoints
        )
    }

    private func makeLeaderboardSheetState(
        userPoints: MyUserPointsAttributes?,
        leaderboard: PointGroupLeaderboardData?
    ) -> LeaderboardSheetState {
        guard let leaderboard else { return .empty }

        let resolvedUserPoints = userPoints ?? .empty

        return LeaderboardSheetState(
            groupTitle: leaderboard.pointGroup?.groupRank?.title ?? "Your Group",
            groupNo: leaderboard.pointGroup?.groupNo,
            groupMemberCount: leaderboard.groupMemberCount,
            currentUserPosition: leaderboard.currentUserPosition,
            currentUserPoints: resolvedUserPoints.points,
            currentUserPointsDelta: resolvedUserPoints.points_add,
            currentUserGroupRankChange: resolvedUserPoints.group_rank_change,
            members: leaderboard.leaderboard.map(makeLeaderboardMemberState)
        )
    }

    private func makeLeaderboardMemberState(
        member: PointGroupLeaderboardMember
    ) -> LeaderboardMemberState {
        LeaderboardMemberState(
            id: member.id,
            position: member.position,
            periodPoints: member.periodPoints,
            isCurrentUser: member.isCurrentUser,
            displayName: member.user.username ?? member.user.email ?? "Unknown",
            honorTitle: member.user.honorTitle?.title
        )
    }

    private func currentPointGroupId() -> Int? {
        let locale = currentLocale()
        return pointGroupService.currentMyPointGroup(locale: locale)?.pointGroup?.id
    }

    private func currentLocale() -> String {
        let locale = localeProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        return locale.isEmpty ? "en" : locale
    }

    private func nextFlashcardStatisticsFetchDate(from statistics: StrapiStatistics) -> Date? {
        guard statistics.dueForReview == 0 else {
            return nil
        }

        guard let nextFetchAt = statistics.nextFetchAt else {
            return nil
        }

        return dateFormatter.date(from: nextFetchAt)
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
