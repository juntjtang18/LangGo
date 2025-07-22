// LangGo/HomeView.swift
import SwiftUI
import AVKit

private enum PracticeImage {
    case asset(String)
    case system(String)
}

private enum VideoSource {
    case asset(String)
    case remote(URL)
}

private struct PracticeAction: Identifiable {
    let id = UUID()
    let image: PracticeImage
    let title: String
    let tabIndex: Int
    let videoSource: VideoSource?
}

struct HomeView: View {
    @Environment(\.theme) var theme
    @Binding var selectedTab: Int
    @State private var username: String = "Vivian"
    @AppStorage("homeViewVideoMuted") private var isGloballyMuted: Bool = false
    
    @StateObject private var playerManager = VideoPlayerManager()
    // 1. Add a state to explicitly track if this view is active.
    @State private var isViewActive: Bool = true

    private let practiceActions: [PracticeAction] = [
        PracticeAction(
            image: .asset("module-vocabulary"),
            title: "Build up my vocabulary",
            tabIndex: 1,
            videoSource: .asset("Introducing the Smart Vocabulary Notebook")
        ),
        PracticeAction(
            image: .system("message.fill"),
            title: "Talk to your AI Partner",
            tabIndex: 2,
            videoSource: nil
        ),
        PracticeAction(
            image: .system("book.fill"),
            title: "Read Stories",
            tabIndex: 3,
            videoSource: nil
        ),
        PracticeAction(
            image: .system("captions.bubble.fill"),
            title: "Smart Translate",
            tabIndex: 4,
            videoSource: nil
        )
    ]

    var body: some View {
        GeometryReader { screenGeometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Hi, \(username)")
                        .homeStyle(.greetingTitle)

                    OfferBannerView()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("LangGo, Ready to GO?")
                                .homeStyle(.sectionHeader)
                            Spacer()
                            Button(action: {
                                isGloballyMuted.toggle()
                                playerManager.updateMuteState(isMuted: isGloballyMuted)
                            }) {
                                Image(systemName: isGloballyMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.title2)
                                    .foregroundColor(theme.text)
                            }
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(practiceActions) { action in
                                    PracticeCardView(
                                        action: action,
                                        selectedTab: $selectedTab,
                                        isMuted: isGloballyMuted,
                                        playerManager: playerManager,
                                        screenFrame: screenGeometry.frame(in: .global),
                                        isViewActive: isViewActive // 2. Pass the active state to the card.
                                    )
                                }
                            }
                        }
                    }
                    
                    ExploreLessonsView()
                }
                .padding()
            }
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            self.username = UserDefaults.standard.string(forKey: "username") ?? "Vivian"
            self.isViewActive = (selectedTab == 0)
        }
        .onChange(of: selectedTab) { _, newTab in
            // 3. Update the active state when the tab changes.
            isViewActive = (newTab == 0)
        }
        .onChange(of: isViewActive) { _, active in
            // 4. When the view becomes inactive, forcefully stop all playback.
            if !active {
                playerManager.stopAllPlayback()
            }
        }
    }
}

// MARK: - Reusable Components for HomeView

private struct OfferBannerView: View {
    // ... (This view remains unchanged)
    @Environment(\.theme) var theme: Theme

    var body: some View {
        Button(action: { /* TODO: Implement offer action */ }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Limited Offer")
                        .homeStyle(.offerTitle)
                    Text("Try LangGo free for 7 days!\nEnds 25 July 2025 at 08:05")
                        .homeStyle(.offerSubtitle)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.title2.bold())
                    .foregroundColor(theme.text)
            }
            .homeStyle(.offerBanner)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PracticeCardView: View {
    let action: PracticeAction
    @Binding var selectedTab: Int
    let isMuted: Bool
    @ObservedObject var playerManager: VideoPlayerManager
    let screenFrame: CGRect
    let isViewActive: Bool // Receives the active state.
    @Environment(\.theme) var theme: Theme
    
    @State private var timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { cardGeometry in
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if let player = playerManager.player, playerManager.currentlyPlayingID == action.id {
                        VideoPlayer(player: player)
                            .allowsHitTesting(false)
                    } else {
                        switch action.image {
                        case .asset(let name):
                            Image(name).resizable().scaledToFit()
                        case .system(let name):
                            Image(systemName: name).font(.system(size: 70)).foregroundColor(theme.text.opacity(0.5))
                        }
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(playerManager.currentlyPlayingID == action.id ? .black : theme.secondary.opacity(0.2))
                .cornerRadius(12)
                .onReceive(timer) { _ in
                    checkVisibility(cardFrame: cardGeometry.frame(in: .global))
                }
                
                HStack {
                    Text(action.title)
                        .homeStyle(.practiceCardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: { selectedTab = action.tabIndex }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .homeStyle(.practiceCard)
        .frame(width: UIScreen.main.bounds.width * 0.85)
    }

    private func checkVisibility(cardFrame: CGRect) {
        let isFullyVisible = screenFrame.minX <= cardFrame.minX && cardFrame.maxX <= screenFrame.maxX
        
        // 5. The card will only attempt to play its video if the entire HomeView is active.
        if isFullyVisible && isViewActive {
            if let videoSource = action.videoSource, let url = getVideoURL(from: videoSource) {
                playerManager.play(url: url, for: action.id, isMuted: isMuted)
            }
        } else {
            playerManager.pause(for: action.id)
        }
    }

    private func getVideoURL(from source: VideoSource) -> URL? {
        // ... (This function remains unchanged)
        switch source {
        case .asset(let assetName):
            guard let dataAsset = NSDataAsset(name: assetName) else {
                print("Video asset '\(assetName)' not found.")
                return nil
            }
            let fileManager = FileManager.default
            let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let tempURL = cacheDirectory.appendingPathComponent("\(assetName).mp4")
            if !fileManager.fileExists(atPath: tempURL.path) {
                do {
                    try dataAsset.data.write(to: tempURL)
                } catch {
                    print("Error writing video to temporary file: \(error)")
                    return nil
                }
            }
            return tempURL
        case .remote(let url):
            return url
        }
    }
}


private struct ExploreLessonsView: View {
    // ... (This view remains unchanged)
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explore lessons on specific topics")
                .homeStyle(.exploreTitle)
                
            Button(action: { /* TODO: Implement navigation to topics view */ }) {
                HStack {
                    Text("Show Topics")
                    Image(systemName: "arrow.right")
                }
                .homeStyle(.exploreButton)
            }
        }
        .padding(.vertical)
    }
}
