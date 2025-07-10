import SwiftUI
import SwiftData

struct ReadFlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var appEnvironment: AppEnvironment

    var body: some View {
        NavigationStack {
            // Pass the languageSettings object and strapiService to the view's initializer.
            ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings, strapiService: appEnvironment.strapiService)
                .navigationTitle("Read Flashcards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
