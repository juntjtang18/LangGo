import SwiftUI

struct VocapageReviewView: View {
    @Environment(\.dismiss) var dismiss
    
    // It takes the cards directly, and the viewModel for the submission logic.
    let cardsToReview: [Flashcard]
    let viewModel: FlashcardViewModel
    
    @State private var currentIndex = 0
    @State private var isFlipped = false

    var body: some View {
        NavigationStack {
            VStack {
                if cardsToReview.isEmpty {
                    Spacer()
                    Text("No cards to review on this page.")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    // Progress indicators
                    VStack {
                        ProgressView(value: Double(currentIndex + 1), total: Double(cardsToReview.count)) {
                            Text("Progress")
                        }
                        .progressViewStyle(.linear)
                        
                        // Use NumberFormatter for locale-sensitive progress count formatting
                        Text(progressCountString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Spacer()

                    // The Flippable Card View
                    if let card = cardsToReview[safe: currentIndex] {
                        
                        // Display Register
                        if let register = card.register, !register.isEmpty, register != "Neutral" {
                            HStack {
                                Text(register)
                                    .style(.registerTag)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        }
                        
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
                                .style(.wrongButton)
                        }
                        
                        Button(action: { markCard(.correct) }) {
                            Text("Correct")
                                .style(.correctButton)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Page Review")
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
    
    private var progressCountString: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        // Use a localized format string for "X of Y"
        let format = NSLocalizedString("%lld of %lld", comment: "Progress count format (e.g., 1 of 10)")
        return String(format: format, currentIndex + 1, cardsToReview.count)
    }
    
    private func markCard(_ answer: ReviewResult) {
        guard let currentCard = cardsToReview[safe: currentIndex] else { return }
        
        // Use the viewModel's method to handle the submission logic
        viewModel.markReview(for: currentCard, result: answer)
        
        goToNextCard()
    }
    
    private func goToNextCard() {
        if currentIndex < cardsToReview.count - 1 {
            // Use a slight delay to allow the user to see the result before the card flips
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFlipped = false // Ensure next card starts on the front
                currentIndex += 1
            }
        } else {
            // All cards have been reviewed
            dismiss()
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
