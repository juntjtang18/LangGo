// LangGo/Vocabook/NewWordInputVew.swift
import SwiftUI
import Combine
import os
import AVFoundation

struct NewWordInputView: View {
    // MARK: - Environment & View Model
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FlashcardViewModel
    @StateObject private var session = UserSessionManager.shared

    // MARK: - State (Source of Truth)
    @State private var word: String = ""
    @State private var baseText: String = ""
    @State private var partOfSpeech: PartOfSpeech? = nil
    @AppStorage("newWordInputDirection") private var inputDirection: InputDirection = .targetToBase
    //@State private var isTranslationStale: Bool = true
    
    @State private var isLoading: Bool = false
    @State private var isTranslating: Bool = false
    @State private var isLearningWord: Bool = false
    
    @State private var searchResults: [StrapiWordDefinition] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    
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

    private var baseLanguageCode: String {
        session.currentUser?.user_profile?.baseLanguage ?? "en"
    }
    private var targetLanguageCode: String { Config.learningTargetLanguageCode }
    private var baseLanguageName: String { languageName(for: baseLanguageCode) }
    private var targetLanguageName: String { languageName(for: targetLanguageCode) }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
                
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
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack { Image(systemName: "chevron.left"); Text("Back") }
                    }
                }
            }
            /*
            .sheet(isPresented: $isTranslating) {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Translating...")
                        .font(.headline)
                }
                .presentationDetents([.height(150)])
                .interactiveDismissDisabled(true)
            }*/
        }
    }

    private var mainContent: some View {
        // MARK: - Removed background tap gesture to resolve conflict with picker.
        VStack {
            Form {
                NewWordFormView(
                    isTranslating: $isTranslating, // <-- Add this line
                    word: $word,
                    baseText: $baseText,
                    partOfSpeech: $partOfSpeech,
                    inputDirection: $inputDirection,
                    searchResults: $searchResults,
                    isSearching: $isSearching,
                    //isTranslationStale: $isTranslationStale,
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
            //.onChange(of: word, perform: { _ in
            //    isTranslationStale = true
            //})
            // MARK: - Added toolbar with a keyboard close icon to dismiss keyboard
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        hideKeyboard()
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.title2)
                    }
                }
            }
            
            actionButtons
        }
        .padding(.bottom, 10)
    }

    // MARK: - Subviews
    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button(action: translateWord) {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isTranslating ? "" : "Translate")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Capsule().fill(Color.blue))
                .foregroundColor(.white)
                .font(.headline)
                .opacity(word.isEmpty || isLoading ? 0.5 : 1.0) // Removed isTranslating from here to keep it opaque while loading
            }
            .disabled(word.isEmpty || isTranslating || isLoading)
            
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
                         //|| isLoading || isTranslating || isTranslationStale ? 0.5 : 1.0)
            }
            .disabled(isLoading
                      || word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || isTranslating )
                      //|| isTranslationStale)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Logic & Actions
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
            return
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func speakTop() {
        let isBaseAtTop = (inputDirection == .baseToTarget)
        speak(text: word, languageCode: isBaseAtTop ? baseLanguageCode : targetLanguageCode)
    }

    private func speakBottom() {
        let isBaseAtBottom = (inputDirection != .baseToTarget)
        speak(text: baseText, languageCode: isBaseAtBottom ? baseLanguageCode : targetLanguageCode)
    }

    private func learnThisWord(_ def: StrapiWordDefinition) {
        guard !isLearningWord else { return }
        isLearningWord = true
        Task {
            do {
                let a = def.attributes
                let posDisplay = a.partOfSpeech?.data?.attributes.name ?? "noun"
                let posRawValue = PartOfSpeech.allCases.first(where: { $0.displayName == posDisplay })?.rawValue ?? "noun"

                try await viewModel.saveNewWord(
                    targetText: a.word?.data?.attributes.targetText ?? "",
                    baseText: a.baseText ?? "",
                    partOfSpeech: posRawValue,
                    locale: baseLanguageCode
                )
                word = ""
                baseText = ""
                searchResults = []
                partOfSpeech = nil
                //isTranslationStale = true
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
        LanguageSettings.availableLanguages.first(where: { $0.id == code })?.name ?? code.uppercased()
    }
    
    private func swapLanguages() {
        withAnimation {
            inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
            (word, baseText) = (baseText, word) // Swaps the text
            searchResults = []; searchTask?.cancel() // Still clears old search results
            //isTranslationStale = true
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
                    partOfSpeech: partOfSpeech?.rawValue ?? "",
                    locale: baseLanguageCode
                )
                word = ""
                baseText = ""
                partOfSpeech = nil
                //isTranslationStale = true
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
                let response = try await viewModel.translateWord(
                    word: sourceText,
                    source: sourceCode,
                    target: targetCode
                )
                self.baseText = response.translation
                
                if !response.partOfSpeech.contains(",") {
                    if let newPartOfSpeech = PartOfSpeech(rawValue: response.partOfSpeech.trimmingCharacters(in: .whitespaces).lowercased()) {
                        self.partOfSpeech = newPartOfSpeech
                    }
                }
                
                //self.isTranslationStale = false
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
            hideKeyboard()
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
