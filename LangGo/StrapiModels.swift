// LangGo/StrapiModels.swift
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

    enum CodingKeys: String, CodingKey {
        case id, attributes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // always decode the id
        id = try container.decode(Int.self, forKey: .id)

        if let wrapped = try container.decodeIfPresent(FlashcardAttributes.self, forKey: .attributes) {
            // API returned { id, attributes: { … } }
            attributes = wrapped
        } else {
            // API returned flat { id, createdAt, updatedAt, … }
            // FlashcardAttributes has its own init(from:) that reads those keys
            attributes = try FlashcardAttributes(from: decoder)
        }
    }

    // (optional) encode back with the wrapper if you need it:
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(attributes, forKey: .attributes)
    }
}

struct FlashcardAttributes: Codable {
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let lastReviewedAt: Date?
    let content: [StrapiComponent]? // Made optional to fix decoding error
    
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

    // Custom initializer to handle optional 'content' key robustly
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.locale = try container.decodeIfPresent(String.self, forKey: .locale)
        self.lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        self.content = try container.decodeIfPresent([StrapiComponent].self, forKey: .content)
        self.correctStreak = try container.decodeIfPresent(Int.self, forKey: .correctStreak)
        self.wrongStreak = try container.decodeIfPresent(Int.self, forKey: .wrongStreak)
        self.isRemembered = try container.decode(Bool.self, forKey: .isRemembered) // This is mandatory, not optional based on JSON
    }
}

// MARK: - Authentication Models (NEW)

/// Request body for user login.
struct LoginCredentials: Encodable {
    let identifier: String
    let password: String
}

/// Request body for user registration (signup).
struct RegistrationPayload: Encodable {
    let email: String
    let password: String
    let username: String
    let baseLanguage: String
    let telephone: String?    // optional for future

    enum CodingKeys: String, CodingKey {
        case email, password, username, baseLanguage
        case telephone
    }
}
/// Response for authentication (login and signup).
struct AuthResponse: Codable {
    let jwt: String
    let user: StrapiUser
}

// MARK: - VBSetting Models

/// Wraps a single vbsetting item returned by Strapi (/vbsettings/mine).
struct VBSettingSingleResponse: Codable {
    let data: VBSetting
}

/// Represents the vbsetting record.
struct VBSetting: Codable {
    let id: Int
    let attributes: VBSettingAttributes
}

/// The actual fields on a vbsetting.
struct VBSettingAttributes: Codable {
    let wordsPerPage: Int
    let interval1: Double
    let interval2: Double
    let interval3: Double
}

/// Payload for updating vbsetting via PUT /vbsettings/mine
struct VBSettingUpdatePayload: Encodable {
    struct Data: Encodable {
        let wordsPerPage: Int
        let interval1: Double
        let interval2: Double
        let interval3: Double
    }
    let data: Data
}


// MARK: - Generic API Response Wrappers (NEW/REVISED)

/// Represents a paginated list response from Strapi.
struct StrapiListResponse<T: Codable>: Codable {
    let data: [T]? // Array of the actual data objects
    let meta: StrapiMeta?
}

/// Represents a single item response from Strapi, typically wrapped under a `data` key.
struct StrapiSingleResponse<T: Codable>: Codable {
    let data: T
}

/// Represents the metadata section in Strapi responses, containing pagination info.
struct StrapiMeta: Codable {
    let pagination: StrapiPagination?
}

/// Represents the pagination details in Strapi's metadata.
struct StrapiPagination: Codable {
    let page: Int
    let pageSize: Int
    let pageCount: Int
    let total: Int
}

/// Represents a standard error response from Strapi.
struct StrapiErrorResponse: Codable {
    let data: String? // Can be null in some error cases
    let error: ErrorDetails
    
    struct ErrorDetails: Codable {
        let status: Int
        let name: String
        let message: String
        let details: [String: String]? // Or more specific structure if known
    }
}

// MARK: - General purpose empty response for successful calls with no body
// ADDED THIS STRUCT FOR MODULE-LEVEL ACCESS
public struct EmptyResponse: Codable {}

// MARK: - Statistics Models

/// The response wrapper for the statistics endpoint.
struct StrapiStatisticsResponse: Codable {
    let data: StrapiStatistics
}

struct StrapiStatistics: Codable {
    let totalCards: Int
    let remembered: Int
    let newCards: Int
    let warmUp: Int
    let weekly: Int
    let monthly: Int
    let hardToRemember: Int

    enum CodingKeys: String, CodingKey {
        case totalCards
        case remembered
        case newCards
        case warmUp
        case weekly
        case monthly
        case hardToRemember
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
    
    enum CodingKeys: String, CodingKey {
        case result, flashcard, user
        case reviewedAt = "reviewed_at"
        case reviewLevel = "review_level"
    }
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

// MARK: - Exam Options Structure
// Represents a single exam option, used within exam_base and exam_target JSON arrays
struct ExamOption: Codable {
    let text: String
    let isCorrect: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case isCorrect = "isCorrect" // Ensure this matches the JSON key from user-word.js
    }
}


// MARK: - Final Attribute Structs
struct UserWordAttributes: Codable {
    let targetText: String? // Renamed from 'word'
    let baseText: String?
    let partOfSpeech: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let examBase: [ExamOption]? // Added new field
    let examTarget: [ExamOption]? // Added new field

    enum CodingKeys: String, CodingKey {
        case locale, createdAt, updatedAt
        case targetText = "target_text" // Updated to match the new API field name
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case examBase = "exam_base" // Added new coding key
        case examTarget = "exam_target" // Added new coding key
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
    let examBase: [ExamOption]? // Added new field
    let examTarget: [ExamOption]? // Added new field

    enum CodingKeys: String, CodingKey {
        case word, instruction, gender, article, createdAt, updatedAt, locale, audio, tags, register
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case exampleSentences = "example_sentences"
        case verbMeta = "verb_meta"
        case examBase = "exam_base" // Added new coding key
        case examTarget = "exam_target" // Added new coding key
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
    let examBase: [ExamOption]? // Added new field
    let examTarget: [ExamOption]? // Added new field
    
    enum CodingKeys: String, CodingKey {
        case title, instruction, createdAt, updatedAt, locale, tags, words, register
        case baseText = "base_text"
        case targetText = "target_text"
        case targetAudio = "target_audio"
        case examBase = "exam_base" // Added new coding key
        case examTarget = "exam_target" // Added new coding key
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

// MARK: - Strapi Data Structures for User Word
// These structs are now defined here for global access.

// Request body for creating a new user word
struct CreateUserWordRequest: Encodable, Decodable {
    let data: UserWordData
}

struct UserWordData: Encodable, Decodable {
    let target_text: String
    let base_text: String
    let part_of_speech: String
    let base_locale: String
    let target_locale: String
}

// Response structure for a created user word (optional, but good for confirmation)
struct UserWordResponse: Decodable {
    let data: UserWordResponseData
}

struct UserWordResponseData: Decodable {
    let id: Int
    let attributes: UserWordAttributes
}

// MARK: - Strapi Data Structures for Translate Word
struct TranslateWordRequest: Codable {
    let word: String
    let source: String
    let target: String
}

struct TranslateWordResponse: Decodable {
    let translatedText: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translation"
    }
}

