//
//  BiomeRenderer.swift
//  VillageWorld
//
//  Phase 5: Takes a BiomeTemplate and renders it into the world.
//  1. Finds an expansion point along the edge of existing territory
//  2. Allocates a smooth elliptical chunk of tiles
//  3. Paints tiles using biome colours
//  4. Fills void gaps — each gap tile is claimed by the nearest biome
//  5. Places resource node sprites based on rarity
//  6. Reveals the fog of war over the new area
//

import SpriteKit
import GameplayKit

final class BiomeRenderer {

    // MARK: - Config

    private let chunkRadius = 8  // radius in tiles for the main ellipse

    // MARK: - Render

    /// Renders a biome into the world and returns the BiomeModel.
    /// Mutates `grid` in-place to update tile metadata.
    func render(
        template: BiomeTemplate,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager,
        fogOfWar: FogOfWar,
        scene: SKScene,
        playerPosition: GridPosition,
        existingBiomes: [BiomeModel]
    ) -> BiomeModel {

        let columns = TileMapManager.columns
        let rows    = TileMapManager.rows

        // 1. Pick expansion centre at the edge of existing territory
        let centre = pickCentre(
            grid: grid,
            columns: columns,
            rows: rows,
            existingBiomes: existingBiomes
        )

        // 2. Compute the smooth set of tiles for this biome
        let biomeTiles = computeBiomeTiles(
            centre: centre,
            columns: columns,
            rows: rows,
            grid: grid
        )

        let chunkSize = chunkRadius * 2
        let origin = GridPosition(
            col: centre.col - chunkRadius,
            row: centre.row - chunkRadius
        )

        let biome = BiomeModel(
            template: template,
            origin: origin,
            size: chunkSize,
            tiles: biomeTiles
        )

        // 3. Paint the new biome's tiles
        paintBiomeTiles(
            tiles: biomeTiles,
            template: template,
            biomeID: biome.id,
            origin: origin,
            chunkSize: chunkSize,
            grid: &grid,
            tileMapManager: tileMapManager
        )

        // 4. Fill void gaps — assign each to the closest biome
        let allBiomes = existingBiomes + [biome]
        fillGaps(
            allBiomes: allBiomes,
            grid: &grid,
            columns: columns,
            rows: rows,
            tileMapManager: tileMapManager
        )

        // 5. Place resource node sprites
        placeResources(biome: biome, template: template,
                       biomeTiles: biomeTiles, tileMapManager: tileMapManager,
                       scene: scene)

        // 6. Reveal fog over the biome area
        fogOfWar.reveal(around: centre, radius: chunkRadius + 3)

        return biome
    }

    // MARK: - Painting

    /// Paints a set of tiles with a biome's colours and updates grid metadata.
    private func paintBiomeTiles(
        tiles: Set<GridPosition>,
        template: BiomeTemplate,
        biomeID: UUID,
        origin: GridPosition,
        chunkSize: Int,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager
    ) {
        let primaryGroup   = tileMapManager.tileGroup(forHex: template.primaryColorHex,
                                                       detailHex: template.secondaryColorHex)
        let secondaryGroup = tileMapManager.tileGroup(forHex: template.secondaryColorHex)

        let noiseSource = GKPerlinNoiseSource(
            frequency: 4.0, octaveCount: 3, persistence: 0.5,
            lacunarity: 2.0, seed: Int32(template.name.hashValue & 0x7FFFFFFF)
        )
        let noise = GKNoise(noiseSource)
        let noiseMap = GKNoiseMap(noise,
                                  size: vector_double2(Double(chunkSize), Double(chunkSize)),
                                  origin: vector_double2(0, 0),
                                  sampleCount: vector_int2(Int32(chunkSize), Int32(chunkSize)),
                                  seamless: false)

        for pos in tiles {
            let localCol = pos.col - origin.col
            let localRow = pos.row - origin.row
            let clampedCol = Int32(max(0, min(localCol, chunkSize - 1)))
            let clampedRow = Int32(max(0, min(localRow, chunkSize - 1)))
            let noiseVal = noiseMap.value(at: vector_int2(clampedCol, clampedRow))

            let group = noiseVal > 0.2 ? secondaryGroup : primaryGroup
            tileMapManager.paintTile(col: pos.col, row: pos.row, group: group)

            grid[pos.col][pos.row].biomeID = biomeID
            grid[pos.col][pos.row].isWalkable = true
            grid[pos.col][pos.row].tileType = .grass
        }
    }

    /// Paints a single tile using a biome's colours. Used for gap-fill tiles.
    private func paintSingleTile(
        pos: GridPosition,
        biome: BiomeModel,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager
    ) {
        let group = tileMapManager.tileGroup(forHex: biome.template.primaryColorHex,
                                              detailHex: biome.template.secondaryColorHex)
        tileMapManager.paintTile(col: pos.col, row: pos.row, group: group)

        grid[pos.col][pos.row].biomeID = biome.id
        grid[pos.col][pos.row].isWalkable = true
        grid[pos.col][pos.row].tileType = .grass
    }

    /// Paints a gap tile as starting-biome grass (no biomeID).
    private func paintStartingGrass(
        pos: GridPosition,
        grid: inout [[TileCell]],
        tileMapManager: TileMapManager
    ) {
        // Use the default grass tile group
        let grassGroup = tileMapManager.tileGroup(forHex: "#5D9E47", detailHex: "#437830")
        tileMapManager.paintTile(col: pos.col, row: pos.row, group: grassGroup)

        grid[pos.col][pos.row].biomeID = nil
        grid[pos.col][pos.row].isWalkable = true
        grid[pos.col][pos.row].tileType = .grass
    }

    // MARK: - Centre Selection

    private func pickCentre(
        grid: [[TileCell]],
        columns: Int,
        rows: Int,
        existingBiomes: [BiomeModel]
    ) -> GridPosition {

        var boundary: [GridPosition] = []
        for c in 0..<columns {
            for r in 0..<rows {
                guard grid[c][r].tileType == .void else { continue }
                if hasNonVoidNeighbour(c: c, r: r, grid: grid, columns: columns, rows: rows) {
                    boundary.append(GridPosition(col: c, row: r))
                }
            }
        }

        guard !boundary.isEmpty else {
            return GridPosition(col: columns / 2, row: rows / 2)
        }

        let existingCentres = existingBiomes.map {
            GridPosition(col: $0.origin.col + $0.size / 2, row: $0.origin.row + $0.size / 2)
        }
        let worldCx = columns / 2
        let worldCy = rows / 2

        var bestScore = -Double.infinity
        var bestCentre = boundary[0]

        let step = max(1, boundary.count / 40)
        for i in Swift.stride(from: 0, to: boundary.count, by: step) {
            let bt = boundary[i]

            let dx = Double(bt.col - worldCx)
            let dy = Double(bt.row - worldCy)
            let mag = max(sqrt(dx * dx + dy * dy), 1.0)
            let pushDist = Double(chunkRadius) * 0.5
            let cx = bt.col + Int((dx / mag) * pushDist)
            let cy = bt.row + Int((dy / mag) * pushDist)

            guard cx - chunkRadius >= 0, cx + chunkRadius < columns,
                  cy - chunkRadius >= 0, cy + chunkRadius < rows else { continue }

            let candidate = GridPosition(col: cx, row: cy)
            let score = scoreCentre(candidate, grid: grid, columns: columns, rows: rows,
                                     existingCentres: existingCentres)
            if score > bestScore {
                bestScore = score
                bestCentre = candidate
            }
        }

        return bestCentre
    }

    private func scoreCentre(
        _ centre: GridPosition,
        grid: [[TileCell]],
        columns: Int,
        rows: Int,
        existingCentres: [GridPosition]
    ) -> Double {
        var voidCount = 0
        var terrainCount = 0
        let r = chunkRadius

        for dc in -r...r {
            for dr in -r...r {
                let c = centre.col + dc
                let rv = centre.row + dr
                guard c >= 0, c < columns, rv >= 0, rv < rows else { continue }
                let dx = Double(dc) / Double(r)
                let dy = Double(dr) / Double(r)
                guard dx * dx + dy * dy <= 1.0 else { continue }

                if grid[c][rv].tileType == .void {
                    voidCount += 1
                } else if grid[c][rv].tileType != .water {
                    terrainCount += 1
                }
            }
        }

        let total = max(Double(voidCount + terrainCount), 1.0)
        let voidRatio = Double(voidCount) / total
        let terrainRatio = Double(terrainCount) / total

        var score = 0.0
        if terrainRatio > 0.05 && terrainRatio < 0.45 {
            score += 12.0
        }
        score += voidRatio * 8.0

        let centre2 = GridPosition(col: centre.col, row: centre.row)
        let minDist = existingCentres.map { manhattanDist(centre2, $0) }.min() ?? 100
        score += Double(minDist) * 0.15

        return score
    }

    private func hasNonVoidNeighbour(c: Int, r: Int, grid: [[TileCell]], columns: Int, rows: Int) -> Bool {
        for (nc, nr) in [(c-1, r), (c+1, r), (c, r-1), (c, r+1)] {
            if nc >= 0 && nc < columns && nr >= 0 && nr < rows && grid[nc][nr].tileType != .void {
                return true
            }
        }
        return false
    }

    private func manhattanDist(_ a: GridPosition, _ b: GridPosition) -> Int {
        abs(a.col - b.col) + abs(a.row - b.row)
    }

    // MARK: - Tile Computation (smooth ellipses)

    private func computeBiomeTiles(
        centre: GridPosition,
        columns: Int,
        rows: Int,
        grid: [[TileCell]]
    ) -> Set<GridPosition> {

        var tiles = Set<GridPosition>()
        let cx = Double(centre.col)
        let cy = Double(centre.row)
        let r  = Double(chunkRadius)

        let seed = abs(centre.col * 73 + centre.row * 37)
        let angle1 = Double(seed % 360) * .pi / 180.0
        let angle2 = angle1 + .pi * 0.6

        let blobs: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
            (cx, cy, r, r * 0.85),
            (cx + cos(angle1) * r * 0.4, cy + sin(angle1) * r * 0.4,
             r * 0.6, r * 0.55),
            (cx + cos(angle2) * r * 0.35, cy + sin(angle2) * r * 0.35,
             r * 0.55, r * 0.6),
        ]

        let scanR = chunkRadius + 2
        for dc in -scanR...scanR {
            for dr in -scanR...scanR {
                let c = centre.col + dc
                let rv = centre.row + dr
                guard c >= 0, c < columns, rv >= 0, rv < rows else { continue }

                let tile = grid[c][rv]
                guard tile.tileType == .void ||
                      (tile.biomeID == nil && tile.tileType != .water) else { continue }
                guard tile.biomeID == nil else { continue }

                let px = Double(c)
                let py = Double(rv)

                let inside = blobs.contains { blob in
                    let dx = (px - blob.cx) / blob.rx
                    let dy = (py - blob.cy) / blob.ry
                    return (dx * dx + dy * dy) <= 1.0
                }

                if inside {
                    tiles.insert(GridPosition(col: c, row: rv))
                }
            }
        }

        return tiles
    }

    // MARK: - Gap Filling

    /// Iteratively fills void tiles that are sandwiched between territory.
    /// Each gap tile is assigned to the closest biome (by distance to that
    /// biome's nearest tile). Starting-area grass (biomeID == nil) is treated
    /// as its own "biome" so gaps between it and a named biome are split fairly.
    private func fillGaps(
        allBiomes: [BiomeModel],
        grid: inout [[TileCell]],
        columns: Int,
        rows: Int,
        tileMapManager: TileMapManager
    ) {
        var changed = true

        while changed {
            changed = false

            // Find void tiles that have terrain on 3+ cardinal sides
            var toFill: [GridPosition] = []
            for c in 0..<columns {
                for r in 0..<rows {
                    guard grid[c][r].tileType == .void else { continue }

                    var terrainCount = 0
                    for (nc, nr) in [(c-1, r), (c+1, r), (c, r-1), (c, r+1)] {
                        if nc >= 0 && nc < columns && nr >= 0 && nr < rows &&
                           grid[nc][nr].tileType != .void {
                            terrainCount += 1
                        }
                    }
                    if terrainCount >= 3 {
                        toFill.append(GridPosition(col: c, row: r))
                    }
                }
            }

            for pos in toFill {
                guard grid[pos.col][pos.row].tileType == .void else { continue }

                // Find the closest biome by checking cardinal neighbours
                var closestBiome: BiomeModel? = nil
                var closestDist = Int.max
                var hasStartingGrassNeighbour = false
                var startingGrassDist = Int.max

                // Check neighbours to find adjacent biome IDs
                for (nc, nr) in [(pos.col-1, pos.row), (pos.col+1, pos.row),
                                 (pos.col, pos.row-1), (pos.col, pos.row+1)] {
                    guard nc >= 0, nc < columns, nr >= 0, nr < rows else { continue }
                    let neighbour = grid[nc][nr]
                    guard neighbour.tileType != .void else { continue }

                    if let bid = neighbour.biomeID {
                        // Named biome — find it and measure distance
                        if let biome = allBiomes.first(where: { $0.id == bid }) {
                            let dist = distanceToBiome(pos, biome: biome)
                            if dist < closestDist {
                                closestDist = dist
                                closestBiome = biome
                            }
                        }
                    } else {
                        // Starting-area grass (no biomeID)
                        hasStartingGrassNeighbour = true
                        startingGrassDist = 1  // direct neighbour
                    }
                }

                // Also measure distance to closest biome tile (not just neighbours)
                // for better accuracy when multiple biomes are nearby
                for biome in allBiomes {
                    let dist = distanceToBiome(pos, biome: biome)
                    if dist < closestDist {
                        closestDist = dist
                        closestBiome = biome
                    }
                }

                // Decide: assign to named biome or starting grass
                if let biome = closestBiome, closestDist <= startingGrassDist {
                    paintSingleTile(pos: pos, biome: biome, grid: &grid,
                                    tileMapManager: tileMapManager)
                    biome.tiles.insert(pos)
                } else if hasStartingGrassNeighbour {
                    paintStartingGrass(pos: pos, grid: &grid,
                                       tileMapManager: tileMapManager)
                } else if let biome = closestBiome {
                    paintSingleTile(pos: pos, biome: biome, grid: &grid,
                                    tileMapManager: tileMapManager)
                    biome.tiles.insert(pos)
                } else {
                    // No adjacent biome found — make it starting grass
                    paintStartingGrass(pos: pos, grid: &grid,
                                       tileMapManager: tileMapManager)
                }

                changed = true
            }
        }
    }

    /// Manhattan distance from a position to the nearest tile in a biome.
    private func distanceToBiome(_ pos: GridPosition, biome: BiomeModel) -> Int {
        // For performance, approximate using distance to biome centre
        let cx = biome.origin.col + biome.size / 2
        let cy = biome.origin.row + biome.size / 2
        return abs(pos.col - cx) + abs(pos.row - cy)
    }

    // MARK: - Resource Placement

    private func placeResources(
        biome: BiomeModel,
        template: BiomeTemplate,
        biomeTiles: Set<GridPosition>,
        tileMapManager: TileMapManager,
        scene: SKScene
    ) {
        let sortedTiles = Array(biomeTiles).sorted { ($0.col, $0.row) < ($1.col, $1.row) }
        var rng = SystemRandomNumberGenerator()

        for biomeResource in template.resources {
            let coverage: Double
            switch biomeResource.rarity {
            case .common:   coverage = 0.12
            case .uncommon: coverage = 0.05
            case .rare:     coverage = 0.02
            }

            let count = max(1, Int(Double(sortedTiles.count) * coverage))
            let selected = sortedTiles.shuffled(using: &rng).prefix(count)

            for pos in selected {
                let center = tileMapManager.tileCenter(col: pos.col, row: pos.row)
                let node = makeResourceSprite(
                    name: biomeResource.name,
                    rarity: biomeResource.rarity
                )
                node.position = CGPoint(
                    x: center.x + CGFloat.random(in: -8...8),
                    y: center.y + CGFloat.random(in: -8...8)
                )
                node.zPosition = 3
                node.name = "biomeResource_\(biomeResource.name)"

                node.setScale(0)
                scene.addChild(node)
                node.run(.sequence([
                    .wait(forDuration: Double.random(in: 0...0.5)),
                    .scale(to: 1.0, duration: 0.3),
                ]))

                biome.resourceNodes[UUID()] = node
            }
        }
    }

    private func makeResourceSprite(name: String, rarity: ResourceRarity) -> SKSpriteNode {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)

        let baseColor: UIColor
        let accentColor: UIColor
        switch rarity {
        case .common:
            baseColor   = UIColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1)
            accentColor = UIColor(red: 0.70, green: 0.60, blue: 0.40, alpha: 1)
        case .uncommon:
            baseColor   = UIColor(red: 0.30, green: 0.55, blue: 0.65, alpha: 1)
            accentColor = UIColor(red: 0.45, green: 0.70, blue: 0.80, alpha: 1)
        case .rare:
            baseColor   = UIColor(red: 0.70, green: 0.50, blue: 0.20, alpha: 1)
            accentColor = UIColor(red: 0.90, green: 0.75, blue: 0.30, alpha: 1)
        }

        let image = renderer.image { _ in
            let ctx = UIGraphicsGetCurrentContext()!
            baseColor.setFill()
            ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 6, height: 6))
            accentColor.setFill()
            ctx.fill(CGRect(x: 2, y: 2, width: 2, height: 2))
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        let sprite = SKSpriteNode(texture: texture, color: .clear,
                                  size: CGSize(width: 16, height: 16))
        return sprite
    }
}
