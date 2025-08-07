import Foundation

// MARK: - Story Models

/// A wrapper for a response containing a single story.
typealias StrapiStoryResponse = StrapiSingleResponse<Story>

/// Represents a story object from the Strapi API.
struct Story: Codable, Identifiable, Hashable {
    let id: Int
    var attributes: StoryAttributes

    static func == (lhs: Story, rhs: Story) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents the attributes of a story.
struct StoryAttributes: Codable, Equatable {
    let title: String
    let author: String
    let brief: String?
    let text: String?
    let slug: String?
    let order: Int?
    let word_count: Int?
    var like_count: Int?
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

    // A simple Equatable implementation that compares IDs.
    static func == (lhs: StoryAttributes, rhs: StoryAttributes) -> Bool {
        return lhs.id == rhs.id
    }
    
    // A computed property to act as a unique identifier for equality checks.
    var id: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(author)
        return hasher.finalize()
    }
    
    var difficultyName: String {
        return self.difficulty_level?.data?.attributes.name ?? "N/A"
    }
    
    var coverImageURL: URL? {
        // This now uses the MediaAttributes struct from StrapiModels.swift
        guard let mediaAttributes = self.illustrations?.first?.media?.data?.attributes else {
            return nil
        }
        
        // Prioritize the full URL, and fall back to the thumbnail.
        if let urlString = mediaAttributes.url, let url = URL(string: urlString) {
            return url
        }
        
        if let thumbnailUrlString = mediaAttributes.formats?["thumbnail"]?.url, let url = URL(string: thumbnailUrlString) {
            return url
        }
        
        return nil
    }
}

/// A typealias for the relation to a difficulty level.
typealias DifficultyLevelRelation = Relation<StrapiData<DifficultyLevelAttributes>>

/// Represents a difficulty level object from the Strapi API.
struct DifficultyLevel: Codable, Identifiable, Equatable {
    let id: Int
    let attributes: DifficultyLevelAttributes
}

/// Represents the attributes of a difficulty level.
struct DifficultyLevelAttributes: Codable, Equatable {
    let name: String
    let level: Int
    let code: String
    let description: String?
    let locale: String
}

/// Represents an illustration component within a story.
struct IllustrationComponent: Codable, Identifiable, Equatable {
    let id: Int
    let caption: String?
    let alt_text: String?
    let paragraph: Int?
    let media: MediaRelation?

    static func == (lhs: IllustrationComponent, rhs: IllustrationComponent) -> Bool {
        return lhs.id == rhs.id
    }
}
struct StoryLikeResponse: Codable {
    let message: String
    let data: StoryLikeData
}

struct StoryLikeData: Codable {
    let id: Int
    let like_count: Int
}

// REMOVED: The duplicate MediaAttributes and MediaFormat structs have been deleted from this file.
// They are now correctly sourced from StrapiModels.swift.
