import SwiftUI
import SwiftData
import AVFoundation
import os // For logging


// MARK: - Vocapage Loader (NEW)
// This new ObservableObject class handles all data loading and caching.
// Its lifecycle is tied to the VocapageHostView, so its tasks are not
// cancelled during swipes.
@MainActor
@Observable
class VocapageLoader {
    private var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageLoader")

    // State properties to hold the data and loading status for each page
    var vocapages: [Int: Vocapage] = [:]
    var loadingStatus: [Int: Bool] = [:]
    var errorMessages: [Int: String] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPage(withId vocapageId: Int) async {
        // Don't re-load if already loading or loaded
        if loadingStatus[vocapageId] == true || vocapages[vocapageId] != nil {
            return
        }

        loadingStatus[vocapageId] = true
        errorMessages[vocapageId] = nil

        do {
            // 1. Fetch the Vocapage object from SwiftData
            let fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == vocapageId })
            guard let page = (try modelContext.fetch(fetchDescriptor)).first else {
                throw NSError(domain: "VocapageLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find vocapage with ID \(vocapageId)."])
            }

            // 2. Fetch the flashcards for this page from the server
            let vbSetting = try await StrapiService.shared.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            let response = try await StrapiService.shared.fetchFlashcards(page: page.order, pageSize: pageSize)
            
            // 3. Sync flashcards and link them to the vocapage object
            var syncedFlashcards: [Flashcard] = []
            if let strapiFlashcards = response.data {
                for strapiCard in strapiFlashcards {
                    let syncedCard = try await syncFlashcard(strapiCard)
                    syncedFlashcards.append(syncedCard)
                }
            }
            page.flashcards = syncedFlashcards
            
            // 4. Save to the database and update our state
            try modelContext.save()
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }

        loadingStatus[vocapageId] = false
    }

    private func syncFlashcard(_ strapiFlashcardData: StrapiFlashcard) async throws -> Flashcard {
        let strapiCard = strapiFlashcardData.attributes
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == strapiFlashcardData.id })
        fetchDescriptor.fetchLimit = 1

        let flashcard: Flashcard
        if let existingFlashcard = try modelContext.fetch(fetchDescriptor).first {
            flashcard = existingFlashcard
        } else {
            flashcard = Flashcard(id: strapiFlashcardData.id, frontContent: "", backContent: "", register: nil, contentType: "", rawComponentData: nil, lastReviewedAt: nil, correctStreak: 0, wrongStreak: 0, isRemembered: false)
            modelContext.insert(flashcard)
        }

        let contentComponent = strapiCard.content?.first
        switch contentComponent?.componentIdentifier {
        case "a.user-word-ref":
            flashcard.frontContent = contentComponent?.userWord?.data?.attributes.baseText ?? "Missing Question"
            flashcard.backContent = contentComponent?.userWord?.data?.attributes.targetText ?? "Missing Answer"
        case "a.word-ref":
            flashcard.frontContent = contentComponent?.word?.data?.attributes.baseText ?? "Missing Question"
            flashcard.backContent = contentComponent?.word?.data?.attributes.word ?? "Missing Answer"
            flashcard.register = contentComponent?.word?.data?.attributes.register
        case "a.user-sent-ref":
            flashcard.frontContent = contentComponent?.userSentence?.data?.attributes.baseText ?? "Missing Question"
            flashcard.backContent = contentComponent?.userSentence?.data?.attributes.targetText ?? "Missing Answer"
        case "a.sent-ref":
            flashcard.frontContent = contentComponent?.sentence?.data?.attributes.baseText ?? "Missing Question"
            flashcard.backContent = contentComponent?.sentence?.data?.attributes.targetText ?? "Missing Answer"
            flashcard.register = contentComponent?.sentence?.data?.attributes.register
        default:
            flashcard.frontContent = "Unknown Content (Front)"
            flashcard.backContent = "Unknown Content (Back)"
        }

        flashcard.contentType = contentComponent?.componentIdentifier ?? ""
        flashcard.rawComponentData = try? JSONEncoder().encode(contentComponent)
        flashcard.lastReviewedAt = strapiCard.lastReviewedAt
        flashcard.correctStreak = strapiCard.correctStreak ?? 0
        flashcard.wrongStreak = strapiCard.wrongStreak ?? 0
        flashcard.isRemembered = strapiCard.isRemembered

        return flashcard
    }
}


// MARK: - VocapageHostView (REVISED)
struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var loader: VocapageLoader
    
    @State private var showBaseText: Bool = true
    @State private var isShowingPracticeView: Bool = false
    @StateObject private var speechManager = SpeechManager()
    
    let allVocapageIds: [Int]
    @State private var currentPageIndex: Int

    init(allVocapageIds: [Int], selectedVocapageId: Int, modelContext: ModelContext) {
        self.allVocapageIds = allVocapageIds
        _currentPageIndex = State(initialValue: allVocapageIds.firstIndex(of: selectedVocapageId) ?? 0)
        _loader = State(initialValue: VocapageLoader(modelContext: modelContext))
    }

    private var currentVocapage: Vocapage? {
        guard !allVocapageIds.isEmpty else { return nil }
        let currentId = allVocapageIds[currentPageIndex]
        return loader.vocapages[currentId]
    }

    var body: some View {
        TabView(selection: $currentPageIndex) {
            ForEach(allVocapageIds.indices, id: \.self) { index in
                VocapageView(
                    vocapageId: allVocapageIds[index],
                    showBaseText: $showBaseText,
                    speechManager: speechManager,
                    loader: loader
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle("My Vocabulary Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
                }
            }
            ToolbarItem(placement: .bottomBar) {
                VocapageBottomBarView(
                    vocapageFlashcards: currentVocapage?.flashcards,
                    showBaseText: showBaseText,
                    isShowingPracticeView: $isShowingPracticeView,
                    speechManager: speechManager
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) {
            speechManager.stopReadingSession()
        }
    }
}


// MARK: - Speech Manager for VocapageView
@MainActor
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentIndex: Int = -1

    private var synthesizer = AVSpeechSynthesizer()
    private var flashcards: [Flashcard] = []
    private var languageSettings: LanguageSettings?
    private var showBaseText: Bool = true
    
    private var interval1: TimeInterval = 1.5
    private var interval2: TimeInterval = 2.0
    private var interval3: TimeInterval = 2.0
    
    private enum ReadingStep {
        case firstReadTarget, secondReadTarget, readBase, finished
    }
    private var currentStep: ReadingStep = .firstReadTarget

    override init() {
        super.init()
        self.synthesizer.delegate = self
    }

    func startReadingSession(flashcards: [Flashcard], showBaseText: Bool, languageSettings: LanguageSettings, settings: VBSettingAttributes) {
        self.flashcards = flashcards
        self.languageSettings = languageSettings
        self.showBaseText = showBaseText
        
        self.interval1 = settings.interval1
        self.interval2 = settings.interval2
        self.interval3 = settings.interval3
        
        self.isSpeaking = true
        self.currentIndex = 0
        self.currentStep = .firstReadTarget
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
        let textToSpeak: String
        let languageCode: String

        switch currentStep {
        case .firstReadTarget, .secondReadTarget:
            textToSpeak = card.backContent
            languageCode = Config.learningTargetLanguageCode
        case .readBase:
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

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isSpeaking else { return }

            switch self.currentStep {
            case .firstReadTarget:
                self.currentStep = .secondReadTarget
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval1) { self.readCurrentCard() }
            
            case .secondReadTarget:
                if self.showBaseText {
                    self.currentStep = .readBase
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval2) { self.readCurrentCard() }
                } else {
                    self.currentStep = .finished
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentCard() }
                }
            
            case .readBase:
                self.currentStep = .finished
                DispatchQueue.main.asyncAfter(deadline: .now() + self.interval3) { self.readCurrentCard() }

            case .finished:
                break
            }
        }
    }
    
    private func goToNextCard() {
        if currentIndex < flashcards.count - 1 {
            currentIndex += 1
            currentStep = .firstReadTarget
            readCurrentCard()
        } else {
            stopReadingSession()
        }
    }
}


struct VocapageView: View {
    @EnvironmentObject var languageSettings: LanguageSettings

    let vocapageId: Int
    @Binding var showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager
    @State var loader: VocapageLoader
    
    private var vocapage: Vocapage? {
        loader.vocapages[vocapageId]
    }
    
    private var isLoading: Bool {
        loader.loadingStatus[vocapageId] ?? false
    }
    
    private var errorMessage: String? {
        loader.errorMessages[vocapageId]
    }
    
    private var sortedFlashcardsForList: [Flashcard] {
        guard let flashcards = vocapage?.flashcards else { return [] }
        return flashcards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
    }

    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
            } else if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
                    .multilineTextAlignment(.center)
            } else if vocapage != nil {
                VocapageContentListView(
                    sortedFlashcards: sortedFlashcardsForList,
                    showBaseText: showBaseText,
                    speechManager: speechManager
                )
            } else {
                Text("Swipe to load content.")
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await loader.loadPage(withId: vocapageId)
        }
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
            ProgressView()
            Spacer()
        } else {
            ScrollViewReader { proxy in
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
                        .id(card.id)
                        .padding(.vertical, 5)
                        .background(speechManager.currentIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                    }
                }
                .onChange(of: speechManager.currentIndex) { _, newIndex in
                    if newIndex >= 0 && newIndex < sortedFlashcards.count {
                        let cardIdToScroll = sortedFlashcards[newIndex].id
                        withAnimation {
                            proxy.scrollTo(cardIdToScroll, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

private struct VocapageBottomBarView: View {
    let vocapageFlashcards: [Flashcard]?
    let showBaseText: Bool
    @Binding var isShowingPracticeView: Bool
    @ObservedObject var speechManager: SpeechManager
    @EnvironmentObject var languageSettings: LanguageSettings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                if speechManager.isSpeaking {
                    speechManager.stopReadingSession()
                } else {
                    Task {
                        do {
                            let settings = try await StrapiService.shared.fetchVBSetting()
                            if let flashcards = vocapageFlashcards, !flashcards.isEmpty {
                                speechManager.startReadingSession(
                                    flashcards: flashcards,
                                    showBaseText: showBaseText,
                                    languageSettings: languageSettings,
                                    settings: settings.attributes
                                )
                            }
                        } catch {
                            print("Failed to fetch vocabook settings: \(error)")
                        }
                    }
                }
            }) {
                Label("Read", systemImage: speechManager.isSpeaking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .tint(speechManager.isSpeaking ? .gray : .blue)
            .disabled(vocapageFlashcards?.isEmpty ?? true)
            
            Spacer()
            Button(action: { isShowingPracticeView = true }) {
                Label("Practice", systemImage: "pencil.circle.fill")
                    .font(.title)
            }
            .tint(.blue)
            .disabled(speechManager.isSpeaking || vocapageFlashcards?.isEmpty ?? true)
            .fullScreenCover(isPresented: $isShowingPracticeView) {
                 ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings)
            }
            Spacer()
        }
        .padding()
    }
}
