import SwiftUI

struct VocabookTabView: View {
    @Binding var isSideMenuShowing: Bool

    @StateObject private var flashcardViewModel = FlashcardViewModel()
    @StateObject private var vocabookViewModel = VocabookViewModel()

    var body: some View {
        NavigationStack {
            VocabookView(
                flashcardViewModel: flashcardViewModel,
                vocabookViewModel: vocabookViewModel
            )

            // The title is removed to allow the custom title to be shown inside the view
            .navigationTitle("")
            // This makes the Navigation Bar background invisible
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // The toolbar button is kept, as requested
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut) { isSideMenuShowing.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}
