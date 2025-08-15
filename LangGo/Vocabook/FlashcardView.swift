// LangGo/Vocabook/FlashcardView.swift
import SwiftUI

struct FlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // @StateObject is the correct property wrapper for creating and owning an
    // ObservableObject instance. It ensures the ViewModel is created once
    // and its lifecycle is managed correctly by SwiftUI.
    @StateObject private var viewModel = FlashcardViewModel()

    @State private var isReviewing: Bool = false
    @State private var isAddingNewWord: Bool = false
    
    var body: some View {
        NavigationStack {
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
                // Assuming NewWordInputView is also updated to use the new pattern
                NewWordInputView(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $isReviewing) {
                // Assuming FlashcardReviewView is also updated
                FlashcardReviewView(viewModel: viewModel)
            }
            .toolbar {
                 // Using the direct toolbar implementation that is known to work.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isSideMenuShowing.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .task {
                // Load initial data when the view first appears.
                await viewModel.loadStatistics()
            }
        }
    }
}

// NOTE: All private subviews (FlashcardProgressCircleView, ActionButtonsView, StatisticsView, etc.)
// remain exactly the same as they were already correctly using @ObservedObject.

private struct FlashcardProgressCircleView: View {
    @ObservedObject var viewModel: FlashcardViewModel

    private var progress: Double {
        guard viewModel.totalCardCount > 0 else { return 0 }
        return Double(viewModel.rememberedCount) / Double(viewModel.totalCardCount)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 15)
            
            Circle().fill(Color.green.opacity(0.1))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
            
            Text(percentageString)
                .font(.largeTitle)
                .bold()
        }
        .frame(width: 150, height: 150)
    }
    
    private var percentageString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: progress)) ?? "\(Int(progress * 100))%"
    }
}

private struct ActionButtonsView: View {
    @ObservedObject var viewModel: FlashcardViewModel
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
                        isReviewing = true
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
    @ObservedObject var viewModel: FlashcardViewModel
    
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

            StatRow(label: "Total Words", value: "\(viewModel.totalCardCount)")
            StatRow(label: "Mastered", value: "\(viewModel.rememberedCount)")
            StatRow(label: "Nearly Mastered", value: "\(viewModel.monthlyCardCount)")
            StatRow(label: "Well Practiced", value: "\(viewModel.weeklyReviewCardCount)")
            StatRow(label: "Warming Up", value: "\(viewModel.warmUpCardCount)")
            StatRow(label: "Just Added", value: "\(viewModel.newCardCount)")
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
