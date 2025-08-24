// LangGo/Vocabook/FlashcardReviewView.swift
import SwiftUI
import SPConfetti
import AVFoundation
import Combine

final class ReviewSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let tts = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        tts.delegate = self
    }

    func speakOnce(card: Flashcard, completion: @escaping () -> Void) {
        self.completion = completion
        // Speak TARGET ONLY (consistent for all locales)
        let word = card.wordDefinition?.attributes.word?.data?.attributes.targetText
            ?? card.frontContent
        let u = AVSpeechUtterance(string: word)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate  = AVSpeechUtteranceDefaultSpeechRate
        tts.speak(u)
    }

    func stop() { tts.stopSpeaking(at: .immediate) }

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
    @State private var isSessionComplete = false
    @State private var showFireworks = false
    @State private var showBadge = false
    
    @AppStorage("repeatReadingEnabled") private var repeatReadingEnabled = false
    @State private var isRepeating = false
    @State private var showRecorder = false
    @StateObject private var speaker = ReviewSpeaker()
    @State private var repeatInterval: TimeInterval = 1.5   // fallback; will load from VBSetting

    var body: some View {
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

                        if let card = viewModel.reviewCards[safe: currentIndex] {
                            if let register = card.register, !register.isEmpty, register != "Neutral" {
                                HStack {
                                    Text(register)
                                        .style(.registerTag)
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
                                withAnimation(.spring) { isFlipped.toggle() }
                            }
                        }
                        
                        Spacer()
                        HStack(spacing: 28) {
                            CircleIcon(systemName: "mic.fill") { showRecorder = true }
                            CircleIcon(systemName: isRepeating ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill") { readButtonTapped() }
                            CircleIcon(systemName: repeatReadingEnabled ? "repeat.circle.fill" : "repeat.circle") { toggleRepeat() }
                        }
                        .padding(.bottom, 8)

                        Spacer()
                        
                        HStack(spacing: 20) {
                            Button(action: { markCard(.wrong) }) {
                                Text("Wrong").style(.wrongButton)
                            }
                            
                            Button(action: { markCard(.correct) }) {
                                Text("Correct").style(.correctButton)
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
                .task {
                    // Load vbSetting.interval1 once
                    if let vb = try? await DataServices.shared.settingsService.fetchVBSetting() {
                        // interval1 is assumed to be seconds; clamp to a safe minimum
                        repeatInterval = max(0.4, TimeInterval(vb.attributes.interval1))
                    }
                }
            }
            .opacity(isSessionComplete ? 0 : 1)

            if isSessionComplete {
                CelebrationView(showBadge: $showBadge, onClose: {
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

    private func readButtonTapped() {
        guard let card = currentCard else { return }
        if repeatReadingEnabled {
            if isRepeating {
                stopRepeating()
            } else {
                startRepeating(card: card)
            }
        } else {
            speaker.speakOnce(card: card) {}
        }
    }

    private func startRepeating(card: Flashcard) {
        guard !isRepeating else { return }
        isRepeating = true
        func loop() {
            guard isRepeating, let liveCard = currentCard else { return }
            speaker.speakOnce(card: liveCard) {
                DispatchQueue.main.asyncAfter(deadline: .now() + repeatInterval) {
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
        guard let card = viewModel.reviewCards[safe: currentIndex] else { return }
        // 1) Optimistically advance the UI
        goToNextCard()
        // 2) Submit review in the background
        viewModel.submitReviewOptimistic(for: card, result: answer)
    }
    
    private func goToNextCard() {
        if currentIndex < viewModel.reviewCards.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFlipped = false
                currentIndex += 1
            }
        } else {
            isSessionComplete = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showFireworks = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showBadge = true
                }
            }
        }
    }
}


// Subviews (CelebrationView, FlippableCardView, etc.) remain unchanged.
private struct CelebrationView: View {
    @Binding var showBadge: Bool
    var onClose: () -> Void

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
                CardFace(content: frontContent).opacity(isFlipped ? 0 : 1)
                CardFace(content: backContent).opacity(isFlipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
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
