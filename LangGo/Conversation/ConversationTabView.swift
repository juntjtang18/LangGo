import SwiftUI

struct ConversationTabView: View {
    @Binding var isSideMenuShowing: Bool
    
    // The ViewModel is now initialized directly and cleanly using the standard property wrapper.
    // It no longer requires a custom init or receives any parameters.
    @StateObject private var conversationViewModel = ConversationViewModel()

    var body: some View {
        NavigationStack {
            // Pass the already-created ViewModel to the child view.
            ConversationView(viewModel: conversationViewModel)
                .navigationTitle("AI Conversation Partner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Using the direct toolbar implementation that we know works.
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isSideMenuShowing.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                }
        }
    }
}
