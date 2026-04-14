//
//  TileMapManager.swift
//  VillageWorld
//
//  Owns the SKTileMapNode and the tile group look-up table.
//  Tile textures are generated procedurally (pixel-art style) until
//  real art assets are shipped in a later phase.
//

import SpriteKit
import UIKit

final class TileMapManager {

    // MARK: - Constants

    static let columns:  Int     = WorldGenerator.columns
    static let rows:     Int     = WorldGenerator.rows
    static let tileSize: CGFloat = 48   // 16-pt pixel art × 3× scale

    // MARK: - Public

    let tileMap: SKTileMapNode
    private var groupsByType: [TileType: SKTileGroup] = [:]

    // MARK: - Init

    init(grid: [[TileCell]]) {
        let (tileSet, groups) = TileMapManager.buildTileSet()
        groupsByType = groups

        tileMap = SKTileMapNode(
            tileSet:  tileSet,
            columns:  TileMapManager.columns,
            rows:     TileMapManager.rows,
            tileSize: CGSize(width: TileMapManager.tileSize, height: TileMapManager.tileSize)
        )
        tileMap.name = "tileMap"
        tileMap.zPosition = 0

        paint(grid: grid)
    }

    // MARK: - Grid ↔ Scene Coordinate Helpers

    func tileCenter(col: Int, row: Int) -> CGPoint {
        tileMap.centerOfTile(atColumn: col, row: row)
    }

    func gridPosition(fromTileMapPoint p: CGPoint) -> GridPosition? {
        let col = tileMap.tileColumnIndex(fromPosition: p)
        let row = tileMap.tileRowIndex(fromPosition: p)
        guard col >= 0, col < TileMapManager.columns,
              row >= 0, row < TileMapManager.rows else { return nil }
        return GridPosition(col: col, row: row)
    }

    // MARK: - Dynamic Biome Painting (Phase 5)

    /// Creates a tile group from an arbitrary hex color and caches it.
    /// Returns the group so it can be applied to tiles.
    func tileGroup(forHex hex: String, detailHex: String? = nil) -> SKTileGroup {
        if let cached = biomeGroups[hex] { return cached }

        let base = UIColor(hex: hex)
        let detail = detailHex.map { UIColor(hex: $0) } ?? base.darkened(by: 0.15)
        let texture = TileMapManager.makeBiomeTexture(base: base, detail: detail)
        let def = SKTileDefinition(texture: texture,
                                   size: CGSize(width: TileMapManager.tileSize,
                                                height: TileMapManager.tileSize))
        let group = SKTileGroup(tileDefinition: def)
        group.name = "biome_\(hex)"
        biomeGroups[hex] = group
        return group
    }

    /// Paints a single tile with a biome color group.
    func paintTile(col: Int, row: Int, group: SKTileGroup) {
        guard col >= 0, col < TileMapManager.columns,
              row >= 0, row < TileMapManager.rows else { return }
        tileMap.setTileGroup(group, forColumn: col, row: row)
    }

    /// Cache for runtime-generated biome tile groups keyed by hex color.
    private var biomeGroups: [String: SKTileGroup] = [:]

    /// Draws a 16×16 pixel-art tile for a biome, with noise-style detail.
    private static func makeBiomeTexture(base: UIColor, detail: UIColor) -> SKTexture {
        let canvas = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))

            // Scattered detail pixels for visual noise
            detail.setFill()
            let positions: [(Int, Int)] = [
                (1, 3), (4, 7), (9, 2), (12, 10), (6, 13),
                (3, 11), (10, 5), (14, 8), (7, 1), (2, 14),
                (11, 12), (5, 6), (13, 3), (8, 9), (0, 7),
            ]
            for (x, y) in positions {
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    // MARK: - Private

    private func paint(grid: [[TileCell]]) {
        for col in 0..<TileMapManager.columns {
            for row in 0..<TileMapManager.rows {
                if let group = groupsByType[grid[col][row].tileType] {
                    tileMap.setTileGroup(group, forColumn: col, row: row)
                }
            }
        }
    }

    // MARK: - Tile Set Factory

    private static func buildTileSet() -> (SKTileSet, [TileType: SKTileGroup]) {
        var groups: [SKTileGroup]          = []
        var byType: [TileType: SKTileGroup] = [:]

        let palette: [(TileType, UIColor)] = [
            (.grass, UIColor(r: 93,  g: 158, b: 71)),
            (.dirt,  UIColor(r: 153, g: 107, b: 61)),
            (.water, UIColor(r: 51,  g: 115, b: 191)),
            (.stone, UIColor(r: 128, g: 128, b: 133)),
            (.sand,  UIColor(r: 209, g: 194, b: 122)),
            (.void,  UIColor(r: 18,  g: 18,  b: 22)),
        ]

        for (type, baseColor) in palette {
            let texture = makeTexture(type: type, base: baseColor)
            let def   = SKTileDefinition(texture: texture,
                                         size: CGSize(width: tileSize, height: tileSize))
            let group = SKTileGroup(tileDefinition: def)
            group.name = "\(type.rawValue)"
            groups.append(group)
            byType[type] = group
        }

        return (SKTileSet(tileGroups: groups), byType)
    }

    /// Draws a 16×16 pixel-art tile texture for each tile type.
    private static func makeTexture(type: TileType, base: UIColor) -> SKTexture {
        let canvas = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: canvas)

        let image = renderer.image { ctx in
            // Base fill
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))

            // Per-type pixel detail
            switch type {
            case .grass:
                let dark = UIColor(r: 67, g: 120, b: 48)
                dark.setFill()
                ctx.fill(CGRect(x: 2, y: 6, width: 1, height: 2))
                ctx.fill(CGRect(x: 7, y: 3, width: 1, height: 2))
                ctx.fill(CGRect(x: 12, y: 9, width: 1, height: 2))
                ctx.fill(CGRect(x: 5, y: 12, width: 1, height: 2))

            case .dirt:
                let dark = UIColor(r: 115, g: 78, b: 40)
                dark.setFill()
                ctx.fill(CGRect(x: 3,  y: 4,  width: 3, height: 1))
                ctx.fill(CGRect(x: 10, y: 8,  width: 4, height: 1))
                ctx.fill(CGRect(x: 5,  y: 12, width: 3, height: 1))

            case .water:
                let light = UIColor(r: 89, g: 155, b: 230, a: 180)
                light.setFill()
                ctx.fill(CGRect(x: 0, y: 4,  width: 16, height: 2))
                ctx.fill(CGRect(x: 0, y: 10, width: 16, height: 2))

            case .stone:
                let dark = UIColor(r: 90, g: 90, b: 94)
                dark.setFill()
                ctx.fill(CGRect(x: 2,  y: 4, width: 5, height: 1))
                ctx.fill(CGRect(x: 9,  y: 8, width: 4, height: 1))
                ctx.fill(CGRect(x: 4,  y: 12, width: 6, height: 1))

            case .sand:
                let dark = UIColor(r: 180, g: 163, b: 90)
                dark.setFill()
                ctx.fill(CGRect(x: 4,  y: 5, width: 2, height: 1))
                ctx.fill(CGRect(x: 11, y: 9, width: 2, height: 1))
                ctx.fill(CGRect(x: 7,  y: 13, width: 2, height: 1))

            case .void:
                // Subtle dark noise — barely visible texture
                let dark = UIColor(r: 12, g: 12, b: 16)
                dark.setFill()
                ctx.fill(CGRect(x: 3,  y: 7, width: 1, height: 1))
                ctx.fill(CGRect(x: 10, y: 3, width: 1, height: 1))
                ctx.fill(CGRect(x: 7,  y: 12, width: 1, height: 1))
            }
        }

        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest   // crisp pixel art — no bilinear blur
        return tex
    }
}

// MARK: - UIColor convenience init (8-bit RGB)

private extension UIColor {
    convenience init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.init(
            red:   CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue:  CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - UIColor hex init & helpers

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1.0
        )
    }

    func darkened(by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(r - factor, 0),
                       green: max(g - factor, 0),
                       blue: max(b - factor, 0),
                       alpha: a)
    }
}
