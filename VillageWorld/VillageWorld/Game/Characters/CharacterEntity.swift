//
//  CharacterEntity.swift
//  VillageWorld
//
//  The data model for every character in the world.
//  GameScene owns all CharacterEntity instances; the state machine
//  drives their behaviour; the LLM (Phase 3) drives their dialogue.
//

import SpriteKit
import UIKit

// MARK: - Supporting Types

enum CharacterRole: String, Codable {
    case researcher
    case farmer
    case worker
    case npc
}

enum CharacterState: Equatable {
    case idle
    case wandering
    case interacting
    case working
}

struct MemoryEntry: Codable {
    let timestamp: Date
    let summary: String        // e.g. "Player told me about solar panels"
    let relatedItemID: UUID?   // links to a tech-tree item when applicable
}

enum TaskType: Codable, Equatable {
    case gather(resource: String, amount: Int)
    case build(techEntryID: UUID)
    case explore(direction: String)
}

enum TaskStatus: Codable, Equatable {
    case queued
    case inProgress
    case complete
    case failed(reason: String)
}

struct GameTask: Identifiable, Codable {
    let id: UUID
    let type: TaskType
    let assignedTo: UUID        // Character ID
    let targetPosition: GridPosition
    let duration: TimeInterval  // game-time seconds
    var progress: Double        // 0.0 to 1.0
    var status: TaskStatus
    let displayName: String     // human-readable task name

    var isComplete: Bool { status == .complete }

    var description: String { displayName }

    init(
        id: UUID = UUID(),
        type: TaskType,
        assignedTo: UUID,
        targetPosition: GridPosition,
        duration: TimeInterval = 10.0,
        progress: Double = 0.0,
        status: TaskStatus = .queued,
        displayName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.assignedTo = assignedTo
        self.targetPosition = targetPosition
        self.duration = duration
        self.progress = progress
        self.status = status
        self.displayName = displayName ?? {
            switch type {
            case .gather(let resource, let amount):
                return "Gather \(amount) \(resource)"
            case .build(let techID):
                return "Build \(techID.uuidString.prefix(8))"
            case .explore(let direction):
                return "Explore \(direction)"
            }
        }()
    }
}

// MARK: - CharacterEntity

final class CharacterEntity: Identifiable {
    let id:          UUID
    let name:        String
    let role:        CharacterRole
    let personality: String           // used as a fragment in LLM system prompts (Phase 3)

    var spriteNode:    SKSpriteNode
    var homePosition:  GridPosition   // wander radius is anchored here
    var gridPosition:  GridPosition   // updated each tile step
    var currentState:  CharacterState = .idle
    var memory:        [MemoryEntry]  = []
    var currentTask:   GameTask?      = nil

    /// Drives idle / wander / interact / work transitions. Wired up by GameScene.
    var stateMachine: CharacterStateMachine?

    init(
        id:           UUID          = UUID(),
        name:         String,
        role:         CharacterRole,
        personality:  String,
        spriteNode:   SKSpriteNode,
        homePosition: GridPosition
    ) {
        self.id          = id
        self.name        = name
        self.role        = role
        self.personality = personality
        self.spriteNode  = spriteNode
        self.homePosition = homePosition
        self.gridPosition = homePosition
    }
}

// MARK: - Sprite Factory

enum CharacterSpriteFactory {

    static func make(role: CharacterRole) -> SKSpriteNode {
        let tex = makeTexture(for: role)
        let sprite = SKSpriteNode(texture: tex, color: .clear,
                                  size: CGSize(width: 28, height: 36))
        sprite.zPosition = 5
        return sprite
    }

    private static func makeTexture(for role: CharacterRole) -> SKTexture {
        let size = CGSize(width: 14, height: 18)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let ctx = UIGraphicsGetCurrentContext()!
            switch role {
            case .researcher: drawResearcher(ctx)
            case .farmer:     drawFarmer(ctx)
            case .worker:     drawWorker(ctx)
            case .npc:        drawNPC(ctx)
            }
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: Role drawings (14×18 canvas, Y=0 at top in CG)

    private static func drawResearcher(_ ctx: CGContext) {
        // Robe — deep purple
        UIColor(red: 0.40, green: 0.15, blue: 0.60, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 8,  width: 10, height: 10))
        // Head — pale
        UIColor(red: 0.93, green: 0.80, blue: 0.68, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 1,  width: 8,  height: 7))
        // Hair — dark
        UIColor(red: 0.20, green: 0.12, blue: 0.05, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 0,  width: 8,  height: 2))
        // Glasses — gold wire
        UIColor(red: 0.80, green: 0.65, blue: 0.10, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 4,  width: 2,  height: 1))
        ctx.fill(CGRect(x: 8, y: 4,  width: 2,  height: 1))
        ctx.fill(CGRect(x: 5, y: 4,  width: 3,  height: 1))
        // Book — brown
        UIColor(red: 0.55, green: 0.28, blue: 0.08, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 9,  width: 3,  height: 4))
    }

    private static func drawFarmer(_ ctx: CGContext) {
        // Overalls — denim blue
        UIColor(red: 0.25, green: 0.40, blue: 0.70, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 8,  width: 10, height: 10))
        // Shirt — green
        UIColor(red: 0.30, green: 0.60, blue: 0.20, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 8,  width: 8,  height: 4))
        // Head — tan
        UIColor(red: 0.90, green: 0.75, blue: 0.60, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 2,  width: 8,  height: 7))
        // Straw hat — yellow
        UIColor(red: 0.90, green: 0.78, blue: 0.20, alpha: 1).setFill()
        ctx.fill(CGRect(x: 1, y: 0,  width: 12, height: 2))
        ctx.fill(CGRect(x: 3, y: 1,  width: 8,  height: 2))
        // Eyes
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 5, y: 5,  width: 1,  height: 1))
        ctx.fill(CGRect(x: 8, y: 5,  width: 1,  height: 1))
    }

    private static func drawWorker(_ ctx: CGContext) {
        // Trousers — dark grey
        UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 12, width: 10, height: 6))
        // Vest — orange
        UIColor(red: 0.95, green: 0.50, blue: 0.10, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 7,  width: 10, height: 6))
        // Head — medium
        UIColor(red: 0.88, green: 0.72, blue: 0.55, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 1,  width: 8,  height: 7))
        // Hard hat — yellow
        UIColor(red: 0.95, green: 0.80, blue: 0.10, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 0,  width: 10, height: 3))
        // Eyes
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 5, y: 4,  width: 1,  height: 1))
        ctx.fill(CGRect(x: 8, y: 4,  width: 1,  height: 1))
        // Tool — grey bar on side
        UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1).setFill()
        ctx.fill(CGRect(x: 11, y: 8, width: 2,  height: 6))
    }

    private static func drawNPC(_ ctx: CGContext) {
        // Tunic — warm grey
        UIColor(red: 0.60, green: 0.57, blue: 0.52, alpha: 1).setFill()
        ctx.fill(CGRect(x: 2, y: 8,  width: 10, height: 10))
        // Head — varied skin
        UIColor(red: 0.92, green: 0.78, blue: 0.62, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 1,  width: 8,  height: 7))
        // Hair — brown
        UIColor(red: 0.45, green: 0.28, blue: 0.10, alpha: 1).setFill()
        ctx.fill(CGRect(x: 3, y: 0,  width: 8,  height: 2))
        // Eyes
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 5, y: 4,  width: 1,  height: 1))
        ctx.fill(CGRect(x: 8, y: 4,  width: 1,  height: 1))
    }
}
