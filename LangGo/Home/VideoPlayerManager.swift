import Foundation
import AVKit
import Combine

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published private(set) var currentPlayer: AVQueuePlayer?
    // ADDED: Tracks the ID of the currently playing video to manage state.
    @Published private(set) var currentlyPlayingID: String?

    // ADDED: Caches player instances to avoid re-creating them on scroll.
    private var playerCache: [String: AVQueuePlayer] = [:]
    private var cancellables = Set<AnyCancellable>()

    // CHANGED: The init now uses a generic notification observer that isn't tied to a single player item.
    init() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] notification in
                guard let self = self,
                      let playerItem = notification.object as? AVPlayerItem,
                      let currentPlayer = self.currentPlayer,
                      playerItem == currentPlayer.currentItem else {
                    return
                }
                currentPlayer.seek(to: .zero)
                currentPlayer.play()
            }
            .store(in: &cancellables)
    }

    // ADDED: New stateful method to play a video by its ID.
    // This handles pausing other players and reusing cached players.
    func playVideo(for id: String, with url: URL, isMuted: Bool) {
        if let currentId = currentlyPlayingID, currentId != id {
            playerCache[currentId]?.pause()
        }

        if let player = playerCache[id] {
            self.currentPlayer = player
            player.isMuted = isMuted
            player.play()
        } else {
            let playerItem = AVPlayerItem(url: url)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            playerCache[id] = newPlayer
            self.currentPlayer = newPlayer
            newPlayer.isMuted = isMuted
            newPlayer.play()
        }
        
        self.currentlyPlayingID = id
    }

    // ADDED: Pauses a specific video without losing its state.
    func pauseVideo(for id: String) {
        playerCache[id]?.pause()
    }
    
    // CHANGED: Renamed from stop() to be more descriptive.
    // This now fully resets the playback state.
    func stopAllPlayback() {
        currentPlayer?.pause()
        currentPlayer = nil
        currentlyPlayingID = nil
    }
}
