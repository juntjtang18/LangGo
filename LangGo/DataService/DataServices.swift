@MainActor
final class DataServices {
    static let shared = DataServices()

    let strapiService: StrapiService
    let storyService: StoryService
    let conversationService: ConversationService
    let reviewSettingsManager: ReviewSettingsManager

    private init() {
        // Construct leaf services first
        self.strapiService = StrapiService()
        self.storyService = StoryService()
        self.conversationService = ConversationService()

        // Inject dependencies – no reference to DataServices.shared here
        self.reviewSettingsManager = ReviewSettingsManager(strapiService: self.strapiService)
    }
}
