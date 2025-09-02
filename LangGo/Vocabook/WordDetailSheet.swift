import SwiftUI

struct WordDetailSheet: View {
    // NEW: pass whole list + starting index
    let cards: [Flashcard]
    let showBaseText: Bool
    let onClose: () -> Void
    let onSpeak: (_ card: Flashcard, _ completion: @escaping () -> Void) -> Void
    // ADDED: A closure to handle the delete action.
    let onDelete: (_ cardId: Int) async -> Void

    // Paging state
    @State private var index: Int
    
    // ADDED: State for the confirmation view and deletion process.
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    init(cards: [Flashcard],
         initialIndex: Int,
         showBaseText: Bool,
         onClose: @escaping () -> Void,
         onSpeak: @escaping (_ card: Flashcard, _ completion: @escaping () -> Void) -> Void,
         // ADDED: onDelete parameter
         onDelete: @escaping (_ cardId: Int) async -> Void) {
        self.cards = cards
        self._index = State(initialValue: initialIndex)
        self.showBaseText = showBaseText
        self.onClose = onClose
        self.onSpeak = onSpeak
        self.onDelete = onDelete
    }

    // Existing controls state (keep your mic/speaker/repeat states here)
    @AppStorage("repeatReadingEnabled") private var repeatReadingEnabled: Bool = false
    @State private var isRepeating = false
    @State private var showRecorder = false

    private enum SlideDir { case none, next, prev }
    @State private var slideDir: SlideDir = .none

    private var card: Flashcard { cards[index] }
    private var canPrev: Bool { index > 0 }
    private var canNext: Bool { index < cards.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // close button row (keep yours)
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                }
            }

            ZStack {
                content(for: card)
                    .id(card.id) // diff by card id
                    .transition(transitionFor(slideDir))
            }
            .animation(.easeInOut(duration: 0.28), value: card.id)

            controlsRow
            navRow
        }
        .padding(.bottom, 12)
        .overlay(deleteConfirmationOverlay) // ADDED: The confirmation view overlay
        //.disabled(showDeleteConfirmation) // Disable background content when overlay is visible
    }

    // MARK: - Content (move your existing word layout here)
    @ViewBuilder
    private func content(for card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(card.wordDefinition?.attributes.word?.data?.attributes.targetText ?? card.frontContent)
                    .font(.title2.weight(.bold))
                if let pos = card.wordDefinition?.attributes.partOfSpeech?.data?.attributes.name {
                    Text("(\(pos))").font(.title3).foregroundColor(.secondary).italic()
                }
                Spacer()
                // ADDED: The "..." menu button
                Menu {
                    Button("Edit Word") {
                        // Placeholder for your edit action
                        print("Edit tapped for card ID: \(card.id)")
                    }
                    Button("Delete Word", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            if let base = card.wordDefinition?.attributes.baseText, !base.isEmpty {
                Text(base).font(.title3)
            }

            Divider().padding(.vertical, 6)

            if let ex = card.wordDefinition?.attributes.exampleSentence, !ex.isEmpty {
                Text(ex).font(.title3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    
    // ADDED: The entire confirmation view
    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        if showDeleteConfirmation {
            ZStack {
                // Background dimmer
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture {
                        if !isDeleting {
                            showDeleteConfirmation = false
                        }
                    }

                // Confirmation dialog
                VStack(spacing: 16) {
                    Text("Are you sure?")
                        .font(.headline)
                    Text("This word will be permanently deleted from your vocabook.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    if isDeleting {
                        ProgressView()
                            .padding(.vertical, 10)
                    } else {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                showDeleteConfirmation = false
                            }
                            .buttonStyle(DetailNavButtonStyle(kind: .secondary))

                            Button("Delete") {
                                Task {
                                    isDeleting = true
                                    await onDelete(card.id)
                                    // The parent view is responsible for closing the sheet.
                                    // We reset state here in case of an error.
                                    isDeleting = false
                                    showDeleteConfirmation = false
                                }
                            }
                            .buttonStyle(DetailNavButtonStyle(kind: .primary, isDestructive: true))
                        }
                    }
                }
                .padding()
                .background(Material.regularMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
                .padding(.horizontal, 40)
            }
            .transition(.opacity.animation(.easeInOut))
        }
    }


    // MARK: - Controls (Unchanged)
    private var controlsRow: some View {
        HStack(spacing: 28) {
            CircleIcon(systemName: "mic.fill") { showRecorder = true }
            CircleIcon(systemName: isRepeating ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill") {
                readTapped() // one-shot or repeat loop
            }
            CircleIcon(systemName: repeatReadingEnabled ? "repeat.circle.fill" : "repeat.circle") {
                toggleRepeat()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private var navRow: some View {
        HStack(spacing: 12) {
            Button("Previous") { goPrev() }
                .buttonStyle(DetailNavButtonStyle(kind: .secondary))
                .disabled(!canPrev)

            Button("Next") { goNext() }
                .buttonStyle(DetailNavButtonStyle(kind: .primary))
                .disabled(!canNext)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func transitionFor(_ dir: SlideDir) -> AnyTransition {
        switch dir {
        case .next:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        case .prev:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .none:
            return .identity
        }
    }

    // MARK: - Paging actions (Unchanged)
    private func goNext() {
        guard canNext else { return }
        slideDir = .next
        withAnimation(.easeInOut(duration: 0.28)) {
            index += 1
        }
    }
    private func goPrev() {
        guard canPrev else { return }
        slideDir = .prev
        withAnimation(.easeInOut(duration: 0.28)) {
            index -= 1
        }
    }

    // MARK: - Speak / Repeat (Unchanged)
    private func readTapped() {
        if repeatReadingEnabled {
            if isRepeating { stopRepeating() } else { startRepeating() }
        } else {
            onSpeak(card) { }
        }
    }
    private func startRepeating() {
        guard !isRepeating else { return }
        isRepeating = true
        func loop() {
            guard isRepeating else { return }
            onSpeak(card) {
                DispatchQueue.main.async { if self.isRepeating { loop() } }
            }
        }
        loop()
    }
    private func stopRepeating() { isRepeating = false }
    private func toggleRepeat() {
        repeatReadingEnabled.toggle()
        if !repeatReadingEnabled { stopRepeating() }
    }
}


private struct DetailNavButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    var isDestructive: Bool = false // ADDED: To style the delete button

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let primaryColor = isDestructive ? Color.red : Color.black
        
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 12)
            .background(
                Group {
                    switch kind {
                    case .primary:
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(primaryColor.opacity(pressed ? 0.85 : 1.0))
                    case .secondary:
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(pressed ? 0.92 : 1.0))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.black.opacity(0.85), lineWidth: 1)
                            )
                    }
                }
            )
            .foregroundColor(kind == .primary ? .white : .black)
            .animation(.easeInOut(duration: 0.12), value: pressed)
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
