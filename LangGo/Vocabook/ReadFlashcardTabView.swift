import SwiftUI

struct ReadFlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    // REMOVED: The modelContext environment variable is gone.
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var appEnvironment: AppEnvironment

    var body: some View {
        NavigationStack {
            // MODIFIED: ReadFlashcardView is now initialized without modelContext.
            ReadFlashcardView(languageSettings: languageSettings, strapiService: appEnvironment.strapiService)
                .navigationTitle("Read Flashcards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
