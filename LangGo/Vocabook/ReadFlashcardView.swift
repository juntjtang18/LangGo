import SwiftUI
import SwiftData

struct ReadFlashcardView: View {
    @StateObject private var viewModel: ReadFlashcardViewModel
    @Environment(\.dismiss) var dismiss

    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var viewMode: ViewMode = .card

    enum ViewMode {
        case card
        case list
    }

    init(modelContext: ModelContext, languageSettings: LanguageSettings, strapiService: StrapiService) {
        _viewModel = StateObject(wrappedValue: ReadFlashcardViewModel(modelContext: modelContext, languageSettings: languageSettings, strapiService: strapiService))
    }

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading cards...")
                } else if viewModel.flashcards.isEmpty {
                    Text("No cards available for reading.")
                        .foregroundColor(.secondary)
                } else {
                    VStack {
                        if viewMode == .card {
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
                        } else {
                            FlashcardListView(flashcards: viewModel.flashcards, currentCardIndex: $viewModel.currentCardIndex)
                        }
                        
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
            .navigationTitle("Reading Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        viewModel.stopReading()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("View Mode", selection: $viewMode) {
                        Image(systemName: "square.on.square").tag(ViewMode.card)
                        Image(systemName: "list.bullet").tag(ViewMode.list)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .onAppear {
                if viewModel.flashcards.isEmpty {
                    Task {
                        await viewModel.fetchFlashcards()
                    }
                }
            }
            .onChange(of: viewModel.currentCardIndex) {
                guard viewMode == .card else { return }
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
}

private struct FlashcardListView: View {
    let flashcards: [Flashcard]
    @Binding var currentCardIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            List(flashcards.indices, id: \.self) { index in
                let card = flashcards[index]
                HStack {
                    Text(card.backContent)
                        .font(.system(.title3, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(card.frontContent)
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(index)
                .listRowBackground(currentCardIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
            }
            .listStyle(.plain)
            .onChange(of: currentCardIndex) {
                withAnimation {
                    proxy.scrollTo(currentCardIndex, anchor: .center)
                }
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
