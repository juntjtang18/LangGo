// UserModels.swift
import Foundation


/// Represents the main user object returned from the `/api/users/me` endpoint.
struct StrapiUser: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
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
