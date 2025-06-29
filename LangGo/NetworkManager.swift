import Foundation
import KeychainAccess
import os // Import for detailed logging

/// A centralized manager for handling network requests.
class NetworkManager {
    static let shared = NetworkManager()
    private let decoder: JSONDecoder
    private let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "NetworkManager")

    private init() {
        decoder = JSONDecoder()
        // FINAL FIX: Removing the global strategy. All key mapping will now be handled
        // explicitly in the models themselves for maximum clarity and robustness.
        // decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        decoder.dateDecodingStrategy = .formatted(formatter)
    }

    func fetch(from url: URL) async throws -> StrapiResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = keychain["jwt"] {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            logger.warning("JWT token not found in keychain. Request to \(url.lastPathComponent) will be unauthenticated.")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP Error: Received status code \(httpResponse.statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        
        // --- NEW LOG ---
        // As requested, this logs the raw JSON string before decoding.
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("Received JSON response:\n---START JSON---\n\(jsonString)\n---END JSON---")
        }
        // ---

        do {
            return try decoder.decode(StrapiResponse.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode the JSON response. Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            throw error
        }
    }
}
