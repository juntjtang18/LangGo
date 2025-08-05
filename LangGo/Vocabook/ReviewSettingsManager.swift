import SwiftUI
import os

@MainActor
class ReviewSettingsManager: ObservableObject {
    @Published private(set) var settings: [String: ReviewTireAttributes] = [:]
    @Published private(set) var masteryStreak: Int = 10 // Default value
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ReviewSettingsManager")

    func loadSettings(strapiService: StrapiService) async {
        logger.info("Loading review tire settings from server.")
        do {
            let fetchedSettings = try await strapiService.fetchReviewTireSettings()
            var tempSettings: [String: ReviewTireAttributes] = [:]
            
            for setting in fetchedSettings {
                tempSettings[setting.attributes.tier] = setting.attributes
            }
            
            self.settings = tempSettings
            
            // Find and store the mastery streak requirement
            if let rememberedTier = tempSettings["remembered"] {
                self.masteryStreak = rememberedTier.min_streak
                logger.info("Review settings loaded. Mastery streak set to: \(self.masteryStreak)")
            } else {
                logger.warning("Could not find 'remembered' tier in settings. Using default mastery streak of \(self.masteryStreak).")
            }
        } catch {
            logger.error("Failed to load review tire settings: \(error.localizedDescription)")
        }
    }
}
