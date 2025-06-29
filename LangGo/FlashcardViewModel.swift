import SwiftUI
import SwiftData
import os

@Observable
class FlashcardViewModel {
    var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.langGo.swift", category: "FlashcardViewModel")

    private var isRefreshModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isRefreshModeEnabled")
    }

    var totalCardCount: Int = 0
    var rememberedCount: Int = 0
    var reviewCards: [Flashcard] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
                    // --- START DEBUG LOGS ---
                    logger.debug("--- Processing Strapi Card ID: \(strapiCard.id) ---")
                    guard let component = strapiCard.attributes.content.first else {
                        logger.warning("Card ID \(strapiCard.id) has no content components. Skipping.")
                        continue
                    }

                    // Log the entire decoded component. This is the most important log.
                    // It will tell us if the nested relation properties are nil.
                    logger.debug("Decoded Component: \(String(describing: component))")
                    // --- END DEBUG LOGS ---

                    var frontContent: String?
                    var backContent: String?

                    // FIX: Switched to use the new 'componentIdentifier' property
                    switch component.componentIdentifier {
                    case "a.user-word-ref":
                        frontContent = component.userWord?.data?.attributes.baseText
                        backContent = component.userWord?.data?.attributes.word
                    case "a.word-ref":
                        frontContent = component.word?.data?.attributes.baseText
                        backContent = component.word?.data?.attributes.word
                    case "a.user-sent-ref":
                        frontContent = component.userSentence?.data?.attributes.baseText
                        backContent = component.userSentence?.data?.attributes.targetText
                    case "a.sent-ref":
                        frontContent = component.sentence?.data?.attributes.baseText
                        backContent = component.sentence?.data?.attributes.targetText
                    default:
                        logger.warning("Unrecognized component type: \(component.componentIdentifier)")
                        break
                    }

                    let finalFront = frontContent ?? "Missing Question"
                    let finalBack = backContent ?? "Missing Answer"
                    
                    // --- MORE DEBUG LOGS ---
                    logger.debug("Card ID \(strapiCard.id) | Front: '\(finalFront)' | Back: '\(finalBack)'")
                    // ---
                    
                    let contentType = component.componentIdentifier.contains("word") ? "word" : "sentence"
                    let rawData = try? JSONEncoder().encode(component)
                    let cardId = strapiCard.id
                    var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
                    fetchDescriptor.fetchLimit = 1

                    if let cardToUpdate = try modelContext.fetch(fetchDescriptor).first {
                        cardToUpdate.frontContent = finalFront
                        cardToUpdate.backContent = finalBack
                        cardToUpdate.contentType = contentType
                        cardToUpdate.rawComponentData = rawData
                        cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
                        cardToUpdate.isRemembered = strapiCard.attributes.isRemembered ?? cardToUpdate.isRemembered
                        processedCards.append(cardToUpdate)
                    } else {
                        let newCard = Flashcard(
                            id: cardId,
                            frontContent: finalFront,
                            backContent: finalBack,
                            contentType: contentType,
                            rawComponentData: rawData,
                            lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                            dailyStreak: strapiCard.attributes.dailyStreak ?? 0,
                            weeklyStreak: strapiCard.attributes.weeklyStreak ?? 0,
                            weeklyWrongStreak: strapiCard.attributes.weeklyWrongStreak ?? 0,
                            monthlyStreak: strapiCard.attributes.monthlyStreak ?? 0,
                            monthlyWrongStreak: strapiCard.attributes.monthlyWrongStreak ?? 0,
                            isRemembered: strapiCard.attributes.isRemembered ?? false
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

                // FIX: Switched to use the new 'componentIdentifier' property
                switch component.componentIdentifier {
                case "a.user-word-ref":
                    frontContent = component.userWord?.data?.attributes.baseText
                    backContent = component.userWord?.data?.attributes.word
                case "a.word-ref":
                    frontContent = component.word?.data?.attributes.baseText
                    backContent = component.word?.data?.attributes.word
                case "a.user-sent-ref":
                    frontContent = component.userSentence?.data?.attributes.baseText
                    backContent = component.userSentence?.data?.attributes.targetText
                case "a.sent-ref":
                    frontContent = component.sentence?.data?.attributes.baseText
                    backContent = component.sentence?.data?.attributes.targetText
                default:
                    logger.warning("Unrecognized component type: \(component.componentIdentifier)")
                    break
                }

                let finalFront = frontContent ?? "Missing Question"
                let finalBack = backContent ?? "Missing Answer"
                let contentType = component.componentIdentifier.contains("word") ? "word" : "sentence"
                let rawData = try? JSONEncoder().encode(component)

                let cardId = strapiCard.id
                var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == cardId })
                fetchDescriptor.fetchLimit = 1
                let existingCards = try modelContext.fetch(fetchDescriptor)

                if let cardToUpdate = existingCards.first {
                    cardToUpdate.frontContent = finalFront
                    cardToUpdate.backContent = finalBack
                    cardToUpdate.contentType = contentType
                    cardToUpdate.rawComponentData = rawData
                    cardToUpdate.lastReviewedAt = strapiCard.attributes.lastReviewedAt
                    cardToUpdate.isRemembered = strapiCard.attributes.isRemembered ?? cardToUpdate.isRemembered
                } else {
                    let newCard = Flashcard(
                        id: cardId,
                        frontContent: finalFront,
                        backContent: finalBack,
                        contentType: contentType,
                        rawComponentData: rawData,
                        lastReviewedAt: strapiCard.attributes.lastReviewedAt,
                        dailyStreak: strapiCard.attributes.dailyStreak ?? 0,
                        weeklyStreak: strapiCard.attributes.weeklyStreak ?? 0,
                        weeklyWrongStreak: strapiCard.attributes.weeklyWrongStreak ?? 0,
                        monthlyStreak: strapiCard.attributes.monthlyStreak ?? 0,
                        monthlyWrongStreak: strapiCard.attributes.monthlyWrongStreak ?? 0,
                        isRemembered: strapiCard.attributes.isRemembered ?? false
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
        try? modelContext.save()
        Task { await loadStatistics() }
    }

    func markWrong(for card: Flashcard) {
        card.isRemembered = false
        card.lastReviewedAt = .now
        try? modelContext.save()
        Task { await loadStatistics() }
    }
}
