import SwiftUI
import os

// Define the PartOfSpeech enum based on your Strapi schema
enum PartOfSpeech: String, CaseIterable, Identifiable {
    case noun, verb, adjective, adverb, conjunction, preposition, interjection, determiner, pronoun

    var id: String { self.rawValue }

    // A more user-friendly display name
    var displayName: String {
        switch self {
        case .noun: return "Noun"
        case .verb: return "Verb"
        case .adjective: return "Adjective"
        case .adverb: return "Adverb"
        case .conjunction: return "Conjunction"
        case .preposition: return "Preposition"
        case .interjection: return "Interjection"
        case .determiner: return "Determiner"
        case .pronoun: return "Pronoun"
        }
    }
}

struct NewWordInputView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: FlashcardViewModel

    @State private var word: String = ""
    @State private var baseText: String = ""
    @State private var partOfSpeech: PartOfSpeech = .noun
    @EnvironmentObject var languageSettings: LanguageSettings // Access the shared language settings
    @State private var isTranslating: Bool = false // New state for translation loading
    @State private var isLoading: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            VStack { // This is the outermost VStack
                Form {
                    // Section for English Word
                    Section("English") {
                        HStack {
                            TextField("Word (e.g., 'run')", text: $word)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)

                            // Magic button for translation
                            Button(action: translateWord) {
                                if isTranslating {
                                    ProgressView()
                                } else {
                                    Image(systemName: "wand.and.stars") // Magic icon
                                        .foregroundColor(.accentColor)
                                }
                            }
                            // Disable if no word, translating, or target language is English (same as source)
                            .disabled(word.isEmpty || isTranslating || languageSettings.selectedLanguageCode == "en")
                        }
                    }

                    // Section for Selected Language
                    Section(languageSettings.availableLanguages.first(where: { $0.id == languageSettings.selectedLanguageCode })?.name ?? "Translation") {
                        TextField("Base Text (e.g., 'to run')", text: $baseText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    // Separate Section for Part of Speech
                    Section("Part of Speech") {
                        Picker("Select Part of Speech", selection: $partOfSpeech) {
                            ForEach(PartOfSpeech.allCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .pickerStyle(.navigationLink) // Often looks cleaner in forms
                    }
                }

                Spacer() // Pushes the form content up and the button down

                // The Save button is now outside the Form
                Button(action: saveWord) {
                    HStack {
                        if isLoading {
                            ProgressView()
                        }
                        Text(isLoading ? "Saving..." : "Save Word") // No icon
                    }
                    .frame(maxWidth: .infinity)
                    .padding() // Add padding around the text inside the button
                    .background(Capsule().fill(Color.accentColor)) // Example background
                    .foregroundColor(.white)
                    .font(.headline)
                    .opacity(word.isEmpty || baseText.isEmpty || isLoading || isTranslating ? 0.5 : 1.0) // Dim if disabled
                }
                .disabled(isLoading || word.isEmpty || baseText.isEmpty || isTranslating)
                .padding(.horizontal) // Padding from the sides of the screen for the button
                // Removed padding from here as it's now applied to the outermost VStack
            }
            .padding(.bottom, 20) // Apply padding to the entire VStack to lift content from the bottom
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveWord() {
        isLoading = true
        Task {
            do {
                try await viewModel.saveNewUserWord(
                    word: word,
                    baseText: baseText,
                    partOfSpeech: partOfSpeech.rawValue
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
                isLoading = false
            }
        }
    }

    private func translateWord() {
        isTranslating = true
        Task {
            do {
                // Use the app's selected language from LanguageSettings as the target locale
                let targetLocale = languageSettings.selectedLanguageCode

                // Prevent translation if source and target languages are the same, or if the word is empty
                // This check is now redundant due to the .disabled modifier on the button, but kept for logical clarity
                if word.isEmpty || targetLocale == "en" { // Assuming source is always "en" for this feature
                    self.baseText = word
                    isTranslating = false
                    return
                }

                // Translate from English ("en") to the device's locale
                let translatedText = try await viewModel.translateWord(
                    word: word,
                    source: "en", // Source language is always English for this feature
                    target: targetLocale
                )
                self.baseText = translatedText
            } catch {
                errorMessage = "Translation failed: \(error.localizedDescription)"
                showingErrorAlert = true
            }
            isTranslating = false
        }
    }
}
