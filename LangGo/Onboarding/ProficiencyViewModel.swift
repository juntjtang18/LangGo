//
//  ProficiencyViewModel.swift
//  LangGo
//
//  Created by James Tang on 2025/8/13.
//


// Onboarding/ProficiencyViewModel.swift

import SwiftUI
import os

@MainActor
class ProficiencyViewModel: ObservableObject {
    @Published var proficiencyLevels: [ProficiencyLevel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let settingsService = DataServices.shared.settingsService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "ProficiencyViewModel")

    func fetchLevels() async {
        guard proficiencyLevels.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        let locale = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"

        do {
            proficiencyLevels = try await settingsService.fetchProficiencyLevels(locale: locale)
        } catch {
            errorMessage = "Could not load proficiency levels. Please check your connection."
            logger.error("❌ fetchProficiencyLevels(locale: \(locale, privacy: .public)) failed: \(error, privacy: .public)")
        }

        isLoading = false
    }
}
