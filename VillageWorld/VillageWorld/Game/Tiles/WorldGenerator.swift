//
//  WorldGenerator.swift
//  VillageWorld
//
//  Generates the initial 64×64 grass-plains world procedurally.
//  All randomisation uses a seeded source so the same world is always produced.
//

import Foundation

struct WorldGenerator {
    static let columns = 64
    static let rows    = 64

    /// Returns a fully populated grid[col][row].
    static func generate() -> [[TileCell]] {
        var grid = Array(
            repeating: Array(repeating: TileCell.defaultGrass(), count: rows),
            count: columns
        )
        placeWaterBodies(in: &grid)
        placeStoneOutcrops(in: &grid)
        placeDirtPaths(in: &grid)
        return grid
    }

    // MARK: - Private Placement Helpers

    private static func placeWaterBodies(in grid: inout [[TileCell]]) {
        let ponds: [(col: Int, row: Int, radius: Int)] = [
            (15, 20, 3),
            (45, 40, 4),
            (10, 50, 2),
            (55, 15, 3),
            (48, 8,  2),
        ]
        for pond in ponds {
            fillCircle(in: &grid, center: (pond.col, pond.row), radius: pond.radius) { _, _ in
                TileCell(tileType: .water, biomeID: nil, isWalkable: false,
                         resourceType: nil, resourceAmount: 0, isDiscovered: false)
            }
        }
    }

    private static func placeStoneOutcrops(in grid: inout [[TileCell]]) {
        // Fixed positions so the starting area (32,32) is clear
        let outcrops: [(col: Int, row: Int)] = [
            (30, 10), (50, 30), (20, 45), (40, 55), (8, 35)
        ]
        var rng = SeededRNG(seed: 42)
        for outcrop in outcrops {
            for dc in -2...2 {
                for dr in -2...2 {
                    let c = outcrop.col + dc
                    let r = outcrop.row + dr
                    guard inBounds(c, r) else { continue }
                    guard grid[c][r].tileType != .water else { continue }
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

    /// Thin dirt cross through the centre — acts as the starting village path.
    private static func placeDirtPaths(in grid: inout [[TileCell]]) {
        let cx = columns / 2
        let cy = rows / 2
        for c in 0..<columns where grid[c][cy].isWalkable {
            grid[c][cy].tileType = .dirt
        }
        for r in 0..<rows where grid[cx][r].isWalkable {
            grid[cx][r].tileType = .dirt
        }
    }

    // MARK: - Utilities

    private static func fillCircle(
        in grid: inout [[TileCell]],
        center: (col: Int, row: Int),
        radius: Int,
        cell: (Int, Int) -> TileCell
    ) {
        for dc in -radius...radius {
            for dr in -radius...radius {
                let c = center.col + dc
                let r = center.row + dr
                guard inBounds(c, r) else { continue }
                if sqrt(Double(dc * dc + dr * dr)) <= Double(radius) {
                    grid[c][r] = cell(c, r)
                }
            }
        }
    }

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
