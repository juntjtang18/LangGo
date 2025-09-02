// LangGo/Vocabook/VocapageView.swift
import SwiftUI

struct VocapageView: View {
    let vocapage: Vocapage?
    @Binding var showBaseText: Bool

    // This property was removed as its state is better managed by the parent view.
    // @State private var selectedCardIndex: Int?

    /// Index of the currently reading item for highlight/scroll.
    let highlightIndex: Int
    let onLoad: () -> Void
    // ADDED: A closure that the parent view provides to handle a card tap.
    let onSelectCard: (Flashcard) -> Void

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()

            VStack {
                if vocapage == nil {
                    ProgressView()
                } else if let vocapage = vocapage {
                    VocapageContentListView(
                        sortedFlashcards: sortedFlashcards,
                        showBaseText: showBaseText,
                        highlightIndex: highlightIndex,
                        // PASSED DOWN: The onSelectCard closure is passed to the list view.
                        onSelectCard: onSelectCard
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let vocapage = vocapage {
                    Text("\(vocapage.order)")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
        .task { onLoad() }
    }

    private var sortedFlashcards: [Flashcard] {
        vocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    // This logic is also better managed by the parent view (e.g., VocapageHostView)
    // that presents the detail sheet.
    /*
    private var isShowingDetail: Binding<Bool> {
        Binding(
            get: { selectedCardIndex != nil },
            set: { if !$0 { selectedCardIndex = nil } }
        )
    }
    */
}

private struct VocapageContentListView: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    let highlightIndex: Int
    // ADDED: The view now accepts the onSelectCard closure.
    let onSelectCard: (Flashcard) -> Void

    var body: some View {
        if sortedFlashcards.isEmpty {
            Spacer()
            Text("No words to show for this page.")
                .foregroundColor(.secondary)
            Spacer()
        } else {
            ScrollViewReader { proxy in
                List {
                    // Using a clear header to add some top padding to the list content.
                    Section(header: Color.clear.frame(height: 10)) {
                        ForEach(sortedFlashcards.enumerated().map { $0 }, id: \.element.id) { index, card in
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
                            .background(highlightIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                            // ADDED: These modifiers make the entire row tappable.
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectCard(card) }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
                .onChange(of: highlightIndex) { newIndex in
                    if newIndex >= 0 && newIndex < sortedFlashcards.count {
                        let cardIdToScroll = sortedFlashcards[newIndex].id
                        withAnimation {
                            proxy.scrollTo(cardIdToScroll, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

