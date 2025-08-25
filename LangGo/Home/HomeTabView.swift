import SwiftUI

struct HomeTabView: View {
    // ADDED: This binding has been restored to fix the build error in MainView.
    @Binding var isSideMenuShowing: Bool
    
    @Binding var selectedTab: Int
    @Environment(\.theme) var theme: Theme

    var body: some View {
        NavigationView {
            HomeView(selectedTab: $selectedTab)
                // This existing logic remains unchanged.
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")     // app mark; swap for your asset if you have one
                                .foregroundColor(theme.accent)
                            Text("LangGo")
                                .font(.headline.bold())
                                .foregroundColor(theme.text)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { isSideMenuShowing.toggle() }
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .imageScale(.large)
                                .foregroundColor(theme.text)
                        }
                        .accessibilityLabel("Profile / Menu")
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
