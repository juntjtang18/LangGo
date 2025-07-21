// LangGo/Stories/StoryViewModel.swift
import Foundation
import SwiftUI

@MainActor
class StoryViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var recommendedStories: [Story] = []
    @Published var difficultyLevels: [DifficultyLevel] = []
    
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
            // Fetch non-paginated data first
            async let levelsTask = storyService.fetchDifficultyLevels()
            async let recommendedTask = storyService.fetchRecommendedStories()
            let (fetchedLevels, fetchedRecommended) = try await (levelsTask, recommendedTask)
            
            var allLevels = [DifficultyLevel(id: 0, attributes: .init(name: "All", level: 0, code: "ALL", description: "All stories", locale: "en"))]
            allLevels.append(contentsOf: fetchedLevels.sorted { $0.attributes.level < $1.attributes.level })
            
            self.recommendedStories = fetchedRecommended
            self.difficultyLevels = allLevels
            
            // Now load the first page of stories
            await loadMoreStoriesIfNeeded(currentItem: nil)

        } catch {
            errorMessage = "Failed to load stories: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func loadMoreStoriesIfNeeded(currentItem item: Story?) async {
        // Ensure we only proceed if we are at the end of the current list
        if let item = item, item.id != stories.last?.id {
            return
        }

        // Check if we are already fetching or if we've reached the last page
        guard !isFetchingMore, (totalPages == nil || currentPage <= totalPages!) else {
            return
        }

        isFetchingMore = true
        
        do {
            // In a real app, you would add filter parameters here based on selectedDifficultyID
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
}
