
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
    
    var flashcards: [Flashcard] = []
    var totalFlashcards: Int = 0       // ← new
    var totalPages: Int = 1            // ← new

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    @MainActor
    func loadVocabookPages() async {
        isLoadingVocabooks = true
        defer { isLoadingVocabooks = false }

        do {
            // 1. Fetch setting
            let vb = try await StrapiService.shared.fetchVBSetting()
            let pageSize = vb.attributes.wordsPerPage

            // 2. Fetch first page
            let resp = try await StrapiService.shared.fetchFlashcards(page: 1, pageSize: pageSize)

            // 3. Pull out pagination meta
            guard let pag = resp.meta?.pagination else {
                totalFlashcards = 0
                totalPages = 1
                vocabooks = []
                return
            }
            totalFlashcards = pag.total
            totalPages = pag.pageCount

            // 4. Build a single Vocabook with 1…pageCount
            let book = Vocabook(id: 1, title: "All Flashcards")
            book.vocapages = (1...totalPages).map { page in
                Vocapage(id: page, title: "Page \(page)", order: page)
            }
            vocabooks = [book]

        } catch {
            logger.error("loadVocabookPages failed: \(error.localizedDescription)")
        }
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
                isRemembered: strapiFlashcard.isRemembered
                
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
