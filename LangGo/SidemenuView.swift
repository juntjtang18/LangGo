//
//  SidemenuView.swift
//  LangGo
//
//  Created by James Tang on 2025/6/28.
//

import Foundation
import SwiftUI
import KeychainAccess

struct SideMenuView: View {
    @Binding var isShowing: Bool
    @Binding var isLoggedIn: Bool
    @Binding var isShowingProfileSheet: Bool
    @Binding var isShowingLanguageSheet: Bool
    @Binding var isShowingSettingSheet: Bool
    
    @State private var username: String = ""
    @State private var email: String = ""
    
    let keychain = Keychain(service: Config.keychainService)

    var body: some View {
        // The HStack pushes the VStack to the right edge.
        HStack {
            Spacer()
            
            // The main vertical stack for the menu content.
            VStack(alignment: .leading, spacing: 0) {
                // Header section with user info
                VStack(alignment: .leading) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 50))
                    Text(username)
                        .font(.title2.bold())
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(30)
                // --- MODIFICATION START ---
                // Use .onAppear to load data every time the menu is shown.
                // This is more reliable than .onChange for this use case.
                .onAppear {
                    self.username = UserDefaults.standard.string(forKey: "username") ?? "User"
                    self.email = UserDefaults.standard.string(forKey: "email") ?? "No email found"
                }
                // --- MODIFICATION END ---

                // Menu buttons
                SideMenuButton(title: "Profile", iconName: "person.fill") {
                    isShowingProfileSheet.toggle()
                    isShowing = false // Close side menu when opening profile
                }
                SideMenuButton(title: "Select Language", iconName: "globe") { isShowingLanguageSheet.toggle() }
                SideMenuButton(title: "Settings", iconName: "gearshape.fill") { isShowingSettingSheet.toggle() }
                
                Spacer()
                
                // Logout button at the bottom
                SideMenuButton(title: "Logout", iconName: "arrow.right.square.fill") {
                    // Clear all user data from Keychain and UserDefaults
                    keychain["jwt"] = nil
                    UserDefaults.standard.removeObject(forKey: "username")
                    UserDefaults.standard.removeObject(forKey: "userId")
                    UserDefaults.standard.removeObject(forKey: "email")
                    
                    // Update state to reflect logout
                    isLoggedIn = false
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
