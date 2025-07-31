import SwiftUI
import os

@MainActor
class ReviewSettingsManager: ObservableObject {
    @Published private(set) var settings: [String: ReviewTireAttributes] = [:]
    @Published private(set) var masteryStreak: Int = 10 // Default value
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ReviewSettingsManager")
    
    // 1. Add a property to hold the StrapiService
    private let strapiService: StrapiService

    // 2. Update the initializer to accept the service
    init(strapiService: StrapiService) {
        self.strapiService = strapiService
    }

    // 3. The load function no longer needs the strapiService passed in
    func load() async {
        logger.info("Loading review tire settings from server.")
        do {
            // It now uses the service that was provided during initialization
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
