// LangGo/VocabookTabView.swift
import SwiftUI
import SwiftData

struct VocabookTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appEnvironment: AppEnvironment
    
    // View models required by the new screen
    @State private var flashcardViewModel: FlashcardViewModel?
    @State private var vocabookViewModel: VocabookViewModel?

    var body: some View {
        NavigationStack {
            if let flashcardViewModel = flashcardViewModel, let vocabookViewModel = vocabookViewModel {
                // The new view is composed in a separate file for clarity
                VocabookView(
                    flashcardViewModel: flashcardViewModel,
                    vocabookViewModel: vocabookViewModel
                )
                .navigationTitle("My Vocabulary Book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
                .task {
                    // Load all necessary data when the view appears
                    await flashcardViewModel.loadStatistics()
                    await vocabookViewModel.loadVocabookPages()
                }
            } else {
                // Show a loading indicator while view models are being initialized
                ProgressView()
                    .onAppear {
                        if flashcardViewModel == nil {
                            flashcardViewModel = FlashcardViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                        if vocabookViewModel == nil {
                            vocabookViewModel = VocabookViewModel(modelContext: modelContext, strapiService: appEnvironment.strapiService)
                        }
                    }
            }
        }
    }
}
