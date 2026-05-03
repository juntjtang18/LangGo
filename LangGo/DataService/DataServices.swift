// LangGo/DataService/DataServices.swift

@MainActor
final class DataServices {
    static let shared = DataServices()

    let authService: AuthService
    let userSnapshotService: UserSnapshotService
    let rankService: RankService

    let flashcardService: FlashcardService
    let wordService: WordService
    let settingsService: SettingsService
    let articleTagService: ArticleTagService
    let articleService: ArticleService
    
    let storyService: StoryService
    let conversationService: ConversationService
    let reviewSettingsManager: ReviewSettingsManager

    private init() {
        self.authService = AuthService()
        self.userSnapshotService = UserSnapshotService()
        self.rankService = RankService()

        let flashcardService = FlashcardService()
        self.flashcardService = flashcardService

        self.wordService = WordService(flashcardService: self.flashcardService)
        self.settingsService = SettingsService()
        let articleTagService = ArticleTagService()
        self.articleTagService = articleTagService
        self.articleService = ArticleService(articleTagService: articleTagService)
        
        self.storyService = StoryService()
        self.conversationService = ConversationService()
        
        // This was the line with the error.
        // I am keeping strapiService as a local variable to be used here.
        let strapiService = StrapiService()
        self.reviewSettingsManager = ReviewSettingsManager(strapiService: strapiService)
    }
    func resetUserScopedRuntimeState() {
        flashcardService.resetUserScopedRuntimeState()
    }

}
