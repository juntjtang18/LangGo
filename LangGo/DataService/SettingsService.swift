//
//  SettingsService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/23.
//


// LangGo/DataService/SettingsService.swift

import Foundation
import os

class SettingsService {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "SettingsService")
    private let cacheService = CacheService.shared
    private let networkManager = NetworkManager.shared

    private let reviewTireSettingsCacheKey = "reviewTireSettings"
    private let vbSettingsCacheKey = "vbSettings"
    private let reviewTireSettingsTimestampKey = "reviewTireSettingsTimestamp"
    private let vbSettingsTimestampKey = "vbSettingsTimestamp"

    private let reviewTireSettingsTTL: TimeInterval = 86400
    private let vbSettingsTTL: TimeInterval = 86400
    
    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    func fetchReviewTireSettings() async throws -> [StrapiReviewTire] {
        if !isRefreshModeEnabled {
            let lastFetch = UserDefaults.standard.object(forKey: reviewTireSettingsTimestampKey) as? Date
            if let lastFetch = lastFetch, -lastFetch.timeIntervalSinceNow < reviewTireSettingsTTL {
                if let cached = cacheService.load(type: [StrapiReviewTire].self, from: reviewTireSettingsCacheKey) {
                    return cached
                }
            }
        }
        
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/review-tires") else { throw URLError(.badURL) }
        let response: StrapiListResponse<StrapiReviewTire> = try await networkManager.fetchDirect(from: url)
        let settings = response.data ?? []

        cacheService.save(settings, key: reviewTireSettingsCacheKey)
        UserDefaults.standard.set(Date(), forKey: reviewTireSettingsTimestampKey)
        return settings
    }

    func fetchVBSetting() async throws -> VBSetting {
        if !isRefreshModeEnabled {
            let lastFetch = UserDefaults.standard.object(forKey: vbSettingsTimestampKey) as? Date
            if let lastFetch = lastFetch, -lastFetch.timeIntervalSinceNow < vbSettingsTTL {
                if let cached = cacheService.load(type: VBSetting.self, from: vbSettingsCacheKey) {
                    return cached
                }
            }
        }

        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else { throw URLError(.badURL) }
        let response: VBSettingSingleResponse = try await networkManager.fetchDirect(from: url)
        
        cacheService.save(response.data, key: vbSettingsCacheKey)
        UserDefaults.standard.set(Date(), forKey: vbSettingsTimestampKey)
        return response.data
    }

    func updateVBSetting(wordsPerPage: Int, interval1: Double, interval2: Double, interval3: Double) async throws -> VBSetting {
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/vbsettings/mine") else { throw URLError(.badURL) }
        let payload = VBSettingUpdatePayload(data: .init(wordsPerPage: wordsPerPage, interval1: interval1, interval2: interval2, interval3: interval3))
        let response: VBSettingSingleResponse = try await networkManager.put(to: url, body: payload)
        
        cacheService.delete(key: vbSettingsCacheKey)
        return response.data
    }

    func fetchProficiencyLevels(locale: String) async throws -> [ProficiencyLevel] {
        let localizedLevels = try await fetchLevels(for: locale)
        if localizedLevels.isEmpty && locale != "en" {
            return try await fetchLevels(for: "en")
        }
        return localizedLevels
    }

    private func fetchLevels(for locale: String) async throws -> [ProficiencyLevel] {
        guard var urlComponents = URLComponents(string: "\(Config.strapiBaseUrl)/api/proficiency-levels") else { throw URLError(.badURL) }
        urlComponents.queryItems = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "sort", value: "level:asc")
        ]
        guard let url = urlComponents.url else { throw URLError(.badURL) }
        let response: StrapiListResponse<ProficiencyLevel> = try await networkManager.fetchDirect(from: url)
        return response.data ?? []
    }
}
