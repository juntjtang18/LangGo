//
//  VocabookPageRow.swift
//  LangGo
//
//  Created by James Tang on 2025/8/1.
//
import SwiftUI
import os

@MainActor
struct VocabookPageRow: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @Environment(\.theme) var theme: Theme
    @EnvironmentObject var reviewSettings: ReviewSettingsManager

    @ObservedObject var flashcardViewModel: FlashcardViewModel
    let vocapage: Vocapage
    let allVocapageIds: [Int]

    // Create a logger instance for cleaner logs
    private let logger = Logger(subsystem: "com.yourapp.langgo", category: "VocabookPageRow")

    private var weightedProgress: WeightedProgress {
        // --- START OF THE FIX ---
        // Log the state *before* the guard statement to see why it might be failing.
        let cardCount = vocapage.flashcards?.count ?? 0
        logger.log("Checking weightedProgress for vocapage \(self.vocapage.order). Flashcard count: \(cardCount), Review settings empty: \(self.reviewSettings.settings.isEmpty)")

        guard let cards = vocapage.flashcards, !cards.isEmpty, !reviewSettings.settings.isEmpty else {
            // Also log when the guard fails
            logger.log("Guard failed for vocapage \(self.vocapage.order). Returning zero progress.")
            return WeightedProgress(progress: 0.0, isComplete: false)
        }
        // --- END OF THE FIX ---

        // Log the desired flashcard details only when the guard passes.
        let cardDetails = cards.map { "frontContent: \($0.frontContent), correctStreak: \($0.correctStreak), reviewTire: \($0.reviewTire)" }
        logger.log("Flashcards for vocapage \(self.vocapage.order): \(cardDetails)")

        let promotionBonus = 2.0
        let masteryStreak = Double(reviewSettings.masteryStreak)
        let numberOfPromotions = Double(reviewSettings.settings.count - 1)
        let maxCardScore = masteryStreak + (numberOfPromotions * promotionBonus)

        guard maxCardScore > 0 else {
            return WeightedProgress(progress: 0.0, isComplete: false)
        }

        let totalPossiblePoints = Double(cards.count) * maxCardScore

        let currentTotalPoints = cards.reduce(0.0) { total, card in
            if card.reviewTire == "remembered" {
                return total + maxCardScore
            }

            var cardScore = Double(card.correctStreak)
            for (tierName, tierSetting) in reviewSettings.settings where tierName != "new" {
                if card.correctStreak >= tierSetting.min_streak {
                    cardScore += Double(promotionBonus)
                }
            }
            return total + min(cardScore, maxCardScore)
        }

        let finalProgress = totalPossiblePoints > 0 ? currentTotalPoints / totalPossiblePoints : 0.0
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
            strapiService: appEnvironment.strapiService,
            flashcardViewModel: flashcardViewModel
        )) {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(vocapage.order)")
                        .font(.body)
                        .fontWeight(.bold)
                    Text(getRelativeDate(from: vocapage.flashcards?.first?.lastReviewedAt))
                        .font(.caption)
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
                .foregroundColor(progressColor)
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)
            Text(progressString)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(theme.text)
        }
    }
}
