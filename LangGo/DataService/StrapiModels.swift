// LangGo/DataService/StrapiModels.swift
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
    let displayName: String?   // NEW

    enum CodingKeys: String, CodingKey {
        case tier, min_streak, max_streak, cooldown_hours, demote_bar
        case displayName = "display_name"
    }
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
    let proficiency: String? // Changed from Int?
    let reminder_enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case email, password, username, baseLanguage, telephone, proficiency
        case reminder_enabled = "reminder_enabled"
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

// ADDED: Structs for the new ProficiencyLevel collection
struct ProficiencyLevel: Codable, Identifiable, Hashable {
    let id: Int
    let attributes: ProficiencyLevelAttributes
}

struct ProficiencyLevelAttributes: Codable, Hashable {
    let key: String
    let displayName: String
    let description: String?
    let level: Int
}



// MARK: - User Profile Models
struct UserProfileUpdatePayload: Encodable {
    let baseLanguage: String
    let proficiency: String? // Changed from Int?
    let reminder_enabled: Bool?
    let telephone: String?
    let bio: String?
    let visible_on_ladder: Bool?

    init(
        baseLanguage: String,
        proficiency: String?,
        reminder_enabled: Bool?,
        telephone: String? = nil,
        bio: String? = nil,
        visible_on_ladder: Bool? = nil
    ) {
        self.baseLanguage = baseLanguage
        self.proficiency = proficiency
        self.reminder_enabled = reminder_enabled
        self.telephone = telephone
        self.bio = bio
        self.visible_on_ladder = visible_on_ladder
    }

    enum CodingKeys: String, CodingKey {
        case baseLanguage, proficiency, telephone
        case visible_on_ladder
        case reminder_enabled = "reminder_enabled"
        case bio = "Bio"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseLanguage, forKey: .baseLanguage)
        try container.encodeIfPresent(proficiency, forKey: .proficiency)
        try container.encodeIfPresent(reminder_enabled, forKey: .reminder_enabled)
        try container.encodeIfPresent(telephone, forKey: .telephone)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(visible_on_ladder, forKey: .visible_on_ladder)
    }
}

// Add this struct to wrap the payload
struct UserProfileUpdatePayloadWrapper: Encodable {
    let data: UserProfileUpdatePayload
}

struct UserAvatarUpdatePayload: Encodable {
    let avatarImageId: Int

    enum CodingKeys: String, CodingKey {
        case avatarImageId = "avatar_img"
    }
}

struct UserAvatarUpdatePayloadWrapper: Encodable {
    let data: UserAvatarUpdatePayload
}

struct UploadedMediaFile: Codable, Identifiable {
    let id: Int
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
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, caption, width, height, formats, hash, ext, mime, size, url, provider, createdAt, updatedAt
        case alternativeText
        case previewUrl
    }
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
    let dueForReview: Int
    let reviewed: Int
    let hardToRemember: Int
    let byTier: [StrapiTierStat]
}
struct StrapiTierStat: Codable, Identifiable {
    let id: Int
    let tier: String
    let displayName: String?
    let min_streak: Int
    let max_streak: Int
    let cooldown_hours: Int
    let count: Int
    let dueCount: Int
    let hardToRememberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, tier
        case displayName = "display_name"
        case min_streak, max_streak, cooldown_hours, count, dueCount, hardToRememberCount
    }
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

struct StrapiData<T: Codable>: Codable, Identifiable {
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
    let locale: String // Add this line

    enum CodingKeys: String, CodingKey {
        case targetText = "target_text"
        case baseText = "base_text"
        case partOfSpeech = "part_of_speech"
        case locale // Add this line
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

// MARK: - User Article Models
struct StrapiArticleTag: Codable, Identifiable {
    let id: Int
    let attributes: StrapiArticleTagAttributes
}

struct StrapiArticleTagAttributes: Codable {
    let tag: String?
}

struct StrapiUserArticle: Codable, Identifiable {
    let id: Int
    let attributes: StrapiUserArticleAttributes
}

struct StrapiUserArticleAttributes: Codable {
    let title: String?
    let content: String?
    let languageCode: String?
    let wordCount: Int?
    let progress: Double?
    let lastReadAt: Date?
    let articleTags: ManyRelation<StrapiArticleTag>?

    enum CodingKeys: String, CodingKey {
        case title, content, progress
        case languageCode = "language_code"
        case wordCount = "word_count"
        case lastReadAt = "last_read_at"
        case articleTags = "article_tags"
    }
}

struct CreateArticleTagRequest: Encodable {
    let data: CreateArticleTagPayload
}

struct CreateArticleTagPayload: Encodable {
    let tag: String
    let user: Int
}

struct UpdateArticleTagRequest: Encodable {
    let data: UpdateArticleTagPayload
}

struct UpdateArticleTagPayload: Encodable {
    let tag: String
}

struct SaveUserArticleRequest: Encodable {
    let data: SaveUserArticlePayload
}

struct SaveUserArticlePayload: Encodable {
    let title: String
    let content: String
    let languageCode: String?
    let wordCount: Int?
    let user: Int
    let progress: Double?
    let lastReadAt: Date?
    let articleTags: [Int]

    enum CodingKeys: String, CodingKey {
        case title, content, user, progress
        case languageCode = "language_code"
        case wordCount = "word_count"
        case lastReadAt = "last_read_at"
        case articleTags = "article_tags"
    }
}


struct Flashcard: Codable, Identifiable, Equatable {
    let id: Int
    
    // This now holds the complete related WordDefinition object, including its ID and attributes.
    let wordDefinition: StrapiWordDefinition?
    
    // Computed properties are updated to access the nested attributes.
    var frontContent: String {
        wordDefinition?.attributes.baseText ?? "Missing Question"
    }
    var backContent: String {
        wordDefinition?.attributes.word?.data?.attributes.targetText ?? "Missing Answer"
    }
    var register: String? {
        wordDefinition?.attributes.register
    }
    
    var lastReviewedAt: Date?
    var correctStreak: Int
    var wrongStreak: Int
    var isRemembered: Bool
    var reviewTire: String?

    init(id: Int, wordDefinition: StrapiWordDefinition?, lastReviewedAt: Date?, correctStreak: Int, wrongStreak: Int, isRemembered: Bool, reviewTire: String?) {
        self.id = id
        self.wordDefinition = wordDefinition
        self.lastReviewedAt = lastReviewedAt
        self.correctStreak = correctStreak
        self.wrongStreak = wrongStreak
        self.isRemembered = isRemembered
        self.reviewTire = reviewTire
    }
    
    // --- MODIFICATION: Manually implement the Equatable conformance ---
    // This tells Swift that two Flashcard objects are equal if their IDs are the same.
    static func == (lhs: Flashcard, rhs: Flashcard) -> Bool {
        lhs.id == rhs.id
    }
}
