// LangGo/DataService/DataServices.swift

@MainActor
final class DataServices {
    static let shared = DataServices()

    let authService: AuthService
    let flashcardService: FlashcardService
    let wordService: WordService
    let settingsService: SettingsService
    
    let storyService: StoryService
    let conversationService: ConversationService
    let reviewSettingsManager: ReviewSettingsManager

    private init() {
        self.authService = AuthService()
        
        let flashcardService = FlashcardService()
        self.flashcardService = flashcardService

        self.wordService = WordService(flashcardService: self.flashcardService)
        self.settingsService = SettingsService()
        
        self.storyService = StoryService()
        self.conversationService = ConversationService()
        
        // This was the line with the error.
        // I am keeping strapiService as a local variable to be used here.
        let strapiService = StrapiService()
        self.reviewSettingsManager = ReviewSettingsManager(strapiService: strapiService)
    }
}
