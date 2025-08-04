// LangGo/Vocabook/Flashcard.swift
import Foundation

struct Flashcard: Codable, Identifiable {
    let id: Int
    
    // The complete definition data is now stored here.
    let definition: WordDefinitionAttributes?
    
    // For immediate display, these are now computed properties.
    var frontContent: String {
        definition?.baseText ?? "Missing Question"
    }
    var backContent: String {
        definition?.word?.data?.attributes.targetText ?? "Missing Answer"
    }
    var register: String? {
        definition?.register
    }
    
    var lastReviewedAt: Date?
    var correctStreak: Int
    var wrongStreak: Int
    var isRemembered: Bool
    var reviewTire: String?

    init(id: Int, definition: WordDefinitionAttributes?, lastReviewedAt: Date?, correctStreak: Int, wrongStreak: Int, isRemembered: Bool, reviewTire: String?) {
        self.id = id
        self.definition = definition
        self.lastReviewedAt = lastReviewedAt
        self.correctStreak = correctStreak
        self.wrongStreak = wrongStreak
        self.isRemembered = isRemembered
        self.reviewTire = reviewTire
    }
}
