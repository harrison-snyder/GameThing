//
//  CharacterStateMachine.swift
//  VillageWorld
//
//  Drives idle → wander → interacting → working transitions for one character.
//  GameScene.update() calls update(deltaTime:) every frame.
//
//  State rules:
//    idle        — wait 2-5 s, then pick a random tile within wanderRadius of home
//    wandering   — SKAction sequence is in flight; completion callback returns to idle
//    interacting — motion stopped; InteractionManager calls exitInteracting() to resume
//    working     — reserved for Phase 4 (worker task execution)
//

import SpriteKit

final class CharacterStateMachine {

    // MARK: - Dependencies (all weak or value types — no retain cycles)

    private weak var entity: CharacterEntity?
    private let movement: CharacterMovement     // shared, read-only pathfinding
    private let tileMap:  SKTileMapNode
    private let grid:     [[TileCell]]

    // MARK: - Config

    private let wanderRadius: Int = 8

    // MARK: - Internal State

    private var idleTimer:  TimeInterval = 0
    private var isMoving:   Bool         = false

    // MARK: - Init

    init(
        entity:   CharacterEntity,
        movement: CharacterMovement,
        tileMap:  SKTileMapNode,
        grid:     [[TileCell]]
    ) {
        self.entity   = entity
        self.movement = movement
        self.tileMap  = tileMap
        self.grid     = grid
        resetIdleTimer()
    }

    // MARK: - Per-Frame Tick

    func update(deltaTime: TimeInterval) {
        guard let entity, entity.currentState == .idle, !isMoving else { return }
        idleTimer -= deltaTime
        if idleTimer <= 0 { startWander() }
    }

    // MARK: - Interaction API (called by InteractionManager)

    func enterInteracting() {
        guard let entity else { return }
        entity.spriteNode.removeAllActions()
        isMoving = false
        entity.currentState = .interacting
    }

    func exitInteracting() {
        guard let entity else { return }
        entity.currentState = .idle
        resetIdleTimer()
    }

    // MARK: - Wander

    private func startWander() {
        guard let entity else { return }

        let home = entity.homePosition
        var candidates: [GridPosition] = []

        for dc in -wanderRadius...wanderRadius {
            for dr in -wanderRadius...wanderRadius {
                let c = home.col + dc
                let r = home.row + dr
                guard c >= 0, c < TileMapManager.columns,
                      r >= 0, r < TileMapManager.rows,
                      grid[c][r].isWalkable else { continue }
                candidates.append(GridPosition(col: c, row: r))
            }
        }

        guard let dest = candidates.randomElement() else {
            resetIdleTimer(); return
        }

        // Convert sprite's scene-space position to a grid tile.
        // tileMap is at scene origin, so scene space == tileMap local space.
        let current = movement.gridPosition(fromTileMapPoint: entity.spriteNode.position,
                                            tileMap: tileMap)
                      ?? entity.gridPosition

        guard let path = movement.findPath(from: current, to: dest), path.count > 1 else {
            resetIdleTimer(); return
        }

        entity.currentState = .wandering
        isMoving = true

        let walk = movement.walkAction(along: path, tileMap: tileMap) { [weak entity] pos in
            entity?.gridPosition = pos
        }

        entity.spriteNode.run(.sequence([
            walk,
            .run { [weak self, weak entity] in
                entity?.gridPosition  = dest
                entity?.currentState  = .idle
                self?.isMoving        = false
                self?.resetIdleTimer()
            },
        ]))
    }

    // MARK: - Helpers

    private func resetIdleTimer() {
        idleTimer = Double.random(in: 2...5)
    }
}
