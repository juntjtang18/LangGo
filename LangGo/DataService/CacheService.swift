//
//  CacheService.swift
//  LangGo
//
//  Created by James Tang on 2025/8/8.
//


import Foundation
import os

class CacheService {
    // A shared instance for easy access, following the Singleton pattern.
    static let shared = CacheService()
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.langGo.swift", category: "CacheService")

    // A private initializer to ensure no other instances are created.
    private init() {}

    /// Saves any Codable object to a file in the app's cache directory.
    /// - Parameters:
    ///   - object: The Codable object to save.
    ///   - key: A unique string to use as the filename (e.g., "allMyFlashcards").
    func save<T: Codable>(_ object: T, key: String) {
        guard let url = cacheURL(for: key) else { return }
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url)
            logger.debug("💾 Successfully saved data to cache for key: \(key)")
        } catch {
            logger.error("🚨 CacheService Error: Failed to save data for key '\(key)': \(error.localizedDescription)")
        }
    }

    /// Loads any Codable object from a file in the app's cache directory.
    /// - Parameters:
    ///   - type: The type of the object we are trying to decode.
    ///   - key: The unique filename key for the data (e.g., "allMyFlashcards").
    /// - Returns: The decoded object, or nil if it doesn't exist or fails to decode.
    func load<T: Codable>(type: T.Type, from key: String) -> T? {
        guard let url = cacheURL(for: key), fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONDecoder().decode(T.self, from: data)
            logger.debug("✅ Successfully loaded data from cache for key: \(key)")
            return object
        } catch {
            logger.error("🚨 CacheService Error: Failed to load or decode data for key '\(key)': \(error.localizedDescription)")
            // If decoding fails, the cache is corrupt or outdated, so we should remove it.
            delete(key: key)
            return nil
        }
    }
    
    /// Deletes a specific cache file.
    /// - Parameter key: The unique filename key to delete.
    func delete(key: String) {
        guard let url = cacheURL(for: key), fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            logger.debug("🗑️ Successfully deleted cache for key: \(key)")
        } catch {
            logger.error("🚨 CacheService Error: Failed to delete cache for key '\(key)': \(error.localizedDescription)")
        }
    }

    // A private helper to construct the full file URL for a given key.
    private func cacheURL(for key: String) -> URL? {
        // Use a consistent file extension
        let fileName = "\(key).json"
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }
}
