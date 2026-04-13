//
//  CharacterMovement.swift
//  VillageWorld
//
//  A* pathfinding via GameplayKit's GKGridGraph.
//  Exposes the path as [GridPosition] so callers can build
//  per-tile SKAction sequences with intermediate callbacks.
//

import SpriteKit
import GameplayKit

final class CharacterMovement {

    // MARK: - Constants

    /// Tiles per second while walking.
    static let defaultSpeed: Double = 3.0

    // MARK: - Private

    private var graph: GKGridGraph<GKGridGraphNode>
    private let columns: Int
    private let rows:    Int

    // MARK: - Init

    init(grid: [[TileCell]], columns: Int, rows: Int) {
        self.columns = columns
        self.rows    = rows

        graph = GKGridGraph<GKGridGraphNode>(
            fromGridStartingAt: vector_int2(0, 0),
            width:              Int32(columns),
            height:             Int32(rows),
            diagonalsAllowed:   false,
            nodeClass:          GKGridGraphNode.self
        )

        // Remove obstacle nodes (non-walkable tiles)
        var obstacles: [GKGridGraphNode] = []
        for col in 0..<columns {
            for row in 0..<rows where !grid[col][row].isWalkable {
                if let n = graph.node(atGridPosition: vector_int2(Int32(col), Int32(row))) {
                    obstacles.append(n)
                }
            }
        }
        graph.remove(obstacles)
    }

    // MARK: - Path Finding

    /// Returns the A* path from `start` to `end` as grid positions,
    /// including `start` at index 0.  Returns nil when no path exists.
    func findPath(from start: GridPosition, to end: GridPosition) -> [GridPosition]? {
        guard
            let startNode = graph.node(atGridPosition: vector_int2(Int32(start.col), Int32(start.row))),
            let endNode   = graph.node(atGridPosition: vector_int2(Int32(end.col),   Int32(end.row)))
        else { return nil }

        let raw = startNode.findPath(to: endNode) as! [GKGridGraphNode]
        guard raw.count > 1 else { return nil }

        return raw.map { GridPosition(col: Int($0.gridPosition.x), row: Int($0.gridPosition.y)) }
    }

    // MARK: - Action Builder

    /// Builds a per-tile SKAction sequence for `sprite`.
    /// `onStep` is called (on main thread, via SKAction.run) each time
    /// the sprite arrives at a new tile — use it to update state / reveal fog.
    func walkAction(
        along path: [GridPosition],
        tileMap:    SKTileMapNode,
        speed:      Double = CharacterMovement.defaultSpeed,
        onStep:     ((GridPosition) -> Void)? = nil
    ) -> SKAction {
        let tileDuration = 1.0 / speed
        var sequence: [SKAction] = []

        for pos in path.dropFirst() {          // skip start position
            let dest = tileMap.centerOfTile(atColumn: pos.col, row: pos.row)
            sequence.append(.move(to: dest, duration: tileDuration))
            if let cb = onStep {
                let captured = pos
                sequence.append(.run { cb(captured) })
            }
        }

        return sequence.isEmpty ? .wait(forDuration: 0) : .sequence(sequence)
    }

    // MARK: - Coordinate Conversion

    /// Converts a position in the tile map's local coordinate space to a GridPosition.
    func gridPosition(fromTileMapPoint point: CGPoint, tileMap: SKTileMapNode) -> GridPosition? {
        let col = tileMap.tileColumnIndex(fromPosition: point)
        let row = tileMap.tileRowIndex(fromPosition: point)
        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }
        return GridPosition(col: col, row: row)
    }
}
