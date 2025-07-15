import Foundation
import SwiftUI

// A helper struct to manage language data, making the code cleaner.
struct Language: Hashable, Identifiable {
    let id: String // The language code, e.g., "en", "ja"
    let name: String // The display name, e.g., "English"
}

// This is the single source of truth for the app's language setting.
class LanguageSettings: ObservableObject {
    @Published var selectedLanguageCode: String {
        // When the language code is changed, we save it to UserDefaults.
        didSet {
            UserDefaults.standard.set(selectedLanguageCode, forKey: "selectedLanguage")
        }
    }

    // The list of languages is generated dynamically from the project's localizations.
    let availableLanguages: [Language]

    init() {
        self.availableLanguages = Self.generateAvailableLanguages()
        
        // When the app starts, load the saved language or default to the device's language.
        let savedCode = UserDefaults.standard.string(forKey: "selectedLanguage")
        let preferredCode = Bundle.main.preferredLocalizations.first
        let defaultCode = "en"
        
        // Ensure the initial language is one that the app actually supports.
        let initialCode = savedCode ?? preferredCode ?? defaultCode
        self.selectedLanguageCode = availableLanguages.contains(where: { $0.id == initialCode }) ? initialCode : defaultCode
    }
    
    /// Generates a list of languages the app supports by reading from the project settings.
    private static func generateAvailableLanguages() -> [Language] {
        return Bundle.main.localizations
            .filter { $0 != "Base" } // Exclude the "Base" pseudo-language
            .compactMap { langCode in
                // Use the Locale API to get the display name for each language code.
                guard let languageName = Locale(identifier: "en").localizedString(forIdentifier: langCode) else {
                    return nil
                }
                return Language(id: langCode, name: languageName.capitalized)
            }
            .sorted { $0.name < $1.name } // Sort alphabetically
    }
}
