//
//  ProficiencyViewModel.swift
//  LangGo
//
//  Created by James Tang on 2025/8/13.
//


// Onboarding/ProficiencyViewModel.swift

import SwiftUI

@MainActor
class ProficiencyViewModel: ObservableObject {
    @Published var proficiencyLevels: [ProficiencyLevel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let settingsService = DataServices.shared.settingsService
    
    func fetchLevels() async {
        // Avoid refetching if data is already loaded.
        guard proficiencyLevels.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Get the user's selected language from UserDefaults.
        let locale = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        
        do {
            proficiencyLevels = try await settingsService.fetchProficiencyLevels(locale: locale)
        } catch {
            errorMessage = "Could not load proficiency levels. Please check your connection."
            print("Error fetching proficiency levels: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}
