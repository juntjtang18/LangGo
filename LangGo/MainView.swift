import SwiftUI
import KeychainAccess
import SwiftData

// MARK: - Main Container View

struct MainView: View {
    @Binding var authState: AuthState
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var languageSettings: LanguageSettings // ADD THIS

    // State to control the active tab
    @State private var selectedTab = 0

    @State private var isSideMenuShowing = false
    @State private var isShowingProfileSheet = false
    @State private var isShowingSettingSheet = false
    @State private var isShowingVocabookSettingSheet = false

    init(authState: Binding<AuthState>) {
        _authState = authState
        
        // Configure the appearance of the TabBar
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            // The TabView selection is now bound to our state variable
            TabView(selection: $selectedTab) {
                // The Home tab receives a binding to control the selected tab
                HomeTabView(isSideMenuShowing: $isSideMenuShowing, selectedTab: $selectedTab)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                VocabookTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Vocabulary Book", systemImage: "square.stack.3d.up.fill") }
                    .tag(1)

                ConversationTabView(isSideMenuShowing: $isSideMenuShowing, appEnvironment: appEnvironment)
                    .tabItem { Label("AI Conversation", systemImage: "message.fill") }
                    .tag(2)
                
                // --- THIS LINE IS NOW CORRECT ---
                StoriesTabView(isSideMenuShowing: $isSideMenuShowing, appEnvironment: appEnvironment, languageSettings: languageSettings)
                     .tabItem { Label("Stories", systemImage: "book.fill") }
                    .tag(3)

                TranslationTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Translation", systemImage: "captions.bubble.fill") }
                    .tag(4)
            }
            .tint(Color.purple)
            
            // Logic for showing the side menu with lazy loading.
            if isSideMenuShowing {
                // A semi-transparent background overlay
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { isSideMenuShowing = false }
                    }
                    .transition(.opacity) // Fade in/out
                
                // Conditionally add SideMenuView to the hierarchy.
                SideMenuView(
                    isShowing: $isSideMenuShowing,
                    authState: $authState,
                    isShowingProfileSheet: $isShowingProfileSheet,
                    isShowingSettingSheet: $isShowingSettingSheet,
                    isShowingVocabookSettingSheet: $isShowingVocabookSettingSheet
                )
                .frame(width: UIScreen.main.bounds.width * 0.75)
                .transition(.move(edge: .trailing)) // Slide in from the right
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


// MARK: - Placeholder Tab Views (Definitions Restored)

// AITabView has been removed as requested.


/*
struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Translation View").navigationTitle("Translation").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}
*/

/// The toolbar item containing the hamburger menu button.
struct MenuToolbar: ToolbarContent {
    @Binding var isSideMenuShowing: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                withAnimation(.easeInOut) {
                    isSideMenuShowing.toggle()
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
        }
    }
}
