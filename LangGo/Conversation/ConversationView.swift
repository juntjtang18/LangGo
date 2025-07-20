// LangGo/Conversation/ConversationView.swift
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
                            MessageView(message: message, theme: theme)
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
                    .foregroundColor(.red)
                    .padding()
            }

            HStack(spacing: 12) {
                TextField("Type or hold to speak...", text: $viewModel.newMessageText)
                    .textFieldStyle(ThemedTextFieldStyle())
                    .disabled(viewModel.isSendingMessage || viewModel.isListening)

                if viewModel.isSendingMessage {
                    ProgressView()
                } else {
                    Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash")
                        .font(.title)
                        .padding()
                        .background(viewModel.isListening ? Color.red.opacity(0.8) : Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .scaleEffect(viewModel.isListening ? 1.1 : 1.0)
                        .animation(.spring(), value: viewModel.isListening)
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
    let theme: Theme

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.content)
                    .padding()
                    .background(theme.primary.opacity(0.8))
                    .foregroundColor(theme.text)
                    .cornerRadius(12)
            } else {
                Text(message.content)
                    .padding()
                    .background(theme.secondary.opacity(0.8))
                    .foregroundColor(theme.text)
                    .cornerRadius(12)
                Spacer()
            }
        }
    }
}
