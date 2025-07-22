import SwiftUI

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    @StateObject private var viewModel: StoryViewModel
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var languageSettings: LanguageSettings

    // This initializer is now updated to pass all required services
    init(isSideMenuShowing: Binding<Bool>, appEnvironment: AppEnvironment, languageSettings: LanguageSettings) {
        _isSideMenuShowing = isSideMenuShowing
        _viewModel = StateObject(wrappedValue: StoryViewModel(
            storyService: appEnvironment.storyService,
            strapiService: appEnvironment.strapiService, // PASS THE SERVICE
            languageSettings: languageSettings // PASS THE SETTINGS
        ))
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
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
