// LangGo/VocapageView.swift
import SwiftUI
import SwiftData
import os // For logging

struct VocapageView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings

    let vocapageId: Int
    
    @State private var vocapage: Vocapage?
    @State private var isLoading: Bool = false
    @State private var showBaseText: Bool = true // New state to control base text visibility
    @State private var isShowingPracticeView: Bool = false
    @State private var errorMessage: String?
    
    private let logger = Logger(subsystem: "com.langGo.swift", category: "VocapageView")

    init(vocapageId: Int) {
        self.vocapageId = vocapageId
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
                    if let flashcards = vocapage.flashcards, !flashcards.isEmpty {
                        List {
                            ForEach(flashcards.sorted(by: { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) })) { card in
                                HStack {
                                    Text(card.backContent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if showBaseText {
                                        Text(card.frontContent)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
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
                    Text("Vocapage details not available.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("My Vocabulary Notebook")
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showBaseText.toggle()
                    }) {
                        Image(systemName: showBaseText ? "eye.slash.fill" : "eye.fill") // Changed icons
                            .accessibilityLabel(showBaseText ? "Hide Base Text" : "Show Base Text")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        // Left-aligned item (Practice Button)
                        Button(action: {
                            isShowingPracticeView = true
                        }) {
                            Label("Practice", systemImage: "play.circle.fill")
                        }
                        //.buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Spacer()
                        Button(action: {
                            isShowingPracticeView = true
                        }) {
                            Label("Practice", systemImage: "play.circle.fill")
                        }

                        // Center-aligned item (Page Number Circle)
                        //if let vocapage = vocapage {
                        //    PageNumberCircleView(pageNumber: vocapage.order)
                        //}

                        Spacer()

                        // Invisible placeholder to balance layout
                        Button(action: {}) {
                            Label("Practice", systemImage: "play.circle.fill")
                                //.opacity(0) // Invisible to keep symmetry
                        }
                        //.buttonStyle(.borderedProminent)
                        //.disabled(true)
                        Spacer()
                    }
                }
            }
            .task {
                await fetchAndSyncVocapageDetails()
            }
            .fullScreenCover(isPresented: $isShowingPracticeView) {
                ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings)
            }
        }
    }
    
    @MainActor
    private func fetchAndSyncVocapageDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedStrapiVocapage = try await StrapiService.shared.fetchVocapageDetails(vocapageId: vocapageId)
            let syncedVocapage = try await syncVocapageFromStrapi(fetchedStrapiVocapage)
            self.vocapage = syncedVocapage
            logger.info("Successfully fetched and synced vocapage details for ID: \(vocapageId)")
            
        } catch {
            self.errorMessage = error.localizedDescription
            logger.error("Failed to fetch or sync vocapage details for ID: \(vocapageId). Error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    @MainActor
    private func syncVocapageFromStrapi(_ strapiVocapage: StrapiVocapage) async throws -> Vocapage {
        var fetchDescriptor = FetchDescriptor<Vocapage>(predicate: #Predicate { $0.id == strapiVocapage.id })
        fetchDescriptor.fetchLimit = 1

        let vocapageToUpdate: Vocapage
        if let existingVocapage = try modelContext.fetch(fetchDescriptor).first {
            vocapageToUpdate = existingVocapage
            vocapageToUpdate.title = strapiVocapage.attributes.title
            vocapageToUpdate.order = strapiVocapage.attributes.order ?? 0
            logger.debug("Updating existing vocapage: \(vocapageToUpdate.title)")
        } else {
            let newVocapage = Vocapage(id: strapiVocapage.id, title: strapiVocapage.attributes.title, order: strapiVocapage.attributes.order ?? 0)
            modelContext.insert(newVocapage)
            vocapageToUpdate = newVocapage
            logger.debug("Inserting new vocapage: \(newVocapage.title)")
        }

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
        
        try modelContext.save()
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
            flashcardToUpdate.vocapage = vocapage
            logger.debug("Updating existing flashcard: \(flashcardToUpdate.id)")
        } else {
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
                vocapage: vocapage
            )
            modelContext.insert(newFlashcard)
            flashcardToUpdate = newFlashcard
            logger.debug("Inserting new flashcard: \(newFlashcard.id)")
        }
        return flashcardToUpdate
    }
}

private struct PageNumberCircleView: View {
    let pageNumber: Int
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 20, height: 20)
            Text("\(pageNumber)")
                // smaller font size for better fit
                .font(.system(size: 12))
                .foregroundColor(.blue)
        }
    }
}
//add quick preview for the view below
// now below preview takes long time to load, so we will use a static preview
struct VocapageView_Previews: PreviewProvider {
    static var previews: some View {
        VocapageView(vocapageId: 1)
    }
}
