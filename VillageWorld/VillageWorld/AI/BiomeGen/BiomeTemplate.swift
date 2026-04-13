//
//  BiomeTemplate.swift
//  VillageWorld
//
//  Structured definition of a biome, produced by the BiomeGenerator
//  (via LLM) and consumed by Phase 5's BiomeRenderer to paint tiles.
//

import Foundation

struct BiomeTemplate: Codable, Sendable {

    let name:              String
    let description:       String
    let climate:           BiomeClimate
    let primaryColorHex:   String
    let secondaryColorHex: String
    let resources:         [BiomeResource]
    let wildlife:          [String]
    let plants:            [String]
    let terrainFeatures:   [String]
    let dangerLevel:       Int            // 1-5

    private enum CodingKeys: String, CodingKey {
        case name, description, climate
        case primaryColorHex   = "primary_color_hex"
        case secondaryColorHex = "secondary_color_hex"
        case resources, wildlife, plants
        case terrainFeatures   = "terrain_features"
        case dangerLevel       = "danger_level"
    }
}

enum BiomeClimate: String, Codable, Sendable {
    case temperate
    case arid
    case tropical
    case cold
    case volcanic
}

struct BiomeResource: Codable, Sendable {
    let name:        String
    let rarity:      ResourceRarity
    let description: String
}

enum ResourceRarity: String, Codable, Sendable {
    case common
    case uncommon
    case rare
}
