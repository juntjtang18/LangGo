// LangGo/Vocabook/NewWordFormView.swift
import SwiftUI

private struct ProminentIconButtonStyle: ButtonStyle {
    let backgroundColor: Color

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


struct NewWordFormView: View {
    // MARK: - State Bindings
    @Binding var word: String
    @Binding var baseText: String
    @Binding var partOfSpeech: PartOfSpeech?
    @Binding var inputDirection: NewWordInputView.InputDirection
    @Binding var searchResults: [SearchResult]
    @Binding var isSearching: Bool
    @Binding var isTranslationStale: Bool
    
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
                .frame(minHeight: 80, alignment: .top)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .top)
                // MODIFIED: Used older, more compatible onChange syntax.
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
                
                Button(action: onTranslate) { Image(systemName: "camera.viewfinder") }
                    .buttonStyle(ProminentIconButtonStyle(backgroundColor: Color(UIColor.systemGray2)))
            }
            .padding(.bottom, 4)
        }
    }

    private var bottomInputSection: some View {
        let isBaseAtBottom = (inputDirection != .baseToTarget)

        return Section {
            TextField(isBaseAtBottom ? "Enter base word" : "Target word", text: $baseText, axis: .vertical)
                .frame(minHeight: 80, alignment: .top)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .bottom)
                .foregroundColor(isTranslationStale ? .gray : .primary)
                // MODIFIED: Used older, more compatible onChange syntax.
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
                
                if isTranslationStale && !baseText.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
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
        Section("Part of Speech") {
            Picker("Select Part of Speech", selection: $partOfSpeech) {
                Text("Not Specified").tag(nil as PartOfSpeech?)
                ForEach(PartOfSpeech.allCases) { pos in
                    Text(pos.displayName).tag(pos as PartOfSpeech?)
                }
            }
            .pickerStyle(.navigationLink)
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
