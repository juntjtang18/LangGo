import SwiftUI

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // The ViewModel is now the only state object owned by this view.
    @StateObject private var viewModel: StoryViewModel

    // The initializer is now clean. It receives the languageSettings
    // state object from its parent view (MainView).
    init(isSideMenuShowing: Binding<Bool>, languageSettings: LanguageSettings) {
        _isSideMenuShowing = isSideMenuShowing
        
        // The ViewModel is initialized here, once, when the TabView is created.
        // It will get its other service dependencies from the DataServices singleton.
        _viewModel = StateObject(wrappedValue: StoryViewModel(languageSettings: languageSettings))
    }
    
    var body: some View {
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
                    // Using the direct implementation for the toolbar to prevent compiler errors.
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
                .navigationDestination(for: Story.self) { story in
                    StoryCoverView(story: story, viewModel: viewModel)
                }
        }
    }
}
