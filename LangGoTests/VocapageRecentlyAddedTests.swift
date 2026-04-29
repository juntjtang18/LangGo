import Foundation
import Testing
@testable import LangGo

// MARK: - Shared helpers

private func makeFlashcard(id: Int, createdAt: Date? = nil) -> Flashcard {
    Flashcard(
        id: id,
        createdAt: createdAt ?? Date(),
        wordDefinition: nil,
        lastReviewedAt: nil,
        correctStreak: 0,
        wrongStreak: 0,
        isRemembered: false,
        reviewTire: nil
    )
}

private func makeVBSetting(wordsPerPage: Int) -> VBSetting {
    VBSetting(
        id: 1,
        attributes: VBSettingAttributes(wordsPerPage: wordsPerPage, interval1: 1, interval2: 3, interval3: 7)
    )
}

// MARK: - 1. Cache key format
//
// These tests are pure — no side effects, no shared state.
// They guard against key renames that would silently break cache routing.

struct FlashcardCacheKeyFormatTests {

    @Test
    func recentFlashcardsKeyEmbedssLimit() {
        #expect(FlashcardCache.recentFlashcardsKey(limit: 5)  == "recentFlashcards.limit.5")
        #expect(FlashcardCache.recentFlashcardsKey(limit: 20) == "recentFlashcards.limit.20")
    }

    @Test
    func allMyFlashcardsKeyIsStable() {
        #expect(FlashcardCache.allMyFlashcardsKey() == "allMyFlashcards")
    }

    @Test
    func tierFlashcardsKeyEmbedsTier() {
        #expect(FlashcardCache.tierFlashcardsKey(reviewTier: "new")     == "allMyFlashcards.tier.new")
        #expect(FlashcardCache.tierFlashcardsKey(reviewTier: "monthly") == "allMyFlashcards.tier.monthly")
    }

    @Test
    func recentKeyAndAllKeyAreDistinct() {
        #expect(FlashcardCache.recentFlashcardsKey(limit: 5) != FlashcardCache.allMyFlashcardsKey())
    }

    @Test
    func differentRecentLimitsDifferentKeys() {
        #expect(FlashcardCache.recentFlashcardsKey(limit: 5) != FlashcardCache.recentFlashcardsKey(limit: 10))
    }
}

// MARK: - 2. FlashcardService routing
//
// Seeds CacheService.shared with disjoint ID sets for each data source,
// then asserts that fetchFlashcards routes to the right set based on recentlyAddedLimit / reviewTier.
//
// .serialized prevents the tests within this suite from running concurrently and
// stomping each other's shared-cache writes.  IDs 1-10 / 101-103 / 201-204 are
// deliberately far apart so a cross-path read would produce a clearly wrong result.

@Suite(.serialized)
struct FlashcardServiceRoutingTests {

    // Unique limit avoids collisions with other suites that also use the shared cache.
    private let testRecentLimit = 73

    private let allWordsCards = (1...10).map  { makeFlashcard(id: $0) }
    private let recentCards   = (101...103).map { makeFlashcard(id: $0) }
    private let newTierCards  = (201...204).map { makeFlashcard(id: $0) }

    private func seedCaches() {
        FlashcardCache.storeAllMyFlashcards(allWordsCards)
        FlashcardCache.storeRecentFlashcards(recentCards, limit: testRecentLimit)
        FlashcardCache.storeTierFlashcards(newTierCards, reviewTier: "new")
    }

    private func clearCaches() {
        CacheService.shared.delete(key: FlashcardCache.allMyFlashcardsKey())
        CacheService.shared.delete(key: FlashcardCache.recentFlashcardsKey(limit: testRecentLimit))
        CacheService.shared.delete(key: FlashcardCache.tierFlashcardsKey(reviewTier: "new"))
    }

    // recentlyAddedLimit > 0  →  returns the recently-added cache slot
    @Test
    func recentlyAddedLimitRoutesToRecentCache() async throws {
        seedCaches()
        defer { clearCaches() }

        let (cards, _) = try await FlashcardService().fetchFlashcards(
            page: 1, pageSize: 100, recentlyAddedLimit: testRecentLimit
        )
        #expect(cards.map(\.id).sorted() == recentCards.map(\.id).sorted())
    }

    // recentlyAddedLimit == 0  →  returns the all-my-flashcards cache slot
    @Test
    func zeroLimitRoutesToAllMyFlashcardsCache() async throws {
        seedCaches()
        defer { clearCaches() }

        let (cards, _) = try await FlashcardService().fetchFlashcards(
            page: 1, pageSize: 100, recentlyAddedLimit: 0
        )
        #expect(cards.map(\.id).sorted() == allWordsCards.map(\.id).sorted())
    }

    // reviewTier != nil with zero limit  →  returns the tier cache slot (not disrupted by refactor)
    @Test
    func reviewTierRoutesToTierCache() async throws {
        seedCaches()
        defer { clearCaches() }

        let (cards, _) = try await FlashcardService().fetchFlashcards(
            page: 1, pageSize: 100, reviewTier: "new", recentlyAddedLimit: 0
        )
        #expect(cards.map(\.id).sorted() == newTierCards.map(\.id).sorted())
    }

    // Result for recentlyAddedLimit > 0 must not contain any all-words card IDs.
    @Test
    func recentlyAddedResultDoesNotContainAllWordsIds() async throws {
        seedCaches()
        defer { clearCaches() }

        let (cards, _) = try await FlashcardService().fetchFlashcards(
            page: 1, pageSize: 100, recentlyAddedLimit: testRecentLimit
        )
        let returnedIds = Set(cards.map(\.id))
        let allWordIds  = Set(allWordsCards.map(\.id))
        #expect(returnedIds.isDisjoint(with: allWordIds))
    }

    // 7 recently-added cards with pageSize 5  →  page 1 = 5 cards, page 2 = 2 cards, no overlap.
    @Test
    func recentlyAddedPaginatesIntoCorrectPages() async throws {
        let limit    = 74  // distinct from testRecentLimit
        let allCards = (501...507).map { makeFlashcard(id: $0) }
        FlashcardCache.storeRecentFlashcards(allCards, limit: limit)
        defer { CacheService.shared.delete(key: FlashcardCache.recentFlashcardsKey(limit: limit)) }

        let pageSize = 5
        let service  = FlashcardService()

        let (page1, pagination1) = try await service.fetchFlashcards(
            page: 1, pageSize: pageSize, recentlyAddedLimit: limit
        )
        let (page2, pagination2) = try await service.fetchFlashcards(
            page: 2, pageSize: pageSize, recentlyAddedLimit: limit
        )

        #expect(page1.count == 5)
        #expect(page2.count == 2)
        #expect(pagination1?.total == 7)
        #expect(pagination2?.pageCount == 2)
        #expect(Set(page1.map(\.id)).isDisjoint(with: Set(page2.map(\.id))))
    }
}

// MARK: - 3. VocapageLoader cache slot isolation
//
// Loads pages via VocapageLoader (which calls FlashcardService + SettingsService internally)
// with different recentlyAddedLimit values and verifies the in-memory page dictionaries
// are keyed separately — meaning a page loaded for limit=83 cannot be returned by
// a page(recentlyAddedLimit:0) query, and vice-versa.
//
// Seeding "vbSettings" + "vbSettingsTimestamp" bypasses the SettingsService network call.

@Suite(.serialized)
struct VocapageLoaderCacheIsolationTests {

    private let recentLimit = 83                                      // distinct from service-routing suite
    private let recentCards = (301...305).map { makeFlashcard(id: $0) } // 5 cards
    private let allCards    = (401...420).map { makeFlashcard(id: $0) } // 20 cards

    private func seedSettings(wordsPerPage: Int = 10) {
        CacheService.shared.save(makeVBSetting(wordsPerPage: wordsPerPage), key: "vbSettings")
        UserDefaults.standard.set(Date(), forKey: "vbSettingsTimestamp")
    }

    private func clearSettings() {
        CacheService.shared.delete(key: "vbSettings")
        UserDefaults.standard.removeObject(forKey: "vbSettingsTimestamp")
    }

    private func seedFlashcardCaches() {
        FlashcardCache.storeRecentFlashcards(recentCards, limit: recentLimit)
        FlashcardCache.storeAllMyFlashcards(allCards)
    }

    private func clearFlashcardCaches() {
        CacheService.shared.delete(key: FlashcardCache.recentFlashcardsKey(limit: recentLimit))
        CacheService.shared.delete(key: FlashcardCache.allMyFlashcardsKey())
    }

    // A page loaded with recentlyAddedLimit > 0 must NOT be returned
    // when the caller queries with recentlyAddedLimit == 0.
    @Test @MainActor
    func pageForRecentlyAddedLimitIsInvisibleToZeroLimitAccessor() async throws {
        seedSettings()
        seedFlashcardCaches()
        defer { clearSettings(); clearFlashcardCaches() }

        let loader = VocapageLoader()
        await loader.loadPage(withId: 1, dueWordsOnly: false, reviewTier: nil, recentlyAddedLimit: recentLimit)

        let recentPage = loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: recentLimit)
        let allPage    = loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: 0)

        #expect(recentPage != nil, "Should find the page loaded with recentlyAddedLimit")
        #expect(allPage == nil,    "Zero-limit accessor must not see a recentlyAddedLimit page")
    }

    // A page loaded with recentlyAddedLimit == 0 must NOT be returned
    // when the caller queries with recentlyAddedLimit > 0.
    @Test @MainActor
    func pageForZeroLimitIsInvisibleToRecentlyAddedAccessor() async throws {
        seedSettings()
        seedFlashcardCaches()
        defer { clearSettings(); clearFlashcardCaches() }

        let loader = VocapageLoader()
        await loader.loadPage(withId: 1, dueWordsOnly: false, reviewTier: nil, recentlyAddedLimit: 0)

        let allPage    = loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: 0)
        let recentPage = loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: recentLimit)

        #expect(allPage != nil,    "Should find the page loaded with zero limit")
        #expect(recentPage == nil, "Non-zero-limit accessor must not see a zero-limit page")
    }

    // A recentlyAddedLimit page must contain exactly the recently-added cards, not the all-words cards.
    @Test @MainActor
    func recentlyAddedPageContainsOnlyRecentCards() async throws {
        seedSettings(wordsPerPage: 20)
        seedFlashcardCaches()
        defer { clearSettings(); clearFlashcardCaches() }

        let loader = VocapageLoader()
        await loader.loadPage(withId: 1, dueWordsOnly: false, reviewTier: nil, recentlyAddedLimit: recentLimit)

        let page      = loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: recentLimit)
        let loadedIds = Set(page?.flashcards?.map(\.id) ?? [])
        let expectedIds = Set(recentCards.map(\.id))

        #expect(!loadedIds.isEmpty)
        #expect(loadedIds == expectedIds)
        #expect(loadedIds.isDisjoint(with: Set(allCards.map(\.id))))
    }

    // Two different recentlyAddedLimit values must occupy separate cache slots
    // even when loaded into the same loader instance.
    @Test @MainActor
    func differentLimitsOccupySeparateCacheSlots() async throws {
        let limit5  = 85
        let limit10 = 86
        let cards5  = (601...605).map { makeFlashcard(id: $0) }
        let cards10 = (701...710).map { makeFlashcard(id: $0) }

        seedSettings(wordsPerPage: 20)
        FlashcardCache.storeRecentFlashcards(cards5,  limit: limit5)
        FlashcardCache.storeRecentFlashcards(cards10, limit: limit10)
        defer {
            clearSettings()
            CacheService.shared.delete(key: FlashcardCache.recentFlashcardsKey(limit: limit5))
            CacheService.shared.delete(key: FlashcardCache.recentFlashcardsKey(limit: limit10))
        }

        let loader = VocapageLoader()
        await loader.loadPage(withId: 1, dueWordsOnly: false, reviewTier: nil, recentlyAddedLimit: limit5)
        await loader.loadPage(withId: 1, dueWordsOnly: false, reviewTier: nil, recentlyAddedLimit: limit10)

        let ids5  = Set(loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: limit5)?.flashcards?.map(\.id) ?? [])
        let ids10 = Set(loader.page(id: 1, dueOnly: false, reviewTier: nil, recentlyAddedLimit: limit10)?.flashcards?.map(\.id) ?? [])

        #expect(ids5  == Set(cards5.map(\.id)))
        #expect(ids10 == Set(cards10.map(\.id)))
        #expect(ids5.isDisjoint(with: ids10))
    }
}
