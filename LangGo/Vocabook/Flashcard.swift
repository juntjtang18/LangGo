// LangGo/Vocabook/Flashcard.swift
import Foundation

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
