import SwiftUI
import SwiftData

struct FlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var viewModel: FlashcardViewModel?

    @State private var isReviewing = false

    var body: some View {
        NavigationStack {
            if let viewModel = viewModel {
                // --- If ViewModel is ready, show the main UI ---
                VStack(spacing: 30) {
                    // Progress Circle
                    FlashcardProgressCircleView(viewModel: viewModel)
                        .padding(.top)

                    // Action Buttons
                    ActionButtonsView(viewModel: viewModel, isReviewing: $isReviewing)

                    // Statistics
                    StatisticsView(viewModel: viewModel)
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Flashcard")
                .navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented: $isReviewing) {
                    FlashcardReviewView(viewModel: viewModel)
                }
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
            } else {
                // --- If ViewModel is not ready, show a loading indicator ---
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

// MARK: - Subviews for Readability

private struct FlashcardProgressCircleView: View {
    let viewModel: FlashcardViewModel

    private var progress: Double {
        guard viewModel.totalCardCount > 0 else { return 0 }
        return Double(viewModel.rememberedCount) / Double(viewModel.totalCardCount)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 15)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.largeTitle)
                .bold()
        }
        .frame(width: 150, height: 150)
    }
}

private struct ActionButtonsView: View {
    let viewModel: FlashcardViewModel
    @Binding var isReviewing: Bool

    var body: some View {
        HStack(spacing: 30) {
            ActionButton(icon: "w.circle.fill", text: "Add word") { /* Add action */ }
            ActionButton(icon: "play.circle.fill", text: "Start review", isLarge: true) {
                viewModel.startReview()
                if !viewModel.reviewCards.isEmpty {
                    isReviewing = true
                }
            }
            ActionButton(icon: "s.circle.fill", text: "Add sentence") { /* Add action */ }
        }
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
                // FIXED: Changed viewModel.fetchData to viewModel.fetchDataFromServer
                Button(action: { viewModel.fetchDataFromServer(forceRefresh: true) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.bottom, 10)

            StatRow(label: "Total Cards", value: "\(viewModel.totalCardCount)")
            StatRow(label: "Remembered", value: "\(viewModel.rememberedCount)")
            StatRow(label: "Review tomorrow", value: "88") // Placeholder
            StatRow(label: "Review next week", value: "54") // Placeholder
            StatRow(label: "Hard to remember", value: "54") // Placeholder
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Helper Views

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
