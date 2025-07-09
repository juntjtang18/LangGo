import SwiftUI
import SwiftData
import AVFoundation
import os // For logging

// MARK: - Speech Manager for VocapageView
@MainActor
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentIndex: Int = -1

    private var synthesizer = AVSpeechSynthesizer()
    private var flashcards: [Flashcard] = []
    private var languageSettings: LanguageSettings?
    private var showBaseText: Bool = true
    
    private enum ReadingStep {
        case firstRead, secondRead, baseRead, finished
    }
    private var currentStep: ReadingStep = .firstRead

    override init() {
        super.init()
        self.synthesizer.delegate = self
    }

    func startReadingSession(flashcards: [Flashcard], showBaseText: Bool, languageSettings: LanguageSettings) {
        self.flashcards = flashcards
        self.languageSettings = languageSettings
        self.showBaseText = showBaseText
        self.isSpeaking = true
        self.currentIndex = 0
        self.currentStep = .firstRead
        readCurrentCard()
    }

    func stopReadingSession() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentIndex = -1
    }

    private func readCurrentCard() {
        guard currentIndex < flashcards.count, isSpeaking else {
            stopReadingSession()
            return
        }

        let card = flashcards[currentIndex]
        var textToSpeak: String
        var languageCode: String

        switch currentStep {
        case .firstRead, .secondRead:
            textToSpeak = card.backContent
            languageCode = Config.learningTargetLanguageCode
        case .baseRead:
            textToSpeak = card.frontContent
            languageCode = languageSettings?.selectedLanguageCode ?? "en-US"
        case .finished:
            goToNextCard()
            return
        }
        
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        if utterance.voice == nil {
            print("Error: Voice for language code '\(languageCode)' not available.")
            speechSynthesizer(synthesizer, didFinish: utterance)
            return
        }
        
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isSpeaking else { return }

        switch currentStep {
        case .firstRead:
            currentStep = .secondRead
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.readCurrentCard() }
        case .secondRead:
            if showBaseText {
                currentStep = .baseRead
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.readCurrentCard() }
            } else {
                currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.readCurrentCard() }
            }
        case .baseRead:
            currentStep = .finished
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.readCurrentCard() }
        case .finished:
            break
        }
    }
    
    private func goToNextCard() {
        if currentIndex < flashcards.count - 1 {
            currentIndex += 1
            currentStep = .firstRead
            readCurrentCard()
        } else {
            stopReadingSession()
        }
    }
}


struct VocapageView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings

    let vocapageId: Int
    
    @State private var vocapage: Vocapage?
    @State private var isLoading: Bool = false
    @State private var showBaseText: Bool = true // Control base text visibility
    @State private var isShowingPracticeView: Bool = false
    @State private var errorMessage: String?
    
    @StateObject private var speechManager = SpeechManager()

    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageView")

    init(vocapageId: Int) {
        self.vocapageId = vocapageId
    }
    
    // MARK: - Computed property to simplify ForEach data source
    private var sortedFlashcardsForList: [Flashcard] {
        guard let flashcards = vocapage?.flashcards else {
            return []
        }
        // This is the sorting logic
        return flashcards
            .sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading vocapage details...")
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else if let vocapage = vocapage {
                    // Pass necessary data to the new subview
                    VocapageContentListView(
                        sortedFlashcards: sortedFlashcardsForList,
                        showBaseText: showBaseText,
                        speechManager: speechManager
                    )
                } else {
                    Text("Vocapage details not available.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("My Vocabulary Notebook")
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showBaseText.toggle() }) {
                        Image(systemName: showBaseText ? "eye.slash.fill" : "eye.fill")
                            .accessibilityLabel(showBaseText ? "Hide Base Text" : "Show Base Text")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    // Pass necessary data and bindings to the new subview
                    VocapageBottomBarView(
                        vocapageFlashcards: vocapage?.flashcards, // Pass the original flashcards here
                        showBaseText: showBaseText,
                        isShowingPracticeView: $isShowingPracticeView,
                        speechManager: speechManager,
                        languageSettings: _languageSettings // Correctly pass EnvironmentObject instance
                    )
                }
            }
            .task { await fetchAndSyncVocapageDetails() }
            .fullScreenCover(isPresented: $isShowingPracticeView) {
                ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings)
            }
        }
    }

    @MainActor
    private func fetchAndSyncVocapageDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await StrapiService.shared.fetchVocapageDetails(vocapageId: vocapageId)
            let synced = try await syncVocapageFromStrapi(fetched)
            self.vocapage = synced
            logger.info("Successfully fetched and synced vocapage details for ID: \(vocapageId)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to fetch or sync vocapage details for ID: \(vocapageId). Error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    @MainActor
    @discardableResult
    private func syncVocapageFromStrapi(_ strapi: StrapiVocapage) async throws -> Vocapage {
        var fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == strapi.id })
        fetchDescriptor.fetchLimit = 1
        let vocapageToUpdate: Vocapage
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            vocapageToUpdate = existing
            vocapageToUpdate.title = strapi.attributes.title
            vocapageToUpdate.order = strapi.attributes.order ?? 0
            logger.debug("Updating existing vocapage: \(vocapageToUpdate.title)")
        } else {
            let newVoc = Vocapage(id: strapi.id, title: strapi.attributes.title, order: strapi.attributes.order ?? 0)
            modelContext.insert(newVoc)
            vocapageToUpdate = newVoc
            logger.debug("Inserting new vocapage: \(newVoc.title)")
        }
        if let data = strapi.attributes.flashcards?.data {
            var synced: [Flashcard] = []
            for item in data {
                let card = try await syncFlashcardForVocapage(item, vocapage: vocapageToUpdate)
                synced.append(card)
            }
            vocapageToUpdate.flashcards = synced
            logger.debug("Synced \(synced.count) flashcards for vocapage '\(vocapageToUpdate.title)'.")
        } else {
            vocapageToUpdate.flashcards = []
            logger.debug("No flashcards found for vocapage '\(vocapageToUpdate.title)'.")
        }
        try modelContext.save()
        return vocapageToUpdate
    }

    @MainActor
    @discardableResult
    private func syncFlashcardForVocapage(_ strapiFlashcardData: StrapiData<FlashcardAttributes>, vocapage: Vocapage) async throws -> Flashcard {
        let strapiFlashcard = strapiFlashcardData.attributes
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == strapiFlashcardData.id })
        fetchDescriptor.fetchLimit = 1

        let flashcardToUpdate: Flashcard
        if let existingFlashcard = try modelContext.fetch(fetchDescriptor).first {
            flashcardToUpdate = existingFlashcard
            let contentComponent = strapiFlashcard.content?.first

            switch contentComponent?.componentIdentifier {
            case "a.user-word-ref":
                flashcardToUpdate.frontContent = contentComponent?.userWord?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.userWord?.data?.attributes.targetText ?? "Missing Answer"
            case "a.word-ref":
                flashcardToUpdate.frontContent = contentComponent?.word?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.word?.data?.attributes.word ?? "Missing Answer"
                flashcardToUpdate.register = contentComponent?.word?.data?.attributes.register
            case "a.user-sent-ref":
                flashcardToUpdate.frontContent = contentComponent?.userSentence?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.userSentence?.data?.attributes.targetText ?? "Missing Answer"
            case "a.sent-ref":
                flashcardToUpdate.frontContent = contentComponent?.sentence?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.sentence?.data?.attributes.targetText ?? "Missing Answer"
                flashcardToUpdate.register = contentComponent?.sentence?.data?.attributes.register
            default:
                flashcardToUpdate.frontContent = "Unknown Content (Front)"
                flashcardToUpdate.backContent = "Unknown Content (Back)"
            }

            flashcardToUpdate.contentType = contentComponent?.componentIdentifier ?? ""
            flashcardToUpdate.rawComponentData = try? JSONEncoder().encode(contentComponent)
            flashcardToUpdate.lastReviewedAt = strapiFlashcard.lastReviewedAt
            flashcardToUpdate.correctStreak = strapiFlashcard.correctStreak ?? 0
            flashcardToUpdate.wrongStreak = strapiFlashcard.wrongStreak ?? 0
            flashcardToUpdate.isRemembered = strapiFlashcard.isRemembered
            flashcardToUpdate.vocapage = vocapage
            logger.debug("Updating existing flashcard: \(flashcardToUpdate.id)")
        } else {
            var front = "Missing Question"
            var back = "Missing Answer"
            var reg: String? = nil
            let contentComponent = strapiFlashcard.content?.first
            switch contentComponent?.componentIdentifier {
            case "a.user-word-ref":
                front = contentComponent?.userWord?.data?.attributes.baseText ?? front
                back = contentComponent?.userWord?.data?.attributes.targetText ?? back
            case "a.word-ref":
                front = contentComponent?.word?.data?.attributes.baseText ?? front
                back = contentComponent?.word?.data?.attributes.word ?? back
                reg = contentComponent?.word?.data?.attributes.register
            case "a.user-sent-ref":
                front = contentComponent?.userSentence?.data?.attributes.baseText ?? front
                back = contentComponent?.userSentence?.data?.attributes.targetText ?? back
            case "a.sent-ref":
                front = contentComponent?.sentence?.data?.attributes.baseText ?? front
                back = contentComponent?.sentence?.data?.attributes.targetText ?? back
                reg = contentComponent?.sentence?.data?.attributes.register
            default:
                break
            }
            let newFlashcard = Flashcard(
                id: strapiFlashcardData.id,
                frontContent: front,
                backContent: back,
                register: reg,
                contentType: contentComponent?.componentIdentifier ?? "",
                rawComponentData: try? JSONEncoder().encode(contentComponent),
                lastReviewedAt: strapiFlashcard.lastReviewedAt,
                correctStreak: strapiFlashcard.correctStreak ?? 0,
                wrongStreak: strapiFlashcard.wrongStreak ?? 0,
                isRemembered: strapiFlashcard.isRemembered
            )
            newFlashcard.vocapage = vocapage
            modelContext.insert(newFlashcard)
            logger.debug("Inserted new flashcard: \(newFlashcard.id)")
            return newFlashcard
        }

        try modelContext.save()
        return flashcardToUpdate
    }
}

// MARK: - Subviews for better organization
private struct VocapageContentListView: View {
    let sortedFlashcards: [Flashcard]
    let showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager

    var body: some View {
        if sortedFlashcards.isEmpty {
            Spacer()
            Text("No flashcards in this page.")
                .foregroundColor(.secondary)
            Spacer()
        } else {
            List {
                ForEach(sortedFlashcards.enumerated().map { (index, card) in (index, card) }, id: \.1.id) { index, card in
                    HStack {
                        Text(card.backContent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showBaseText {
                            Text(card.frontContent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 5)
                    .background(speechManager.currentIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                }
            }
        }
    }
}

private struct VocapageBottomBarView: View {
    let vocapageFlashcards: [Flashcard]? // Use the original optional array here
    let showBaseText: Bool
    @Binding var isShowingPracticeView: Bool
    @ObservedObject var speechManager: SpeechManager
    @EnvironmentObject var languageSettings: LanguageSettings // Correctly receives EnvironmentObject

    // Computed property for button disabled state
    private var isButtonDisabled: Bool {
        return speechManager.isSpeaking
    }

    var body: some View {
        HStack {
            Spacer()
            // Read Button
            Button(action: {
                if speechManager.isSpeaking {
                    speechManager.stopReadingSession()
                } else {
                    if let flashcards = vocapageFlashcards {
                        speechManager.startReadingSession(flashcards: flashcards, showBaseText: showBaseText, languageSettings: languageSettings)
                    }
                }
            }) {
                Label(speechManager.isSpeaking ? "Stop" : "Read", systemImage: speechManager.isSpeaking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .tint(speechManager.isSpeaking ? .gray : .blue)
            
            Spacer()
            Button(action: { isShowingPracticeView = true }) {
                Label("Practice", systemImage: "pencil.circle.fill")
                    .font(.title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .tint(.blue)
            .disabled(isButtonDisabled)
            
            Spacer()
        }
    }
}
