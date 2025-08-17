// LangGo/Vocabook/VocapageView.swift
import SwiftUI

struct VocapageView: View {
    let vocapage: Vocapage?
    @Binding var showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager
    let onLoad: () -> Void

    private var sortedFlashcards: [Flashcard] {
        vocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
            
            VStack {
                // Use a computed property for isLoading
                if vocapage == nil {
                    ProgressView()
                } else if let vocapage = vocapage {
                    VocapageContentListView(
                        sortedFlashcards: sortedFlashcards,
                        showBaseText: showBaseText,
                        speechManager: speechManager
                    )
                    
                    Text("\(vocapage.order)")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 60) // Space for the toolbar
                    
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
