import SwiftUI
import AVKit

// MARK: - PreferenceKey for Tracking Card Visibility
private struct CardVisibilityInfo: Equatable {
    let id: UUID
    let frame: CGRect
}

private struct VisibleCardPreferenceKey: PreferenceKey {
    typealias Value = [CardVisibilityInfo]
    static var defaultValue: Value = []

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Home View
struct HomeView: View {
    @Environment(\.theme) var theme
    @Binding var selectedTab: Int
    @State private var username: String = "Vivian"
    @AppStorage("homeViewVideoMuted") private var isGloballyMuted: Bool = false
    
    @StateObject private var playerManager = VideoPlayerManager()
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
            videoSource: .asset("LangGo App_ Talk to Your Learning Partner Feature")
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
                                        playerManager: playerManager
                                    )
                                }
                            }
                        }
                        .onPreferenceChange(VisibleCardPreferenceKey.self) { cardInfos in
                            // Use a slight delay to avoid frantic playback during fast scrolls
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                processVisibleCards(cardInfos, screenFrame: screenGeometry.frame(in: .global))
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
            isViewActive = (newTab == 0)
        }
        .onChange(of: isViewActive) { _, active in
            if !active {
                playerManager.stopAllPlayback()
            }
        }
    }

    private func processVisibleCards(_ infos: [CardVisibilityInfo], screenFrame: CGRect) {
        let videoCards = infos.filter { info in
            practiceActions.first { $0.id == info.id }?.videoSource != nil
        }
        
        // Find the card that is most centered on the screen
        var bestCandidate: (id: UUID, distance: CGFloat)? = nil
        
        for info in videoCards {
            let cardMidX = info.frame.midX
            let screenMidX = screenFrame.midX
            let distance = abs(cardMidX - screenMidX)
            
            // Ensure the card is at least partially on screen
            if info.frame.maxX > screenFrame.minX && info.frame.minX < screenFrame.maxX {
                if bestCandidate == nil || distance < bestCandidate!.distance {
                    bestCandidate = (info.id, distance)
                }
            }
        }
        
        // Play the video for the best candidate if the view is active
        if let bestCandidateID = bestCandidate?.id, isViewActive {
            if let actionToPlay = practiceActions.first(where: { $0.id == bestCandidateID }),
               let videoSource = actionToPlay.videoSource,
               let url = getVideoURL(from: videoSource) {
                playerManager.play(url: url, for: bestCandidateID, isMuted: isGloballyMuted)
            }
        }
    }

    private func getVideoURL(from source: VideoSource) -> URL? {
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


// MARK: - Reusable Components
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

private struct OfferBannerView: View {
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
    @ObservedObject var playerManager: VideoPlayerManager
    @Environment(\.theme) var theme: Theme
    
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
            // Report the card's frame to the parent view
            .preference(key: VisibleCardPreferenceKey.self, value: [CardVisibilityInfo(id: action.id, frame: cardGeometry.frame(in: .global))])
        }
        .homeStyle(.practiceCard)
        .frame(width: UIScreen.main.bounds.width * 0.85)
    }
}


private struct ExploreLessonsView: View {
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
