import Foundation
import KeychainAccess
import os

/// A centralized manager for handling network requests.
class NetworkManager {
    static let shared = NetworkManager()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder // NEW: Encoder for POST requests
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
        // NEW: Ensure the encoder uses the same date format Strapi expects.
        encoder.dateEncodingStrategy = .formatted(formatter)
        // NEW: The review log model uses camelCase, so we need to convert to snake_case for the JSON payload.
        encoder.keyEncodingStrategy = .convertToSnakeCase
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
        
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("Received JSON response:\n---START JSON---\n\(jsonString)\n---END JSON---")
        }

        do {
            return try decoder.decode(StrapiResponse.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode StrapiResponse. Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            throw error
        }
    }
    
    // NEW: Function to fetch the current user from /api/users/me
    func fetchUser(from url: URL) async throws -> StrapiUser {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let token = keychain["jwt"] else {
            logger.error("JWT token not found. Cannot fetch user profile.")
            throw URLError(.userAuthenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP Error: Received status code \(httpResponse.statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        
        do {
            return try decoder.decode(StrapiUser.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode StrapiUser. Error: \(error.localizedDescription)")
            throw error
        }
    }

    // NEW: Generic function to POST Codable data
    func post<T: Codable>(to url: URL, body: T) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let token = keychain["jwt"] else {
            logger.error("JWT token not found. Cannot make authenticated POST request.")
            throw URLError(.userAuthenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("HTTP POST Error: Received status code \(statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }
        logger.info("Successfully posted data to \(url).")
    }
    
    // Function to fetch the current user's review logs from the new endpoint
    func fetchMyReviewLogs() async throws -> [StrapiReviewLog] {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/my-reviewlogs?populate=*") else {
            logger.error("Invalid URL for /api/my-reviewlogs")
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let token = keychain["jwt"] else {
            logger.error("JWT token not found. Cannot fetch review logs.")
            throw URLError(.userAuthenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP Error: Received status code \(httpResponse.statusCode) for URL \(url). Body: \(errorBody)")
            throw URLError(.badServerResponse)
        }

        do {
            // Strapi's transformResponse unwraps the 'data' key, so we decode the array directly.
            return try decoder.decode([StrapiReviewLog].self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode [StrapiReviewLog]. Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            throw error
        }
    }
}
