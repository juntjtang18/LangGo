import SwiftUI
import KeychainAccess

// MARK: - Main Container View

struct MainView: View {
    // 1. The state is now a @Binding, passed down from LangGoApp.
    @Binding var isLoggedIn: Bool
    
    // Side menu state remains the same
    @State private var isSideMenuShowing = false
    @State private var isShowingProfileSheet = false
    @State private var isShowingLanguageSheet = false
    @State private var isShowingSettingSheet = false
    
    // 2. The keychain check and custom init() are REMOVED. The view is much simpler.
    init(isLoggedIn: Binding<Bool>) {
        _isLoggedIn = isLoggedIn
        
        // Tab bar appearance setup remains the same
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        // 3. The if/else logic is REMOVED. This view's only job is to show the ZStack with the TabView.
        ZStack {
            TabView {
                LearnTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Learn", systemImage: "leaf.fill") }

                FlashcardTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Flashcards", systemImage: "square.stack.3d.up.fill") }

                AITabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("AI", systemImage: "sparkles") }
                
                StoriesTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Stories", systemImage: "book.fill") }

                TranslationTabView(isSideMenuShowing: $isSideMenuShowing)
                    .tabItem { Label("Translation", systemImage: "captions.bubble.fill") }
            }
            .tint(Color.purple)
            
            // Side Menu Layer
            if isSideMenuShowing {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) { isSideMenuShowing = false }
                    }
                    .transition(.opacity)
            }
            
            SideMenuView(
                isShowing: $isSideMenuShowing,
                isLoggedIn: $isLoggedIn, // This binding is passed down as before
                isShowingProfileSheet: $isShowingProfileSheet,
                isShowingLanguageSheet: $isShowingLanguageSheet,
                isShowingSettingSheet: $isShowingSettingSheet
            )
            .frame(width: UIScreen.main.bounds.width * 0.75)
            .offset(x: isSideMenuShowing ? 0 : UIScreen.main.bounds.width)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingProfileSheet) { Text("Profile View Sheet") }
        .sheet(isPresented: $isShowingLanguageSheet) { Text("Language Picker Sheet") }
        .sheet(isPresented: $isShowingSettingSheet) { Text("Settings View Sheet") }
    }
}


// MARK: - Placeholder Tab Views
// No changes needed here
struct AITabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("AI View").navigationTitle("AI Assistant").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}
struct StoriesTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Stories View").navigationTitle("Stories").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}
struct TranslationTabView: View {
    @Binding var isSideMenuShowing: Bool
    var body: some View { NavigationStack { Text("Translation View").navigationTitle("Translation").toolbar { MenuToolbar(isSideMenuShowing: $isSideMenuShowing) } } }
}


// MARK: - Reusable Components
// No changes needed to SideMenuView, SideMenuButton, or MenuToolbar
struct SideMenuView: View {
    @Binding var isShowing: Bool
    @Binding var isLoggedIn: Bool
    @Binding var isShowingProfileSheet: Bool
    @Binding var isShowingLanguageSheet: Bool
    @Binding var isShowingSettingSheet: Bool
    
    let keychain = Keychain(service: "com.geniusparentingai.GeniusParentingAISwift")

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 50))
                    Text("User Name").font(.title2.bold())
                    Text("user.email@langgo.com").font(.subheadline).foregroundColor(.gray)
                }.padding(30)
                SideMenuButton(title: "Profile", iconName: "person.fill") { isShowingProfileSheet.toggle() }
                SideMenuButton(title: "Select Language", iconName: "globe") { isShowingLanguageSheet.toggle() }
                SideMenuButton(title: "Settings", iconName: "gearshape.fill") { isShowingSettingSheet.toggle() }
                Spacer()
                SideMenuButton(title: "Logout", iconName: "arrow.right.square.fill") {
                    // Logout Action
                    keychain["jwt"] = nil
                    isLoggedIn = false
                    isShowing = false
                }.padding(.bottom, 40)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.1, green: 0.1, blue: 0.2))
        }
    }
}

struct SideMenuButton: View {
    var title: String, iconName: String, action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 15) { Image(systemName: iconName).font(.title2); Text(title).font(.headline) }.padding().frame(maxWidth: .infinity, alignment: .leading) } }
}

struct MenuToolbar: ToolbarContent {
    @Binding var isSideMenuShowing: Bool
    var body: some ToolbarContent { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { withAnimation(.easeInOut) { isSideMenuShowing.toggle() } }) { Image(systemName: "line.3.horizontal").font(.title3).foregroundColor(.primary) } } }
}


// MARK: - Preview
#Preview {
    // The preview now needs a constant binding to work.
    MainView(isLoggedIn: .constant(true))
}
