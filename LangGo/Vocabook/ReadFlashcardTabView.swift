import SwiftUI
import CoreData // Use CoreData instead of SwiftData

// The view is no longer restricted to iOS 17
struct ReadFlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // 1. Use the Core Data context from the environment
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var languageSettings: LanguageSettings
    @EnvironmentObject var appEnvironment: AppEnvironment

    var body: some View {
        NavigationStack {
            // 2. Pass the correct Core Data context to the view's initializer
            ReadFlashcardView(
                managedObjectContext: managedObjectContext,
                languageSettings: languageSettings,
                strapiService: appEnvironment.strapiService
            )
            .navigationTitle("Read Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 3. Use an explicit ToolbarItem to prevent ambiguity errors
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isSideMenuShowing.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}
