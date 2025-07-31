// LangGo/Home/HomeView.swift

import SwiftUI
import AVKit

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
    @Binding var selectedTab: Int
    @State private var username: String = "Vivian"
    @AppStorage("homeViewVideoMuted") private var isVideoMuted: Bool = true
    
    @StateObject private var playerManager = VideoPlayerManager()
    
    private var isViewActive: Bool {
        selectedTab == 0
    }

    private let practiceActions: [PracticeAction] = [
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
            title: "Talk to my Conversation Partner",
            tabIndex: 2,
            videoAssetName: "LangGo App_ Talk to Your Learning Partner Feature"
        ),
        PracticeAction(
            id: "read_stories",
            image: .system("book.fill"),
            title: "Reading/Listening Stories",
            tabIndex: 3,
            videoAssetName: "LangGo_ Learn English Through Stories"
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
                            Text("LangGo to Pro, Ready to GO?")
                                .homeStyle(.sectionHeader)
                            Spacer()
                            Button(action: {
                                isVideoMuted.toggle()
                                if let currentlyPlayingID = playerManager.currentlyPlayingID {
                                    playerManager.playVideo(for: currentlyPlayingID, isMuted: isVideoMuted)
                                }
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
                                        videoURL: getVideoURL(fromAsset: action.videoAssetName),
                                        selectedTab: $selectedTab,
                                        playerManager: playerManager
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
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
        // MODIFIED: Changed the closure to match the iOS 14-16 signature.
        .onChange(of: isViewActive) { active in
            if !active {
                playerManager.stopAllPlayback()
            }
        }
    }

    private func processVisibleCards(_ infos: [VisibleCardPreferenceKey.CardInfo], in screenFrame: CGRect) {
        guard isViewActive else { return }

        let primaryCandidate = infos
            .filter { screenFrame.intersects($0.frame) }
            .min(by: { abs($0.frame.midX - screenFrame.midX) < abs($1.frame.midX - screenFrame.midX) })

        let primaryAction = primaryCandidate.flatMap { candidate in
            practiceActions.first { $0.id == candidate.id }
        }

        if let action = primaryAction, action.videoAssetName != nil {
            playerManager.playVideo(for: action.id, isMuted: isVideoMuted)
        } else {
            playerManager.stopAllPlayback()
        }

        for action in practiceActions where action.videoAssetName != nil {
            if action.id != primaryAction?.id {
                playerManager.pauseVideo(for: action.id)
            }
        }
    }

    private func getVideoURL(fromAsset assetName: String?) -> URL? {
        guard let assetName = assetName, !assetName.isEmpty else { return nil }
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

// Data Models and other helper views remain unchanged.

private enum PracticeImage {
    case asset(String)
    case system(String)
}

private struct PracticeAction: Identifiable {
    let id: String
    let image: PracticeImage
    let title: String
    let tabIndex: Int
    let videoAssetName: String?
}

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
                Image(systemName: "arrow.right").font(.title2.bold()).foregroundColor(theme.text)
            }
            .homeStyle(.offerBanner)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PracticeCardView: View {
    let action: PracticeAction
    let videoURL: URL?
    @Binding var selectedTab: Int
    @ObservedObject var playerManager: VideoPlayerManager
    @Environment(\.theme) var theme: Theme
    
    @State private var player: AVQueuePlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                let shouldShowVideo = playerManager.currentlyPlayingID == action.id && !playerManager.finishedVideoIDs.contains(action.id)

                if !shouldShowVideo {
                    switch action.image {
                    case .asset(let name):
                        Image(name).resizable().scaledToFit().padding()
                    case .system(let name):
                        Image(systemName: name).font(.system(size: 70)).foregroundColor(theme.text.opacity(0.5))
                    }
                }
                
                if let player = player {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                        .opacity(shouldShowVideo ? 1 : 0)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(theme.secondary.opacity(0.2))
            .cornerRadius(12)
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
        .onAppear {
            if let videoURL = videoURL {
                self.player = playerManager.player(for: action.id, with: videoURL)
            }
        }
    }
}

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
