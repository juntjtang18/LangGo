//
//  WordDetailSheet.swift
//  LangGo
//
//  Created by James Tang on 2025/8/17.
//
import Foundation
import SwiftUI

struct WordDetailSheet: View {
    let card: Flashcard
    let showBaseText: Bool
    let onClose: () -> Void
    
    @AppStorage("repeatReadingEnabled") private var repeatReadingEnabled: Bool = false
    let onSpeak: (@escaping () -> Void) -> Void   // speak one word, then call completion
    @State private var isRepeating: Bool = false   // event-driven loop flag
    @State private var showRecorder: Bool = false   // NEW

    // MARK: - Resolved fields from your models
    private var def: WordDefinitionAttributes? {
        card.wordDefinition?.attributes
    }
    
    private var wordText: String {
        // backContent already resolves this, but we read it from the model directly
        def?.word?.data?.attributes.targetText ?? card.backContent
    }
    
    private var baseText: String? { def?.baseText }
    private var posName: String? { def?.partOfSpeech?.data?.attributes.name }
    private var example: String? { def?.exampleSentence }
    private var register: String? { def?.register }
    private var gender: String? { def?.gender }
    private var article: String? { def?.article }
    private var verbMeta: VerbMetaComponent? { def?.verbMeta }
    private var examBase: [ExamOption]? { def?.examBase }
    private var examTarget: [ExamOption]? { def?.examTarget }
    // Optional: convert "adjective" -> "adj.", etc.
    private func shortPOS(_ s: String) -> String {
        switch s.lowercased() {
        case "adjective": return "adj."
        case "noun": return "n."
        case "verb": return "v."
        case "adverb": return "adv."
        case "pronoun": return "pron."
        case "conjunction": return "conj."
        case "preposition": return "prep."
        case "interjection": return "interj."
        case "article": return "art."
        default: return s
        }
    }
    var body: some View {
        ZStack{
            VStack(spacing: 12) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(8)
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title: word + POS
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(card.wordDefinition?.attributes.word?.data?.attributes.targetText ?? "")
                                .font(.title).bold()
                                .lineLimit(1)
                            if let posFull = card.wordDefinition?.attributes.partOfSpeech?.data?.attributes.name {
                                Text("(\(posAbbrev(from: posFull)))")
                                    .font(.title3)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            Spacer(minLength: 0)
                        }
                        
                        if let base = baseText, !base.isEmpty {
                            Text(base)
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Register / Gender / Article (inline pills if present)
                        HStack(spacing: 8) {
                            if let reg = register, !reg.isEmpty {
                                CapsulePill(text: reg)
                            }
                            if let gen = gender, !gen.isEmpty {
                                CapsulePill(text: gen)
                            }
                            if let art = article, !art.isEmpty {
                                CapsulePill(text: art)
                            }
                        }
                        
                        // Verb forms
                        if let vm = verbMeta, hasAnyVerbForm(vm) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Verb forms").font(.headline)
                                VerbRow(label: "Simple past", value: vm.simplePast)
                                VerbRow(label: "Past participle", value: vm.pastParticiple)
                                VerbRow(label: "Present participle", value: vm.presentParticiple)
                                VerbRow(label: "3rd person singular", value: vm.thirdpersonSingular)
                                VerbRow(label: "Auxiliary", value: vm.auxiliaryVerb)
                            }
                        }
                        
                        // Example sentence
                        if let ex = example, !ex.isEmpty {
                            Divider().opacity(0.5)
                            Text(ex)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // (Optional) Exam options – uncomment if you want them visible
                        /*
                         if let opts = examTarget, !opts.isEmpty {
                         Divider().opacity(0.5)
                         Text("Target-side options").font(.headline)
                         ExamList(options: opts)
                         }
                         if let opts = examBase, !opts.isEmpty {
                         Divider().opacity(0.5)
                         Text("Base-side options").font(.headline)
                         ExamList(options: opts)
                         }
                         */
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Controls row
                HStack(spacing: 28) {
                    CircleIcon(systemName: "mic.fill") { showRecorder = true }
                    CircleIcon(systemName: isRepeating ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill") {
                        readButtonTapped()
                    }
                    CircleIcon(systemName: repeatReadingEnabled ? "repeat.circle.fill" : "repeat.circle") {
                        toggleRepeat()
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.top, 8)
            .blur(radius: showRecorder ? 8 : 0)
            .disabled(showRecorder)
            .onAppear {
                // @AppStorage loads the last saved toggle automatically.
                // Do NOT auto-start; user taps Read to begin looping.
                isRepeating = false
                
                // If you prefer auto-start when Repeat is ON, uncomment:
                // if repeatReadingEnabled { startRepeating() }
            }
            .onDisappear {
                // Stop any in-flight loop, but keep the saved toggle as-is.
                stopRepeating()
            }
            if showRecorder {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                RecordModalView(
                    phrase: wordText,
                    onClose: { showRecorder = false }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .interactiveDismissDisabled(true)     // <- prevents swipe-to-dismiss
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: showRecorder)
    }
    
    // MARK: - Small helpers
    private func hasAnyVerbForm(_ vm: VerbMetaComponent) -> Bool {
        [vm.simplePast, vm.pastParticiple, vm.presentParticiple, vm.thirdpersonSingular, vm.auxiliaryVerb]
            .compactMap { $0 }
            .contains { !$0.isEmpty }
    }
    private func posAbbrev(from name: String) -> String {
        switch name.lowercased() {
        case "noun": return "n."
        case "verb": return "v."
        case "adjective": return "adj."
        case "adverb": return "adv."
        case "conjunction": return "conj."
        case "pronoun": return "pron."
        case "preposition": return "prep."
        case "interjection": return "interj."
        default: return name   // fallback: show the raw value
        }
    }

    // MARK: - Reading logic

    private func readButtonTapped() {
        if repeatReadingEnabled {
            // Toggle start/stop of repeating
            if isRepeating {
                stopRepeating()
            } else {
                startRepeating()
            }
        } else {
            // Single cycle (SpeechManager already reads target twice, + base if enabled)
            onSpeak({})
        }
    }
    private func startRepeating() {
        guard !isRepeating else { return }
        isRepeating = true

        func loop() {
            guard isRepeating else { return }
            onSpeak {
                // Chain the next read only after one word fully finishes
                DispatchQueue.main.async {
                    if self.isRepeating { loop() }
                }
            }
        }
        loop()
    }
    private func stopRepeating() {
        isRepeating = false
    }

    private func toggleRepeat() {
        repeatReadingEnabled.toggle()
        if !repeatReadingEnabled { stopRepeating() }
    }

}

private struct CapsulePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct VerbRow: View {
    let label: String
    let value: String?
    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label + ":").font(.callout).foregroundColor(.secondary)
                Text(value).font(.callout)
            }
        }
    }
}

private struct ExamList: View {
    let options: [ExamOption]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                HStack(spacing: 8) {
                    if let correct = opt.isCorrect {
                        Image(systemName: correct ? "checkmark.circle.fill" : "circle")
                            .imageScale(.small)
                            .foregroundColor(correct ? .green : .secondary)
                    }
                    Text(opt.text)
                        .font(.callout)
                }
            }
        }
    }
}

private struct CircleIcon: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black))
                .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

