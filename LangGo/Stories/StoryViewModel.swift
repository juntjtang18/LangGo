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
    
    @Published var selectedDifficultyID: Int? = 0 {
        didSet {
            resetAndLoadStories()
        }
    }
    
    private var currentPage = 1
    private var totalPages: Int?
    private let storyService: StoryService

    init(storyService: StoryService) {
        self.storyService = storyService
    }
    
    private func resetAndLoadStories() {
        stories.removeAll()
        currentPage = 1
        totalPages = nil
        Task {
            await loadMoreStoriesIfNeeded(currentItem: nil)
        }
    }

    func initialLoad() async {
        guard recommendedStories.isEmpty else { return }
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
            let (fetchedStories, pagination) = try await storyService.fetchStories(page: currentPage)
            
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
        // Only set loading to true if we don't have the story yet.
        if selectedStory?.id != id {
            selectedStory = nil // Clear previous story
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
