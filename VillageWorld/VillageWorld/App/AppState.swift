//
//  AppState.swift
//  VillageWorld
//
//  Global observable game state shared between SwiftUI overlays and the
//  SpriteKit scene.  Owned by ContentView as a @StateObject.
//

import SwiftUI
import SpriteKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Game Scene

    let gameScene: GameScene

    // MARK: - HUD State (Phase 1 — placeholders)

    @Published var isDialogueActive: Bool = false

    @Published var resources: [String: Int] = [
        "Wood":  0,
        "Stone": 0,
        "Food":  0,
    ]

    // MARK: - Init

    init() {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        gameScene = scene
    }
}
