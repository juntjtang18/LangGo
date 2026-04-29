import SwiftUI

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

    private let leaderboardEntries: [AscentLeaderboardEntry] = [
        .init(rank: 1, name: "Sarah Chen", score: "5,234", medal: "🥇", isCurrentUser: false),
        .init(rank: 2, name: "Mike Johnson", score: "4,892", medal: "🥈", isCurrentUser: false),
        .init(rank: 3, name: "Emma Davis", score: "4,156", medal: "🥉", isCurrentUser: false),
        .init(rank: 4, name: "Alex Kim", score: "3,721", medal: nil, isCurrentUser: false),
        .init(rank: 5, name: "Lisa Wang", score: "3,298", medal: nil, isCurrentUser: false),
        .init(rank: 6, name: "David Park", score: "3,102", medal: nil, isCurrentUser: false),
        .init(rank: 7, name: "Maria Garcia", score: "2,956", medal: nil, isCurrentUser: false),
        .init(rank: 8, name: "You", score: "2,847", medal: nil, isCurrentUser: true),
        .init(rank: 9, name: "James Wilson", score: "2,734", medal: nil, isCurrentUser: false),
        .init(rank: 10, name: "Nina Patel", score: "2,621", medal: nil, isCurrentUser: false)
    ]

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
            AscentLeaderboardSheet(entries: leaderboardEntries)
        }
    }

    private func hero(metrics: AscentMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.heroSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: metrics.textTightSpacing) {
                    Text("Ascent")
                        .font(.system(size: metrics.titleFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your journey to glory")
                        .font(.system(size: metrics.subtitleFont, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer(minLength: metrics.compactSpacing)

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
                            .foregroundStyle(.white)
                    }
                    .frame(minWidth: metrics.profileTapWidth, minHeight: metrics.profileTapHeight)
                    .padding(.top, metrics.heroIconTopPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: metrics.cardInnerSpacing) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: metrics.textTightSpacing) {
                        Text("Total Points")
                            .font(.system(size: metrics.pointsLabelFont, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))

                        Text("2,847")
                            .font(.system(size: metrics.pointsFont, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: metrics.compactSpacing)

                    VStack(alignment: .trailing, spacing: metrics.badgeSpacing) {
                        Text("#8")
                            .font(.system(size: metrics.rankFont, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Up 4")
                            .font(.system(size: metrics.rankBadgeFont, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, metrics.rankBadgeHorizontalPadding)
                            .padding(.vertical, metrics.rankBadgeVerticalPadding)
                            .background(Capsule().fill(Color(red: 0.07, green: 0.70, blue: 0.29)))
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

private struct AscentLeaderboardEntry: Identifiable {
    let rank: Int
    let name: String
    let score: String
    let medal: String?
    let isCurrentUser: Bool

    var id: Int { rank }
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
        profileInitialsFont = scaled(22)
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
        heroIconTopPadding = scaled(1)
        profileButtonSpacing = scaled(6)
        profileButtonSize = scaled(50)
        profileTapWidth = scaled(78)
        profileTapHeight = scaled(74)
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

private struct AscentLeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [AscentLeaderboardEntry]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaderboard")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                        Text("1,243 learners")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.57))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
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
                            Text("Your Score")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.53, green: 0.48, blue: 0.33))

                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text("2,847")
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.22))
                                Text("+124")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.10, green: 0.67, blue: 0.30))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "medal.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.orange)
                                Text("#8")
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                            }

                            Text("Up 4 spots")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.10, green: 0.67, blue: 0.30))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color(red: 0.89, green: 1.00, blue: 0.90)))
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
                            ForEach(entries) { entry in
                                AscentLeaderboardRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .background(Color.white)
        }
    }
}

private struct AscentLeaderboardRow: View {
    let entry: AscentLeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            if let medal = entry.medal {
                Text(medal)
                    .font(.system(size: 22))
                    .frame(width: 30)
            } else {
                Text("\(entry.rank)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.45, blue: 0.53))
                    .frame(width: 30, height: 30)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.99))
                    .clipShape(Circle())
            }

            Text(entry.name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.27, green: 0.29, blue: 0.36))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.isCurrentUser ? Color.orange : Color(red: 0.63, green: 0.65, blue: 0.72))
                Text(entry.score)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.isCurrentUser ? Color(red: 0.84, green: 0.45, blue: 0.12) : Color(red: 0.33, green: 0.36, blue: 0.44))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(entry.isCurrentUser ? Color(red: 1.00, green: 0.98, blue: 0.90) : Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(entry.isCurrentUser ? Color(red: 0.95, green: 0.83, blue: 0.48) : Color.black.opacity(0.06))
                .frame(height: 1)
        }
    }
}

#Preview {
    NavigationStack {
        AscentView(onShowProfile: {})
    }
}
