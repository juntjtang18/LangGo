import SwiftUI
import SwiftData

struct ReadFlashcardView: View {
    @State private var viewModel: ReadFlashcardViewModel
    @Environment(\.dismiss) var dismiss
    
    // Animation state for the card transition
    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1

    init(modelContext: ModelContext, languageSettings: LanguageSettings, strapiService: StrapiService) {
        // The viewModel is now initialized with the necessary languageSettings and strapiService.
        _viewModel = State(initialValue: ReadFlashcardViewModel(modelContext: modelContext, languageSettings: languageSettings, strapiService: strapiService))
    }

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Loading cards...")
            } else if viewModel.flashcards.isEmpty {
                Text("No cards available for reading.")
                    .foregroundColor(.secondary)
            } else {
                VStack {
                    // Progress View
                    ProgressView(value: Double(viewModel.currentCardIndex + 1), total: Double(viewModel.flashcards.count)) {
                        Text("Card \(viewModel.currentCardIndex + 1) of \(viewModel.flashcards.count)")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)

                    // Card display area
                    ZStack {
                        // This creates the "deck" effect by showing the next card slightly behind.
                        if let nextCard = viewModel.flashcards[safe: viewModel.currentCardIndex + 1] {
                            CardReadingView(card: nextCard, readingState: .idle)
                                .scaleEffect(0.95)
                                .offset(y: -20)
                        } else if !viewModel.flashcards.isEmpty {
                            // Show the first card behind the last card to complete the loop illusion
                             CardReadingView(card: viewModel.flashcards[0], readingState: .idle)
                                .scaleEffect(0.95)
                                .offset(y: -20)
                        }

                        if let currentCard = viewModel.flashcards[safe: viewModel.currentCardIndex] {
                            CardReadingView(card: currentCard, readingState: viewModel.readingState)
                                .id(viewModel.currentCardIndex) // Use index to ensure view redraws
                                .offset(y: cardOffset)
                                .opacity(cardOpacity)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if value.translation.height < 0 {
                                                cardOffset = value.translation.height
                                            }
                                        }
                                        .onEnded { value in
                                            if value.translation.height < -100 {
                                                // Swipe up to skip card
                                                viewModel.skipToNextCard()
                                            } else {
                                                withAnimation(.spring) {
                                                    cardOffset = 0
                                                }
                                            }
                                        }
                                )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()

                    // Control Buttons - This logic correctly swaps between Start and Stop.
                    HStack {
                        Button(action: {
                            if viewModel.isReading {
                                viewModel.stopReading()
                            } else {
                                viewModel.startReadingSession()
                            }
                        }) {
                            Text(viewModel.isReading ? "Stop" : "Start Reading")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.isReading ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            if viewModel.flashcards.isEmpty {
                Task {
                    await viewModel.fetchFlashcards()
                }
            }
        }
        .onChange(of: viewModel.currentCardIndex) { _, _ in
            // Animate card sliding up and away
            cardOffset = 0
            cardOpacity = 1
            withAnimation(.easeInOut(duration: 0.3)) {
                cardOffset = -UIScreen.main.bounds.height
                cardOpacity = 0
            }
            
            // Reset for the new card to slide in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                cardOffset = 0
                cardOpacity = 1
            }
        }
    }
}

// A dedicated view for displaying the content of a single card during reading.
private struct CardReadingView: View {
    let card: Flashcard
    let readingState: ReadFlashcardViewModel.ReadingState

    var body: some View {
        VStack(spacing: 20) {
            
            // English Word (Back Content)
            Text(card.backContent)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(readingState == .readingWord ? .blue : .primary)
                .scaleEffect(readingState == .readingWord ? 1.05 : 1.0)

            // Chinese Translation (Front Content)
            Text(card.frontContent)
                .font(.system(size: 32))
                .foregroundColor(readingState == .readingBaseText ? .blue : .secondary)
                .scaleEffect(readingState == .readingBaseText ? 1.05 : 1.0)
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 350)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .animation(.spring(), value: readingState)
    }
}
