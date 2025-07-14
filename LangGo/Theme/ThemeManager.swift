import SwiftUI

class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme

    let themes: [Theme]

    init() {
        // 1. To add a new theme, just add its ID string here.
        let themeIDs = [
            "OceanBreeze",
            "SunsetCoral",
            "ForestNight",
            "SoftPastel"
        ]

        // 2. Dynamically create the themes from the list of IDs.
        self.themes = themeIDs.map { AppTheme(id: $0) }

        // 3. Load the user's saved theme or default to the first one.
        let savedThemeID = UserDefaults.standard.string(forKey: "selectedThemeID")
        self.currentTheme = themes.first { $0.id == savedThemeID } ?? themes.first!
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeID")
    }
}
