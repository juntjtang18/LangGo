// LangGo/HomeTabView.swift
import SwiftUI

// MARK: - Home Tab Container
struct HomeTabView: View {
    @Binding var isSideMenuShowing: Bool
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            // HomeView no longer requires ViewModels, simplifying the container.
            HomeView(selectedTab: $selectedTab)
                // The navigation title is removed to better match the mockup.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The menu toolbar is kept for consistency with other app tabs.
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
