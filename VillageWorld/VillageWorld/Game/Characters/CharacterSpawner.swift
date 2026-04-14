//
//  CharacterSpawner.swift
//  VillageWorld
//
//  Periodically produces a new CharacterEntity at the edge of the
//  player's revealed area.  GameScene calls update(deltaTime:…) each
//  frame; when it returns a non-nil entity, the scene adds it to the world.
//

import SpriteKit

final class CharacterSpawner {

    // MARK: - Config

    private let maxCharacters = 20
    private let spawnIntervalRange: ClosedRange<Double> = 45...90  // seconds

    // MARK: - State

    private var timer:    TimeInterval = 30  // first spawn sooner
    private var interval: TimeInterval = 60

    // MARK: - Update

    /// Returns a ready-to-place CharacterEntity when the spawn timer fires,
    /// or nil otherwise.
    func update(
        deltaTime:         TimeInterval,
        currentCount:      Int,
        revealedPositions: Set<GridPosition>,
        grid:              [[TileCell]]
    ) -> CharacterEntity? {
        guard currentCount < maxCharacters else { return nil }

        timer += deltaTime
        guard timer >= interval else { return nil }
        timer    = 0
        interval = Double.random(in: spawnIntervalRange)

        guard let spawnPos = borderTile(in: revealedPositions, grid: grid) else { return nil }

        let role        = pickRole()
        let name        = CharacterNames.random()
        let personality = CharacterPersonalities.random(for: role)
        let sprite      = CharacterSpriteFactory.make(role: role)

        return CharacterEntity(name: name, role: role, personality: personality,
                               spriteNode: sprite, homePosition: spawnPos)
    }

    // MARK: - Helpers

    private func pickRole() -> CharacterRole {
        Double.random(in: 0...1) < 0.85
            ? .npc
            : [CharacterRole.researcher, .farmer, .worker, .engineer].randomElement()!
    }

    /// Returns a walkable tile at the boundary of the revealed area
    /// (has at least one unrevealed neighbour).
    private func borderTile(in revealed: Set<GridPosition>, grid: [[TileCell]]) -> GridPosition? {
        let boundary = revealed.filter { pos in
            guard grid[pos.col][pos.row].isWalkable else { return false }
            let neighbours = [
                GridPosition(col: pos.col + 1, row: pos.row),
                GridPosition(col: pos.col - 1, row: pos.row),
                GridPosition(col: pos.col,     row: pos.row + 1),
                GridPosition(col: pos.col,     row: pos.row - 1),
            ]
            return neighbours.contains { !revealed.contains($0) }
        }
        return boundary.randomElement()
    }
}

// MARK: - Name List

enum CharacterNames {
    private static let pool: [String] = [
        "Aldric", "Brea", "Cael", "Dara", "Eryn", "Finn", "Gale", "Hana",
        "Ivor",  "Jana", "Kira", "Lorn", "Mira", "Nael", "Oryn", "Peta",
        "Quinn", "Reva", "Sari", "Thorn","Uma",  "Vael", "Wren", "Xara",
        "Yael",  "Zora", "Aedan","Brynn","Cora", "Dwyn", "Elara","Faen",
    ]
    static func random() -> String { pool.randomElement()! }
}

// MARK: - Personality Pool

enum CharacterPersonalities {
    private static let npc: [String] = [
        "curious and talkative",
        "quiet and deeply observant",
        "former sailor who loves stories",
        "slightly grumpy but kind-hearted",
        "endlessly optimistic",
        "superstitious about the weather",
        "loves to barter",
        "philosophical wanderer",
        "skilled artisan, rarely speaks",
        "enthusiastic about food",
    ]
    private static let researcher: [String] = [
        "meticulous and methodical",
        "excitable when a new idea clicks",
        "keeps exhaustive written notes",
        "skeptical of anything unproven",
    ]
    private static let farmer: [String] = [
        "deeply connected to the soil",
        "patient observer of seasons",
        "proud of every harvest",
        "always anxious about the rain",
    ]
    private static let worker: [String] = [
        "practical, no-nonsense mindset",
        "takes fierce pride in craftsmanship",
        "strong and utterly reliable",
        "prefers doing to talking",
    ]
    private static let engineer: [String] = [
        "obsessed with how things fit together",
        "always sketching blueprints in the dirt",
        "measures twice, builds once",
        "dreams of machines that run themselves",
    ]

    static func random(for role: CharacterRole) -> String {
        switch role {
        case .researcher: return researcher.randomElement()!
        case .farmer:     return farmer.randomElement()!
        case .worker:     return worker.randomElement()!
        case .engineer:   return engineer.randomElement()!
        case .npc:        return npc.randomElement()!
        }
    }
}
