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
    
    @FocusState.Binding var focusedField: NewWordInputView.Field?
    
    // MARK: - View Configuration
    let baseLanguageName: String
    let targetLanguageName: String

    // MARK: - Actions
    let onDebouncedSearch: (String, Bool) -> Void
    let onTranslate: () -> Void
    let onSwap: () -> Void
    let onLearnThis: (SearchResult) -> Void
    
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
                .focused($focusedField, equals: .top)
                .onChange(of: word) { onDebouncedSearch($0, true) }
            
            if isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            
            ForEach(searchResults) { result in
                searchResultRow(for: result)
            }
        }
        
        actionButtonsSection
        
        Section("Target (\(targetLanguageName))") {
            TextField("Enter target word", text: $baseText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .bottom)
                .onChange(of: baseText) { onDebouncedSearch($0, false) }
        }
    }
    
    @ViewBuilder
    private var targetToBaseSections: some View {
        Section("Target (\(targetLanguageName))") {
            TextField("Enter target word", text: $word)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .top)
                .onChange(of: word) { onDebouncedSearch($0, false) }
            
            if isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            ForEach(searchResults) { result in
                searchResultRow(for: result)
            }
        }
        
        actionButtonsSection

        Section("Base (\(baseLanguageName))") {
            TextField("Enter base word", text: $baseText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .bottom)
                .onChange(of: baseText) { onDebouncedSearch($0, true) }
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
    
    private func searchResultRow(for result: SearchResult) -> some View {
        HStack {
            let posText = (result.partOfSpeech != "N/A" && !result.partOfSpeech.isEmpty) ? "(\(result.partOfSpeech.lowercased()))" : ""
            
            Text("\(result.targetText) ") + Text(posText).foregroundColor(.secondary) + Text(" \(result.baseText)")
            
            Spacer()

            if result.isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            } else {
                Button("Learn This") {
                    onLearnThis(result)
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(.vertical, 4)
        // REMOVED: .contentShape and .onTapGesture modifiers are no longer here.
    }
}
