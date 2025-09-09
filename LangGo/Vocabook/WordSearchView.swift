//
//  WordSearchView.swift
//  LangGo
//
//  Created by James Tang on 2025/9/7.
//
import SwiftUI

struct WordSearchView: View {
    @ObservedObject var vocabookVM: VocabookViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [StrapiWordDefinition] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var liveSearchTask: Task<Void, Never>? = nil    // ← debounce token

    @State private var selectedCard: Flashcard? = nil


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                List {
                    if let msg = errorMessage, !msg.isEmpty {
                        Text(msg).foregroundStyle(.red)
                    }
                    if isSearching {
                        HStack { ProgressView(); Text("Searching…") }
                    }
                    ForEach(results, id: \.id) { def in
                        let a = def.attributes
                        let target = a.word?.data?.attributes.targetText ?? ""
                        let base   = a.baseText ?? ""
                        let pos    = a.partOfSpeech?.data?.attributes.name ?? ""

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(target).font(.headline)
                            if !pos.isEmpty {
                                Text(pos)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                            if !base.isEmpty {
                                Text(base)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let card = makeCard(from: def) {
                                selectedCard = card // ✅ only real cards go into the sheet
                            } else {
                                // No flashcard yet for this definition => either ignore or prompt to learn
                                // e.g. showLearnPrompt = true
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: query) { newValue in
                liveSearchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count >= 2 else {
                    results = []; errorMessage = nil; isSearching = false
                    return
                }
                liveSearchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await runSearch(queryOverride: trimmed)
                }
            }
            .onDisappear { liveSearchTask?.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: .flashcardsDidChange)) { _ in
                // If the user currently has a valid query, refresh the list.
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else { return }
                liveSearchTask?.cancel()
                Task { await runSearch(queryOverride: trimmed) }
            }

            // ↓ NEW: detail sheet at ~2/3 height, with nav row hidden, single definition
            .sheet(item: $selectedCard) { card in
                WordDetailSheet(
                    cards: [card],
                    initialIndex: 0,
                    showBaseText: true,
                    showNavRow: false
                )
                .presentationDetents([.fraction(0.67)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .imageScale(.medium)
            TextField("Word or sentence", text: $query)
                .textInputAutocapitalization(.never)   // ✅ no auto-capitalization
                .autocorrectionDisabled(true)          // ✅ no autocorrect
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    errorMessage = nil
                    liveSearchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private func runSearch(queryOverride: String? = nil) async {
        let q = (queryOverride ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        isSearching = true; errorMessage = nil
        do {
            let r = try await vocabookVM.searchForWord(query: q, searchBase: false)
            await MainActor.run { results = r; isSearching = false }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; isSearching = false }
        }
    }
    
    private func makeCard(from def: StrapiWordDefinition) -> Flashcard? {
        guard let rel = def.attributes.flashcards?.data.first else { return nil }
        let a = rel.attributes
        return Flashcard(
            id: rel.id,                                        // ✅ real server id
            wordDefinition: def,
            lastReviewedAt: a.lastReviewedAt,
            correctStreak: a.correctStreak ?? 0,
            wrongStreak: a.wrongStreak ?? 0,
            isRemembered: a.isRemembered,
            reviewTire: a.reviewTire?.data?.attributes.tier
        )
    }

}
