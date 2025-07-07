import Foundation
import KeychainAccess
import os

/// A centralized, generic manager for handling all network requests.
class NetworkManager {
    static let shared = NetworkManager()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let keychain = Keychain(service: Config.keychainService)
    private let logger = Logger(subsystem: "com.langGo.swift", category: "NetworkManager") // Changed subsystem to match LangGo

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
    }

    // MARK: - Public API Methods
    
    /// Performs a user login.
    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        return try await performRequest(url: url, method: "POST", body: credentials)
    }

    /// Fetches the authenticated user's profile.
    func fetchUser() async throws -> StrapiUser {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        return try await performRequest(url: url, method: "GET")
    }

    /// Registers a new user.
    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/register") else { throw URLError(.badURL) } // Updated to new register endpoint
        return try await performRequest(url: url, method: "POST", body: payload)
    }

    /// Fetches a single page of items and returns the response shell, including pagination metadata.
    func fetchPage<T: Codable>(baseURLComponents: URLComponents, page: Int, pageSize: Int = 25) async throws -> StrapiListResponse<T> {
        var components = baseURLComponents
        var queryItems = components.queryItems ?? []

        queryItems.removeAll { $0.name == "pagination[page]" || $0.name == "pagination[pageSize]" }
        queryItems.append(URLQueryItem(name: "pagination[page]", value: String(page)))
        queryItems.append(URLQueryItem(name: "pagination[pageSize]", value: String(pageSize)))
        components.queryItems = queryItems
        
        guard let url = components.url else { throw URLError(.badURL) }
        
        return try await performRequest(url: url, method: "GET")
    }

    /// Fetches all pages for a given query by aggregating the results. Useful for background data sync.
    func fetchAllPages<T: Codable>(baseURLComponents: URLComponents) async throws -> [T] {
        var allItems: [T] = []
        var currentPage = 1
        var totalPages = 1
        
        repeat {
            let response: StrapiListResponse<T> = try await fetchPage(baseURLComponents: baseURLComponents, page: currentPage, pageSize: 100)
            
            if let items = response.data {
                allItems.append(contentsOf: items)
            }
            
            if let pagination = response.meta?.pagination {
                totalPages = pagination.pageCount
            }
            
            currentPage += 1
            
        } while currentPage <= totalPages
        
        return allItems
    }
    
    /// Fetches a single resource that is wrapped in a `data` key (e.g., `/api/flashcard-stat`).
    func fetchSingle<T: Codable>(from url: URL) async throws -> T {
        let response: StrapiSingleResponse<T> = try await performRequest(url: url, method: "GET")
        return response.data
    }

    /// Fetches a resource directly, without a `data` wrapper (e.g., `/api/users/me`).
    func fetchDirect<T: Decodable>(from url: URL) async throws -> T {
        return try await performRequest(url: url, method: "GET")
    }

    /// Performs a POST request with an encodable body and expects a decodable response.
    func post<RequestBody: Encodable, ResponseBody: Decodable>(to url: URL, body: RequestBody) async throws -> ResponseBody {
        return try await performRequest(url: url, method: "POST", body: body)
    }
    
    /// Performs a PUT request with an encodable body and expects a decodable response.
    func put<RequestBody: Encodable, ResponseBody: Decodable>(to url: URL, body: RequestBody) async throws -> ResponseBody {
        return try await performRequest(url: url, method: "PUT", body: body)
    }

    /// Performs a DELETE request, expecting an empty response.
    func delete(at url: URL) async throws {
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Private Core Request Function

    /// Generic function to perform any HTTP request, handle authentication, errors, and decoding.
    private func performRequest<ResponseBody: Decodable, RequestBody: Encodable>(url: URL, method: String, body: RequestBody? = nil) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let isAuthRequest = url.absoluteString.contains("/api/auth/local") || url.absoluteString.contains("/api/user-profiles/register")
        if let token = keychain["jwt"], !isAuthRequest {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try encoder.encode(body)
            if let jsonString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                logger.debug("Request body for \(url): \(jsonString)")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("HTTP Error: \(method) request to \(url) failed with status code \(httpResponse.statusCode). Body: \(errorBody)")
            if let errorResponse = try? decoder.decode(StrapiErrorResponse.self, from: data) {
                // Throw a custom error with specific Strapi message
                throw NSError(domain: "NetworkManager.StrapiError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Received status code \(httpResponse.statusCode)."])
        }
        
        if data.isEmpty {
            guard let empty = EmptyResponse() as? ResponseBody else {
                logger.error("Failed to cast EmptyResponse to \(ResponseBody.self)")
                throw URLError(.cannotParseResponse)
            }
            return empty
        }

        do {
            if let jsonString = String(data: data, encoding: .utf8) {
                logger.debug("Received JSON response for \(url):\n\(jsonString)")
            }
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            logger.error("Decoding Error: Failed to decode \(ResponseBody.self). Error: \(error.localizedDescription)")
            logger.error("Decoding Error Details: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) { logger.error("Raw JSON: \(jsonString)") }
            throw error
        }
    }
    
    // Overload for requests without a body (GET, DELETE without specific body)
    private func performRequest<ResponseBody: Decodable>(url: URL, method: String) async throws -> ResponseBody {
        let emptyBody: EmptyPayload? = nil
        return try await performRequest(url: url, method: method, body: emptyBody)
    }
}

// Private structs used internally by NetworkManager
private struct EmptyResponse: Codable {}
private struct EmptyPayload: Codable {}
