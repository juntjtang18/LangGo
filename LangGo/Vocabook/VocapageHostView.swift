// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import Combine

struct VocapageHostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme: Theme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var loader = VocapageLoader()
    @StateObject private var speechManager = SpeechManager()

    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    @AppStorage("readingMode") private var readingMode: ReadingMode = .cyclePage
    
    @Binding var isShowingDueWordsOnly: Bool

    @State private var vocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    let onFilterChange: () -> Void

    @State private var isAutoPlaying = false
    @State private var currentWordIndex = -1
    @State private var vbSettings: VBSettingAttributes?
    @State private var pendingAutoplayAfterLoad = false

    @State private var isShowingReviewView = false
    @State private var selectedCard: Flashcard?

    init(
        allVocapageIds: [Int],
        selectedVocapageId: Int,
        flashcardViewModel: FlashcardViewModel,
        isShowingDueWordsOnly: Binding<Bool>,
        onFilterChange: @escaping () -> Void
    ) {
        self._vocapageIds = State(initialValue: allVocapageIds)
        self._currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        self.flashcardViewModel = flashcardViewModel
        self._isShowingDueWordsOnly = isShowingDueWordsOnly
        self.onFilterChange = onFilterChange
    }

    private var currentVocapage: Vocapage? {
        guard !vocapageIds.isEmpty, currentPageIndex < vocapageIds.count else { return nil }
        return loader.vocapages[vocapageIds[currentPageIndex]]
    }
    
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        ZStack {
            if vocapageIds.isEmpty {
                 Text("No words to show for this page.")
                    .foregroundColor(.secondary)
            } else {
                VocapagePagingView(
                    currentPageIndex: $currentPageIndex,
                    allVocapageIds: vocapageIds,
                    loader: loader,
                    showBaseText: $showBaseText,
                    highlightIndex: speechManager.currentIndex,
                    isShowingDueWordsOnly: isShowingDueWordsOnly,
                    onSelectCard: { card in
                        stopAutoplay()
                        selectedCard = card
                    }
                )

                PageNavigationControls(
                    currentPageIndex: $currentPageIndex,
                    pageCount: vocapageIds.count
                )
            }
        }
        .navigationTitle("My Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    stopAutoplay()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showBaseText.toggle()
                } label: {
                    Image(systemName: showBaseText ? "text.badge.minus" : "text.badge.plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(showBaseText ? "Hide Base Text" : "Show Base Text")
            }
        }
        .safeAreaInset(edge: .bottom) { bottomToolbar }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) { _ in
            if readingMode != .cycleAll { stopAutoplay() }
        }
        .onChange(of: sortedFlashcardsForCurrentPage) { newCards in
            guard pendingAutoplayAfterLoad,
                  readingMode == .cycleAll,
                  isAutoPlaying,
                  !newCards.isEmpty else { return }
            pendingAutoplayAfterLoad = false
            if currentWordIndex >= newCards.count { currentWordIndex = max(0, newCards.count - 1) }
            DispatchQueue.main.async { playCurrent() }
        }
        .sheet(item: $selectedCard) { card in wordDetailSheet(for: card) }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(cardsToReview: sortedFlashcardsForCurrentPage, viewModel: flashcardViewModel)
        }
        .onDisappear { stopAutoplay() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                stopAutoplay()
            }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            Spacer()
            Button { playPauseTapped() } label: {
                Image(systemName: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .accessibilityLabel(isAutoPlaying ? "Pause" : "Play")

            Spacer(minLength: 0)

            Menu {
                Button {
                    toggleReading(.repeatWord)
                } label: {
                    Label("Repeat Word", systemImage: readingMode == .repeatWord ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    toggleReading(.cyclePage)
                } label: {
                    Label("Cycle Page", systemImage: readingMode == .cyclePage ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    toggleReading(.cycleAll)
                } label: {
                    Label("Cycle All", systemImage: readingMode == .cycleAll ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: repeatIndicatorIcon).font(.title3)
            }
            .accessibilityLabel("Reading Mode")

            Menu {
                Button {
                    if !isShowingDueWordsOnly {
                        isShowingDueWordsOnly = true
                    }
                } label: {
                    Label("Due Only", systemImage: isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    if isShowingDueWordsOnly {
                        isShowingDueWordsOnly = false
                    }
                } label: {
                    Label("All Words", systemImage: !isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.title3)
            }
            .accessibilityLabel("Filter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func wordDetailSheet(for card: Flashcard) -> some View {
        let cards = sortedFlashcardsForCurrentPage
        let idx = cards.firstIndex(where: { $0.id == card.id }) ?? 0

        let onSpeakOnce: (_ c: Flashcard, _ completion: @escaping () -> Void) -> Void = { c, completion in
            Task {
                if self.vbSettings == nil {
                    self.vbSettings = try? await DataServices.shared.settingsService.fetchVBSetting().attributes
                }
                if let settings = self.vbSettings {
                    self.speechManager.stop()
                    self.speechManager.speak(
                        card: c,
                        showBaseText: self.showBaseText,
                        settings: settings
                    ) { completion() }
                } else {
                    completion()
                }
            }
        }

        WordDetailSheet(
            cards: cards,
            initialIndex: idx,
            showBaseText: showBaseText,
            onClose: { self.selectedCard = nil },
            onSpeak: onSpeakOnce
        )
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    private func toggleReading(_ target: ReadingMode) {
        readingMode = (readingMode == target) ? .inactive : target
    }
    
    private var repeatIndicatorIcon: String {
        switch readingMode {
        case .inactive:   return "repeat"
        case .repeatWord: return "repeat.1"
        case .cyclePage:  return "repeat.circle"
        case .cycleAll:   return "repeat.circle.fill"
        }
    }

    private func playPauseTapped() {
        if isAutoPlaying {
            isAutoPlaying = false
            speechManager.pause()
        } else {
            isAutoPlaying = true
            if speechManager.isPaused {
                speechManager.resume()
            } else {
                startAutoplayIfNeeded()
            }
        }
    }
    private func startAutoplayIfNeeded() {
        guard !sortedFlashcardsForCurrentPage.isEmpty else { return }
        Task {
            if vbSettings == nil {
                do { vbSettings = try await DataServices.shared.settingsService.fetchVBSetting().attributes }
                catch { vbSettings = nil }
            }
            if currentWordIndex == -1 { currentWordIndex = 0 }
            playCurrent()
        }
    }
    private func stopAutoplay() {
        isAutoPlaying = false
        speechManager.stop()
        currentWordIndex = -1
    }
    private func playCurrent() {
        guard isAutoPlaying else { return }
        let cards = sortedFlashcardsForCurrentPage
        guard !cards.isEmpty,
              currentWordIndex >= 0, currentWordIndex < cards.count,
              let settings = vbSettings else { return }

        speechManager.currentIndex = currentWordIndex
        speechManager.speak(card: cards[currentWordIndex], showBaseText: showBaseText, settings: settings) {
            onOneWordFinished()
        }
    }
    private func onOneWordFinished() {
        guard isAutoPlaying else { return }
        let count = sortedFlashcardsForCurrentPage.count
        if count == 0 { stopAutoplay(); return }
        switch readingMode {
        case .repeatWord:
            if currentWordIndex == -1 { currentWordIndex = 0 }
            playCurrent()
        case .cyclePage:
            currentWordIndex = (currentWordIndex + 1) % count
            playCurrent()
        case .cycleAll:
            if currentWordIndex < count - 1 {
                currentWordIndex += 1
                playCurrent()
            } else {
                advanceToNextPageAndContinue()
            }
        case .inactive:
            if currentWordIndex < count - 1 {
                currentWordIndex += 1
                playCurrent()
            } else {
                stopAutoplay()
            }
        }
    }

    private func advanceToNextPageAndContinue() {
        guard !vocapageIds.isEmpty else { stopAutoplay(); return }
        let nextPage = (currentPageIndex + 1) % vocapageIds.count

        pendingAutoplayAfterLoad = true
        currentWordIndex = 0

        speechManager.stop()
        speechManager.currentIndex = 0

        currentPageIndex = nextPage
        Task {
            await loader.loadPage(withId: vocapageIds[nextPage], dueWordsOnly: isShowingDueWordsOnly)
        }
    }
}
