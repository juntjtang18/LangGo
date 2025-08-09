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
            .task {
                await flashcardViewModel.loadStatistics()
                await vocabookViewModel.loadVocabookPages()
            }
            .navigationTitle("My Vocabulary Book")
            .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline) // iOS 14+
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { // works on iOS 16+
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
