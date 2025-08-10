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
                // The HeaderTitleView is now updated to match the image exactly.
                HeaderTitleView()
                
                OverallProgressView(viewModel: flashcardViewModel)
                    .padding(.horizontal)

                ActionButtonsGrid(
                    isReviewing: $isReviewing,
                    isListening: $isListening,
                    isQuizzing: $isQuizzing,
                    isAddingNewWord: $isAddingNewWord
                )
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)

            NavigationLink(destination: PagesListView(viewModel: vocabookViewModel, flashcardViewModel: flashcardViewModel)) {
                Text("Open Book")
                    .font(.headline)
                    .padding()
                    .background(theme.accent)
                    .foregroundColor(Color.white)
                    .clipShape(Capsule())
                    .shadow(radius: 5, y: 3)
            }
            .padding()
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

// A custom shape to round only the right-side corners of a rectangle.
private struct RightRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top left (sharp corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Line to top right before the curve
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        
        // Top-right arc
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: Angle(degrees: -90),
                    endAngle: Angle(degrees: 0),
                    clockwise: false)
        
        // Line to bottom right before the curve
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))

        // Bottom-right arc
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false)
        
        // Line to bottom left (sharp corner)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        path.closeSubpath()
        return path
    }
}

// MODIFIED: HeaderTitleView now uses the custom shape and layout.
private struct HeaderTitleView: View {
    var body: some View {
        HStack {
            Text("My Vocabulary\nNote Book")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 20)
                .padding(.leading, 30)
                .padding(.trailing, 40) // More padding on the right for the curve
                .background(
                    RightRoundedRectangle(radius: 30)
                        .fill(Color(red: 0.29, green: 0.82, blue: 0.4))
                )
                .shadow(color: .black.opacity(0.2), radius: 5, x: 2, y: 2)

            // Spacer pushes the title to the left edge of the screen.
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
            Text(label)
                .foregroundColor(theme.text.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.medium)
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

private struct ActionButtonsGrid: View {
    @Binding var isReviewing: Bool
    @Binding var isListening: Bool
    @Binding var isQuizzing: Bool
    @Binding var isAddingNewWord: Bool

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 15) {
                VocabookActionButton(title: "Card Review", icon: "square.stack.3d.up.fill") { isReviewing = true }
                VocabookActionButton(title: "Listen", icon: "headphones") { isListening = true }
            }
            HStack(spacing: 15) {
                VocabookActionButton(title: "Quiz Review", icon: "checkmark.circle.fill") { isQuizzing = true }
                VocabookActionButton(title: "Add Word", icon: "plus.app.fill") { isAddingNewWord = true }
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(4)
            .background(theme.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 80)
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
                    if viewModel.isLoadingVocabooks {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let vocabook = viewModel.vocabook, let pages = vocabook.vocapages, !pages.isEmpty {
                        let sortedPages = pages.sorted(by: { $0.order < $1.order })
                        ForEach(sortedPages) { page in
                            VocabookPageRow(flashcardViewModel: flashcardViewModel, vocapage: page, allVocapageIds: sortedPages.map { $0.id })
                                .id(page.id)
                        }
                    } else {
                        Text("No vocabulary pages found. Start learning to create them!")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.loadCycle) { _ in
                logger.debug("PageListView::onChange()")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let lastViewedID = UserDefaults.standard.integer(forKey: "lastViewedVocapageID")
                    if lastViewedID != 0 {
                        withAnimation {
                            proxy.scrollTo(lastViewedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle("Vocabulary Pages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
