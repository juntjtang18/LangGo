// LangGo/Vocabook/NewWordInputView.swift
import SwiftUI
import os

struct NewWordInputView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: FlashcardViewModel

    // UPPER field is always `word`, LOWER field is always `baseText`
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
        case baseToTarget = "Base → Target"
        case targetToBase = "Target → Base"
        var id: String { self.rawValue }
    }
    @State private var inputDirection: InputDirection = .baseToTarget

    // MARK: - Language Codes & Names
    private var baseLanguageCode: String {
        // Base = user's profile locale
        languageSettings.selectedLanguageCode
    }
    private var targetLanguageCode: String {
        // Target = app's learning locale
        Config.learningTargetLanguageCode
    }
    private func languageName(for code: String) -> String {
        languageSettings.availableLanguages.first(where: { $0.id == code })?.name ?? code.uppercased()
    }
    private var baseLanguageName: String { languageName(for: baseLanguageCode) }
    private var targetLanguageName: String { languageName(for: targetLanguageCode) }

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    if inputDirection == .baseToTarget {
                        // Base → Target: UPPER = BASE, LOWER = TARGET
                        Section("Base (\(baseLanguageName))") {
                            TextField("Enter base word", text: $word)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        actionButtonsSection
                        Section("Target (\(targetLanguageName))") {
                            TextField("Enter target word", text: $baseText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    } else {
                        // Target → Base: UPPER = TARGET, LOWER = BASE
                        Section("Target (\(targetLanguageName))") {
                            TextField("Enter target word", text: $word)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        actionButtonsSection
                        Section("Base (\(baseLanguageName))") {
                            TextField("Enter base word", text: $baseText)
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
                .id(inputDirection) // force redraw on swap

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
                .frame(height: 100)
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
                    inputDirection = (inputDirection == .baseToTarget) ? .targetToBase : .baseToTarget
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
                        ProgressView().frame(width: 60, height: 60)
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
            // Enabled as long as upper has text and we're not already translating
            .disabled(isTranslating || word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
    }

    // MARK: - Save
    private func saveWord() {
        isLoading = true
        Task {
            do {
                // Map by UI direction:
                // Base → Target: UPPER=BASE(word), LOWER=TARGET(baseText)
                // Target → Base: UPPER=TARGET(word), LOWER=BASE(baseText)
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
                    targetText: targetOut,   // TARGET = learning (targetLanguageCode)
                    baseText: baseOut,       // BASE   = profile locale (baseLanguageCode)
                    partOfSpeech: partOfSpeech.rawValue
                )

                // reset UI
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
                errorMessageText = error.localizedDescription
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

    // MARK: - Translate (upper → lower)
    private func translateWord() {
        isTranslating = true
        Task {
            do {
                // Translate from UPPER (source) to LOWER (target) based on direction
                let sourceCode = (inputDirection == .baseToTarget) ? baseLanguageCode : targetLanguageCode
                let targetCode = (inputDirection == .baseToTarget) ? targetLanguageCode : baseLanguageCode
                let sourceText = word.trimmingCharacters(in: .whitespacesAndNewlines)

                if sourceText.isEmpty || sourceCode == targetCode {
                    // Mirror when empty or same language
                    baseText = word
                    isTranslating = false
                    return
                }

                let translated = try await viewModel.translateWord(
                    word: sourceText,
                    source: sourceCode,
                    target: targetCode
                )
                // Always fill LOWER field with the translation
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
