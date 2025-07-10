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
}

struct FlashcardAttributes: Codable {
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let lastReviewedAt: Date?
    let content: [StrapiComponent]?
    
    let correctStreak: Int?
    let wrongStreak: Int?
    let isRemembered: Bool
    let reviewTire: ReviewTireRelation? // NEW: Added for the new relation

    enum CodingKeys: String, CodingKey {
        case createdAt, updatedAt, locale, content
        case lastReviewedAt = "last_reviewed_at"
        case correctStreak = "correct_streak"
        case wrongStreak = "wrong_streak"
        case isRemembered = "is_remembered"
        case reviewTire = "review_tire" // NEW: Coding key for review_tire
    }
}

// MARK: - NEW: ReviewTire Models
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

// MARK: - Dynamic Zone Component
struct StrapiComponent: Codable {
    let id: Int
    let componentIdentifier: String
    let userWord: UserWordRelation?
    let userSentence: UserSentenceRelation?
    let word: WordRelation?
    let sentence: SentenceRelation?

    enum CodingKeys: String, CodingKey {
        case id
        case componentIdentifier = "__component"
        case userWord = "user_word"
        case userSentence = "user_sentence"
        case word, sentence
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
typealias UserWordRelation = Relation<StrapiData<UserWordAttributes>>
typealias UserSentenceRelation = Relation<StrapiData<UserSentenceAttributes>>
typealias WordRelation = Relation<StrapiData<WordAttributes>>
typealias SentenceRelation = Relation<StrapiData<SentenceAttributes>>
typealias MediaRelation = Relation<StrapiData<MediaAttributes>>
typealias ExampleSentencesRelation = ManyRelation<StrapiData<SentenceAttributes>>
typealias WordsRelation = ManyRelation<StrapiData<WordAttributes>>
typealias ReviewTireRelation = Relation<StrapiData<ReviewTireAttributes>> // NEW: Typealias for the review tire relation


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
    let isCorrect: Bool

    enum CodingKeys: String, CodingKey {
        case text, isCorrect
    }
}

struct UserWordAttributes: Codable {
    let targetText: String?
    let baseText: String?
    let partOfSpeech: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?
    let examBase: [ExamOption]?
    let examTarget: [ExamOption]?

    enum CodingKeys: String, CodingKey {
        case locale, createdAt, updatedAt
        case targetText = "target_text"
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case examBase = "exam_base"
        case examTarget = "exam_target"
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
    let examBase: [ExamOption]?
    let examTarget: [ExamOption]?

    enum CodingKeys: String, CodingKey {
        case word, instruction, gender, article, createdAt, updatedAt, locale, audio, tags, register
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case exampleSentences = "example_sentences"
        case verbMeta = "verb_meta"
        case examBase = "exam_base"
        case examTarget = "exam_target"
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
    let examBase: [ExamOption]?
    let examTarget: [ExamOption]?
    
    enum CodingKeys: String, CodingKey {
        case title, instruction, createdAt, updatedAt, locale, tags, words, register
        case baseText = "base_text"
        case targetText = "target_text"
        case targetAudio = "target_audio"
        case examBase = "exam_base"
        case examTarget = "exam_target"
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

// MARK: - User Word & Translation Models
struct CreateUserWordRequest: Encodable {
    let data: UserWordData
}

struct UserWordData: Encodable {
    let target_text: String
    let base_text: String
    let part_of_speech: String
    let base_locale: String
    let target_locale: String
}

struct UserWordResponse: Decodable {
    let data: StrapiData<UserWordAttributes>
}

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
