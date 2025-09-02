// LangGo/Vocabook/NewWordInputVew.swift
import SwiftUI
import Combine
import os
import AVFoundation

// FIX 1: Moved SearchResult outside the main view struct to make it accessible to NewWordFormView.
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

private struct ActionButtonStyle: ButtonStyle {
    var backgroundColor: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Capsule().fill(backgroundColor))
            .foregroundColor(.white)
            .font(.headline)
            .opacity(isEnabled ? 1.0 : 0.5) // Fades the button when disabled
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isEnabled)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

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
    
    enum ViewState: Equatable {
        case idle
        case searching
        case translating
        case saving
        case success
        case error(String)
        
        static func == (lhs: NewWordInputView.ViewState, rhs: NewWordInputView.ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.searching, .searching), (.translating, .translating),
                 (.saving, .saving), (.success, .success):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }
    @State private var viewState: ViewState = .idle
    
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    
    enum Field: Hashable { case top, bottom }
    @FocusState private var focusedField: Field?
    
    @State private var synthesizer = AVSpeechSynthesizer()

    // MARK: - Enums & Computed Properties
    enum InputDirection: String { case baseToTarget, targetToBase }

    private var baseLanguageCode: String { session.currentUser?.user_profile?.baseLanguage ?? "en" }
    private var targetLanguageCode: String { Config.learningTargetLanguageCode }
    private var baseLanguageName: String { languageName(for: baseLanguageCode) }
    private var targetLanguageName: String { languageName(for: targetLanguageCode) }

    private var isBusy: Bool {
        viewState != .idle && viewState != .success
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Add New Word")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button("Back") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(action: hideKeyboard) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                    }
                }
        }
    }

    private var mainContent: some View {
        VStack {
            // FIX 2: Wrapped Form in a Group before applying the .id() modifier.
            Group {
                Form {
                    NewWordFormView(
                        word: $word,
                        baseText: $baseText,
                        partOfSpeech: $partOfSpeech,
                        inputDirection: $inputDirection,
                        searchResults: $searchResults,
                        isSearching: .constant(viewState == .searching),
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
            }
            .id(inputDirection)
            .onAppear { focusedField = .top }

            actionButtons
        }
        .padding(.bottom, 10)
        .background(Color(UIColor.systemGroupedBackground)) // Match form background
        .onTapGesture {
            hideKeyboard()
        }
        .overlay {
            feedbackOverlay
        }
    }
    
    @ViewBuilder
    private var feedbackOverlay: some View {
        ZStack {
            if isBusy {
                Color.black.opacity(0.001)
            }
            
            switch viewState {
            case .translating:
                FeedbackPill(message: "Translating...", icon: nil, style: .loading)
            case .saving:
                FeedbackPill(message: "Saving...", icon: nil, style: .loading)
            case .success:
                FeedbackPill(message: "Saved Successfully!", icon: "checkmark.circle.fill", style: .success)
            case .error(let message):
                FeedbackPill(message: message, icon: "xmark.circle.fill", style: .error)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut, value: viewState)
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button("Translate", action: translateWord)
                .buttonStyle(ActionButtonStyle(backgroundColor: .blue))
                .disabled(word.trimmed.isEmpty || isBusy)

            Button("Save", action: saveWord)
                .buttonStyle(ActionButtonStyle(backgroundColor: .green))
                .disabled(word.trimmed.isEmpty || baseText.trimmed.isEmpty || isBusy)
        }
        .padding(.horizontal)
    }
    
    private func hideKeyboard() {
        focusedField = nil
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

    private func learnThisWord(result: SearchResult) {
        Task {
            viewState = .saving
            do {
                let posRawValue = PartOfSpeech.allCases.first { $0.displayName == result.partOfSpeech }?.rawValue ?? "noun"
                try await viewModel.saveNewWord(
                    targetText: result.targetText,
                    baseText: result.baseText,
                    partOfSpeech: posRawValue,
                    locale: baseLanguageCode
                )
                word = ""; baseText = ""; searchResults = []; partOfSpeech = nil
                viewState = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if viewState == .success { viewState = .idle }
                }
            } catch {
                viewState = .error("Already in vocabook.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if case .error = viewState { viewState = .idle }
                }
            }
        }
    }

    private func languageName(for code: String) -> String {
        LanguageSettings.availableLanguages.first(where: { $0.id == code })?.name ?? code.uppercased()
    }
    
    private func swapLanguages() {
        (word, baseText) = (baseText, word)
        inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
        debouncedSearch(term: word, searchBase: inputDirection == .baseToTarget)
    }
    
    private func debouncedSearch(term: String, searchBase: Bool) {
        searchTask?.cancel()
        guard term.trimmed.count >= 2 else {
            searchResults = []
            if case .searching = viewState { viewState = .idle }
            return
        }
        
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                viewState = .searching
                
                try await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                
                let results = try await viewModel.searchForWord(term: term.trimmed, searchBase: searchBase)
                self.searchResults = results
                viewState = .idle
            } catch {
                if Task.isCancelled {
                    viewState = .idle
                } else {
                    viewState = .error("Search failed")
                }
            }
        }
        searchTask = task
    }

    private func saveWord() {
        guard !isBusy else { return }
        hideKeyboard()
        viewState = .saving
        Task {
            do {
                let targetOut = (inputDirection == .baseToTarget) ? baseText.trimmed : word.trimmed
                let baseOut = (inputDirection == .baseToTarget) ? word.trimmed : baseText.trimmed
                
                try await viewModel.saveNewWord(
                    targetText: targetOut,
                    baseText: baseOut,
                    partOfSpeech: partOfSpeech?.rawValue ?? "",
                    locale: baseLanguageCode
                )
                word = ""; baseText = ""; partOfSpeech = nil
                viewState = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if viewState == .success { viewState = .idle }
                }
            } catch {
                viewState = .error("Failed to save. Word may already exist.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if case .error = viewState { viewState = .idle }
                }
            }
        }
    }
    
    private func translateWord() {
        guard !word.trimmed.isEmpty, !isBusy else { return }
        hideKeyboard()
        viewState = .translating
        Task {
            do {
                let sourceCode = (inputDirection == .baseToTarget) ? baseLanguageCode : targetLanguageCode
                let targetCode = (inputDirection == .baseToTarget) ? targetLanguageCode : baseLanguageCode
                
                if sourceCode == targetCode {
                    baseText = word
                    viewState = .idle
                    return
                }
                
                let response = try await viewModel.translateWord(word: word.trimmed, source: sourceCode, target: targetCode)
                self.baseText = response.translation
                
                if let newPOS = PartOfSpeech(rawValue: response.partOfSpeech.trimmed.lowercased()) {
                    self.partOfSpeech = newPOS
                }
                viewState = .idle
            } catch {
                viewState = .error("Translation failed.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if case .error = viewState { viewState = .idle }
                }
            }
        }
    }
}

private struct FeedbackPill: View {
    let message: String
    let icon: String?
    let style: Style
    
    enum Style { case loading, success, error }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
            } else if style == .loading {
                ProgressView()
            }
            Text(message)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // FIX 3: Corrected the background modifier syntax
        .background(backgroundColor, in: Capsule())
        .shadow(radius: 10)
    }
    
    private var backgroundColor: some ShapeStyle {
        switch style {
        case .loading: return Color.blue.gradient
        case .success: return Color.green.gradient
        case .error: return Color.red.gradient
        }
    }
}

extension String {
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
