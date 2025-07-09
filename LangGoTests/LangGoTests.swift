//
//  LangGoTests.swift
//  LangGoTests
//
//  Created by James Tang on 2025/6/24.
//

import Testing
@testable import LangGo

struct LangGoTests {

    @Test
    func example() async throws {
        // existing example test
    }

    // MARK: –– VBSetting Service Tests ––

    @Test
    func testFetchVBSetting() async throws {
        // Fetch the current user's VBSetting
        let vbSetting = try await StrapiService.shared.fetchVBSetting()
        // Sanity assertions
        #expect(vbSetting.attributes.wordsPerPage > 0)
        #expect(vbSetting.attributes.interval1 > 0)
        #expect(vbSetting.attributes.interval2 > 0)
        #expect(vbSetting.attributes.interval3 > 0)
    }

    @Test
    func testUpdateVBSetting() async throws {
        // New values to write
        let newWordsPerPage = 25
        let newInterval1: Double = 1.2
        let newInterval2: Double = 2.5
        let newInterval3: Double = 3.8

        // Perform the update
        let updated = try await StrapiService.shared.updateVBSetting(
            wordsPerPage: newWordsPerPage,
            interval1: newInterval1,
            interval2: newInterval2,
            interval3: newInterval3
        )

        // Assert they were applied
        #expect(updated.attributes.wordsPerPage == newWordsPerPage)
        #expect(updated.attributes.interval1 == newInterval1)
        #expect(updated.attributes.interval2 == newInterval2)
        #expect(updated.attributes.interval3 == newInterval3)
    }
}
