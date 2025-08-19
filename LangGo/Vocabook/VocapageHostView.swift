// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import os
import Combine

struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme: Theme

    @StateObject private var loader = VocapageLoader()
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true

    // Speaker now plays exactly one word; host manages "auto-play" loop and next index.
    @StateObject private var speechManager = SpeechManager()
    @State private var pendingAutoplayAfterLoad: Bool = false

    @State private var showReadingMenu: Bool = false
    @State private var showFilterMenu: Bool = false               // NEW
    @AppStorage("readingMode") private var readingMode: ReadingMode = .cyclePage

    let originalAllVocapageIds: [Int]
    @State private var vocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    @State private var isShowingReviewView: Bool = false
    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly: Bool = false

    // New: host-owned auto-play state & index.
    @State private var isAutoPlaying: Bool = false
    @State private var currentWordIndex: Int = -1
    @State private var vbSettings: VBSettingAttributes?
    @State private var selectedCard: Flashcard? = nil

    // Popup anchors (measured in global space)
    @State private var gearFrameGlobal: CGRect = .zero
    @State private var filterFrameGlobal: CGRect = .zero          // NEW

    init(allVocapageIds: [Int], selectedVocapageId: Int, flashcardViewModel: FlashcardViewModel) {
        self.originalAllVocapageIds = allVocapageIds
        self._vocapageIds = State(initialValue: allVocapageIds)
        _currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        self.flashcardViewModel = flashcardViewModel
    }

    private var currentVocapage: Vocapage? {
        guard !vocapageIds.isEmpty else { return nil }
        let currentId = vocapageIds[currentPageIndex]
        return loader.vocapages[currentId]
    }

    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

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
                    // Stop autoplay so it doesn’t keep speaking behind the sheet
                    stopAutoplay()
                    selectedCard = card
                }
            )

            PageNavigationControls(currentPageIndex: $currentPageIndex, pageCount: vocapageIds.count)
        }
        .navigationTitle("My Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            VocapageToolbar(
                showBaseText: $showBaseText,
                sortedFlashcards: sortedFlashcardsForCurrentPage,
                isAutoPlaying: isAutoPlaying,
                onPlayPauseTapped: { playPauseTapped() },
                onDismiss: { dismiss() },
                isShowingReviewView: $isShowingReviewView,
                isShowingDueWordsOnly: $isShowingDueWordsOnly,
                onToggleDueWords: {
                    isShowingDueWordsOnly.toggle()
                    Task { await updatePageIdsForFilter() }
                },
                showReadingMenu: $showReadingMenu,
                showFilterMenu: $showFilterMenu         // NEW
            )
        }
        .toolbar(.hidden, for: .tabBar)
        // Listen for anchor updates from toolbar buttons
        .onPreferenceChange(GearFrameKey.self) { gearFrameGlobal = $0 }
        .onPreferenceChange(FilterFrameKey.self) { filterFrameGlobal = $0 } // NEW
        .overlay {
            GeometryReader { rootProxy in
                // Host view’s rect in global space
                let rootGlobal = rootProxy.frame(in: .global)
                let viewW = rootProxy.size.width
                let viewH = rootProxy.size.height

                // Popup layout constants
                let H_NUDGE: CGFloat = 0
                let V_GAP:   CGFloat = 32

                ZStack {
                    // ===== Reading-mode popup (anchored to gear, with fallback) =====
                    if showReadingMenu {
                        // Decide if the toolbar-provided anchor is usable; if not, we'll float bottom-trailing.
                        let anchorUsable = gearFrameGlobal.width > 1 && gearFrameGlobal.height > 1 && gearFrameGlobal.intersects(rootGlobal.insetBy(dx: -20, dy: -20))

                        // Convert gear’s global → host-local
                        let gearMidXLocal = gearFrameGlobal.midX - rootGlobal.minX
                        let gearTopLocal  = gearFrameGlobal.minY - rootGlobal.minY

                        let unclampedX = gearMidXLocal + H_NUDGE
                        let unclampedY = gearTopLocal  - V_GAP

                        // keep inside visible content to avoid clipping under toolbar
                        let x = min(max(unclampedX, 16), viewW - 16)
                        let y = min(max(unclampedY, 16), viewH - 16)

                        if anchorUsable {
                            ReadingMenuView(
                                activeMode: readingMode,
                                onRepeatWord: { readingMode = .repeatWord; showReadingMenu = false },
                                onCyclePage:  { readingMode = .cyclePage;  showReadingMenu = false },
                                onCycleAll:   { readingMode = .cycleAll;   showReadingMenu = false }
                            )
                            .fixedSize()
                            .position(x: x, y: y)
                            .zIndex(1000)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showReadingMenu)
                        } else {
                            ReadingMenuView(
                                activeMode: readingMode,
                                onRepeatWord: { readingMode = .repeatWord; showReadingMenu = false },
                                onCyclePage:  { readingMode = .cyclePage;  showReadingMenu = false },
                                onCycleAll:   { readingMode = .cycleAll;   showReadingMenu = false }
                            )
                            .fixedSize()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.bottom, 16)
                            .padding(.trailing, 16)
                            .zIndex(1000)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showReadingMenu)
                        }
                    }

                    // ===== Filter popup (anchored to 3rd button, with fallback) =====
                    if showFilterMenu {
                        // Decide if the toolbar-provided anchor is usable; if not, we'll float bottom-trailing.
                        let anchorUsable = filterFrameGlobal.width > 1 && filterFrameGlobal.height > 1 && filterFrameGlobal.intersects(rootGlobal.insetBy(dx: -20, dy: -20))

                        // Convert filter button’s global → host-local
                        let filterMidXLocal = filterFrameGlobal.midX - rootGlobal.minX
                        let filterTopLocal  = filterFrameGlobal.minY - rootGlobal.minY

                        let unclampedX = filterMidXLocal + H_NUDGE
                        let unclampedY = filterTopLocal  - V_GAP

                        let x = min(max(unclampedX, 16), viewW - 16)
                        let y = min(max(unclampedY, 16), viewH - 16)

                        if anchorUsable {
                            FilterMenuView(
                                isDueOnly: isShowingDueWordsOnly,
                                onDueWords: {
                                    if !isShowingDueWordsOnly {
                                        isShowingDueWordsOnly = true
                                        Task { await updatePageIdsForFilter() }
                                    }
                                    showFilterMenu = false
                                },
                                onAllWords: {
                                    if isShowingDueWordsOnly {
                                        isShowingDueWordsOnly = false
                                        Task { await updatePageIdsForFilter() }
                                    }
                                    showFilterMenu = false
                                }
                            )
                            .fixedSize()
                            .position(x: x, y: y)
                            .zIndex(1000)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFilterMenu)
                        } else {
                            FilterMenuView(
                                isDueOnly: isShowingDueWordsOnly,
                                onDueWords: {
                                    if !isShowingDueWordsOnly {
                                        isShowingDueWordsOnly = true
                                        Task { await updatePageIdsForFilter() }
                                    }
                                    showFilterMenu = false
                                },
                                onAllWords: {
                                    if isShowingDueWordsOnly {
                                        isShowingDueWordsOnly = false
                                        Task { await updatePageIdsForFilter() }
                                    }
                                    showFilterMenu = false
                                }
                            )
                            .fixedSize()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.bottom, 16)
                            .padding(.trailing, 16)
                            .zIndex(1000)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFilterMenu)
                        }
                    }
                }
            }
        }
        .onChange(of: currentPageIndex) { _ in
            // If user manually changes page and we're not in cycleAll autoplay, stop.
            if readingMode != .cycleAll {
                stopAutoplay()
            }
        }
        .onChange(of: sortedFlashcardsForCurrentPage) { newCards in
            // Only trigger after a page change we initiated for cycleAll autoplay.
            guard pendingAutoplayAfterLoad else { return }
            guard readingMode == .cycleAll, isAutoPlaying, !newCards.isEmpty else { return }

            pendingAutoplayAfterLoad = false

            // Clamp in case due-only filter altered the count.
            if currentWordIndex >= newCards.count { currentWordIndex = max(0, newCards.count - 1) }

            // Defer one tick so the List is rendered; this ensures highlight and scroll are ready.
            DispatchQueue.main.async {
                playCurrent()
            }
        }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(cardsToReview: sortedFlashcardsForCurrentPage, viewModel: flashcardViewModel)
        }
        .task { await updatePageIdsForFilter() }
        .sheet(item: $selectedCard) { card in
            wordDetailSheet(for: card)
        }
    }

    @ViewBuilder
    private func wordDetailSheet(for card: Flashcard) -> some View {
        let onClose: () -> Void = { self.selectedCard = nil }

        let onSpeakOnce: (@escaping () -> Void) -> Void = { completion in
            Task {
                if self.vbSettings == nil {
                    self.vbSettings = try? await DataServices.shared.strapiService.fetchVBSetting().attributes
                }
                if let settings = self.vbSettings {
                    // Ensure only one utterance sequence at a time
                    self.speechManager.stop()
                    self.speechManager.speak(
                        card: card,
                        showBaseText: self.showBaseText,
                        settings: settings
                    ) {
                        completion()
                    }
                } else {
                    // If settings fail to load, still unblock the loop
                    completion()
                }
            }
        }

        WordDetailSheet(
            card: card,
            showBaseText: showBaseText,
            onClose: onClose,
            onSpeak: onSpeakOnce     // <-- updated signature
        )
        .presentationDetents([.medium, .large])
    }
    
    private func vbRepeatGapSeconds() -> TimeInterval {
        guard let s = vbSettings else { return 1.0 } // sensible fallback
        return TimeInterval(s.interval1) / 1000.0
    }

    // MARK: - Auto-play control owned by host

    private func playPauseTapped() {
        if isAutoPlaying {
            // Pause current utterance and freeze loop.
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
            if currentWordIndex == -1 {
                currentWordIndex = 0
            }
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
        guard !cards.isEmpty else { return }
        guard currentWordIndex >= 0 && currentWordIndex < cards.count else { return }
        guard let settings = vbSettings else { return }
        
        // Update highlight
        speechManager.currentIndex = currentWordIndex
        
        speechManager.speak(
            card: cards[currentWordIndex],
            showBaseText: showBaseText,
            settings: settings
        ) {
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
            currentWordIndex = (currentWordIndex + 1) % count
            playCurrent()

        case .cycleAll:
            if currentWordIndex < count - 1 {
                currentWordIndex += 1
                playCurrent()
            } else {
                // move to next page and continue at index 0
                advanceToNextPageAndContinue()
            }

        case .inactive:
            stopAutoplay()
        }
    }

    private func advanceToNextPageAndContinue() {
        guard !vocapageIds.isEmpty else { stopAutoplay(); return }
        let nextPage = (currentPageIndex + 1) % vocapageIds.count

        // Prepare one-time autoplay after load.
        pendingAutoplayAfterLoad = true
        currentWordIndex = 0

        // Stop any in-flight utterance to avoid chopping the “second read”.
        speechManager.stop()

        // Optimistically show highlight at 0 so the user sees it immediately.
        speechManager.currentIndex = 0

        // Switch page and load; DO NOT call playCurrent() here.
        currentPageIndex = nextPage
        Task {
            await loader.loadPage(withId: vocapageIds[nextPage], dueWordsOnly: isShowingDueWordsOnly)
            // onChange(sortedFlashcardsForCurrentPage) will fire and call playCurrent() exactly once.
        }
    }

    // MARK: - Existing filter paging logic retained

    private func updatePageIdsForFilter() async {
        if isShowingDueWordsOnly {
            await flashcardViewModel.loadStatistics()
            let totalDueCards = flashcardViewModel.dueForReviewCount

            do {
                let vbSetting = try await DataServices.shared.strapiService.fetchVBSetting()
                let pageSize = vbSetting.attributes.wordsPerPage
                let totalPages = Int(ceil(Double(totalDueCards) / Double(pageSize)))

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

        // Any page structure change cancels autoplay if current page is empty.
        if sortedFlashcardsForCurrentPage.isEmpty { stopAutoplay() }
    }
}

