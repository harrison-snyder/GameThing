//
//  WorldGenerator.swift
//  VillageWorld
//
//  Generates the initial 128×128 world.
//  Starts as void (dark, unwalkable) and carves a small, smooth
//  starting biome in the centre using overlapping ellipses for
//  an organic but clean boundary.
//

import Foundation

struct WorldGenerator {
    static let columns = 128
    static let rows    = 128

    /// Returns a fully populated grid[col][row].
    static func generate() -> [[TileCell]] {
        // Fill everything with void first
        var grid = Array(
            repeating: Array(repeating: TileCell.defaultGrass(), count: rows),
            count: columns
        )

        // Carve the starting biome
        carveStartingBiome(in: &grid)

        // Place features only inside the starting area
        placeWaterBodies(in: &grid)
        placeStoneOutcrops(in: &grid)
        placeDirtPaths(in: &grid)

        return grid
    }

    // MARK: - Starting Biome

    /// Carves a smooth grass area around the map centre using overlapping
    /// ellipses to create an organic but clean boundary.
    private static func carveStartingBiome(in grid: inout [[TileCell]]) {
        let cx = Double(columns) / 2.0
        let cy = Double(rows) / 2.0

        // Several overlapping ellipses create a smooth blob shape
        let blobs: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
            (cx,       cy,       10.0, 9.0),   // main body
            (cx - 3.0, cy + 2.0, 6.0,  5.0),   // left lobe
            (cx + 4.0, cy - 1.0, 5.0,  6.0),   // right lobe
            (cx + 1.0, cy + 4.0, 4.0,  4.5),   // top bump
            (cx - 1.0, cy - 3.0, 5.0,  4.0),   // bottom bump
        ]

        for c in 0..<columns {
            for r in 0..<rows {
                let x = Double(c)
                let y = Double(r)

                let inside = blobs.contains { blob in
                    let dx = (x - blob.cx) / blob.rx
                    let dy = (y - blob.cy) / blob.ry
                    return (dx * dx + dy * dy) <= 1.0
                }

                if inside {
                    grid[c][r] = TileCell.defaultGrass()
                }
            }
        }
    }

    private static func carveExtraBiomes(in grid: inout [[TileCell]], rng: inout SeededRNG) {
    let biomeCount = 4
    let startCX = columns / 2
    let startCY = rows / 2

    for _ in 0..<biomeCount {
        var col: Int
        var row: Int

        repeat {
            col = Int(rng.next() % UInt64(columns - 12)) + 6
            row = Int(rng.next() % UInt64(rows - 12)) + 6

            let dx = col - startCX
            let dy = row - startCY
            let tooCloseToStart = dx * dx + dy * dy < 18 * 18

            if !tooCloseToStart {
                break
            }
        } while true

        let cx = Double(col)
        let cy = Double(row)

        let blobs: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
            (cx, cy, 6.0 + Double(rng.next() % 5), 6.0 + Double(rng.next() % 5)),
            (cx - 2.0, cy + 1.0, 3.0 + Double(rng.next() % 4), 3.0 + Double(rng.next() % 4)),
            (cx + 2.0, cy - 2.0, 3.0 + Double(rng.next() % 4), 3.0 + Double(rng.next() % 4)),
        ]

        for c in 0..<columns {
            for r in 0..<rows {
                let x = Double(c)
                let y = Double(r)

                let inside = blobs.contains { blob in
                    let dx = (x - blob.cx) / blob.rx
                    let dy = (y - blob.cy) / blob.ry
                    return (dx * dx + dy * dy) <= 1.0
                }

                if inside {
                    grid[c][r] = TileCell.defaultGrass()
                }
            }
        }
    }
}

    // MARK: - Feature Placement

    private static func placeWaterBodies(in grid: inout [[TileCell]]) {
        let cx = columns / 2
        let cy = rows / 2
        let ponds: [(col: Int, row: Int, radius: Int)] = [
            (cx - 6, cy + 4, 2),
            (cx + 5, cy - 3, 2),
        ]
        for pond in ponds {
            for dc in -pond.radius...pond.radius {
                for dr in -pond.radius...pond.radius {
                    let c = pond.col + dc
                    let r = pond.row + dr
                    guard inBounds(c, r) else { continue }
                    guard sqrt(Double(dc * dc + dr * dr)) <= Double(pond.radius) else { continue }
                    guard grid[c][r].tileType == .grass else { continue }
                    grid[c][r] = TileCell(tileType: .water, biomeID: nil, isWalkable: false,
                                          resourceType: nil, resourceAmount: 0, isDiscovered: false)
                }
            }
        }
    }

    private static func placeStoneOutcrops(in grid: inout [[TileCell]]) {
        let cx = columns / 2
        let cy = rows / 2
        let outcrops: [(col: Int, row: Int)] = [
            (cx - 8, cy - 2),
            (cx + 7, cy + 5),
        ]
        var rng = SeededRNG(seed: 42)
        for outcrop in outcrops {
            for dc in -1...1 {
                for dr in -1...1 {
                    let c = outcrop.col + dc
                    let r = outcrop.row + dr
                    guard inBounds(c, r) else { continue }
                    guard grid[c][r].tileType == .grass else { continue }
                    if rng.next() % 2 == 0 {
                        grid[c][r] = TileCell(
                            tileType: .stone, biomeID: nil, isWalkable: false,
                            resourceType: .stone, resourceAmount: Int(rng.next() % 6) + 3,
                            isDiscovered: false
                        )
                    }
                }
            }
        }
    }

    /// Short dirt paths through the centre.
    private static func placeDirtPaths(in grid: inout [[TileCell]]) {
        let cx = columns / 2
        let cy = rows / 2
        let halfPath = 5
        for c in (cx - halfPath)...(cx + halfPath) where inBounds(c, cy) && grid[c][cy].tileType == .grass {
            grid[c][cy].tileType = .dirt
        }
        for r in (cy - halfPath)...(cy + halfPath) where inBounds(cx, r) && grid[cx][r].tileType == .grass {
            grid[cx][r].tileType = .dirt
        }
    }

    // MARK: - Utilities

    private static func inBounds(_ col: Int, _ row: Int) -> Bool {
        col >= 0 && col < columns && row >= 0 && row < rows
    }
}

// MARK: - Seeded RNG (LCG — good enough for world gen)

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
