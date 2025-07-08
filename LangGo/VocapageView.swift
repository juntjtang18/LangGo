import SwiftUI
import SwiftData
import AVFoundation
import os // For logging

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
                    if let flashcards = vocapage.flashcards, !flashcards.isEmpty {
                        List {
                            ForEach(Array(flashcards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) }).enumerated()), id: \.element.id) { index, card in
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
                    } else {
                        Spacer()
                        Text("No flashcards in this page.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
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
                    Button(action: {
                        showBaseText.toggle()
                    }) {
                        Image(systemName: showBaseText ? "eye.slash.fill" : "eye.fill")
                            .accessibilityLabel(showBaseText ? "Hide Base Text" : "Show Base Text")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        // Read button: reads flashcards sequentially
                        Button(action: {
                            if let flashcards = vocapage?.flashcards {
                                let sortedCards = flashcards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
                                speechManager.startReading(sortedCards, showBaseText: showBaseText)
                            }
                        }) {
                            Label("Read", systemImage: "play.circle.fill")
                                .font(.title)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .tint(.blue)
                        Spacer()
                        // Practice button: opens practice view
                        Button(action: {
                            isShowingPracticeView = true
                        }) {
                            Label("Practice", systemImage: "play.circle.fill")
                                .font(.title)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .tint(.blue)
                        Spacer()
                        // Placeholder to balance layout
                        Button(action: {}) {
                            Label("", systemImage: "circle")
                                .font(.title)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .opacity(0)
                        }
                        .disabled(true)
                        Spacer()
                    }
                }
            }
            .task {
                await fetchAndSyncVocapageDetails()
            }
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
            let contentComponent = strapiFlashcard.content?.first
            var front: String = "Missing Question"
            var back: String = "Missing Answer"
            var reg: String? = nil
            let type: String = contentComponent?.componentIdentifier ?? ""
            let rawData: Data? = try? JSONEncoder().encode(contentComponent)

            switch contentComponent?.componentIdentifier {
            case "a.user-word-ref":
                front = contentComponent?.userWord?.data?.attributes.baseText ?? front
                back = contentComponent?.userWord?.data?.attributes.targetText ?? back
            case "a.word-ref":
                front = contentComponent?.word?.data?.attributes.baseText ?? front
                back = contentComponent?.word?.data?.attributes.word ?? back
                reg = contentComponent?.word?.data?.attributes.register ?? reg
            case "a.user-sent-ref":
                front = contentComponent?.userSentence?.data?.attributes.baseText ?? front
                back = contentComponent?.userSentence?.data?.attributes.targetText ?? back
            case "a.sent-ref":
                front = contentComponent?.sentence?.data?.attributes.baseText ?? front
                back = contentComponent?.sentence?.data?.attributes.targetText ?? back
                reg = contentComponent?.sentence?.data?.attributes.register ?? reg
            default:
                break
            }

            let newFlashcard = Flashcard(
                id: strapiFlashcardData.id,
                frontContent: front,
                backContent: back,
                register: reg,
                contentType: type,
                rawComponentData: rawData,
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

// MARK: - Speech Manager for VocapageView
private class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var currentIndex: Int = -1
    private var flashcards: [Flashcard] = []
    private var showBaseText: Bool = true
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startReading(_ flashcards: [Flashcard], showBaseText: Bool) {
        synthesizer.stopSpeaking(at: .immediate)
        self.flashcards = flashcards
        self.showBaseText = showBaseText
        self.currentIndex = 0
        speakCurrentCard()
    }

    private func speakCurrentCard() {
        guard currentIndex >= 0 && currentIndex < flashcards.count else {
            currentIndex = -1
            return
        }
        let card = flashcards[currentIndex]
        var textToSpeak = card.backContent
        if showBaseText {
            textToSpeak += " " + card.frontContent
        }
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.languageCode ?? "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.currentIndex += 1
            if self.currentIndex < self.flashcards.count {
                self.speakCurrentCard()
            } else {
                self.currentIndex = -1
            }
        }
    }
}
