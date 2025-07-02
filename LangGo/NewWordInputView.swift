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

    // State to control the input direction based on learning context
    enum InputDirection: String, CaseIterable, Identifiable {
        case englishToLearning = "English to Learning Language"
        case learningToEnglish = "Learning Language to English"

        var id: String { self.rawValue }
    }
    @State private var inputDirection: InputDirection = .englishToLearning

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    // Dynamically render sections based on inputDirection
                    if inputDirection == .englishToLearning {
                        Section("English Word") {
                            HStack {
                                TextField("Enter English word", text: $word)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                Button(action: translateWord) {
                                    if isTranslating {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .disabled(word.isEmpty || isTranslating || (languageSettings.selectedLanguageCode == "en"))
                            }
                        }

                        // Swap button as a larger circle with icon only
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    inputDirection = .learningToEnglish
                                    word = "" // Clear fields on swap
                                    baseText = "" // Clear fields on swap
                                }
                            }) {
                                Image(systemName: "arrow.up.arrow.down.circle.fill")
                                    .font(.largeTitle) // Make icon larger
                                    .foregroundColor(.white) // Icon color
                                    .frame(width: 60, height: 60) // Fixed size for the tappable area
                                    .background(Color.accentColor) // A solid color for the circle background
                                    .clipShape(Circle()) // Clip to a perfect circle
                                    .shadow(radius: 3) // Add a subtle shadow for depth
                            }
                            .padding(.vertical, 10) // Add some vertical padding to separate it from sections
                            Spacer()
                        }


                        Section((languageSettings.availableLanguages.first(where: { $0.id == languageSettings.selectedLanguageCode })?.name ?? "Learning Language") + " Translation") {
                            TextField("Translated text", text: $baseText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    } else { // inputDirection == .learningToEnglish
                        Section((languageSettings.availableLanguages.first(where: { $0.id == languageSettings.selectedLanguageCode })?.name ?? "Learning Language") + " Word") {
                            HStack {
                                TextField("Enter word in learning language", text: $word)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                Button(action: translateWord) {
                                    if isTranslating {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .disabled(word.isEmpty || isTranslating || (languageSettings.selectedLanguageCode == "en"))
                            }
                        }

                        // Swap button as a larger circle with icon only
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    inputDirection = .englishToLearning
                                    word = "" // Clear fields on swap
                                    baseText = "" // Clear fields on swap
                                }
                            }) {
                                Image(systemName: "arrow.up.arrow.down.circle.fill")
                                    .font(.largeTitle) // Make icon larger
                                    .foregroundColor(.white) // Icon color
                                    .frame(width: 60, height: 60) // Fixed size for the tappable area
                                    .background(Color.accentColor) // A solid color for the circle background
                                    .clipShape(Circle()) // Clip to a perfect circle
                                    .shadow(radius: 3) // Add a subtle shadow for depth
                            }
                            .padding(.vertical, 10) // Add some vertical padding to separate it from sections
                            Spacer()
                        }


                        Section("English Translation") {
                            TextField("English translation", text: $baseText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    }

                    Section("Part of Speech") {
                        Picker("Select Part of Speech", selection: $partOfSpeech) {
                            ForEach(PartOfSpeech.allCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Spacer()

                Button(action: saveWord) {
                    HStack {
                        if isLoading {
                            ProgressView()
                        }
                        Text(isLoading ? "Saving..." : "Save Word")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
                    .font(.headline)
                    .opacity(word.isEmpty || baseText.isEmpty || isLoading || isTranslating ? 0.5 : 1.0)
                }
                .disabled(isLoading || word.isEmpty || baseText.isEmpty || isTranslating)
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
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
                let learningLanguageWord: String
                let englishTranslation: String

                if inputDirection == .englishToLearning {
                    learningLanguageWord = baseText
                    englishTranslation = word
                } else { // learningToEnglish
                    learningLanguageWord = word
                    englishTranslation = baseText
                }

                try await viewModel.saveNewUserWord(
                    word: learningLanguageWord,
                    baseText: englishTranslation,
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
                let sourceLanguageCode: String
                let targetLanguageCode: String

                if inputDirection == .englishToLearning {
                    sourceLanguageCode = "en"
                    targetLanguageCode = languageSettings.selectedLanguageCode
                } else { // learningToEnglish
                    sourceLanguageCode = languageSettings.selectedLanguageCode
                    targetLanguageCode = "en"
                }

                if word.isEmpty || sourceLanguageCode == targetLanguageCode {
                    self.baseText = word
                    isTranslating = false
                    return
                }

                let translatedText = try await viewModel.translateWord(
                    word: word,
                    source: sourceLanguageCode,
                    target: targetLanguageCode
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
