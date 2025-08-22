// LangGo/Vocabook/VocabookView.swift
import SwiftUI
import os

struct VocabookView: View {
    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @ObservedObject var vocabookViewModel: VocabookViewModel

    @EnvironmentObject var reviewSettings: ReviewSettingsManager
    @Environment(\.theme) var theme: Theme

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    // 'isListening' state is removed as the button is no longer used.
    @State private var isQuizzing: Bool = false
    @State private var isShowingSettings: Bool = false
    
    private var allFlashcards: [Flashcard] {
        vocabookViewModel.vocabook?.vocapages?.flatMap { $0.flashcards ?? [] } ?? []
    }

    private var weightedProgress: Double {
        guard !allFlashcards.isEmpty, !reviewSettings.settings.isEmpty else {
            return 0.0
        }

        let promotionBonus = 2.0
        let masteryStreak = Double(reviewSettings.masteryStreak)
        let numberOfPromotions = Double(reviewSettings.settings.count - 1)
        let maxCardScore = masteryStreak + (numberOfPromotions * promotionBonus)

        guard maxCardScore > 0 else {
            return 0.0
        }

        let totalPossiblePoints = Double(allFlashcards.count) * maxCardScore

        let currentTotalPoints = allFlashcards.reduce(0.0) { total, card in
            if card.reviewTire == "remembered" {
                return total + maxCardScore
            }

            var cardScore = Double(card.correctStreak)
            let sortedTiers = reviewSettings.settings.values.sorted { $0.min_streak < $1.min_streak }
            for tierSetting in sortedTiers where tierSetting.tier != "new" {
                 if card.correctStreak >= tierSetting.min_streak {
                    cardScore += promotionBonus
                }
            }
            return total + min(cardScore, maxCardScore)
        }
        
        return totalPossiblePoints > 0 ? currentTotalPoints / totalPossiblePoints : 0.0
    }

    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                HeaderTitleView(viewModel: vocabookViewModel)

                OverallProgressView(
                    progress: weightedProgress,
                    viewModel: vocabookViewModel
                )
                .padding(.horizontal)

                ConnectedActionButtons(
                    isReviewing: $isReviewing,
                    isQuizzing: $isQuizzing,
                    isAddingNewWord: $isAddingNewWord,
                    isShowingSettings: $isShowingSettings,
                    vocabookViewModel: vocabookViewModel,
                    flashcardViewModel: flashcardViewModel
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            Task {
                await vocabookViewModel.loadStatistics()
            }
        }
        .fullScreenCover(isPresented: $isAddingNewWord) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isReviewing, onDismiss: {
            Task {
                await vocabookViewModel.loadStatistics()
            }
        }) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        // The .fullScreenCover for 'isListening' has been removed.
        .sheet(isPresented: $isQuizzing, onDismiss: {
            Task {
                await vocabookViewModel.loadStatistics()
            }
        }) {
            if !flashcardViewModel.reviewCards.isEmpty {
                ExamView(flashcards: flashcardViewModel.reviewCards)
            } else {
                VStack(spacing: 16) {
                    Text("No Cards for Quiz")
                        .font(.title)
                    Text("Complete some lessons or add new words to get cards for your quiz.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            VocabookSettingView()
        }
        .task {
            await vocabookViewModel.loadVocabookPages()
            await vocabookViewModel.loadStatistics()
            if flashcardViewModel.reviewCards.isEmpty {
                await flashcardViewModel.prepareReviewSession()
            }
        }
    }
}

// MARK: - Components

private struct RightRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct TwoButtonConnector: Shape {
    let rect1: CGRect
    let rect2: CGRect
    let cornerRadius: CGFloat
    let connectorWidthRatio: CGFloat = 0.7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pinchOffset = cornerRadius * (1 - connectorWidthRatio)

        path.move(to: CGPoint(x: rect1.maxX - cornerRadius + pinchOffset, y: rect1.maxY))
        path.addLine(to: CGPoint(x: rect1.maxX, y: rect1.maxY - cornerRadius + pinchOffset))
        path.addLine(to: CGPoint(x: rect2.minX + cornerRadius - pinchOffset, y: rect2.minY))
        path.addLine(to: CGPoint(x: rect2.minX, y: rect2.minY + cornerRadius - pinchOffset))
        path.closeSubpath()
        
        return path
    }
}

private struct HeaderTitleView: View {
    @ObservedObject var viewModel: VocabookViewModel

    var body: some View {
        HStack {
            HStack {
                Text("My Vocabulary\nNote Book")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Spacer()

                Text("\(viewModel.totalCards)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(Color(red: 0.29, green: 0.82, blue: 0.4))
                    .frame(minWidth: 40, minHeight: 40)
                    .background(Circle().fill(Color.white))
            }
            .padding(.vertical, 20)
            .padding(.leading, 30)
            .padding(.trailing, 20)
            .background(RightRoundedRectangle(radius: 30).fill(Color(red: 0.29, green: 0.82, blue: 0.4)))
            .shadow(color: .black.opacity(0.2), radius: 5, x: 2, y: 2)
            
            Spacer()
        }
    }
}

private struct OverallProgressView: View {
    let progress: Double
    @ObservedObject var viewModel: VocabookViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 16) {
            VocabookProgressCircleView(progress: progress)
                .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 8) {
                StatRow(label: "Remembered",       value: "\(viewModel.rememberedCount)")
                StatRow(label: "Reviewed (Not Due)", value: "\(viewModel.reviewedCount)")
                StatRow(label: "Due for Review",   value: "\(viewModel.dueForReviewCount)")
            }
            // Ensure the text column is allowed to grow and not collapse
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(theme.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}

// Keep StatRow, but make its label resilient to compression:
private struct StatRow: View {
    let label: String
    let value: String
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(theme.text.opacity(0.7))
                .lineLimit(1)                 // don't wrap vertically
                .minimumScaleFactor(0.85)     // shrink slightly if tight
                .layoutPriority(1)            // protect from being compressed to 1-char width
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
// MARK: - Quick stats (New + Hard to Remember)
private struct QuickStatsView: View {
    @ObservedObject var viewModel: VocabookViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Stats")
                .font(.headline)
            StatRow(label: "New", value: "\(viewModel.newCardCount)")
            StatRow(label: "Hard to Remember", value: "\(viewModel.hardToRememberCount)")
        }
        .padding()
        .background(theme.secondary.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Tier breakdown (data-driven)
private struct TierBreakdownView: View {
    @ObservedObject var viewModel: VocabookViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tier Breakdown").font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.loadStatistics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("Refresh statistics")
            }

            if viewModel.tierStats.isEmpty {
                Text("No tier data yet.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.tierStats) { tier in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.displayName ?? tier.tier.capitalized)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                if tier.dueCount > 0 {
                                    Label("\(tier.dueCount) due",
                                          systemImage: "clock.badge.exclamationmark")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text("Streak \(tier.min_streak)–\(tier.max_streak)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(tier.count)")
                            .font(.headline)
                    }
                    .padding(.vertical, 6)

                    if tier.id != viewModel.tierStats.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
        .padding()
        .background(theme.secondary.opacity(0.08))
        .cornerRadius(12)
    }
}
private struct VocabookProgressCircleView: View {
    let progress: Double
    @Environment(\.theme) var theme: Theme

    private var percentageString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: progress)) ?? "\(Int(progress * 100))%"
    }

    var body: some View {
        ZStack {
            Circle().stroke(theme.secondary.opacity(0.3), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
            Text(percentageString)
                .font(.title2)
                .bold()
                .foregroundColor(theme.text)
        }
    }
}

private struct ConnectedActionButtons: View {
    @Binding var isReviewing: Bool
    @Binding var isQuizzing: Bool
    @Binding var isAddingNewWord: Bool
    @Binding var isShowingSettings: Bool

    @ObservedObject var vocabookViewModel: VocabookViewModel
    @ObservedObject var flashcardViewModel: FlashcardViewModel

    private let buttonSize: CGFloat = 110
    private let spacing: CGFloat = 15
    private let cornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            let primaryColor = Color(red: 0.2, green: 0.6, blue: 0.25)
            let secondaryColor = Color(red: 0.5, green: 0.8, blue: 0.5)
            
            // The CGRects for the connectors remain the same, as they map to the original grid positions.
            let rect1_CardReview = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
            let rect2_ListenSpot = CGRect(x: buttonSize + spacing, y: 0, width: buttonSize, height: buttonSize) // Now the "Open" button
            let rect5_AddWord = CGRect(x: buttonSize + spacing, y: buttonSize + spacing, width: buttonSize, height: buttonSize)
            let rect6_OpenSpot = CGRect(x: (buttonSize + spacing) * 2, y: buttonSize + spacing, width: buttonSize, height: buttonSize) // Now the "Setting" button
            
            // This connector links "Card Review" (top-left) to "Add Word" (bottom-middle).
            TwoButtonConnector(rect1: rect1_CardReview, rect2: rect5_AddWord, cornerRadius: cornerRadius)
                .fill(primaryColor)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 4)
            
            // This connector links the new "Open" button (top-middle) to the new "Setting" button (bottom-right).
            TwoButtonConnector(rect1: rect2_ListenSpot, rect2: rect6_OpenSpot, cornerRadius: cornerRadius)
                .fill(secondaryColor)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 4)

            VStack(alignment: .leading, spacing: spacing) {
                // --- MODIFICATION: Top row now has two buttons ---
                HStack(spacing: spacing) {
                    VocabookActionButton(title: "Card Review", icon: "square.stack.3d.up.fill", style: .vocabookActionPrimary) {
                        Task {
                            await flashcardViewModel.prepareReviewSession()
                            isReviewing = true
                        }
                    }

                    // "Listen" is replaced with "Open"
                    if let pages = vocabookViewModel.vocabook?.vocapages, !pages.isEmpty {
                        let allIDs = pages.map { $0.id }.sorted()
                        let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                        let targetPageID = (lastViewedID != 0 && allIDs.contains(lastViewedID)) ? lastViewedID : allIDs.first ?? 1

                        NavigationLink(destination: VocapageHostView(
                            allVocapageIds: allIDs,
                            selectedVocapageId: targetPageID,
                            flashcardViewModel: flashcardViewModel
                        )) {
                            VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary)
                        }
                    } else {
                        VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary)
                            .opacity(0.5)
                    }
                    
                    // The original "Setting" button is removed.
                }

                // --- MODIFICATION: Bottom row now has the new "Setting" button ---
                HStack(spacing: spacing) {
                    VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill", style: .vocabookActionSecondary) {
                        Task {
                            await flashcardViewModel.prepareReviewSession()
                            isQuizzing = true
                        }
                    }

                    VocabookActionButton(title: "Add Word", icon: "plus.app.fill", style: .vocabookActionPrimary) { isAddingNewWord = true }

                    // The original "Open" button is replaced with "Setting".
                    VocabookActionButton(title: "Setting", icon: "gear", style: .vocabookActionSecondary) { isShowingSettings = true }
                }
            }
        }
        .frame(width: buttonSize * 3 + spacing * 2, height: buttonSize * 2 + spacing)
    }
}

private struct VocabookButtonLabel: View {
    let title: String
    let icon: String
    let style: ViewStyle

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .style(style)
    }
}

private struct VocabookActionButton: View {
    let title: String
    let icon: String
    let style: ViewStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VocabookButtonLabel(title: title, icon: icon, style: style)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PagesListView: View {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "PagesListView")
    @ObservedObject var viewModel: VocabookViewModel
    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isLoadingVocabooks { ProgressView().frame(maxWidth: .infinity) }
                    else if let vocabook = viewModel.vocabook, let pages = vocabook.vocapages, !pages.isEmpty {
                        let sortedPages = pages.sorted(by: { $0.order < $1.order })
                        ForEach(sortedPages) { page in
                            VocabookPageRow(flashcardViewModel: flashcardViewModel, vocapage: page, allVocapageIds: sortedPages.map { $0.id })
                                .id(page.id)
                        }
                    } else {
                        Text("No vocabulary pages found. Start learning to create them!")
                            .font(.caption).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.loadCycle) { _ in
                logger.debug("PageListView::onChange()")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                    if lastViewedID != 0 {
                        withAnimation { proxy.scrollTo(lastViewedID, anchor: .center) }
                    }
                }
            }
        }
        .navigationTitle("Vocabulary Pages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
