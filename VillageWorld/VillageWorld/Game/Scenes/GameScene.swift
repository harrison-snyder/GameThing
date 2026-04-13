//
//  GameScene.swift
//  VillageWorld
//
//  Main SKScene — tile map, player, camera, fog of war, tap-to-move,
//  drag-to-walk, and pinch-to-zoom.
//
//  Controls:
//    Tap   → A* pathfind to tapped tile
//    Drag  → Walk continuously in the dragged direction (4-directional)
//            Direction updates mid-drag at the next tile boundary.
//    Pinch → Zoom (0.5× – 2.0× camera scale)
//

import SpriteKit
import GameplayKit
import UIKit

final class GameScene: SKScene {

    // MARK: - Nodes

    private var tileMapNode: SKTileMapNode!
    private var playerNode:  SKSpriteNode!
    private let cameraNode = SKCameraNode()

    // MARK: - Systems

    private var tileMapManager: TileMapManager!
    private var fogOfWar:       FogOfWar!
    private var movement:       CharacterMovement!

    // MARK: - Grid State

    private var grid: [[TileCell]] = []
    private var playerGridPos = GridPosition(col: WorldGenerator.columns / 2,
                                             row: WorldGenerator.rows    / 2)

    // MARK: - Touch / Drag State

    /// Scene-space position where the current touch began.
    private var touchOrigin: CGPoint = .zero
    /// True once the touch has moved past the drag threshold.
    private var isDragging = false
    /// The last snapped direction while dragging.
    private var dragDirection: GridDirection? = nil
    /// True while a drag-driven tile step is in progress.
    /// The step's completion callback will chain the next step.
    private var isDragWalking = false

    private let dragThreshold: CGFloat = 18   // points before drag is recognised

    // MARK: - Pinch / Zoom State

    private var pinchStartScale: CGFloat = 1.0
    private var isPinching = false
    private let minCamScale: CGFloat = 0.5
    private let maxCamScale: CGFloat = 2.0

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        buildWorld()
        buildPlayer()
        buildCamera()
        attachGestureRecognisers(to: view)
    }

    // MARK: - World Setup

    private func buildWorld() {
        grid           = WorldGenerator.generate()
        tileMapManager = TileMapManager(grid: grid)
        tileMapNode    = tileMapManager.tileMap
        addChild(tileMapNode)

        fogOfWar = FogOfWar(columns: TileMapManager.columns,
                            rows:    TileMapManager.rows,
                            tileMap: tileMapNode)
        addChild(fogOfWar.node)

        movement = CharacterMovement(grid:    grid,
                                     columns: TileMapManager.columns,
                                     rows:    TileMapManager.rows)
        fogOfWar.reveal(around: playerGridPos, radius: 10)
    }

    private func buildPlayer() {
        playerNode = SKSpriteNode(texture: PlayerTexture.make(),
                                  color:   .clear,
                                  size:    CGSize(width: 32, height: 40))
        playerNode.position  = tileMapManager.tileCenter(col: playerGridPos.col, row: playerGridPos.row)
        playerNode.zPosition = 5
        playerNode.name      = "player"
        addChild(playerNode)
    }

    private func buildCamera() {
        addChild(cameraNode)
        camera              = cameraNode
        cameraNode.position = playerNode.position
        let halfW = CGFloat(TileMapManager.columns) * TileMapManager.tileSize / 2
        let halfH = CGFloat(TileMapManager.rows)    * TileMapManager.tileSize / 2
        cameraNode.constraints = [
            SKConstraint.positionX(SKRange(lowerLimit: -halfW, upperLimit: halfW)),
            SKConstraint.positionY(SKRange(lowerLimit: -halfH, upperLimit: halfH)),
        ]
    }

    // MARK: - Gesture Recognisers

    private func attachGestureRecognisers(to view: SKView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        switch r.state {
        case .began:
            pinchStartScale = cameraNode.xScale
            isPinching      = true
        case .changed:
            cameraNode.setScale((pinchStartScale / r.scale).clamped(to: minCamScale...maxCamScale))
        case .ended, .cancelled, .failed:
            isPinching = false
        default:
            break
        }
    }

    // MARK: - Touch Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPinching, let touch = touches.first else { return }
        touchOrigin  = touch.location(in: self)
        isDragging   = false
        dragDirection = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPinching, let touch = touches.first else { return }

        let current = touch.location(in: self)
        let delta   = CGPoint(x: current.x - touchOrigin.x,
                              y: current.y - touchOrigin.y)
        let mag     = hypot(delta.x, delta.y)

        guard mag >= dragThreshold else { return }

        // Slide the D-pad centre: keep touchOrigin exactly dragThreshold behind
        // the finger in the current direction of motion. This means the direction
        // is always measured relative to *recent* finger movement, not the original
        // touch point — so any of the 4 directions is equally reachable from
        // wherever the finger currently sits.
        touchOrigin = CGPoint(x: current.x - (delta.x / mag) * dragThreshold,
                              y: current.y - (delta.y / mag) * dragThreshold)

        guard let dir = GridDirection.from(delta: delta, threshold: dragThreshold) else { return }

        if !isDragging {
            // Transition from tap to drag: cancel any A* path in flight.
            isDragging = true
            playerNode.removeAllActions()
            isDragWalking = false
        }

        let directionChanged = dir != dragDirection
        dragDirection = dir

        if directionChanged && isDragWalking {
            // Cancel the in-flight tile step and redirect immediately from
            // wherever the player currently is.
            playerNode.removeAllActions()
            isDragWalking = false
            stepInDragDirection()
        } else if !isDragWalking {
            stepInDragDirection()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        if !isDragging {
            // Short tap — A* pathfind to the tapped tile.
            let tapPt = touch.location(in: tileMapNode)
            if let dest = tileMapManager.gridPosition(fromTileMapPoint: tapPt),
               grid[dest.col][dest.row].isWalkable {
                tapMovePlayer(to: dest)
            }
        }

        isDragging    = false
        dragDirection = nil
        // isDragWalking clears itself in the completion callback.
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging    = false
        dragDirection = nil
    }

    // MARK: - Tap Movement (A* pathfind)

    private func tapMovePlayer(to destination: GridPosition) {
        playerNode.removeAllActions()
        isDragWalking = false

        let localPos = tileMapNode.convert(playerNode.position, from: self)
        let current  = tileMapManager.gridPosition(fromTileMapPoint: localPos) ?? playerGridPos

        guard let path = movement.findPath(from: current, to: destination) else { return }

        playerNode.run(movement.walkAction(along: path, tileMap: tileMapNode) { [weak self] pos in
            self?.playerGridPos = pos
            self?.fogOfWar.reveal(around: pos, radius: 7)
        })
    }

    // MARK: - Drag Movement (tile-by-tile, chained)

    private func stepInDragDirection() {
        guard isDragging, let dir = dragDirection else {
            isDragWalking = false
            return
        }

        // Re-derive grid position from sprite's pixel position so cancellations
        // mid-tile don't leave playerGridPos stale.
        let localPos = tileMapNode.convert(playerNode.position, from: self)
        let current  = tileMapManager.gridPosition(fromTileMapPoint: localPos) ?? playerGridPos
        let next     = dir.neighbor(of: current)

        guard next.col >= 0, next.col < TileMapManager.columns,
              next.row >= 0, next.row < TileMapManager.rows,
              grid[next.col][next.row].isWalkable
        else {
            isDragWalking = false   // hit a wall; touchesMoved will retry if direction changes
            return
        }

        isDragWalking = true

        let dest = tileMapManager.tileCenter(col: next.col, row: next.row)

        // Scale duration by actual distance so the character always moves at
        // a constant speed, even when a direction change interrupts mid-tile.
        let dist     = hypot(dest.x - playerNode.position.x, dest.y - playerNode.position.y)
        let duration = max(Double(dist / TileMapManager.tileSize) / CharacterMovement.defaultSpeed, 0.05)

        playerNode.run(.sequence([
            .move(to: dest, duration: duration),
            .run { [weak self] in
                guard let self else { return }
                self.playerGridPos = next
                self.fogOfWar.reveal(around: next, radius: 7)
                self.isDragWalking = false
                // Chain next step — uses latest dragDirection at tile boundary.
                self.stepInDragDirection()
            },
        ]))
    }

    // MARK: - Per-Frame Update

    override func update(_ currentTime: TimeInterval) {
        let lerp: CGFloat = 0.10
        cameraNode.position.x += (playerNode.position.x - cameraNode.position.x) * lerp
        cameraNode.position.y += (playerNode.position.y - cameraNode.position.y) * lerp
    }
}

// MARK: - Grid Direction

private enum GridDirection {
    case up, down, left, right

    /// Returns the neighbouring grid position one step in this direction.
    func neighbor(of pos: GridPosition) -> GridPosition {
        switch self {
        case .up:    return GridPosition(col: pos.col,     row: pos.row + 1)
        case .down:  return GridPosition(col: pos.col,     row: pos.row - 1)
        case .left:  return GridPosition(col: pos.col - 1, row: pos.row)
        case .right: return GridPosition(col: pos.col + 1, row: pos.row)
        }
    }

    /// Snaps a drag delta to the dominant axis.
    /// Returns nil if the delta hasn't crossed `threshold` yet.
    /// Note: SpriteKit scene Y increases upward, so positive dy = upward swipe.
    static func from(delta: CGPoint, threshold: CGFloat) -> GridDirection? {
        let mag = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        guard mag >= threshold else { return nil }
        if abs(delta.x) >= abs(delta.y) {
            return delta.x > 0 ? .right : .left
        } else {
            return delta.y > 0 ? .up : .down
        }
    }
}

// MARK: - Comparable clamp

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Player Texture

private enum PlayerTexture {
    static func make() -> SKTexture {
        let size = CGSize(width: 16, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let ctx = UIGraphicsGetCurrentContext()!
            // Legs
            UIColor(red: 0.20, green: 0.20, blue: 0.70, alpha: 1).setFill()
            ctx.fill(CGRect(x: 4, y: 14, width: 3, height: 6))
            ctx.fill(CGRect(x: 9, y: 14, width: 3, height: 6))
            // Body
            UIColor(red: 0.25, green: 0.50, blue: 0.90, alpha: 1).setFill()
            ctx.fill(CGRect(x: 3, y: 8, width: 10, height: 7))
            // Head
            UIColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1).setFill()
            ctx.fill(CGRect(x: 4, y: 1, width: 8, height: 8))
            // Eyes
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 6, y: 4, width: 1, height: 1))
            ctx.fill(CGRect(x: 9, y: 4, width: 1, height: 1))
            // Hair
            UIColor(red: 0.45, green: 0.28, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(x: 4, y: 0, width: 8, height: 2))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }
}
