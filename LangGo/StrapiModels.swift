import Foundation

// MARK: - Core Response Wrappers
/// Represents a standard Strapi response for a collection, wrapped in a "data" key.
struct StrapiResponse: Codable {
    let data: [StrapiFlashcard]
}

/// Represents a single flashcard object from the Strapi API.
struct StrapiFlashcard: Codable {
    let id: Int
    let attributes: FlashcardAttributes
}

struct FlashcardAttributes: Codable {
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let lastReviewedAt: Date?
    let content: [StrapiComponent]
    
    let correctStreak: Int?
    let wrongStreak: Int?
    let isRemembered: Bool

    enum CodingKeys: String, CodingKey {
        case createdAt, updatedAt, locale, content
        case lastReviewedAt = "last_reviewed_at"
        case correctStreak = "correct_streak"
        case wrongStreak = "wrong_streak"
        case isRemembered = "is_remembered"
    }
}

// MARK: - Review Models (REVISED)

/// The request body for the `POST /api/flashcards/:id/review` endpoint.
struct ReviewBody: Codable {
    let result: String
}

// Used for creating a new review log via POST request.
struct ReviewLogRequestBody: Codable {
    let data: ReviewLogData
}

struct ReviewLogData: Codable {
    let result: String
    let flashcard: Int
    let reviewedAt: Date
    let reviewLevel: String
    let user: Int
    
    // REVISED: This is no longer needed because the NetworkManager's JSONEncoder
    // now uses the `.convertToSnakeCase` strategy, which handles this automatically.
    // Keeping it could cause conflicts.
    /*
    enum CodingKeys: String, CodingKey {
        case result, flashcard, user
        case reviewedAt = "reviewed_at"
        case reviewLevel = "review_level"
    }
    */
}


// MARK: - Dynamic Zone Component
struct StrapiComponent: Codable {
    let id: Int
    let componentIdentifier: String
    let userWord: UserWordRelation?
    let userSentence: UserSentenceRelation?
    let word: WordRelation?
    let sentence: SentenceRelation?

    enum CodingKeys: String, CodingKey {
        case id, word, sentence
        case componentIdentifier = "__component"
        case userWord = "user_word"
        case userSentence = "user_sentence"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        componentIdentifier = try container.decode(String.self, forKey: .componentIdentifier)
        userWord = try container.decodeIfPresent(UserWordRelation.self, forKey: .userWord)
        userSentence = try container.decodeIfPresent(UserSentenceRelation.self, forKey: .userSentence)
        word = try container.decodeIfPresent(WordRelation.self, forKey: .word)
        sentence = try container.decodeIfPresent(SentenceRelation.self, forKey: .sentence)
    }
}

// MARK: - Generic Relation & Data Wrappers
struct Relation<T: Codable>: Codable {
    let data: T?
}
struct ManyRelation<T: Codable>: Codable {
    let data: [T]
}
struct StrapiData<T: Codable>: Codable {
    let id: Int
    let attributes: T
}

// Typealiases
typealias UserWordRelation = Relation<StrapiData<UserWordAttributes>>
typealias UserSentenceRelation = Relation<StrapiData<UserSentenceAttributes>>
typealias WordRelation = Relation<StrapiData<WordAttributes>>
typealias SentenceRelation = Relation<StrapiData<SentenceAttributes>>
typealias MediaRelation = Relation<StrapiData<MediaAttributes>>
typealias ExampleSentencesRelation = ManyRelation<StrapiData<SentenceAttributes>>
typealias WordsRelation = ManyRelation<StrapiData<WordAttributes>>

// MARK: - Component Schemas
struct TagListComponent: Codable {
    let id: Int
    let tag: String?
}

struct VerbMetaComponent: Codable {
    let id: Int
    let simplePast: String?
    let pastParticiple: String?
    let presentParticiple: String?
    let thirdpersonSingular: String?
    let auxiliaryVerb: String?

    enum CodingKeys: String, CodingKey {
        case id
        case simplePast = "simple_past"
        case pastParticiple = "past_participle"
        case presentParticiple = "present_participle"
        case thirdpersonSingular = "thirdperson_singular"
        case auxiliaryVerb = "auxiliary_verb"
    }
}

// MARK: - Final Attribute Structs
struct UserWordAttributes: Codable {
    let word: String?
    let baseText: String?
    let partOfSpeech: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?

    enum CodingKeys: String, CodingKey {
        case word, locale, createdAt, updatedAt
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
    }
}

struct UserSentenceAttributes: Codable {
    let targetText: String?
    let baseText: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?

    enum CodingKeys: String, CodingKey {
        case createdAt, updatedAt, locale
        case targetText = "target_text"
        case baseText = "base_text"
    }
}

struct WordAttributes: Codable {
    let word: String?
    let baseText: String?
    let instruction: String?
    let partOfSpeech: String?
    let gender: String?
    let article: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let audio: MediaRelation?
    let tags: [TagListComponent]?
    let exampleSentences: ExampleSentencesRelation?
    let verbMeta: VerbMetaComponent?
    let register: String?

    enum CodingKeys: String, CodingKey {
        case word, instruction, gender, article, createdAt, updatedAt, locale, audio, tags, register
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case exampleSentences = "example_sentences"
        case verbMeta = "verb_meta"
    }
}

struct SentenceAttributes: Codable {
    let title: String?
    let instruction: String?
    let baseText: String?
    let targetText: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let targetAudio: MediaRelation?
    let tags: [TagListComponent]?
    let words: WordsRelation?
    let register: String?
    
    enum CodingKeys: String, CodingKey {
        case title, instruction, createdAt, updatedAt, locale, tags, words, register
        case baseText = "base_text"
        case targetText = "target_text"
        case targetAudio = "target_audio"
    }
}

struct MediaAttributes: Codable {
    let name: String?
    let alternativeText: String?
    let caption: String?
    let width: Int?
    let height: Int?
    let formats: [String: MediaFormat]?
    let hash: String?
    let ext: String?
    let mime: String?
    let size: Double?
    let url: String?
    let previewUrl: String?
    let provider: String?
    let providerMetadata: [String: String]?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case name, caption, width, height, formats, hash, ext, mime, size, url, provider, createdAt, updatedAt
        case alternativeText
        case previewUrl
        case providerMetadata = "provider_metadata"
    }
}

struct MediaFormat: Codable {
    let name: String?
    let hash: String?
    let ext: String?
    let mime: String?
    let path: String?
    let width: Int?
    let height: Int?
    let size: Double?
    let url: String?
}

// Wrapper for the array response from /api/my-reviewlogs
struct StrapiReviewLogResponse: Codable {
    let data: [StrapiReviewLog]
}

// Represents a single review log object from the API
struct StrapiReviewLog: Codable, Identifiable {
    let id: Int
    let attributes: ReviewLogAttributes
}

// The attributes of a review log
struct ReviewLogAttributes: Codable {
    let result: String
    let reviewedAt: Date
    let reviewLevel: String?

    enum CodingKeys: String, CodingKey {
        case result
        case reviewedAt = "reviewed_at"
        case reviewLevel = "level"
    }
}
