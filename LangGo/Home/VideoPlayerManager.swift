import Foundation
import AVKit
import Combine

@MainActor
class VideoPlayerManager: ObservableObject {
    // REMOVED: The single @Published currentPlayer was causing views to be destroyed/recreated, leading to the crash.
    // @Published private(set) var currentPlayer: AVQueuePlayer?
    
    @Published private(set) var currentlyPlayingID: String?

    private var playerCache: [String: AVQueuePlayer] = [:]
    private var cancellables = Set<AnyCancellable>()

    // ADDED: This new function provides a stable player instance for a given ID.
    // It creates and caches the player on the first request.
    func player(for id: String, with url: URL) -> AVQueuePlayer {
        if let existingPlayer = playerCache[id] {
            return existingPlayer
        } else {
            let playerItem = AVPlayerItem(url: url)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            playerCache[id] = newPlayer
            
            // Set up a loop observer for this specific new player.
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
                .sink { [weak newPlayer] _ in
                    newPlayer?.seek(to: .zero)
                    newPlayer?.play()
                }
                .store(in: &cancellables)
            
            return newPlayer
        }
    }

    func playVideo(for id: String, isMuted: Bool) {
        guard let player = playerCache[id] else { return }

        // Pause any other video that might be playing.
        if let currentId = currentlyPlayingID, currentId != id {
            playerCache[currentId]?.pause()
        }
        
        player.isMuted = isMuted
        player.play()
        
        // Announce which video is now playing.
        currentlyPlayingID = id
    }

    func pauseVideo(for id: String) {
        playerCache[id]?.pause()
        if currentlyPlayingID == id {
            currentlyPlayingID = nil
        }
    }
    
    func stopAllPlayback() {
        playerCache.values.forEach { $0.pause() }
        if currentlyPlayingID != nil {
            currentlyPlayingID = nil
        }
    }
}
