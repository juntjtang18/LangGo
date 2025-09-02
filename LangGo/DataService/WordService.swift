//
//  WordService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/23.
//


// LangGo/DataService/WordService.swift

import Foundation
import os

class WordService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "WordService")
    private let networkManager = NetworkManager.shared
    private let flashcardService: FlashcardService
    
    init(flashcardService: FlashcardService) {
        self.flashcardService = flashcardService
    }
    
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String, locale: String) async throws -> WordDefinitionResponse {
        logger.debug("WordService: Saving new word.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/word-definitions") else { throw URLError(.badURL) }
        let payload = WordDefinitionCreationPayload(targetText: targetText, baseText: baseText, partOfSpeech: partOfSpeech, locale: locale)
        let requestBody = CreateWordDefinitionRequest(data: payload)
        let response: WordDefinitionResponse = try await networkManager.post(to: url, body: requestBody)
        
        flashcardService.invalidateAllFlashcardCaches()
        return response
    }

    func searchWords(term: String) async throws -> [StrapiWord] {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/words/search") else { throw URLError(.badURL) }
        urlComponents.queryItems = [URLQueryItem(name: "term", value: term)]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiWord> = try await networkManager.fetchDirect(from: url)
        return response.data ?? []
    }

    func searchWordDefinitions(term: String) async throws -> [StrapiWordDefinition] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/word-definitions/search-by-target") else { throw URLError(.badURL) }
        urlComponents.queryItems = [URLQueryItem(name: "term", value: q)]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiWordDefinition> = try await networkManager.fetchDirect(from: url)
        return response.data ?? []
    }
    
    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word") else { throw URLError(.badURL) }
        let requestBody = TranslateWordRequest(word: word, source: source, target: target)
        return try await networkManager.post(to: url, body: requestBody)
    }

    func translateWordInContext(word: String, sentence: String, sourceLang: String, targetLang: String) async throws -> TranslateWordInContextResponse {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word-context") else { throw URLError(.badURL) }
        let requestBody = TranslateWordInContextRequest(word: word, sentence: sentence, sourceLang: sourceLang, targetLang: targetLang)
        return try await networkManager.post(to: url, body: requestBody)
    }
}
