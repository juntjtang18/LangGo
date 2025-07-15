// LangGo/VocabookTabView.swift
import SwiftUI
import SwiftData

struct VocabookTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appEnvironment: AppEnvironment
    
    // View models required by the new screen
    @State private var flashcardViewModel: FlashcardViewModel?
    @State private var learnViewModel: LearnViewModel?

    var body: some View {
        NavigationStack {
            if let flashcardViewModel = flashcardViewModel, let learnViewModel = learnViewModel {
                // The new view is composed in a separate file for clarity
                MyVocabookView(
                    flashcardViewModel: flashcardViewModel,
                    learnViewModel: learnViewModel
                )
                .navigationTitle("My Vocabulary Book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
                .task {
                    // Load all necessary data when the view appears
                    await flashcardViewModel.loadStatistics()
                    await learnViewModel.loadVocabookPages()
                }
            } else {
                // Show a loading indicator while view models are being initialized
                ProgressView()
                    .onAppear {
                        if flashcardViewModel == nil {
                            flashcardViewModel = FlashcardViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                        if learnViewModel == nil {
                            learnViewModel = LearnViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                    }
            }
        }
    }
}
