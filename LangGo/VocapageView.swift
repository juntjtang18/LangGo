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

            // 2. Fetch and sync the flashcards for this page from the server
            let vbSetting = try await StrapiService.shared.fetchVBSetting()
            let pageSize = vbSetting.attributes.wordsPerPage
            let syncedFlashcards = try await StrapiService.shared.fetchFlashcards(page: page.order, pageSize: pageSize, modelContext: modelContext)
            
            // 3. Link flashcards to the vocapage object and save
            page.flashcards = syncedFlashcards
            try modelContext.save()
            vocapages[vocapageId] = page

        } catch {
            logger.error("Failed to load details for vocapage \(vocapageId): \(error.localizedDescription)")
            errorMessages[vocapageId] = error.localizedDescription
        }

        loadingStatus[vocapageId] = false
    }
}


// MARK: - VocapageHostView (REVISED)
struct VocapageHostView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var loader: VocapageLoader
    
    // Use @AppStorage to automatically save the user's preference
    @AppStorage("showBaseTextInVocapage") private var showBaseText: Bool = true
    
    @State private var isShowingExamView: Bool = false
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
    
    // REFACTORED: Sort the list once here.
    private var sortedFlashcardsForCurrentPage: [Flashcard] {
        return currentVocapage?.flashcards?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        TabView(selection: $currentPageIndex) {
            ForEach(allVocapageIds.indices, id: \.self) { index in
                // REFACTORED: Pass the vocapage object directly, as it contains the order info
                VocapageView(
                    vocapage: loader.vocapages[allVocapageIds[index]],
                    sortedFlashcards: loader.vocapages[allVocapageIds[index]]?.flashcards?.sorted { $0.id < $1.id } ?? [],
                    isLoading: loader.loadingStatus[allVocapageIds[index]] ?? false,
                    errorMessage: loader.errorMessages[allVocapageIds[index]],
                    showBaseText: $showBaseText,
                    speechManager: speechManager,
                    onLoad: {
                        Task {
                            await loader.loadPage(withId: allVocapageIds[index])
                        }
                    }
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
                // REFACTORED: Pass the single sorted list to the bottom bar.
                VocapageBottomBarView(
                    sortedFlashcards: sortedFlashcardsForCurrentPage,
                    showBaseText: showBaseText,
                    isShowingExamView: $isShowingExamView,
                    speechManager: speechManager
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: currentPageIndex) {
            speechManager.stopReadingSession()
        }
        .sheet(isPresented: $isShowingExamView) {
            if let vocapage = currentVocapage {
                ExamView(vocapage: vocapage)
            }
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
    let vocapage: Vocapage?
    let sortedFlashcards: [Flashcard] // REFACTORED: Receive the pre-sorted list
    let isLoading: Bool
    let errorMessage: String?
    @Binding var showBaseText: Bool
    @ObservedObject var speechManager: SpeechManager
    let onLoad: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
            
            VStack {
                if isLoading {
                    ProgressView()
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                        .multilineTextAlignment(.center)
                } else if let vocapage = vocapage {
                    // REFACTORED: Pass the pre-sorted list directly
                    VocapageContentListView(
                        sortedFlashcards: sortedFlashcards,
                        showBaseText: showBaseText,
                        speechManager: speechManager
                    )
                    
                    Text("\(vocapage.order)")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                } else {
                    Text("Swipe to load content.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            onLoad()
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
                    // Transparent spacer to push the content down
                    Section(header: Color.clear.frame(height: 10)) {
                        ForEach(sortedFlashcards.enumerated().map { (index, card) in (index, card) }, id: \.1.id) { index, card in
                            HStack {
                                Text(card.backContent)
                                    .font(.system(.title3, design: .serif))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if showBaseText {
                                    Text(card.frontContent)
                                        .font(.system(.body, design: .serif))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .id(card.id)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                            .background(speechManager.currentIndex == index ? Color.yellow.opacity(0.3) : Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
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
    let sortedFlashcards: [Flashcard] // REFACTORED: Receive the pre-sorted list
    let showBaseText: Bool
    @Binding var isShowingExamView: Bool
    @ObservedObject var speechManager: SpeechManager
    @EnvironmentObject var languageSettings: LanguageSettings

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
                            // REFACTORED: Use the pre-sorted list directly
                            if !sortedFlashcards.isEmpty {
                                speechManager.startReadingSession(
                                    flashcards: sortedFlashcards,
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
                Image(systemName: speechManager.isSpeaking ? "stop.fill" : "play.fill")
                    .font(.title)
            }
            .tint(.blue)
            .disabled(sortedFlashcards.isEmpty)
            
            Spacer()
            
            Rectangle()
                .frame(width: 50, height: 50)
                .hidden()
            
            Spacer()
            
            Button(action: { isShowingExamView = true }) {
                Image(systemName: "graduationcap.fill")
                    .font(.title)
            }
            .tint(.blue)
            .disabled(sortedFlashcards.isEmpty)
            
            Spacer()
        }
        .padding()
    }
}
