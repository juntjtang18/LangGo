import SwiftUI
import KeychainAccess
// REMOVED: import SwiftData is no longer needed.

// MARK: - Main Container View

struct MainView: View {
    @Binding var authState: AuthState
    @EnvironmentObject var appEnvironment: AppEnvironment
    @EnvironmentObject var languageSettings: LanguageSettings

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
            TabView(selection: $selectedTab) {
                HomeTabView(isSideMenuShowing: $isSideMenuShowing, selectedTab: $selectedTab)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                VocabookTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Vocabulary Book", systemImage: "square.stack.3d.up.fill") }
                    .tag(1)

                ConversationTabView(isSideMenuShowing: $isSideMenuShowing, appEnvironment: appEnvironment)
                    .tabItem { Label("AI Conversation", systemImage: "message.fill") }
                    .tag(2)
                
                StoriesTabView(isSideMenuShowing: $isSideMenuShowing, appEnvironment: appEnvironment, languageSettings: languageSettings)
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


// MARK: - Placeholder Tab Views

/*
struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Translation View").navigationTitle("Translation").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}
*/

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
    // MODIFIED: The AppEnvironment is now initialized without any arguments.
    // This removes the dependency on ModelContainer and fixes all errors.
    MainView(authState: .constant(.loggedIn))
        .environmentObject(LanguageSettings())
        .environmentObject(AppEnvironment())
}
