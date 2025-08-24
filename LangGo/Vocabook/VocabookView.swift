// LangGo/Vocabook/VocabookView.swift
import SwiftUI
import os
import SPConfetti

struct VocabookView: View {
    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @ObservedObject var vocabookViewModel: VocabookViewModel

    @EnvironmentObject var reviewSettings: ReviewSettingsManager
    @Environment(\.theme) var theme: Theme

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    @State private var isQuizzing: Bool = false
    @State private var isShowingSettings: Bool = false
    
    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly: Bool = false
    
    @State private var badgeAnchor: Anchor<CGPoint>? = nil
    @State private var flightTrigger: Int = 0
    
    @State private var isFlyingStar: Bool = false
    @State private var starProgress: CGFloat = 0
    @State private var bezier: (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint)? = nil

    
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
                    isShowingDueWordsOnly: $isShowingDueWordsOnly,
                    vocabookViewModel: vocabookViewModel,
                    flashcardViewModel: flashcardViewModel,
                    onFilterChange: {
                        Task {
                            await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
                        }
                    }
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
        .overlay {
            if vocabookViewModel.isLoadingVocabooks || (vocabookViewModel.vocabook?.vocapages == nil) {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .scaleEffect(1.4)
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .onPreferenceChange(BadgePositionPreferenceKey.self) { anchor in
            self.badgeAnchor = anchor
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewCelebrationClosed)) { _ in
            flightTrigger &+= 1
        }
        .background(theme.background.ignoresSafeArea())
        .overlay {
            GeometryReader { proxy in
                ZStack {
                    if isFlyingStar, let b = bezier {
                        Image(systemName: "star.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.yellow)
                            .shadow(color: .orange.opacity(0.5), radius: 6)
                            .modifier(BezierFlight(t: starProgress, p0: b.p0, p1: b.p1, p2: b.p2, p3: b.p3))
                            .transition(.opacity)
                    }
                }
                .onChange(of: flightTrigger) { _ in
                    guard let anchor = badgeAnchor else { return }
                    let screenBounds = UIScreen.main.bounds
                    let screenCenterGlobal = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
                    let containerFrameGlobal = proxy.frame(in: .global)
                    let start = CGPoint(x: screenCenterGlobal.x - containerFrameGlobal.minX, y: screenCenterGlobal.y - containerFrameGlobal.minY)
                    let end = proxy[anchor]
                    let bendX = -min(proxy.size.width, proxy.size.height) * 0.25
                    let dy = end.y - start.y
                    let lift = max(24, abs(dy) * 0.15)
                    let c1 = CGPoint(x: start.x + bendX, y: start.y - lift)
                    let c2 = CGPoint(x: end.x   + bendX, y: end.y   + lift)
                    bezier = (p0: start, p1: c1, p2: c2, p3: end)
                    isFlyingStar = true
                    starProgress = 0
                    withAnimation(.easeInOut(duration: 0.95)) { starProgress = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { SPConfetti.startAnimating(.fullWidthToDown, particles: [.star], duration: 0.6) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { isFlyingStar = false }
                }
            }
        }
        .fullScreenCover(isPresented: $isAddingNewWord) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isReviewing, onDismiss: {
            Task {
                await vocabookViewModel.loadStatistics()
                await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
            }
        }) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        .sheet(isPresented: $isQuizzing, onDismiss: {
            Task {
                await vocabookViewModel.loadStatistics()
                await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
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
            await vocabookViewModel.loadVocabookPages(dueOnly: isShowingDueWordsOnly)
            await vocabookViewModel.loadStatistics()
            if flashcardViewModel.reviewCards.isEmpty {
                await flashcardViewModel.prepareReviewSession()
            }
        }
    }
    
    private var allFlashcards: [Flashcard] {
        vocabookViewModel.vocabook?.vocapages?.flatMap { $0.flashcards ?? [] } ?? []
    }

    private var weightedProgress: Double {
        guard !allFlashcards.isEmpty, !reviewSettings.settings.isEmpty else { return 0.0 }
        let promotionBonus = 2.0
        let masteryStreak = Double(reviewSettings.masteryStreak)
        let numberOfPromotions = Double(reviewSettings.settings.count - 1)
        let maxCardScore = masteryStreak + (numberOfPromotions * promotionBonus)
        guard maxCardScore > 0 else { return 0.0 }
        let totalPossiblePoints = Double(allFlashcards.count) * maxCardScore
        let currentTotalPoints = allFlashcards.reduce(0.0) { total, card in
            if card.reviewTire == "remembered" { return total + maxCardScore }
            var cardScore = Double(card.correctStreak)
            let sortedTiers = reviewSettings.settings.values.sorted { $0.min_streak < $1.min_streak }
            for tierSetting in sortedTiers where tierSetting.tier != "new" {
                 if card.correctStreak >= tierSetting.min_streak { cardScore += promotionBonus }
            }
            return total + min(cardScore, maxCardScore)
        }
        return totalPossiblePoints > 0 ? currentTotalPoints / totalPossiblePoints : 0.0
    }
    
    private var isInitialLoading: Bool {
        vocabookViewModel.isLoadingVocabooks || (vocabookViewModel.vocabook?.vocapages == nil)
    }

    private struct ConnectedActionButtons: View {
        @Binding var isReviewing: Bool
        @Binding var isQuizzing: Bool
        @Binding var isAddingNewWord: Bool
        @Binding var isShowingSettings: Bool
        @Binding var isShowingDueWordsOnly: Bool

        @ObservedObject var vocabookViewModel: VocabookViewModel
        @ObservedObject var flashcardViewModel: FlashcardViewModel
        
        let onFilterChange: () -> Void

        private let buttonSize: CGFloat = 110
        private let spacing: CGFloat = 15
        private let cornerRadius: CGFloat = 20

        var body: some View {
            ZStack {
                let primaryColor = Color(red: 0.2, green: 0.6, blue: 0.25)
                let secondaryColor = Color(red: 0.5, green: 0.8, blue: 0.5)
                let rect1_CardReview = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
                let rect2_ListenSpot = CGRect(x: buttonSize + spacing, y: 0, width: buttonSize, height: buttonSize)
                let rect5_AddWord = CGRect(x: buttonSize + spacing, y: buttonSize + spacing, width: buttonSize, height: buttonSize)
                let rect6_OpenSpot = CGRect(x: (buttonSize + spacing) * 2, y: buttonSize + spacing, width: buttonSize, height: buttonSize)
                
                TwoButtonConnector(rect1: rect1_CardReview, rect2: rect5_AddWord, cornerRadius: cornerRadius).fill(primaryColor).shadow(color: .black.opacity(0.2), radius: 5, y: 4)
                TwoButtonConnector(rect1: rect2_ListenSpot, rect2: rect6_OpenSpot, cornerRadius: cornerRadius).fill(secondaryColor).shadow(color: .black.opacity(0.2), radius: 5, y: 4)

                VStack(alignment: .leading, spacing: spacing) {
                    HStack(spacing: spacing) {
                        VocabookActionButton(title: "Card Review", icon: "square.stack.3d.up.fill", style: .vocabookActionPrimary) {
                            Task {
                                await flashcardViewModel.prepareReviewSession()
                                isReviewing = true
                            }
                        }
                        if let pages = vocabookViewModel.vocabook?.vocapages, !pages.isEmpty {
                            let allIDs = pages.map { $0.id }.sorted()
                            let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                            let targetPageID = (lastViewedID != 0 && allIDs.contains(lastViewedID)) ? lastViewedID : allIDs.first ?? 1
                            NavigationLink(destination: VocapageHostView(
                                allVocapageIds: allIDs,
                                selectedVocapageId: targetPageID,
                                flashcardViewModel: flashcardViewModel,
                                isShowingDueWordsOnly: $isShowingDueWordsOnly,
                                onFilterChange: onFilterChange
                            )) {
                                VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary)
                            }
                        } else {
                            VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary).opacity(0.5)
                        }
                    }
                    HStack(spacing: spacing) {
                        VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill", style: .vocabookActionSecondary) {
                            Task {
                                await flashcardViewModel.prepareReviewSession()
                                isQuizzing = true
                            }
                        }
                        VocabookActionButton(title: "Add Word", icon: "plus.app.fill", style: .vocabookActionPrimary) { isAddingNewWord = true }
                        VocabookActionButton(title: "Setting", icon: "gear", style: .vocabookActionSecondary) { isShowingSettings = true }
                    }
                }
            }
            .frame(width: buttonSize * 3 + spacing * 2, height: buttonSize * 2 + spacing)
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

                ZStack {
                    Circle().fill(Color.white)
                    Text("\(viewModel.totalCards)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(Color(red: 0.29, green: 0.82, blue: 0.4))
                }
                .frame(width: 40, height: 40)
                .anchorPreference(key: BadgePositionPreferenceKey.self, value: .center) { $0 }
                /*
                Text("\(viewModel.totalCards)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(Color(red: 0.29, green: 0.82, blue: 0.4))
                    .frame(minWidth: 40, minHeight: 40)
                    .background(Circle().fill(Color.white))
                 */
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
// MARK: - Overall progress (shift text right; tight gap; right-aligned numbers)
private struct OverallProgressView: View {
    let progress: Double
    @ObservedObject var viewModel: VocabookViewModel
    @Environment(\.theme) var theme: Theme

    private var isCompactPhone: Bool { UIScreen.main.bounds.height <= 667 }
    private var rightColumnMaxWidth: CGFloat { isCompactPhone ? 230 : 300 } // cap so gap never grows too wide

    private var tiersHighToLow: [StrapiTierStat] {
        viewModel.tierStats.sorted { $0.min_streak > $1.min_streak }
    }

    var body: some View {
        HStack(spacing: isCompactPhone ? 12 : 16) {
            // Left: circle, protected from squeezing
            VocabookProgressCircleView(progress: progress)
                .frame(width: isCompactPhone ? 84 : 100,
                       height: isCompactPhone ? 84 : 100)
                .layoutPriority(1)

            // Right: shifted a bit to the right; tight internal spacing; values right-aligned
            VStack(alignment: .leading, spacing: isCompactPhone ? 3 : 6) {
                StatRowTight(label: "Total Words", value: "\(viewModel.totalCards)")

                ForEach(tiersHighToLow, id: \.id) { t in
                    StatRowTight(label: t.displayName ?? t.tier.capitalized,
                                 value: "\(t.count)")
                }

                StatRowTight(label: "Due for Review", value: "\(viewModel.dueForReviewCount)")
            }
            .font(isCompactPhone ? .footnote : .subheadline)
            .padding(.leading, isCompactPhone ? 4 : 6)          // ← move the text block a little to the right
            .frame(maxWidth: rightColumnMaxWidth, alignment: .leading) // ← cap width so label–value gap stays small
        }
        .padding(isCompactPhone ? 10 : 16)
        .background(theme.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}


private struct StatRowTight: View {
    let label: String
    let value: String
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {   // ← tight base spacing
            Text(label)
                .foregroundColor(theme.text.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)

            Spacer(minLength: 6)                               // ← minimal gap, expands only within capped width

            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(alignment: .trailing)                   // ← right-aligned within the row
        }
        .frame(maxWidth: .infinity, alignment: .leading)       // rows fill the right column width, values align
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

/*
// MARK: - Components
private struct ConnectedActionButtons: View {
    @Binding var isReviewing: Bool
    @Binding var isQuizzing: Bool
    @Binding var isAddingNewWord: Bool
    @Binding var isShowingSettings: Bool
    @Binding var isShowingDueWordsOnly: Bool

    @ObservedObject var vocabookViewModel: VocabookViewModel
    @ObservedObject var flashcardViewModel: FlashcardViewModel

    private let buttonSize: CGFloat = 110
    private let spacing: CGFloat = 15
    private let cornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            // ... (ZStack content remains the same)

            VStack(alignment: .leading, spacing: spacing) {
                HStack(spacing: spacing) {
                    VocabookActionButton(title: "Card Review", icon: "square.stack.3d.up.fill", style: .vocabookActionPrimary) {
                        Task {
                            await flashcardViewModel.prepareReviewSession()
                            isReviewing = true
                        }
                    }

                    if let pages = vocabookViewModel.vocabook?.vocapages, !pages.isEmpty {
                        let allIDs = pages.map { $0.id }.sorted()
                        let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                        let targetPageID = (lastViewedID != 0 && allIDs.contains(lastViewedID)) ? lastViewedID : allIDs.first ?? 1

                        NavigationLink(destination: VocapageHostView(
                            allVocapageIds: allIDs,
                            selectedVocapageId: targetPageID,
                            flashcardViewModel: flashcardViewModel,
                            isShowingDueWordsOnly: $isShowingDueWordsOnly
                        )) {
                            VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary)
                        }
                    } else {
                        VocabookButtonLabel(title: "Open", icon: "book.fill", style: .vocabookActionSecondary)
                            .opacity(0.5)
                    }
                }
                HStack(spacing: spacing) {
                    VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill", style: .vocabookActionSecondary) {
                        Task {
                            await flashcardViewModel.prepareReviewSession()
                            isQuizzing = true
                        }
                    }
                    VocabookActionButton(title: "Add Word", icon: "plus.app.fill", style: .vocabookActionPrimary) { isAddingNewWord = true }
                    VocabookActionButton(title: "Setting", icon: "gear", style: .vocabookActionSecondary) { isShowingSettings = true }
                }
            }
        }
        .frame(width: buttonSize * 3 + spacing * 2, height: buttonSize * 2 + spacing)
    }
}
*/

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



private struct BezierFlight: AnimatableModifier {
    var t: CGFloat
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    private func point(at t: CGFloat) -> CGPoint {
        let u  = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        var p = CGPoint.zero
        p.x = uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x
        p.y = uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        return p
    }

    func body(content: Content) -> some View {
        let pos = point(at: t)
        content.position(pos)
    }
}

