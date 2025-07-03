import SwiftUI
import KeychainAccess

// MARK: - Main Container View

struct MainView: View {
    @Binding var authState: AuthState
    
    @State private var isSideMenuShowing = false
    @State private var isShowingProfileSheet = false
    @State private var isShowingSettingSheet = false
    
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
            // Main TabView for the app's primary sections
            TabView {
                LearnTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Learn", systemImage: "leaf.fill") }

                FlashcardTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Flashcards", systemImage: "square.stack.3d.up.fill") }

                ReadFlashcardTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Read Flashcards", systemImage: "speaker.wave.2.fill") }
                
                StoriesTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Stories", systemImage: "book.fill") }

                TranslationTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Translation", systemImage: "captions.bubble.fill") }
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
                    isShowingSettingSheet: $isShowingSettingSheet
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
    }
}


// MARK: - Placeholder Tab Views (Definitions Restored)

// AITabView has been removed as requested.

struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Stories View").navigationTitle("Stories").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}
struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Translation View").navigationTitle("Translation").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}


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


// MARK: - Preview
#Preview {
    // You will need to provide a mock LanguageSettings object for the preview to work.
    MainView(authState: .constant(.loggedIn))
        .environmentObject(LanguageSettings())
}
