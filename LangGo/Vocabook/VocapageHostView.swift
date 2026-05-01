// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import Combine
import os

struct VocapageHostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme: Theme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: VocapageViewModel
    @StateObject private var speechManager = SpeechManager()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageHostView")

    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    @AppStorage("readingMode") private var readingMode: ReadingMode = .cyclePage

    @Binding var isShowingDueWordsOnly: Bool

    private let reviewTier: String?
    private let allowsDueFilter: Bool
    private let recentlyAddedLimit: Int

    let flashcardViewModel: FlashcardViewModel
    let onFilterChange: () -> Void

    @State private var isAutoPlaying = false
    @State private var currentWordIndex = -1
    @State private var vbSettings: VBSettingAttributes?
    @State private var pendingAutoplayAfterLoad = false

    @State private var selectedCard: Flashcard?
    @State private var isProcessingDeletion = false

    init(
        initialPage: Int = 1,
        flashcardViewModel: FlashcardViewModel,
        isShowingDueWordsOnly: Binding<Bool>,
        reviewTier: String? = nil,
        allowsDueFilter: Bool = true,
        recentlyAddedLimit: Int = 0,
        onFilterChange: @escaping () -> Void
    ) {
        self._viewModel = StateObject(
            wrappedValue: VocapageViewModel(
                initialPage: initialPage,
                dueOnly: allowsDueFilter ? isShowingDueWordsOnly.wrappedValue : false,
                reviewTier: reviewTier,
                recentlyAddedLimit: recentlyAddedLimit
            )
        )
        self.flashcardViewModel = flashcardViewModel
        self._isShowingDueWordsOnly = isShowingDueWordsOnly
        self.reviewTier = reviewTier
        self.allowsDueFilter = allowsDueFilter
        self.recentlyAddedLimit = recentlyAddedLimit
        self.onFilterChange = onFilterChange
    }

    private var currentVocapage: Vocapage? {
        guard !viewModel.currentPageCards.isEmpty else { return nil }
        return Vocapage(
            id: viewModel.currentPage,
            title: "Page \(viewModel.currentPage)",
            order: viewModel.currentPage,
            flashcards: viewModel.currentPageCards
        )
    }

    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        viewModel.currentPageCards.sorted { $0.id < $1.id }
    }

    var body: some View {
        ZStack {
            if viewModel.totalPages == 0 && !viewModel.isLoading {
                emptyStateView
            } else {
                VocapagePagingView(
                    vocapage: currentVocapage,
                    showBaseText: $showBaseText,
                    highlightIndex: speechManager.currentIndex,
                    onSelectCard: { card in
                        stopAutoplay()
                        selectedCard = card
                    }
                )

                PageNavigationControls(
                    currentPage: viewModel.currentPage,
                    totalPages: viewModel.totalPages,
                    onPrevious: {
                        Task {
                            _ = await viewModel.goPrevious()
                        }
                    },
                    onNext: {
                        Task {
                            _ = await viewModel.goNext()
                        }
                    }
                )
            }
        }
        .overlay {
            if isProcessingDeletion {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()

                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Updating...")
                            .font(.headline)
                            .padding(.top)
                    }
                    .padding(30)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
                    .shadow(radius: 10)
                }
                .transition(.opacity.animation(.easeInOut))
            }
        }
        .navigationTitle("My Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
            leading: Button {
                stopAutoplay()
                dismiss()
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Back"),
            trailing: Button {
                showBaseText.toggle()
            } label: {
                Image(systemName: showBaseText ? "text.badge.minus" : "text.badge.plus")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(showBaseText ? "Hide Base Text" : "Show Base Text")
        )
        .safeAreaInset(edge: .bottom) { bottomToolbar }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.loadInitialPage()
        }
        .onChange(of: viewModel.currentPage) { newPage in
            handlePageChange(newPage: newPage)
        }
        .onChange(of: sortedFlashcardsForCurrentPage, perform: handleCardsLoadedForAutoplay)
        .sheet(item: $selectedCard) { card in
            let cards = sortedFlashcardsForCurrentPage
            let idx = cards.firstIndex(where: { $0.id == card.id }) ?? 0

            WordDetailSheet(
                cards: cards,
                initialIndex: idx,
                showBaseText: showBaseText
            )
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flashcardDeleted)) { note in
            Task { @MainActor in
                guard let deletedId = note.object as? Int else { return }
                if selectedCard?.id == deletedId { selectedCard = nil }
                await refreshAfterExternalDeletion()
            }
        }
        .onDisappear { stopAutoplay() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active { stopAutoplay() }
        }
        .onChange(of: isShowingDueWordsOnly, perform: handleFilterChange)
    }

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

    private func refreshAfterExternalDeletion() async {
        isProcessingDeletion = true
        defer { isProcessingDeletion = false }
        await viewModel.loadPage(viewModel.currentPage)
    }

    private func deleteCardAndRefresh(cardId: Int) async {
        isProcessingDeletion = true
        defer { isProcessingDeletion = false }

        logger.debug("--- Start Deletion Process for cardId: \(cardId) ---")
        selectedCard = nil

        do {
            try await DataServices.shared.flashcardService.deleteFlashcard(cardId: cardId)
            logger.debug("✅ Service deletion successful.")
            await viewModel.loadPage(viewModel.currentPage)
            logger.debug("✅ Page reload complete.")
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

    private func handlePageChange(newPage: Int) {
        if readingMode != .cycleAll { stopAutoplay() }
        UserDefaults.standard.set(max(1, newPage), forKey: "lastViewedVocapageID")
    }

    private func handleCardsLoadedForAutoplay(newCards: [Flashcard]) {
        guard pendingAutoplayAfterLoad, readingMode == .cycleAll, isAutoPlaying, !newCards.isEmpty else { return }
        pendingAutoplayAfterLoad = false
        if currentWordIndex >= newCards.count { currentWordIndex = max(0, newCards.count - 1) }
        DispatchQueue.main.async { playCurrent() }
    }

    private func handleFilterChange(newValue: Bool) {
        guard allowsDueFilter else { return }
        Task {
            onFilterChange()
            await viewModel.updateDueOnly(newValue)
            if viewModel.totalPages == 0 {
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
                    if !isShowingDueWordsOnly { isShowingDueWordsOnly = true }
                } label: {
                    Label("Due Only", systemImage: isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    if isShowingDueWordsOnly { isShowingDueWordsOnly = false }
                } label: {
                    Label("All Words", systemImage: !isShowingDueWordsOnly ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.title3)
            }
            .accessibilityLabel("Filter")
            .opacity(allowsDueFilter ? 1 : 0)
            .allowsHitTesting(allowsDueFilter)
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
        let pageCount = viewModel.totalPages
        guard pageCount > 0 else { stopAutoplay(); return }
        let nextPage = viewModel.currentPage < pageCount ? (viewModel.currentPage + 1) : 1

        pendingAutoplayAfterLoad = true
        currentWordIndex = 0

        speechManager.stop()
        speechManager.currentIndex = 0

        Task {
            await viewModel.loadPage(nextPage)
        }
    }
}
