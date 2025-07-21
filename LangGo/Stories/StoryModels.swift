// LangGo/StoryModels.swift
import Foundation

// MARK: - Story Models

/// A wrapper for a response containing a single story.
typealias StrapiStoryResponse = StrapiSingleResponse<Story>

/// Represents a story object from the Strapi API.
struct Story: Codable, Identifiable {
    let id: Int
    let attributes: StoryAttributes
}

/// Represents the attributes of a story.
struct StoryAttributes: Codable {
    let title: String
    let author: String
    let brief: String?
    let text: String?
    let slug: String?
    let order: Int?
    let word_count: Int?
    let like_count: Int?
    let createdAt: String?
    let updatedAt: String?
    let locale: String
    let difficulty_level: DifficultyLevelRelation?
    let illustrations: [IllustrationComponent]?

    enum CodingKeys: String, CodingKey {
        case title, author, brief, text, slug, order, createdAt, updatedAt, locale, illustrations
        case word_count = "word_count"
        case difficulty_level = "difficulty_level"
        case like_count = "like_count"
    }
    
    // --- ADDED: Computed properties for view logic ---
    
    /// The name of the difficulty level.
    var difficultyName: String {
        return self.difficulty_level?.data?.attributes.name ?? "N/A"
    }
    
    /// The URL for the story's cover image, using the 'thumbnail' format.
    var coverImageURL: URL? {
        guard let urlString = self.illustrations?.first?.media?.data?.attributes.formats?["thumbnail"]?.url else {
            return nil
        }
        return URL(string: urlString)
    }
}

/// A typealias for the relation to a difficulty level.
typealias DifficultyLevelRelation = Relation<StrapiData<DifficultyLevelAttributes>>

/// Represents a difficulty level object from the Strapi API.
struct DifficultyLevel: Codable, Identifiable {
    let id: Int
    let attributes: DifficultyLevelAttributes
}

/// Represents the attributes of a difficulty level.
struct DifficultyLevelAttributes: Codable {
    let name: String
    let level: Int
    let code: String
    let description: String?
    let locale: String
}

/// Represents an illustration component within a story.
struct IllustrationComponent: Codable, Identifiable {
    let id: Int
    let caption: String?
    let alt_text: String?
    let paragraph: Int?
    let media: MediaRelation?
}
