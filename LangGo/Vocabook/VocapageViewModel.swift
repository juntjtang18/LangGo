// LangGo/Vocabook/VocapageViewModel.swift
import Foundation
import SwiftUI

@MainActor
class VocapageViewModel: ObservableObject {
    @Published var flashcards: [Flashcard] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?

    private let strapiService: StrapiService
    private let page: Int
    private let pageSize: Int

    init(strapiService: StrapiService, page: Int, pageSize: Int) {
        self.strapiService = strapiService
        self.page = page
        self.pageSize = pageSize
    }

    func fetchFlashcardsForPage() async {
        guard flashcards.isEmpty else { return } // Fetch only once
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Use the existing service method to fetch a specific page.
            let (cards, _) = try await strapiService.fetchFlashcards(page: self.page, pageSize: self.pageSize)
            self.flashcards = cards
        } catch {
            self.errorMessage = "Failed to load page content: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}