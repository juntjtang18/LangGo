// LangGo/Vocabook/VocapageHostView.swift
import SwiftUI
import AVFoundation
import os

struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme: Theme
    
    @StateObject private var loader = VocapageLoader()
    
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    
    @StateObject private var speechManager = SpeechManager()
    
    @State private var showReadingMenu: Bool = false
    
    let originalAllVocapageIds: [Int]
    @State private var vocapageIds: [Int]
    @State private var currentPageIndex: Int

    let flashcardViewModel: FlashcardViewModel
    @State private var isShowingReviewView: Bool = false
    
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
                sortedFlashcards: sortedFlashcardsForCurrentPage,
                speechManager: speechManager,
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
        .overlay(alignment: .bottom) {
            if showReadingMenu {
                HStack {
                    Spacer()
                    ReadingMenuView(
                        activeMode: speechManager.readingMode,
                        onRepeatWord: {
                            speechManager.readingMode = .repeatWord
                            showReadingMenu = false
                        },
                        onCyclePage: {
                            speechManager.readingMode = .cyclePage
                            showReadingMenu = false
                        },
                        onCycleAll: {
                            speechManager.readingMode = .cycleAll
                            showReadingMenu = false
                        }
                    )
                }
                .padding(.trailing, 20)
                .offset(y: -52)
            }
        }
        .onChange(of: currentPageIndex) { _ in
            speechManager.stopReadingSession()
        }
        .fullScreenCover(isPresented: $isShowingReviewView) {
            VocapageReviewView(
                cardsToReview: sortedFlashcardsForCurrentPage,
                viewModel: flashcardViewModel
            )
        }
        .task {
            await updatePageIdsForFilter()
        }
    }
    
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
            } catch { vocapageIds = [] }
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

private struct Callout: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pointerHeight: CGFloat = 8
        let pointerWidth: CGFloat = 16
        
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height - pointerHeight), cornerSize: CGSize(width: 12, height: 12))
        
        let pointerTip = CGPoint(x: rect.midX, y: rect.maxY)
        let pointerBaseLeft = CGPoint(x: rect.midX - (pointerWidth / 2), y: rect.maxY - pointerHeight)
        let pointerBaseRight = CGPoint(x: rect.midX + (pointerWidth / 2), y: rect.maxY - pointerHeight)
        
        path.move(to: pointerBaseLeft)
        path.addLine(to: pointerTip)
        path.addLine(to: pointerBaseRight)
        
        return path
    }
}

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
            Callout()
                .fill(.thinMaterial)
                .shadow(radius: 5)
        )
        .transition(.scale.animation(.spring(response: 0.4, dampingFraction: 0.6)))
    }
}

// MARK: - Subviews

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
    @ObservedObject var speechManager: SpeechManager
    @Binding var showReadingMenu: Bool
    private let strapiService = DataServices.shared.strapiService

    var body: some View {
        HStack(spacing: 12) {
            VocapageActionButton(icon: "square.stack.3d.up.fill") {
                isShowingReviewView = true
            }

            // --- MODIFICATION: The main play/pause button logic is corrected ---
            VocapageActionButton(icon: speechManager.isSpeaking ? "pause.circle.fill" : "play.circle.fill") {
                if speechManager.isSpeaking {
                    speechManager.pause()
                } else {
                    // Use currentIndex to determine if we should resume or start fresh.
                    if speechManager.currentIndex == -1 {
                        // Start a new session using the persistent reading mode
                        Task {
                            do {
                                let settings = try await strapiService.fetchVBSetting()
                                if !sortedFlashcards.isEmpty {
                                    speechManager.startReadingSession(
                                        flashcards: sortedFlashcards,
                                        mode: speechManager.readingMode, // Use the saved mode
                                        showBaseText: showBaseText,
                                        settings: settings.attributes
                                    )
                                }
                            } catch {
                                print("Failed to fetch vocabook settings: \(error)")
                            }
                        }
                    } else {
                        // If a session was paused, just resume it
                        speechManager.resume()
                    }
                }
            }

            VocapageActionButton(icon: "gearshape.fill") {
                showReadingMenu.toggle()
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
    let sortedFlashcards: [Flashcard]
    @ObservedObject var speechManager: SpeechManager
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
                    speechManager: speechManager,
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
