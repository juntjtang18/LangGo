import SwiftUI

@MainActor
final class AscentViewModel: ObservableObject {
    @Published private(set) var totalPointsText = "0"
    @Published private(set) var groupOrderText = "#-"

    private let rankService: RankService
    private let userSnapshotService: UserSnapshotService
    private let localeProvider: () -> String

    init(
        rankService: RankService? = nil,
        userSnapshotService: UserSnapshotService? = nil,
        localeProvider: (() -> String)? = nil
    ) {
        let services = DataServices.shared
        self.rankService = rankService ?? services.rankService
        self.userSnapshotService = userSnapshotService ?? services.userSnapshotService
        self.localeProvider = localeProvider ?? {
            UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        }
    }

    func load() async {
        async let snapshotTask = userSnapshotService.loadSnapshot(locale: currentLocale())
        async let leaderboardTask = rankService.fetchMyLeaderboard()

        _ = await snapshotTask
        let leaderboard = try? await leaderboardTask
        let snapshot = userSnapshotService.currentSnapshot(locale: currentLocale())

        totalPointsText = formatNumber(snapshot?.total_points ?? 0)
        if let currentMember = leaderboard?.members.first(where: { $0.isCurrentUser }) {
            groupOrderText = "#\(currentMember.order_in_group)"
        } else {
            groupOrderText = "#-"
        }
    }

    private func currentLocale() -> String {
        localeProvider()
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct AscentTabView: View {
    let onShowProfile: () -> Void

    var body: some View {
        NavigationStack {
            AscentView(onShowProfile: onShowProfile)
                .navigationTitle("")
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct AscentView: View {
    let onShowProfile: () -> Void
    @StateObject private var userSession = UserSessionManager.shared
    @StateObject private var viewModel: AscentViewModel
    @State private var isShowingLeaderboard = false

    private let statCards: [AscentStatCard] = [
        .init(title: "Streak", value: "7 days", icon: "calendar", accent: Color(red: 0.96, green: 0.42, blue: 0.12), background: Color(red: 1.00, green: 0.96, blue: 0.92)),
        .init(title: "Words", value: "342", icon: "character.book.closed", accent: Color(red: 0.21, green: 0.47, blue: 0.96), background: Color(red: 0.92, green: 0.95, blue: 1.00)),
        .init(title: "Articles", value: "12", icon: "arrow.up.right.circle", accent: Color(red: 0.58, green: 0.24, blue: 0.94), background: Color(red: 0.96, green: 0.93, blue: 1.00)),
        .init(title: "Study Days", value: "45", icon: "trophy", accent: Color(red: 0.07, green: 0.70, blue: 0.29), background: Color(red: 0.93, green: 0.99, blue: 0.95))
    ]

    private let achievements: [AscentAchievement] = [
        .init(emoji: "🎯", title: "First Steps", subtitle: "Added your first word", accent: Color(red: 1.00, green: 0.76, blue: 0.20), isDimmed: false),
        .init(emoji: "🔥", title: "Week Warrior", subtitle: "7-day streak", accent: Color(red: 1.00, green: 0.76, blue: 0.20), isDimmed: false),
        .init(emoji: "💯", title: "Century Club", subtitle: "Learn 100 words", accent: Color(red: 1.00, green: 0.76, blue: 0.20), isDimmed: false),
        .init(emoji: "📚", title: "Bookworm", subtitle: "Read 10 articles", accent: Color(red: 1.00, green: 0.76, blue: 0.20), isDimmed: false),
        .init(emoji: "⭐", title: "Rising Star", subtitle: "Reach top 10", accent: Color(red: 1.00, green: 0.76, blue: 0.20), isDimmed: false),
        .init(emoji: "🏆", title: "Month Master", subtitle: "30-day streak", accent: Color(red: 0.91, green: 0.88, blue: 0.75), isDimmed: true)
    ]

    @MainActor
    init(
        onShowProfile: @escaping () -> Void,
        viewModel: AscentViewModel? = nil
    ) {
        self.onShowProfile = onShowProfile
        self._viewModel = StateObject(wrappedValue: viewModel ?? AscentViewModel())
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AscentMetrics(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    hero(metrics: metrics)
                    statsGrid(metrics: metrics)
                    achievementsSection(metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
            .background(Color(red: 0.99, green: 0.99, blue: 1.00).ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $isShowingLeaderboard) {
            AscentLeaderboardSheet()
        }
        .task {
            await viewModel.load()
        }
    }

    private func hero(metrics: AscentMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.heroSpacing) {
            profileButton(metrics: metrics)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: metrics.heroSpacing) {
                VStack(alignment: .leading, spacing: metrics.textTightSpacing) {
                    Text("Ascent")
                        .font(.system(size: metrics.titleFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your journey to glory")
                        .font(.system(size: metrics.subtitleFont, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                VStack(alignment: .leading, spacing: metrics.cardInnerSpacing) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: metrics.textTightSpacing) {
                            Text("Total Points")
                                .font(.system(size: metrics.pointsLabelFont, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))

                            Text(viewModel.totalPointsText)
                                .font(.system(size: metrics.pointsFont, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Spacer(minLength: metrics.compactSpacing)

                        VStack(alignment: .trailing, spacing: metrics.badgeSpacing) {
                            Spacer()
                            Text(viewModel.groupOrderText)
                                .font(.system(size: metrics.rankFont, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            /*
                            Text("Up 4")
                                .font(.system(size: metrics.rankBadgeFont, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, metrics.rankBadgeHorizontalPadding)
                                .padding(.vertical, metrics.rankBadgeVerticalPadding)
                                .background(Capsule().fill(Color(red: 0.07, green: 0.70, blue: 0.29)))
                             */
                        }
                    }

                    Button {
                        isShowingLeaderboard = true
                    } label: {
                        Text("View Leaderboard")
                            .font(.system(size: metrics.leaderboardButtonFont, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.28, green: 0.25, blue: 0.98))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, metrics.leaderboardButtonVerticalPadding)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: metrics.innerCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(metrics.pointsCardPadding)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            }
            .padding(metrics.heroPadding)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.34, blue: 0.98),
                        Color(red: 0.63, green: 0.12, blue: 0.93)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.heroCornerRadius, style: .continuous))
        }
    }

    private func profileButton(metrics: AscentMetrics) -> some View {
        Button {
            onShowProfile()
        } label: {
            VStack(spacing: metrics.profileButtonSpacing) {
                AscentProfileAvatarView(
                    imageURL: resolvedMediaURL(from: userSession.currentUser?.user_profile?.avatar_img?.data?.attributes.url),
                    initials: profileInitials,
                    metrics: metrics
                )

                Text("Profile")
                    .font(.system(size: metrics.profileLabelFont, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))
            }
            .frame(minWidth: metrics.profileTapWidth, minHeight: metrics.profileTapHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statsGrid(metrics: AscentMetrics) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: metrics.compactSpacing),
            GridItem(.flexible(), spacing: metrics.compactSpacing)
        ], spacing: metrics.compactSpacing) {
            ForEach(statCards) { card in
                AscentStatCardView(card: card, metrics: metrics)
            }
        }
    }

    private func achievementsSection(metrics: AscentMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.compactSectionSpacing) {
            HStack {
                Text("ACHIEVEMENTS")
                    .font(.system(size: metrics.sectionLabelFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.56))

                Spacer()

                Button { } label: {
                    Text("View All")
                        .font(.system(size: metrics.viewAllFont, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.28, green: 0.25, blue: 0.98))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: metrics.compactSpacing),
                GridItem(.flexible(), spacing: metrics.compactSpacing),
                GridItem(.flexible(), spacing: metrics.compactSpacing)
            ], spacing: metrics.compactSpacing) {
                ForEach(achievements) { achievement in
                    AscentAchievementCard(achievement: achievement, metrics: metrics)
                }
            }
        }
    }

    private var profileInitials: String {
        let username = userSession.currentUser?.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (username?.isEmpty == false ? username : UserDefaults.standard.string(forKey: "username")) ?? "LG"
        let words = source
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
            .map(String.init)

        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return String(first + second).uppercased()
        }

        return String(source.prefix(2)).uppercased()
    }
}

private struct AscentStatCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let accent: Color
    let background: Color
}

private struct AscentAchievement: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let subtitle: String
    let accent: Color
    let isDimmed: Bool
}

private struct AscentMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let compactSectionSpacing: CGFloat
    let compactSpacing: CGFloat
    let textTightSpacing: CGFloat

    let titleFont: CGFloat
    let subtitleFont: CGFloat
    let pointsLabelFont: CGFloat
    let pointsFont: CGFloat
    let rankFont: CGFloat
    let rankBadgeFont: CGFloat
    let leaderboardButtonFont: CGFloat
    let profileInitialsFont: CGFloat
    let profileLabelFont: CGFloat
    let sectionLabelFont: CGFloat
    let viewAllFont: CGFloat
    let statTitleFont: CGFloat
    let statValueFont: CGFloat
    let statIconFont: CGFloat
    let achievementEmojiFont: CGFloat
    let achievementTitleFont: CGFloat
    let achievementSubtitleFont: CGFloat

    let heroPadding: CGFloat
    let heroCornerRadius: CGFloat
    let heroSpacing: CGFloat
    let heroIconTopPadding: CGFloat
    let profileButtonSpacing: CGFloat
    let profileButtonSize: CGFloat
    let profileTapWidth: CGFloat
    let profileTapHeight: CGFloat
    let pointsCardPadding: CGFloat
    let cardCornerRadius: CGFloat
    let innerCornerRadius: CGFloat
    let cardInnerSpacing: CGFloat
    let badgeSpacing: CGFloat
    let rankBadgeHorizontalPadding: CGFloat
    let rankBadgeVerticalPadding: CGFloat
    let leaderboardButtonVerticalPadding: CGFloat
    let statCardPadding: CGFloat
    let statIconCircle: CGFloat
    let statCardHeight: CGFloat
    let achievementCardPadding: CGFloat
    let achievementCardHeight: CGFloat

    init(screenSize: CGSize) {
        let widthScale = screenSize.width / 393
        let heightScale = screenSize.height / 852
        let resolvedScale = min(max(min(widthScale, heightScale), 0.88), 1.10)
        let compactScale: CGFloat = screenSize.height < 760 ? 0.94 : 1.0

        func scaled(_ value: CGFloat) -> CGFloat {
            value * resolvedScale * compactScale
        }

        horizontalPadding = scaled(16)
        topPadding = scaled(12)
        bottomPadding = scaled(26)
        sectionSpacing = scaled(18)
        compactSectionSpacing = scaled(10)
        compactSpacing = scaled(10)
        textTightSpacing = scaled(3)

        titleFont = scaled(31)
        subtitleFont = scaled(21)
        pointsLabelFont = scaled(20.5)
        pointsFont = scaled(31)
        rankFont = scaled(28)
        rankBadgeFont = scaled(18.5)
        leaderboardButtonFont = scaled(22)
        profileInitialsFont = scaled(44)
        profileLabelFont = scaled(18.5)
        sectionLabelFont = scaled(19.5)
        viewAllFont = scaled(19.5)
        statTitleFont = scaled(20)
        statValueFont = scaled(23)
        statIconFont = scaled(17.5)
        achievementEmojiFont = scaled(24)
        achievementTitleFont = scaled(19)
        achievementSubtitleFont = scaled(17.5)

        heroPadding = scaled(16)
        heroCornerRadius = scaled(18)
        heroSpacing = scaled(14)
        profileButtonSpacing = scaled(6)
        heroIconTopPadding = scaled(1)
        profileButtonSize = scaled(100)
        profileTapWidth = scaled(120)
        profileTapHeight = scaled(138)
        pointsCardPadding = scaled(12)
        cardCornerRadius = scaled(16)
        innerCornerRadius = scaled(10)
        cardInnerSpacing = scaled(10)
        badgeSpacing = scaled(6)
        rankBadgeHorizontalPadding = scaled(10)
        rankBadgeVerticalPadding = scaled(6)
        leaderboardButtonVerticalPadding = scaled(12)
        statCardPadding = scaled(12)
        statIconCircle = scaled(22)
        statCardHeight = scaled(78)
        achievementCardPadding = scaled(12)
        achievementCardHeight = scaled(90)
    }
}

private struct AscentProfileAvatarView: View {
    let imageURL: URL?
    let initials: String
    let metrics: AscentMetrics

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: metrics.profileButtonSize, height: metrics.profileButtonSize)

            if let imageURL {
                CachedAsyncImage(url: imageURL, contentMode: .fill)
                    .frame(width: metrics.profileButtonSize, height: metrics.profileButtonSize)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: metrics.profileInitialsFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.36, green: 0.24, blue: 0.94))
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.40), lineWidth: 1)
        )
    }
}

private struct AscentStatCardView: View {
    let card: AscentStatCard
    let metrics: AscentMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.textTightSpacing) {
            ZStack {
                Circle()
                    .fill(card.accent.opacity(0.16))
                    .frame(width: metrics.statIconCircle, height: metrics.statIconCircle)

                Image(systemName: card.icon)
                    .font(.system(size: metrics.statIconFont, weight: .bold))
                    .foregroundStyle(card.accent)
            }

            Text(card.title)
                .font(.system(size: metrics.statTitleFont, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.41, green: 0.44, blue: 0.52))

            Text(card.value)
                .font(.system(size: metrics.statValueFont, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.21, green: 0.23, blue: 0.29))
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.statCardHeight, alignment: .leading)
        .padding(metrics.statCardPadding)
        .background(card.background)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(card.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }
}

private struct AscentAchievementCard: View {
    let achievement: AscentAchievement
    let metrics: AscentMetrics

    var body: some View {
        VStack(spacing: metrics.textTightSpacing) {
            Text(achievement.emoji)
                .font(.system(size: metrics.achievementEmojiFont))
                .grayscale(achievement.isDimmed ? 0.65 : 0.0)
                .opacity(achievement.isDimmed ? 0.75 : 1.0)

            Text(achievement.title)
                .font(.system(size: metrics.achievementTitleFont, weight: .bold, design: .rounded))
                .foregroundStyle(achievement.isDimmed ? Color(red: 0.72, green: 0.73, blue: 0.78) : Color(red: 0.24, green: 0.23, blue: 0.18))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(achievement.subtitle)
                .font(.system(size: metrics.achievementSubtitleFont, weight: .medium, design: .rounded))
                .foregroundStyle(achievement.isDimmed ? Color(red: 0.76, green: 0.77, blue: 0.82) : Color(red: 0.53, green: 0.51, blue: 0.41))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.achievementCardHeight)
        .padding(metrics.achievementCardPadding)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(achievement.accent, lineWidth: 1.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }
}

private func resolvedMediaURL(from rawURL: String?) -> URL? {
    guard let rawURL, !rawURL.isEmpty else { return nil }
    if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
        return URL(string: rawURL)
    }
    return URL(string: "\(Config.strapiBaseUrl)\(rawURL)")
}

#Preview {
    NavigationStack {
        AscentView(onShowProfile: {})
    }
}
