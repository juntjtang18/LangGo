//
//  StoriesTabView.swift
//  LangGo
//
//  Created by James Tang on 2025/7/20.
//


import SwiftUI

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    @StateObject private var viewModel: StoryViewModel
    @EnvironmentObject var appEnvironment: AppEnvironment

    // This initializer correctly accepts the appEnvironment.
    init(isSideMenuShowing: Binding<Bool>, appEnvironment: AppEnvironment) {
        _isSideMenuShowing = isSideMenuShowing
        // The ViewModel is created here, using the service from the environment object.
        _viewModel = StateObject(wrappedValue: StoryViewModel(storyService: appEnvironment.storyService))
    }
    
    var body: some View {
        NavigationStack {
            StoryListView(viewModel: viewModel)
                .navigationTitle("Stories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Search button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { /* TODO: Implement Search */ }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    // This reuses the existing menu toolbar component.
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
