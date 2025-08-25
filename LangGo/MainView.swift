import SwiftUI
import KeychainAccess

// MARK: - Main Container View

struct MainView: View {
    @Binding var authState: AuthState
    @State private var selectedTab = 0
    @State private var isSideMenuShowing = false
    @State private var isShowingProfileSheet = false
    @State private var isShowingSettingSheet = false
    @State private var isShowingVocabookSettingSheet = false
    @EnvironmentObject var voiceService: VoiceSelectionService

    init(authState: Binding<AuthState>) {
        _authState = authState

        // 1) Base appearance (yours)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)

        // 2) Bigger label font (works on iPhone/iPad, all layouts)
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold) // tweak size/weight here

        let item = UITabBarItemAppearance()
        item.normal.titleTextAttributes   = [.font: font]          // unselected
        item.selected.titleTextAttributes = [.font: font]          // selected
        // Optional: also control colors if you want
        // item.normal.iconColor = UIColor.secondaryLabel
        // item.normal.titleTextAttributes?[.foregroundColor] = UIColor.secondaryLabel
        // (selected color is driven by SwiftUI .tint)

        // Apply to all layout styles (stacked/inline/compactInline)
        appearance.stackedLayoutAppearance       = item
        appearance.inlineLayoutAppearance        = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeTabView(isSideMenuShowing: $isSideMenuShowing, selectedTab: $selectedTab)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                VocabookTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Vocabulary", systemImage: "square.stack.3d.up.fill") }
                    .tag(1)

                // The appEnvironment parameter is no longer passed
                ConversationTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Speaking", systemImage: "message.fill") }
                    .tag(2)
                
                // The appEnvironment parameter is no longer passed
                StoriesTabView(isSideMenuShowing: $isSideMenuShowing, voiceService: voiceService)
                    .tabItem { Label("Stories", systemImage: "book.fill") }
                    .tag(3)

                TranslationTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Translation", systemImage: "captions.bubble.fill") }
                    .tag(4)
            }
            .tint(Color.purple)
            
            if isSideMenuShowing {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { isSideMenuShowing = false }
                    }
                    .transition(.opacity)
                
                SideMenuView(
                    isShowing: $isSideMenuShowing,
                    authState: $authState,
                    isShowingProfileSheet: $isShowingProfileSheet,
                    isShowingSettingSheet: $isShowingSettingSheet,
                    isShowingVocabookSettingSheet: $isShowingVocabookSettingSheet
                )
                .frame(width: UIScreen.main.bounds.width * 0.75)
                .transition(.move(edge: .trailing))
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $isShowingProfileSheet) {
            ProfileView()
        }
        .sheet(isPresented: $isShowingSettingSheet) {
            SettingView()
        }
        .sheet(isPresented: $isShowingVocabookSettingSheet) {
            VocabookSettingView()
        }
    }
}


// MARK: - Preview
#Preview {
    // MODIFIED: The old AppEnvironment is removed.
    // We add the ReviewSettingsManager from our singleton so child views
    // that depend on it can access it in the preview.
    MainView(authState: .constant(.loggedIn))
        .environmentObject(DataServices.shared.reviewSettingsManager)
}
