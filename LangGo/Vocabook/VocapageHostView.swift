// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import Combine
import os

struct VocapageHostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme: Theme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var loader = VocapageLoader()
    @StateObject private var speechManager = SpeechManager()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageHostView")

    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    @AppStorage("readingMode") private var readingMode: ReadingMode = .cyclePage
    
    @Binding var isShowingDueWordsOnly: Bool

    @State private var vocapageIds: [Int]
    private let allIdsSeed: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    let onFilterChange: () -> Void

    @State private var isAutoPlaying = false
    @State private var currentWordIndex = -1
    @State private var vbSettings: VBSettingAttributes?
    @State private var pendingAutoplayAfterLoad = false

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
        self.allIdsSeed = allVocapageIds
    }

    private var currentVocapage: Vocapage? {
        guard !vocapageIds.isEmpty, currentPageIndex < vocapageIds.count else { return nil }
        return loader.page(id: vocapageIds[currentPageIndex], dueOnly: isShowingDueWordsOnly)
    }
    
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        ZStack {
            if vocapageIds.isEmpty {
                emptyStateView
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
        .toolbar { navigationToolbarItems }
        .safeAreaInset(edge: .bottom) { bottomToolbar }
        .toolbar(.hidden, for: .tabBar)
        // 👇 ADD THIS .TASK MODIFIER to proactively load the first page
        .task {
            guard !vocapageIds.isEmpty else { return }
            let initialPageId = vocapageIds[currentPageIndex]
            await loader.loadPage(withId: initialPageId, dueWordsOnly: isShowingDueWordsOnly)
        }
        .onChange(of: currentPageIndex, perform: handlePageChange)
        .onChange(of: sortedFlashcardsForCurrentPage, perform: handleCardsLoadedForAutoplay)
        .sheet(item: $selectedCard) { card in
            wordDetailSheet(for: card)
        }
        .onDisappear { stopAutoplay() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active { stopAutoplay() }
        }
        .onChange(of: isShowingDueWordsOnly, perform: handleFilterChange)
    }
    
    // MARK: - Subviews & Logic
    
    private var emptyStateView: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
            VStack {
                Spacer()
                Text("No words to show.")
                    .foregroundColor(.secondary)
                    .font(.headline)
                Text(isShowingDueWordsOnly ? "You have no words due for review." : "Add some words to your vocabook to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbarItems: some ToolbarContent {
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

    @ViewBuilder
    private func wordDetailSheet(for card: Flashcard) -> some View {
        let cards = sortedFlashcardsForCurrentPage
        let idx = cards.firstIndex(where: { $0.id == card.id }) ?? 0

        WordDetailSheet(
            cards: cards,
            initialIndex: idx,
            showBaseText: showBaseText,
            onClose: { self.selectedCard = nil },
            onSpeak: speakOnce,
            onDelete: { cardId in
                await deleteCardAndRefresh(cardId: cardId)
            }
        )
        .presentationDetents([.fraction(0.65)])
        .presentationDragIndicator(.visible)
    }
    
    private func deleteCardAndRefresh(cardId: Int) async {
        logger.debug("--- Start Deletion Process for cardId: \(cardId) ---")
        self.selectedCard = nil
        
        do {
            try await DataServices.shared.flashcardService.deleteFlashcard(cardId: cardId)
            logger.debug("✅ Service deletion successful.")
            let oldPageCount = vocapageIds.count
            let newIds = await rebuildAllPageIds()
            logger.debug("🔄 Page IDs rebuilt. Old count: \(oldPageCount), New count: \(newIds.count)")
            self.vocapageIds = newIds
            
            if currentPageIndex >= newIds.count {
                currentPageIndex = max(0, newIds.count - 1)
                logger.debug("Adjusted page index to: \(self.currentPageIndex)")
            }
            
            if !newIds.isEmpty {
                let pageToReload = newIds[currentPageIndex]
                logger.debug("⚡️ Forcing reload of page ID: \(pageToReload)...")
                await loader.forceReloadPage(withId: newIds[currentPageIndex], dueWordsOnly: isShowingDueWordsOnly)
                logger.debug("✅ Page reload complete.")
            } else {
                logger.debug("No pages left, skipping reload.")
            }
            
        } catch {
            print("Failed to delete card: \(error.localizedDescription)")
        }
        logger.debug("--- End Deletion Process ---")
    }
    
    private func speakOnce(card: Flashcard, completion: @escaping () -> Void) {
        Task {
            if self.vbSettings == nil {
                self.vbSettings = try? await DataServices.shared.settingsService.fetchVBSetting().attributes
            }
            if let settings = self.vbSettings {
                self.speechManager.stop()
                self.speechManager.speak(card: card, showBaseText: self.showBaseText, settings: settings, onComplete: completion)
            } else {
                completion()
            }
        }
    }
    
    private func handlePageChange(newIndex: Int) {
        if readingMode != .cycleAll { stopAutoplay() }
        if newIndex >= 0, newIndex < vocapageIds.count {
            UserDefaults.standard.set(vocapageIds[newIndex], forKey: "lastViewedVocapageID")
        }
    }

    private func handleCardsLoadedForAutoplay(newCards: [Flashcard]) {
        guard pendingAutoplayAfterLoad, readingMode == .cycleAll, isAutoPlaying, !newCards.isEmpty else { return }
        pendingAutoplayAfterLoad = false
        if currentWordIndex >= newCards.count { currentWordIndex = max(0, newCards.count - 1) }
        DispatchQueue.main.async { playCurrent() }
    }

    private func handleFilterChange(newValue: Bool) {
        Task {
            if !vocapageIds.isEmpty, currentPageIndex < vocapageIds.count {
                await loader.loadPage(withId: vocapageIds[currentPageIndex], dueWordsOnly: newValue)
            }
    
            if newValue {
                await withTaskGroup(of: Void.self) { group in
                    for id in allIdsSeed { group.addTask { await loader.loadPage(withId: id, dueWordsOnly: true) } }
                }
                let filtered = allIdsSeed.filter { !(loader.page(id: $0, dueOnly: true)?.flashcards?.isEmpty ?? true) }
    
                if filtered.isEmpty {
                    vocapageIds = []
                    currentPageIndex = 0
                    stopAutoplay()
                } else {
                    let currentId = (currentPageIndex < vocapageIds.count) ? vocapageIds[currentPageIndex] : filtered.first!
                    vocapageIds = filtered
                    currentPageIndex = vocapageIds.firstIndex(of: currentId) ?? 0
                }
            } else {
                let freshIds = await rebuildAllPageIds()
                vocapageIds = freshIds
                currentPageIndex = min(currentPageIndex, max(0, freshIds.count - 1))
                if !vocapageIds.isEmpty {
                    await loader.loadPage(withId: vocapageIds[currentPageIndex], dueWordsOnly: false)
                }
            }
        }
    }
    
    private func rebuildAllPageIds() async -> [Int] {
        logger.debug("Rebuilding all page IDs...")
        do {
            let vb = try await DataServices.shared.settingsService.fetchVBSetting()
            let pageSize = vb.attributes.wordsPerPage
            let all = try await DataServices.shared.flashcardService.fetchAllMyFlashcards()
            logger.debug("Found \(all.count) total flashcards to calculate pages.")
            let pageCount = all.isEmpty ? 0 : Int(ceil(Double(all.count) / Double(pageSize)))
            guard pageCount > 0 else {
                logger.debug("Page count is 0. Returning empty ID list.")
                return []
            }
            let ids = Array(1...pageCount)
            logger.debug("Calculated \(ids.count) pages.")

            return Array(1...pageCount)
        } catch {
            logger.error("❌ Failed to rebuild page IDs: \(error.localizedDescription)")
           return []
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
                    if !isShowingDueWordsOnly { isShowingDueWordsOnly = true; onFilterChange() }
                } label: {
                    Label("Due Only", systemImage: isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    if isShowingDueWordsOnly { isShowingDueWordsOnly = false; onFilterChange() }
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
        speechManager.speak(card: cards[currentWordIndex], showBaseText: showBaseText, settings: settings, onComplete: onOneWordFinished)
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
