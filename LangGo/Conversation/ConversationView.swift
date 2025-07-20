import SwiftUI

struct ConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
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
                .onChange(of: viewModel.messages.count) {
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
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
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("AI Conversation")
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
