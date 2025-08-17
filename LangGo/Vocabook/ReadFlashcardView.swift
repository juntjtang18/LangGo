import SwiftUI

struct ReadFlashcardView: View {
    @StateObject private var viewModel: ReadFlashcardViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme: Theme

    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    
    @AppStorage("readViewMode") private var viewMode: ViewMode = .card
    @AppStorage("readViewShowBaseText") private var showBaseText = true

    enum ViewMode: String, CaseIterable {
        case card
        case list
    }

    // MODIFIED: The initializer no longer requires strapiService.
    init() {
        _viewModel = StateObject(wrappedValue: ReadFlashcardViewModel())
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
                    ReadingSessionView(
                        viewModel: viewModel,
                        viewMode: $viewMode,
                        showBaseText: $showBaseText,
                        cardOffset: $cardOffset,
                        cardOpacity: $cardOpacity
                    )
                }
            }
            .navigationTitle("Reading Session")
            .navigationBarTitleDisplayMode(.inline)
            .background(theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        viewModel.stopReading()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            showBaseText.toggle()
                        }) {
                            Image(systemName: showBaseText ? "eye.slash.fill" : "eye.fill")
                        }
                        Picker("View Mode", selection: $viewMode) {
                            Image(systemName: "square.on.square").tag(ViewMode.card)
                            Image(systemName: "list.bullet").tag(ViewMode.list)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .onAppear {
                handleOnAppear()
            }
            .onDisappear {
                saveSettings()
            }
            .onChange(of: viewModel.currentCardIndex) { _ in
                guard viewMode == .card else { return }
                cardOffset = 0
                cardOpacity = 1
                withAnimation(.easeInOut(duration: 0.3)) {
                    cardOffset = -UIScreen.main.bounds.height
                    cardOpacity = 0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    cardOffset = 0
                    cardOpacity = 1
                }
            }
        }
    }
    
    private func handleOnAppear() {
        loadSettings()
        if viewModel.flashcards.isEmpty {
            Task {
                await viewModel.fetchReviewFlashcards()
                let lastIndex = UserDefaults.standard.integer(forKey: "lastReadCardIndex")
                viewModel.setInitialCardIndex(lastIndex)
            }
        }
    }
    
    private func loadSettings() {
        let savedMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "readViewMode") ?? "card")
        self.viewMode = savedMode ?? .card

        if UserDefaults.standard.object(forKey: "readViewShowBaseText") != nil {
            self.showBaseText = UserDefaults.standard.bool(forKey: "readViewShowBaseText")
        } else {
            self.showBaseText = true // Default
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(viewMode.rawValue, forKey: "readViewMode")
        UserDefaults.standard.set(showBaseText, forKey: "readViewShowBaseText")
        UserDefaults.standard.set(viewModel.currentCardIndex, forKey: "lastReadCardIndex")
    }
}

// MARK: - Extracted Subviews

private struct ReadingSessionView: View {
    @ObservedObject var viewModel: ReadFlashcardViewModel
    @Binding var viewMode: ReadFlashcardView.ViewMode
    @Binding var showBaseText: Bool
    @Binding var cardOffset: CGFloat
    @Binding var cardOpacity: Double
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack {
            if viewMode == .card {
                ProgressView(value: Double(viewModel.currentCardIndex + 1), total: Double(viewModel.flashcards.count)) {
                    Text("Card \(viewModel.currentCardIndex + 1) of \(viewModel.flashcards.count)")
                }
                .padding(.horizontal)
                .padding(.bottom, 20)

                CardDisplayView(
                    viewModel: viewModel,
                    showBaseText: $showBaseText,
                    cardOffset: $cardOffset,
                    cardOpacity: $cardOpacity
                )
            } else {
                FlashcardListView(
                    flashcards: viewModel.flashcards,
                    currentCardIndex: $viewModel.currentCardIndex,
                    showBaseText: $showBaseText
                )
            }
            
            Spacer()

            Button(action: {
                if viewModel.isReading {
                    viewModel.stopReading()
                } else {
                    viewModel.startReadingSession(showBaseTextBinding: $showBaseText)
                }
            }) {
                Text(viewModel.isReading ? "Stop" : "Start Reading")
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isReading ? theme.secondary : theme.primary)
                    .foregroundColor(theme.text)
                    .cornerRadius(12)
            }
            .padding()
        }
    }
}


private struct CardDisplayView: View {
    @ObservedObject var viewModel: ReadFlashcardViewModel
    @Binding var showBaseText: Bool
    @Binding var cardOffset: CGFloat
    @Binding var cardOpacity: Double

    var body: some View {
        ZStack {
            if let nextCard = viewModel.flashcards[safe: viewModel.currentCardIndex + 1] {
                CardReadingView(card: nextCard, readingState: .idle, showBaseText: $showBaseText)
                    .scaleEffect(0.95)
                    .offset(y: -20)
            } else if !viewModel.flashcards.isEmpty {
                CardReadingView(card: viewModel.flashcards[0], readingState: .idle, showBaseText: $showBaseText)
                    .scaleEffect(0.95)
                    .offset(y: -20)
            }

            if let currentCard = viewModel.flashcards[safe: viewModel.currentCardIndex] {
                CardReadingView(card: currentCard, readingState: viewModel.readingState, showBaseText: $showBaseText)
                    .id(viewModel.currentCardIndex)
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
    }
}


private struct FlashcardListView: View {
    let flashcards: [Flashcard]
    @Binding var currentCardIndex: Int
    @Binding var showBaseText: Bool
    @Environment(\.theme) var theme: Theme

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List(flashcards.indices, id: \.self) { index in
                    let card = flashcards[index]
                    HStack(spacing: 8) {
                        TierIconView(tier: card.reviewTire)
                        
                        Text(card.backContent)
                            .font(.body)
                            .frame(width: geometry.size.width * 0.5, alignment: .leading)
                        
                        if showBaseText {
                            Text(card.frontContent)
                                .font(.subheadline)
                                .foregroundColor(theme.text.opacity(0.7))
                                .frame(width: geometry.size.width * 0.3, alignment: .leading)
                        }
                    }
                    .id(index)
                    .listRowBackground(currentCardIndex == index ? theme.accent.opacity(0.3) : Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                // MODIFIED: The onChange closure is updated for iOS 16 compatibility.
                .onChange(of: currentCardIndex) { newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct CardReadingView: View {
    let card: Flashcard
    let readingState: ReadFlashcardViewModel.ReadingState
    @Binding var showBaseText: Bool
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(spacing: 20) {
            
            Text(card.backContent)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(readingState == .readingWord ? theme.accent : theme.text)
                .scaleEffect(readingState == .readingWord ? 1.05 : 1.0)

            if showBaseText {
                Text(card.frontContent)
                    .font(.title2)
                    .foregroundColor(readingState == .readingBaseText ? theme.accent : theme.text.opacity(0.7))
                    .scaleEffect(readingState == .readingBaseText ? 1.05 : 1.0)
            }
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 350)
        .background(theme.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .animation(.spring(), value: readingState)
    }
}
