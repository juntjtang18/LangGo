import Foundation

// This class holds references to services that are used throughout the app.
@MainActor // Add this line to isolate the class to the main actor
class AppEnvironment: ObservableObject {
    
    let strapiService: StrapiService
    let reviewSettingsManager: ReviewSettingsManager
    let conversationService: ConversationService
    let storyService: StoryService
    
    init(strapiService: StrapiService) {
        self.strapiService = strapiService
        // This call is now valid because both initializers are on the main actor
        self.reviewSettingsManager = ReviewSettingsManager(strapiService: strapiService)
        
        // Initialize the other services.
        self.conversationService = ConversationService()
        self.storyService = StoryService()
    }
}
