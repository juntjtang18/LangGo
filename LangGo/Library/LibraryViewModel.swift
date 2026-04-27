import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var libraryArticles: [LibraryArticle] = []
    @Published private(set) var discoverArticles = LibraryArticle.discoverMocks
    @Published private(set) var availableTags: [String] = []
    @Published private(set) var isLoadingLibrary = false
    @Published private(set) var isLoadingNextArticlePage = false
    @Published private(set) var isLoadingPreviousArticlePage = false
    @Published private(set) var articleErrorMessage: String?
    @Published private(set) var totalArticlePages = 1
    @Published var selectedFilterTags: Set<String> = []

    private let articleService: ArticleService
    private let articleTagService: ArticleTagService
    private let articlePageSize: Int
    private let maxCachedArticlePages: Int

    private var cancellables = Set<AnyCancellable>()
    private var hasLoadedLibrary = false
    private var cachedArticlePages: [Int: [LibraryArticle]] = [:]
    private var cachedArticlePageOrder: [Int] = []
    private var pendingPageLoads: [Int: ArticlePageDirection] = [:]
    private var discoverLibraryArticles: [LibraryArticle] = []

    init(
        articleService: ArticleService? = nil,
        articleTagService: ArticleTagService? = nil,
        articlePageSize: Int = 10,
        maxCachedArticlePages: Int = 3
    ) {
        let services = DataServices.shared
        self.articleService = articleService ?? services.articleService
        self.articleTagService = articleTagService ?? services.articleTagService
        self.articlePageSize = articlePageSize
        self.maxCachedArticlePages = maxCachedArticlePages

        bindServices()
        syncAvailableTagsFromService()
        syncPendingPagesFromService()
    }

    var filterTags: [String] {
        let tags = Array(NSOrderedSet(array: availableTags)) as? [String] ?? availableTags
        return tags.sorted()
    }

    var displayedLibraryArticles: [LibraryArticle] {
        guard !selectedFilterTags.isEmpty else { return libraryArticles }
        return libraryArticles.filter { article in
            selectedFilterTags.isSubset(of: Set(article.tags))
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true
        await loadLibrary()
    }

    func loadLibrary() async {
        isLoadingLibrary = true
        articleErrorMessage = nil

        defer {
            syncPendingPagesFromService()
            syncAvailableTagsFromService()
            syncErrorState()
            isLoadingLibrary = false
        }

        async let tagsTask: Void = articleTagService.loadArticleTagsIfNeeded(usedOnly: true)
        async let articlesTask: Void = articleService.loadUserArticlesPageIfNeeded(page: 1, pageSize: articlePageSize)

        _ = await (tagsTask, articlesTask)
    }

    func saveDraftAsArticle(_ draft: ArticleDraft, sourceLabel: String = "OCR") async throws {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = trimmedTitle.isEmpty ? "Untitled Article" : trimmedTitle
        let wordCount = draft.content.split { $0.isWhitespace || $0.isNewline }.count

        let savedArticle: StrapiUserArticle
        if let articleId = draft.articleId {
            savedArticle = try await articleService.updateUserArticle(
                articleId: articleId,
                title: normalizedTitle,
                content: draft.content,
                languageCode: nil,
                wordCount: wordCount,
                progress: 0,
                lastReadAt: Date(),
                tags: draft.tags
            )
        } else {
            savedArticle = try await articleService.createUserArticle(
                title: normalizedTitle,
                content: draft.content,
                languageCode: nil,
                wordCount: wordCount,
                progress: 0,
                lastReadAt: Date(),
                tags: draft.tags
            )
        }

        let existingID = libraryArticles.first(where: { $0.backendId == savedArticle.id })?.id
        upsertLocalArticle(
            makeLibraryArticle(
                from: savedArticle,
                fallbackID: existingID,
                sourceLabelOverride: sourceLabel,
                dateLabelOverride: "Just now"
            )
        )
    }

    func toggleFilterTag(_ tag: String) {
        if selectedFilterTags.contains(tag) {
            selectedFilterTags.remove(tag)
        } else {
            selectedFilterTags.insert(tag)
        }
    }

    func dismissArticleError() {
        articleErrorMessage = nil
    }

    func addDiscoverArticle(_ article: LibraryArticle) {
        guard let index = discoverArticles.firstIndex(where: { $0.id == article.id }) else { return }

        var moved = discoverArticles.remove(at: index)
        moved.progress = 0.0
        discoverLibraryArticles.removeAll { $0.id == moved.id }
        discoverLibraryArticles.insert(moved, at: 0)
        rebuildArticleWindow()
    }

    func handleArticleAppearance(_ article: LibraryArticle) async {
        guard !displayedLibraryArticles.isEmpty else { return }

        if article.id == displayedLibraryArticles.first?.id {
            await loadPreviousArticlePageIfNeeded()
        }

        if article.id == displayedLibraryArticles.last?.id {
            await loadNextArticlePageIfNeeded()
        }
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

        articleService.$userArticlePages
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncPendingPagesFromService()
                }
            }
            .store(in: &cancellables)

        articleService.$articlesErrorMessage
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
            .sorted()

        let uniqueTags = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        availableTags = uniqueTags
        selectedFilterTags = selectedFilterTags.intersection(Set(uniqueTags))
    }

    private func syncPendingPagesFromService() {
        let loadedPages = Set(
            articleService.userArticlePages.keys
                .filter { $0.pageSize == articlePageSize }
                .map(\.page)
        )
        let trackedPages = loadedPages
            .union(cachedArticlePageOrder)
            .union(pendingPageLoads.keys)

        guard !trackedPages.isEmpty else {
            rebuildArticleWindow()
            return
        }

        var resolvedTotalPages = 1
        var sawPageResponse = false

        for page in trackedPages.sorted() {
            guard let response = articleService.currentUserArticlesPage(page: page, pageSize: articlePageSize) else {
                continue
            }

            sawPageResponse = true
            resolvedTotalPages = max(resolvedTotalPages, response.meta?.pagination?.pageCount ?? 1)

            let existingArticles = cachedArticlePages[page] ?? []
            let mappedArticles = mapUserArticles(response.data ?? [], preserving: existingArticles)

            if !mappedArticles.isEmpty || cachedArticlePageOrder.contains(page) {
                cachedArticlePages[page] = mappedArticles
            } else {
                cachedArticlePages.removeValue(forKey: page)
            }

            if !cachedArticlePageOrder.contains(page), !mappedArticles.isEmpty {
                cachedArticlePageOrder.append(page)
                cachedArticlePageOrder.sort()

                if let direction = pendingPageLoads[page] ?? nil {
                    trimArticlePageWindow(for: direction)
                }
            }
        }

        if sawPageResponse {
            totalArticlePages = max(resolvedTotalPages, 1)
        }

        rebuildArticleWindow()
    }

    private func syncErrorState() {
        articleErrorMessage = articleService.articlesErrorMessage ?? articleTagService.tagsErrorMessage
    }

    private func loadNextArticlePageIfNeeded() async {
        guard !isLoadingLibrary, !isLoadingNextArticlePage else { return }
        guard let lastPage = cachedArticlePageOrder.max(), lastPage < totalArticlePages else { return }

        isLoadingNextArticlePage = true
        defer { isLoadingNextArticlePage = false }

        await loadArticlePage(lastPage + 1, direction: .next)
    }

    private func loadPreviousArticlePageIfNeeded() async {
        guard !isLoadingLibrary, !isLoadingPreviousArticlePage else { return }
        guard let firstPage = cachedArticlePageOrder.min(), firstPage > 1 else { return }

        isLoadingPreviousArticlePage = true
        defer { isLoadingPreviousArticlePage = false }

        await loadArticlePage(firstPage - 1, direction: .previous)
    }

    private func loadArticlePage(_ page: Int, direction: ArticlePageDirection) async {
        guard cachedArticlePages[page] == nil else { return }

        pendingPageLoads[page] = direction
        await articleService.loadUserArticlesPageIfNeeded(page: page, pageSize: articlePageSize)
        pendingPageLoads.removeValue(forKey: page)
        syncPendingPagesFromService()
        syncErrorState()
    }

    private func trimArticlePageWindow(for direction: ArticlePageDirection) {
        while cachedArticlePageOrder.count > maxCachedArticlePages {
            let pageToDrop: Int
            switch direction {
            case .next:
                pageToDrop = cachedArticlePageOrder.min() ?? cachedArticlePageOrder[0]
            case .previous:
                pageToDrop = cachedArticlePageOrder.max() ?? cachedArticlePageOrder[cachedArticlePageOrder.count - 1]
            }

            cachedArticlePages.removeValue(forKey: pageToDrop)
            cachedArticlePageOrder.removeAll { $0 == pageToDrop }
        }
    }

    private func rebuildArticleWindow() {
        let orderedPages = cachedArticlePageOrder.sorted()
        let backendArticles = orderedPages.flatMap { cachedArticlePages[$0] ?? [] }
        libraryArticles = discoverLibraryArticles + backendArticles
    }

    private func upsertLocalArticle(_ article: LibraryArticle) {
        if let existingIndex = libraryArticles.firstIndex(where: { $0.backendId == article.backendId }) {
            libraryArticles[existingIndex] = article

            for page in cachedArticlePages.keys {
                if let pageIndex = cachedArticlePages[page]?.firstIndex(where: { $0.backendId == article.backendId }) {
                    cachedArticlePages[page]?[pageIndex] = article
                }
            }

            if let discoverIndex = discoverLibraryArticles.firstIndex(where: { $0.backendId == article.backendId }) {
                discoverLibraryArticles[discoverIndex] = article
            }
        } else {
            if cachedArticlePages[1] != nil {
                cachedArticlePages[1]?.insert(article, at: 0)

                if let firstPageCount = cachedArticlePages[1]?.count, firstPageCount > articlePageSize {
                    cachedArticlePages[1]?.removeLast(firstPageCount - articlePageSize)
                }
            } else {
                cachedArticlePages[1] = [article]
            }

            if !cachedArticlePageOrder.contains(1) {
                cachedArticlePageOrder.insert(1, at: 0)
                cachedArticlePageOrder = Array(Set(cachedArticlePageOrder)).sorted()
            }
        }

        rebuildArticleWindow()

        let mergedTags = Array(NSOrderedSet(array: availableTags + article.tags)) as? [String] ?? (availableTags + article.tags)
        availableTags = mergedTags.sorted()
    }

    private func mapUserArticles(_ articles: [StrapiUserArticle], preserving existing: [LibraryArticle]) -> [LibraryArticle] {
        let existingPairs: [(Int, LibraryArticle)] = existing.compactMap { article in
            guard let backendId = article.backendId else { return nil }
            return (backendId, article)
        }
        let existingByBackendID = Dictionary(uniqueKeysWithValues: existingPairs)

        return articles.map { article in
            let existingArticle = existingByBackendID[article.id]
            let sourceLabelOverride = existingArticle?.sourceLabel == "My Article" ? nil : existingArticle?.sourceLabel
            let dateLabelOverride = existingArticle?.dateLabel == "Just now" ? existingArticle?.dateLabel : nil

            return makeLibraryArticle(
                from: article,
                fallbackID: existingArticle?.id,
                sourceLabelOverride: sourceLabelOverride,
                dateLabelOverride: dateLabelOverride
            )
        }
    }

    private func makeLibraryArticle(
        from article: StrapiUserArticle,
        fallbackID: UUID? = nil,
        sourceLabelOverride: String? = nil,
        dateLabelOverride: String? = nil
    ) -> LibraryArticle {
        let title = article.attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = article.attributes.content ?? ""
        let tagNames = article.attributes.articleTags?.data.compactMap {
            $0.attributes.tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty } ?? []
        let wordCount = article.attributes.wordCount ?? content.split { $0.isWhitespace || $0.isNewline }.count

        return LibraryArticle(
            id: fallbackID ?? UUID(),
            backendId: article.id,
            title: (title?.isEmpty == false ? title : "Untitled Article") ?? "Untitled Article",
            content: content,
            wordCount: wordCount,
            newWords: max(8, min(max(wordCount / 28, 0), 60)),
            progress: article.attributes.progress,
            tag: tagNames.first,
            tags: tagNames,
            dateLabel: dateLabelOverride ?? relativeDateLabel(for: article.attributes.lastReadAt),
            sourceLabel: sourceLabelOverride ?? "My Article"
        )
    }

    private func relativeDateLabel(for date: Date?) -> String {
        guard let date else { return "Saved" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private enum ArticlePageDirection {
    case previous
    case next
}
