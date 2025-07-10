import SwiftUI
import SwiftData

struct FlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FlashcardViewModel?

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    
    var body: some View {
        NavigationStack {
            if let viewModel = viewModel {
                VStack(spacing: 30) {
                    FlashcardProgressCircleView(viewModel: viewModel)
                        .padding(.top)
                    
                    ActionButtonsView(viewModel: viewModel, isReviewing: $isReviewing, isAddingNewWord: $isAddingNewWord)
                    
                    StatisticsView(viewModel: viewModel)
                    Spacer()
                }
                .padding()
                .navigationTitle("Flashcard")
                .navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented: $isAddingNewWord) {
                    NewWordInputView(viewModel: viewModel)
                }
                // Add this fullScreenCover to present FlashcardReviewView
                .fullScreenCover(isPresented: $isReviewing) {
                    // Assuming FlashcardReviewView exists and takes these parameters
                    // Removed 'isReviewing' argument as it caused the "Extra argument" error.
                    // The dismissal of FlashcardReviewView should typically be handled internally
                    // using @Environment(\.dismiss) or a similar mechanism.
                    FlashcardReviewView(viewModel: viewModel)
                }
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
                .task {
                    await viewModel.loadStatistics()
                }
            } else {
                ProgressView()
                    .onAppear {
                        if viewModel == nil {
                            viewModel = FlashcardViewModel(modelContext: modelContext)
                        }
                    }
            }
        }
    }
}

private struct FlashcardProgressCircleView: View {
    let viewModel: FlashcardViewModel

    private var progress: Double {
        guard viewModel.totalCardCount > 0 else { return 0 }
        return Double(viewModel.rememberedCount) / Double(viewModel.totalCardCount)
    }

    var body: some View {
        ZStack {
            // This is the outer, gray stroke
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 15)
            
            // This is the inner circle that will be filled green
            Circle().fill(Color.green.opacity(0.1)) // Added this line to fill the inner circle with green

            // This is the progress arc, which remains green
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
            
            // Use NumberFormatter for locale-sensitive percentage formatting
            Text(percentageString)
                .font(.largeTitle)
                .bold()
        }
        .frame(width: 150, height: 150)
    }
    
    private var percentageString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        // Set minimum and maximum fraction digits as needed.
        // For whole percentages, use 0. If you want to show decimals, adjust these.
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        // Ensure the percentage symbol is locale-appropriate
        formatter.locale = Locale.current
        // Directly format the 'progress' (Double) value
        return formatter.string(from: NSNumber(value: progress)) ?? "\(Int(progress * 100))%"
    }
}

private struct ActionButtonsView: View {
    let viewModel: FlashcardViewModel
    @Binding var isReviewing: Bool
    @Binding var isAddingNewWord: Bool
    
    var body: some View {
        Grid {
            GridRow {
                ActionButton(icon: "w.circle.fill", text: "Add word") {
                    isAddingNewWord = true
                }
                .gridCellAnchor(.center)
                .frame(maxWidth: .infinity)

                ActionButton(icon: "play.circle.fill", text: "Start review", isLarge: true) {
                    Task {
                        await viewModel.prepareReviewSession()
                        isReviewing = true // This will now trigger the fullScreenCover
                    }
                }
                .gridCellAnchor(.center)
                .frame(maxWidth: .infinity)

                ActionButton(icon: "s.circle.fill", text: "Add sentence") { /* Add action */ }
                    .gridCellAnchor(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatisticsView: View {
    let viewModel: FlashcardViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Statistics")
                    .font(.title2).bold()
                Spacer()
                Button(action: {
                    Task {
                        await viewModel.loadStatistics()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.bottom, 10)

            StatRow(label: "Total Cards", value: "\(viewModel.totalCardCount)")
            StatRow(label: "Remembered", value: "\(viewModel.rememberedCount)")
            StatRow(label: "New Cards", value: "\(viewModel.newCardCount)")
            StatRow(label: "Warm-up cards", value: "\(viewModel.warmUpCardCount)")
            StatRow(label: "Weekly Review Cards", value: "\(viewModel.weeklyReviewCardCount)")
            StatRow(label: "Monthly Cards", value: "\(viewModel.monthlyCardCount)")
            StatRow(label: "Hard to remember", value: "\(viewModel.hardToRememberCount)")
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

private struct ActionButton: View {
    let icon: String
    let text: String
    var isLarge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(isLarge ? .system(size: 60) : .system(size: 40))
                    .foregroundColor(.teal)
                Text(text).font(.caption)
            }
        }
        .foregroundColor(.primary)
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}
