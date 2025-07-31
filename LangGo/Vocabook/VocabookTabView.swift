import SwiftUI
import CoreData // Use CoreData instead of SwiftData

struct VocabookTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // 1. Use the Core Data context from the environment
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var appEnvironment: AppEnvironment
    
    @State private var flashcardViewModel: FlashcardViewModel?
    @State private var vocabookViewModel: VocabookViewModel?

    var body: some View {
        NavigationStack {
            if let flashcardViewModel = flashcardViewModel, let vocabookViewModel = vocabookViewModel {
                VocabookView(
                    flashcardViewModel: flashcardViewModel,
                    vocabookViewModel: vocabookViewModel
                )
                .navigationTitle("My Vocabulary Book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // 2. Use an explicit ToolbarItem to fix the ambiguity error
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
                .task {
                    await flashcardViewModel.loadStatistics()
                    await vocabookViewModel.loadVocabookPages()
                }
            } else {
                ProgressView()
                    .onAppear {
                        if flashcardViewModel == nil {
                            // 3. Initialize ViewModels with the Core Data context
                            flashcardViewModel = FlashcardViewModel(
                                managedObjectContext: managedObjectContext,
                                strapiService: appEnvironment.strapiService
                            )
                        }
                        if vocabookViewModel == nil {
                            vocabookViewModel = VocabookViewModel(
                                managedObjectContext: managedObjectContext,
                                strapiService: appEnvironment.strapiService
                            )
                        }
                    }
            }
        }
    }
}
