import SwiftUI
import SPConfetti // NEW: Import the confetti package
import AVFoundation   // ← add
import Combine


// Replace your speaker class signature:
final class ReviewSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let tts = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        tts.delegate = self
    }

    func speakOnce(card: Flashcard, completion: @escaping () -> Void) {
        self.completion = completion
        var parts: [String] = []
        if let word = card.wordDefinition?.attributes.word?.data?.attributes.targetText, !word.isEmpty {
            parts.append(word)
        } else {
            parts.append(card.frontContent)
        }
        if let base = card.wordDefinition?.attributes.baseText, !base.isEmpty {
            parts.append(base)
        }
        if let ex = card.wordDefinition?.attributes.exampleSentence, !ex.isEmpty {
            parts.append(ex)
        }

        let u = AVSpeechUtterance(string: parts.joined(separator: ". "))
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate  = AVSpeechUtteranceDefaultSpeechRate
        tts.speak(u)
    }

    func stop() { tts.stopSpeaking(at: .immediate) }

    // AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?(); completion = nil
    }
}
extension Notification.Name {
    static let reviewCelebrationClosed = Notification.Name("reviewCelebrationClosed")
}

struct FlashcardReviewView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: FlashcardViewModel
    
    @State private var currentIndex = 0
    @State private var isFlipped = false

    // NEW: State variables to control the completion animation
    @State private var isSessionComplete = false
    @State private var showFireworks = false
    @State private var showBadge = false
    
    
    @AppStorage("repeatReadingEnabled") private var repeatReadingEnabled = false
    @State private var isRepeating = false
    @State private var showRecorder = false
    @StateObject private var speaker = ReviewSpeaker()   // local TTS helper


    var body: some View {
        // NEW: ZStack to allow the celebration view to overlay the main content
        ZStack {
            NavigationStack {
                VStack {
                    if viewModel.reviewCards.isEmpty {
                        Spacer()
                        Text("No cards to review.")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Spacer()
                    } else {
                        // Progress indicators
                        VStack {
                            ProgressView(value: Double(currentIndex + 1), total: Double(viewModel.reviewCards.count)) {
                                Text("Progress")
                            }
                            .progressViewStyle(.linear)
                            
                            Text(progressCountString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        
                        Spacer()

                        // The Flippable Card View
                        if let card = viewModel.reviewCards[safe: currentIndex] {
                            
                            // Display Register
                            if let register = card.register, !register.isEmpty, register != "Neutral" {
                                HStack {
                                    Text(register)
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(.gray)
                                        .cornerRadius(8)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                            }
                            
                            FlippableCardView(
                                frontContent: card.frontContent,
                                backContent: card.backContent,
                                isFlipped: $isFlipped
                            )
                            .onTapGesture {
                                withAnimation(.spring) {
                                    isFlipped.toggle()
                                }
                            }
                        }
                        
                        Spacer()
                        // Controls row (Mic / Speaker / Repeat)
                        HStack(spacing: 28) {
                            // Mic: show recorder
                            CircleIcon(systemName: "mic.fill") { showRecorder = true }

                            // Speaker: single cycle (or toggle repeat loop if repeat is ON)
                            CircleIcon(systemName: isRepeating ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill") {
                                readButtonTapped()
                            }

                            // Repeat toggle
                            CircleIcon(systemName: repeatReadingEnabled ? "repeat.circle.fill" : "repeat.circle") {
                                toggleRepeat()
                            }
                        }
                        .padding(.bottom, 8)

                        Spacer()
                        
                        // Action Buttons
                        HStack(spacing: 20) {
                            Button(action: { markCard(.wrong) }) {
                                Text("Wrong")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: { markCard(.correct) }) {
                                Text("Correct")
                                     .font(.title2)
                                     .fontWeight(.bold)
                                     .frame(maxWidth: .infinity)
                                     .padding()
                                     .background(Color.green.opacity(0.8))
                                     .foregroundColor(.white)
                                     .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle("Review Session")
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
            // NEW: Hide the navigation stack when the session is complete to avoid visual glitches
            .opacity(isSessionComplete ? 0 : 1)

            // NEW: Celebration View Overlay
            if isSessionComplete {
                CelebrationView(showBadge: $showBadge, onClose: {
                    // Notify VocabookView, then dismiss the review screen
                    NotificationCenter.default.post(name: .reviewCelebrationClosed, object: nil)
                    dismiss()
                })
                .confetti(isPresented: $showFireworks,
                          animation: .fullWidthToUp,
                          particles: [.star, .arc, .circle],
                          duration: 3.0)
            }
            if showRecorder {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)

                RecordModalView(
                    phrase: currentWordText,
                    onClose: { showRecorder = false }
                )
                .transition(.scale.combined(with: .opacity))
            }

        }
    }
    private var currentCard: Flashcard? { viewModel.reviewCards[safe: currentIndex] }
    private var currentWordText: String {
        currentCard?.wordDefinition?.attributes.word?.data?.attributes.targetText
        ?? currentCard?.frontContent ?? ""
    }
    // MARK: - Reading logic (mirrors WordDetailSheet behavior)
    private func readButtonTapped() {
        guard let card = currentCard else { return }
        if repeatReadingEnabled {
            if isRepeating {
                stopRepeating()
            } else {
                startRepeating(card: card)
            }
        } else {
            speaker.speakOnce(card: card) { /* no-op */ }
        }
    }

    private func startRepeating(card: Flashcard) {
        guard !isRepeating else { return }
        isRepeating = true

        func loop() {
            guard isRepeating, let liveCard = currentCard else { return }
            speaker.speakOnce(card: liveCard) {
                DispatchQueue.main.async {
                    if self.isRepeating { loop() }
                }
            }
        }
        loop()
    }

    private func stopRepeating() {
        isRepeating = false
        speaker.stop()
    }

    private func toggleRepeat() {
        repeatReadingEnabled.toggle()
        if !repeatReadingEnabled { stopRepeating() }
    }

    private var progressCountString: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        let format = NSLocalizedString("%lld of %lld", comment: "Progress count format (e.g., 1 of 10)")
        return String(format: format, currentIndex + 1, viewModel.reviewCards.count)
    }
    
    private func markCard(_ answer: ReviewResult) {
        guard let currentCard = viewModel.reviewCards[safe: currentIndex] else { return }
        viewModel.markReview(for: currentCard, result: answer)
        goToNextCard()
    }
    
    // NEW: Updated logic to handle the end-of-session animation
    private func goToNextCard() {
        if currentIndex < viewModel.reviewCards.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFlipped = false
                currentIndex += 1
            }
        } else {
            // All cards have been reviewed, start the celebration sequence
            isSessionComplete = true
            
            // 1. Trigger fireworks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showFireworks = true
            }
            
            // 2. Show the badge after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showBadge = true
                }
            }
            
        }
    }
}

// MARK: - Subviews

// NEW: A dedicated view for the celebration animation
private struct CelebrationView: View {
    @Binding var showBadge: Bool
    var onClose: () -> Void          // ← add this

    var body: some View {
        VStack {
            Spacer()
            
            if showBadge {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .frame(width: 150, height: 150)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        
                        Image(systemName: "star.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                    }
                    
                    Text("Session Complete!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 2)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct FlippableCardView: View {
    let frontContent: String
    let backContent: String
    @Binding var isFlipped: Bool

    var body: some View {
        ZStack {
            Group {
                CardFace(content: frontContent)
                    .opacity(isFlipped ? 0 : 1)
                
                CardFace(content: backContent)
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }
}

private struct CardFace: View {
    let content: String
    
    var body: some View {
        Text(content)
            .font(.system(size: 48, weight: .bold))
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(radius: 5)
            .padding(.horizontal)
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
