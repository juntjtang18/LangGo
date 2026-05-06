import SwiftUI

struct ConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    @Environment(\.theme) var theme: Theme

    @FocusState private var isInputFocused: Bool
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        VStack(spacing: 0) {
            AvatarView(isSpeaking: viewModel.isMouthAnimating)
                .frame(height: UIScreen.main.bounds.height * 0.55)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

            VStack {
                // Messages list…
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
                    .onAppear {
                        if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.messages) { new in
                        if let last = new.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).style(.errorText)
                }

                // Input bar
                HStack(spacing: 12) {
                    if viewModel.isSendingMessage {
                        ProgressView()
                            .frame(width: 108, height: 108)
                    } else {
                        Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash.fill")
                            .conversationStyle(.micButton(isListening: viewModel.isListening))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in if !viewModel.isListening { viewModel.startListening() } }
                                    .onEnded { _ in if viewModel.isListening { viewModel.stopListening() } }
                            )
                    }

                    TextField("Type or hold to speak...", text: $viewModel.newMessageText)
                        .font(.system(size: 15)) // Set font size to 15pt
                        .textFieldStyle(ThemedTextFieldStyle())
                        .disabled(viewModel.isSendingMessage || viewModel.isListening)
                        .focused($isInputFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button(action: { isInputFocused = false }) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .imageScale(.large)
                                        .padding(.vertical, 6)
                                }
                                .accessibilityLabel("Hide keyboard")
                            }
                        }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(theme.background)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { viewModel.startConversation() }
        .onDisappear { viewModel.cleanupAudioOnDisappear() }

        // Lift everything above the keyboard
        .padding(.bottom, keyboard.height)
        .animation(.easeOut(duration: 0.25), value: keyboard.height)
        // Also allow tapping anywhere to dismiss
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
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
