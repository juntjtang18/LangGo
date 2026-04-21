import Foundation
import Testing
@testable import LangGo

struct CacheServiceTests {
    private struct SamplePayload: Codable, Equatable {
        let value: String
    }

    @Test
    func saveAndLoadIfValidReturnsFreshPayload() async throws {
        let cache = CacheService.shared
        let key = "test.cache.fresh.\(UUID().uuidString)"
        let tag = CacheService.CacheTag(rawValue: "test-cache-fresh")
        let payload = SamplePayload(value: "fresh")

        defer {
            cache.delete(key: key)
            cache.invalidate(tag: tag)
        }

        cache.save(payload, key: key, ttl: .seconds(60), tags: [tag])

        let loaded = cache.loadIfValid(type: SamplePayload.self, from: key)

        #expect(loaded == payload)
    }

    @Test
    func loadIfValidReturnsNilAfterExpiry() async throws {
        let cache = CacheService.shared
        let key = "test.cache.expired.\(UUID().uuidString)"
        let tag = CacheService.CacheTag(rawValue: "test-cache-expired")

        defer {
            cache.delete(key: key)
            cache.invalidate(tag: tag)
        }

        cache.save(SamplePayload(value: "expired"), key: key, ttl: .seconds(0.1), tags: [tag])
        try await Task.sleep(for: .milliseconds(250))

        let loaded = cache.loadIfValid(type: SamplePayload.self, from: key)

        #expect(loaded == nil)
    }

    @Test
    func invalidateTagRemovesTaggedEntries() async throws {
        let cache = CacheService.shared
        let tag = CacheService.CacheTag(rawValue: "test-cache-invalidate.\(UUID().uuidString)")
        let key1 = "test.cache.invalidate.1.\(UUID().uuidString)"
        let key2 = "test.cache.invalidate.2.\(UUID().uuidString)"

        defer {
            cache.delete(key: key1)
            cache.delete(key: key2)
            cache.invalidate(tag: tag)
        }

        cache.save(SamplePayload(value: "one"), key: key1, ttl: .seconds(60), tags: [tag])
        cache.save(SamplePayload(value: "two"), key: key2, ttl: .seconds(60), tags: [tag])

        cache.invalidate(tag: tag)

        let value1 = cache.loadIfValid(type: SamplePayload.self, from: key1)
        let value2 = cache.loadIfValid(type: SamplePayload.self, from: key2)

        #expect(value1 == nil)
        #expect(value2 == nil)
    }
}
