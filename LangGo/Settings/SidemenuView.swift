import Foundation
import SwiftUI
import KeychainAccess

struct SideMenuView: View {
    @Binding var isShowing: Bool
    @Binding var authState: AuthState
    @Binding var isShowingProfileSheet: Bool
    @Binding var isShowingSettingSheet: Bool
    @Binding var isShowingVocabookSettingSheet: Bool

    @EnvironmentObject var userSession: UserSessionManager

    private let keychain = Keychain(service: Config.keychainService)

    private var displayUsername: String {
        userSession.currentUser?.username ?? "User"
    }
    private var displayEmail: String {
        userSession.currentUser?.email ?? "No email found"
    }

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 50))
                    Text(displayUsername)
                        .font(.title2.bold())
                    Text(displayEmail)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(30)

                // Menu buttons
                SideMenuButton(title: "Profile", iconName: "person.fill") {
                    isShowingProfileSheet.toggle()
                    isShowing = false
                }

                SideMenuButton(title: "Vocabulary Notebook Setting", iconName: "book.fill") {
                    isShowingVocabookSettingSheet.toggle()
                    isShowing = false
                }

                SideMenuButton(title: "Settings", iconName: "gearshape.fill") {
                    isShowingSettingSheet.toggle()
                    isShowing = false
                }

                Spacer()

                // Logout
                SideMenuButton(title: "Logout", iconName: "arrow.right.square.fill") {
                    keychain["jwt"] = nil            // clear token
                    userSession.logout()             // clear in-memory & persisted user bits
                    authState = .loggedOut
                    isShowing = false
                }
                .padding(.bottom, 40)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.1, green: 0.1, blue: 0.2))
        }
    }
}

/// A reusable button component for the side menu.
struct SideMenuButton: View {
    var title: String
    var iconName: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: iconName)
                    .font(.title2)
                Text(title)
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
