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
    @State private var isLoading: Bool = false
    @State private var showingSuccessAlert: Bool = false
    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Word Details") {
                    TextField("Word (e.g., 'run')", text: $word)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Base Text (e.g., 'to run')", text: $baseText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Picker("Part of Speech", selection: $partOfSpeech) {
                        ForEach(PartOfSpeech.allCases) { pos in
                            Text(pos.displayName).tag(pos)
                        }
                    }
                }

                Section {
                    Button(action: saveWord) {
                        HStack {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(isLoading ? "Saving..." : "Save Word")
                        }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .disabled(isLoading || word.isEmpty || baseText.isEmpty)
                }
            }
            .navigationTitle("Add New Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showingSuccessAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your new word has been saved.")
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
                // The saveNewUserWord function is now correctly accessed from the viewModel
                try await viewModel.saveNewUserWord(
                    word: word,
                    baseText: baseText,
                    partOfSpeech: partOfSpeech.rawValue
                )
                showingSuccessAlert = true
                // No need to dismiss here, the alert OK button will dismiss
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
                isLoading = false
            }
        }
    }
}

// MARK: - Strapi Data Structures for User Word (REMOVED FROM THIS FILE)
// These structs are now defined solely in FlashcardViewModel.swift to avoid redeclaration errors.
