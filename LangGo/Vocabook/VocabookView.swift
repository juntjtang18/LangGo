import SwiftUI
import os

struct VocabookView: View {
    @ObservedObject var flashcardViewModel: FlashcardViewModel
    @ObservedObject var vocabookViewModel: VocabookViewModel

    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.theme) var theme: Theme

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    @State private var isListening: Bool = false
    @State private var isQuizzing: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 30) {
                HeaderTitleView()

                OverallProgressView(viewModel: flashcardViewModel)
                    .padding(.horizontal)

                ConnectedActionButtons(
                    isReviewing: $isReviewing,
                    isListening: $isListening,
                    isQuizzing: $isQuizzing,
                    isAddingNewWord: $isAddingNewWord
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)

            // MODIFIED: This button now navigates directly to the last viewed page.
            if let pages = vocabookViewModel.vocabook?.vocapages, !pages.isEmpty {
                let allIDs = pages.map { $0.id }.sorted()
                let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                
                // Use last viewed ID if it's valid; otherwise, default to the first page.
                let targetPageID = (lastViewedID != 0 && allIDs.contains(lastViewedID)) ? lastViewedID : allIDs.first ?? 1

                NavigationLink(destination: VocapageHostView(
                    allVocapageIds: allIDs,
                    selectedVocapageId: targetPageID,
                    flashcardViewModel: flashcardViewModel
                )) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Open")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color(red: 0.2, green: 0.6, blue: 0.25))
                    .clipShape(Capsule())
                    .shadow(radius: 5, y: 3)
                }
                .padding([.trailing, .bottom], 20)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $isAddingNewWord) {
            NewWordInputView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isReviewing) {
            FlashcardReviewView(viewModel: flashcardViewModel)
        }
        .fullScreenCover(isPresented: $isListening) {
             ReadFlashcardView(languageSettings: languageSettings)
        }
        .sheet(isPresented: $isQuizzing) {
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
        .task {
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

private struct DiagonalConnectingShape: Shape {
    let buttonSize: CGFloat
    let cornerRadius: CGFloat
    let connectorWidthRatio: CGFloat = 0.7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topLeftRect = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        let bottomRightRect = CGRect(x: rect.width - buttonSize, y: rect.height - buttonSize, width: buttonSize, height: buttonSize)

        path.addRoundedRect(in: topLeftRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        path.addRoundedRect(in: bottomRightRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let pinchOffset = cornerRadius * (1 - connectorWidthRatio)

        path.move(to: CGPoint(x: topLeftRect.maxX - cornerRadius + pinchOffset, y: topLeftRect.maxY))
        path.addLine(to: CGPoint(x: topLeftRect.maxX, y: topLeftRect.maxY - cornerRadius + pinchOffset))
        path.addLine(to: CGPoint(x: bottomRightRect.minX + cornerRadius - pinchOffset, y: bottomRightRect.minY))
        path.addLine(to: CGPoint(x: bottomRightRect.minX, y: bottomRightRect.minY + cornerRadius - pinchOffset))
        path.closeSubpath()
        
        return path
    }
}

private struct HeaderTitleView: View {
    var body: some View {
        HStack {
            Text("My Vocabulary\nNote Book")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 20)
                .padding(.leading, 30)
                .padding(.trailing, 40)
                .background(RightRoundedRectangle(radius: 30).fill(Color(red: 0.29, green: 0.82, blue: 0.4)))
                .shadow(color: .black.opacity(0.2), radius: 5, x: 2, y: 2)
            Spacer()
        }
    }
}

private struct OverallProgressView: View {
    @ObservedObject var viewModel: FlashcardViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 20) {
            VocabookProgressCircleView(viewModel: viewModel)
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                StatRow(label: "Total Words", value: "\(viewModel.totalCardCount)")
                StatRow(label: "Remembered", value: "\(viewModel.rememberedCount)")
                StatRow(label: "Due for Review", value: "\(viewModel.dueForReviewCount)")
                StatRow(label: "New Words", value: "\(viewModel.newCardCount)")
            }
            .font(.body)
        }
        .padding()
        .background(theme.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack {
            Text(label).foregroundColor(theme.text.opacity(0.7))
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

private struct VocabookProgressCircleView: View {
    @ObservedObject var viewModel: FlashcardViewModel
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

private struct ConnectedActionButtons: View {
    @Binding var isReviewing: Bool
    @Binding var isListening: Bool
    @Binding var isQuizzing: Bool
    @Binding var isAddingNewWord: Bool

    private let buttonSize: CGFloat = 110
    private let spacing: CGFloat = 20

    var body: some View {
        ZStack {
            DiagonalConnectingShape(buttonSize: buttonSize, cornerRadius: 20)
                .fill(Color(red: 0.2, green: 0.6, blue: 0.25))
                .shadow(color: .black.opacity(0.2), radius: 5, y: 4)

            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    buttonContent(title: "Card Review", icon: "square.stack.3d.up.fill")
                        .onTapGesture { isReviewing = true }
                    
                    VocabookActionButton(title: "Listen", icon: "headphones", isDark: false) { isListening = true }
                }
                HStack(spacing: spacing) {
                    VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill", isDark: false) { isQuizzing = true }

                    buttonContent(title: "Add Word", icon: "plus.app.fill")
                        .onTapGesture { isAddingNewWord = true }
                }
            }
        }
        .frame(width: buttonSize * 2 + spacing, height: buttonSize * 2 + spacing)
    }

    @ViewBuilder
    private func buttonContent(title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.white)
        .frame(width: buttonSize, height: buttonSize)
    }
}


private struct VocabookActionButton: View {
    let title: String
    let icon: String
    let isDark: Bool
    let action: () -> Void

    private var backgroundColor: Color {
        isDark ? Color(red: 0.2, green: 0.6, blue: 0.25) : Color(red: 0.5, green: 0.8, blue: 0.5)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(.white)
            .frame(width: 110, height: 110)
            .background(backgroundColor)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 5, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// NOTE: PagesListView is no longer used in this file but is kept for the NavigationLink destination.
// In a real project, this would likely be moved to its own file.
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
