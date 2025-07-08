// LangGo/VocapageView.swift
import SwiftUI
import SwiftData
import os // For logging

struct VocapageView: View {
    @Environment(\.dismiss) var dismiss // To dismiss the full screen cover
    @Environment(\.modelContext) private var modelContext // Add ModelContext for SwiftData operations

    let vocapageId: Int // The ID of the vocapage to display
    
    @State private var vocapage: Vocapage? // State to hold the fetched SwiftData Vocapage object
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageView")

    init(vocapageId: Int) {
        self.vocapageId = vocapageId
        // No @Query init here, as we will fetch and sync it ourselves.
        // This allows us to handle loading states and network errors explicitly.
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading vocapage details...")
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else if let vocapage = vocapage { // Display content when SwiftData model is loaded
                    Text(vocapage.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 20)
                    
                    if let flashcards = vocapage.flashcards, !flashcards.isEmpty {
                        List {
                            // Header Row for columns
                            HStack {
                                Text("Target Text")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Base Text")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.1))
                            .listRowInsets(EdgeInsets()) // Remove default list padding for header

                            // Iterate over the actual Flashcard model objects
                            // Sort by lastReviewedAt for consistent order
                            ForEach(flashcards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })) { card in
                                HStack {
                                    // `backContent` is the target (e.g., English word)
                                    // `frontContent` is the base (e.g., Chinese translation).
                                    Text(card.backContent) // Learning language word/sentence
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(card.frontContent) // Base language translation
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    } else {
                        Spacer()
                        Text("No flashcards in this page.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    // Fallback in case vocapage is nil and not loading/error
                    Text("Vocapage details not available.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Vocapage Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
            .task {
                await fetchAndSyncVocapageDetails()
            }
        }
    }
    
    @MainActor
    private func fetchAndSyncVocapageDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            // 1. Fetch the StrapiVocapage (network model)
            let fetchedStrapiVocapage = try await StrapiService.shared.fetchVocapageDetails(vocapageId: vocapageId)
            
            // 2. Sync the network model to the local SwiftData model
            let syncedVocapage = try await syncVocapageFromStrapi(fetchedStrapiVocapage)
            
            // 3. Assign the SwiftData model to the @State variable
            self.vocapage = syncedVocapage
            logger.info("Successfully fetched and synced vocapage details for ID: \(vocapageId)")
            
        } catch {
            self.errorMessage = error.localizedDescription
            logger.error("Failed to fetch or sync vocapage details for ID: \(vocapageId). Error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - SwiftData Syncing Logic for VocapageView
    @MainActor
    private func syncVocapageFromStrapi(_ strapiVocapage: StrapiVocapage) async throws -> Vocapage {
        var fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == strapiVocapage.id })
        fetchDescriptor.fetchLimit = 1

        let vocapageToUpdate: Vocapage
        if let existingVocapage = try modelContext.fetch(fetchDescriptor).first {
            vocapageToUpdate = existingVocapage
            vocapageToUpdate.title = strapiVocapage.attributes.title
            vocapageToUpdate.order = strapiVocapage.attributes.order ?? 0
            // vocabook relationship is set during vocabook sync, or can be nullified.
            // If this vocapage is opened directly, its vocabook might not be present,
            // which is fine unless strict consistency is required outside the vocabook hierarchy.
            logger.debug("Updating existing vocapage: \(vocapageToUpdate.title)")
        } else {
            let newVocapage = Vocapage(id: strapiVocapage.id, title: strapiVocapage.attributes.title, order: strapiVocapage.attributes.order ?? 0)
            modelContext.insert(newVocapage)
            vocapageToUpdate = newVocapage
            logger.debug("Inserting new vocapage: \(newVocapage.title)")
        }

        // Sync flashcards for this vocapage
        if let strapiFlashcards = strapiVocapage.attributes.flashcards?.data {
            var syncedFlashcards: [Flashcard] = []
            for strapiFlashcardData in strapiFlashcards {
                let syncedFlashcard = try await syncFlashcardForVocapage(strapiFlashcardData, vocapage: vocapageToUpdate)
                syncedFlashcards.append(syncedFlashcard)
            }
            vocapageToUpdate.flashcards = syncedFlashcards
            logger.debug("Synced \(syncedFlashcards.count) flashcards for vocapage '\(vocapageToUpdate.title)'.")
        } else {
            vocapageToUpdate.flashcards = []
            logger.debug("No flashcards found or populated for vocapage '\(vocapageToUpdate.title)'.")
        }
        
        try modelContext.save() // Save changes to the context
        return vocapageToUpdate
    }

    @MainActor
    @discardableResult
    private func syncFlashcardForVocapage(_ strapiFlashcardData: StrapiData<FlashcardAttributes>, vocapage: Vocapage) async throws -> Flashcard {
        let strapiFlashcard = strapiFlashcardData.attributes
        var fetchDescriptor = FetchDescriptor<Flashcard>(predicate: #Predicate { $0.id == strapiFlashcardData.id })
        fetchDescriptor.fetchLimit = 1

        let flashcardToUpdate: Flashcard
        if let existingFlashcard = try modelContext.fetch(fetchDescriptor).first {
            flashcardToUpdate = existingFlashcard
            // Update properties
            let contentComponent = strapiFlashcard.content?.first
            
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
                flashcardToUpdate.frontContent = "Unknown Content (Front)"
                flashcardToUpdate.backContent = "Unknown Content (Back)"
            }

            flashcardToUpdate.contentType = contentComponent?.componentIdentifier ?? ""
            flashcardToUpdate.rawComponentData = try? JSONEncoder().encode(contentComponent)
            flashcardToUpdate.lastReviewedAt = strapiFlashcard.lastReviewedAt
            flashcardToUpdate.correctStreak = strapiFlashcard.correctStreak ?? 0
            flashcardToUpdate.wrongStreak = strapiFlashcard.wrongStreak ?? 0
            flashcardToUpdate.isRemembered = strapiFlashcard.isRemembered
            flashcardToUpdate.vocapage = vocapage // Ensure relationship is set
            logger.debug("Updating existing flashcard: \(flashcardToUpdate.id)")
        } else {
            // Create new Flashcard
            let contentComponent = strapiFlashcard.content?.first
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
}
