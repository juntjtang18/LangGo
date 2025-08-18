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
    @State private var gearFrameGlobal: CGRect = .zero

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
        .onPreferenceChange(GearFrameKey.self) { gearFrameGlobal = $0 }
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
                showReadingMenu: $showReadingMenu
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .onPreferenceChange(GearFrameKey.self) { newFrame in
            gearFrameGlobal = newFrame
        }
        .overlay {
            GeometryReader { rootProxy in
                // Host view’s rect in global space
                let rootGlobal = rootProxy.frame(in: .global)

                // Convert gear’s global → host-local
                let gearMidXLocal = gearFrameGlobal.midX - rootGlobal.minX
                let gearTopLocal  = gearFrameGlobal.minY - rootGlobal.minY
                let gearH         = gearFrameGlobal.height

                // Tweak these two as needed:
                let H_NUDGE: CGFloat = 0            // move left(-)/right(+)
                let V_GAP:   CGFloat = gearH * 0.4  // how far above the gear (40% of its height)

                ZStack {
                    if showReadingMenu && gearFrameGlobal != .zero {
                        ReadingMenuView(
                            activeMode: readingMode,
                            onRepeatWord: { readingMode = .repeatWord; showReadingMenu = false },
                            onCyclePage:  { readingMode = .cyclePage;  showReadingMenu = false },
                            onCycleAll:   { readingMode = .cycleAll;   showReadingMenu = false }
                        )
                        .fixedSize()
                        // X is the gear center (+ optional nudge);
                        // Y is just above the gear’s top by a fraction of its height
                        .position(x: gearMidXLocal + H_NUDGE,
                                  y: gearTopLocal - V_GAP)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showReadingMenu)
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

// MARK: - Helper Views (minor signature tweaks)

private struct ReadingMenuView: View {
    let activeMode: ReadingMode
    var onRepeatWord: () -> Void
    var onCyclePage: () -> Void
    var onCycleAll: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onRepeatWord) {
                Image(systemName: "repeat.1")
                    .foregroundColor(activeMode == .repeatWord ? theme.accent : theme.text)
            }
            Divider().frame(height: 20)
            Button(action: onCyclePage) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(activeMode == .cyclePage ? theme.accent : theme.text)
            }
            Divider().frame(height: 20)
            Button(action: onCycleAll) {
                Image(systemName: "infinity")
                    .foregroundColor(activeMode == .cycleAll ? theme.accent : theme.text)
            }
        }
        .font(.title2)
        .padding(.horizontal, 25)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .shadow(radius: 5)
        )
        .transition(.scale.animation(.spring(response: 0.4, dampingFraction: 0.6)))
    }
}

private struct PageNavigationControls: View {
    @Binding var currentPageIndex: Int
    let pageCount: Int

    var body: some View {
        HStack {
            Button(action: {
                withAnimation { currentPageIndex = max(0, currentPageIndex - 1) }
            }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(PageNavigationButtonStyle())
            .opacity(currentPageIndex > 0 ? 1.0 : 0.0)
            .disabled(currentPageIndex <= 0)

            Spacer()

            Button(action: {
                withAnimation { currentPageIndex = min(pageCount - 1, currentPageIndex + 1) }
            }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(PageNavigationButtonStyle())
            .opacity(currentPageIndex < pageCount - 1 ? 1.0 : 0.0)
            .disabled(currentPageIndex >= pageCount - 1)
        }
        .padding(.horizontal)
    }
}

private struct PageNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title.weight(.bold))
            .padding()
            .background(Color.black.opacity(configuration.isPressed ? 0.5 : 0.25))
            .foregroundColor(.white)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

private struct VocapageActionButton: View {
    let icon: String
    let action: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct VocapageActionButtons: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    @Binding var isShowingReviewView: Bool

    // Replaced direct SpeechManager control with simple play/pause signal from host.
    let isAutoPlaying: Bool
    let onPlayPauseTapped: () -> Void

    @Binding var showReadingMenu: Bool
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            VocapageActionButton(icon: "square.stack.3d.up.fill") {
                isShowingReviewView = true
            }

            VocapageActionButton(icon: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill") {
                onPlayPauseTapped()
            }

            VocapageActionButton(icon: "gearshape.fill") {
                showReadingMenu.toggle()
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: GearFrameKey.self,
                                    value: proxy.frame(in: .global))
                }
            )
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

private struct VocapagePagingView: View {
    @Binding var currentPageIndex: Int
    let allVocapageIds: [Int]
    @ObservedObject var loader: VocapageLoader
    @Binding var showBaseText: Bool
    let highlightIndex: Int
    let isShowingDueWordsOnly: Bool
    let onSelectCard: (Flashcard) -> Void   // <-- add this

    var body: some View {
        TabView(selection: $currentPageIndex) {
            ForEach(allVocapageIds.indices, id: \.self) { index in
                VocapageView(
                    vocapage: loader.vocapages[allVocapageIds[index]],
                    showBaseText: $showBaseText,
                    highlightIndex: highlightIndex,
                    onLoad: {
                        Task {
                            await loader.loadPage(withId: allVocapageIds[index], dueWordsOnly: isShowingDueWordsOnly)
                        }
                    },
                    onSelectCard: onSelectCard                 // <-- add this
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct VocapageToolbar: ToolbarContent {
    @Binding var showBaseText: Bool
    let sortedFlashcards: [Flashcard]

    // New: we no longer pass the manager through; just the state and actions the UI needs.
    let isAutoPlaying: Bool
    var onPlayPauseTapped: () -> Void

    var onDismiss: () -> Void
    @Binding var isShowingReviewView: Bool
    @Binding var isShowingDueWordsOnly: Bool
    var onToggleDueWords: () -> Void
    @Environment(\.theme) var theme: Theme
    @Binding var showReadingMenu: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: onDismiss) {
                HStack { Image(systemName: "chevron.left"); Text("Back") }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showBaseText.toggle() }) {
                Image(systemName: showBaseText ? "eye.slash.fill" : "eye.fill")
            }
        }
        ToolbarItem(placement: .bottomBar) {
            HStack {
                VocapageActionButtons(
                    sortedFlashcards: sortedFlashcards,
                    showBaseText: showBaseText,
                    isShowingReviewView: $isShowingReviewView,
                    isAutoPlaying: isAutoPlaying,
                    onPlayPauseTapped: onPlayPauseTapped,
                    showReadingMenu: $showReadingMenu
                )
                Spacer()
                Button(action: onToggleDueWords) {
                    Image(systemName: isShowingDueWordsOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.title2)
                        .foregroundColor(theme.accent)
                }
            }
        }
    }
}

private struct GearFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
