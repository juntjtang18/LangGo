// LangGo/NewWordInputView.swift
import SwiftUI
import os


struct NewWordInputView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: FlashcardViewModel
    @State private var word: String = ""
    @State private var baseText: String = ""
    @State private var partOfSpeech: PartOfSpeech = .noun
    @EnvironmentObject var languageSettings: LanguageSettings
    @State private var isTranslating: Bool = false
    @State private var isLoading: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var showErrorMessage: Bool = false
    @State private var errorMessageText: String = ""

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
                .id(inputDirection) // <-- Add this modifier to fix the redraw issues

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

                VStack {
                    if showSuccessMessage {
                        Text("Word saved successfully!")
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
                .frame(height: 100) // Fixed space for messages
            }
            .padding(.bottom, 10)
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: {
                withAnimation {
                    inputDirection = (inputDirection == .englishToLearning) ? .learningToEnglish : .englishToLearning
                    word = ""
                    baseText = ""
                }
            }) {
                VStack {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    Text("Swap")
                        .foregroundColor(.primary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(PlainButtonStyle())
            Spacer()
            Button(action: { translateWord() }) {
                VStack {
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
                    Text("AI Translation")
                        .foregroundColor(.primary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(PlainButtonStyle())
            .disabled(word.isEmpty || isTranslating || (languageSettings.selectedLanguageCode == "en"))
            Spacer()
        }
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
    }

    private func saveWord() {
        isLoading = true
        Task {
            do {
                let strapiWordFieldContent: String // This will be the English word
                let strapiBaseTextFieldContent: String // This will be the Learning Language word
                let baseLocale: String
                let targetLocale: String

                if inputDirection == .englishToLearning {
                    // UI: "English Word" is $word, "Learning Language Translation" is $baseText
                    // Desired Strapi: 'word' field = English, 'base_text' field = Learning Language
                    strapiWordFieldContent = word // Content of UI's "English Word"
                    strapiBaseTextFieldContent = baseText // Content of UI's "Learning Language Translation"
                    baseLocale = "en"
                    targetLocale = languageSettings.selectedLanguageCode
                } else { // inputDirection == .learningToEnglish
                    // UI: "Learning Language Word" is $word, "English Translation" is $baseText
                    // Desired Strapi: 'word' field = English, 'base_text' field = Learning Language
                    strapiWordFieldContent = baseText // Content of UI's "English Translation"
                    strapiBaseTextFieldContent = word // Content of UI's "Learning Language Word"
                    baseLocale = languageSettings.selectedLanguageCode
                    targetLocale = "en"
                }
                
                try await viewModel.saveNewUserWord(
                    targetText: strapiWordFieldContent, // Renamed for clarity and correctness
                    baseText: strapiBaseTextFieldContent, // Maps to Strapi 'base_text' field
                    partOfSpeech: partOfSpeech.rawValue,
                    baseLocale: baseLocale,
                    targetLocale: targetLocale
                )
                word = ""
                baseText = ""
                partOfSpeech = .noun
                withAnimation {
                    showSuccessMessage = true
                    showErrorMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showSuccessMessage = false
                    }
                }
                isLoading = false
            } catch {
                errorMessageText = error.localizedDescription
                withAnimation {
                    showErrorMessage = true
                    showSuccessMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showErrorMessage = false
                    }
                }
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
                errorMessageText = "Translation failed: \(error.localizedDescription)"
                withAnimation {
                    showErrorMessage = true
                    showSuccessMessage = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showErrorMessage = false
                    }
                }
            }
            isTranslating = false
        }
    }
}
