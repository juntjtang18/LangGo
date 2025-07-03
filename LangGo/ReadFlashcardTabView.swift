import SwiftUI
import SwiftData

struct ReadFlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var languageSettings: LanguageSettings

    var body: some View {
        NavigationStack {
            // Pass the languageSettings object to the view's initializer.
            ReadFlashcardView(modelContext: modelContext, languageSettings: languageSettings)
                .navigationTitle("Read Flashcards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
