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
    let dailyStreak: Int?
    let weeklyStreak: Int?
    let weeklyWrongStreak: Int?
    let monthlyStreak: Int?
    let monthlyWrongStreak: Int?
    let isRemembered: Bool?
    let content: [StrapiComponent]

    // FINAL FIX: Removed the incorrect 'id' case from the enum to match the struct's properties.
    enum CodingKeys: String, CodingKey {
        case createdAt, updatedAt, locale, content
        case lastReviewedAt = "last_reviewed_at"
        case dailyStreak = "daily_streak"
        case weeklyStreak = "weekly_streak"
        case weeklyWrongStreak = "weekly_wrong_streak"
        case monthlyStreak = "monthly_streak"
        case monthlyWrongStreak = "monthly_wrong_streak"
        case isRemembered = "is_remembered"
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

// MARK: - Final Attribute Structs
struct UserWordAttributes: Codable {
    let word: String?
    let baseText: String?
    let partOfSpeech: String?
    let createdAt: String?
    let updatedAt: String?
    let locale: String?

    // FINAL FIX: Added missing cases for createdAt and updatedAt to match the struct's properties.
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

    enum CodingKeys: String, CodingKey {
        case word, instruction, gender, article, createdAt, updatedAt, locale, audio, tags
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
    
    enum CodingKeys: String, CodingKey {
        case title, instruction, createdAt, updatedAt, locale, tags, words
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
