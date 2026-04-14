//
//  TechTreeEntry.swift
//  VillageWorld
//
//  Data model for items discovered via Researcher/Farmer interactions.
//  Each entry tracks what the player introduced, its resource requirements,
//  and whether it has been built/grown in the village.
//

import Foundation

// MARK: - Tech Category

enum TechCategory: String, Codable {
    case technology  // from Researcher
    case crop        // from Farmer (plants)
    case animal      // from Farmer (animals)
    case component   // from Engineer (batteries, motors, gears, etc.)
}

// MARK: - Tech Status

enum TechStatus: String, Codable {
    case researched       // discovered, but missing resources
    case requirementsMet  // all resources available
    case built            // constructed / planted in the village
}

// MARK: - Tech Tree Entry

struct TechTreeEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let category: TechCategory
    let requirements: [ResourceRequirement]
    let buildTimeMinutes: Int
    let difficulty: Difficulty
    var status: TechStatus
    let createdBy: UUID  // character who researched it
    let infrastructure: String?  // required structure (e.g. "Garden Bed", "Animal Pen")

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: TechCategory,
        requirements: [ResourceRequirement],
        buildTimeMinutes: Int,
        difficulty: Difficulty,
        status: TechStatus = .researched,
        createdBy: UUID,
        infrastructure: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.requirements = requirements
        self.buildTimeMinutes = buildTimeMinutes
        self.difficulty = difficulty
        self.status = status
        self.createdBy = createdBy
        self.infrastructure = infrastructure
    }
}
