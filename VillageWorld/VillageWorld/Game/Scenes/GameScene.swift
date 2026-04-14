//
//  GameScene.swift
//  VillageWorld
//
//  Main SKScene.  Owns and orchestrates every game system:
//    Phase 1 — tile map, player, fog of war, camera, tap/drag/pinch input
//    Phase 2 — characters, state machines, spawner, interaction manager
//

import SpriteKit
import GameplayKit
import UIKit

final class GameScene: SKScene {

    // MARK: - Callbacks (wired by AppState to avoid import cycles)

    var onCharacterTapped: ((CharacterEntity) -> Void)?
    var onTaskCompleted:   ((GameTask) -> Void)?

    // MARK: - Nodes

    private var tileMapNode: SKTileMapNode!
    private var playerNode:  SKSpriteNode!
    private let cameraNode = SKCameraNode()

    // MARK: - Systems

    private var tileMapManager:     TileMapManager!
    private var fogOfWar:           FogOfWar!
    private var movement:           CharacterMovement!
    private(set) var interactionManager = InteractionManager()
    private var spawner             = CharacterSpawner()
    private let taskQueue           = TaskQueue()

    // MARK: - Grid State

    private var grid: [[TileCell]] = []
    private var playerGridPos = GridPosition(col: WorldGenerator.columns / 2,
                                             row: WorldGenerator.rows    / 2)

    // MARK: - Character Registry

    /// All living character entities (excludes the player).
    private(set) var characters:     [CharacterEntity]       = []
    /// Fast sprite→entity look-up used by tap detection.
    private      var characterNodes: [UUID: SKSpriteNode]    = [:]

    // MARK: - Touch / Drag State

    private var touchOrigin:  CGPoint       = .zero
    private var isDragging:   Bool          = false
    private var dragDirection: GridDirection? = nil
    private var isDragWalking: Bool         = false
    private let dragThreshold: CGFloat      = 18

    // MARK: - Pinch / Zoom

    private var pinchStartScale: CGFloat = 1.0
    private var isPinching: Bool         = false
    private let minCamScale: CGFloat     = 0.5
    private let maxCamScale: CGFloat     = 2.0

    // MARK: - Timing

    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        buildWorld()
        buildPlayer()
        buildCamera()
        placeStarterCharacters()
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
                                  size:    CGSize(width: 28, height: 36))
        playerNode.position  = tileMapManager.tileCenter(col: playerGridPos.col,
                                                          row: playerGridPos.row)
        playerNode.zPosition = 6   // above characters (zPos 5)
        playerNode.name      = "player"
        addChild(playerNode)
    }

    private func buildCamera() {
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = playerNode.position
        let halfW = CGFloat(TileMapManager.columns) * TileMapManager.tileSize / 2
        let halfH = CGFloat(TileMapManager.rows)    * TileMapManager.tileSize / 2
        cameraNode.constraints = [
            SKConstraint.positionX(SKRange(lowerLimit: -halfW, upperLimit: halfW)),
            SKConstraint.positionY(SKRange(lowerLimit: -halfH, upperLimit: halfH)),
        ]
    }

    // MARK: - Starter Characters

    private func placeStarterCharacters() {
        let starters: [(name: String, role: CharacterRole, col: Int, row: Int)] = [
            ("Sage",  .researcher, 32, 34),
            ("Rowan", .farmer,     30, 32),
            ("Stone", .worker,     34, 32),
        ]
        for s in starters {
            let pos    = GridPosition(col: s.col, row: s.row)
            let sprite = CharacterSpriteFactory.make(role: s.role)
            sprite.position = tileMapManager.tileCenter(col: s.col, row: s.row)
            let entity = CharacterEntity(
                name:         s.name,
                role:         s.role,
                personality:  CharacterPersonalities.random(for: s.role),
                spriteNode:   sprite,
                homePosition: pos
            )
            registerCharacter(entity)
        }
    }

    // MARK: - Character Registration

    private func registerCharacter(_ entity: CharacterEntity) {
        entity.spriteNode.name = "character_\(entity.id)"
        addChild(entity.spriteNode)
        characters.append(entity)
        characterNodes[entity.id] = entity.spriteNode

        entity.stateMachine = CharacterStateMachine(
            entity:   entity,
            movement: movement,
            tileMap:  tileMapNode,
            grid:     grid
        )
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
        touchOrigin   = touch.location(in: self)
        isDragging    = false
        dragDirection = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPinching, let touch = touches.first else { return }

        let current = touch.location(in: self)
        let delta   = CGPoint(x: current.x - touchOrigin.x,
                              y: current.y - touchOrigin.y)
        let mag     = hypot(delta.x, delta.y)
        guard mag >= dragThreshold else { return }

        // Slide the D-pad centre: always dragThreshold behind the finger so
        // any direction is reachable with equal effort from anywhere.
        touchOrigin = CGPoint(x: current.x - (delta.x / mag) * dragThreshold,
                              y: current.y - (delta.y / mag) * dragThreshold)

        guard let dir = GridDirection.from(delta: delta, threshold: dragThreshold) else { return }

        if !isDragging {
            isDragging = true
            playerNode.removeAllActions()
            isDragWalking = false
        }

        let changed = dir != dragDirection
        dragDirection = dir

        if changed && isDragWalking {
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
            let locInScene = touch.location(in: self)

            // Character tap takes priority over tile tap.
            if let tapped = characters.first(where: { $0.spriteNode.contains(locInScene) }) {
                onCharacterTapped?(tapped)
            } else {
                let tapInTileMap = touch.location(in: tileMapNode)
                if let dest = tileMapManager.gridPosition(fromTileMapPoint: tapInTileMap),
                   grid[dest.col][dest.row].isWalkable {
                    tapMovePlayer(to: dest)
                }
            }
        }

        isDragging    = false
        dragDirection = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging    = false
        dragDirection = nil
    }

    // MARK: - Tap Movement (A*)

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
            isDragWalking = false; return
        }

        let localPos = tileMapNode.convert(playerNode.position, from: self)
        let current  = tileMapManager.gridPosition(fromTileMapPoint: localPos) ?? playerGridPos
        let next     = dir.neighbor(of: current)

        guard next.col >= 0, next.col < TileMapManager.columns,
              next.row >= 0, next.row < TileMapManager.rows,
              grid[next.col][next.row].isWalkable
        else { isDragWalking = false; return }

        isDragWalking = true
        let dest     = tileMapManager.tileCenter(col: next.col, row: next.row)
        let dist     = hypot(dest.x - playerNode.position.x, dest.y - playerNode.position.y)
        let duration = max(Double(dist / TileMapManager.tileSize) / CharacterMovement.defaultSpeed, 0.05)

        playerNode.run(.sequence([
            .move(to: dest, duration: duration),
            .run { [weak self] in
                guard let self else { return }
                self.playerGridPos = next
                self.fogOfWar.reveal(around: next, radius: 7)
                self.isDragWalking = false
                self.stepInDragDirection()
            },
        ]))
    }

    // MARK: - Per-Frame Update

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 0.1)
        lastUpdateTime = currentTime

        // Tick character state machines
        for char in characters {
            char.stateMachine?.update(deltaTime: dt)
        }

        // Proximity interactions
        interactionManager.update(deltaTime: dt, characters: characters, tileMap: tileMapNode)

        // NPC spawning
        if let newChar = spawner.update(deltaTime: dt,
                                         currentCount: characters.count,
                                         revealedPositions: fogOfWar.revealedPositions,
                                         grid: grid) {
            newChar.spriteNode.position = tileMapManager.tileCenter(
                col: newChar.homePosition.col,
                row: newChar.homePosition.row
            )
            registerCharacter(newChar)
        }

        // Smooth camera follow
        let lerp: CGFloat = 0.10
        cameraNode.position.x += (playerNode.position.x - cameraNode.position.x) * lerp
        cameraNode.position.y += (playerNode.position.y - cameraNode.position.y) * lerp
    }
    // MARK: - Task Assignment (Phase 4)

    func assignTask(_ task: GameTask, to character: CharacterEntity) {
        taskQueue.enqueue(task)

        // Wire completion callback from state machine
        character.stateMachine?.onTaskCompleted = { [weak self] completedTask in
            self?.taskQueue.markComplete(id: completedTask.id)
            DispatchQueue.main.async {
                self?.onTaskCompleted?(completedTask)
            }
        }

        // Clamp target to valid grid bounds
        let clampedTarget = GridPosition(
            col: max(0, min(task.targetPosition.col, TileMapManager.columns - 1)),
            row: max(0, min(task.targetPosition.row, TileMapManager.rows - 1))
        )
        // We need a walkable target; find nearest walkable tile if needed
        let target: GridPosition
        if clampedTarget.col >= 0, clampedTarget.col < TileMapManager.columns,
           clampedTarget.row >= 0, clampedTarget.row < TileMapManager.rows,
           grid[clampedTarget.col][clampedTarget.row].isWalkable {
            target = clampedTarget
        } else {
            target = character.gridPosition  // fallback: work in place
        }

        let finalTask = GameTask(
            id: task.id,
            type: task.type,
            assignedTo: task.assignedTo,
            targetPosition: target,
            duration: task.duration,
            progress: 0,
            status: .inProgress
        )

        character.stateMachine?.enterWorking(task: finalTask)
    }

    // MARK: - Built Item Placement (Phase 4)

    func placeBuiltItem(name: String, near position: GridPosition) {
        // Find a free walkable spot near the target
        let col = max(0, min(position.col, TileMapManager.columns - 1))
        let row = max(0, min(position.row, TileMapManager.rows - 1))

        let center = tileMapManager.tileCenter(col: col, row: row)

        // Build a small pixel-art sprite for the item
        let size = CGSize(width: 24, height: 24)
        let color = UIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        let itemNode = SKSpriteNode(color: color, size: size)
        itemNode.position = center
        itemNode.zPosition = 4  // below characters
        itemNode.name = "builtItem_\(name)"

        // Label
        let label = SKLabelNode(text: name)
        label.fontName = "Courier-Bold"
        label.fontSize = 7
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: size.height * 0.5 + 2)
        itemNode.addChild(label)

        // Pop-in animation
        itemNode.setScale(0)
        addChild(itemNode)
        itemNode.run(.sequence([
            .scale(to: 1.2, duration: 0.2),
            .scale(to: 1.0, duration: 0.1),
        ]))
    }

    // MARK: - Exploration Reveal (Phase 4)

    func revealExploredArea(around position: GridPosition) {
        let col = max(0, min(position.col, TileMapManager.columns - 1))
        let row = max(0, min(position.row, TileMapManager.rows - 1))
        fogOfWar.reveal(around: GridPosition(col: col, row: row), radius: 12)
    }
}

// MARK: - Grid Direction

private enum GridDirection: Equatable {
    case up, down, left, right

    func neighbor(of pos: GridPosition) -> GridPosition {
        switch self {
        case .up:    return GridPosition(col: pos.col,     row: pos.row + 1)
        case .down:  return GridPosition(col: pos.col,     row: pos.row - 1)
        case .left:  return GridPosition(col: pos.col - 1, row: pos.row)
        case .right: return GridPosition(col: pos.col + 1, row: pos.row)
        }
    }

    static func from(delta: CGPoint, threshold: CGFloat) -> GridDirection? {
        guard hypot(delta.x, delta.y) >= threshold else { return nil }
        return abs(delta.x) >= abs(delta.y)
            ? (delta.x > 0 ? .right : .left)
            : (delta.y > 0 ? .up    : .down)
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
        let size = CGSize(width: 14, height: 18)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let ctx = UIGraphicsGetCurrentContext()!
            // Legs
            UIColor(red: 0.18, green: 0.18, blue: 0.65, alpha: 1).setFill()
            ctx.fill(CGRect(x: 3,  y: 13, width: 3, height: 5))
            ctx.fill(CGRect(x: 8,  y: 13, width: 3, height: 5))
            // Body
            UIColor(red: 0.20, green: 0.48, blue: 0.88, alpha: 1).setFill()
            ctx.fill(CGRect(x: 2,  y: 7,  width: 10, height: 7))
            // Head
            UIColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1).setFill()
            ctx.fill(CGRect(x: 3,  y: 1,  width: 8,  height: 7))
            // Eyes
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 5,  y: 4,  width: 1,  height: 1))
            ctx.fill(CGRect(x: 8,  y: 4,  width: 1,  height: 1))
            // Hair
            UIColor(red: 0.42, green: 0.26, blue: 0.08, alpha: 1).setFill()
            ctx.fill(CGRect(x: 3,  y: 0,  width: 8,  height: 2))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }
}
