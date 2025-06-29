import Foundation
import SwiftData

@Model
final class Flashcard {
    @Attribute(.unique) var id: Int
    
    // For immediate display
    var frontContent: String
    var backContent: String
    
    // Stores the full, original component JSON for future use.
    @Attribute(.externalStorage) var rawComponentData: Data?
    
    var contentType: String // "word" or "sentence"
    var lastReviewedAt: Date?
    var dailyStreak: Int
    var weeklyStreak: Int
    var weeklyWrongStreak: Int
    var monthlyStreak: Int
    var monthlyWrongStreak: Int
    var isRemembered: Bool
    
    init(id: Int, frontContent: String, backContent: String, contentType: String, rawComponentData: Data?, lastReviewedAt: Date?, dailyStreak: Int, weeklyStreak: Int, weeklyWrongStreak: Int, monthlyStreak: Int, monthlyWrongStreak: Int, isRemembered: Bool) {
        self.id = id
        self.frontContent = frontContent
        self.backContent = backContent
        self.contentType = contentType
        self.rawComponentData = rawComponentData
        self.lastReviewedAt = lastReviewedAt
        self.dailyStreak = dailyStreak
        self.weeklyStreak = weeklyStreak
        self.weeklyWrongStreak = weeklyWrongStreak
        self.monthlyStreak = monthlyStreak
        self.monthlyWrongStreak = monthlyWrongStreak
        self.isRemembered = isRemembered
    }
}
