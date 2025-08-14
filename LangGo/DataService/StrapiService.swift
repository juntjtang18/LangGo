// LangGo/StrapiService.swift

import Foundation
import os
import SwiftUI // Import SwiftUI to use @AppStorage

// Define typealiases for Strapi data structures to improve clarity
typealias StrapiWord = StrapiData<WordAttributes>
typealias StrapiWordDefinition = StrapiData<WordDefinitionAttributes>

class StrapiService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "StrapiService")
    private let cacheService = CacheService.shared
    
    // MARK: - Cache State Management
    
    /// A single flag to indicate if all local flashcard data is fresh or needs to be re-fetched.
    private var isFlashcardsCacheStale = true
    
    /// Consistent keys for storing and retrieving data from the cache.
    private let allMyFlashcardsCacheKey = "allMyFlashcards" // Consolidated key
    private let reviewFlashcardsCacheKey = "allMyReviewFlashcards"
    private let flashcardStatisticsCacheKey = "flashcardStatistics"
    private let reviewTireSettingsCacheKey = "reviewTireSettings"
    private let vbSettingsCacheKey = "vbSettings"
    
    /// UserDefaults key for storing the last fetch timestamp for TTL caching.
    private let reviewTireSettingsTimestampKey = "reviewTireSettingsTimestamp"
    private let vbSettingsTimestampKey = "vbSettingsTimestamp"

    
    /// Time-To-Live for the review tire settings cache, in seconds (e.g., 24 hours).
    private let reviewTireSettingsTTL: TimeInterval = 86400
    private let vbSettingsTTL: TimeInterval = 86400
    
    /// Reads the refresh mode setting from UserDefaults.
    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    init() {
    }

    // MARK: - Authentication & User Management
    func login(credentials: LoginCredentials) async throws -> AuthResponse {
        logger.debug("StrapiService: Attempting login.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local") else { throw URLError(.badURL) }
        let response: AuthResponse = try await NetworkManager.shared.post(to: url, body: credentials)
        // Invalidate all user-specific caches on login
        self.invalidateAllUserCaches()
        return response
    }

    func signup(payload: RegistrationPayload) async throws -> AuthResponse {
        logger.debug("StrapiService: Attempting signup with proficiency and reminders.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/local/register") else { throw URLError(.badURL) }
        let response: AuthResponse = try await NetworkManager.shared.post(to: url, body: payload)
        // Invalidate caches on a new registration.
        self.invalidateAllUserCaches()
        return response
    }

    func fetchCurrentUser() async throws -> StrapiUser {
        logger.debug("StrapiService: Fetching current user profile.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/me") else { throw URLError(.badURL) }
        return try await NetworkManager.shared.fetchDirect(from: url)
    }
    
    func updateUsername(userId: Int, username: String) async throws -> StrapiUser {
        logger.debug("StrapiService: Updating username for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/users/\(userId)") else { throw URLError(.badURL) }
        let body = ["username": username]
        return try await NetworkManager.shared.put(to: url, body: body)
    }

    func updateBaseLanguage(languageCode: String) async throws {
        logger.debug("StrapiService: Updating base language to \(languageCode).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }

        // CORRECTED: Added nil for the new optional parameters to satisfy the initializer.
        let payload = UserProfileUpdatePayload(baseLanguage: languageCode, proficiency: nil, reminder_enabled: nil)
        let body = UserProfileUpdatePayloadWrapper(data: payload)

        let _: EmptyResponse = try await NetworkManager.shared.put(to: url, body: body)
    }

    // This is the new function from the previous step, now corrected.
    func updateUserProfile(userId: Int, proficiencyKey: String, remindersEnabled: Bool) async throws {
        logger.debug("StrapiService: Updating user profile for user ID: \(userId).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/user-profiles/mine") else { throw URLError(.badURL) }

        let baseLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"

        let payload = UserProfileUpdatePayload(
            baseLanguage: baseLanguage,
            proficiency: proficiencyKey,
            reminder_enabled: remindersEnabled
        )
        let body = UserProfileUpdatePayloadWrapper(data: payload)

        let _: EmptyResponse = try await NetworkManager.shared.put(to: url, body: body)
    }


    func changePassword(currentPassword: String, newPassword: String, confirmNewPassword: String) async throws -> EmptyResponse {
        logger.debug("StrapiService: Changing password.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/auth/change-password") else { throw URLError(.badURL) }
        let body = [
            "currentPassword": currentPassword,
            "password": newPassword,
            "passwordConfirmation": confirmNewPassword
        ]
        return try await NetworkManager.shared.post(to: url, body: body)
    }

    // MARK: - Flashcard & Review

    func fetchFlashcardStatistics() async throws -> StrapiStatistics {
        if !isFlashcardsCacheStale {
            if let cachedStats = cacheService.load(type: StrapiStatistics.self, from: flashcardStatisticsCacheKey) {
                logger.debug("✅ Returning flashcard statistics from cache.")
                return cachedStats
            }
        }
        
        logger.debug("StrapiService: Cache is stale or empty. Fetching flashcard statistics from network.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcard-stat") else { throw URLError(.badURL) }
        let stats: StrapiStatistics = try await NetworkManager.shared.fetchSingle(from: url)
        
        cacheService.save(stats, key: flashcardStatisticsCacheKey)
        logger.debug("💾 Saved fetched statistics to cache.")
        
        return stats
    }
    
    func fetchReviewTireSettings() async throws -> [StrapiReviewTire] {
        if !isRefreshModeEnabled {
            let userDefaults = UserDefaults.standard
            let lastFetchDate = userDefaults.object(forKey: reviewTireSettingsTimestampKey) as? Date

            if let lastFetch = lastFetchDate, -lastFetch.timeIntervalSinceNow < reviewTireSettingsTTL {
                if let cachedSettings = cacheService.load(type: [StrapiReviewTire].self, from: reviewTireSettingsCacheKey) {
                    logger.debug("✅ Returning review tire settings from cache (TTL valid).")
                    return cachedSettings
                }
            }
        } else {
            logger.debug("🔄 Refresh mode is enabled. Bypassing cache for review tire settings.")
        }

        logger.debug("StrapiService: Fetching review tire settings from network.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/review-tires") else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiReviewTire> = try await NetworkManager.shared.fetchDirect(from: url)
        let settings = response.data ?? []

        cacheService.save(settings, key: reviewTireSettingsCacheKey)
        UserDefaults.standard.set(Date(), forKey: reviewTireSettingsTimestampKey)
        logger.debug("💾 Saved fetched review tire settings to cache and updated timestamp.")

        return settings
    }

    func fetchAllReviewFlashcards() async throws -> [Flashcard] {
        if !isFlashcardsCacheStale {
            if let cachedFlashcards = cacheService.load(type: [Flashcard].self, from: reviewFlashcardsCacheKey) {
                logger.debug("✅ Returning review flashcards from cache.")
                return cachedFlashcards
            }
        }

        logger.debug("Cache for review flashcards is stale or empty. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        let pageSize = 100
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await self.fetchReviewFlashcardsPage(page: currentPage, pageSize: pageSize)
            
            if !cards.isEmpty {
                allCards.append(contentsOf: cards)
            }
            
            if let pag = pagination {
                hasMorePages = pag.page < pag.pageCount
                currentPage += 1
            } else {
                hasMorePages = false
            }
        }
        
        cacheService.save(allCards, key: reviewFlashcardsCacheKey)
        self.isFlashcardsCacheStale = false
        
        return allCards
    }

    func submitFlashcardReview(cardId: Int, result: ReviewResult) async throws -> Flashcard {
        logger.debug("StrapiService: Submitting review for card ID: \(cardId) with result: \(result.rawValue).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/flashcards/\(cardId)/review") else { throw URLError(.badURL) }
        let body = ReviewBody(result: result.rawValue)
        let response: Relation<StrapiFlashcard> = try await NetworkManager.shared.post(to: url, body: body)
        
        guard let updatedStrapiCard = response.data else {
            throw NSError(domain: "StrapiServiceError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response was missing the 'data' object."])
        }
        
        self.invalidateAllUserCaches()
        
        let flashcard = transformStrapiCard(updatedStrapiCard)
        return flashcard
    }

    func fetchAllMyFlashcards() async throws -> [Flashcard] {
        return try await getOrFetchAllMyFlashcards()
    }
    
    // MARK: - Flashcards Pagination
    
    func fetchFlashcards(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        // 1. Get the full list of flashcards, either from cache or network.
        let allFlashcards = try await getOrFetchAllMyFlashcards()
        
        // 2. Perform pagination in-memory.
        let totalItems = allFlashcards.count
        let totalPages = (totalItems + pageSize - 1) / pageSize
        
        guard page > 0, page <= totalPages || totalItems == 0 else {
            // Return empty if the requested page is out of bounds, unless there are no items.
            let pagination = StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems)
            return ([], pagination)
        }
        
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, totalItems)
        
        let pageItems = Array(allFlashcards[startIndex..<endIndex])
        
        // 3. Construct the pagination metadata.
        let pagination = StrapiPagination(page: page, pageSize: pageSize, pageCount: totalPages, total: totalItems)
        
        logger.debug("✅ Returning page \(page) of flashcards from in-memory cache.")
        return (pageItems, pagination)
    }

    
    // MARK: - Word Creation, Translation & Search
    
    func saveNewWord(targetText: String, baseText: String, partOfSpeech: String, locale: String) async throws -> WordDefinitionResponse { // Add locale parameter
        logger.debug("StrapiService: Saving new word and definition.")
        
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/word-definitions") else { throw URLError(.badURL) }
        
        let payload = WordDefinitionCreationPayload(
            targetText: targetText,
            baseText: baseText,
            partOfSpeech: partOfSpeech,
            locale: locale // Add locale to payload
        )
        let requestBody = CreateWordDefinitionRequest(data: payload)
        
        let response: WordDefinitionResponse = try await NetworkManager.shared.post(to: url, body: requestBody)
        
        self.invalidateAllUserCaches()
        
        return response
    }

    func searchWords(term: String) async throws -> [StrapiWord] {
        logger.debug("StrapiService: Searching words with term: \(term).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/words/search") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: term)
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiListResponse<StrapiWord> = try await NetworkManager.shared.fetchDirect(from: url)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let responseData = try encoder.encode(response)
            if let jsonString = String(data: responseData, encoding: .utf8) {
                logger.info("Response from searchWords for term '\(term, privacy: .public)':\n\(jsonString, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode or log searchWords response: \(error.localizedDescription)")
        }
        
        return response.data ?? []
    }

    func searchWordDefinitions(term: String) async throws -> [StrapiWordDefinition] {
        logger.debug("StrapiService: Searching word definitions with term: \(term).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/word-definitions/search") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: term)
        ]
        
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        
        let response: StrapiListResponse<StrapiWordDefinition> = try await NetworkManager.shared.fetchDirect(from: url)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let responseData = try encoder.encode(response)
            if let jsonString = String(data: responseData, encoding: .utf8) {
                logger.info("Response from searchWordDefinitions for term '\(term, privacy: .public)':\n\(jsonString, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode or log searchWordDefinitions response: \(error.localizedDescription)")
        }
        
        return response.data ?? []
    }
    func translateWord(word: String, source: String, target: String) async throws -> TranslateWordResponse {
        logger.debug("StrapiService: Translating word '\(word)' from \(source) to \(target).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word") else { throw URLError(.badURL) }
        let requestBody = TranslateWordRequest(word: word, source: source, target: target)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }

    func translateWordInContext(word: String, sentence: String, sourceLang: String, targetLang: String) async throws -> TranslateWordInContextResponse {
        logger.debug("StrapiService: Translating word '\(word)' in context from \(sourceLang) to \(targetLang).")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/translate-word-context") else { throw URLError(.badURL) }
        let requestBody = TranslateWordInContextRequest(word: word, sentence: sentence, sourceLang: sourceLang, targetLang: targetLang)
        return try await NetworkManager.shared.post(to: url, body: requestBody)
    }
    
    // MARK: - VBSetting Endpoints
    func fetchVBSetting() async throws -> VBSetting {
        if !isRefreshModeEnabled {
            let userDefaults = UserDefaults.standard
            let lastFetchDate = userDefaults.object(forKey: vbSettingsTimestampKey) as? Date

            if let lastFetch = lastFetchDate, -lastFetch.timeIntervalSinceNow < vbSettingsTTL {
                if let cachedSettings = cacheService.load(type: VBSetting.self, from: vbSettingsCacheKey) {
                    logger.debug("✅ Returning VB settings from cache (TTL valid).")
                    return cachedSettings
                }
            }
        } else {
            logger.debug("🔄 Refresh mode is enabled. Bypassing cache for VB settings.")
        }

        logger.debug("StrapiService: Fetching VB settings from network.")
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let response: VBSettingSingleResponse = try await NetworkManager.shared.fetchDirect(from: url)
        let settings = response.data
        
        cacheService.save(settings, key: vbSettingsCacheKey)
        UserDefaults.standard.set(Date(), forKey: vbSettingsTimestampKey)
        logger.debug("💾 Saved fetched VB settings to cache and updated timestamp.")

        return settings
    }

    func updateVBSetting(wordsPerPage: Int, interval1: Double, interval2: Double, interval3: Double) async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else {
            throw URLError(.badURL)
        }
        let payload = VBSettingUpdatePayload(data: .init(wordsPerPage: wordsPerPage, interval1: interval1, interval2: interval2, interval3: interval3))
        let response: VBSettingSingleResponse = try await NetworkManager.shared.put(to: url, body: payload)
        
        // Invalidate the cache after a successful update
        cacheService.delete(key: vbSettingsCacheKey)
        logger.debug("✏️ Invalidated VB settings cache due to update.")
        
        return response.data
    }

    func fetchProficiencyLevels(locale: String) async throws -> [ProficiencyLevel] {
        logger.debug("StrapiService: Attempting to fetch proficiency levels for locale: \(locale).")
        let localizedLevels = try await fetchLevels(for: locale)
        if localizedLevels.isEmpty && locale != "en" {
            logger.debug("No results for locale '\(locale)', falling back to 'en'.")
            return try await fetchLevels(for: "en")
        }
        return localizedLevels
    }

    /// A private helper function to perform the actual network request for proficiency levels.
    private func fetchLevels(for locale: String) async throws -> [ProficiencyLevel] {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/proficiency-levels") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "sort", value: "level:asc")
        ]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<ProficiencyLevel> = try await NetworkManager.shared.fetchDirect(from: url)
        return response.data ?? []
    }
    
    // MARK: - Private Helper Functions
    
    /// The single source of truth for fetching "my flashcards". It handles caching and network requests.
    /// Get /api/flashcards/mine?pagination[page]=...
    ///
    private func getOrFetchAllMyFlashcards() async throws -> [Flashcard] {
        // 1. If cache is fresh, try to load from it.
        if !isFlashcardsCacheStale {
            if let cachedFlashcards = cacheService.load(type: [Flashcard].self, from: allMyFlashcardsCacheKey) {
                logger.debug("✅ Returning all 'my flashcards' from cache.")
                return cachedFlashcards
            }
        }

        // 2. If cache is stale or empty, fetch all pages from the network.
        logger.debug("Cache for 'my flashcards' is stale or empty. Fetching all pages from network.")
        var allCards: [Flashcard] = []
        var currentPage = 1
        let pageSize = 100 // Standard size for fetching all data
        var hasMorePages = true

        while hasMorePages {
            let (cards, pagination) = try await fetchFlashcardsPageFromNetwork(page: currentPage, pageSize: pageSize)
            
            if !cards.isEmpty {
                allCards.append(contentsOf: cards)
            }
            
            if let pag = pagination {
                hasMorePages = pag.page < pag.pageCount
                currentPage += 1
            } else {
                hasMorePages = false
            }
        }
        
        // 3. Save the complete list to the cache and mark it as fresh.
        cacheService.save(allCards, key: allMyFlashcardsCacheKey)
        self.isFlashcardsCacheStale = false
        logger.debug("💾 Saved all 'my flashcards' to cache and marked cache as fresh.")
        
        return allCards
    }

    /*
     * fetch /api/review-flashcards
     */
    private func fetchReviewFlashcardsPage(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        logger.debug("StrapiService: Fetching review flashcards page \(page), size \(pageSize).")
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/review-flashcards") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "pagination[page]", value: "\(page)"),
            URLQueryItem(name: "pagination[pageSize]", value: "\(pageSize)"),
            URLQueryItem(name: "populate[word_definition][populate]", value: "word")
        ]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }

        let response: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)
        
        let flashcards = (response.data ?? []).map(transformStrapiCard)
        return (flashcards, response.meta?.pagination)
    }
    
    /// A simple, network-only function to fetch a single page of "my flashcards".
    private func fetchFlashcardsPageFromNetwork(page: Int, pageSize: Int) async throws -> ([Flashcard], StrapiPagination?) {
        logger.debug("StrapiService: Fetching flashcards page \(page), size \(pageSize) from network.")
        guard let url = URL(string:
            "\(Config.strapiBaseUrl)/api/flashcards/mine?pagination[page]=\(page)&pagination[pageSize]=\(pageSize)&populate[word_definition][populate]=word")
        else {
            throw URLError(.badURL)
        }
        let response: StrapiListResponse<StrapiFlashcard> = try await NetworkManager.shared.fetchDirect(from: url)

        let flashcards = (response.data ?? []).map(transformStrapiCard)
        return (flashcards, response.meta?.pagination)
    }
    
    private func invalidateAllUserCaches() {
        isFlashcardsCacheStale = true
        cacheService.delete(key: allMyFlashcardsCacheKey)
        cacheService.delete(key: reviewFlashcardsCacheKey)
        cacheService.delete(key: flashcardStatisticsCacheKey)
        cacheService.delete(key: vbSettingsCacheKey)
        logger.debug("✏️ Invalidated and cleared all user-specific caches.")
    }
    
    private func transformStrapiCard(_ strapiCard: StrapiFlashcard) -> Flashcard {
        let attributes = strapiCard.attributes
        let wordDefinitionData = attributes.wordDefinition?.data

        return Flashcard(
            id: strapiCard.id,
            wordDefinition: wordDefinitionData,
            lastReviewedAt: attributes.lastReviewedAt,
            correctStreak: attributes.correctStreak ?? 0,
            wrongStreak: attributes.wrongStreak ?? 0,
            isRemembered: attributes.isRemembered,
            reviewTire: attributes.reviewTire?.data?.attributes.tier
        )
    }
}
