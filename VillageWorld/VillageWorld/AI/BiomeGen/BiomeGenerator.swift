//
//  BiomeGenerator.swift
//  VillageWorld
//
//  Uses the LLM to dream up new biomes when the world needs to
//  expand (Phase 5 trigger conditions).  The JSON response is
//  decoded into a BiomeTemplate that the BiomeRenderer paints.
//
//  In stub mode a pool of hand-crafted biomes is returned so the
//  game loop works end-to-end without a real model.
//

import Foundation

final class BiomeGenerator: Sendable {

    private let llm: LLMService

    init(llm: LLMService) {
        self.llm = llm
    }

    /// Generates a new biome that does not duplicate anything in
    /// `existingBiomes`.  `techLevel` biases difficulty/rarity.
    func generate(
        existingBiomes: [String],
        techLevel:      Int
    ) async -> BiomeTemplate {

        let system = "You are a creative fantasy world-builder."
        let user = """
        Generate a new biome for a fantasy village world.
        Existing biomes: \(existingBiomes.joined(separator: ", "))

        Create something different. Respond ONLY with valid JSON — no markdown fences:
        {
            "name": "...",
            "description": "...",
            "climate": "temperate|arid|tropical|cold|volcanic",
            "primary_color_hex": "#RRGGBB",
            "secondary_color_hex": "#RRGGBB",
            "resources": [
                {"name": "...", "rarity": "common|uncommon|rare", "description": "..."}
            ],
            "wildlife": ["..."],
            "plants": ["..."],
            "terrain_features": ["..."],
            "danger_level": \(min(techLevel + 1, 5))
        }
        """

        let raw = await llm.generateFull(systemPrompt: system, userPrompt: user,
                                          maxTokens: 400, temperature: 0.9)

        if let data = extractJSON(from: raw),
           let parsed = try? JSONDecoder().decode(BiomeTemplate.self, from: data) {
            return parsed
        }

        // Deterministic fallback
        return stubBiome(excluding: existingBiomes)
    }

    // MARK: - JSON extraction

    private func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    // MARK: - Stub pool

    private func stubBiome(excluding existing: [String]) -> BiomeTemplate {
        let candidate = Self.stubPool.first { !existing.contains($0.name) }
        return candidate ?? Self.stubPool[0]
    }

    private static let stubPool: [BiomeTemplate] = [
        BiomeTemplate(
            name: "Whispering Forest",
            description: "Dense ancient woodland where the trees seem to murmur secrets. Rich in timber and herbs.",
            climate: .temperate,
            primaryColorHex: "#2D5A27",
            secondaryColorHex: "#1A3A15",
            resources: [
                BiomeResource(name: "hardwood",   rarity: .common,   description: "Strong timber from ancient oaks"),
                BiomeResource(name: "herbs",      rarity: .common,   description: "Wild medicinal plants"),
                BiomeResource(name: "amber resin", rarity: .uncommon, description: "Golden sap with preserving properties"),
            ],
            wildlife: ["deer", "owl", "fox"],
            plants: ["oak", "fern", "moss"],
            terrainFeatures: ["hollow logs", "mushroom rings", "creek"],
            dangerLevel: 1
        ),
        BiomeTemplate(
            name: "Sunscorch Desert",
            description: "An arid expanse of shifting sands concealing ancient ruins and precious minerals.",
            climate: .arid,
            primaryColorHex: "#C4A35A",
            secondaryColorHex: "#8B6914",
            resources: [
                BiomeResource(name: "sandite crystal", rarity: .uncommon, description: "Heat-forged gemstone"),
                BiomeResource(name: "clay",            rarity: .common,   description: "Sun-baked pottery clay"),
                BiomeResource(name: "obsidian",        rarity: .rare,     description: "Volcanic glass from deep ruins"),
            ],
            wildlife: ["scorpion", "lizard", "vulture"],
            plants: ["cactus", "aloe", "tumbleweed"],
            terrainFeatures: ["sand dunes", "oasis", "buried ruins"],
            dangerLevel: 3
        ),
        BiomeTemplate(
            name: "Crystal Caverns",
            description: "A subterranean network of glowing crystal formations and underground rivers.",
            climate: .cold,
            primaryColorHex: "#3A4F8C",
            secondaryColorHex: "#1F2B52",
            resources: [
                BiomeResource(name: "quartz",       rarity: .common,   description: "Clear crystal for lenses and tools"),
                BiomeResource(name: "iron ore",     rarity: .common,   description: "Raw metal veins in the cave walls"),
                BiomeResource(name: "glowstone",    rarity: .rare,     description: "Luminescent mineral that never dims"),
            ],
            wildlife: ["bat", "cave spider", "blind fish"],
            plants: ["glowing moss", "cave lichen", "crystal bloom"],
            terrainFeatures: ["stalactites", "underground lake", "crystal pillars"],
            dangerLevel: 4
        ),
        BiomeTemplate(
            name: "Ember Peaks",
            description: "Volcanic highlands with geothermal vents, hot springs, and rich mineral deposits.",
            climate: .volcanic,
            primaryColorHex: "#6B2020",
            secondaryColorHex: "#3E1010",
            resources: [
                BiomeResource(name: "sulfite",      rarity: .common,   description: "Yellow mineral from geothermal vents"),
                BiomeResource(name: "basalt",       rarity: .common,   description: "Dense volcanic stone"),
                BiomeResource(name: "fire opal",    rarity: .rare,     description: "A gem that holds warmth"),
            ],
            wildlife: ["salamander", "fire hawk", "lava beetle"],
            plants: ["heat vine", "ash fern", "magma lily"],
            terrainFeatures: ["lava flows", "hot springs", "steam vents"],
            dangerLevel: 5
        ),
    ]
}
