//
//  ReadingMenuView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/18.
//

import SwiftUI

// MARK: - Helper Views

struct ReadingMenuView: View {
    let activeMode: ReadingMode
    var onRepeatWord: () -> Void
    var onCyclePage: () -> Void
    var onCycleAll: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 20) {
            // Word Repeat
            Button(action: onRepeatWord) {
                VStack(spacing: 6) {
                    Image(systemName: "repeat.1")
                    Text("Word Repeat")
                        .font(.caption2)
                }
                .foregroundColor(activeMode == .repeatWord ? theme.accent : theme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().frame(height: 32)

            // Cycle Page
            Button(action: onCyclePage) {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Cycle Page")
                        .font(.caption2)
                }
                .foregroundColor(activeMode == .cyclePage ? theme.accent : theme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().frame(height: 32)

            // Cycle All
            Button(action: onCycleAll) {
                VStack(spacing: 6) {
                    Image(systemName: "infinity")
                    Text("Cycle All")
                        .font(.caption2)
                }
                .foregroundColor(activeMode == .cycleAll ? theme.accent : theme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

struct FilterMenuView: View {
    let isDueOnly: Bool
    var onDueWords: () -> Void
    var onAllWords: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 24) {
            // Due Words
            Button(action: onDueWords) {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Due Words")
                        .font(.caption2)
                }
            }
            .foregroundColor(isDueOnly ? theme.accent : theme.text)
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Divider().frame(height: 32)

            // All Words
            Button(action: onAllWords) {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                    Text("All Words")
                        .font(.caption2)
                }
            }
            .foregroundColor(!isDueOnly ? theme.accent : theme.text)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .shadow(radius: 5)
        )
        .transition(.scale.animation(.spring(response: 0.4, dampingFraction: 0.6)))
    }
}

struct PageNavigationControls: View {
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

struct PageNavigationButtonStyle: ButtonStyle {
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

struct VocapageActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.accent)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(theme.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VocapageActionButtons: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    @Binding var isShowingReviewView: Bool

    // Replaced direct SpeechManager control with simple play/pause signal from host.
    let isAutoPlaying: Bool
    let onPlayPauseTapped: () -> Void

    @Binding var showReadingMenu: Bool
    @Binding var showFilterMenu: Bool             // NEW
    @Environment(\.theme) var theme: Theme
    let isShowingDueWordsOnly: Bool
    let onToggleDueWords: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            /*
            VocapageActionButton(icon: "square.stack.3d.up.fill", label: "Review") {
                isShowingReviewView = true
            }
            */

            VocapageActionButton(icon: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill", label: "Play") {
                onPlayPauseTapped()
            }

            // Gear (reading menu)
            VocapageActionButton(icon: "gearshape.fill", label: "Repeat") {
                showReadingMenu.toggle()
                if showReadingMenu { showFilterMenu = false }
            }
            .background( // publish from outside the button label (stable in toolbar)
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: GearFrameKey.self,
                                    value: proxy.frame(in: .global))
                }
            )

            // Filter (due/all) menu
            VocapageActionButton(
                icon: isShowingDueWordsOnly
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
                label: "All Words"
            ) {
                showFilterMenu.toggle()
                if showFilterMenu { showReadingMenu = false }
            }
            .background( // publish the 3rd button's frame
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: FilterFrameKey.self,
                                    value: proxy.frame(in: .global))
                }
            )
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct VocapagePagingView: View {
    @Binding var currentPageIndex: Int
    let allVocapageIds: [Int]
    @ObservedObject var loader: VocapageLoader
    @Binding var showBaseText: Bool
    let highlightIndex: Int
    let isShowingDueWordsOnly: Bool
    let onSelectCard: (Flashcard) -> Void

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
                    onSelectCard: onSelectCard
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

struct VocapageToolbar: ToolbarContent {
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
    @Binding var showFilterMenu: Bool             // NEW

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
                    showReadingMenu: $showReadingMenu,
                    showFilterMenu: $showFilterMenu,   // NEW
                    isShowingDueWordsOnly: isShowingDueWordsOnly,
                    onToggleDueWords: onToggleDueWords
                )
            }
        }
    }
}

// MARK: - Preference Keys

struct GearFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct FilterFrameKey: PreferenceKey {   // NEW
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
