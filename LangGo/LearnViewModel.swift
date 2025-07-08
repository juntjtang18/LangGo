// LangGo/LearnViewModel.swift
import Foundation
import SwiftData
import os

// MARK: - SwiftData Models (Moved from separate files)
// These models are now defined within the same file as LearnViewModel
// to reduce file count, but remain top-level @Model classes as required by SwiftData.

@Model
final class Vocabook {
    @Attribute(.unique) var id: Int
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \Vocapage.vocabook)
    var vocapages: [Vocapage]? // One-to-many relationship with Vocapage

    init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

@Model
final class Vocapage {
    @Attribute(.unique) var id: Int
    var title: String
    var order: Int
    @Relationship(deleteRule: .nullify, inverse: \Flashcard.vocapage)
    var flashcards: [Flashcard]? // One-to-many relationship with Flashcard
    var vocabook: Vocabook? // Many-to-one relationship with Vocabook

    init(id: Int, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }

    // Helper to calculate progress based on remembered flashcards
    var progress: Double {
        guard let cards = flashcards, !cards.isEmpty else { return 0.0 }
        let rememberedCount = cards.filter { $0.isRemembered || $0.correctStreak >= 11 }.count
        return Double(rememberedCount) / Double(cards.count)
    }
}


// MARK: - LearnViewModel

@Observable
class LearnViewModel {
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LearnViewModel")
    private var modelContext: ModelContext

    var vocabooks: [Vocabook] = []
    var isLoadingVocabooks = false
    var expandedVocabooks: Set<Int> = [] // To keep track of expanded vocabooks

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @MainActor
    func fetchAndSyncVocabooks() async {
        isLoadingVocabooks = true
        do {
            logger.info("Fetching vocabooks from Strapi.")
            // response is now [StrapiVocabook] directly due to fetchAllPages
            let response = try await StrapiService.shared.fetchUserVocabooks()
            
            var syncedVocabooks: [Vocabook] = []
            for strapiVocabook in response {
                let syncedVocabook = try await syncVocabook(strapiVocabook)
                syncedVocabooks.append(syncedVocabook)
            }
            try modelContext.save()
            self.vocabooks = syncedVocabooks.sorted { $0.title < $1.title } // Sort by title
            logger.info("Successfully fetched and synced \(self.vocabooks.count) vocabooks.")
        } catch {
            logger.error("Failed to fetch and sync vocabooks: \(error.localizedDescription)")
            // Fallback to local data if server fetch fails
            await fetchVocabooksLocally()
        }
        isLoadingVocabooks = false
    }

    @MainActor
    private func fetchVocabooksLocally() async {
        logger.info("Fetching vocabooks from local SwiftData store.")
        do {
            let descriptor = FetchDescriptor<Vocabook>(sortBy: [SortDescriptor(\.title)])
            self.vocabooks = try modelContext.fetch(descriptor)
            logger.info("Successfully loaded \(self.vocabooks.count) vocabooks from local storage.")
        } catch {
            logger.error("Failed to fetch vocabooks locally: \(error.localizedDescription)")
            self.vocabooks = []
        }
    }

    @MainActor
    private func syncVocabook(_ strapiVocabook: StrapiVocabook) async throws -> Vocabook {
        var fetchDescriptor = FetchDescriptor<Vocabook>(predicate: #Predicate { $0.id == strapiVocabook.id })
        fetchDescriptor.fetchLimit = 1

        let vocabookToUpdate: Vocabook
        if let existingVocabook = try modelContext.fetch(fetchDescriptor).first {
            vocabookToUpdate = existingVocabook
            vocabookToUpdate.title = strapiVocabook.attributes.title
            logger.debug("Updating existing vocabook: \(vocabookToUpdate.title)")
        } else {
            let newVocabook = Vocabook(id: strapiVocabook.id, title: strapiVocabook.attributes.title)
            modelContext.insert(newVocabook)
            vocabookToUpdate = newVocabook
            logger.debug("Inserting new vocabook: \(vocabookToUpdate.title)")
        }

        // Sync vocapages for this vocabook
        if let strapiVocapages = strapiVocabook.attributes.vocapages?.data {
            var syncedVocapages: [Vocapage] = []
            for strapiVocapageData in strapiVocapages {
                let syncedVocapage = try await syncVocapage(strapiVocapageData, vocabook: vocabookToUpdate)
                syncedVocapages.append(syncedVocapage)
            }
            vocabookToUpdate.vocapages = syncedVocapages.sorted { ($0.order) < ($1.order) } // Sort by order
            logger.debug("Synced \(syncedVocapages.count) vocapages for vocabook '\(vocabookToUpdate.title)'.")
        } else {
            vocabookToUpdate.vocapages = []
            logger.debug("No vocapages found or populated for vocabook '\(vocabookToUpdate.title)'.")
        }
        
        return vocabookToUpdate
    }

    @MainActor
    private func syncVocapage(_ strapiVocapageData: StrapiData<VocapageAttributes>, vocabook: Vocabook) async throws -> Vocapage {
        let strapiVocapage = strapiVocapageData.attributes
        var fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == strapiVocapageData.id })
        fetchDescriptor.fetchLimit = 1

        let vocapageToUpdate: Vocapage
        if let existingVocapage = try modelContext.fetch(fetchDescriptor).first {
            vocapageToUpdate = existingVocapage
            vocapageToUpdate.title = strapiVocapage.title
            vocapageToUpdate.order = strapiVocapage.order ?? 0
            vocapageToUpdate.vocabook = vocabook
            logger.debug("Updating existing vocapage: \(vocapageToUpdate.title)")
        } else {
            let newVocapage = Vocapage(id: strapiVocapageData.id, title: strapiVocapage.title, order: strapiVocapage.order ?? 0)
            newVocapage.vocabook = vocabook
            modelContext.insert(newVocapage)
            vocapageToUpdate = newVocapage
            logger.debug("Inserting new vocapage: \(newVocapage.title)")
        }

        // Sync flashcards for this vocapage (only if populated)
        if let strapiFlashcards = strapiVocapage.flashcards?.data {
            var syncedFlashcards: [Flashcard] = []
            for strapiFlashcardData in strapiFlashcards {
                let syncedFlashcard = try await syncFlashcard(strapiFlashcardData, vocapage: vocapageToUpdate)
                syncedFlashcards.append(syncedFlashcard)
            }
            vocapageToUpdate.flashcards = syncedFlashcards
            logger.debug("Synced \(syncedFlashcards.count) flashcards for vocapage '\(vocapageToUpdate.title)'.")
        } else {
            vocapageToUpdate.flashcards = []
            logger.debug("No flashcards populated for vocapage '\(vocapageToUpdate.title)'.")
        }
        
        return vocapageToUpdate
    }

    @MainActor
    @discardableResult
    private func syncFlashcard(_ strapiFlashcardData: StrapiData<FlashcardAttributes>, vocapage: Vocapage) async throws -> Flashcard {
        let strapiFlashcard = strapiFlashcardData.attributes
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == strapiFlashcardData.id })
        fetchDescriptor.fetchLimit = 1

        let flashcardToUpdate: Flashcard
        if let existingFlashcard = try modelContext.fetch(fetchDescriptor).first {
            flashcardToUpdate = existingFlashcard
            // Note: Updated logic to safely access content based on componentIdentifier
            let contentComponent = strapiFlashcard.content?.first // Access 'content' as optional
            
            switch contentComponent?.componentIdentifier {
            case "a.user-word-ref":
                flashcardToUpdate.frontContent = contentComponent?.userWord?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.userWord?.data?.attributes.targetText ?? "Missing Answer"
            case "a.word-ref":
                flashcardToUpdate.frontContent = contentComponent?.word?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.word?.data?.attributes.word ?? "Missing Answer"
                flashcardToUpdate.register = contentComponent?.word?.data?.attributes.register
            case "a.user-sent-ref":
                flashcardToUpdate.frontContent = contentComponent?.userSentence?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.userSentence?.data?.attributes.targetText ?? "Missing Answer"
            case "a.sent-ref":
                flashcardToUpdate.frontContent = contentComponent?.sentence?.data?.attributes.baseText ?? "Missing Question"
                flashcardToUpdate.backContent = contentComponent?.sentence?.data?.attributes.targetText ?? "Missing Answer"
                flashcardToUpdate.register = contentComponent?.sentence?.data?.attributes.register
            default:
                // Fallback for unknown types or missing content component entirely
                flashcardToUpdate.frontContent = "Unknown Content (Front)"
                flashcardToUpdate.backContent = "Unknown Content (Back)"
            }

            flashcardToUpdate.contentType = contentComponent?.componentIdentifier ?? ""
            flashcardToUpdate.rawComponentData = try? JSONEncoder().encode(contentComponent)
            flashcardToUpdate.lastReviewedAt = strapiFlashcard.lastReviewedAt
            flashcardToUpdate.correctStreak = strapiFlashcard.correctStreak ?? 0
            flashcardToUpdate.wrongStreak = strapiFlashcard.wrongStreak ?? 0
            flashcardToUpdate.isRemembered = strapiFlashcard.isRemembered
            flashcardToUpdate.vocapage = vocapage // Set the relationship
            logger.debug("Updating existing flashcard: \(flashcardToUpdate.id)")
        } else {
            let contentComponent = strapiFlashcard.content?.first // Access 'content' as optional
            var front: String = "Missing Question"
            var back: String = "Missing Answer"
            var reg: String? = nil
            let type: String = contentComponent?.componentIdentifier ?? ""
            let rawData: Data? = try? JSONEncoder().encode(contentComponent)

            switch contentComponent?.componentIdentifier {
            case "a.user-word-ref":
                front = contentComponent?.userWord?.data?.attributes.baseText ?? front
                back = contentComponent?.userWord?.data?.attributes.targetText ?? back
            case "a.word-ref":
                front = contentComponent?.word?.data?.attributes.baseText ?? front
                back = contentComponent?.word?.data?.attributes.word ?? back
                reg = contentComponent?.word?.data?.attributes.register ?? reg
            case "a.user-sent-ref":
                front = contentComponent?.userSentence?.data?.attributes.baseText ?? front
                back = contentComponent?.userSentence?.data?.attributes.targetText ?? back
            case "a.sent-ref":
                front = contentComponent?.sentence?.data?.attributes.baseText ?? front
                back = contentComponent?.sentence?.data?.attributes.targetText ?? back
                reg = contentComponent?.sentence?.data?.attributes.register ?? reg
            default:
                // Fallback for unknown types or missing content component entirely
                front = "Unknown Content (Front)"
                back = "Unknown Content (Back)"
            }

            let newFlashcard = Flashcard(
                id: strapiFlashcardData.id,
                frontContent: front,
                backContent: back,
                register: reg,
                contentType: type,
                rawComponentData: rawData,
                lastReviewedAt: strapiFlashcard.lastReviewedAt,
                correctStreak: strapiFlashcard.correctStreak ?? 0,
                wrongStreak: strapiFlashcard.wrongStreak ?? 0,
                isRemembered: strapiFlashcard.isRemembered,
                vocapage: vocapage // Set the relationship
            )
            modelContext.insert(newFlashcard)
            flashcardToUpdate = newFlashcard
            logger.debug("Inserting new flashcard: \(newFlashcard.id)")
        }
        return flashcardToUpdate
    }

    func toggleVocabookExpansion(vocabookId: Int) {
        if expandedVocabooks.contains(vocabookId) {
            expandedVocabooks.remove(vocabookId)
        } else {
            expandedVocabooks.insert(vocabookId)
        }
    }
}
