// LangGo/Vocabook/NewWordInputView.swift
import SwiftUI
import Combine
import os
import AVFoundation

struct NewWordInputView: View {
    // MARK: - Environment & View Model
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FlashcardViewModel
    @EnvironmentObject var languageSettings: LanguageSettings

    // MARK: - State (Source of Truth)
    @State private var word: String = ""
    @State private var baseText: String = ""
    // MODIFIED: Part of speech is now optional and defaults to nil.
    @State private var partOfSpeech: PartOfSpeech? = nil
    
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
    
    // Enum and State for managing focus
    enum Field: Hashable {
        case top, bottom
    }
    @FocusState private var focusedField: Field?
    
    // Speech Synthesizer
    @State private var synthesizer = AVSpeechSynthesizer()

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
            ZStack {
                VStack {
                    Form {
                        NewWordFormView(
                            word: $word,
                            baseText: $baseText,
                            partOfSpeech: $partOfSpeech,
                            inputDirection: $inputDirection,
                            searchResults: $searchResults,
                            isSearching: $isSearching,
                            focusedField: $focusedField,
                            baseLanguageName: baseLanguageName,
                            targetLanguageName: targetLanguageName,
                            onDebouncedSearch: debouncedSearch,
                            onTranslate: translateWord,
                            onSwap: swapLanguages,
                            onLearnThis: learnThisWord,
                            onSpeakTop: speakTop,
                            onSpeakBottom: speakBottom
                        )
                    }
                    .id(inputDirection)
                    .onAppear {
                        focusedField = .top
                    }
                    
                    saveButton
                }
                .padding(.bottom, 10)

                if showSuccessMessage || showErrorMessage {
                    FloatingMessageView(
                        isSuccess: showSuccessMessage,
                        message: showSuccessMessage ? "Word saved successfully!" : errorMessageText
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack { Image(systemName: "chevron.left"); Text("Back") }
                    }
                }
            }
            .sheet(isPresented: $isLearningWord) {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Saving...")
                        .font(.headline)
                }
                .presentationDetents([.height(150)])
                .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Subviews
    private var saveButton: some View {
        Button(action: saveWord) {
            HStack {
                if isLoading { ProgressView() }
                Text(isLoading ? "Saving..." : "Save")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Capsule().fill(Color.green))
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
    
    // MARK: - Logic & Actions
    
    private func speak(text: String, languageCode: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        if utterance.voice == nil {
            print("Error: The voice for language code '\(languageCode)' is not available on this device.")
            errorMessageText = "Speech for this language is not available."
            showErrorMessage = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showErrorMessage = false
            }
            return
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func speakTop() {
        let isBaseAtTop = (inputDirection == .baseToTarget)
        let textToSpeak = word
        let langCode = isBaseAtTop ? baseLanguageCode : targetLanguageCode
        speak(text: textToSpeak, languageCode: langCode)
    }

    private func speakBottom() {
        let isBaseAtBottom = (inputDirection != .baseToTarget)
        let textToSpeak = baseText
        let langCode = isBaseAtBottom ? baseLanguageCode : targetLanguageCode
        speak(text: textToSpeak, languageCode: langCode)
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
                
                word = ""
                baseText = ""
                searchResults = []
                // MODIFIED: Reset part of speech to nil
                partOfSpeech = nil
                focusedField = .top
                
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

    private func languageName(for code: String) -> String {
        languageSettings.availableLanguages.first(where: { $0.id == code })?.name ?? code.uppercased()
    }
    
    private func swapLanguages() {
        withAnimation {
            inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
            word = ""; baseText = ""; searchResults = []; searchTask?.cancel()
        }
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
                    // MODIFIED: Handle optional part of speech. Pass an empty string if nil.
                    partOfSpeech: partOfSpeech?.rawValue ?? ""
                )

                word = ""
                baseText = ""
                // MODIFIED: Reset part of speech to nil on successful save.
                partOfSpeech = nil
                withAnimation {
                    showSuccessMessage = true
                    showErrorMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                withAnimation {
                    showErrorMessage = true
                    showSuccessMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showErrorMessage = false }
                }
            }
            isTranslating = false
        }
    }
}


// MARK: - Floating Message View
private struct FloatingMessageView: View {
    let isSuccess: Bool
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding()
            .background(isSuccess ? Color.green : Color.red)
            .cornerRadius(12)
            .shadow(radius: 10)
    }
}


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
