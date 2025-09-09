import SwiftUI
import Combine

extension Notification.Name {
    static let flashcardDeleted = Notification.Name("flashcardDeleted")
}

struct WordDetailSheet: View {
    // Input
    private let initialIndex: Int
    private let initialCards: [Flashcard]
    let showBaseText: Bool
    let showNavRow: Bool   // ← NEW
    
    // Sheet control
    @Environment(\.dismiss) private var dismiss
    
    // Local mutable models
    @State private var cards: [Flashcard]
    @State private var index: Int
    
    // Read / settings
    @AppStorage("repeatReadingEnabled") private var repeatReadingEnabled: Bool = false
    @State private var isRepeating = false
    @State private var showRecorder = false
    @State private var vbSettings: VBSettingAttributes?
    
    // UI state
    private enum SlideDir { case none, next, prev }
    @State private var slideDir: SlideDir = .none
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isFetchingSettings = false
    
    private var card: Flashcard { cards[index] }
    private var canPrev: Bool { index > 0 }
    private var canNext: Bool { index < cards.count - 1 }
    @StateObject private var speechManager = SpeechManager()
    
    init(
        cards: [Flashcard],
        initialIndex: Int,
        showBaseText: Bool,
        showNavRow: Bool = true
    ) {
        self.initialCards = cards
        self._cards = State(initialValue: cards)
        self.initialIndex = initialIndex
        self._index = State(initialValue: initialIndex)
        self.showBaseText = showBaseText
        self.showNavRow = showNavRow
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Close
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                }
            }
            
            // Content
            ZStack {
                content(for: card)
                    .id(card.id)
                    .transition(transitionFor(slideDir))
            }
            .animation(.easeInOut(duration: 0.28), value: card.id)
            
            controlsRow
            if showNavRow {
                navRow
            }
        }
        .padding(.bottom, 12)
        .overlay(deleteConfirmationOverlay)
        .task {
            await ensureVBSettings()
        }
    }
    
    // MARK: - Content
    @ViewBuilder
    private func content(for card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(card.wordDefinition?.attributes.word?.data?.attributes.targetText ?? card.frontContent)
                    .font(.title2.weight(.bold))
                
                if let pos = card.wordDefinition?.attributes.partOfSpeech?.data?.attributes.name {
                    Text("(\(pos))")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Spacer()
                
                Menu {
                    Button("Edit Word") {
                        // Hook up later if needed
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
    
    // MARK: - Delete overlay
    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        if showDeleteConfirmation {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture {
                        if !isDeleting { showDeleteConfirmation = false }
                    }

                if isDeleting {
                    // 🔄 No background card while deleting — just the spinner (and optional label)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Deleting…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40)
                    .allowsHitTesting(false) // block taps entirely while in-flight
                } else {
                    // 🗂️ Normal confirmation dialog (with background)
                    VStack(spacing: 16) {
                        Text("Are you sure?").font(.headline)
                        Text("This word will be permanently deleted from your vocabook.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("Cancel") { showDeleteConfirmation = false }
                                .buttonStyle(DetailNavButtonStyle(kind: .secondary))
                            Button("Delete") { Task { await deleteCurrentCard() } }
                                .buttonStyle(DetailNavButtonStyle(kind: .primary, isDestructive: true))
                        }
                    }
                    .padding()
                    .background(Material.regularMaterial)   // ← applied only when NOT deleting
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .padding(.horizontal, 40)
                }
            }
            .transition(.opacity.animation(.easeInOut))
        }
    }


    
    // MARK: - Controls
    private var controlsRow: some View {
        HStack(spacing: 28) {
            CircleIcon(systemName: "mic.fill") { showRecorder = true }
            CircleIcon(systemName: isRepeating ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill") {
                readTapped()
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
        case .next: return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        case .prev: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .none: return .identity
        }
    }
    
    // MARK: - Paging
    private func goNext() {
        guard canNext else { return }
        slideDir = .next
        withAnimation(.easeInOut(duration: 0.28)) { index += 1 }
    }
    private func goPrev() {
        guard canPrev else { return }
        slideDir = .prev
        withAnimation(.easeInOut(duration: 0.28)) { index -= 1 }
    }
    
    // MARK: - Read / Repeat
    private func readTapped() {
        if repeatReadingEnabled {
            if isRepeating { stopRepeating() } else { startRepeating() }
        } else {
            speakOnce()
        }
    }
    
    private func ensureVBSettings() async {
        guard vbSettings == nil, !isFetchingSettings else { return }
        isFetchingSettings = true
        defer { isFetchingSettings = false }
        vbSettings = try? await DataServices.shared.settingsService.fetchVBSetting().attributes
    }
    
    private func speakOnce() {
        guard let vb = vbSettings else { return }
        speechManager.stop()
        speechManager.speak(card: card, showBaseText: showBaseText, settings: vb, onComplete: {})
    }
    
    private func startRepeating() {
        guard !isRepeating else { return }
        isRepeating = true
        
        func loop() {
            guard isRepeating else { return }
            if let vb = vbSettings {
                speechManager.speak(card: card, showBaseText: showBaseText, settings: vb) {
                    DispatchQueue.main.async { if self.isRepeating { loop() } }
                }
            } else {
                isRepeating = false
            }
        }
        loop()
    }
    private func stopRepeating() { isRepeating = false }
    private func toggleRepeat() {
        repeatReadingEnabled.toggle()
        if !repeatReadingEnabled { stopRepeating() }
    }
    
    // MARK: - Delete
    private func deleteCurrentCard() async {
        guard index < cards.count else { return }
        isDeleting = true
        defer { isDeleting = false }

        let id = cards[index].id
        do {
            try await DataServices.shared.flashcardService.deleteFlashcard(cardId: id)
            NotificationCenter.default.post(name: .flashcardDeleted, object: id)

            // Always close after delete (no navigation to other words)
            await MainActor.run {
                showDeleteConfirmation = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                showDeleteConfirmation = false
                // (Optional) Show a toast or alert here.
            }
        }
    }

    // MARK: - Helper
    @inline(__always)
    private func nextIndexAfterDeletion(deleting i: Int, totalCount: Int) -> Int {
        // If deleting the last item, select the previous one; otherwise select the same slot
        return (i == totalCount - 1) ? max(0, i - 1) : i
    }
}

// --- styles unchanged
private struct DetailNavButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    var isDestructive: Bool = false

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
