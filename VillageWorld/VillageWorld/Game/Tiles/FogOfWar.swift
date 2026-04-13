//
//  FogOfWar.swift
//  VillageWorld
//
//  One dark sprite per tile acts as the fog layer.
//  Sprites share a single texture to keep memory usage low.
//  SpriteKit culls off-screen sprites automatically, so render cost
//  is proportional to the viewport, not the total map size.
//

import SpriteKit

final class FogOfWar {

    // MARK: - Public

    let node: SKNode

    // MARK: - Private

    private var sprites: [[SKSpriteNode?]]
    private var revealed: Set<GridPosition> = []
    private let columns: Int
    private let rows: Int

    // MARK: - Init

    init(columns: Int, rows: Int, tileMap: SKTileMapNode) {
        self.columns = columns
        self.rows    = rows
        self.node    = SKNode()
        self.node.name       = "fogLayer"
        self.node.zPosition  = 10

        // Sparse 2-D array; slots set to nil once the sprite is removed.
        self.sprites = Array(repeating: Array(repeating: nil, count: rows), count: columns)

        let shared = FogOfWar.sharedFogTexture()
        let size   = CGSize(width: TileMapManager.tileSize, height: TileMapManager.tileSize)

        for col in 0..<columns {
            for row in 0..<rows {
                let s = SKSpriteNode(texture: shared, color: .clear, size: size)
                s.position = tileMap.centerOfTile(atColumn: col, row: row)
                s.isUserInteractionEnabled = false
                sprites[col][row] = s
                node.addChild(s)
            }
        }
    }

    // MARK: - API

    /// Reveals all tiles within a circle of `radius` tiles around `centre`.
    /// Already-revealed tiles are skipped.
    func reveal(around centre: GridPosition, radius: Int) {
        for dc in -radius...radius {
            for dr in -radius...radius {
                let c = centre.col + dc
                let r = centre.row + dr
                guard c >= 0, c < columns, r >= 0, r < rows else { continue }
                guard sqrt(Double(dc * dc + dr * dr)) <= Double(radius) else { continue }

                let pos = GridPosition(col: c, row: r)
                guard !revealed.contains(pos) else { continue }
                revealed.insert(pos)

                guard let sprite = sprites[c][r] else { continue }
                sprites[c][r] = nil

                sprite.run(.sequence([
                    .fadeOut(withDuration: 0.35),
                    .removeFromParent()
                ]))
            }
        }
    }

    func isRevealed(_ pos: GridPosition) -> Bool {
        revealed.contains(pos)
    }

    /// Full set of revealed grid positions — used by CharacterSpawner to
    /// find boundary tiles for NPC entry points.
    var revealedPositions: Set<GridPosition> { revealed }

    // MARK: - Texture

    private static func sharedFogTexture() -> SKTexture {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(white: 0.05, alpha: 0.90).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }
}
