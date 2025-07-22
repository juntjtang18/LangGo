import Foundation
import SwiftUI

@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var recommendedStories: [Story] = []
    @Published var difficultyLevels: [DifficultyLevel] = []
    @Published var selectedStory: Story?
    
    @Published var isLoading: Bool = false
    @Published var isFetchingMore: Bool = false
    @Published var errorMessage: String?

    @Published var translationResult: String?
    @Published var isTranslating: Bool = false
    
    @Published var selectedDifficultyID: Int? = 0 {
        didSet {
            resetAndLoadStories()
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
        guard stories.isEmpty else { return } // Prevent re-loading if already populated
        isLoading = true
        errorMessage = nil
        
        do {
            async let levelsTask = storyService.fetchDifficultyLevels()
            async let recommendedTask = storyService.fetchRecommendedStories()
            
            let (fetchedLevels, fetchedRecommended) = try await (levelsTask, recommendedTask)
            
            var allLevels = [DifficultyLevel(id: 0, attributes: .init(name: "All", level: 0, code: "ALL", description: "All stories", locale: "en"))]
            allLevels.append(contentsOf: fetchedLevels.sorted { $0.attributes.level < $1.attributes.level })
            
            self.recommendedStories = fetchedRecommended
            self.difficultyLevels = allLevels
            
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
            // MODIFIED: Pass the selectedDifficultyID to the service call
            let (fetchedStories, pagination) = try await storyService.fetchStories(
                page: currentPage,
                difficultyID: selectedDifficultyID
            )
            
            if let pagination = pagination {
                self.totalPages = pagination.pageCount
            }
            
            stories.append(contentsOf: fetchedStories)
            currentPage += 1

        } catch {
            errorMessage = "Failed to load more stories: \(error.localizedDescription)"
        }
        
        isFetchingMore = false
    }

    func fetchStoryDetails(id: Int) async {
        if let story = recommendedStories.first(where: { $0.id == id }) ?? stories.first(where: { $0.id == id }) {
            self.selectedStory = story
            print("✅ Story found in memory. No network call needed.")
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

    private func resetAndLoadStories() {
        stories.removeAll()
        currentPage = 1
        totalPages = nil
        Task {
            await loadMoreStoriesIfNeeded(currentItem: nil)
        }
    }
}
