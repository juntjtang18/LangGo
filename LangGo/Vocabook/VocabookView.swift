// LangGo/MyVocabookView.swift
import SwiftUI
import os

struct VocabookView: View {
    let flashcardViewModel: FlashcardViewModel
    let vocabookViewModel: VocabookViewModel
    
    @EnvironmentObject var appEnvironment: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.theme) var theme: Theme

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    @State private var isListening: Bool = false
    @State private var isQuizzing: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // This top part is now fixed and does not scroll
            OverallProgressView(viewModel: flashcardViewModel)
                .padding(.horizontal)

            ActionButtonsGrid(
                isReviewing: $isReviewing,
                isListening: $isListening,
                isQuizzing: $isQuizzing,
                isAddingNewWord: $isAddingNewWord
            )
            .padding(.horizontal)

            // This list view now handles its own scrolling
            PagesListView(viewModel: vocabookViewModel, flashcardViewModel: flashcardViewModel)
        }
        .padding(.top)
        .background(theme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $isAddingNewWord) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isReviewing) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isListening) {
             ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings, strapiService: appEnvironment.strapiService)
        }
        .sheet(isPresented: $isQuizzing) {
            if !flashcardViewModel.reviewCards.isEmpty {
                ExamView(flashcards: flashcardViewModel.reviewCards, strapiService: appEnvironment.strapiService)
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
        .task {
            if flashcardViewModel.reviewCards.isEmpty {
                await flashcardViewModel.prepareReviewSession()
            }
        }
    }
}

// MARK: - Components

private struct OverallProgressView: View {
    let viewModel: FlashcardViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 20) {
            VocabookProgressCircleView(viewModel: viewModel)
                .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 8) {
                StatRow(label: "Total Words", value: "\(viewModel.totalCardCount)")
                StatRow(label: "Remembered", value: "\(viewModel.rememberedCount)")
                StatRow(label: "In Progress", value: "\(viewModel.inProgressCount)")
                StatRow(label: "New Words", value: "\(viewModel.newCardCount)")
            }
            .style(.body)
        }
        .padding()
        .background(theme.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}

private struct VocabookProgressCircleView: View {
    let viewModel: FlashcardViewModel
    @Environment(\.theme) var theme: Theme

    private var progress: Double {
        guard viewModel.totalCardCount > 0 else { return 0 }
        return Double(viewModel.rememberedCount) / Double(viewModel.totalCardCount)
    }

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

private struct ActionButtonsGrid: View {
    @Binding var isReviewing: Bool
    @Binding var isListening: Bool
    @Binding var isQuizzing: Bool
    @Binding var isAddingNewWord: Bool

    var body: some View {
        HStack(spacing: 12) {
            VocabookActionButton(title: "Flashcard Review", icon: "square.stack.3d.up.fill") { isReviewing = true }
            VocabookActionButton(title: "Listen", icon: "headphones") { isListening = true }
            VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill") { isQuizzing = true }
            VocabookActionButton(title: "Add Word", icon: "plus.app.fill") { isAddingNewWord = true }
        }
    }
}

private struct VocabookActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.accent)
                Text(title)
                    .font(.caption)
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(4)
            .background(theme.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PagesListView: View {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "PagesListView")
    let viewModel: VocabookViewModel
    let flashcardViewModel: FlashcardViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        // The ScrollViewReader provides the 'proxy' to its content.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isLoadingVocabooks {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let vocabook = viewModel.vocabook, let pages = vocabook.vocapages, !pages.isEmpty {
                        let sortedPages = pages.sorted(by: { $0.order < $1.order })
                        ForEach(sortedPages) { page in
                            VocabookPageRow(flashcardViewModel: flashcardViewModel, vocapage: page, allVocapageIds: sortedPages.map { $0.id })
                                .id(page.id) // Ensure each row has an ID
                        }
                    } else {
                        Text("No vocabulary pages found. Start learning to create them!")
                            .style(.caption)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            // THIS IS THE CORRECT PLACEMENT
            // The .onChange modifier is now on the ScrollView, inside the reader's scope.
            .onChange(of: viewModel.loadCycle) {
                // Use a tiny delay to ensure views are rendered before scrolling
                logger.debug("PageListView::onChange()")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                    if lastViewedID != 0 {
                        withAnimation {
                            // The 'proxy' is now correctly found and used here
                            proxy.scrollTo(lastViewedID, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private struct VocabookPageRow: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) var theme: Theme
    @EnvironmentObject var reviewSettings: ReviewSettingsManager
    
    let flashcardViewModel: FlashcardViewModel
    let vocapage: Vocapage
    let allVocapageIds: [Int]

    private var weightedProgress: WeightedProgress {
        guard let cards = vocapage.flashcards, !cards.isEmpty, !reviewSettings.settings.isEmpty else {
            return WeightedProgress(progress: 0.0, isComplete: false)
        }

        let promotionBonus = 2.0
        let masteryStreak = Double(reviewSettings.masteryStreak)
        let numberOfPromotions = Double(reviewSettings.settings.count - 1)
        let maxCardScore = masteryStreak + (numberOfPromotions * promotionBonus)
        
        guard maxCardScore > 0 else {
            return WeightedProgress(progress: 0.0, isComplete: false)
        }

        let totalPossiblePoints = Double(cards.count) * maxCardScore
        
        let currentTotalPoints = cards.reduce(0.0) { total, card in
            // --- THIS IS THE FIX ---
            // If the card's tier is explicitly "remembered", it gets full points.
            // This is the primary source of truth for mastery.
            if card.reviewTire == "remembered" {
                return total + maxCardScore
            }

            var cardScore = Double(card.correctStreak)
            // Add bonus points for each tier achieved
            for (tierName, tierSetting) in reviewSettings.settings where tierName != "new" {
                if card.correctStreak >= tierSetting.min_streak {
                    cardScore += Double(promotionBonus)
                }
            }
            // The score for a single card cannot exceed the maximum possible score.
            return total + min(cardScore, maxCardScore)
        }
        
        let finalProgress = totalPossiblePoints > 0 ? currentTotalPoints / totalPossiblePoints : 0.0
        // Ensure that floating point inaccuracies don't prevent completion
        let isComplete = finalProgress >= 0.999
        return WeightedProgress(progress: finalProgress, isComplete: isComplete)
    }

    private func getRelativeDate(from date: Date?) -> String {
        guard let date = date else { return "Not reviewed yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Reviewed \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        NavigationLink(destination: VocapageHostView(
            allVocapageIds: allVocapageIds,
            selectedVocapageId: vocapage.id,
            modelContext: modelContext,
            strapiService: appEnvironment.strapiService,
            flashcardViewModel: flashcardViewModel
        )) {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(vocapage.order)")
                        .style(.body)
                        .fontWeight(.bold)
                    Text(getRelativeDate(from: vocapage.flashcards?.first?.lastReviewedAt))
                        .style(.caption)
                }
                Spacer()
                
                let progress = weightedProgress
                if progress.isComplete {
                    Image(systemName: "medal.fill")
                        .font(.largeTitle)
                        .foregroundColor(theme.progressComplete)
                } else {
                    PageProgressCircle(progress: progress.progress)
                        .frame(width: 44, height: 44)
                }
            }
            .padding()
            .background(theme.primary.opacity(0.2))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        // ADD THIS GESTURE MODIFIER
        .simultaneousGesture(TapGesture().onEnded {
            UserDefaults.standard.set(vocapage.id, forKey: "lastViewedVocapageID")
        })

    }
}

private struct PageProgressCircle: View {
    let progress: Double
    @Environment(\.theme) var theme: Theme
    
    private var progressString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter.string(from: NSNumber(value: progress)) ?? "0%"
    }

    private var progressColor: Color {
        if progress < 0.25 { return theme.progressLow }
        if progress < 0.50 { return theme.progressMedium }
        if progress < 1.0 { return theme.progressHigh }
        return theme.progressComplete
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.secondary.opacity(0.3), lineWidth: 5)
            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 5.0, lineCap: .round))
                .foregroundColor(progressColor) // Use the tier-specific color
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)
            Text(progressString)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(theme.text)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(theme.text.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
