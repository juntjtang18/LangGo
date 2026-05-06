import SwiftUI

struct CompletionOverlayView: View {
    var onDone: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            // Full-screen blur + subtle dim
            Rectangle()
                .fill(.ultraThinMaterial)          // system blur
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.18)) // gentle dim so text pops
                .transition(.opacity)

            // Floating content only (no card background)
            VStack(spacing: 14) {
                Image(systemName: "rosette")
                    .font(.system(size: 68, weight: .bold))
                    .foregroundStyle(.yellow, .orange)
                    .symbolRenderingMode(.palette)
                    .shadow(radius: 6, y: 2)

                Text("Review Complete")
                    .font(.title2.weight(.bold))
                    .shadow(radius: 2, y: 1)

                Text("Nice work! You’ve finished today’s due words.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .scaleEffect(appear ? 1.0 : 0.92)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appear)
        }
        .onAppear { appear = true }
    }
}
