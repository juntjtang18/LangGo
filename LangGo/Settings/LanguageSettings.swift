import Foundation
import SwiftUI
import os

// This is the single source of truth for the app's language setting.
@MainActor
class LanguageSettings: ObservableObject {
    private let authService = DataServices.shared.authService
    private let logger = Logger(subsystem: "com.langGo.swift", category: "LanguageSettings")

    // LanguageSettings.swift
    @Published var selectedLanguageCode: String {
        didSet {
            guard selectedLanguageCode != oldValue else { return }

            // Always persist locally
            UserDefaults.standard.set(selectedLanguageCode, forKey: "selectedLanguage")

            // 🚫 Skip server update if not authenticated
            guard UserSessionManager.shared.currentUser != nil else {
                logger.debug("Skipped base language update (not authenticated).")
                return
            }

            Task {
                do {
                    try await authService.updateBaseLanguage(languageCode: selectedLanguageCode)
                    logger.info("Updated base language to \(self.selectedLanguageCode, privacy: .public).")
                } catch {
                    logger.error("Failed to update base language: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // 🔹 Now it's static: one list for the whole app
    static let availableLanguages: [Language] = {
        return generateAvailableLanguages()
    }()

    init() {
        let savedCode   = UserDefaults.standard.string(forKey: "selectedLanguage")
        let appMatch    = Bundle.main.preferredLocalizations.first  // e.g. "zh-Hans" on a Simplified Chinese device
        let defaultCode = "en"

        let initialCode = savedCode ?? appMatch ?? defaultCode
        self.selectedLanguageCode = initialCode
    }

    
    /// Generates a list of languages the app supports by reading from the project settings.
    private static func generateAvailableLanguages() -> [Language] {
        print("DEBUG: Detected localizations ->", Bundle.main.localizations)
        
        return Bundle.main.localizations
            .filter { $0 != "Base" }
            .compactMap { langCode in
                guard let languageName = Locale(identifier: "en").localizedString(forIdentifier: langCode) else {
                    return nil
                }
                return Language(id: langCode, name: languageName.capitalized)
            }
            .sorted { $0.name < $1.name }
    }
}
