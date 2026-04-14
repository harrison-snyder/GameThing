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

    init(resource: String, amount: Int, biomeHint: String) {
        self.resource = resource
        self.amount = amount
        self.biomeHint = biomeHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resource = try c.decode(String.self, forKey: .resource)
        // LLMs sometimes emit amount as a quoted string rather than a bare int
        if let intVal = try? c.decode(Int.self, forKey: .amount) {
            amount = intVal
        } else if let strVal = try? c.decode(String.self, forKey: .amount),
                  let parsed = Int(strVal) {
            amount = parsed
        } else {
            amount = 1
        }
        biomeHint = (try? c.decode(String.self, forKey: .biomeHint)) ?? "Grass Plains"
    }
}

enum Difficulty: String, Codable, Sendable {
    case easy, medium, hard

    // Accept any capitalisation the LLM produces ("Easy", "MEDIUM", etc.)
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = Difficulty(rawValue: raw) ?? .medium
    }
}

struct GeneratedRequirements: Codable, Sendable {
    let itemName:         String
    let description:      String
    let requirements:     [ResourceRequirement]
    let buildTimeMinutes: Int
    let difficulty:       Difficulty
    let infrastructure:   String?  // required structure (e.g. "Garden Bed", "Animal Pen")

    private enum CodingKeys: String, CodingKey {
        case itemName         = "item_name"
        case description
        case requirements
        case buildTimeMinutes = "build_time_minutes"
        case difficulty
        case infrastructure
    }

    init(itemName: String, description: String, requirements: [ResourceRequirement],
         buildTimeMinutes: Int, difficulty: Difficulty, infrastructure: String? = nil) {
        self.itemName = itemName
        self.description = description
        self.requirements = requirements
        self.buildTimeMinutes = buildTimeMinutes
        self.difficulty = difficulty
        self.infrastructure = infrastructure
    }

    // Lenient decoding: fall back gracefully when individual fields are absent or
    // formatted unexpectedly (common with small on-device models).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemName         = try c.decode(String.self, forKey: .itemName)
        description      = (try? c.decode(String.self, forKey: .description)) ?? ""
        requirements     = (try? c.decode([ResourceRequirement].self, forKey: .requirements)) ?? []
        buildTimeMinutes = (try? c.decode(Int.self, forKey: .buildTimeMinutes)) ?? 10
        let diffStr      = ((try? c.decode(String.self, forKey: .difficulty)) ?? "medium").lowercased()
        difficulty       = Difficulty(rawValue: diffStr) ?? .medium
        infrastructure   = try? c.decode(String.self, forKey: .infrastructure)
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
        itemName:        String,
        role:            CharacterRole,
        knownBiomes:     [String],
        knownResources:  [String],
        knownComponents: [String]
    ) async -> GeneratedRequirements {
        let system = "You are a helpful game design assistant for a village simulation game. " +
                     "You are acting as the village \(role.rawValue). " +
                     "Respond only with the requested JSON."
        let user   = buildPrompt(item: itemName, role: role,
                                  biomes: knownBiomes, resources: knownResources,
                                  components: knownComponents)

        let raw = await llm.generateFull(systemPrompt: system, userPrompt: user,
                                         maxTokens: 512, temperature: 0.3)

        if let data = extractJSON(from: raw),
           let parsed = try? JSONDecoder().decode(GeneratedRequirements.self, from: data) {
            return parsed
        }

        return stubRequirements(for: itemName, role: role)
    }

    private func buildPrompt(item: String, role: CharacterRole,
                              biomes: [String], resources: [String],
                              components: [String] = []) -> String {
        let action: String
        switch role {
        case .researcher: action = "build"
        case .farmer:     action = "grow/raise"
        case .engineer:   action = "craft as a component"
        default:          action = "create"
        }

        let componentLine = components.isEmpty
            ? "No components have been crafted yet."
            : "Known components the engineer can produce: \(components.joined(separator: ", "))"

        return """
        You are a \(role.rawValue) in a small village.
        Available biomes: \(biomes.joined(separator: ", "))
        Currently available resources: \(resources.joined(separator: ", "))
        \(componentLine)

        The player wants to \(action): \(item)

        List the resources realistically needed. You are NOT limited to the currently available \
        resources — invent new resource names if the item genuinely requires them \
        (e.g. "iron", "clay", "fiber", "glass", "leather", "copper", "rubber", "silicon"). \
        Use short, simple lowercase names.

        \(role == .researcher ? """
        For complex technologies, require components (like "battery", "motor", "gear", \
        "circuit", "lens", "spring") that the engineer must craft. Treat components as \
        resources in the requirements list. The more advanced the technology, the more \
        components it should need. Simple technologies can use only raw materials.
        """ : "")
        \(role == .engineer ? """
        This is a component — an intermediate building block used by other technologies. \
        Require only raw materials and simpler components. More complex components should \
        require simpler ones (e.g. a motor needs gears and copper wire; a circuit board \
        needs copper, silicon, and acid). Invent new raw materials freely.
        """ : "")
        \(role == .farmer ? """
        Plants and animals need infrastructure to be placed in. Every crop needs a structure \
        like a "Garden Bed", "Greenhouse", "Planter Box", "Irrigated Field", or "Herb Garden". \
        Every animal needs a structure like an "Animal Pen", "Chicken Coop", "Stable", \
        "Fish Pond", "Beehive", or "Barn". Pick the most appropriate one for this specific \
        plant or animal. Set the "infrastructure" field to the name of the required structure. \
        The infrastructure must be built before the plant can be planted or animal placed.
        """ : "")

        Respond ONLY with valid JSON — no markdown fences:
        {
            "item_name": "...",
            "description": "...",
            "requirements": [
                {"resource": "...", "amount": <int>, "biome_hint": "..."}
            ],\(role == .farmer ? """

            "infrastructure": "...",
        """ : "")
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

    /// Deterministic but item-specific stub so each item has plausible novel requirements.
    private func stubRequirements(for item: String, role: CharacterRole = .researcher) -> GeneratedRequirements {
        if role == .engineer {
            return stubComponentRequirements(for: item)
        }
        if role == .farmer {
            return stubFarmerRequirements(for: item)
        }

        // Hash the item name to pick from a pool of resource sets
        let pools: [[ResourceRequirement]] = [
            [ResourceRequirement(resource: "wood",   amount: 5, biomeHint: "Grass Plains"),
             ResourceRequirement(resource: "stone",  amount: 3, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "iron",   amount: 4, biomeHint: "Mountains"),
             ResourceRequirement(resource: "gear",   amount: 2, biomeHint: "Engineer")],

            [ResourceRequirement(resource: "clay",   amount: 6, biomeHint: "Riverbank"),
             ResourceRequirement(resource: "fiber",  amount: 3, biomeHint: "Grass Plains")],

            [ResourceRequirement(resource: "battery", amount: 2, biomeHint: "Engineer"),
             ResourceRequirement(resource: "copper",  amount: 3, biomeHint: "Mountains"),
             ResourceRequirement(resource: "glass",   amount: 2, biomeHint: "Desert")],

            [ResourceRequirement(resource: "motor",   amount: 1, biomeHint: "Engineer"),
             ResourceRequirement(resource: "iron",    amount: 3, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "circuit", amount: 2, biomeHint: "Engineer"),
             ResourceRequirement(resource: "wire",    amount: 4, biomeHint: "Mountains"),
             ResourceRequirement(resource: "wood",    amount: 2, biomeHint: "Forest")],
        ]

        let difficulties: [Difficulty] = [.easy, .easy, .medium, .medium, .medium, .hard]
        let times = [5, 8, 10, 12, 15, 20]

        let idx = abs(item.hashValue) % pools.count
        return GeneratedRequirements(
            itemName:         item,
            description:      "A \(item) crafted from local village resources.",
            requirements:     pools[idx],
            buildTimeMinutes: times[idx],
            difficulty:       difficulties[idx]
        )
    }

    /// Stub requirements for farmer crops/animals — includes infrastructure.
    private func stubFarmerRequirements(for item: String) -> GeneratedRequirements {
        let animalKeywords = ["cow", "pig", "chicken", "horse", "sheep", "goat", "dog", "cat", "rabbit", "fish", "bee"]
        let isAnimal = animalKeywords.contains(where: { item.lowercased().contains($0) })

        let cropPools: [([ResourceRequirement], String)] = [
            ([ResourceRequirement(resource: "seeds",     amount: 3, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 5, biomeHint: "Riverbank"),
              ResourceRequirement(resource: "compost",   amount: 2, biomeHint: "Forest")], "Garden Bed"),

            ([ResourceRequirement(resource: "seeds",     amount: 2, biomeHint: "Meadow"),
              ResourceRequirement(resource: "fertilizer", amount: 3, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 4, biomeHint: "Riverbank")], "Irrigated Field"),

            ([ResourceRequirement(resource: "seeds",     amount: 4, biomeHint: "Forest"),
              ResourceRequirement(resource: "water",     amount: 3, biomeHint: "Riverbank"),
              ResourceRequirement(resource: "mulch",     amount: 2, biomeHint: "Forest")], "Greenhouse"),

            ([ResourceRequirement(resource: "seeds",     amount: 2, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 2, biomeHint: "Riverbank")], "Herb Garden"),
        ]

        let animalPools: [([ResourceRequirement], String)] = [
            ([ResourceRequirement(resource: "feed",      amount: 5, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 3, biomeHint: "Riverbank"),
              ResourceRequirement(resource: "hay",       amount: 4, biomeHint: "Meadow")], "Animal Pen"),

            ([ResourceRequirement(resource: "grain",     amount: 4, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 2, biomeHint: "Riverbank")], "Chicken Coop"),

            ([ResourceRequirement(resource: "feed",      amount: 6, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "hay",       amount: 5, biomeHint: "Meadow"),
              ResourceRequirement(resource: "water",     amount: 4, biomeHint: "Riverbank")], "Stable"),

            ([ResourceRequirement(resource: "feed",      amount: 3, biomeHint: "Grass Plains"),
              ResourceRequirement(resource: "water",     amount: 6, biomeHint: "Riverbank")], "Fish Pond"),
        ]

        let pools = isAnimal ? animalPools : cropPools
        let idx = abs(item.hashValue) % pools.count
        let (reqs, infra) = pools[idx]
        let difficulties: [Difficulty] = [.easy, .easy, .medium, .medium]
        let times = [5, 8, 10, 12]

        return GeneratedRequirements(
            itemName:         item,
            description:      isAnimal
                ? "A \(item) to raise in the village."
                : "A \(item) to grow in the village.",
            requirements:     reqs,
            buildTimeMinutes: times[idx],
            difficulty:       difficulties[idx],
            infrastructure:   infra
        )
    }

    /// Stub requirements for engineer components — uses only raw materials and simpler components.
    private func stubComponentRequirements(for item: String) -> GeneratedRequirements {
        let pools: [[ResourceRequirement]] = [
            [ResourceRequirement(resource: "iron",   amount: 3, biomeHint: "Mountains"),
             ResourceRequirement(resource: "copper", amount: 2, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "copper", amount: 4, biomeHint: "Mountains"),
             ResourceRequirement(resource: "acid",   amount: 1, biomeHint: "Swamp")],

            [ResourceRequirement(resource: "iron",   amount: 2, biomeHint: "Mountains"),
             ResourceRequirement(resource: "gear",   amount: 1, biomeHint: "Engineer"),
             ResourceRequirement(resource: "copper", amount: 2, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "silicon",  amount: 3, biomeHint: "Desert"),
             ResourceRequirement(resource: "copper",   amount: 2, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "rubber",   amount: 3, biomeHint: "Jungle"),
             ResourceRequirement(resource: "iron",     amount: 2, biomeHint: "Mountains")],

            [ResourceRequirement(resource: "glass",    amount: 2, biomeHint: "Desert"),
             ResourceRequirement(resource: "spring",   amount: 1, biomeHint: "Engineer")],
        ]

        let difficulties: [Difficulty] = [.easy, .easy, .medium, .medium, .medium, .hard]
        let times = [3, 4, 6, 8, 5, 10]

        let idx = abs(item.hashValue) % pools.count
        return GeneratedRequirements(
            itemName:         item,
            description:      "A \(item) component crafted by the village engineer.",
            requirements:     pools[idx],
            buildTimeMinutes: times[idx],
            difficulty:       difficulties[idx]
        )
    }
}
