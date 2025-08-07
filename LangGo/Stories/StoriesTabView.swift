import SwiftUI

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    @StateObject private var viewModel: StoryViewModel
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var languageSettings: LanguageSettings

    init(isSideMenuShowing: Binding<Bool>, appEnvironment: AppEnvironment, languageSettings: LanguageSettings) {
        _isSideMenuShowing = isSideMenuShowing
        _viewModel = StateObject(wrappedValue: StoryViewModel(
            storyService: appEnvironment.storyService,
            strapiService: appEnvironment.strapiService,
            languageSettings: languageSettings
        ))
    }
    
    var body: some View {
        // The entire tab is now wrapped in a single, persistent NavigationStack.
        NavigationStack {
            StoryListView(viewModel: viewModel)
                .navigationTitle("Stories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { /* TODO: Implement Search */ }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
                // This defines where to go when a NavigationLink passes a Story object.
                .navigationDestination(for: Story.self) { story in
                    StoryCoverView(story: story, viewModel: viewModel)
                }
        }
    }
}
