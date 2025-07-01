import SwiftUI
import SwiftData
import os

@Observable
class FlashcardViewModel {
    var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")
    var userReviewLogs: [StrapiReviewLog] = [] // Property to hold the fetched logs

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    var totalCardCount: Int = 0
    var rememberedCount: Int = 0
    var reviewCards: [Flashcard] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // REMOVED: The network call to fetch the user has been removed.
        // The userId will be fetched directly from UserDefaults when needed.
    }

    @MainActor
    func loadStatistics() async {
        do {
            let descriptor = FetchDescriptor<Flashcard>()
            let allCards = try modelContext.fetch(descriptor)
            self.totalCardCount = allCards.count
            self.rememberedCount = allCards.filter { $0.isRemembered }.count
        } catch {
            logger.error("loadStatistics: Failed to load stats from local store: \(error.localizedDescription)")
        }
    }

    @MainActor
    func prepareReviewSession() async {
        if isRefreshModeEnabled {
            logger.info("prepareReviewSession: Refresh mode is ON. Fetching from server.")
            await fetchAndLoadReviewCardsFromServer()
        } else {
            do {
                let descriptor = FetchDescriptor<Flashcard>(sortBy: [SortDescriptor(\.lastReviewedAt, order: .forward)])
                self.reviewCards = try modelContext.fetch(descriptor)
                logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from local storage.")
            } catch {
                logger.error("prepareReviewSession: Failed to fetch cards for review: \(error.localizedDescription)")
                self.reviewCards = []
            }
        }
    }

    @MainActor
    private func fetchAndLoadReviewCardsFromServer() async {
        let urlString = "\(Config.strapiBaseUrl)/api/review-flashcards"
        guard let url = URL(string: urlString) else {
            self.reviewCards = []
            return
        }
        logger.debug("fetchAndLoadReviewCardsFromServer called: /api/review-flashcards")

        do {
            let fetchedData = try await NetworkManager.shared.fetch(from: url)
            var processedCards: [Flashcard] = []

            for strapiCard in fetchedData.data {
                do {
                    guard let component = strapiCard.attributes.content.first else { continue }

                    var frontContent: String?
                    var backContent: String?
                    var register: String?

                    switch component.componentIdentifier {
                    case "a.user-word-ref":
                        frontContent = component.userWord?.data?.attributes.baseText
                        backContent = component.userWord?.data?.attributes.word
                        register = nil
                    case "a.word-ref":
                        frontContent = component.word?.data?.attributes.baseText
                        backContent = component.word?.data?.attributes.word
                        register = component.word?.data?.attributes.register
                    case "a.user-sent-ref":
                        frontContent = component.userSentence?.data?.attributes.baseText
                        backContent = component.userSentence?.data?.attributes.targetText
                        register = nil
                    case "a.sent-ref":
                        frontContent = component.sentence?.data?.attributes.baseText
                        backContent = component.sentence?.data?.attributes.targetText
                        register = component.sentence?.data?.attributes.register
                    default:
                        logger.warning("Unrecognized component type: \(component.componentIdentifier)")
                        break
                    }

                    let finalFront = frontContent ?? "Missing Question"
                    let finalBack = backContent ?? "Missing Answer"
                    let contentType = component.componentIdentifier
                    let rawData = try? JSONEncoder().encode(component)
                    let cardId = strapiCard.id
                    var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
                    fetchDescriptor.fetchLimit = 1

                    if let cardToUpdate = try modelContext.fetch(fetchDescriptor).first {
                        cardToUpdate.frontContent = finalFront
                        cardToUpdate.backContent = finalBack
                        cardToUpdate.register = register
                        cardToUpdate.contentType = contentType
                        cardToUpdate.rawComponentData = rawData
                        cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
                        cardToUpdate.isRemembered = strapiCard.attributes.isRemembered
                        // FIXED: Use nil-coalescing operator to provide a default value for optional streaks.
                        cardToUpdate.correctStreak = strapiCard.attributes.correctStreak ?? 0
                        cardToUpdate.wrongStreak = strapiCard.attributes.wrongStreak ?? 0
                        processedCards.append(cardToUpdate)
                    } else {
                        let newCard = Flashcard(
                            id: cardId,
                            frontContent: finalFront,
                            backContent: finalBack,
                            register: register,
                            contentType: contentType,
                            rawComponentData: rawData,
                            lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                            // FIXED: Use nil-coalescing operator for streaks during initialization.
                            correctStreak: strapiCard.attributes.correctStreak ?? 0,
                            wrongStreak: strapiCard.attributes.wrongStreak ?? 0,
                            isRemembered: strapiCard.attributes.isRemembered
                        )
                        modelContext.insert(newCard)
                        processedCards.append(newCard)
                    }
                } catch {
                    logger.error("Error processing card \(strapiCard.id): \(error.localizedDescription)")
                }
            }

            try modelContext.save()
            logger.info("Successfully saved/updated \(fetchedData.data.count) cards.")

            self.reviewCards = processedCards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })
            logger.info("prepareReviewSession: Successfully loaded \(self.reviewCards.count) cards for review from server.")

        } catch {
            logger.error("fetchAndLoadReviewCardsFromServer: Failed to fetch or save data: \(error.localizedDescription)")
            self.reviewCards = []
        }
    }

    public func fetchDataFromServer(forceRefresh: Bool = false) async {
        let urlString = "\(Config.strapiBaseUrl)/api/flashcards?populate=content"
        guard let url = URL(string: urlString) else { return }

        do {
            let fetchedData = try await NetworkManager.shared.fetch(from: url)
            await MainActor.run {
                updateLocalDatabase(with: fetchedData.data)
            }
        } catch {
            logger.error("fetchDataFromServer: Failed to fetch or decode data: \(error.localizedDescription)")
        }
    }

    private func updateLocalDatabase(with strapiFlashcards: [StrapiFlashcard]) {
        logger.debug("updateLocalDatabase called.")
        for strapiCard in strapiFlashcards {
            do {
                guard let component = strapiCard.attributes.content.first else { continue }

                var frontContent: String?
                var backContent: String?
                var register: String?

                switch component.componentIdentifier {
                case "a.user-word-ref":
                    frontContent = component.userWord?.data?.attributes.baseText
                    backContent = component.userWord?.data?.attributes.word
                    register = nil
                case "a.word-ref":
                    frontContent = component.word?.data?.attributes.baseText
                    backContent = component.word?.data?.attributes.word
                    register = component.word?.data?.attributes.register
                case "a.user-sent-ref":
                    frontContent = component.userSentence?.data?.attributes.baseText
                    backContent = component.userSentence?.data?.attributes.targetText
                    register = nil
                case "a.sent-ref":
                    frontContent = component.sentence?.data?.attributes.baseText
                    backContent = component.sentence?.data?.attributes.targetText
                    register = component.sentence?.data?.attributes.register
                default:
                    logger.warning("Unrecognized component type: \(component.componentIdentifier)")
                    break
                }

                let finalFront = frontContent ?? "Missing Question"
                let finalBack = backContent ?? "Missing Answer"
                let contentType = component.componentIdentifier
                let rawData = try? JSONEncoder().encode(component)
                let cardId = strapiCard.id
                var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
                fetchDescriptor.fetchLimit = 1
                let existingCards = try modelContext.fetch(fetchDescriptor)

                if let cardToUpdate = existingCards.first {
                    cardToUpdate.frontContent = finalFront
                    cardToUpdate.backContent = finalBack
                    cardToUpdate.register = register
                    cardToUpdate.contentType = contentType
                    cardToUpdate.rawComponentData = rawData
                    cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
                    cardToUpdate.isRemembered = strapiCard.attributes.isRemembered
                    // FIXED: Use nil-coalescing operator for streaks.
                    cardToUpdate.correctStreak = strapiCard.attributes.correctStreak ?? 0
                    cardToUpdate.wrongStreak = strapiCard.attributes.wrongStreak ?? 0
                } else {
                    let newCard = Flashcard(
                        id: cardId,
                        frontContent: finalFront,
                        backContent: finalBack,
                        register: register,
                        contentType: contentType,
                        rawComponentData: rawData,
                        lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                        // FIXED: Use nil-coalescing operator for streaks.
                        correctStreak: strapiCard.attributes.correctStreak ?? 0,
                        wrongStreak: strapiCard.attributes.wrongStreak ?? 0,
                        isRemembered: strapiCard.attributes.isRemembered
                    )
                    modelContext.insert(newCard)
                }
            } catch {
                logger.error("updateLocalDatabase: Error processing card: \(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("updateLocalDatabase: Failed to save context: \(error.localizedDescription)")
        }
    }

    func markCorrect(for card: Flashcard) {
        card.isRemembered = true
        card.lastReviewedAt = .now
        card.correctStreak += 1
        card.wrongStreak = 0
        
        try? modelContext.save()
        Task {
            await createReviewLog(for: card, result: "correct")
            await loadStatistics()
        }
    }

    func markWrong(for card: Flashcard) {
        card.isRemembered = false
        card.lastReviewedAt = .now
        card.wrongStreak += 1
        card.correctStreak = 0
        
        try? modelContext.save()
        Task {
            await createReviewLog(for: card, result: "wrong")
            await loadStatistics()
        }
    }
    
    private func createReviewLog(for card: Flashcard, result: String) async {
        // FIXED: Retrieve the user ID directly from UserDefaults, where it was stored on login.
        guard let userId = UserDefaults.standard.object(forKey: "userId") as? Int else {
            logger.warning("Cannot create review log. User ID not found in UserDefaults.")
            return
        }
        
        guard let url = URL(string: "\(Config.strapiBaseUrl)/api/reviewlogs") else {
            logger.error("Invalid URL for /api/reviewlogs")
            return
        }
        
        let logData = ReviewLogData(result: result, flashcard: card.id, reviewedAt: .now, reviewLevel: "daily", user: userId)
        let requestBody = ReviewLogRequestBody(data: logData)
        
        do {
            try await NetworkManager.shared.post(to: url, body: requestBody)
            logger.info("Successfully created review log for flashcard \(card.id) for user \(userId).")
        } catch {
            logger.error("Failed to create review log for flashcard \(card.id): \(error.localizedDescription)")
        }
    }
    // Add this new function to fetch the logs
    @MainActor
    func fetchMyReviewLogs() async {
        do {
            self.userReviewLogs = try await NetworkManager.shared.fetchMyReviewLogs()
            logger.info("Successfully fetched \(self.userReviewLogs.count) review logs for the current user.")
        } catch {
            logger.error("Failed to fetch user review logs: \(error.localizedDescription)")
        }
    }
}
