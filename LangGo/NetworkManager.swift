import Foundation
import KeychainAccess
import os

/// A centralized manager for handling network requests.
class NetworkManager {
    static let shared = NetworkManager()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "NetworkManager")

    private init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        decoder.dateDecodingStrategy = .formatted(formatter)
        encoder.dateEncodingStrategy = .formatted(formatter)
        // This strategy handles converting camelCase (like `reviewedAt`) to snake_case (`reviewed_at`)
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Fetches data and decodes it into a StrapiResponse (an array of items).
    func fetch(from url: URL) async throws -> StrapiResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = keychain["jwt"] {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            logger.warning("JWT token not found in keychain. Request to \(url.lastPathComponent) will be unauthenticated.")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("HTTP GET Error: Received status code \(statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        
        do {
            return try decoder.decode(StrapiResponse.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode StrapiResponse. Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            throw error
        }
    }
    
    /// Fetches the current user from /api/users/me
    func fetchUser(from url: URL) async throws -> StrapiUser {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let token = keychain["jwt"] else {
            logger.error("JWT token not found. Cannot fetch user profile.")
            throw URLError(.userAuthenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
             let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("HTTP Error: Received status code \(statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        
        do {
            return try decoder.decode(StrapiUser.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode StrapiUser. Error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - POST Requests (REVISED)

    /// Generic function to POST Codable data and receive a Decodable response.
    /// This is used for the review endpoint which returns the updated flashcard.
    func post<T: Codable, U: Decodable>(to url: URL, body: T) async throws -> U {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let token = keychain["jwt"] else {
            logger.error("JWT token not found. Cannot make authenticated POST request.")
            throw URLError(.userAuthenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = try encoder.encode(body)
        
        if let jsonString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            logger.debug("POST body for \(url): \(jsonString)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("HTTP POST Error: Received status code \(statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("Received JSON response from POST:\n\(jsonString)")
        }
        
        do {
            // The review endpoint returns the single updated flashcard, not wrapped in a "data" object.
            return try decoder.decode(U.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode response of type \(U.self). Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            throw error
        }
    }
}
