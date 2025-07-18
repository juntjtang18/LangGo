// LangGo/TranslationView.swift
import SwiftUI
import SwiftData
import os

// New enum to manage the direction of translation input
enum InputDirection: String, CaseIterable, Identifiable {
    case baseToTarget = "Base to Target" // User inputs native language, translates to learning language
    case targetToBase = "Target to Base" // User inputs learning language, translates to native language
    var id: String { self.rawValue }
}

struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var appEnvironment: AppEnvironment

    var body: some View {
        NavigationStack {
            TranslationView(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                .navigationTitle("Translation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}

struct TranslationView: View {
    @EnvironmentObject var languageSettings: LanguageSettings
    @State private var viewModel: FlashcardViewModel

    @State private var inputText: String = ""
    @State private var translatedText: String = ""
    @State private var isLoadingTranslation: Bool = false
    @State private var isLoadingSave: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var showErrorMessage: Bool = false
    @State private var errorMessageText: String = ""

    // Use the configurable learning target language from Config.swift
    private let learningTargetLanguageCode: String = Config.learningTargetLanguageCode
    
    // Default part of speech for new words
    @State private var partOfSpeech: PartOfSpeech = .noun

    // New state to manage the direction of translation
    @State private var inputDirection: InputDirection = .baseToTarget

    // FIX: New state variable to track if input has changed since last translation
    @State private var inputIsStale: Bool = true // Initially true because no translation has occurred yet

    // FIX: New state variables to store the last successfully translated pair
    @State private var lastTranslatedInput: String?
    @State private var lastTranslatedOutput: String?

    init(modelContext: ModelContext, strapiService: StrapiService) {
        _viewModel = State(initialValue: FlashcardViewModel(modelContext: modelContext, strapiService: strapiService))
    }

    var body: some View {
        VStack {
            Form {
                // Input Section - dynamically adjusts based on inputDirection
                Section(header: Text("Input Text (\(inputLanguageCode.uppercased()))")) {
                    TextField("Enter word or sentence", text: $inputText, axis: .vertical) // Allow multiline input
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(minHeight: 80) // Enlarge input text box
                        // FIX: Detect changes in inputText to mark it as stale or restore
                        .onChange(of: inputText) { _, newText in
                            if newText == lastTranslatedInput {
                                // Input matches a previously translated word, restore translation and enable button
                                translatedText = lastTranslatedOutput ?? ""
                                inputIsStale = false
                            } else {
                                // Input has changed to something new or different from last translated
                                inputIsStale = true
                                translatedText = "" // Clear translated text for new input
                            }
                            showSuccessMessage = false
                            showErrorMessage = false
                        }
                }

                // Swap Button
                HStack {
                    Spacer()
                    Button(action: swapLanguages) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear) // Ensure the button background is clear

                // Translation Section - dynamically adjusts based on inputDirection
                Section(header: Text("Translation (\(translationLanguageCode.uppercased()))")) {
                    TextEditor(text: $translatedText)
                        .frame(minHeight: 150) // Enlarge target text box
                        .disabled(true) // Make it read-only
                        .foregroundColor(.gray)
                }
            }
            .id(inputDirection) // Force redraw of the Form when inputDirection changes
            .padding(.bottom, 10)

            HStack(spacing: 20) {
                Button(action: translateContent) {
                    HStack {
                        if isLoadingTranslation {
                            ProgressView()
                        }
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
                        if isLoadingSave {
                            ProgressView()
                        }
                        Text(isLoadingSave ? "Adding..." : "Add to VocaBook")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.green))
                    .foregroundColor(.white)
                    .font(.headline)
                    // FIX: Disable if input is stale (not translated), or other existing conditions
                    .opacity(translatedText.isEmpty || inputText.isEmpty || isLoadingSave || isLoadingTranslation || sourceTranslationLanguageCode == targetTranslationLanguageCode || inputIsStale ? 0.5 : 1.0)
                }
                // FIX: Disable if input is stale (not translated), or other existing conditions
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
            .frame(height: 50) // Fixed space for messages
        }
        .onAppear {
            inputIsStale = true // Ensure button is disabled on initial appearance
        }
    }

    // Helper computed properties for language codes based on current input direction
    private var inputLanguageCode: String {
        inputDirection == .baseToTarget ? languageSettings.selectedLanguageCode : learningTargetLanguageCode
    }

    private var translationLanguageCode: String {
        inputDirection == .baseToTarget ? learningTargetLanguageCode : languageSettings.selectedLanguageCode
    }

    // These are the actual source and target for the API call
    private var sourceTranslationLanguageCode: String {
        inputDirection == .baseToTarget ? languageSettings.selectedLanguageCode : learningTargetLanguageCode
    }

    private var targetTranslationLanguageCode: String {
        inputDirection == .baseToTarget ? learningTargetLanguageCode : languageSettings.selectedLanguageCode
    }

    private func swapLanguages() {
        withAnimation {
            inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
            inputText = ""       // Clear input when swapping
            translatedText = ""  // Clear translation when swapping
            inputIsStale = true  // Mark as stale after swap
            lastTranslatedInput = nil // Clear last translated state
            lastTranslatedOutput = nil // Clear last translated state
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
                    source: sourceTranslationLanguageCode, // Dynamic source
                    target: targetTranslationLanguageCode  // Dynamic target
                )
                translatedText = result

                // FIX: Store the newly translated pair
                lastTranslatedInput = inputText
                lastTranslatedOutput = translatedText

                inputIsStale = false // Mark input as fresh after successful translation
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
                let baseLangContentForSave: String
                let targetLangContentForSave: String
                
                // baseLocaleForSave will always be the user's selected app language
                let baseLocaleForSave: String = languageSettings.selectedLanguageCode
                // targetLocaleForSave will always be the app's learning target language
                let targetLocaleForSave: String = learningTargetLanguageCode

                // Determine content based on input direction
                if inputDirection == .baseToTarget {
                    // User inputs native language (base), translates to learning language (target)
                    baseLangContentForSave = inputText
                    targetLangContentForSave = translatedText
                } else { // inputDirection == .targetToBase
                    // User inputs learning language (target), translates to native language (base)
                    baseLangContentForSave = translatedText
                    targetLangContentForSave = inputText
                }

                try await viewModel.saveNewUserWord(
                    targetText: targetLangContentForSave,
                    baseText: baseLangContentForSave,
                    partOfSpeech: partOfSpeech.rawValue,
                    baseLocale: baseLocaleForSave,
                    targetLocale: targetLocaleForSave
                )
                withAnimation { showSuccessMessage = true }
                // Clear inputs after successful save
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
                withAnimation {
                    showErrorMessage = false
                }
            }
        }
    }
}
