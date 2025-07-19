//
//  ConversationTabView.swift
//  LangGo
//
//  Created by James Tang on 2025/7/19.
//


import SwiftUI

struct ConversationTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // The ViewModel is now created and owned by the TabView.
    @StateObject private var conversationViewModel: ConversationViewModel

    // Custom initializer to create the ViewModel using the environment object
    init(isSideMenuShowing: Binding<Bool>, appEnvironment: AppEnvironment) {
        _isSideMenuShowing = isSideMenuShowing
        // The ViewModel is initialized here, once, when the TabView is created.
        _conversationViewModel = StateObject(wrappedValue: ConversationViewModel(conversationService: appEnvironment.conversationService))
    }

    var body: some View {
        NavigationStack {
            // Pass the already-created ViewModel to the view.
            ConversationView(viewModel: conversationViewModel)
                .navigationTitle("AI Conversation Partner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    MenuToolbar(isSideMenuShowing: $isSideMenuShowing)
                }
        }
    }
}
