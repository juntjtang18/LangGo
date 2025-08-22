// LangGo/Vocabook/VocapageView.swift
import SwiftUI

struct VocapageView: View {
    let vocapage: Vocapage?
    @Binding var showBaseText: Bool
    /// Index of the currently reading item for highlight/scroll.
    let highlightIndex: Int
    let onLoad: () -> Void
    let onSelectCard: (Flashcard) -> Void      // <-- add this

    private var sortedFlashcards: [Flashcard] {
        vocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

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
                        onSelectCard: onSelectCard              // <-- pass down
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
}

private struct VocapageContentListView: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    let highlightIndex: Int
    let onSelectCard: (Flashcard) -> Void      // <-- add this

    var body: some View {
        if sortedFlashcards.isEmpty {
            Spacer()
            Text("No words to show for this page.")
                .foregroundColor(.secondary)
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
                            .background(highlightIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                            // 👇 make the whole row tappable
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
                            proxy.scrollTo(cardIdToScroll, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}
