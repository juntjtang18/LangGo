import XCTest
@testable import LangGo

/// Integration tests for VBSetting endpoints in StrapiService.
/// Ensure that you have a valid JWT stored in Keychain under Config.keychainService key before running these tests.
class VBSettingServiceTests: XCTestCase {
    /// Test fetching the current user's vbsetting.
    func testFetchVBSetting() async {
        do {
            let vbSetting = try await StrapiService.shared.fetchVBSetting()
            // Basic sanity checks on returned values
            XCTAssertGreaterThan(vbSetting.attributes.wordsPerPage, 0, "wordsPerPage should be positive by default")
            XCTAssertGreaterThan(vbSetting.attributes.interval1, 0, "interval1 should be positive by default")
            XCTAssertGreaterThan(vbSetting.attributes.interval2, 0, "interval2 should be positive by default")
            XCTAssertGreaterThan(vbSetting.attributes.interval3, 0, "interval3 should be positive by default")
        } catch {
            XCTFail("fetchVBSetting threw an error: \(error)")
        }
    }

    /// Test updating the current user's vbsetting with new values.
    func testUpdateVBSetting() async {
        let newWordsPerPage = 25
        let newInterval1: Double = 1.2
        let newInterval2: Double = 2.5
        let newInterval3: Double = 3.8

        do {
            let updated = try await StrapiService.shared.updateVBSetting(
                wordsPerPage: newWordsPerPage,
                interval1: newInterval1,
                interval2: newInterval2,
                interval3: newInterval3
            )

            XCTAssertEqual(updated.attributes.wordsPerPage, newWordsPerPage, "wordsPerPage should match the updated value")
            XCTAssertEqual(updated.attributes.interval1, newInterval1, accuracy: 0.0001, "interval1 should match the updated value")
            XCTAssertEqual(updated.attributes.interval2, newInterval2, accuracy: 0.0001, "interval2 should match the updated value")
            XCTAssertEqual(updated.attributes.interval3, newInterval3, accuracy: 0.0001, "interval3 should match the updated value")
        } catch {
            XCTFail("updateVBSetting threw an error: \(error)")
        }
    }
}
