import SwiftUI
import SwiftData
import AVFoundation
import os // For logging

// MARK: - VocapageHostView (REVISED)
struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var loader: VocapageLoader
    
    // Use @AppStorage to automatically save the user's preference
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    
    @State private var isShowingExamView: Bool = false
    @StateObject private var speechManager = SpeechManager()
    
    let allVocapageIds: [Int]
    @State private var currentPageIndex: Int

    // New properties to handle global actions
    let flashcardViewModel: FlashcardViewModel
    @State private var isShowingReviewView: Bool = false

    init(allVocapageIds: [Int], selectedVocapageId: Int, modelContext: ModelContext, strapiService: StrapiService, flashcardViewModel: FlashcardViewModel) {
        self.allVocapageIds = allVocapageIds
        _currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        _loader = StateObject(wrappedValue: VocapageLoader(modelContext: modelContext, strapiService: strapiService))
        self.flashcardViewModel = flashcardViewModel
    }

    private var currentVocapage: Vocapage? {
        guard !allVocapageIds.isEmpty else { return nil }
        let currentId = allVocapageIds[currentPageIndex]
        return loader.vocapages[currentId]
    }
    
    // REFACTORED: Sort the list once here.
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        return currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        // REFACTORED: The main view is now a scaffold for the subviews.
        VocapagePagingView(
            currentPageIndex: $currentPageIndex,
            allVocapageIds: allVocapageIds,
            loader: loader,
            showBaseText: $showBaseText,
            speechManager: speechManager
        )
        .navigationTitle("My Vocabulary Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            VocapageToolbar(
                showBaseText: $showBaseText,
                isShowingExamView: $isShowingExamView,
                sortedFlashcards: sortedFlashcardsForCurrentPage,
                speechManager: speechManager,
                onDismiss: { dismiss() },
                isShowingReviewView: $isShowingReviewView
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) {
            speechManager.stopReadingSession()
        }
        .sheet(isPresented: $isShowingExamView) {
            if let vocapage = currentVocapage, let flashcards = vocapage.flashcards, !flashcards.isEmpty {
                ExamView(flashcards: flashcards, strapiService: loader.strapiService)
            }
        }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(
                cardsToReview: sortedFlashcardsForCurrentPage,
                viewModel: flashcardViewModel
            )
        }
    }
}

// MARK: - Extracted Subviews for Simplicity

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
    @EnvironmentObject var appEnvironment: AppEnvironment

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
                            let settings = try await appEnvironment.strapiService.fetchVBSetting()
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
                            await loader.loadPage(withId: allVocapageIds[index])
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
            VocapageActionButtons(
                sortedFlashcards: sortedFlashcards,
                showBaseText: showBaseText,
                isShowingExamView: $isShowingExamView,
                isShowingReviewView: $isShowingReviewView,
                speechManager: speechManager
            )
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
            ProgressView()
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List {
                    Section(header: Color.clear.frame(height: 10)) {
                        ForEach(sortedFlashcards.enumerated().map { (index, card) in (index, card) }, id: \.1.id) { index, card in
                            HStack(spacing: 8) { // Adjusted spacing
                                // ADDED: Tier icon is displayed here
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
                .onChange(of: speechManager.currentIndex) { _, newIndex in
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
