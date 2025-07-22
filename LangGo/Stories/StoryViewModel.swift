import Foundation
import SwiftUI

@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var recommendedStories: [Story] = []
    
    // These now drive the UI
    @Published var storyRows: [StoryRow] = []
    @Published var recommendedStoryRows: [StoryRow] = []

    @Published var difficultyLevels: [DifficultyLevel] = []
    @Published var selectedStory: Story?
    
    @Published var isLoading: Bool = false
    @Published var isFetchingMore: Bool = false
    @Published var errorMessage: String?

    @Published var translationResult: String?
    @Published var isTranslating: Bool = false
    
    @Published var selectedDifficultyID: Int? = 0 {
        didSet {
            if oldValue != selectedDifficultyID {
                resetAndLoadStories()
            }
        }
    }
    
    private var currentPage = 1
    private var totalPages: Int?
    private let storyService: StoryService
    private let strapiService: StrapiService
    private let languageSettings: LanguageSettings

    init(storyService: StoryService, strapiService: StrapiService, languageSettings: LanguageSettings) {
        self.storyService = storyService
        self.strapiService = strapiService
        self.languageSettings = languageSettings
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

    private func resetAndLoadStories() {
        stories.removeAll()
        storyRows.removeAll()
        currentPage = 1
        totalPages = nil
        Task {
            await loadMoreStoriesIfNeeded(currentItem: nil)
        }
    }
    
    // --- THIS IS THE NEW, DETERMINISTIC LAYOUT LOGIC ---
    private func generateLayout(for stories: [Story]) -> [StoryRow] {
        var rows: [StoryRow] = []
        var index = 0

        while index < stories.count {
            let story = stories[index]
            
            // Determine the style based on the story's ID. This is always the same.
            let styleId = story.id % 4
            
            // Rule: If the ID is divisible by 4 and there's another story available,
            // create a paired half-width row.
            if styleId == 0 && index + 1 < stories.count {
                let pair = [story, stories[index + 1]]
                rows.append(StoryRow(stories: pair, style: .half))
                index += 2 // Advance the index by 2
            } else {
                // Otherwise, use a full or landscape card for a single-story row.
                let style: CardStyle = (styleId == 2) ? .landscape : .full
                rows.append(StoryRow(stories: [story], style: style))
                index += 1 // Advance the index by 1
            }
        }
        return rows
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
    
    func translate(word: String) async {
        isTranslating = true
        translationResult = ""
        
        do {
            let learningLanguage = Config.learningTargetLanguageCode
            let baseLanguage = languageSettings.selectedLanguageCode
            
            guard learningLanguage != baseLanguage else {
                translationResult = word
                isTranslating = false
                return
            }

            let response = try await strapiService.translateWord(
                word: word,
                source: learningLanguage,
                target: baseLanguage
            )
            translationResult = response.translatedText
        } catch {
            translationResult = "Translation failed."
            errorMessage = error.localizedDescription
        }
        
        isTranslating = false
    }

    func toggleLike(for story: Story) async {
        do {
            let response = try await storyService.likeStory(id: story.id)
            updateStoryLikeCount(storyId: story.id, newLikeCount: response.data.like_count)
        } catch {
            errorMessage = "Failed to update like status: \(error.localizedDescription)"
        }
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
