import SwiftUI
import CoreData // THIS LINE FIXES THE ERROR
import AVFoundation
import os // For logging

// MARK: - VocapageHostView (REVISED)
struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var loader: VocapageLoader
    
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    
    @State private var isShowingExamView: Bool = false
    @StateObject private var speechManager = SpeechManager()
    
    let allVocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    @State private var isShowingReviewView: Bool = false

    init(allVocapageIds: [Int], selectedVocapageId: Int, managedObjectContext: NSManagedObjectContext, strapiService: StrapiService, flashcardViewModel: FlashcardViewModel) {
        self.allVocapageIds = allVocapageIds
        _currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        _loader = StateObject(wrappedValue: VocapageLoader(managedObjectContext: managedObjectContext, strapiService: strapiService))
        self.flashcardViewModel = flashcardViewModel
    }

    private var currentVocapage: Vocapage? {
        guard !allVocapageIds.isEmpty, currentPageIndex < allVocapageIds.count else { return nil }
        let currentId = allVocapageIds[currentPageIndex]
        return loader.vocapages[currentId]
    }
    
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        let flashcardSet = currentVocapage?.flashcards as? Set<Flashcard> ?? []
        return Array(flashcardSet).sorted { $0.id < $1.id }
    }

    var body: some View {
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
            // --- FIX 1: Toolbar Ambiguity ---
            // The navigation bar items remain here.
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
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
        }
        // The bottom bar is moved to a safeAreaInset to resolve the ambiguity.
        .safeAreaInset(edge: .bottom) {
            VocapageActionButtons(
                sortedFlashcards: sortedFlashcardsForCurrentPage,
                showBaseText: showBaseText,
                isShowingExamView: $isShowingExamView,
                isShowingReviewView: $isShowingReviewView,
                speechManager: speechManager
            )
            .padding(.top, 8) // Add some padding
            .background(.thinMaterial)
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) { _ in
            speechManager.stopReadingSession()
        }
        .sheet(isPresented: $isShowingExamView) {
            if let vocapage = currentVocapage, let flashcards = vocapage.flashcards?.allObjects as? [Flashcard], !flashcards.isEmpty {
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
                // --- FIX 2: Type-checking timeout ---
                // The complex expression is broken down to help the compiler.
                let vocapageId = allVocapageIds[index]
                let vocapage = loader.vocapages[vocapageId]
                let flashcardSet = vocapage?.flashcards as? Set<Flashcard> ?? []
                let sortedFlashcards = Array(flashcardSet).sorted { $0.id < $1.id }
                
                VocapageView(
                    vocapage: vocapage,
                    sortedFlashcards: sortedFlashcards,
                    isLoading: loader.loadingStatus[vocapageId] ?? false,
                    errorMessage: loader.errorMessages[vocapageId],
                    showBaseText: $showBaseText,
                    speechManager: speechManager,
                    onLoad: {
                        Task {
                            await loader.loadPage(withId: vocapageId)
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
                        // --- FIX 3: Type-checking timeout ---
                        // The ForEach loop is simplified to be more explicit.
                        ForEach(Array(sortedFlashcards.enumerated()), id: \.element.id) { index, card in
                            HStack(spacing: 8) {
                                TierIconView(tier: card.reviewTire)
                                Text(card.backContent ?? "N/A")
                                    .font(.system(.title3, design: .serif))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if showBaseText {
                                    Text(card.frontContent ?? "N/A")
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
