import Foundation
import SwiftUI
import os
import AVFoundation // ADDED: For text-to-speech

@MainActor
class StoryViewModel: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "StoryViewModel")
    
    // MARK: - Published Properties
    @Published var stories: [Story] = []
    @Published var recommendedStories: [Story] = []
    @Published var storyRows: [StoryRow] = []
    @Published var recommendedStoryRows: [StoryRow] = []
    @Published var difficultyLevels: [DifficultyLevel] = []
    @Published var selectedStory: Story?
    @Published var isLoading: Bool = false
    @Published var isFetchingMore: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Text to Speech
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var speechQueue: [AVSpeechUtterance] = []
    
    @Published var isSpeaking: Bool = false
    // MARK: - Voice Selection
    //@Published var availableStandardVoices: [AVSpeechSynthesisVoice] = []
    
    // Use AppStorage to save the user's choice persistently
    //@AppStorage("selectedVoiceIdentifier") var selectedVoiceIdentifier: String = AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
    
    private let voiceService: VoiceSelectionService

    struct ContextualTranslation {
        let translatedWord: String
        let translatedSentence: String
        let partOfSpeech: String
    }
    @Published var contextualTranslation: ContextualTranslation?
    @Published var isTranslating: Bool = false
    
    @Published var selectedDifficultyID: Int? = 0 {
        didSet {
            if oldValue != selectedDifficultyID {
                resetAndLoadStories()
            }
        }
    }
    
    // MARK: - Private Properties
    private var currentPage = 1
    private var totalPages: Int?
    
    // Services are now fetched directly from the DataServices singleton.
    private let storyService = DataServices.shared.storyService
    private let strapiService = DataServices.shared.strapiService
    
    // MARK: - Initialization
    // The initializer is now clean and only takes the dependencies it can't get globally.
    init(voiceService: VoiceSelectionService) {
        self.voiceService = voiceService
        super.init()
        speechSynthesizer.delegate = self
    }
    func startReadingAloud(paragraphs: [String]) {
        guard !isSpeaking, !paragraphs.isEmpty else {
            stopReadingAloud()
            return
        }
        
        // Create a queue of utterances to speak
        speechQueue = paragraphs.map { paragraph in
            let utterance = AVSpeechUtterance(string: paragraph)
            //utterance.voice = AVSpeechSynthesisVoice(language: Config.learningTargetLanguageCode)
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceService.selectedVoiceIdentifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            return utterance
        }
        
        isSpeaking = true
        speakNextInQueue()
    }
    
    func stopReadingAloud() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechQueue.removeAll()
        isSpeaking = false
    }
    
    private func speakNextInQueue() {
        guard !speechQueue.isEmpty else {
            // Finished reading
            isSpeaking = false
            return
        }
        let utterance = speechQueue.removeFirst()
        speechSynthesizer.speak(utterance)
    }
    // Add this computed property
    private var baseLanguageCode: String {
        UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
    }
    // MARK: - Public Methods
    
    // ADDED: A new method to handle speaking text.
    func speak(word: String) {
        let utterance = AVSpeechUtterance(string: word)
        // This automatically uses the system's voice for the device's language.
        //utterance.voice = AVSpeechSynthesisVoice(language: Config.learningTargetLanguageCode)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceService.selectedVoiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        speechSynthesizer.speak(utterance)
    }
    
    func initialLoad() async {
        guard stories.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            async let levelsTask = storyService.fetchDifficultyLevels()
            async let recommendedTask = storyService.fetchRecommendedStories()
            
            let (fetchedLevels, fetchedRecommended) = try await (levelsTask, recommendedTask)
            
            var allLevels = [DifficultyLevel(id: 0, attributes: .init(name: "All", level: 0, code: "ALL", description: "All stories", locale: "en"))]
            allLevels.append(contentsOf: fetchedLevels.sorted { $0.attributes.level < $1.attributes.level })
            
            self.recommendedStories = Array(fetchedRecommended.prefix(5))
            self.difficultyLevels = allLevels
            
            self.recommendedStoryRows = generateLayout(for: self.recommendedStories)
            await loadMoreStoriesIfNeeded(currentItem: nil)
            
        } catch {
            errorMessage = "Failed to load stories: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func loadMoreStoriesIfNeeded(currentItem item: Story?) async {
        if let item = item, item.id != stories.last?.id {
            return
        }
        
        guard !isFetchingMore, (totalPages == nil || currentPage <= totalPages!) else {
            return
        }
        
        isFetchingMore = true
        
        do {
            let (fetchedStories, pagination) = try await storyService.fetchStories(page: currentPage, difficultyID: selectedDifficultyID)
            
            if let pagination = pagination { self.totalPages = pagination.pageCount }
            
            self.stories.append(contentsOf: fetchedStories)
            self.storyRows = generateLayout(for: self.stories)
            currentPage += 1
            
        } catch {
            errorMessage = "Failed to load more stories: \(error.localizedDescription)"
        }
        
        isFetchingMore = false
    }
    
    func fetchStoryDetails(id: Int) async {
        if let story = recommendedStories.first(where: { $0.id == id }) ?? stories.first(where: { $0.id == id }) {
            self.selectedStory = story
            return
        }
        
        if selectedStory?.id != id {
            selectedStory = nil
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            selectedStory = try await storyService.fetchStory(id: id)
        } catch {
            errorMessage = "Failed to load story details: \(error.localizedDescription)"
        }
    }
    
    func translateInContext(word: String, sentence: String) async {
        isTranslating = true
        contextualTranslation = nil
        
        do {
            let learningLanguage = Config.learningTargetLanguageCode
            let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
            
            guard learningLanguage != baseLanguage else {
                contextualTranslation = ContextualTranslation(
                    translatedWord: word,
                    translatedSentence: sentence,
                    partOfSpeech: "N/A"
                )
                isTranslating = false
                return
            }
            
            let response = try await strapiService.translateWordInContext(
                word: word,
                sentence: sentence,
                sourceLang: learningLanguage,
                targetLang: baseLanguage
            )
            
            contextualTranslation = ContextualTranslation(
                translatedWord: response.translation,
                translatedSentence: response.sentence,
                partOfSpeech: response.partOfSpeech
            )
        } catch {
            errorMessage = "Context translation failed: \(error.localizedDescription)"
        }
        
        isTranslating = false
    }
    
    @MainActor
    func saveWordToVocabook(targetText: String, baseText: String, partOfSpeech: String) async throws {
        do {
            let tgt = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            logger.info("Saving new word from story -> target:'\(tgt, privacy: .public)' | base:'\(base, privacy: .public)' | pos:'\(partOfSpeech, privacy: .public)'")
            _ = try await strapiService.saveNewWord(
                targetText: tgt,
                baseText: base,
                partOfSpeech: partOfSpeech,
                locale: baseLanguageCode // FIX 1: Add locale parameter
            )
            logger.info("Saved new word successfully from story view.")
        } catch {
            logger.error("Failed to save new word from story view: \(error.localizedDescription)")
            throw error
        }
    }
    
    func toggleLike(for story: Story) async {
        do {
            let response = try await storyService.likeStory(id: story.id)
            updateStoryLikeCount(storyId: story.id, newLikeCount: response.data.like_count)
        } catch {
            errorMessage = "Failed to update like status: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    private func resetAndLoadStories() {
        stories.removeAll()
        storyRows.removeAll()
        currentPage = 1
        totalPages = nil
        Task {
            await loadMoreStoriesIfNeeded(currentItem: nil)
        }
    }
    
    // In Stories/StoryViewModel.swift
    
    private func generateLayout(for stories: [Story]) -> [StoryRow] {
        var rows: [StoryRow] = []
        
        for story in stories {
            rows.append(StoryRow(stories: [story], style: .full))
        }
        
        return rows
    }
    
    private func updateStoryLikeCount(storyId: Int, newLikeCount: Int?) {
        if let index = stories.firstIndex(where: { $0.id == storyId }) {
            stories[index].attributes.like_count = newLikeCount
        }
        if let index = recommendedStories.firstIndex(where: { $0.id == storyId }) {
            recommendedStories[index].attributes.like_count = newLikeCount
        }
        if selectedStory?.id == storyId {
            selectedStory?.attributes.like_count = newLikeCount
        }
    }
}
extension StoryViewModel: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // When one paragraph finishes, speak the next one.
        speakNextInQueue()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Ensure state is correct if cancelled.
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
