import SwiftUI

struct HomeTabView: View {
    @Binding var selectedTab: Int

    var body: some View {
        HomeView(selectedTab: $selectedTab)
    }
}
