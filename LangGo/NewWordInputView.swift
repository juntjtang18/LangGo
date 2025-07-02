import SwiftUI
import os

// PartOfSpeech enum remains unchanged
enum PartOfSpeech: String, CaseIterable, Identifiable {
    case noun, verb, adjective, adverb, conjunction, preposition, interjection, determiner, pronoun

    var id: String { self.rawValue }

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
    @EnvironmentObject var languageSettings: LanguageSettings
    @State private var isTranslating: Bool = false
    @State private var isLoading: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

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
                    if inputDirection == .englishToLearning {
                        Section("English Word") {
                            TextField("Enter English word", text: $word)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        // Use extracted action buttons section
                        actionButtonsSection

                        Section((languageSettings.availableLanguages.first(where: { $0.id == languageSettings.selectedLanguageCode })?.name ?? "Learning Language") + " Translation") {
                            TextField("Translated text", text: $baseText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    } else {
                        Section((languageSettings.availableLanguages.first(where: { $0.id == languageSettings.selectedLanguageCode })?.name ?? "Learning Language") + " Word") {
                            TextField("Enter word in learning language", text: $word)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        // Use extracted action buttons section
                        actionButtonsSection

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

    // MARK: - Extracted Action Buttons Section
    private var actionButtonsSection: some View {
        HStack(spacing: 20) { // Add spacing to prevent tap overlap
            // Swap Button
            Button(action: {
                withAnimation {
                    inputDirection = (inputDirection == .englishToLearning) ? .learningToEnglish : .englishToLearning
                    word = ""
                    baseText = ""
                }
            }) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
            .contentShape(Circle()) // Explicitly define tap area
            .buttonStyle(PlainButtonStyle()) // Prevent Form styling interference

            // Magic (AI) Button
            Button(action: {
                translateWord()
            }) {
                if isTranslating {
                    ProgressView()
                        .frame(width: 60, height: 60)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }
            }
            .contentShape(Circle()) // Explicitly define tap area
            .buttonStyle(PlainButtonStyle()) // Prevent Form styling interference
            .disabled(word.isEmpty || isTranslating || (languageSettings.selectedLanguageCode == "en"))
        }
        .padding(.vertical, 10)
        .listRowBackground(Color.clear) // Ensure the row background is clear
    }

    // saveWord and translateWord functions remain unchanged
    private func saveWord() {
        isLoading = true
        Task {
            do {
                let learningLanguageWord: String
                let englishTranslation: String

                if inputDirection == .englishToLearning {
                    learningLanguageWord = baseText
                    englishTranslation = word
                } else {
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
                } else {
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
