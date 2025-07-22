// LangGo/HomeView.swift
import SwiftUI
import AVKit // Use the AVKit framework for video playback

// An enum to differentiate image sources for practice cards.
private enum PracticeImage {
    case asset(String)
    case system(String)
}

// An enum to differentiate the video source.
private enum VideoSource {
    case asset(String) // For video name in Assets.xcassets
    case remote(URL)   // For a remote video URL
}


// Data model for the horizontally-scrolling practice cards.
private struct PracticeAction: Identifiable {
    let id = UUID()
    let image: PracticeImage
    let title: String
    let tabIndex: Int
    let videoSource: VideoSource? // The video to be played
}

/// The main view for the "LangGo" home screen, redesigned to match the mockup.
struct HomeView: View {
    @Environment(\.theme) var theme
    @Binding var selectedTab: Int
    @State private var username: String = "Vivian" // Default value, loaded from UserDefaults

    /// Data for the practice cards. Actions navigate to the correct tabs.
    private var practiceActions: [PracticeAction] {
        [
            PracticeAction(
                image: .asset("module-vocabulary"),
                title: "Build up my vocabulary",
                tabIndex: 1,
                videoSource: .asset("Introducing the Smart Vocabulary Notebook") // Set to your asset name
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
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Greeting Header
                Text("Hi, \(username)")
                    .homeStyle(.greetingTitle)

                // 2. Limited Offer Banner
                OfferBannerView()
                
                // 3. "Ready to Go" Section with Practice Cards
                VStack(alignment: .leading, spacing: 16) {
                    Text("LangGo, Ready to GO?")
                        .homeStyle(.sectionHeader)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(practiceActions) { action in
                                PracticeCardView(action: action, selectedTab: $selectedTab)
                            }
                        }
                    }
                }
                
                // 4. Explore Lessons Section
                ExploreLessonsView()
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            self.username = UserDefaults.standard.string(forKey: "username") ?? "Vivian"
        }
    }
}

// MARK: - Reusable Components for HomeView

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
    @Environment(\.theme) var theme: Theme
    
    // A state variable to hold the temporary URL of the local video file.
    @State private var localVideoURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Main visual element for the card
            Group {
                // If a video URL is available, use the VideoPlayer
                if let url = localVideoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else {
                    // Otherwise, fall back to the image
                    switch action.image {
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .scaledToFit()
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 70))
                            .foregroundColor(theme.text.opacity(0.5))
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            // Show a background only if it's an image
            .background(localVideoURL == nil ? theme.secondary.opacity(0.2) : .clear)
            .cornerRadius(12)
            .onAppear {
                // When the view appears, prepare the local video from the asset name
                if case let .asset(videoName)? = action.videoSource {
                    prepareLocalVideo(named: videoName)
                }
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
        .homeStyle(.practiceCard)
        .frame(width: UIScreen.main.bounds.width * 0.85) // Set width to 85% of screen width
    }

    /// This function loads video data from your app's assets and writes it to a
    /// temporary file that the VideoPlayer can use.
    private func prepareLocalVideo(named assetName: String) {
        // Find the asset in your app's bundle
        guard let dataAsset = NSDataAsset(name: assetName) else {
            print("Video asset '\(assetName)' not found in Asset Catalog.")
            return
        }
        
        // Create a temporary URL in the device's cache directory
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let tempURL = cacheDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        
        // Write the video data to the temporary URL
        do {
            try dataAsset.data.write(to: tempURL)
            self.localVideoURL = tempURL // Set the state variable to trigger the VideoPlayer
        } catch {
            print("Error writing video to temporary file: \(error)")
        }
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
