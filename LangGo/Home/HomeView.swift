import SwiftUI
import AVKit

// ADDED: A PreferenceKey to communicate card visibility from child views to the ScrollView.
private struct VisibleCardPreferenceKey: PreferenceKey {
    struct CardInfo: Equatable {
        let id: String
        let frame: CGRect
    }

    typealias Value = [CardInfo]
    static var defaultValue: Value = []

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.append(contentsOf: nextValue())
    }
}

struct HomeView: View {
    @Environment(\.theme) var theme: Theme
    // ADDED: The view now receives the selectedTab binding.
    @Binding var selectedTab: Int
    @State private var username: String = "Vivian"
    @AppStorage("homeViewVideoMuted") private var isVideoMuted: Bool = true
    
    // CHANGED: The manager is now a @StateObject as it's owned by this view.
    @StateObject private var playerManager = VideoPlayerManager()
    
    // ADDED: A computed property to determine if this tab is active.
    private var isViewActive: Bool {
        selectedTab == 0
    }

    private let practiceActions: [PracticeAction] = [
        // CHANGED: Added a unique 'id' string to each action for state tracking.
        PracticeAction(
            id: "vocab_video",
            image: .asset("module-vocabulary"),
            title: "Build up my vocabulary",
            tabIndex: 1,
            videoAssetName: "Introducing the Smart Vocabulary Notebook"
        ),
        PracticeAction(
            id: "ai_partner_video",
            image: .system("message.fill"),
            title: "Talk to your AI Partner",
            tabIndex: 2,
            videoAssetName: "LangGo App_ Talk to Your Learning Partner Feature"
        ),
        PracticeAction(
            id: "read_stories",
            image: .system("book.fill"),
            title: "Read Stories",
            tabIndex: 3,
            videoAssetName: nil
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
                            // CHANGED: The mute button now directly updates the player manager.
                            Button(action: {
                                isVideoMuted.toggle()
                                playerManager.currentPlayer?.isMuted = isVideoMuted
                            }) {
                                Image(systemName: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
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
                                        playerManager: playerManager
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                        // ADDED: These modifiers listen for the visible cards and process them.
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(VisibleCardPreferenceKey.self) { cardInfos in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                processVisibleCards(cardInfos, in: screenGeometry.frame(in: .global))
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
        }
        // ADDED: This observer pauses all videos when the user switches to a different tab.
        .onChange(of: isViewActive) { _, active in
            if !active {
                playerManager.stopAllPlayback()
            }
        }
    }

    // ADDED: This new function contains all the logic for deciding which video to play or pause.
    private func processVisibleCards(_ infos: [VisibleCardPreferenceKey.CardInfo], in screenFrame: CGRect) {
        guard isViewActive else { return }

        let visibleVideoCards = infos.filter { info in
            practiceActions.first { $0.id == info.id }?.videoAssetName != nil && screenFrame.intersects(info.frame)
        }
        
        let bestCandidate = visibleVideoCards.min(by: {
            abs($0.frame.midX - screenFrame.midX) < abs($1.frame.midX - screenFrame.midX)
        })
        
        if let cardToPlay = bestCandidate {
            if let action = practiceActions.first(where: { $0.id == cardToPlay.id }),
               let assetName = action.videoAssetName,
               let url = getVideoURL(fromAsset: assetName) {
                playerManager.playVideo(for: cardToPlay.id, with: url, isMuted: isVideoMuted)
            }
        }

        for info in visibleVideoCards {
            if info.id != bestCandidate?.id {
                playerManager.pauseVideo(for: info.id)
            }
        }
    }

    // This helper function is unchanged, but used by the new logic.
    private func getVideoURL(fromAsset assetName: String) -> URL? {
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
    }
}

// This struct is unchanged.
private enum PracticeImage {
    case asset(String)
    case system(String)
}

private struct PracticeAction: Identifiable {
    // CHANGED: The 'id' is now a String to be more explicit and is required.
    let id: String
    let image: PracticeImage
    let title: String
    let tabIndex: Int
    let videoAssetName: String?
}

// This view is unchanged.
private struct OfferBannerView: View {
    @Environment(\.theme) var theme: Theme

    var body: some View {
        Button(action: { /* Offer action */ }) {
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
    @ObservedObject var playerManager: VideoPlayerManager
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                // CHANGED: Logic now checks the currentlyPlayingID from the manager.
                if let player = playerManager.currentPlayer, playerManager.currentlyPlayingID == action.id {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(.default))
                } else {
                    ZStack {
                        Rectangle().fill(theme.secondary.opacity(0.2))
                        switch action.image {
                        case .asset(let name):
                            Image(name).resizable().scaledToFit().padding()
                        case .system(let name):
                            Image(systemName: name).font(.system(size: 70)).foregroundColor(theme.text.opacity(0.5))
                        }
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(playerManager.currentlyPlayingID == action.id ? .black : Color.clear)
            .cornerRadius(12)
            // ADDED: This background modifier is the key to reporting the card's position up to the parent.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: VisibleCardPreferenceKey.self,
                        value: [VisibleCardPreferenceKey.CardInfo(id: action.id, frame: proxy.frame(in: .named("scroll")))]
                    )
                }
            )
            
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
        .homeStyle(.practiceCard)
        .frame(width: UIScreen.main.bounds.width * 0.85)
    }
}

// This view is unchanged.
private struct ExploreLessonsView: View {
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explore lessons on specific topics")
                .homeStyle(.exploreTitle)
                
            Button(action: { /* Navigation action */ }) {
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
