//
//  BiomeModel.swift
//  VillageWorld
//
//  Runtime representation of a discovered biome in the world.
//  Tracks which tiles belong to it, its template data, and
//  the resource overlay nodes placed on those tiles.
//

import SpriteKit

// MARK: - Biome Model

final class BiomeModel: Identifiable {
    let id: UUID
    let template: BiomeTemplate
    let origin: GridPosition          // top-left corner of the biome chunk
    let size: Int                     // side length (square chunk, e.g. 20)
    var tiles: Set<GridPosition>      // all grid positions belonging to this biome
    var resourceNodes: [UUID: SKSpriteNode] = [:]  // resource overlay sprites

    init(
        id: UUID = UUID(),
        template: BiomeTemplate,
        origin: GridPosition,
        size: Int,
        tiles: Set<GridPosition> = []
    ) {
        self.id = id
        self.template = template
        self.origin = origin
        self.size = size
        self.tiles = tiles
    }
}

// MARK: - Placed Resource

struct PlacedResource {
    let biomeResourceName: String
    let rarity: ResourceRarity
    let position: GridPosition
}
