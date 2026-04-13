//
//  RequirementsGenerator.swift
//  VillageWorld
//
//  After the player describes a technology/crop/animal, this generator
//  asks the LLM to produce a structured JSON blob listing what
//  resources are needed to build or grow it.
//
//  In stub mode the LLM returns valid-looking JSON; a real model
//  does so with actual reasoning about the item.
//

import Foundation

// MARK: - Output types

struct ResourceRequirement: Codable, Sendable {
    let resource: String
    let amount: Int
    let biomeHint: String

    private enum CodingKeys: String, CodingKey {
        case resource
        case amount
        case biomeHint = "biome_hint"
    }
}

enum Difficulty: String, Codable, Sendable {
    case easy, medium, hard
}

struct GeneratedRequirements: Codable, Sendable {
    let itemName:         String
    let description:      String
    let requirements:     [ResourceRequirement]
    let buildTimeMinutes: Int
    let difficulty:       Difficulty

    private enum CodingKeys: String, CodingKey {
        case itemName         = "item_name"
        case description
        case requirements
        case buildTimeMinutes = "build_time_minutes"
        case difficulty
    }
}

// MARK: - Generator

final class RequirementsGenerator: Sendable {

    private let llm: LLMService

    init(llm: LLMService) {
        self.llm = llm
    }

    /// Asks the LLM for resource requirements for `itemName`.
    /// Falls back to a hardcoded stub when JSON parsing fails.
    func generate(
        itemName:       String,
        role:           CharacterRole,
        knownBiomes:    [String],
        knownResources: [String]
    ) async -> GeneratedRequirements {
        let system = "You are a helpful game design assistant."
        let user   = buildPrompt(item: itemName, role: role,
                                  biomes: knownBiomes, resources: knownResources)

        let raw = await llm.generateFull(systemPrompt: system, userPrompt: user,
                                         maxTokens: 300, temperature: 0.3)

        // Try to parse JSON from the response
        if let data = extractJSON(from: raw),
           let parsed = try? JSONDecoder().decode(GeneratedRequirements.self, from: data) {
            return parsed
        }

        // Fallback: deterministic stub so the pipeline never fails
        return stubRequirements(for: itemName)
    }

    // MARK: - Prompt

    private func buildPrompt(item: String, role: CharacterRole,
                              biomes: [String], resources: [String]) -> String {
        """
        You are a \(role.rawValue) in a small village.
        Known biomes: \(biomes.joined(separator: ", "))
        Known resources: \(resources.joined(separator: ", "))

        The player wants to \(role == .researcher ? "build" : "grow/raise"): \(item)

        Respond ONLY with valid JSON — no markdown fences:
        {
            "item_name": "...",
            "description": "...",
            "requirements": [
                {"resource": "...", "amount": <int>, "biome_hint": "..."}
            ],
            "build_time_minutes": <int>,
            "difficulty": "easy|medium|hard"
        }
        """
    }

    // MARK: - JSON extraction

    /// Pulls the first `{…}` block out of a possibly chatty response.
    private func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    // MARK: - Stub fallback

    private func stubRequirements(for item: String) -> GeneratedRequirements {
        GeneratedRequirements(
            itemName:         item,
            description:      "A useful \(item) for the village.",
            requirements: [
                ResourceRequirement(resource: "wood",  amount: 5, biomeHint: "Grass Plains"),
                ResourceRequirement(resource: "stone", amount: 3, biomeHint: "Mountains"),
            ],
            buildTimeMinutes: 10,
            difficulty:       .medium
        )
    }
}
