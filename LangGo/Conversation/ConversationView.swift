//
//  ConversationView.swift
//  LangGo
//
//  Created by James Tang on 2025/7/19.
//

import SwiftUI

struct ConversationView: View {
    // The view now observes a ViewModel created by its parent.
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
                    // Make sure scrolling happens on the main thread with animation
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

            HStack {
                TextField("Type a message...", text: $viewModel.newMessageText)
                    .textFieldStyle(ThemedTextFieldStyle())
                    .padding(.leading)
                    .disabled(viewModel.isSendingMessage)

                if viewModel.isSendingMessage {
                    ProgressView()
                        .padding(.trailing)
                } else {
                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(theme.accent)
                    }
                    .padding(.trailing)
                    .disabled(viewModel.newMessageText.isEmpty)
                }
            }
            .padding(.bottom)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("AI Conversation")
        .task {
            viewModel.startConversation()
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
