import Foundation
import os

final class CacheService {
    static let shared = CacheService()

    typealias CacheTag = CacheTagValue
    typealias CacheTTL = CacheTTLValue

    private let logger = Logger(subsystem: "com.langGo.swift", category: "CacheService")
    private let memoryStore: MemoryCacheStore
    private let diskStore: DiskCacheStore
    private let indexStore: CacheIndexStore

    init(
        memoryStore: MemoryCacheStore = MemoryCacheStore(),
        diskStore: DiskCacheStore = DiskCacheStore(),
        indexStore: CacheIndexStore = CacheIndexStore()
    ) {
        self.memoryStore = memoryStore
        self.diskStore = diskStore
        self.indexStore = indexStore
    }

    func save<T: Codable>(_ object: T, key: String) {
        saveWithPolicy(object, key: key, ttl: nil, tags: [])
    }

    func saveWithPolicy<T: Codable>(_ object: T, key: String, ttl: CacheTTL?, tags: [CacheTag]) {
        do {
            let entry = CacheEntry(
                key: key,
                createdAt: Date(),
                expiresAt: ttl.map { Date().addingTimeInterval($0.timeInterval) },
                payload: object
            )
            let data = try JSONEncoder().encode(entry)
            memoryStore.setData(data, for: key)
            try diskStore.write(data, for: key)
            indexStore.replaceTags(for: key, with: tags)
            logger.debug("💾 Successfully saved data to cache for key: \(key)")
        } catch {
            logger.error("🚨 CacheService Error: Failed to save data for key '\(key)': \(error.localizedDescription)")
        }
    }

    func load<T: Codable>(type: T.Type, from key: String) -> T? {
        load(type: type, from: key, enforceTTL: false)
    }

    func loadIfValid<T: Codable>(type: T.Type, from key: String) -> T? {
        load(type: type, from: key, enforceTTL: true)
    }

    func delete(key: String) {
        memoryStore.removeData(for: key)
        indexStore.removeKey(key)

        do {
            try diskStore.removeData(for: key)
            logger.debug("🗑️ Successfully deleted cache for key: \(key)")
        } catch {
            logger.error("🚨 CacheService Error: Failed to delete cache for key '\(key)': \(error.localizedDescription)")
        }
    }

    func invalidate(tag: CacheTag) {
        let keys = indexStore.keys(for: tag)
        guard !keys.isEmpty else { return }

        for key in keys {
            delete(key: key)
        }

        logger.debug("🧹 Invalidated \(keys.count) cache entries for tag: \(tag.rawValue)")
    }

    func invalidate(tags: [CacheTag]) {
        Set(tags).forEach { invalidate(tag: $0) }
    }

    func keys(for tag: CacheTag) -> [String] {
        indexStore.keys(for: tag)
    }

    private func load<T: Codable>(type: T.Type, from key: String, enforceTTL: Bool) -> T? {
        if let memoryData = memoryStore.data(for: key),
           let value: T = decodeEntry(from: memoryData, for: key, enforceTTL: enforceTTL) {
            logger.debug("✅ Successfully loaded data from in-memory cache for key: \(key)")
            return value
        }

        do {
            guard let diskData = try diskStore.data(for: key),
                  let value: T = decodeEntry(from: diskData, for: key, enforceTTL: enforceTTL) else {
                return nil
            }

            memoryStore.setData(diskData, for: key)
            logger.debug("✅ Successfully loaded data from disk cache for key: \(key)")
            return value
        } catch {
            logger.error("🚨 CacheService Error: Failed to load data for key '\(key)': \(error.localizedDescription)")
            delete(key: key)
            return nil
        }
    }

    private func decodeEntry<T: Codable>(from data: Data, for key: String, enforceTTL: Bool) -> T? {
        let decoder = JSONDecoder()

        do {
            let entry = try decoder.decode(CacheEntry<T>.self, from: data)
            if enforceTTL, let expiresAt = entry.expiresAt, expiresAt <= Date() {
                logger.debug("⌛ Cache expired for key: \(key)")
                delete(key: key)
                return nil
            }
            return entry.payload
        } catch {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("🚨 CacheService Error: Failed to decode entry for key '\(key)': \(error.localizedDescription)")
                delete(key: key)
                return nil
            }
        }
    }
}
