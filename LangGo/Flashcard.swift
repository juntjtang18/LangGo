//
//  Flashcard.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation
import SwiftData

// 1. SWIFTDATA MODEL: This is what you'll store and use locally in your app.
@Model
final class Flashcard {
    // Strapi's unique ID for the record. Use `@Attribute(.unique)` to prevent duplicates.
    @Attribute(.unique) var id: Int
    
    // Simplified content from the dynamic zone.
    var content: String
    var contentType: String // "word" or "sentence"
    
    var correctTimes: Int
    var wrongTimes: Int
    var lastViewedAt: Date?
    
    init(id: Int, content: String, contentType: String, correctTimes: Int, wrongTimes: Int, lastViewedAt: Date?) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.correctTimes = correctTimes
        self.wrongTimes = wrongTimes
        self.lastViewedAt = lastViewedAt
    }
}


// 2. DTO (Data Transfer Object): This struct matches the Strapi JSON structure for easy decoding.
struct StrapiResponse: Codable {
    let data: [StrapiFlashcard]
}

struct StrapiFlashcard: Codable {
    let id: Int
    let attributes: FlashcardAttributes
}

struct FlashcardAttributes: Codable {
    let correct_times: Int
    let wrong_times: Int
    let lastview_at: Date?
    
    // For now, we assume the dynamic zone has at least one item
    // and we just grab the first one's content for simplicity.
    // A full implementation would decode this array properly.
    let content: [StrapiComponent]
    
    // A simplified model for the dynamic zone component
    struct StrapiComponent: Codable {
        // You can add other fields from your components here
        let __component: String
        let text: String? // Assuming your components have a 'text' field
        let sentence: String? // Assuming your components have a 'sentence' field
    }
}
