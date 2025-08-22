import SwiftUI

struct ReadFlashcardTabView: View {
    @Binding var isSideMenuShowing: Bool

    var body: some View {
        NavigationStack {
            // MODIFIED: ReadFlashcardView is now initialized without strapiService.
            // It will get the service from the DataServices singleton internally.
            ReadFlashcardView()
                .navigationTitle("Read Flashcards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Using the direct toolbar implementation to prevent potential errors.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isSideMenuShowing.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                }
        }
    }
}

