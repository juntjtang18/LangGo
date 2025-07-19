//
//  ConversationService.swift
//  LangGo
//
//  Created by James Tang on 2025/7/19.
//

import Foundation
import os

class ConversationService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ConversationService")

    func startConversation() async throws -> StartConversationResponse {
        logger.debug("ConversationService: Starting conversation.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/v1/conversation/start") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchDirect(from: url)
    }

    func getNextPrompt(history: [ConversationMessage], topic: String?) async throws -> NextPromptResponse {
        logger.debug("ConversationService: Getting next conversation prompt.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/v1/conversation/nextprompt") else { throw URLError(.badURL) }
        let payload = NextPromptRequest(history: history, topic_title: topic)
        return try await NetworkManager.shared.post(to: url, body: payload)
    }
}
