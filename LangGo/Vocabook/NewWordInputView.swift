// LangGo/Vocabook/NewWordInputView.swift
import SwiftUI
import Combine
import os

struct NewWordInputView: View {
    // MARK: - Environment & View Model
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FlashcardViewModel
    @EnvironmentObject var languageSettings: LanguageSettings

    // MARK: - State (Source of Truth)
    @State private var word: String = ""
    @State private var baseText: String = ""
    @State private var partOfSpeech: PartOfSpeech = .noun
    @State private var inputDirection: InputDirection = .baseToTarget
    
    // Asynchronous Operation State
    @State private var isLoading: Bool = false
    @State private var isTranslating: Bool = false
    @State private var isLearningWord: Bool = false
    
    // Search State
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    
    // User Feedback State
    @State private var showSuccessMessage: Bool = false
    @State private var showErrorMessage: Bool = false
    @State private var errorMessageText: String = ""
    
    // MARK: - Enums & Computed Properties
    enum InputDirection: String, CaseIterable, Identifiable {
        case baseToTarget = "Base → Target"
        case targetToBase = "Target → Base"
        var id: String { self.rawValue }
    }

    private var baseLanguageCode: String { languageSettings.selectedLanguageCode }
    private var targetLanguageCode: String { Config.learningTargetLanguageCode }
    private var baseLanguageName: String { languageName(for: baseLanguageCode) }
    private var targetLanguageName: String { languageName(for: targetLanguageCode) }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    NewWordFormView(
                        word: $word,
                        baseText: $baseText,
                        partOfSpeech: $partOfSpeech,
                        inputDirection: $inputDirection,
                        searchResults: $searchResults,
                        isSearching: $isSearching,
                        baseLanguageName: baseLanguageName,
                        targetLanguageName: targetLanguageName,
                        onDebouncedSearch: debouncedSearch,
                        onTranslate: translateWord,
                        onSwap: swapLanguages,
                        onSelectSearchResult: handleResultSelection,
                        onLearnThis: learnThisWord
                    )
                }
                .id(inputDirection)
                
                saveButton
                userFeedbackMessages
            }
            .padding(.bottom, 10)
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack { Image(systemName: "chevron.left"); Text("Back") }
                    }
                }
            }
        }
    }

    // MARK: - Subviews
    private var saveButton: some View {
        Button(action: saveWord) {
            HStack {
                if isLoading { ProgressView() }
                Text(isLoading ? "Saving..." : "Save Word")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Capsule().fill(Color.accentColor))
            .foregroundColor(.white)
            .font(.headline)
            .opacity(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     || baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     || isLoading || isTranslating ? 0.5 : 1.0)
        }
        .disabled(isLoading
                  || word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || isTranslating)
        .padding(.horizontal)
    }
    
    private var userFeedbackMessages: some View {
        VStack {
            if showSuccessMessage {
                Text("Word saved successfully!")
                    .font(.subheadline).padding().background(Color.green.opacity(0.9))
                    .foregroundColor(.white).cornerRadius(10).shadow(radius: 5).transition(.opacity)
            } else if showErrorMessage {
                Text(errorMessageText)
                    .font(.subheadline).padding().background(Color.red.opacity(0.9))
                    .foregroundColor(.white).cornerRadius(10).shadow(radius: 5).transition(.opacity)
            }
        }
        .frame(height: 100)
    }
    
    // MARK: - Logic & Actions
    private func languageName(for code: String) -> String {
        languageSettings.availableLanguages.first(where: { $0.id == code })?.name ?? code.uppercased()
    }
    
    private func swapLanguages() {
        withAnimation {
            inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
            word = ""; baseText = ""; searchResults = []; searchTask?.cancel()
        }
    }
    
    private func handleResultSelection(_ result: SearchResult) {
        if inputDirection == .baseToTarget {
            self.word = result.baseText
            self.baseText = result.targetText
        } else {
            self.word = result.targetText
            self.baseText = result.baseText
        }
        if let selectedPos = PartOfSpeech.allCases.first(where: { $0.displayName == result.partOfSpeech }) {
            self.partOfSpeech = selectedPos
        }
        self.searchResults = []; self.searchTask?.cancel()
    }
    
    private func debouncedSearch(term: String, searchBase: Bool) {
        searchTask?.cancel()
        
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        guard trimmedTerm.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        showErrorMessage = false
        
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // The ViewModel now performs the search and checks against existing cards.
                let results = try await viewModel.searchForWord(term: trimmedTerm, searchBase: searchBase)
                await MainActor.run { self.searchResults = results; self.isSearching = false }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    await MainActor.run { self.isSearching = false }
                } else {
                    await MainActor.run {
                        self.errorMessageText = "Search failed: \(error.localizedDescription)"
                        self.showErrorMessage = true
                        self.isSearching = false
                    }
                }
            }
        }
    }

    private func saveWord() {
        isLoading = true
        Task {
            do {
                let targetOut: String
                let baseOut: String

                if inputDirection == .baseToTarget {
                    baseOut   = word.trimmingCharacters(in: .whitespacesAndNewlines)
                    targetOut = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    targetOut = word.trimmingCharacters(in: .whitespacesAndNewlines)
                    baseOut   = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                try await viewModel.saveNewWord(
                    targetText: targetOut,
                    baseText: baseOut,
                    partOfSpeech: partOfSpeech.rawValue
                )

                word = ""
                baseText = ""
                partOfSpeech = .noun
                withAnimation {
                    showSuccessMessage = true
                    showErrorMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showSuccessMessage = false }
                }
                isLoading = false
            } catch {
                errorMessageText = "Failed to save word: \(error.localizedDescription)"
                withAnimation {
                    showErrorMessage = true
                    showSuccessMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showErrorMessage = false }
                }
                isLoading = false
            }
        }
    }
    
    private func learnThisWord(result: SearchResult) {
        guard !isLearningWord else { return }
        isLearningWord = true
        
        Task {
            do {
                let posRawValue = PartOfSpeech.allCases.first(where: { $0.displayName == result.partOfSpeech })?.rawValue ?? "noun"
                
                try await viewModel.saveNewWord(
                    targetText: result.targetText,
                    baseText: result.baseText,
                    partOfSpeech: posRawValue
                )
                
                // Update the specific item in searchResults to reflect it's been added
                if let index = searchResults.firstIndex(where: { $0.id == result.id }) {
                    searchResults[index] = SearchResult(
                        id: result.id,
                        wordDefinitionId: result.wordDefinitionId,
                        baseText: result.baseText,
                        targetText: result.targetText,
                        partOfSpeech: result.partOfSpeech,
                        isAlreadyAdded: true
                    )
                }
            } catch {
                errorMessageText = "Failed to add word: \(error.localizedDescription)"
                withAnimation { showErrorMessage = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showErrorMessage = false }
                }
            }
            isLearningWord = false
        }
    }

    private func translateWord() {
        isTranslating = true
        Task {
            do {
                let sourceCode = (inputDirection == .baseToTarget) ? baseLanguageCode : targetLanguageCode
                let targetCode = (inputDirection == .baseToTarget) ? targetLanguageCode : baseLanguageCode
                let sourceText = word.trimmingCharacters(in: .whitespacesAndNewlines)

                if sourceText.isEmpty || sourceCode == targetCode {
                    baseText = word
                    isTranslating = false
                    return
                }

                let translated = try await viewModel.translateWord(
                    word: sourceText,
                    source: sourceCode,
                    target: targetCode
                )
                self.baseText = translated
            } catch {
                errorMessageText = "Translation failed: \(error.localizedDescription)"
                withAnimation { showErrorMessage = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showErrorMessage = false }
                }
            }
            isTranslating = false
        }
    }
}

// The SearchResult struct is now canonical, making it easier to handle in the view.
struct SearchResult: Identifiable, Hashable {
    let id: String
    let wordDefinitionId: Int
    let baseText: String
    let targetText: String
    let partOfSpeech: String
    let isAlreadyAdded: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(wordDefinitionId)
    }
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.wordDefinitionId == rhs.wordDefinitionId
    }
}
