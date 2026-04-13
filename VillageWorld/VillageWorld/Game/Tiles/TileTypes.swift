//
//  TileTypes.swift
//  VillageWorld
//

import Foundation

// MARK: - Tile Type

enum TileType: Int, Codable, CaseIterable {
    case grass = 0
    case dirt  = 1
    case water = 2
    case stone = 3
    case sand  = 4
}

// MARK: - Resource Type

enum ResourceType: String, Codable {
    case wood
    case stone
    case food
    case water
}

// MARK: - Tile Cell

struct TileCell: Codable {
    var tileType: TileType
    var biomeID: UUID?
    var isWalkable: Bool
    var resourceType: ResourceType?
    var resourceAmount: Int
    var isDiscovered: Bool

    static func defaultGrass() -> TileCell {
        TileCell(tileType: .grass, biomeID: nil, isWalkable: true,
                 resourceType: nil, resourceAmount: 0, isDiscovered: false)
    }

    static func water() -> TileCell {
        TileCell(tileType: .water, biomeID: nil, isWalkable: false,
                 resourceType: nil, resourceAmount: 0, isDiscovered: false)
    }
}

// MARK: - Grid Position

struct GridPosition: Hashable, Equatable, Codable {
    var col: Int
    var row: Int
}
