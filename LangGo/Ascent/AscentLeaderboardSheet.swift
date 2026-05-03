import SwiftUI

@MainActor
final class AscentLeaderboardViewModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let rank: Int
        let name: String
        let score: String
        let medal: String?
        let isCurrentUser: Bool

        var id: Int { rank }
    }

    @Published private(set) var totalPeriodPointsText = "0"
    @Published private(set) var periodPointsAddText = "+0"
    @Published private(set) var groupOrderText = "#-"
    @Published private(set) var groupRankTitleText = "-"
    @Published private(set) var entries: [Entry] = []

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
        async let snapshotTask = userSnapshotService.refreshUserSnapshot(locale: currentLocale())
        async let leaderboardTask = rankService.fetchMyLeaderboard()

        let snapshot = try? await snapshotTask
        let leaderboard = try? await leaderboardTask

        apply(snapshot: snapshot, leaderboard: leaderboard)
    }

    private func apply(snapshot: UserRankSnapshot?, leaderboard: MyLeaderboardData?) {
        totalPeriodPointsText = formatNumber(snapshot?.period_points ?? 0)
        periodPointsAddText = formatDelta(snapshot?.period_points_change ?? 0)
        groupRankTitleText = trimmed(snapshot?.group_rank_title) ?? "-"

        if let currentMember = leaderboard?.members.first(where: { $0.isCurrentUser }) {
            groupOrderText = "#\(currentMember.order_in_group)"
        } else {
            groupOrderText = "#-"
        }

        entries = (leaderboard?.members ?? []).map { member in
            Entry(
                rank: member.order_in_group,
                name: member.isCurrentUser ? "You" : member.username,
                score: formatNumber(member.period_points),
                medal: medal(for: member.order_in_group),
                isCurrentUser: member.isCurrentUser
            )
        }
    }

    private func medal(for rank: Int) -> String? {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
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

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func currentLocale() -> String {
        localeProvider()
    }
}

struct AscentLeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AscentLeaderboardViewModel

    @MainActor
    init(viewModel: AscentLeaderboardViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AscentLeaderboardViewModel())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaderboard")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
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
                                Text(viewModel.totalPeriodPointsText)
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.22))
                                Text(viewModel.periodPointsAddText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.10, green: 0.67, blue: 0.30))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            
                            Text(viewModel.groupRankTitleText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.10, green: 0.67, blue: 0.30))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color(red: 0.89, green: 1.00, blue: 0.90)))
                             
                            HStack(spacing: 6) {
                                Image(systemName: "medal.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.orange)
                                Text(viewModel.groupOrderText)
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.23))
                            }

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
                            ForEach(viewModel.entries) { entry in
                                AscentLeaderboardRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .background(Color.white)
        }
        .task {
            await viewModel.load()
        }
    }
}

private struct AscentLeaderboardRow: View {
    let entry: AscentLeaderboardViewModel.Entry

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
