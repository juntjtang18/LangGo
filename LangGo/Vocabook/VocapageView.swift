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

    init(allVocapageIds: [Int], selectedVocapageId: Int, modelContext: ModelContext, strapiService: StrapiService) {
        self.allVocapageIds = allVocapageIds
        _currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        _loader = StateObject(wrappedValue: VocapageLoader(modelContext: modelContext, strapiService: strapiService))
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
                onDismiss: { dismiss() }
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) {
            speechManager.stopReadingSession()
        }
        .sheet(isPresented: $isShowingExamView) {
            if let vocapage = currentVocapage {
                ExamView(flashcards: vocapage.flashcards ?? [], strapiService: loader.strapiService)
            }
        }
    }
}

// MARK: - Extracted Subviews for Simplicity

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
            VocapageBottomBarView(
                sortedFlashcards: sortedFlashcards,
                showBaseText: showBaseText,
                isShowingExamView: $isShowingExamView,
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

// A new view to display an icon based on the review tier.
private struct TierIconView: View {
    let tier: String?

    var body: some View {
        Group {
            switch tier {
            case "new":
                Image(systemName: "sparkle")
                    .foregroundColor(.cyan)
            case "warmup":
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
            case "weekly":
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
            case "monthly":
                Image(systemName: "calendar.circle.fill")
                    .foregroundColor(.purple)
            case "remembered":
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            default:
                // Provides a transparent placeholder to maintain alignment
                Image(systemName: "circle")
                    .opacity(0)
            }
        }
        .font(.subheadline)
        .frame(width: 20, alignment: .center) // Ensures consistent width for all icons
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

private struct VocapageBottomBarView: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    @Binding var isShowingExamView: Bool
    @ObservedObject var speechManager: SpeechManager
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var appEnvironment: AppEnvironment

    var body: some View {
        HStack {
            Spacer()
            
            Button(action: {
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
            }) {
                Image(systemName: speechManager.isSpeaking ? "stop.fill" : "play.fill")
                    .font(.title)
            }
            .tint(.blue)
            .disabled(sortedFlashcards.isEmpty)
            
            Spacer()
            
            Rectangle()
                .frame(width: 50, height: 50)
                .hidden()
            
            Spacer()
            
            Button(action: { isShowingExamView = true }) {
                Image(systemName: "graduationcap.fill")
                    .font(.title)
            }
            .tint(.blue)
            .disabled(sortedFlashcards.isEmpty)
            
            Spacer()
        }
        .padding()
    }
}
