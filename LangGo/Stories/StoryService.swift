import Foundation
import os

/// A service layer for interacting with the story-related endpoints of the Strapi backend.
class StoryService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "StoryService")

    // MARK: - Story Service

    /// Fetches a paginated list of stories from the server.
    // MODIFIED: Function signature updated to accept an optional difficultyID
    func fetchStories(page: Int, pageSize: Int = 10, difficultyID: Int? = nil) async throws -> ([Story], StrapiPagination?) {
        logger.debug("StoryService: Fetching stories page \(page) with difficultyID: \(String(describing: difficultyID)).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/stories") else {
            throw URLError(.badURL)
        }

        // Start with the base query items
        var queryItems = [
            URLQueryItem(name: "populate[difficulty_level]", value: "*"),
            URLQueryItem(name: "populate[illustrations][populate]", value: "media"),
            URLQueryItem(name: "sort", value: "order:asc"),
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)")
        ]
        
        // Add the filter if a specific difficulty is selected (and it's not "All")
        if let id = difficultyID, id != 0 {
            let filterItem = URLQueryItem(name: "filters[difficulty_level][id][$eq]", value: "\(id)")
            queryItems.append(filterItem)
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiListResponse<Story> = try await NetworkManager.shared.fetchDirect(from: url)
        return (response.data ?? [], response.meta?.pagination)
    }


    /// Fetches a single story by its ID, populating all its details.
    func fetchStory(id: Int) async throws -> Story {
        logger.debug("StoryService: Fetching story with ID \(id).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/stories/\(id)") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "populate", value: "*")
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiStoryResponse = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data
    }

    /// Fetches all available difficulty levels.
    func fetchDifficultyLevels() async throws -> [DifficultyLevel] {
        logger.debug("StoryService: Fetching all difficulty levels.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/difficulty-levels") else {
            throw URLError(.badURL)
        }
        
        let response: StrapiListResponse<DifficultyLevel> = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data ?? []
    }
    
    /// Fetches a list of recommended stories from the server.
    func fetchRecommendedStories() async throws -> [Story] {
        logger.debug("StoryService: Fetching recommended stories.")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/stories/recommended") else {
            throw URLError(.badURL)
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "populate[difficulty_level]", value: "*"),
            URLQueryItem(name: "populate[illustrations][populate]", value: "media"),
            URLQueryItem(name: "pagination[page]", value: "1"),
            URLQueryItem(name: "pagination[pageSize]", value: "6")
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiListResponse<Story> = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data ?? []
    }
    
    /// Toggles the 'like' status for a given story.
    func likeStory(id: Int) async throws -> StoryLikeResponse {
        logger.debug("StoryService: Toggling like for story ID \(id).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/stories/\(id)/like") else {
            throw URLError(.badURL)
        }
        let emptyBody: [String: String] = [:]
        return try await NetworkManager.shared.post(to: url, body: emptyBody)
    }
}
