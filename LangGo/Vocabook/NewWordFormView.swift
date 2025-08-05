//
//  NewWordFormView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/4.
//


// LangGo/Vocabook/NewWordFormView.swift
import SwiftUI

struct NewWordFormView: View {
    // MARK: - State Bindings
    @Binding var word: String
    @Binding var baseText: String
    @Binding var partOfSpeech: PartOfSpeech
    @Binding var inputDirection: NewWordInputView.InputDirection
    
    // MARK: - Search State Bindings
    @Binding var searchResults: [SearchResult]
    @Binding var isSearching: Bool
    
    // MARK: - View Configuration
    let baseLanguageName: String
    let targetLanguageName: String

    // MARK: - Actions
    let onDebouncedSearch: (String, Bool) -> Void
    let onTranslate: () -> Void
    let onSwap: () -> Void
    let onSelectSearchResult: (SearchResult) -> Void
    
    // MARK: - Body
    var body: some View {
        Group {
            if inputDirection == .baseToTarget {
                baseToTargetSections
            } else {
                targetToBaseSections
            }
            partOfSpeechSection
        }
    }
    
    // MARK: - Reusable Components
    @ViewBuilder
    private var baseToTargetSections: some View {
        Section("Base (\(baseLanguageName))") {
            TextField("Enter base word", text: $word)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: word) { newValue in onDebouncedSearch(newValue, true) }
            
            if isSearching { ProgressView() }
            else if !searchResults.isEmpty { searchResultsList }
        }
        
        actionButtonsSection
        
        Section("Target (\(targetLanguageName))") {
            TextField("Enter target word", text: $baseText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: baseText) { newValue in onDebouncedSearch(newValue, false) }
        }
    }
    
    @ViewBuilder
    private var targetToBaseSections: some View {
        Section("Target (\(targetLanguageName))") {
            TextField("Enter target word", text: $word)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: word) { newValue in onDebouncedSearch(newValue, false) }
            
            if isSearching { ProgressView() }
            else if !searchResults.isEmpty { searchResultsList }
        }
        
        actionButtonsSection

        Section("Base (\(baseLanguageName))") {
            TextField("Enter base word", text: $baseText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: baseText) { newValue in onDebouncedSearch(newValue, true) }
        }
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: onSwap) {
                VStack {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.largeTitle).foregroundColor(.white).frame(width: 60, height: 60)
                        .background(Color.accentColor).clipShape(Circle()).shadow(radius: 3)
                    Text("Swap").foregroundColor(.primary).font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())
            Spacer()
            Button(action: onTranslate) {
                VStack {
                    Image(systemName: "wand.and.stars")
                        .font(.largeTitle).foregroundColor(.white).frame(width: 60, height: 60)
                        .background(Color.accentColor).clipShape(Circle()).shadow(radius: 3)
                    Text("AI Translation").foregroundColor(.primary).font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
    }
    
    private var partOfSpeechSection: some View {
        Section("Part of Speech") {
            Picker("Select Part of Speech", selection: $partOfSpeech) {
                ForEach(PartOfSpeech.allCases) { pos in
                    Text(pos.displayName).tag(pos)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }
    
    private var searchResultsList: some View {
        List(searchResults) { result in
            HStack(spacing: 4) {
                // Main text for the word and its definition
                Text("\(result.word) -> \(result.definition)")

                // Conditionally display the part of speech in parentheses
                if result.partOfSpeech != "N/A" {
                    Text("(\(result.partOfSpeech.lowercased()))")
                        .foregroundColor(.secondary) // Use a secondary color for the POS
                }
                
                Spacer() // Pushes the content to the left
            }
            .font(.subheadline)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { onSelectSearchResult(result) }
        }
        .listStyle(.plain)
        .frame(maxHeight: 200)
    }
}
