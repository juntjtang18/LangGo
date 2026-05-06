import Foundation
import AVKit
import Combine

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published private(set) var currentlyPlayingID: String?
    // ADDED: This set tracks which videos have played to the end.
    @Published var finishedVideoIDs: Set<String> = []

    private var playerCache: [String: AVQueuePlayer] = [:]
    // ADDED: This dictionary helps find the ID for a given player item.
    private var itemToIDMap: [AVPlayerItem: String] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        // This observer now detects when a video finishes and adds its ID to our set.
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] notification in
                guard let self = self,
                      let playerItem = notification.object as? AVPlayerItem,
                      let finishedID = self.itemToIDMap[playerItem] else {
                    return
                }
                
                // Mark the video as finished.
                self.finishedVideoIDs.insert(finishedID)
                if self.currentlyPlayingID == finishedID {
                    self.currentlyPlayingID = nil
                }
            }
            .store(in: &cancellables)
    }
    
    func player(for id: String, with url: URL) -> AVQueuePlayer {
        if let existingPlayer = playerCache[id] {
            return existingPlayer
        } else {
            let playerItem = AVPlayerItem(url: url)
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            playerCache[id] = newPlayer
            itemToIDMap[playerItem] = id // Map the item back to its ID.
            return newPlayer
        }
    }

    func playVideo(for id: String, isMuted: Bool) {
        guard let player = playerCache[id] else { return }

        if let currentId = currentlyPlayingID, currentId != id {
            playerCache[currentId]?.pause()
        }
        
        // When we play a video, it's no longer in the "finished" state.
        finishedVideoIDs.remove(id)
        
        // If the video was at its end, seek to the beginning.
        if let currentItem = player.currentItem, player.currentTime() >= currentItem.duration {
            player.seek(to: .zero)
        }
        
        player.isMuted = isMuted
        player.play()
        
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
