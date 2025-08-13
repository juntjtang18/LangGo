// LangGo/StrapiModels.swift
import Foundation

// MARK: - Core Response Wrappers
struct StrapiResponse: Codable {
    let data: [StrapiFlashcard]
}

struct StrapiFlashcard: Codable {
    let id: Int
    let attributes: FlashcardAttributes
}

struct FlashcardAttributes: Codable {
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let lastReviewedAt: Date?
    let wordDefinition: WordDefinitionRelation?
    let correctStreak: Int?
    let wrongStreak: Int?
    let isRemembered: Bool
    let reviewTire: ReviewTireRelation?

    enum CodingKeys: String, CodingKey {
        case createdAt, updatedAt, locale
        case lastReviewedAt = "last_reviewed_at"
        case correctStreak = "correct_streak"
        case wrongStreak = "wrong_streak"
        case isRemembered = "is_remembered"
        case wordDefinition = "word_definition"
        case reviewTire = "review_tire"
    }
}

// MARK: - Word and WordDefinition Models
struct WordAttributes: Codable {
    let targetText: String?
    let word_definitions: ManyRelation<StrapiData<WordDefinitionAttributes>>?

    enum CodingKeys: String, CodingKey {
        case targetText = "target_text"
        case word_definitions
    }
}

struct WordDefinitionAttributes: Codable {
    let baseText: String?
    let instruction: String?
    let gender: String?
    let article: String?
    let tags: TagListComponent?
    let exampleSentence: String?
    let verbMeta: VerbMetaComponent?
    let examBase: [ExamOption]?
    let examTarget: [ExamOption]?
    let register: String?
    let word: WordRelation?
    let partOfSpeech: PartOfSpeechRelation?
    let flashcards: ManyRelation<StrapiFlashcard>?

    enum CodingKeys: String, CodingKey {
        // ADDED 'flashcards' to the list of coding keys.
        case instruction, gender, article, tags, register, word, flashcards
        case baseText = "base_text"
        case exampleSentence = "example_sentence"
        case verbMeta = "verb_meta"
        case examBase = "exam_base"
        case examTarget = "exam_target"
        case partOfSpeech = "part_of_speech"
    }
}

// MARK: - ReviewTire Models
struct StrapiReviewTire: Codable {
    let id: Int
    let attributes: ReviewTireAttributes
}

struct ReviewTire: Codable {
    let data: StrapiData<ReviewTireAttributes>?
}

struct ReviewTireAttributes: Codable {
    let tier: String
    let min_streak: Int
    let max_streak: Int
    let cooldown_hours: Int
    let demote_bar: Int
}

// MARK: - Authentication Models
struct LoginCredentials: Encodable {
    let identifier: String
    let password: String
}

struct RegistrationPayload: Encodable {
    let email: String
    let password: String
    let username: String
    let baseLanguage: String
    let telephone: String?

    enum CodingKeys: String, CodingKey {
        case email, password, username, baseLanguage, telephone
    }
}

struct AuthResponse: Codable {
    let jwt: String
    let user: StrapiUser
}

// MARK: - VBSetting Models
struct VBSettingSingleResponse: Codable {
    let data: VBSetting
}

struct VBSetting: Codable {
    let id: Int
    let attributes: VBSettingAttributes
}

struct VBSettingAttributes: Codable {
    let wordsPerPage: Int
    let interval1: Double
    let interval2: Double
    let interval3: Double
}

struct VBSettingUpdatePayload: Encodable {
    struct Data: Encodable {
        let wordsPerPage: Int
        let interval1: Double
        let interval2: Double
        let interval3: Double
    }
    let data: Data
}

// MARK: - User Profile Models
struct UserProfileUpdatePayload: Encodable {
    let baseLanguage: String
}

// Add this struct to wrap the payload
struct UserProfileUpdatePayloadWrapper: Encodable {
    let data: UserProfileUpdatePayload
}


// MARK: - Generic API Response Wrappers
struct StrapiListResponse<T: Codable>: Codable {
    let data: [T]?
    let meta: StrapiMeta?
}

struct StrapiSingleResponse<T: Codable>: Codable {
    let data: T
}

struct StrapiMeta: Codable {
    let pagination: StrapiPagination?
}

struct StrapiPagination: Codable {
    let page: Int
    let pageSize: Int
    let pageCount: Int
    let total: Int
}

struct StrapiErrorResponse: Codable {
    let data: String?
    let error: ErrorDetails
    
    struct ErrorDetails: Codable {
        let status: Int
        let name: String
        let message: String
        let details: [String: String]?
    }
}

public struct EmptyResponse: Codable {}

// MARK: - Statistics Models
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
    let dueForReview: Int // ADDED: New property for due cards
}

// MARK: - Review Models
struct ReviewBody: Codable {
    let result: String
}

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

// MARK: - Typealiases
typealias WordDefinitionRelation = Relation<StrapiData<WordDefinitionAttributes>>
typealias WordRelation = Relation<StrapiData<WordAttributes>>
typealias MediaRelation = Relation<StrapiData<MediaAttributes>>
typealias ReviewTireRelation = Relation<StrapiData<ReviewTireAttributes>>
typealias WordDefinitionResponse = StrapiSingleResponse<WordDefinitionAttributes>


// MARK: - Component Schemas & Attributes
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

struct ExamOption: Codable {
    let text: String
    let isCorrect: Bool?

    enum CodingKeys: String, CodingKey {
        case text, isCorrect
    }
}

struct MediaFormat: Codable {
    let name: String?, hash: String?, ext: String?, mime: String?, path: String?
    let width: Int?, height: Int?
    let size: Double?, url: String?
}

struct MediaAttributes: Codable {
    let name: String?, alternativeText: String?, caption: String?
    let width: Int?, height: Int?
    let formats: [String: MediaFormat]?
    let hash: String?, ext: String?, mime: String?, size: Double?, url: String?, previewUrl: String?
    let provider: String?, providerMetadata: [String: String]?
    let createdAt: String?, updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case name, caption, width, height, formats, hash, ext, mime, size, url, provider, createdAt, updatedAt
        case alternativeText, previewUrl
        case providerMetadata = "provider_metadata"
    }
}

// MARK: - Review Log Models
struct StrapiReviewLogResponse: Codable {
    let data: [StrapiReviewLog]
}

struct StrapiReviewLog: Codable, Identifiable {
    let id: Int
    let attributes: ReviewLogAttributes
}

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

// MARK: - Word Creation & Translation Models
struct WordDefinitionCreationPayload: Encodable {
    let targetText: String
    let baseText: String
    let partOfSpeech: String
    
    enum CodingKeys: String, CodingKey {
        case targetText = "target_text"
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
    }
}
// Add this struct to handle the attributes of a part of speech
struct PartOfSpeechAttributes: Codable {
    let name: String?
}

// Add this typealias for the relation
typealias PartOfSpeechRelation = Relation<StrapiData<PartOfSpeechAttributes>>

struct CreateWordDefinitionRequest: Encodable {
    let data: WordDefinitionCreationPayload
}

struct TranslateWordRequest: Codable {
    let word: String
    let source: String
    let target: String
}

// --- MODIFIED ---
struct TranslateWordResponse: Decodable {
    let translation: String
    let partOfSpeech: String
}

// MARK: - Contextual Translation Models
struct TranslateWordInContextRequest: Codable {
    let word: String
    let sentence: String
    let sourceLang: String
    let targetLang: String
}

// --- MODIFIED ---
struct TranslateWordInContextResponse: Decodable {
    let translation: String
    let sentence: String
    let partOfSpeech: String
}
