import SwiftUI

struct FlashcardReviewView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: FlashcardViewModel
    
    @State private var currentIndex = 0
    @State private var isFlipped = false

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.reviewCards.isEmpty {
                    Spacer()
                    Text("No cards to review.")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    // Progress indicators
                    VStack {
                        ProgressView(value: Double(currentIndex + 1), total: Double(viewModel.reviewCards.count)) {
                            Text("Progress")
                        }
                        .progressViewStyle(.linear)
                        
                        Text("\(currentIndex + 1) of \(viewModel.reviewCards.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Spacer()

                    // The Flippable Card View
                    if let card = viewModel.reviewCards[safe: currentIndex] {
                        FlippableCardView(
                            frontContent: card.frontContent,
                            backContent: card.backContent,
                            isFlipped: $isFlipped
                        )
                        .onTapGesture {
                            withAnimation(.spring) {
                                isFlipped.toggle()
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 20) {
                        Button(action: { markCard(.wrong) }) {
                            Text("Wrong")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        Button(action: { markCard(.correct) }) {
                            Text("Correct")
                                 .font(.title2)
                                 .fontWeight(.bold)
                                 .frame(maxWidth: .infinity)
                                 .padding()
                                 .background(Color.green.opacity(0.8))
                                 .foregroundColor(.white)
                                 .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
    }
    
    private enum Answer {
        case correct, wrong
    }
    
    private func markCard(_ answer: Answer) {
        guard let currentCard = viewModel.reviewCards[safe: currentIndex] else { return }
        
        if answer == .correct {
            viewModel.markCorrect(for: currentCard)
        } else {
            viewModel.markWrong(for: currentCard)
        }
        
        // Move to the next card
        if currentIndex < viewModel.reviewCards.count - 1 {
            isFlipped = false // Ensure next card starts on the front
            currentIndex += 1
        } else {
            dismiss() // End of session
        }
    }
}

// MARK: - Subviews

private struct FlippableCardView: View {
    let frontContent: String
    let backContent: String
    @Binding var isFlipped: Bool

    var body: some View {
        ZStack {
            // Use a Group to apply modifiers to both card faces
            Group {
                CardFace(content: frontContent)
                    .opacity(isFlipped ? 0 : 1)
                
                CardFace(content: backContent)
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }
}

private struct CardFace: View {
    let content: String
    
    var body: some View {
        Text(content)
            .font(.system(size: 48, weight: .bold))
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(radius: 5)
            .padding(.horizontal)
    }
}


// Helper extension for safe array access
extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
