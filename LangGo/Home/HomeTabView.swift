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
                .navigationBarItems(leading: (
                    Button(action: {
                        withAnimation {
                            self.isSideMenuShowing.toggle()
                        }
                    }) {
                        Image(systemName: "line.horizontal.3")
                            .imageScale(.large)
                    }
                ))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
