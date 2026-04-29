import Combine
import Foundation

@MainActor
final class UserArticleScanFlowViewModel: ObservableObject {
    @Published private(set) var availableTags: [String] = []
    @Published private(set) var articleErrorMessage: String?

    private let articleService: ArticleService
    private let articleTagService: ArticleTagService
    private var cancellables = Set<AnyCancellable>()
    private var hasLoadedTags = false

    init(
        articleService: ArticleService? = nil,
        articleTagService: ArticleTagService? = nil
    ) {
        let services = DataServices.shared
        self.articleService = articleService ?? services.articleService
        self.articleTagService = articleTagService ?? services.articleTagService

        bindServices()
        syncAvailableTagsFromService()
        syncErrorState()
    }

    func loadIfNeeded() async {
        guard !hasLoadedTags else { return }
        hasLoadedTags = true

        await articleTagService.loadArticleTagsIfNeeded(usedOnly: true)
        syncAvailableTagsFromService()
        syncErrorState()
    }

    func saveDraftAsArticle(_ draft: ArticleDraft, sourceLabel _: String = "OCR") async throws {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = trimmedTitle.isEmpty ? "Untitled Article" : trimmedTitle
        let wordCount = draft.content.split { $0.isWhitespace || $0.isNewline }.count

        if let articleID = draft.articleId {
            _ = try await articleService.updateUserArticle(
                articleId: articleID,
                title: normalizedTitle,
                content: draft.content,
                languageCode: nil,
                wordCount: wordCount,
                progress: 0,
                lastReadAt: Date(),
                tags: draft.tags
            )
        } else {
            _ = try await articleService.createUserArticle(
                title: normalizedTitle,
                content: draft.content,
                languageCode: nil,
                wordCount: wordCount,
                progress: 0,
                lastReadAt: Date(),
                tags: draft.tags
            )
        }

        syncErrorState()
    }

    func dismissArticleError() {
        articleErrorMessage = nil
    }

    private func bindServices() {
        articleTagService.$usedArticleTags
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncAvailableTagsFromService()
                }
            }
            .store(in: &cancellables)

        articleTagService.$tagsErrorMessage
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncErrorState()
                }
            }
            .store(in: &cancellables)
    }

    private func syncAvailableTagsFromService() {
        let tags = articleTagService.currentArticleTags(usedOnly: true)
            .compactMap { $0.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let uniqueTags = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        availableTags = uniqueTags.sorted()
    }

    private func syncErrorState() {
        articleErrorMessage = articleTagService.tagsErrorMessage
    }
}
