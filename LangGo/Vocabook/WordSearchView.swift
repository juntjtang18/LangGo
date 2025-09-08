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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader             // ✅ custom header keeps toolbar intact
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
                                Text(pos).font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                            }
                            if !base.isEmpty {
                                Text(base).font(.body).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
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
            // Live search with debounce (same logic you had)
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
        }
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
}
