import SwiftUI

struct InitialLoadingView: View {
    @EnvironmentObject var reviewSettingsManager: ReviewSettingsManager
    @Binding var authState: AuthState
    @State private var isLoadingComplete = false

    var body: some View {
        Group {
            if isLoadingComplete {
                MainView(authState: $authState)
            } else {
                VStack {
                    Text("Loading Your App...")
                    ProgressView()
                }
                .onAppear {
                    Task {
                        await performInitialLoad()
                    }
                }
            }
        }
    }

    private func performInitialLoad() async {
        await reviewSettingsManager.load()
        
        DispatchQueue.main.async {
            isLoadingComplete = true
        }
    }
}
