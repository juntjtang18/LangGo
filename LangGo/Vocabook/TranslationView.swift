import SwiftUI
import os

enum InputDirection: String, CaseIterable, Identifiable {
    case baseToTarget = "Base to Target"
    case targetToBase = "Target to Base"
    var id: String { self.rawValue }
}

// MARK: - Tab View
struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    // Note: AppEnvironment is no longer needed here.

    var body: some View {
        NavigationStack {
            // The TranslationView is now self-sufficient and doesn't need any parameters.
            TranslationView()
                .navigationTitle("Translation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Using the direct toolbar implementation that is known to work.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isSideMenuShowing.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                }
        }
    }
}

// MARK: - Main Translation View
struct TranslationView: View {
    @EnvironmentObject var languageSettings: LanguageSettings

    // @StateObject is the correct property wrapper for creating and owning an
    // ObservableObject instance within a view. It ensures the ViewModel's
    // lifecycle is managed correctly by SwiftUI.
    @StateObject private var viewModel = FlashcardViewModel()

    @State private var inputText: String = ""
    @State private var translatedText: String = ""
    @State private var isLoadingTranslation: Bool = false
    @State private var isLoadingSave: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var showErrorMessage: Bool = false
    @State private var errorMessageText: String = ""

    private let learningTargetLanguageCode: String = Config.learningTargetLanguageCode
    
    // Note: The custom init has been removed.
    // The rest of your view's state and logic remains the same.
    @State private var partOfSpeech: PartOfSpeech = .noun
    @State private var inputDirection: InputDirection = .baseToTarget
    @State private var inputIsStale: Bool = true
    @State private var lastTranslatedInput: String?
    @State private var lastTranslatedOutput: String?

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Input Text (\(inputLanguageCode.uppercased()))")) {
                    TextField("Enter word or sentence", text: $inputText, axis: .vertical)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(minHeight: 80)
                        .onChange(of: inputText) { newText in
                            if newText == lastTranslatedInput {
                                translatedText = lastTranslatedOutput ?? ""
                                inputIsStale = false
                            } else {
                                inputIsStale = true
                                translatedText = ""
                            }
                            showSuccessMessage = false
                            showErrorMessage = false
                        }
                }

                HStack {
                    Spacer()
                    Button(action: swapLanguages) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                Section(header: Text("Translation (\(translationLanguageCode.uppercased()))")) {
                    TextEditor(text: $translatedText)
                        .frame(minHeight: 150)
                        .disabled(true)
                        .foregroundColor(.gray)
                }
            }
            .id(inputDirection)
            .padding(.bottom, 10)

            HStack(spacing: 20) {
                Button(action: translateContent) {
                    HStack {
                        if isLoadingTranslation { ProgressView() }
                        Text(isLoadingTranslation ? "Translating..." : "Translate")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.blue))
                    .foregroundColor(.white)
                    .font(.headline)
                    .opacity(inputText.isEmpty || isLoadingTranslation || isLoadingSave ? 0.5 : 1.0)
                }
                .disabled(inputText.isEmpty || isLoadingTranslation || isLoadingSave)

                Button(action: addWordToVocaBook) {
                    HStack {
                        if isLoadingSave { ProgressView() }
                        Text(isLoadingSave ? "Adding..." : "Add to VocaBook")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.green))
                    .foregroundColor(.white)
                    .font(.headline)
                    .opacity(translatedText.isEmpty || inputText.isEmpty || isLoadingSave || isLoadingTranslation || sourceTranslationLanguageCode == targetTranslationLanguageCode || inputIsStale ? 0.5 : 1.0)
                }
                .disabled(translatedText.isEmpty || inputText.isEmpty || isLoadingSave || isLoadingTranslation || sourceTranslationLanguageCode == targetTranslationLanguageCode || inputIsStale)
            }
            .padding(.horizontal)

            VStack {
                if showSuccessMessage {
                    Text("Action successful!")
                        .font(.subheadline)
                        .padding()
                        .background(Color.green.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .transition(.opacity)
                } else if showErrorMessage {
                    Text(errorMessageText)
                        .font(.subheadline)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .transition(.opacity)
                }
            }
            .frame(height: 50)
        }
        .onAppear { inputIsStale = true }
    }

    private var inputLanguageCode: String {
        inputDirection == .baseToTarget ? languageSettings.selectedLanguageCode : learningTargetLanguageCode
    }

    private var translationLanguageCode: String {
        inputDirection == .baseToTarget ? learningTargetLanguageCode : languageSettings.selectedLanguageCode
    }

    private var sourceTranslationLanguageCode: String {
        inputDirection == .baseToTarget ? languageSettings.selectedLanguageCode : learningTargetLanguageCode
    }

    private var targetTranslationLanguageCode: String {
        inputDirection == .baseToTarget ? learningTargetLanguageCode : languageSettings.selectedLanguageCode
    }

    private func swapLanguages() {
        withAnimation {
            inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
            inputText = ""
            translatedText = ""
            inputIsStale = true
            lastTranslatedInput = nil
            lastTranslatedOutput = nil
            showSuccessMessage = false
            showErrorMessage = false
        }
    }

    private func translateContent() {
        isLoadingTranslation = true
        showSuccessMessage = false
        showErrorMessage = false
        errorMessageText = ""
        Task {
            do {
                let result = try await viewModel.translateWord(
                    word: inputText,
                    source: sourceTranslationLanguageCode,
                    target: targetTranslationLanguageCode
                )
                translatedText = result.translation
                lastTranslatedInput = inputText
                lastTranslatedOutput = translatedText
                inputIsStale = false
                withAnimation { showSuccessMessage = true }
            } catch {
                errorMessageText = "Translation failed: \(error.localizedDescription)"
                withAnimation { showErrorMessage = true }
            }
            isLoadingTranslation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showSuccessMessage = false
                    showErrorMessage = false
                }
            }
        }
    }

    private func addWordToVocaBook() {
        isLoadingSave = true
        showSuccessMessage = false
        showErrorMessage = false
        errorMessageText = ""
        Task {
            do {
                let targetOut: String
                let baseOut: String

                if inputDirection == .baseToTarget {
                    baseOut   = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    targetOut = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    baseOut   = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    targetOut = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                try await viewModel.saveNewWord(
                    targetText: targetOut,
                    baseText: baseOut,
                    partOfSpeech: partOfSpeech.rawValue,
                    locale: languageSettings.selectedLanguageCode
                )

                withAnimation { showSuccessMessage = true }
                inputText = ""
                translatedText = ""
                inputIsStale = true
                lastTranslatedInput = nil
                lastTranslatedOutput = nil
            } catch {
                errorMessageText = "Failed to add to VocaBook: \(error.localizedDescription)"
                withAnimation {
                    showErrorMessage = true
                    showSuccessMessage = false
                }
            }
            isLoadingSave = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { showErrorMessage = false }
            }
        }
    }
}
