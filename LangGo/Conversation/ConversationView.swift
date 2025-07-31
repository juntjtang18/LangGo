import SwiftUI

struct ConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            // 1. Avatar occupies the top 55% of the screen
            AvatarView(isSpeaking: viewModel.isMouthAnimating)
                .frame(height: UIScreen.main.bounds.height * 0.55)
                .clipped()

            // 2. Chat UI occupies the remaining space with a solid background
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // If you wanted the iOS 17 `initial: true` behavior, simulate it here.
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .style(.errorText)
                }

                HStack(spacing: 15) {
                    if viewModel.isSendingMessage {
                        ProgressView()
                            .frame(width: 108, height: 108)
                    } else {
                        Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash.fill")
                            .conversationStyle(.micButton(isListening: viewModel.isListening))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !viewModel.isListening {
                                            viewModel.startListening()
                                        }
                                    }
                                    .onEnded { _ in
                                        if viewModel.isListening {
                                            viewModel.stopListening()
                                        }
                                    }
                            )
                    }

                    TextField("Type or hold to speak...", text: $viewModel.newMessageText)
                        .textFieldStyle(ThemedTextFieldStyle())
                        .disabled(viewModel.isSendingMessage || viewModel.isListening)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(theme.background)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            viewModel.startConversation()
        }
        .onDisappear {
            viewModel.cleanupAudioOnDisappear()
        }
    }
}


struct MessageView: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.content)
                    .conversationStyle(.messageBubble(isUser: true))
            } else {
                Text(message.content)
                    .conversationStyle(.messageBubble(isUser: false))
                Spacer()
            }
        }
    }
}
struct AvatarView: View {
    var isSpeaking: Bool

    var body: some View {
        Image(isSpeaking ? "girl1-open" : "girl1-close")
            .resizable()
            .scaledToFill()
            .transition(.opacity.animation(.easeInOut(duration: 0.1)))
    }
}
