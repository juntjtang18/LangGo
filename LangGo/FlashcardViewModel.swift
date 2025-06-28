import SwiftUI
import SwiftData

@Observable
class FlashcardViewModel {
    var modelContext: ModelContext
    
    var totalCardCount: Int = 0
    var rememberedCount: Int = 0
    
    var reviewCards: [Flashcard] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFromLocalStore()
    }

    // MARK: - Data Handling

    func fetchDataFromServer(forceRefresh: Bool = false) {
        Task {
            do {
                // FIXED: The hardcoded URL is now replaced with your Config struct.
                let urlString = "\(Config.strapiBaseUrl)/api/flashcards?populate=content"
                guard let url = URL(string: urlString) else {
                    print("Error: Invalid URL string: \(urlString)")
                    return
                }
                
                let fetchedData = try await NetworkManager.shared.fetch(from: url)
                
                await MainActor.run {
                    updateLocalDatabase(with: fetchedData.data)
                    loadFromLocalStore()
                }
            } catch {
                print("Failed to fetch or update data: \(error)")
            }
        }
    }
    
    func loadFromLocalStore() {
        do {
            let descriptor = FetchDescriptor<Flashcard>()
            let allCards = try modelContext.fetch(descriptor)
            
            totalCardCount = allCards.count
            rememberedCount = allCards.filter { $0.correctTimes > $0.wrongTimes }.count
            
        } catch {
            print("Failed to load data from local store: \(error)")
        }
    }
    
    private func updateLocalDatabase(with strapiFlashcards: [StrapiFlashcard]) {
        for strapiCard in strapiFlashcards {
            guard let firstComponent = strapiCard.attributes.content.first else { continue }
            let contentText = firstComponent.text ?? firstComponent.sentence ?? "No Content"
            let contentType = firstComponent.__component.contains("word") ? "word" : "sentence"
            
            let newCard = Flashcard(
                id: strapiCard.id,
                content: contentText,
                contentType: contentType,
                correctTimes: strapiCard.attributes.correct_times,
                wrongTimes: strapiCard.attributes.wrong_times,
                lastViewedAt: strapiCard.attributes.lastview_at
            )
            modelContext.insert(newCard)
        }
        
        try? modelContext.save()
        print("Successfully updated local database.")
    }
    
    // MARK: - Review Logic
    
    func startReview() {
        let descriptor = FetchDescriptor<Flashcard>(sortBy: [SortDescriptor(\.lastViewedAt, order: .forward)])
        reviewCards = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func markCorrect(for card: Flashcard) {
        card.correctTimes += 1
        card.lastViewedAt = .now
        try? modelContext.save()
        loadFromLocalStore()
    }
    
    func markWrong(for card: Flashcard) {
        card.wrongTimes += 1
        card.lastViewedAt = .now
        try? modelContext.save()
        loadFromLocalStore()
    }
}


// A simple singleton Network Manager
class NetworkManager {
    static let shared = NetworkManager()
    private let decoder: JSONDecoder
    
    private init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        decoder.dateDecodingStrategy = .formatted(formatter)
    }
    
    func fetch(from url: URL) async throws -> StrapiResponse {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(StrapiResponse.self, from: data)
    }
}
