import SwiftUI
import os

@MainActor
final class ReviewSettingsManager: ObservableObject {
    @Published private(set) var settings: [String: ReviewTireAttributes] = [:]
    @Published private(set) var masteryStreak: Int = 10

    private let strapiService: StrapiService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ReviewSettingsManager")

    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }

    func loadSettings() async {
        logger.info("Loading review tire settings from server.")
        do {
            let fetchedSettings = try await strapiService.fetchReviewTireSettings()
            var temp: [String: ReviewTireAttributes] = [:]
            for setting in fetchedSettings {
                temp[setting.attributes.tier] = setting.attributes
            }
            self.settings = temp

            if let remembered = temp["remembered"] {
                self.masteryStreak = remembered.min_streak
                logger.info("Review settings loaded. Mastery streak set to: \(self.masteryStreak)")
            } else {
                logger.warning("Missing 'remembered' tier; using default mastery streak \(self.masteryStreak).")
            }
        } catch {
            logger.error("Failed to load review tire settings: \(error.localizedDescription)")
        }
    }
}
