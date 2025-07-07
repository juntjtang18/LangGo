import SwiftUI
import SwiftData
import AVFoundation
import os

@Observable
class ReadFlashcardViewModel: NSObject, AVSpeechSynthesizerDelegate {
    // MARK: - Public Properties
    var flashcards: [Flashcard] = []
    var currentCardIndex: Int = 0
    var isReading = false
    var isLoading = false
    var readingState: ReadingState = .idle
    
    enum ReadingState {
        case idle, readingWord, readingBaseText, paused
    }

    // MARK: - Private Properties
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ReadFlashcardViewModel")
    private var modelContext: ModelContext
    private var languageSettings: LanguageSettings // To get the correct language code
    
    private enum ReadingStep {
        case firstWord, secondWord, baseText, finished
    }
    private var currentStep: ReadingStep = .firstWord

    // MARK: - Initialization
    init(modelContext: ModelContext, languageSettings: LanguageSettings) {
        self.modelContext = modelContext
        self.languageSettings = languageSettings
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods
    @MainActor
    func fetchFlashcards() async {
        isLoading = true
        do {
            // Use StrapiService to fetch review flashcards
            let fetchedData: StrapiResponse = try await StrapiService.shared.fetchReviewFlashcards()
            var processedCards: [Flashcard] = []

            for strapiCard in fetchedData.data {
                let card = try await syncCard(strapiCard)
                processedCards.append(card)
            }
            try modelContext.save()
            
            self.flashcards = processedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("Successfully loaded \(self.flashcards.count) cards for reading.")
        } catch {
            logger.error("Failed to fetch or process flashcards for reading: \(error.localizedDescription)")
        }
        isLoading = false
    }

    @MainActor
    func startReadingSession() {
        guard !flashcards.isEmpty else {
            logger.warning("No flashcards to read.")
            return
        }
        isReading = true
        currentStep = .firstWord
        readCurrentCard()
    }

    func stopReading() {
        isReading = false
        synthesizer.stopSpeaking(at: .immediate)
        readingState = .idle
    }

    @MainActor
    func skipToNextCard() {
        synthesizer.stopSpeaking(at: .immediate)
        goToNextCard(animate: false) // Go to next card without the speech delay
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            guard isReading else { return }
            
            readingState = .paused
            
            switch currentStep {
            case .firstWord:
                currentStep = .secondWord
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.readCurrentCard() }
            case .secondWord:
                currentStep = .baseText
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.readCurrentCard() }
            case .baseText:
                currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.goToNextCard() }
            case .finished:
                break
            }
        }
    }

    // MARK: - Private Methods
    @MainActor
    private func readCurrentCard() {
        guard isReading, let card = flashcards[safe: currentCardIndex] else {
            stopReading()
            return
        }

        let textToSpeak: String
        let languageCode: String

        switch currentStep {
        case .firstWord, .secondWord:
            // This is the English 'word' from Strapi, which is backContent locally
            textToSpeak = card.backContent
            languageCode = "en-US"
            readingState = .readingWord
        case .baseText:
            // This is the Chinese 'base_text' from Strapi, which is frontContent locally
            textToSpeak = card.frontContent
            languageCode = self.languageSettings.selectedLanguageCode // FIX: Use dynamic language code
            readingState = .readingBaseText
        case .finished:
            return
        }

        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        if utterance.voice == nil {
            logger.error("Error: The voice for language code '\(languageCode)' is not available on this device.")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
    
    @MainActor
    private func goToNextCard(animate: Bool = true) {
        // FIX: Looping logic
        if currentCardIndex >= flashcards.count - 1 {
            // Reached the end, loop back to the beginning
            currentCardIndex = 0
        } else {
            // Go to the next card
            currentCardIndex += 1
        }
        
        // If we are animating as part of normal speech flow, add a delay.
        // If we are skipping, no delay is needed.
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.currentStep = .firstWord
                self.readCurrentCard()
            }
        } else {
            self.currentStep = .firstWord
            self.readCurrentCard()
        }
    }
    
    @MainActor
    @discardableResult
    private func syncCard(_ strapiCard: StrapiFlashcard) async throws -> Flashcard {
        // Same as before...
        guard let component = strapiCard.attributes.content.first else {
            throw NSError(domain: "CardSyncError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Card \(strapiCard.id) has no content component."])
        }

        var frontContent: String?, backContent: String?, register: String?

        switch component.componentIdentifier {
        case "a.user-word-ref":
            frontContent = component.userWord?.data?.attributes.baseText
            backContent = component.userWord?.data?.attributes.targetText // Changed to use the new field
        case "a.word-ref":
            frontContent = component.word?.data?.attributes.baseText
            backContent = component.word?.data?.attributes.word
            register = component.word?.data?.attributes.register
        case "a.user-sent-ref":
            frontContent = component.userSentence?.data?.attributes.baseText
            backContent = component.userSentence?.data?.attributes.targetText
        case "a.sent-ref":
            frontContent = component.sentence?.data?.attributes.baseText
            backContent = component.sentence?.data?.attributes.targetText
            register = component.sentence?.data?.attributes.register
        default:
            logger.warning("Unrecognized component type: \(component.componentIdentifier)")
        }

        let finalFront = frontContent ?? "Missing Question"
        let finalBack = backContent ?? "Missing Answer"
        let cardId = strapiCard.id
        
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
        fetchDescriptor.fetchLimit = 1

        if let cardToUpdate = try modelContext.fetch(fetchDescriptor).first {
            cardToUpdate.frontContent = finalFront
            cardToUpdate.backContent = finalBack
            cardToUpdate.register = register
            cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
            return cardToUpdate
        } else {
            let newCard = Flashcard(
                id: cardId, frontContent: finalFront, backContent: finalBack, register: register,
                contentType: component.componentIdentifier, rawComponentData: nil,
                lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                correctStreak: strapiCard.attributes.correctStreak ?? 0,
                wrongStreak: strapiCard.attributes.wrongStreak ?? 0,
                isRemembered: strapiCard.attributes.isRemembered
            )
            modelContext.insert(newCard)
            return newCard
        }
    }
}
