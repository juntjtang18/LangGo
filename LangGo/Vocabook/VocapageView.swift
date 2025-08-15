// LangGo/Vocabook/VocapageView.swift
import SwiftUI
import AVFoundation
import os // For logging

// MARK: - VocapageHostView
struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme: Theme
    
    @StateObject private var loader = VocapageLoader()
    
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    
    @State private var isShowingExamView: Bool = false
    @StateObject private var speechManager = SpeechManager()
    
    let originalAllVocapageIds: [Int]
    @State private var vocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    @State private var isShowingReviewView: Bool = false
    
    // MODIFICATION 1: Use @AppStorage to persist the filter state.
    @AppStorage("isShowingDueWordsOnly") private var isShowingDueWordsOnly: Bool = false

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
        return currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        ZStack {
            VocapagePagingView(
                currentPageIndex: $currentPageIndex,
                allVocapageIds: vocapageIds,
                loader: loader,
                showBaseText: $showBaseText,
                speechManager: speechManager,
                isShowingDueWordsOnly: isShowingDueWordsOnly
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
            VocapageToolbar(
                showBaseText: $showBaseText,
                isShowingExamView: $isShowingExamView,
                sortedFlashcards: sortedFlashcardsForCurrentPage,
                speechManager: speechManager,
                onDismiss: { dismiss() },
                isShowingReviewView: $isShowingReviewView,
                isShowingDueWordsOnly: $isShowingDueWordsOnly,
                onToggleDueWords: {
                    // This now toggles the @AppStorage variable, automatically saving the state.
                    isShowingDueWordsOnly.toggle()
                    Task {
                        await updatePageIdsForFilter()
                    }
                }
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) { _ in
            speechManager.stopReadingSession()
        }
        .sheet(isPresented: $isShowingExamView) {
            if let vocapage = currentVocapage, let flashcards = vocapage.flashcards, !flashcards.isEmpty {
                ExamView(flashcards: flashcards)
            }
        }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(
                cardsToReview: sortedFlashcardsForCurrentPage,
                viewModel: flashcardViewModel
            )
        }
        // MODIFICATION 2: Add a task to load the initial state when the view appears.
        .task {
            await updatePageIdsForFilter()
        }
    }
    
    // MODIFICATION 3: Create a reusable function to update the page list.
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
    }
}

// MARK: - Extracted Subviews for Simplicity

// NEW: A view for the overlay navigation controls (< >)
private struct PageNavigationControls: View {
    @Binding var currentPageIndex: Int
    let pageCount: Int

    var body: some View {
        HStack {
            // Previous Page Button
            Button(action: {
                withAnimation {
                    currentPageIndex = max(0, currentPageIndex - 1)
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title.weight(.bold))
            }
            .buttonStyle(PageNavigationButtonStyle())
            .opacity(currentPageIndex > 0 ? 1.0 : 0.0) // Hide when at the first page
            .disabled(currentPageIndex <= 0)

            Spacer()

            // Next Page Button
            Button(action: {
                withAnimation {
                    currentPageIndex = min(pageCount - 1, currentPageIndex + 1)
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title.weight(.bold))
            }
            .buttonStyle(PageNavigationButtonStyle())
            .opacity(currentPageIndex < pageCount - 1 ? 1.0 : 0.0) // Hide when at the last page
            .disabled(currentPageIndex >= pageCount - 1)
        }
        .padding(.horizontal)
    }
}

// NEW: A custom button style for the navigation controls for a consistent look.
private struct PageNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.black.opacity(configuration.isPressed ? 0.5 : 0.25))
            .foregroundColor(.white)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
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
    @Binding var isShowingExamView: Bool
    @Binding var isShowingReviewView: Bool
    @ObservedObject var speechManager: SpeechManager
    
    @EnvironmentObject var languageSettings: LanguageSettings
    private let strapiService = DataServices.shared.strapiService

    var body: some View {
        HStack(spacing: 12) {
            VocapageActionButton(icon: "square.stack.3d.up.fill") {
                isShowingReviewView = true
            }

            VocapageActionButton(icon: speechManager.isSpeaking ? "stop.circle.fill" : "headphones") {
                if speechManager.isSpeaking {
                    speechManager.stopReadingSession()
                } else {
                    Task {
                        do {
                            let settings = try await strapiService.fetchVBSetting()
                            if !sortedFlashcards.isEmpty {
                                speechManager.startReadingSession(
                                    flashcards: sortedFlashcards,
                                    showBaseText: showBaseText,
                                    languageSettings: languageSettings,
                                    settings: settings.attributes
                                )
                            }
                        } catch {
                            print("Failed to fetch vocabook settings: \(error)")
                        }
                    }
                }
            }

            VocapageActionButton(icon: "checkmark.circle.fill") {
                isShowingExamView = true
            }
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
    @ObservedObject var speechManager: SpeechManager
    let isShowingDueWordsOnly: Bool

    var body: some View {
        TabView(selection: $currentPageIndex) {
            ForEach(allVocapageIds.indices, id: \.self) { index in
                VocapageView(
                    vocapage: loader.vocapages[allVocapageIds[index]],
                    sortedFlashcards: loader.vocapages[allVocapageIds[index]]?.flashcards?.sorted { $0.id < $1.id } ?? [],
                    isLoading: loader.loadingStatus[allVocapageIds[index]] ?? false,
                    errorMessage: loader.errorMessages[allVocapageIds[index]],
                    showBaseText: $showBaseText,
                    speechManager: speechManager,
                    onLoad: {
                        Task {
                            await loader.loadPage(withId: allVocapageIds[index], dueWordsOnly: isShowingDueWordsOnly)
                        }
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct VocapageToolbar: ToolbarContent {
    @Binding var showBaseText: Bool
    @Binding var isShowingExamView: Bool
    let sortedFlashcards: [Flashcard]
    @ObservedObject var speechManager: SpeechManager
    var onDismiss: () -> Void
    @Binding var isShowingReviewView: Bool
    @Binding var isShowingDueWordsOnly: Bool
    var onToggleDueWords: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: onDismiss) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
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
                    isShowingExamView: $isShowingExamView,
                    isShowingReviewView: $isShowingReviewView,
                    speechManager: speechManager
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

struct VocapageView: View {
    let vocapage: Vocapage?
    let sortedFlashcards: [Flashcard]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager
    let onLoad: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
            
            VStack {
                if isLoading {
                    ProgressView()
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                        .multilineTextAlignment(.center)
                } else if let vocapage = vocapage {
                    VocapageContentListView(
                        sortedFlashcards: sortedFlashcards,
                        showBaseText: showBaseText,
                        speechManager: speechManager
                    )
                    
                    Text("\(vocapage.order)")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                } else {
                    Text("Swipe to load content.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            onLoad()
        }
    }
}

private struct VocapageContentListView: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager

    var body: some View {
        if sortedFlashcards.isEmpty {
            Spacer()
            if speechManager.isSpeaking {
                ProgressView()
            } else {
                Text("No words to show for this page.")
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List {
                    Section(header: Color.clear.frame(height: 10)) {
                        ForEach(sortedFlashcards.enumerated().map { (index, card) in (index, card) }, id: \.1.id) { index, card in
                            HStack(spacing: 8) {
                                TierIconView(tier: card.reviewTire)

                                Text(card.backContent)
                                    .font(.system(.title3, design: .serif))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if showBaseText {
                                    Text(card.frontContent)
                                        .font(.system(.body, design: .serif))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .id(card.id)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                            .background(speechManager.currentIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
                .onChange(of: speechManager.currentIndex) { newIndex in
                    if newIndex >= 0 && newIndex < sortedFlashcards.count {
                        let cardIdToScroll = sortedFlashcards[newIndex].id
                        withAnimation {
                            proxy.scrollTo(cardIdToScroll, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}
