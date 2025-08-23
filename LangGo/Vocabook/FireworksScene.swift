//
//  FireworksScene.swift
//  LangGo
//
//  Created by James Tang on 2025/8/22.
//


import SwiftUI
import SpriteKit

// This is a simple SpriteKit scene that loads our .sks file
class FireworksScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .clear

        // This action creates a new fireworks burst at a random location
        let burstAction = SKAction.run { [weak self] in
            self?.createFireworksBurst()
        }
        
        // This action creates a delay
        let waitAction = SKAction.wait(forDuration: 1.5, withRange: 1.0)
        
        // We create a sequence of bursting and waiting
        let sequence = SKAction.sequence([burstAction, waitAction])
        
        // Run the sequence forever
        self.run(SKAction.repeatForever(sequence))
    }
    
    private func createFireworksBurst() {
        guard let view = self.view else { return }
        
        // Load the particle file
        guard let emitter = SKEmitterNode(fileNamed: "Fireworks.sks") else {
            print("Error: Could not load Fireworks.sks")
            return
        }
        
        // Place the burst at a random position on the screen
        let randomX = CGFloat.random(in: view.bounds.width * 0.1 ... view.bounds.width * 0.9)
        let randomY = CGFloat.random(in: view.bounds.height * 0.3 ... view.bounds.height * 0.7)
        emitter.position = CGPoint(x: randomX, y: randomY)
        
        // Add the burst to the scene
        addChild(emitter)
        
        // Set the emitter to be removed from the scene after its particles have faded
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 2.5), // Wait for particles to fade
            SKAction.removeFromParent()     // Remove the emitter node
        ])
        emitter.run(removeAction)
    }
}


// This is the SwiftUI view that hosts the SpriteKit scene
// This is the SwiftUI view that hosts the SpriteKit scene
struct FireworksView: View {
    // Create the scene and specify its size
    var scene: SKScene {
        let scene = FireworksScene()
        // Use the full screen size for a better effect
        scene.size = UIScreen.main.bounds.size
        scene.scaleMode = .resizeFill
        return scene
    }

    var body: some View {
        // CORRECTED: The .options parameter has been removed.
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
