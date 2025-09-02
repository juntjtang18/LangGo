// LangGo/Vocabook/NewWordFormView.swift
import SwiftUI

struct NewWordFormView: View {
    // MARK: - State Bindings
    @Binding var isTranslating: Bool
    @Binding var word: String
    @Binding var baseText: String
    @Binding var partOfSpeech: PartOfSpeech?
    @Binding var inputDirection: NewWordInputView.InputDirection
    @Binding var searchResults: [SearchResult]
    @Binding var isSearching: Bool
    //@Binding var isTranslationStale: Bool

    @FocusState.Binding var focusedField: NewWordInputView.Field?
    
    // MARK: - View Configuration
    let baseLanguageName: String
    let targetLanguageName: String

    // MARK: - Actions
    let onDebouncedSearch: (String, Bool) -> Void
    let onTranslate: () -> Void
    let onSwap: () -> Void
    let onLearnThis: (SearchResult) -> Void
    let onSpeakTop: () -> Void
    let onSpeakBottom: () -> Void
    
    @Environment(\.theme) var theme: Theme
    
    // MARK: - Body
    var body: some View {
        Group {
            topInputSection
            bottomInputSection
            partOfSpeechSection
        }
    }
    
    // MARK: - Input Sections
    private var topInputSection: some View {
        let isBaseAtTop = (inputDirection == .baseToTarget)
        
        return Section {
            TextField(isBaseAtTop ? "Enter base word" : "Enter target word", text: $word, axis: .vertical)
                .lineLimit(1...4) // Start at 1 line, grow up to 4
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .top)
                .onChange(of: word, perform: { newWord in
                    onDebouncedSearch(newWord, isBaseAtTop)
                })

            if focusedField == .top {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(searchResults) { result in
                    searchResultRow(for: result)
                }
            }
        } header: {
            HStack {
                Text(isBaseAtTop ? "Base (\(baseLanguageName))" : "Target (\(targetLanguageName))")
                Spacer()
                Button(action: onSpeakTop) { Image(systemName: "speaker.wave.2.fill") }
                    .buttonStyle(SubtleIconButtonStyle())
                
                if isTranslating {
                    ProgressView()
                        .frame(width: 44, height: 44) // Match the button's frame
                } else {
                    Button(action: onTranslate) { Image(systemName: "sparkles") }
                        .buttonStyle(ProminentIconButtonStyle(backgroundColor: word.isEmpty ? Color(UIColor.systemGray2) : theme.accent))
                        .disabled(word.isEmpty)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var bottomInputSection: some View {
        let isBaseAtBottom = (inputDirection != .baseToTarget)

        return Section {
            TextField(isBaseAtBottom ? "Enter base word" : "Target word", text: $baseText, axis: .vertical)
                .lineLimit(1...4) // Start at 1 line, grow up to 4
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .bottom)
                //.foregroundColor(isTranslationStale ? .gray : .primary)
                .onChange(of: baseText, perform: { newText in
                    onDebouncedSearch(newText, isBaseAtBottom)
                })

            if focusedField == .bottom {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(searchResults) { result in
                    searchResultRow(for: result)
                }
            }
        } header: {
            HStack {
                Text(isBaseAtBottom ? "Base (\(baseLanguageName))" : "Target (\(targetLanguageName))")
                
                //if isTranslationStale && !baseText.isEmpty {
                /*
                if baseText.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                */
                Spacer()
                Button(action: onSpeakBottom) { Image(systemName: "speaker.wave.2.fill") }
                    .buttonStyle(SubtleIconButtonStyle())

                Button(action: onSwap) { Image(systemName: "arrow.up.arrow.down") }
                    .buttonStyle(ProminentIconButtonStyle(backgroundColor: .accentColor))
            }
            .padding(.bottom, 4)
        }
    }
    
    private var partOfSpeechSection: some View {
        // MODIFIED: Removed the section header text.
        Section("") {
            Picker("Part of Speech", selection: $partOfSpeech) {
                Text("Not Specified").tag(nil as PartOfSpeech?)
                ForEach(PartOfSpeech.allCases) { pos in
                    Text(pos.displayName).tag(pos as PartOfSpeech?)
                }
            }
            .pickerStyle(.menu) // Changed to .menu style.
        }
    }
    
    private func searchResultRow(for result: SearchResult) -> some View {
        HStack {
            let posText = (result.partOfSpeech != "N/A" && !result.partOfSpeech.isEmpty) ? "(\(result.partOfSpeech.lowercased()))" : ""
            
            Text("\(result.targetText) ") + Text(posText).foregroundColor(.secondary) + Text(" \(result.baseText)")
            
            Spacer()

            if result.isAlreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            } else {
                Button("Learn This") {
                    onLearnThis(result)
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProminentIconButtonStyle: ButtonStyle {
    let backgroundColor: Color
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(backgroundColor)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

private struct SubtleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.secondary)
            .padding(8)
            .background(
                Circle()
                    .fill(Color(UIColor.systemGray6))
            )
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

