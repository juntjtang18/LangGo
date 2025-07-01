import Foundation
import SwiftData

@Model
final class Flashcard {
    @Attribute(.unique) var id: Int
    
    // For immediate display
    var frontContent: String
    var backContent: String
    var register: String?
    
    // Stores the full, original component JSON for future use.
    @Attribute(.externalStorage) var rawComponentData: Data?
    
    // This will now store values like "a.word-ref", "a.user-word-ref", etc.
    var contentType: String
    var lastReviewedAt: Date?
    
    // UPDATED: Replaced old streak system with new properties
    var correctStreak: Int
    var wrongStreak: Int
    
    var isRemembered: Bool
    
    // UPDATED: The init method now uses the new streak properties.
    init(id: Int, frontContent: String, backContent: String, register: String?, contentType: String, rawComponentData: Data?, lastReviewedAt: Date?, correctStreak: Int, wrongStreak: Int, isRemembered: Bool) {
        self.id = id
        self.frontContent = frontContent
        self.backContent = backContent
        self.register = register
        self.contentType = contentType
        self.rawComponentData = rawComponentData
        self.lastReviewedAt = lastReviewedAt
        self.correctStreak = correctStreak
        self.wrongStreak = wrongStreak
        self.isRemembered = isRemembered
    }
    
    private var decodedComponent: StrapiComponent? {
        guard let data = rawComponentData else { return nil }
        return try? JSONDecoder().decode(StrapiComponent.self, from: data)
    }
    
    /// Returns the full WordAttributes struct if this flashcard is an official word.
    var wordAttributes: WordAttributes? {
        guard contentType == "a.word-ref" else { return nil }
        return decodedComponent?.word?.data?.attributes
    }
    
    /// Returns the full SentenceAttributes struct if this flashcard is an official sentence.
    var sentenceAttributes: SentenceAttributes? {
        guard contentType == "a.sent-ref" else { return nil }
        return decodedComponent?.sentence?.data?.attributes
    }
    
    /// Returns the full UserWordAttributes struct if this flashcard is a user-created word.
    var userWordAttributes: UserWordAttributes? {
        guard contentType == "a.user-word-ref" else { return nil }
        return decodedComponent?.userWord?.data?.attributes
    }
    
    /// Returns the full UserSentenceAttributes struct if this flashcard is a user-created sentence.
    var userSentenceAttributes: UserSentenceAttributes? {
        guard contentType == "a.user-sent-ref" else { return nil }
        return decodedComponent?.userSentence?.data?.attributes
    }
}
