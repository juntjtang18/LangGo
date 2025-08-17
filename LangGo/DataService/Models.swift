// DataService/Models.swift

import Foundation

// ADDED: A new struct to represent the nested user_profile attributes.
struct UserProfileAttributes: Codable {
    let proficiency: String?  // Change to String?
    let reminder_enabled: Bool?
    let baseLanguage: String?
    let telephone: String?
}

struct Language: Hashable, Identifiable {
    let id: String // The language code, e.g., "en", "ja"
    let name: String // The display name, e.g., "English"
}

/// Represents the main user object returned from the `/api/users/me` endpoint.
struct StrapiUser: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
    // MODIFIED: This now correctly reflects the nested user_profile object.
    let user_profile: UserProfileAttributes?
    
    enum CodingKeys: String, CodingKey {
        case id, username, email
        case user_profile
    }
    /*
    static var availableLanguages: [Language] {
        return Bundle.main.localizations
            .filter { $0 != "Base" }
            .compactMap { langCode in
                guard let languageName = Locale(identifier: "en").localizedString(forIdentifier: langCode) else {
                    return nil
                }
                return Language(id: langCode, name: languageName.capitalized)
            }
            .sorted { $0.name < $1.name }
    }
     */
}

enum PartOfSpeech: String, CaseIterable, Identifiable {
    case noun, verb, adjective, adverb, conjunction, preposition, interjection, determiner, pronoun
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .noun: return "Noun"
        case .verb: return "Verb"
        case .adjective: return "Adjective"
        case .adverb: return "Adverb"
        case .conjunction: return "Conjunction"
        case .preposition: return "Preposition"
        case .interjection: return "Interjection"
        case .determiner: return "Determiner"
        case .pronoun: return "Pronoun"
        }
    }
}
