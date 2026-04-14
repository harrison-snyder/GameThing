//
//  InteractionManager.swift
//  VillageWorld
//
//  Proximity-based NPC ↔ NPC interaction.
//  Checks pairwise character distances every `checkInterval` seconds.
//  If two eligible characters are within `proximityTiles` tiles:
//    — 30 % chance to trigger a brief "chat" (chat bubble + interaction state)
//    — The LLM generates actual dialogue for the bubble text.
//

import SpriteKit

final class InteractionManager {

    // MARK: - Config

    private let proximityTiles: Int   = 2
    private let checkInterval: Double = 8.0   // seconds between proximity sweeps
    private let chatDuration:  Double = 5.0   // seconds an interaction lasts

    // MARK: - State

    private var checkTimer: TimeInterval = 0

    // MARK: - AI (wired by GameScene/AppState)

    var dialogueGenerator: DialogueGenerator?
    var interactionContext: (() -> InteractionContext)?

    // MARK: - Callback (wired by GameScene to handle player-tap interactions)

    var onPlayerTappedCharacter: ((CharacterEntity) -> Void)?

    // MARK: - Per-Frame Update

    func update(deltaTime: TimeInterval, characters: [CharacterEntity], tileMap: SKTileMapNode) {
        checkTimer += deltaTime
        guard checkTimer >= checkInterval else { return }
        checkTimer = 0
        sweepProximity(characters: characters, tileMap: tileMap)
    }

    // MARK: - Proximity Sweep

    private func sweepProximity(characters: [CharacterEntity], tileMap: SKTileMapNode) {
        // Only consider characters that aren't already busy
        let eligible = characters.filter {
            $0.currentState == .idle || $0.currentState == .wandering
        }

        for i in 0..<eligible.count {
            for j in (i + 1)..<eligible.count {
                let a = eligible[i]
                let b = eligible[j]

                let manhattan = abs(a.gridPosition.col - b.gridPosition.col)
                             + abs(a.gridPosition.row - b.gridPosition.row)
                guard manhattan <= proximityTiles else { continue }
                guard Double.random(in: 0...1) < 0.30 else { continue }

                triggerChat(between: a, and: b)
                return  // one interaction per sweep
            }
        }
    }

    // MARK: - Chat Interaction

    private func triggerChat(between a: CharacterEntity, and b: CharacterEntity) {
        a.stateMachine?.enterInteracting()
        b.stateMachine?.enterInteracting()

        // Show placeholder immediately, then replace with LLM text
        showBubble(on: a.spriteNode, text: "...")
        showBubble(on: b.spriteNode, text: "...")

        // Generate real dialogue if LLM is available
        if let generator = dialogueGenerator {
            let ctx = interactionContext?() ?? InteractionContext()
            Task {
                let textA = await generator.generateFullDialogue(
                    character: a,
                    playerInput: "\(b.name) walks up to you and says hello.",
                    context: ctx
                )
                let shortA = String(textA.prefix(40))

                let textB = await generator.generateFullDialogue(
                    character: b,
                    playerInput: "\(a.name) says: \(shortA)",
                    context: ctx
                )
                let shortB = String(textB.prefix(40))

                await MainActor.run {
                    self.showBubble(on: a.spriteNode, text: shortA.isEmpty ? "Hello!" : shortA)
                    self.showBubble(on: b.spriteNode, text: shortB.isEmpty ? "Hi!" : shortB)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + chatDuration) { [weak a, weak b] in
            a?.stateMachine?.exitInteracting()
            b?.stateMachine?.exitInteracting()
        }
    }

    // MARK: - Chat Bubble Node

    private func showBubble(on sprite: SKSpriteNode, text: String) {
        sprite.childNode(withName: "chatBubble")?.removeFromParent()

        // Truncate for display
        let displayText = text.count > 35 ? String(text.prefix(32)) + "..." : text

        let label        = SKLabelNode(text: displayText)
        label.fontName   = "Courier-Bold"
        label.fontSize   = 7
        label.fontColor  = .black
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center

        let pad: CGFloat = 5
        let bgW  = max(label.frame.width + pad * 2, 18)
        let bgH: CGFloat = 14

        let bg      = SKSpriteNode(color: .white, size: CGSize(width: bgW, height: bgH))
        bg.name     = "chatBubble"
        bg.zPosition = 20
        bg.position  = CGPoint(x: 0, y: sprite.size.height * 0.5 + bgH * 0.5 + 3)
        bg.addChild(label)
        sprite.addChild(bg)

        bg.run(.sequence([
            .wait(forDuration: chatDuration - 0.5),
            .fadeOut(withDuration: 0.5),
            .removeFromParent(),
        ]))
    }
}
