//
//  ConversationModels.swift
//  LangGo
//
//  Created by James Tang on 2025/7/19.
//
import Foundation

struct ConversationMessage: Codable, Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

struct NextPromptRequest: Codable {
    let history: [ConversationMessage]
    let topic_title: String?
    let sessionId: String
}

struct StartConversationResponse: Codable {
    let next_prompt: String
    let suggested_topic: String?
    let sessionId: String
}

struct NextPromptResponse: Codable {
    let next_prompt: String
    let sessionId: String
}
