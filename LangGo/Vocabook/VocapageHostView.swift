// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import Combine

struct VocapageHostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme: Theme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var loader = VocapageLoader()
    @StateObject private var speechManager = SpeechManager()

    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    @AppStorage("readingMode") private var readingMode: ReadingMode = .cyclePage
    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly: Bool = false

    let originalAllVocapageIds: [Int]
    @State private var vocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel

    // Playback state
    @State private var isAutoPlaying = false
    @State private var currentWordIndex = -1
    @State private var vbSettings: VBSettingAttributes?
    @State private var pendingAutoplayAfterLoad = false
    //@State private var finishPageWithoutRepeat = false

    // Sheets
    @State private var isShowingReviewView = false
    @State private var selectedCard: Flashcard?

    init(allVocapageIds: [Int], selectedVocapageId: Int, flashcardViewModel: FlashcardViewModel) {
        self.originalAllVocapageIds = allVocapageIds
        self._vocapageIds = State(initialValue: allVocapageIds)
        self._currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        self.flashcardViewModel = flashcardViewModel
    }

    // MARK: - Derived
    private var currentVocapage: Vocapage? {
        guard !vocapageIds.isEmpty else { return nil }
        return loader.vocapages[vocapageIds[currentPageIndex]]
    }
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    // MARK: - UI
    var body: some View {
        ZStack {
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
        .task { await updatePageIdsForFilter() }
        .sheet(item: $selectedCard) { card in wordDetailSheet(for: card) }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(cardsToReview: sortedFlashcardsForCurrentPage, viewModel: flashcardViewModel)
        }
        .onDisappear { stopAutoplay() }
        .onChange(of: scenePhase) { phase in
            // Stop reading whenever app is not active (home button, lock, multitask)
            if phase != .active {
                stopAutoplay()
            }
        }
    }

    // MARK: - Bottom Toolbar
    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            Spacer()
            // Play / Pause
            Button { playPauseTapped() } label: {
                Image(systemName: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .accessibilityLabel(isAutoPlaying ? "Pause" : "Play")

            Spacer(minLength: 0)

            // Reading / Repeat (toggle items)
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

            // Filter
            Menu {
                Button {
                    if !isShowingDueWordsOnly {
                        isShowingDueWordsOnly = true
                        Task { await updatePageIdsForFilter() }
                    }
                } label: {
                    Label("Due Only", systemImage: isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    if isShowingDueWordsOnly {
                        isShowingDueWordsOnly = false
                        Task { await updatePageIdsForFilter() }
                    }
                } label: {
                    Label("All Words", systemImage: !isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.title3)
            }
            .accessibilityLabel("Filter")

            // Review
            Button {
                stopAutoplay()
                isShowingReviewView = true
            } label: {
                Image(systemName: "list.bullet.rectangle.portrait").font(.title3)
            }
            .accessibilityLabel("Review")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Sheet
    @ViewBuilder
    private func wordDetailSheet(for card: Flashcard) -> some View {
        let cards = sortedFlashcardsForCurrentPage
        let idx = cards.firstIndex(where: { $0.id == card.id }) ?? 0

        // speak helper that takes a card
        let onSpeakOnce: (_ c: Flashcard, _ completion: @escaping () -> Void) -> Void = { c, completion in
            Task {
                if self.vbSettings == nil {
                    self.vbSettings = try? await DataServices.shared.strapiService.fetchVBSetting().attributes
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
        // 🔒 keep half height even when paging
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }



    // MARK: - Reading Mode
    private func toggleReading(_ target: ReadingMode) {
        // Tapping the same item toggles OFF; otherwise switch to that mode.
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

    // MARK: - Autoplay
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
                do { vbSettings = try await DataServices.shared.strapiService.fetchVBSetting().attributes }
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
            // same index
            playCurrent()

        case .cyclePage:
            // wrap within the page
            currentWordIndex = (currentWordIndex + 1) % count
            playCurrent()

        case .cycleAll:
            // advance across pages and wrap to next page
            if currentWordIndex < count - 1 {
                currentWordIndex += 1
                playCurrent()
            } else {
                advanceToNextPageAndContinue()
            }

        case .inactive:
            // NEW: advance within page WITHOUT wrapping; stop at end
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
            // playback resumes once in onChange(sortedFlashcardsForCurrentPage)
        }
    }

    // MARK: - Filter paging
    private func updatePageIdsForFilter() async {
        if isShowingDueWordsOnly {
            do {
                // Pull fresh stats directly from the service (VM no longer owns stats)
                let stats = try await DataServices.shared.strapiService.fetchFlashcardStatistics()
                let totalDue = stats.dueForReview

                let vb = try await DataServices.shared.strapiService.fetchVBSetting()
                let pageSize = vb.attributes.wordsPerPage
                let totalPages = Int(ceil(Double(totalDue) / Double(pageSize)))

                vocapageIds = totalPages > 0 ? Array(1...totalPages) : []

                if currentPageIndex >= vocapageIds.count {
                    currentPageIndex = max(0, vocapageIds.count - 1)
                }
            } catch {
                vocapageIds = []
            }
        } else {
            vocapageIds = originalAllVocapageIds
        }

        loader.vocapages.removeAll()
        if !vocapageIds.isEmpty {
            let currentId = vocapageIds[currentPageIndex]
            await loader.loadPage(withId: currentId, dueWordsOnly: isShowingDueWordsOnly)
        }

        if sortedFlashcardsForCurrentPage.isEmpty { stopAutoplay() }
    }

}
