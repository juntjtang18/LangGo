import SwiftUI

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // 1. Get the VoiceSelectionService from the environment
    @EnvironmentObject var voiceService: VoiceSelectionService
    
    // The ViewModel is now the only state object owned by this view.
    @StateObject private var viewModel: StoryViewModel

    // 2. The initializer now accepts the voiceService to pass to the ViewModel
    init(isSideMenuShowing: Binding<Bool>, voiceService: VoiceSelectionService) {
        _isSideMenuShowing = isSideMenuShowing
        _viewModel = StateObject(wrappedValue: StoryViewModel(voiceService: voiceService))
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
