// LangGo/VideoPlayerManager.swift
import Foundation
import AVKit

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var currentlyPlayingID: UUID?
    
    private var playerCache: [UUID: (player: AVQueuePlayer, looper: AVPlayerLooper)] = [:]

    func play(url: URL, for id: UUID, isMuted: Bool) {
        if let currentId = currentlyPlayingID, currentId != id {
            playerCache[currentId]?.player.pause()
        }
        
        if let cached = playerCache[id] {
            self.player = cached.player
            self.player?.isMuted = isMuted
            self.player?.play()
        } else {
            let playerItem = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            playerCache[id] = (player: queuePlayer, looper: looper)
            
            self.player = queuePlayer
            self.player?.isMuted = isMuted
            self.player?.play()
        }
        
        self.currentlyPlayingID = id
    }

    func pause(for id: UUID) {
        if self.currentlyPlayingID == id {
            playerCache[id]?.player.pause()
            self.currentlyPlayingID = nil
        }
    }
    
    func updateMuteState(isMuted: Bool) {
        self.player?.isMuted = isMuted
    }
    
    /// Stops the current video, removes its content, and clears the active player state.
    func stopAllPlayback() {
        player?.pause()
        // This is a more forceful stop that prevents the looper from continuing.
        player?.replaceCurrentItem(with: nil)
        
        player = nil
        currentlyPlayingID = nil
    }
}
