// DataService/Models.swift

import Foundation

// ADDED: A new struct to represent the nested user_profile attributes.
struct UserProfileAttributes: Codable {
    let proficiency: String?
    let reminder_enabled: Bool?
    let baseLanguage: String?
    let telephone: String?
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
